// GPS keşif → rozet onay akışının uçtan uca testleri.
//
// GeofenceController, enjekte edilen mock store'lar + granted izin ile kurulur.
// Gerçek konum akışı yerine controller.debugPushSample ile hazırlanmış
// (sahte saatli) GeoSample'lar itilir; böylece dwell tamamlanması → +XP →
// keşif kaydı → rozet değerlendirmesi zinciri deterministik test edilir.

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/data/user_stats_store.dart';
import 'package:rotori/data/visit_store.dart';
import 'package:rotori/domain/city_places.dart';
import 'package:rotori/domain/geofence.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/viewer/geofence_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- Test yardımcıları ---------------------------------------------------

Trip _tokyoKyotoTrip() => Trip(
      id: 't1',
      slug: 't1',
      title: 'Japonya',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-10-01',
      tripEnd: '2026-10-10',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-10-01', end: '2026-10-10'),
        pace: Pace.moderate,
      ),
      days: [
        DayPlan(dayNumber: 1, date: '2026-10-01', theme: 'Tokyo · Asakusa'),
        DayPlan(dayNumber: 2, date: '2026-10-02', theme: 'Kyoto tapınakları'),
      ],
    );

Future<GeofenceController> _buildController(Trip trip) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final fences = cityPlacesToGeofences(detectTripCities(trip));
  return GeofenceController(
    trip: trip,
    fences: fences,
    visitStore: VisitStore(prefs, 'test'),
    statsStore: UserStatsStore(prefs, 'test'),
    positionStreamFactory: () => const Stream<GeoSample>.empty(),
    permissionRequester: () async => GeofencePermissionStatus.granted,
  );
}

DateTime _t(int epochSec) =>
    DateTime.fromMillisecondsSinceEpoch(epochSec * 1000, isUtc: true);

/// [fence]'i tamamlar: merkezinde 120 sn aralıklı örnekler iterek dwell'i
/// minDwellSeconds'ın üzerine çıkarır. (Tek büyük sıçrama delta cap'ine —
/// graceSeconds + 60 — takılacağından kademeli tick gerekir.)
/// Dönen değer: bir sonraki durak için serbest başlangıç epoch'u.
int _completeFence(GeofenceController c, Geofence f, int startSec) {
  var t = startSec;
  // İlk örnek oturumu açar (dwell eklemez).
  c.debugPushSample(
      GeoSample(lat: f.lat, lng: f.lng, accuracy: 10, timestamp: _t(t)));
  while (c.visits.records[f.id]?.completedAt == null) {
    t += 120;
    c.debugPushSample(
        GeoSample(lat: f.lat, lng: f.lng, accuracy: 10, timestamp: _t(t)));
  }
  return t + 300; // sonraki durağa "yolculuk" payı
}

