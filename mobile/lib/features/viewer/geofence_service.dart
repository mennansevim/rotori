// apps/viewer/src/hooks/useGeofence.ts'in Dart portu.
// Foreground geofence motoru:
//   - Geolocator konum akışıyla (yalnız uygulama öndeyken) konum okur.
//   - Her tick'te aktif fence'lere dwell saniyesi ekler; minDwell'i geçince
//     complete tetikler (+XP).
//   - Persistans SharedPreferences'ta; tekrar açıldığında rozetler korunur.
//   - Uygulama arka plana geçince akış duraklatılır, öne gelince sürer
//     (React'taki visibilitychange davranışının karşılığı).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/supabase_client.dart';
import '../../data/plans_repository.dart' show sharedPrefsProvider;
import '../../data/user_stats_store.dart';
import '../../data/visit_store.dart';
import '../../domain/city_places.dart';
import '../../domain/geofence.dart';
import '../../domain/types.dart';

/// Konum izni durumu (React: GeofencePermission + iOS deniedForever ayrımı).
enum GeofencePermissionStatus {
  idle,
  requesting,
  granted,
  denied,

  /// Kalıcı red — kullanıcıyı Ayarlar'a yönlendirmek gerekir.
  deniedForever,
  unsupported,
}

/// Tek bir konum örneği — Geolocator `Position`'dan bağımsız, test edilebilir.
class GeoSample {
  const GeoSample({
    required this.lat,
    required this.lng,
    required this.timestamp,
    this.accuracy = 50,
  });

  final double lat;
  final double lng;

  /// Yatay doğruluk (m). React: `pos.coords.accuracy ?? 50`.
  final double accuracy;
  final DateTime timestamp;
}

class _ActiveSession {
  _ActiveSession({required this.startedAt, required this.lastTick});
  final int startedAt; // epoch ms
  int lastTick; // epoch ms
}

/// Saf dwell/oturum motoru — zaman kaynağı örneklerin timestamp'idir,
/// bu sayede testlerde sahte saat enjekte edilebilir.
///
/// React `handlePosition` mantığının birebir portu:
///   - inside = mesafe <= radiusMeters + min(accuracy, 80)
///   - girişte firstSeenAt kaydedilir, tick başına delta saniye eklenir
///     (delta, graceSeconds + 60 ile sınırlanır)
///   - totalDwellSeconds >= minDwellSeconds olunca completedAt set edilir ve
///     onCompleted bir kez tetiklenir
///   - fence dışında graceSeconds'tan uzun kalınırsa oturum silinir
class GeofenceEngine {
  GeofenceEngine({
    required this.fences,
    this.graceSeconds = 120,
    VisitState initial = const VisitState(),
    this.onCompleted,
  }) : visits = initial;

  final List<Geofence> fences;

  /// Geofence dışına çıkınca dwell sayacının sıfırlanmasına kadar verilen
  /// tolerans (sn).
  final int graceSeconds;

  void Function(Geofence fence)? onCompleted;

  VisitState visits;
  final Map<String, _ActiveSession> _sessions = {};

  /// Aktif oturum var mı? (test/inceleme için)
  bool hasSession(String fenceId) => _sessions.containsKey(fenceId);

  /// Bir konum örneğini işler; ziyaret durumu değiştiyse true döner.
  bool handleSample(GeoSample sample) {
    final nowMs = sample.timestamp.millisecondsSinceEpoch;
    final here = LatLng(sample.lat, sample.lng);
    final accuracy = sample.accuracy;

    var next = visits;
    var changed = false;
    final completedNow = <Geofence>[];

    for (final f in fences) {
      if (next.records[f.id]?.completedAt != null) continue;
      final d = distanceMeters(here, LatLng(f.lat, f.lng));
      final inside = d <= f.radiusMeters + math.min(accuracy, 80.0);
      final session = _sessions[f.id];

      if (inside) {
        if (session == null) {
          _sessions[f.id] = _ActiveSession(startedAt: nowMs, lastTick: nowMs);
          next = next.upsert(
            f.id,
            firstSeenAt: next.records[f.id]?.firstSeenAt ?? _iso(nowMs),
          );
          changed = true;
        } else {
          final delta = math.max(0.0, (nowMs - session.lastTick) / 1000.0);
          if (delta > 0) {
            final total = (next.records[f.id]?.totalDwellSeconds ?? 0) +
                math.min(delta, (graceSeconds + 60).toDouble());
            next = next.upsert(f.id, totalDwellSeconds: total);
            changed = true;
            if (total >= f.minDwellSeconds &&
                next.records[f.id]!.completedAt == null) {
              next = next.upsert(f.id, completedAt: _iso(nowMs));
              completedNow.add(f);
            }
          }
          session.lastTick = nowMs;
        }
      } else if (session != null) {
        final sinceLast = (nowMs - session.lastTick) / 1000.0;
        if (sinceLast > graceSeconds) {
          _sessions.remove(f.id);
        }
      }
    }

    visits = next;
    // React'taki queueMicrotask karşılığı: state güncellendikten sonra bildir.
    for (final f in completedNow) {
      onCompleted?.call(f);
    }
    return changed;
  }

  void clearSessions() => _sessions.clear();

  void reset() {
    visits = const VisitState();
    _sessions.clear();
  }

  static String _iso(int epochMs) =>
      DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true)
          .toIso8601String();
}

typedef PositionStreamFactory = Stream<GeoSample> Function();
typedef PermissionRequester = Future<GeofencePermissionStatus> Function();

