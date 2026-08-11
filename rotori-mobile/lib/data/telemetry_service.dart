import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'crash_reporter.dart';

const _analyticsEventsTable = 'analytics_events';
const _routeGenerationLogsTable = 'route_generation_logs';
const _outboxPrefix = 'telemetry_outbox_v1:';
const _maxQueuedEvents = 200;

/// Ürün analitiğini kendi Supabase projesine, kullanıcı deneyimini
/// engellemeyen yerel bir outbox üzerinden yollar.
///
/// Sentry yalnız crash/hata içindir. Rota request/response JSON'u hiçbir
/// üçüncü taraf gözlem servisine gönderilmez.
class TelemetryService with WidgetsBindingObserver {
  TelemetryService._();

  static final TelemetryService instance = TelemetryService._();

  final _uuid = const Uuid();
  final String _sessionId = const Uuid().v4();

  SupabaseClient? _client;
  SharedPreferences? _prefs;
  StreamSubscription<AuthState>? _authSubscription;
  List<Map<String, dynamic>> _outbox = [];
  String? _currentUserId;
  bool _flushing = false;
  bool _initialized = false;

  bool get isReady => _initialized && _currentUserId != null;

  Future<void> initialize(SupabaseClient client) async {
    if (_initialized) return;
    _initialized = true;
    _client = client;
    try {
      _prefs = await SharedPreferences.getInstance();
    } on Object {
      // Outbox kalıcı olamazsa canlı gönderim yine denenir.
    }
    WidgetsBinding.instance.addObserver(this);

    await _switchUser(client.auth.currentUser?.id);
    _authSubscription = client.auth.onAuthStateChange.listen(
      (state) => unawaited(_switchUser(state.session?.user.id)),
    );

    if (_currentUserId != null) {
      await track('app_open');
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _authSubscription?.cancel();
    _authSubscription = null;
    _initialized = false;
  }

  Future<void> _switchUser(String? userId) async {
    if (_currentUserId == userId) {
      await CrashReporter.setUser(userId);
      unawaited(flush());
      return;
    }

    _currentUserId = userId;
    _outbox = userId == null ? [] : _loadOutbox(userId);
    await CrashReporter.setUser(userId);
    unawaited(flush());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(track('app_foreground'));
      unawaited(flush());
    } else if (state == AppLifecycleState.paused) {
      unawaited(track('app_background'));
    }
  }

