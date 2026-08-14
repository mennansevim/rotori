// GPS devreye girme politikası.
//
// Politikanın asıl değeri GPS'i AÇMAK değil, çoğu zaman AÇMAMAK. Bu yüzden
// testlerin ağırlığı "akış başlamamalı" senaryolarında.

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/geofence.dart' show LatLng, distanceMeters;
import 'package:rotori/domain/gps_arming_policy.dart';

void main() {
  _accuracyTests();

  const policy = GpsArmingPolicy();

  // Asakusa (Senso-ji) ve Shinjuku — aralarında ~8 km var.
  const asakusaLat = 35.7148, asakusaLng = 139.7967;
  const shinjukuLat = 35.6896, shinjukuLng = 139.7006;

  final now = DateTime(2026, 8, 20, 10, 0);

  GpsTarget asakusa({DateTime? at, bool discovered = false}) => GpsTarget(
        id: 'sensoji',
        lat: asakusaLat,
        lng: asakusaLng,
        radiusMeters: 150,
        scheduledAt: at,
        isDiscovered: discovered,
      );

  GeoFix fixAt(double lat, double lng, {Duration age = Duration.zero}) =>
      GeoFix(lat: lat, lng: lng, timestamp: now.subtract(age));

  GpsArmingDecision run({
    bool permission = true,
    bool inTrip = true,
    List<GpsTarget>? targets,
    GeoFix? fix,
    DateTime? at,
  }) =>
      policy.evaluate(
        now: at ?? now,
        isWithinTripWindow: inTrip,
        hasPermission: permission,
        targets: targets ?? [asakusa(at: now)],
        lastFix: fix,
      );

  group('kapılar — GPS hiç açılmaz', () {
    test('izin yoksa off', () {
      final d = run(permission: false, fix: fixAt(asakusaLat, asakusaLng));
      expect(d.tier, GpsArmingTier.off);
      expect(d.reason, GpsArmingReason.permissionMissing);
      expect(d.isStreaming, isFalse);
    });

    test('gezi penceresi dışındaysa off', () {
      final d = run(inTrip: false, fix: fixAt(asakusaLat, asakusaLng));
      expect(d.tier, GpsArmingTier.off);
      expect(d.reason, GpsArmingReason.outsideTripWindow);
    });

    test('hedef yoksa off', () {
      final d = run(targets: const [], fix: fixAt(asakusaLat, asakusaLng));
      expect(d.tier, GpsArmingTier.off);
      expect(d.reason, GpsArmingReason.noTargets);
    });

    test('tüm hedefler keşfedilmişse off', () {
      final d = run(
        targets: [asakusa(at: now, discovered: true)],
        fix: fixAt(asakusaLat, asakusaLng),
      );
      expect(d.tier, GpsArmingTier.off);
      expect(d.reason, GpsArmingReason.allTargetsDiscovered);
    });
  });

  group('tek atış — akış başlatmadan konum öğren', () {
    test('konum bilinmiyorsa oneShot', () {
      final d = run(fix: null);
      expect(d.tier, GpsArmingTier.oneShot);
      expect(d.reason, GpsArmingReason.noFixYet);
      expect(d.needsFix, isTrue);
      expect(d.isStreaming, isFalse);
    });

    test('fix çok eskiyse oneShot', () {
      final d = run(
        fix: fixAt(asakusaLat, asakusaLng, age: const Duration(minutes: 45)),
      );
      expect(d.tier, GpsArmingTier.oneShot);
      expect(d.reason, GpsArmingReason.staleFix);
      expect(d.needsFix, isTrue);
    });

    test('taze fix bayat sayılmaz', () {
      final d = run(
        fix: fixAt(asakusaLat, asakusaLng, age: const Duration(minutes: 5)),
      );
      expect(d.needsFix, isFalse);
    });
  });

  group('mesafe kapısı', () {
    test('8 km uzaktayken akış AÇILMAZ', () {
      final d = run(fix: fixAt(shinjukuLat, shinjukuLng));
      expect(d.tier, GpsArmingTier.oneShot);
      expect(d.reason, GpsArmingReason.farFromAllTargets);
      expect(d.isStreaming, isFalse);
      expect(d.nearestTargetMeters, greaterThan(7000));
      expect(d.nearestTargetId, 'sensoji');
    });

    test('uzak mesafede tekrar-bakma aralığı uzar', () {
      final far = run(fix: fixAt(shinjukuLat, shinjukuLng));
      expect(far.recheckAfter, isNotNull);
      // ~8 km / 4.6 km/s ≈ 104 dk; yarısı 52 dk → 30 dk üst sınıra kırpılır.
      expect(far.recheckAfter, const Duration(minutes: 30));
    });

    test('yaklaşma yarıçapı içinde balanced', () {
      // Asakusa'dan ~800 m kuzey.
      final d = run(fix: fixAt(asakusaLat + 0.0072, asakusaLng));
      expect(d.tier, GpsArmingTier.balanced);
      expect(d.reason, GpsArmingReason.approachingTarget);
      expect(d.isStreaming, isTrue);
      expect(d.nearestTargetMeters, closeTo(800, 60));
    });

    test('hedefin dibinde precise', () {
      final d = run(fix: fixAt(asakusaLat + 0.0009, asakusaLng));
      expect(d.tier, GpsArmingTier.precise);
      expect(d.reason, GpsArmingReason.atTarget);
      expect(d.isStreaming, isTrue);
    });
  });

  group('zaman kapısı — iki koşul BİRLİKTE gerekir', () {
    test('hedef yakın ama saati gelmemişse akış AÇILMAZ', () {
      // 800 m yakında, ama planlı saat 6 saat sonra.
      final d = run(
        targets: [asakusa(at: now.add(const Duration(hours: 6)))],
        fix: fixAt(asakusaLat + 0.0072, asakusaLng),
      );
      expect(d.tier, GpsArmingTier.oneShot);
      expect(d.reason, GpsArmingReason.outsideTimeWindow);
      expect(d.isStreaming, isFalse);
    });

    test('otelde gece yarısı, hedefe uzak → kesinlikle off/oneShot', () {
      final midnight = DateTime(2026, 8, 20, 23, 0);
      final d = run(
        at: midnight,
        targets: [asakusa(at: DateTime(2026, 8, 21, 10, 0))],
        fix: GeoFix(
          lat: shinjukuLat,
          lng: shinjukuLng,
          timestamp: midnight,
        ),
      );
      expect(d.isStreaming, isFalse);
    });

    test('planlı saatin ±45 dk penceresinde akış açılır', () {
      for (final offset in const [
        Duration(minutes: -40),
        Duration.zero,
        Duration(minutes: 40),
      ]) {
        final d = run(
          targets: [asakusa(at: now.add(offset))],
          fix: fixAt(asakusaLat + 0.0072, asakusaLng),
        );
        expect(d.isStreaming, isTrue, reason: 'offset $offset');
      }
    });

    test('pencere sınırının hemen dışı kapalı', () {
      final d = run(
        targets: [asakusa(at: now.add(const Duration(minutes: 50)))],
        fix: fixAt(asakusaLat + 0.0072, asakusaLng),
      );
      expect(d.isStreaming, isFalse);
      expect(d.reason, GpsArmingReason.outsideTimeWindow);
    });

    test('saati bilinmeyen hedef zaman yüzünden ıskalanmaz', () {
      final d = run(
        targets: [asakusa(at: null)],
        fix: fixAt(asakusaLat + 0.0072, asakusaLng),
      );
      expect(d.isStreaming, isTrue);
      expect(d.reason, GpsArmingReason.approachingTarget);
    });
  });

  group('çoklu hedef', () {
    test('zaman kapısı açık olan yakın hedef seçilir', () {
      final d = policy.evaluate(
        now: now,
        isWithinTripWindow: true,
        hasPermission: true,
        // Daha yakın ama saati gelmemiş; uzak ama saati gelmiş.
        targets: [
          GpsTarget(
            id: 'yakin-ama-erken',
            lat: asakusaLat + 0.0009,
            lng: asakusaLng,
            scheduledAt: now.add(const Duration(hours: 8)),
          ),
          GpsTarget(
            id: 'uzak-ama-zamani',
            lat: asakusaLat + 0.009,
            lng: asakusaLng,
            scheduledAt: now,
          ),
        ],
        lastFix: fixAt(asakusaLat, asakusaLng),
      );
      expect(d.isStreaming, isTrue);
      expect(d.nearestTargetId, 'uzak-ama-zamani');
    });

    test('keşfedilmiş hedef hesaba katılmaz', () {
      final d = policy.evaluate(
        now: now,
        isWithinTripWindow: true,
        hasPermission: true,
        targets: [
          GpsTarget(
            id: 'bitti',
            lat: asakusaLat,
            lng: asakusaLng,
            scheduledAt: now,
            isDiscovered: true,
          ),
          GpsTarget(
            id: 'uzak',
            lat: shinjukuLat,
            lng: shinjukuLng,
            scheduledAt: now,
          ),
        ],
        lastFix: fixAt(asakusaLat, asakusaLng),
      );
      expect(d.isStreaming, isFalse);
      expect(d.nearestTargetId, 'uzak');
    });
  });

  group('distanceMeters', () {
    test('aynı nokta sıfır', () {
      expect(
        distanceMeters(const LatLng(35.68, 139.65), const LatLng(35.68, 139.65)),
        closeTo(0, 0.5),
      );
    });

    test('Shinjuku → Asakusa ~8 km', () {
      final m = distanceMeters(
        const LatLng(shinjukuLat, shinjukuLng),
        const LatLng(asakusaLat, asakusaLng),
      );
      expect(m, closeTo(8900, 700));
    });

    test('simetrik', () {
      final a = distanceMeters(
        const LatLng(35.68, 139.65),
        const LatLng(35.01, 135.76),
      );
      final b = distanceMeters(
        const LatLng(35.01, 135.76),
        const LatLng(35.68, 139.65),
      );
      expect(a, closeTo(b, 0.01));
    });

    test('Tokyo → Kyoto ~360 km', () {
      final m = distanceMeters(
        const LatLng(35.68, 139.65),
        const LatLng(35.01, 135.76),
      );
      expect(m / 1000, closeTo(365, 25));
    });
  });
}