/// Geolocator akışı + yaşam döngüsü + persistans katmanı.
/// Test için konum akışı ve izin isteği enjekte edilebilir.
class GeofenceController extends ChangeNotifier with WidgetsBindingObserver {
  GeofenceController({
    required List<Geofence> fences,
    required VisitStore visitStore,
    required UserStatsStore statsStore,
    int graceSeconds = 120,
    PositionStreamFactory? positionStreamFactory,
    PermissionRequester? permissionRequester,
  })  : _visitStore = visitStore,
        _statsStore = statsStore,
        _positionStreamFactory =
            positionStreamFactory ?? _defaultPositionStream,
        _permissionRequester = permissionRequester ?? _defaultPermission {
    _engine = GeofenceEngine(
      fences: fences,
      graceSeconds: graceSeconds,
      initial: visitStore.load(),
      onCompleted: _handleCompleted,
    );
    _stats = statsStore.load();
    WidgetsBinding.instance.addObserver(this);
  }

  final VisitStore _visitStore;
  final UserStatsStore _statsStore;
  final PositionStreamFactory _positionStreamFactory;
  final PermissionRequester _permissionRequester;

  late final GeofenceEngine _engine;
  late UserStats _stats;

  StreamSubscription<GeoSample>? _sub;

  /// Uygulama arka plana alınınca takip duraklatıldıysa true (öne gelince sürdür).
  bool _pausedByLifecycle = false;

  GeofencePermissionStatus _status = GeofencePermissionStatus.idle;
  GeoSample? _lastSample;

  /// UI'nın SnackBar göstermesi için keşif bildirimi.
  void Function(Geofence fence)? onDiscovered;

  // --- Okunabilir durum ---
  GeofencePermissionStatus get status => _status;
  VisitState get visits => _engine.visits;
  UserStats get stats => _stats;
  GeoSample? get lastSample => _lastSample;
  List<Geofence> get fences => _engine.fences;
  bool get isTracking => _sub != null || _pausedByLifecycle;

  /// Konum takibini başlat (izin akışı dahil).
  Future<void> start() async {
    if (_status == GeofencePermissionStatus.unsupported) return;
    if (_sub != null) return;
    _status = GeofencePermissionStatus.requesting;
    notifyListeners();

    final result = await _permissionRequester();
    _status = result;
    if (result != GeofencePermissionStatus.granted) {
      notifyListeners();
      return;
    }
    _subscribe();
    notifyListeners();
  }

  /// Takibi durdur; dwell oturumları sıfırlanır (React `stop` ile aynı).
  void stop() {
    _sub?.cancel();
    _sub = null;
    _pausedByLifecycle = false;
    _engine.clearSessions();
    notifyListeners();
  }

  /// Kalıcı izin reddi durumunda kullanıcıyı uygulama ayarlarına götürür.
  Future<void> openSettings() => Geolocator.openAppSettings();

  /// Test/debug: manuel konum simüle et.
  void simulate({required double lat, required double lng, double accuracy = 20}) {
    _onSample(GeoSample(
      lat: lat,
      lng: lng,
      accuracy: accuracy,
      timestamp: DateTime.now(),
    ));
  }

  void _subscribe() {
    _sub = _positionStreamFactory().listen(
      _onSample,
      onError: (Object err) {
        if (err is PermissionDeniedException) {
          _status = GeofencePermissionStatus.denied;
          _sub?.cancel();
          _sub = null;
          notifyListeners();
        }
      },
    );
  }

  void _onSample(GeoSample sample) {
    _lastSample = sample;
    _engine.handleSample(sample);
    // React her tick'te kaydeder; yazma hatası (kota vs.) yutulur.
    unawaited(_visitStore.save(_engine.visits).catchError((_) {}));
    notifyListeners();
  }

  void _handleCompleted(Geofence fence) {
    // Nokta keşfi XP'si (+25) — stats kalıcı olarak güncellenir.
    _stats = _stats.copyWith(xp: _stats.xp + fence.xp);
    unawaited(_statsStore.save(_stats).catchError((_) {}));
    onDiscovered?.call(fence);
  }

  // --- Yaşam döngüsü: arka planda GPS'i duraklat, önde sürdür ---
  // Dwell oturumları korunur; böylece pil tüketimi azalır (React
  // visibilitychange davranışıyla aynı).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (_sub != null) {
          _sub!.cancel();
          _sub = null;
          _pausedByLifecycle = true;
        }
      case AppLifecycleState.resumed:
        if (_pausedByLifecycle) {
          _pausedByLifecycle = false;
          _subscribe();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }

  // --- Varsayılan (gerçek) Geolocator entegrasyonu ---

  static Stream<GeoSample> _defaultPositionStream() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    return Geolocator.getPositionStream(locationSettings: settings).map(
      (pos) => GeoSample(
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        timestamp: pos.timestamp,
      ),
    );
  }

  static Future<GeofencePermissionStatus> _defaultPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return GeofencePermissionStatus.unsupported;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      return switch (perm) {
        LocationPermission.always ||
        LocationPermission.whileInUse =>
          GeofencePermissionStatus.granted,
        LocationPermission.deniedForever =>
          GeofencePermissionStatus.deniedForever,
        _ => GeofencePermissionStatus.denied,
      };
    } catch (_) {
      return GeofencePermissionStatus.unsupported;
    }
  }
}

/// Plana ait keşif controller'ı. SharedPreferences hazır olana kadar null.
final geofenceControllerProvider = ChangeNotifierProvider.autoDispose
    .family<GeofenceController?, Trip>((ref, trip) {
  final prefs = ref.watch(sharedPrefsProvider).valueOrNull;
  if (prefs == null) return null;
  final userId = ref.watch(currentUserProvider)?.id ?? 'anon';
  final fences = cityPlacesToGeofences(detectTripCities(trip));
  return GeofenceController(
    fences: fences,
    visitStore: VisitStore(prefs, userId),
    statsStore: UserStatsStore(prefs, userId),
  );
});