Geofence _byId(List<Geofence> fences, String id) =>
    fences.firstWhere((f) => f.id == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GeofenceController: keşif → XP + rozet (uçtan uca)', () {
    test('tek Tokyo noktasında dwell → tamamlanır, +25 XP, first-discovery',
        () async {
      final trip = _tokyoKyotoTrip();
      final c = await _buildController(trip);
      final skytree = _byId(c.fences, 'tk-skytree');

      _completeFence(c, skytree, 0);

      final rec = c.visits.records['tk-skytree'];
      expect(rec?.completedAt, isNotNull);
      expect(c.stats.xp, 25);
      expect(c.stats.discoveredPlaceIds, contains('tk-skytree'));
      expect(c.stats.discoveredCityCounts['tokyo'], 1);
      expect(c.stats.badgesEarned, contains('first-discovery'));
    });

    test('5 farklı nokta → explorer-5 kazanılır', () async {
      final trip = _tokyoKyotoTrip();
      final c = await _buildController(trip);
      const ids = [
        'tk-skytree',
        'tk-sensoji',
        'tk-shibuya',
        'tk-meiji',
        'tk-teamlab',
      ];
      var t = 0;
      for (final id in ids) {
        t = _completeFence(c, _byId(c.fences, id), t);
      }

      expect(c.stats.discoveredPlaceIds.length, 5);
      expect(c.stats.xp, 25 * 5);
      expect(c.stats.badgesEarned, contains('explorer-5'));
      expect(c.stats.badgesEarned, contains('first-discovery'));
    });

    test('3 Tokyo noktası → tokyo-roamer kazanılır', () async {
      final trip = _tokyoKyotoTrip();
      final c = await _buildController(trip);
      var t = 0;
      for (final id in ['tk-skytree', 'tk-sensoji', 'tk-shibuya']) {
        t = _completeFence(c, _byId(c.fences, id), t);
      }
      expect(c.stats.discoveredCityCounts['tokyo'], 3);
      expect(c.stats.badgesEarned, contains('tokyo-roamer'));
    });

    test('onBadgesEarned callback yeni rozetlerle tetiklenir', () async {
      final trip = _tokyoKyotoTrip();
      final c = await _buildController(trip);
      final earned = <String>[];
      c.onBadgesEarned = (newly) => earned.addAll(newly.map((b) => b.id));

      _completeFence(c, _byId(c.fences, 'tk-skytree'), 0);
      expect(earned, contains('first-discovery'));
    });

    test('grace: dwell öncesi çıkıp grace içinde dönünce yine tamamlanır',
        () async {
      final trip = _tokyoKyotoTrip();
      final c = await _buildController(trip);
      final f = _byId(c.fences, 'tk-skytree');

      // t=0 giriş, ardından 120 sn aralıklı tick'lerle 480 sn dwell birik.
      for (final t in [0, 120, 240, 360, 480]) {
        c.debugPushSample(
            GeoSample(lat: f.lat, lng: f.lng, accuracy: 10, timestamp: _t(t)));
      }
      expect(c.visits.records['tk-skytree']?.totalDwellSeconds, 480);
      expect(c.visits.records['tk-skytree']?.completedAt, isNull);

      // t=560 dwell tamamlanmadan dışarı çık (son tick'ten 80 sn, grace içinde
      // → oturum korunur; lastTick 480'de kalır).
      c.debugPushSample(
          GeoSample(lat: 36.5, lng: 139.0, accuracy: 10, timestamp: _t(560)));
      expect(c.visits.records['tk-skytree']?.completedAt, isNull);

      // t=620 grace içinde geri dön → delta 620-480=140 eklenir → 620 >= 600
      // → tamamlanır.
      c.debugPushSample(
          GeoSample(lat: f.lat, lng: f.lng, accuracy: 10, timestamp: _t(620)));

      expect(c.visits.records['tk-skytree']?.completedAt, isNotNull);
      expect(c.stats.badgesEarned, contains('first-discovery'));
    });

    test('aynı nokta tekrar tamamlanmaz (idempotent, XP tek sefer)', () async {
      final trip = _tokyoKyotoTrip();
      final c = await _buildController(trip);
      final f = _byId(c.fences, 'tk-skytree');
      _completeFence(c, f, 0);
      final xpAfterFirst = c.stats.xp;
      // Aynı fence'e tekrar örnek it → completedAt set olduğundan engine atlar.
      _completeFence(c, f, 5000);
      expect(c.stats.xp, xpAfterFirst);
      expect(c.stats.discoveredPlaceIds.length, 1);
    });
  });

  group('UserStats.withDiscovery', () {
    test('yeni id ekler, şehir sayacını artırır (küçük harf)', () {
      const s = UserStats();
      final s1 = s.withDiscovery('tk-skytree', 'Tokyo');
      expect(s1.discoveredPlaceIds, ['tk-skytree']);
      expect(s1.discoveredCityCounts, {'tokyo': 1});

      final s2 = s1.withDiscovery('tk-sensoji', 'Tokyo');
      expect(s2.discoveredPlaceIds.length, 2);
      expect(s2.discoveredCityCounts['tokyo'], 2);
    });

    test('aynı id tekrar → this değişmez (idempotent)', () {
      const s = UserStats();
      final s1 = s.withDiscovery('tk-skytree', 'Tokyo');
      final s2 = s1.withDiscovery('tk-skytree', 'Tokyo');
      expect(identical(s1, s2), isTrue);
      expect(s2.discoveredCityCounts['tokyo'], 1);
    });

    test('JSON roundtrip yeni alanları korur', () {
      final s = const UserStats()
          .withDiscovery('tk-skytree', 'Tokyo')
          .withDiscovery('ky-fushimi', 'Kyoto');
      final restored = UserStats.fromJson(s.toJson());
      expect(restored.discoveredPlaceIds, containsAll(['tk-skytree', 'ky-fushimi']));
      expect(restored.discoveredCityCounts['tokyo'], 1);
      expect(restored.discoveredCityCounts['kyoto'], 1);
    });
  });

  group('Keşif rozeti değerlendiricileri (stats bazlı)', () {
    final trip = _tokyoKyotoTrip();
    BadgeDefinition badge(String id) =>
        kBadgeDefinitions.firstWhere((b) => b.id == id);

    test('first-discovery: en az bir keşifle açılır', () {
      expect(badge('first-discovery').evaluate(trip, const UserStats()), isFalse);
      expect(
        badge('first-discovery')
            .evaluate(trip, const UserStats(discoveredPlaceIds: ['a'])),
        isTrue,
      );
    });

    test('explorer-5 / explorer-10 eşikleri', () {
      final five = UserStats(
          discoveredPlaceIds: List.generate(5, (i) => 'p$i'));
      final ten = UserStats(
          discoveredPlaceIds: List.generate(10, (i) => 'p$i'));
      expect(badge('explorer-5').evaluate(trip, five), isTrue);
      expect(badge('explorer-10').evaluate(trip, five), isFalse);
      expect(badge('explorer-10').evaluate(trip, ten), isTrue);
    });

    test('şehir rozetleri 3 eşiğinde açılır (küçük harf anahtar)', () {
      const s = UserStats(discoveredCityCounts: {
        'tokyo': 3,
        'kyoto': 2,
        'osaka': 3,
      });
      expect(badge('tokyo-roamer').evaluate(trip, s), isTrue);
      expect(badge('kyoto-roamer').evaluate(trip, s), isFalse);
      expect(badge('osaka-roamer').evaluate(trip, s), isTrue);
    });
  });
}