  Future<void> track(
    String eventName, {
    String? screen,
    Map<String, Object?> properties = const {},
  }) async {
    final userId = _currentUserId;
    if (!_initialized || userId == null) return;

    await _enqueue(
      table: _analyticsEventsTable,
      payload: {
        'event_id': _uuid.v4(),
        'user_id': userId,
        'session_id': _sessionId,
        'event_name': eventName,
        if (screen != null) 'screen': screen,
        'properties': properties,
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<String> routeGenerationStarted({
    required Map<String, dynamic> requestJson,
  }) async {
    final attemptId = _uuid.v4();
    await _routeGenerationPhase(
      attemptId: attemptId,
      phase: 'started',
      requestJson: requestJson,
    );
    await CrashReporter.breadcrumb(
      'Route generation started',
      category: 'route_generation',
      data: {
        'attempt_id': attemptId,
        'city_count': (requestJson['cityKeys'] as List?)?.length ?? 0,
      },
    );
    return attemptId;
  }

  Future<void> routeGenerationSucceeded({
    required String attemptId,
    required Map<String, dynamic> requestJson,
    required Map<String, dynamic> routeJson,
    required Map<String, dynamic> metrics,
  }) async {
    await _routeGenerationPhase(
      attemptId: attemptId,
      phase: 'succeeded',
      requestJson: requestJson,
      routeJson: routeJson,
      metrics: metrics,
    );
    await track('route_generation_succeeded', properties: metrics);
    await CrashReporter.breadcrumb(
      'Route generation succeeded',
      category: 'route_generation',
      data: {
        'attempt_id': attemptId,
        'elapsed_ms': metrics['elapsedMs'],
        'day_count': metrics['dayCount'],
      },
    );
  }

  Future<void> routeGenerationFailed({
    required String attemptId,
    required Map<String, dynamic> requestJson,
    required String stage,
    required Object error,
    required StackTrace stackTrace,
    Map<String, dynamic>? routeJson,
    Map<String, dynamic> metrics = const {},
  }) async {
    await _routeGenerationPhase(
      attemptId: attemptId,
      phase: 'failed',
      requestJson: requestJson,
      routeJson: routeJson,
      metrics: metrics,
      errorCode: stage,
    );
    await track(
      'route_generation_failed',
      properties: {'stage': stage, ...metrics},
    );
    await CrashReporter.capture(
      error,
      stackTrace,
      operation: 'route_generation',
      context: {
        'attempt_id': attemptId,
        'stage': stage,
        ...metrics,
      },
    );
  }

  Future<void> _routeGenerationPhase({
    required String attemptId,
    required String phase,
    required Map<String, dynamic> requestJson,
    Map<String, dynamic>? routeJson,
    Map<String, dynamic> metrics = const {},
    String? errorCode,
  }) async {
    final userId = _currentUserId;
    if (!_initialized || userId == null) return;

    await _enqueue(
      table: _routeGenerationLogsTable,
      payload: {
        'event_id': _uuid.v4(),
        'attempt_id': attemptId,
        'user_id': userId,
        'session_id': _sessionId,
        'phase': phase,
        'request_json': requestJson,
        if (routeJson != null) 'route_json': routeJson,
        'metrics': metrics,
        if (errorCode != null) 'error_code': errorCode,
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<void> _enqueue({
    required String table,
    required Map<String, dynamic> payload,
  }) async {
    _outbox.add({'table': table, 'payload': payload});
    _trimOutbox();
    try {
      await _persistOutbox();
    } on Object {
      // Telemetry depolama hatası kullanıcı eylemini engellemez.
    }
    unawaited(flush());
  }

  void _trimOutbox() {
    while (_outbox.length > _maxQueuedEvents) {
      final genericIndex = _outbox.indexWhere(
        (item) => item['table'] == _analyticsEventsTable,
      );
      if (genericIndex < 0) break;
      _outbox.removeAt(genericIndex);
    }
  }

  Future<void> flush() async {
    final client = _client;
    final userId = _currentUserId;
    if (_flushing || client == null || userId == null || _outbox.isEmpty) {
      return;
    }

    _flushing = true;
    try {
      while (_outbox.isNotEmpty && _currentUserId == userId) {
        final item = _outbox.first;
        final table = item['table'] as String;
        final payload = (item['payload'] as Map).cast<String, dynamic>();
        if (payload['user_id'] != userId) break;

        try {
          await client.from(table).upsert(
                payload,
                onConflict: 'event_id',
                ignoreDuplicates: true,
              );
        } on Exception catch (error) {
          if (kDebugMode) {
            debugPrint('Telemetry flush ertelendi: $error');
          }
          break;
        }

        _outbox.removeAt(0);
        await _persistOutbox();
      }
    } finally {
      _flushing = false;
    }
  }

  List<Map<String, dynamic>> _loadOutbox(String userId) {
    final raw = _prefs?.getString('$_outboxPrefix$userId');
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<Object?, Object?>>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
    } on Object {
      return [];
    }
  }

  Future<void> _persistOutbox() async {
    final prefs = _prefs;
    final userId = _currentUserId;
    if (prefs == null || userId == null) return;
    try {
      await prefs.setString('$_outboxPrefix$userId', jsonEncode(_outbox));
    } on Object {
      // Kalıcı outbox yoksa canlı flush yine çalışır.
    }
  }

  Future<void> clearUser(String userId) async {
    try {
      await _prefs?.remove('$_outboxPrefix$userId');
    } on Object {
      // Hesap silme telemetri cache temizliğine bağlı değildir.
    }
    if (_currentUserId == userId) _outbox = [];
  }
}

/// Ekran adlarını genel ürün analitiğine ve crash öncesi breadcrumb zincirine
/// yazar. Route parametreleri/plan kimlikleri loglanmaz.
class TelemetryNavigatorObserver extends NavigatorObserver {
  void _screen(Route<dynamic>? route, String action) {
    final screen = route?.settings.name;
    if (screen == null || screen.isEmpty) return;
    unawaited(
      TelemetryService.instance.track(
        'screen_view',
        screen: screen,
        properties: {'navigationAction': action},
      ),
    );
    unawaited(
      CrashReporter.breadcrumb(
        'Screen changed',
        category: 'navigation',
        data: {'screen': screen, 'action': action},
      ),
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _screen(route, 'push');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _screen(newRoute, 'replace');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _screen(previousRoute, 'pop');
  }
}