// ---------------------------------------------------------------------------
// Apple uyumluluğu: iOS 14+ "Yaklaşık Konum" ve fix hata payı.
// ---------------------------------------------------------------------------

void _accuracyTests() {
  const policy = GpsArmingPolicy();
  const lat = 35.7148, lng = 139.7967;
  final now = DateTime(2026, 8, 20, 10, 0);

  GpsArmingDecision run({
    required LocationAccuracyAuthorization accuracy,
    required double fixLat,
    double fixAccuracyMeters = 20,
  }) =>
      policy.evaluate(
        now: now,
        isWithinTripWindow: true,
        hasPermission: true,
        accuracy: accuracy,
        targets: [
          GpsTarget(id: 'sensoji', lat: lat, lng: lng, scheduledAt: now),
        ],
        lastFix: GeoFix(
          lat: fixLat,
          lng: lng,
          timestamp: now,
          accuracyMeters: fixAccuracyMeters,
        ),
      );

  group('yaklaşık konum yetkisi', () {
    test('hedefin dibinde bile damga verilmez, geçici izin istenir', () {
      final d = run(
        accuracy: LocationAccuracyAuthorization.reduced,
        fixLat: lat + 0.0009, // ~100 m
      );
      expect(d.tier, isNot(GpsArmingTier.precise));
      expect(d.reason, GpsArmingReason.reducedAccuracyBlocked);
      expect(d.needsTemporaryFullAccuracy, isTrue);
      expect(d.isStreaming, isFalse);
    });

    test('tam doğrulukta aynı konum precise verir', () {
      final d = run(
        accuracy: LocationAccuracyAuthorization.precise,
        fixLat: lat + 0.0009,
      );
      expect(d.tier, GpsArmingTier.precise);
      expect(d.needsTemporaryFullAccuracy, isFalse);
    });

    test('yaklaşık konumda uzaktayken geçici izin İSTENMEZ', () {
      // Erken sormak kabul oranını düşürür; yalnız yakındayken sorulur.
      final d = run(
        accuracy: LocationAccuracyAuthorization.reduced,
        fixLat: lat + 0.09, // ~10 km
      );
      expect(d.needsTemporaryFullAccuracy, isFalse);
      expect(d.reason, GpsArmingReason.farFromAllTargets);
    });
  });

  group('fix hata payı', () {
    test('hata payı karar yarıçapından büyükse "hedefteyim" denmez', () {
      final d = run(
        accuracy: LocationAccuracyAuthorization.precise,
        fixLat: lat + 0.0009, // ~100 m
        fixAccuracyMeters: 900, // ama ±900 m belirsizlik
      );
      expect(d.tier, GpsArmingTier.balanced);
      expect(d.reason, GpsArmingReason.approachingTarget);
    });

    test('iyi hata payında precise korunur', () {
      final d = run(
        accuracy: LocationAccuracyAuthorization.precise,
        fixLat: lat + 0.0009,
        fixAccuracyMeters: 15,
      );
      expect(d.tier, GpsArmingTier.precise);
    });
  });
}
