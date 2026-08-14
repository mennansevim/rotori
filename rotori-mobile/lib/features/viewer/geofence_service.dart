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

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/supabase_client.dart';
import '../../data/plans_repository.dart' show sharedPrefsProvider;
import '../../data/user_stats_store.dart';
import '../../data/visit_store.dart';
import '../../domain/city_places.dart';
import '../../domain/geofence.dart';
import '../../domain/gps_arming_policy.dart';
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

enum GeofenceTrackingMode {
  batterySaver,
  balanced,
  precise,
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
    required Trip trip,
    required List<Geofence> fences,
    required VisitStore visitStore,
    required UserStatsStore statsStore,
    SharedPreferences? prefs,
    String? userId,
    int graceSeconds = 120,
    PositionStreamFactory? positionStreamFactory,
    PermissionRequester? permissionRequester,
    GpsArmingPolicy? armingPolicy,
  })  : _trip = trip,
        _armingPolicy = armingPolicy,
        _visitStore = visitStore,
        _statsStore = statsStore,
      _prefs = prefs,
      _prefsPrefix = userId == null ? null : 'geofence:$userId',
      _positionStreamFactory = positionStreamFactory,
        _permissionRequester = permissionRequester ?? _defaultPermission {
    _engine = GeofenceEngine(
      fences: fences,
      graceSeconds: graceSeconds,
      initial: visitStore.load(),
      onCompleted: _handleCompleted,
    );
    _stats = statsStore.load();
    _loadTrackingPrefs();
    WidgetsBinding.instance.addObserver(this);
  }

  final Trip _trip;
  final VisitStore _visitStore;
  final UserStatsStore _statsStore;
  final SharedPreferences? _prefs;
  final String? _prefsPrefix;
  final PositionStreamFactory? _positionStreamFactory;
  final PermissionRequester _permissionRequester;

  /// Verilirse GPS kademesi plandan **türetilir** (zaman + mesafe kapısı).
  /// `null` iken davranış v2 ile birebir aynı kalır: kullanıcı modu elle seçer
  /// ve akış gezi penceresi boyunca açık kalır.
  final GpsArmingPolicy? _armingPolicy;

  GpsArmingDecision? _lastArmingDecision;

  /// iOS 14+ / Android 12+ doğruluk yetkisi. Varsayılan `precise`; gerçek
  /// değer izin akışında okunur.
  LocationAccuracyAuthorization _accuracyAuthorization =
      LocationAccuracyAuthorization.precise;

  late final GeofenceEngine _engine;
  late UserStats _stats;

  StreamSubscription<GeoSample>? _sub;

  /// Uygulama arka plana alınınca takip duraklatıldıysa true (öne gelince sürdür).
  bool _pausedByLifecycle = false;

  GeofencePermissionStatus _status = GeofencePermissionStatus.idle;
  GeoSample? _lastSample;
  GeofenceTrackingMode _trackingMode = GeofenceTrackingMode.batterySaver;
  bool _smartTrackingEnabled = true;

  /// UI'nın SnackBar göstermesi için keşif bildirimi.
  void Function(Geofence fence)? onDiscovered;

  /// Bir keşif sonucu yeni rozet(ler) kazanıldığında tetiklenir.
  void Function(List<BadgeDefinition> newly)? onBadgesEarned;

  // --- Okunabilir durum ---
  GeofencePermissionStatus get status => _status;
  VisitState get visits => _engine.visits;
  UserStats get stats => _stats;
  GeoSample? get lastSample => _lastSample;
  List<Geofence> get fences => _engine.fences;
  bool get isTracking => _sub != null || _pausedByLifecycle;
  GeofenceTrackingMode get trackingMode => _trackingMode;
  bool get smartTrackingEnabled => _smartTrackingEnabled;
  bool get isInTripWindow => _isWithinTripWindow(DateTime.now());

  /// Politika etkinken son verilen karar — UI'daki dürüst durum çipi için.
  GpsArmingDecision? get armingDecision => _lastArmingDecision;

  bool get isArmingPolicyEnabled => _armingPolicy != null;

  /// Kullanıcı "Yaklaşık Konum" verdiyse `reduced`.
  LocationAccuracyAuthorization get accuracyAuthorization =>
      _accuracyAuthorization;

  /// Damga anı için Apple'ın **geçici** tam doğruluk iznini ister.
  ///
  /// Yalnız kullanıcı fiilen bir keşif noktasının yakınındayken çağrılmalı
  /// (`armingDecision.needsTemporaryFullAccuracy`). Erken sormak hem kabul
  /// oranını düşürür hem App Store incelemesinde gereksiz sürtünme yaratır.
  Future<bool> requestPreciseAccuracyForDiscovery() async {
    try {
      final status = await Geolocator.requestTemporaryFullAccuracy(
        purposeKey: 'DiscoveryStamp',
      );
      _accuracyAuthorization = status == LocationAccuracyStatus.reduced
          ? LocationAccuracyAuthorization.reduced
          : LocationAccuracyAuthorization.precise;
      notifyListeners();
      return _accuracyAuthorization == LocationAccuracyAuthorization.precise;
    } catch (_) {
      // iOS 13 ve altı / Android: API yok sayılır, mevcut yetki korunur.
      return _accuracyAuthorization == LocationAccuracyAuthorization.precise;
    }
  }

  Future<void> _refreshAccuracyAuthorization() async {
    try {
      final status = await Geolocator.getLocationAccuracy();
      _accuracyAuthorization = status == LocationAccuracyStatus.reduced
          ? LocationAccuracyAuthorization.reduced
          : LocationAccuracyAuthorization.precise;
    } catch (_) {
      _accuracyAuthorization = LocationAccuracyAuthorization.precise;
    }
  }

  /// Akışta fiilen kullanılacak mod. Politika etkinken kademeden türer;
  /// değilse kullanıcının seçtiği mod geçerlidir.
  GeofenceTrackingMode get effectiveTrackingMode {
    final decision = _lastArmingDecision;
    if (_armingPolicy == null || decision == null) return _trackingMode;
    return switch (decision.tier) {
      GpsArmingTier.precise => GeofenceTrackingMode.precise,
      GpsArmingTier.balanced => GeofenceTrackingMode.balanced,
      GpsArmingTier.oneShot => GeofenceTrackingMode.batterySaver,
      GpsArmingTier.off => GeofenceTrackingMode.batterySaver,
    };
  }

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
    // İzin alındıktan sonra doğruluk yetkisi netleşir (kullanıcı "Yaklaşık
    // Konum" seçmiş olabilir); politika buna göre karar verir.
    await _refreshAccuracyAuthorization();
    if (!_shouldTrackNow()) {
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

  Future<void> setTrackingMode(GeofenceTrackingMode mode) async {
    if (_trackingMode == mode) return;
    _trackingMode = mode;
    _saveTrackingPrefs();

    final shouldResubscribe = _sub != null;
    if (shouldResubscribe) {
      await _sub?.cancel();
      _sub = null;
      if (_status == GeofencePermissionStatus.granted && _shouldTrackNow()) {
        _subscribe();
      }
    }
    notifyListeners();
  }

  Future<void> setSmartTrackingEnabled(bool enabled) async {
    if (_smartTrackingEnabled == enabled) return;
    _smartTrackingEnabled = enabled;
    _saveTrackingPrefs();
    if (!enabled) {
      stop();
      return;
    }
    if (_isWithinTripWindow(DateTime.now())) {
      await start();
      return;
    }
    if (_sub != null) stop();
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

  /// Simülasyon/test için tek bir hazır [GeoSample]'ı motora iletir.
  /// Yalnızca GPS simülatörü ve entegrasyon testlerinde kullanılır — gerçek
  /// konum akışı [start] üzerinden gelir.
  void debugPushSample(GeoSample s) => _onSample(s);

  void _subscribe() {
    final streamFactory = _positionStreamFactory ?? _defaultPositionStream;
    _sub = streamFactory().listen(
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
    // Nokta keşfi: +XP ekle ve keşfi kaydet (id + şehir sayacı, idempotent).
    _stats = _stats.withDiscovery(fence.id, fence.city).copyWith(
          xp: _stats.xp + fence.xp,
        );
    // Yeni açılan rozetleri değerlendir (GPS keşif + plan tabanlı hepsi).
    final res = evaluateBadges(_trip, _stats);
    _stats = _stats.copyWith(badgesEarned: res.allEarnedIds);
    unawaited(_statsStore.save(_stats).catchError((_) {}));
    onDiscovered?.call(fence);
    if (res.newly.isNotEmpty) {
      onBadgesEarned?.call(res.newly);
    }
    notifyListeners();
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
        if (_pausedByLifecycle && _shouldTrackNow()) {
          _pausedByLifecycle = false;
          _subscribe();
        } else if (_pausedByLifecycle) {
          _pausedByLifecycle = false;
        }
        if (_smartTrackingEnabled && !_isWithinTripWindow(DateTime.now())) {
          stop();
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

  Stream<GeoSample> _defaultPositionStream() {
    final settings = _locationSettingsForMode(_trackingMode);
    return Geolocator.getPositionStream(locationSettings: settings).map(
      (pos) => GeoSample(
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        timestamp: pos.timestamp,
      ),
    );
  }

  LocationSettings _locationSettingsForMode(GeofenceTrackingMode mode) {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      return AppleSettings(
        accuracy: switch (mode) {
          GeofenceTrackingMode.batterySaver => LocationAccuracy.low,
          GeofenceTrackingMode.balanced => LocationAccuracy.medium,
          GeofenceTrackingMode.precise => LocationAccuracy.bestForNavigation,
        },
        distanceFilter: switch (mode) {
          GeofenceTrackingMode.batterySaver => 60,
          GeofenceTrackingMode.balanced => 25,
          GeofenceTrackingMode.precise => 10,
        },
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: false,
      );
    }

    return LocationSettings(
      accuracy: switch (mode) {
        GeofenceTrackingMode.batterySaver => LocationAccuracy.low,
        GeofenceTrackingMode.balanced => LocationAccuracy.medium,
        GeofenceTrackingMode.precise => LocationAccuracy.best,
      },
      distanceFilter: switch (mode) {
        GeofenceTrackingMode.batterySaver => 80,
        GeofenceTrackingMode.balanced => 30,
        GeofenceTrackingMode.precise => 12,
      },
    );
  }

  bool _shouldTrackNow() {
    final policy = _armingPolicy;
    if (policy != null) {
      // Politika etkinken kullanıcı "akıllı takip"i kapatarak sürekli akışa
      // dönebilir; aksi halde kademe kararı belirler.
      if (!_smartTrackingEnabled) return true;
      return _evaluateArming(policy).isStreaming;
    }
    if (!_smartTrackingEnabled) return true;
    return _isWithinTripWindow(DateTime.now());
  }

  /// Kademeyi yeniden değerlendirir ve sonucu saklar.
  GpsArmingDecision _evaluateArming(GpsArmingPolicy policy) {
    final now = DateTime.now();
    final decision = policy.evaluate(
      now: now,
      isWithinTripWindow: _isWithinTripWindow(now),
      hasPermission: _status == GeofencePermissionStatus.granted,
      targets: _armingTargets(now),
      lastFix: _lastSample == null
          ? null
          : GeoFix(
              lat: _lastSample!.lat,
              lng: _lastSample!.lng,
              timestamp: _lastSample!.timestamp,
              accuracyMeters: _lastSample!.accuracy,
            ),
      accuracy: _accuracyAuthorization,
    );
    _lastArmingDecision = decision;
    return decision;
  }

  /// Keşif noktalarını politika hedefine çevirir.
  ///
  /// Planlı saat, o günün timeline satırlarından **koordinat yakınlığıyla**
  /// eşleştirilir: fence ile satır ~300 m içindeyse satırın saati zaman kapısı
  /// olur. Eşleşme yoksa `scheduledAt` null kalır — saati bilinmeyen bir
  /// hedefi saat yüzünden ıskalamak istemeyiz.
  List<GpsTarget> _armingTargets(DateTime now) {
    final today = _todayPlan(now);
    final scheduled = <({double lat, double lng, DateTime at})>[];
    if (today != null) {
      for (final item in today.items) {
        final lat = item.lat, lng = item.lng;
        final hhmm = item.scheduledTime ?? item.time;
        if (lat == null || lng == null || hhmm == null) continue;
        final parts = hhmm.split(':');
        if (parts.length < 2) continue;
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour == null || minute == null) continue;
        scheduled.add((
          lat: lat,
          lng: lng,
          at: DateTime(now.year, now.month, now.day, hour, minute),
        ));
      }
    }

    final visits = _engine.visits.records;
    return [
      for (final fence in _engine.fences)
        GpsTarget(
          id: fence.id,
          lat: fence.lat,
          lng: fence.lng,
          radiusMeters: fence.radiusMeters,
          scheduledAt: _scheduleFor(fence, scheduled),
          isDiscovered: visits[fence.id]?.completedAt != null,
        ),
    ];
  }

  DateTime? _scheduleFor(
    Geofence fence,
    List<({double lat, double lng, DateTime at})> scheduled,
  ) {
    DateTime? best;
    var bestMeters = double.infinity;
    for (final row in scheduled) {
      final meters = distanceMeters(
        LatLng(fence.lat, fence.lng),
        LatLng(row.lat, row.lng),
      );
      if (meters <= 300 && meters < bestMeters) {
        bestMeters = meters;
        best = row.at;
      }
    }
    return best;
  }

  DayPlan? _todayPlan(DateTime now) {
    final iso = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    for (final day in _trip.days) {
      if (day.date == iso) return day;
    }
    return null;
  }

  bool _isWithinTripWindow(DateTime now) {
    final tripStart = DateTime.tryParse(_trip.tripStart);
    final tripEnd = DateTime.tryParse(_trip.tripEnd);
    if (tripStart == null || tripEnd == null) return true;

    final startBuffer = DateTime(
      tripStart.year,
      tripStart.month,
      tripStart.day,
    ).subtract(const Duration(days: 1));
    final endBuffer = DateTime(
      tripEnd.year,
      tripEnd.month,
      tripEnd.day,
      23,
      59,
      59,
    ).add(const Duration(days: 1));
    return !now.isBefore(startBuffer) && !now.isAfter(endBuffer);
  }

  void _loadTrackingPrefs() {
    if (_prefs == null || _prefsPrefix == null) return;
    final modeRaw = _prefs.getString('$_prefsPrefix:mode');
    final smart = _prefs.getBool('$_prefsPrefix:smart');

    _trackingMode = switch (modeRaw) {
      'battery' => GeofenceTrackingMode.batterySaver,
      'precise' => GeofenceTrackingMode.precise,
      _ => GeofenceTrackingMode.batterySaver,
    };
    if (smart != null) {
      _smartTrackingEnabled = smart;
    }
  }

  void _saveTrackingPrefs() {
    if (_prefs == null || _prefsPrefix == null) return;
    final modeRaw = switch (_trackingMode) {
      GeofenceTrackingMode.batterySaver => 'battery',
      GeofenceTrackingMode.balanced => 'balanced',
      GeofenceTrackingMode.precise => 'precise',
    };
    _prefs
      ..setString('$_prefsPrefix:mode', modeRaw)
      ..setBool('$_prefsPrefix:smart', _smartTrackingEnabled);
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
    trip: trip,
    fences: fences,
    visitStore: VisitStore(prefs, userId),
    statsStore: UserStatsStore(prefs, userId),
    prefs: prefs,
    userId: userId,
  );
});
