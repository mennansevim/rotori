// Keşif haritası geofence motoru testleri.
// Haversine bilinen-mesafe, eşik (accuracy cap) ve dwell/grace senaryoları.
// Zaman kaynağı örneklerin timestamp'i olduğundan sahte saat enjeksiyonu
// GeoSample.timestamp üzerinden yapılır.

import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/geofence.dart';
import 'package:japan_trip/features/viewer/geofence_service.dart';

Geofence _fence({
  String id = 'f1',
  double lat = 35.0,
  double lng = 135.0,
  double radius = 120,
  int minDwell = 600,
}) =>
    Geofence(
      id: id,
      name: 'Test Fence',
      city: 'Test',
      lat: lat,
      lng: lng,
      radiusMeters: radius,
      minDwellSeconds: minDwell,
      xp: 25,
      emoji: '📍',
    );

GeoSample _at(
  int seconds, {
  double lat = 35.0,
  double lng = 135.0,
  double accuracy = 20,
}) =>
    GeoSample(
      lat: lat,
      lng: lng,
      accuracy: accuracy,
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
    );

/// 1 derece enlemin metre karşılığı (R = 6371000 için).
const double _metersPerDegLat = 6371000 * 3.141592653589793 / 180; // ≈111194.9

double _latOffsetForMeters(double meters) => meters / _metersPerDegLat;

void main() {
  group('distanceMeters (haversine)', () {
    test('aynı nokta 0 metre', () {
      expect(
        distanceMeters(const LatLng(35.7101, 139.8107),
            const LatLng(35.7101, 139.8107)),
        0,
      );
    });

    test('ekvatorda 1 derece boylam ≈ 111195 m', () {
      expect(
        distanceMeters(const LatLng(0, 0), const LatLng(0, 1)),
        closeTo(111194.93, 0.5),
      );
    });

    test('Tokyo Skytree → Senso-ji ≈ 1.37 km', () {
      final d = distanceMeters(
        const LatLng(35.7101, 139.8107), // Skytree
        const LatLng(35.7148, 139.7967), // Senso-ji
      );
      expect(d, closeTo(1369, 30));
    });

    test('Tokyo İstasyonu → Shibuya Crossing ≈ 6.5 km', () {
      final d = distanceMeters(
        const LatLng(35.6812, 139.7671),
        const LatLng(35.6595, 139.7005),
      );
      expect(d, closeTo(6489, 80));
    });

    test('simetrik: d(a,b) == d(b,a)', () {
      const a = LatLng(34.9671, 135.7727);
      const b = LatLng(35.0394, 135.7292);
      expect(distanceMeters(a, b), distanceMeters(b, a));
    });
  });

  group('geofence eşiği (inside = d <= radius + min(accuracy, 80))', () {
    // Fence merkezi (35, 135), yarıçap 120 m. Nokta 190 m kuzeyde.
    final north190 = 35.0 + _latOffsetForMeters(190);

    test('accuracy 200 → 80 ile sınırlanır → eşik 200 → içeride', () {
      final engine = GeofenceEngine(fences: [_fence()]);
      engine.handleSample(_at(0, lat: north190, accuracy: 200));
      expect(engine.hasSession('f1'), isTrue);
      expect(engine.visits.records['f1']?.firstSeenAt, isNotNull);
    });

    test('accuracy 60 → eşik 180 → dışarıda', () {
      final engine = GeofenceEngine(fences: [_fence()]);
      engine.handleSample(_at(0, lat: north190, accuracy: 60));
      expect(engine.hasSession('f1'), isFalse);
      expect(engine.visits.records.containsKey('f1'), isFalse);
    });

    test('tam sınırda (d == radius + accuracy) içeride sayılır', () {
      // 140 m kuzey; eşik = 120 + min(20, 80) = 140.
      final north140 = 35.0 + _latOffsetForMeters(140);
      final engine = GeofenceEngine(fences: [_fence()]);
      engine.handleSample(_at(0, lat: north140, accuracy: 20.001));
      expect(engine.hasSession('f1'), isTrue);
    });
  });

  group('dwell birikimi + tamamlanma', () {
    test('60 sn aralıklı tick\'ler 600 sn\'de complete tetikler (tek sefer)',
        () {
      final completed = <String>[];
      final engine = GeofenceEngine(
        fences: [_fence()],
        onCompleted: (f) => completed.add(f.id),
      );

      // t=0 giriş (oturum açılır, dwell eklenmez)
      engine.handleSample(_at(0));
      expect(engine.visits.records['f1']!.totalDwellSeconds, 0);

      // t=60..540: her tick 60 sn ekler → 540 sn
      for (var t = 60; t <= 540; t += 60) {
        engine.handleSample(_at(t));
      }
      expect(engine.visits.records['f1']!.totalDwellSeconds, 540);
      expect(engine.visits.records['f1']!.completedAt, isNull);
      expect(completed, isEmpty);

      // t=600 → toplam 600 >= minDwell → complete
      engine.handleSample(_at(600));
      final rec = engine.visits.records['f1']!;
      expect(rec.totalDwellSeconds, 600);
      expect(rec.completedAt, isNotNull);
      expect(completed, ['f1']);

      // Tamamlandıktan sonra tick'ler kaydı değiştirmez, callback tekrarlamaz.
      engine.handleSample(_at(660));
      expect(engine.visits.records['f1']!.totalDwellSeconds, 600);
      expect(completed, ['f1']);
    });

    test('tick deltası graceSeconds + 60 ile sınırlanır', () {
      final engine = GeofenceEngine(fences: [_fence()], graceSeconds: 120);
      engine.handleSample(_at(0));
      // 1000 sn'lik boşluk → delta 180 sn'e (grace + 60) kırpılır.
      engine.handleSample(_at(1000));
      expect(engine.visits.records['f1']!.totalDwellSeconds, 180);
    });

    test('firstSeenAt ilk girişte set edilir ve korunur', () {
      final engine = GeofenceEngine(fences: [_fence()], graceSeconds: 120);
      engine.handleSample(_at(0));
      final first = engine.visits.records['f1']!.firstSeenAt;
      expect(first, isNotNull);

      // Çık (grace aşımı) ve tekrar gir — firstSeenAt değişmemeli.
      engine.handleSample(_at(200, lat: 36.0)); // uzakta, 200 > 120 grace
      expect(engine.hasSession('f1'), isFalse);
      engine.handleSample(_at(300));
      expect(engine.visits.records['f1']!.firstSeenAt, first);
    });
  });

  group('grace period (çıkışta 120 sn tolerans)', () {
    test('grace içinde dışarı çıkma oturumu korur, dönüşte delta eklenir', () {
      final engine = GeofenceEngine(fences: [_fence()], graceSeconds: 120);
      engine.handleSample(_at(0)); // giriş
      engine.handleSample(_at(60)); // +60
      // t=120: dışarıda, son tick'ten 60 sn geçti (<= 120) → oturum korunur.
      engine.handleSample(_at(120, lat: 36.0));
      expect(engine.hasSession('f1'), isTrue);
      // t=170: içeri döndü → delta = 170 - 60 = 110 → toplam 170.
      engine.handleSample(_at(170));
      expect(engine.visits.records['f1']!.totalDwellSeconds, 170);
    });

    test('grace aşılınca oturum silinir; dwell sıfırlanmaz ama devam etmez',
        () {
      final engine = GeofenceEngine(fences: [_fence()], graceSeconds: 120);
      engine.handleSample(_at(0));
      engine.handleSample(_at(60)); // +60
      // t=190: dışarıda, son tick'ten 130 sn geçti (> 120) → oturum silinir.
      engine.handleSample(_at(190, lat: 36.0));
      expect(engine.hasSession('f1'), isFalse);
      // Biriken dwell kalıcı state'te korunur.
      expect(engine.visits.records['f1']!.totalDwellSeconds, 60);
      // t=250: yeni giriş — oturum tekrar açılır, ilk tick dwell eklemez.
      engine.handleSample(_at(250));
      expect(engine.visits.records['f1']!.totalDwellSeconds, 60);
      // t=310: +60 → toplam 120.
      engine.handleSample(_at(310));
      expect(engine.visits.records['f1']!.totalDwellSeconds, 120);
    });
  });

  group('VisitState JSON', () {
    test('roundtrip kayıpsız', () {
      const state = VisitState(records: {
        'a': VisitRecord(
          geofenceId: 'a',
          totalDwellSeconds: 123.5,
          firstSeenAt: '2026-07-07T10:00:00.000Z',
          completedAt: '2026-07-07T10:10:00.000Z',
        ),
        'b': VisitRecord(geofenceId: 'b', totalDwellSeconds: 45),
      });
      final restored = VisitState.fromJson(state.toJson());
      expect(restored.records.length, 2);
      expect(restored.records['a']!.totalDwellSeconds, 123.5);
      expect(restored.records['a']!.completedAt, '2026-07-07T10:10:00.000Z');
      expect(restored.records['b']!.completedAt, isNull);
      expect(restored.records['b']!.totalDwellSeconds, 45);
    });
  });
}
