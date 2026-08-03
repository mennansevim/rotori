import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/route_matrix.dart';

import '../../tool/route_opt_harness/matrix_builder.dart';
import '../../tool/route_opt_harness/poi_data.dart';

/// P0 doğruluk fixleri için harness regresyonları:
///  - yemek yeri çalışma saatleri korunur (kapalı yere akşam yemeği yazılmaz),
///  - tam gün / uzak gezi POI'leri açık gün rolüyle izole edilir,
///  - aynı koordinatlı legler sıfırlanır (yapay kahvaltı yürüyüşü yok).
void main() {
  group('Yemek yeri çalışma saatleri (Faz 1.1)', () {
    test('Tsukiji öğle olabilir ama akşam yemeği olamaz', () {
      final tsukiji = pois.firstWhere((p) => p.id == 'tk_tsukiji');
      expect(tsukiji.servesMeal(MealPeriod.lunch, 11, 15, 40), isTrue);
      expect(tsukiji.servesMeal(MealPeriod.dinner, 18, 22, 55), isFalse);
    });

    test('Nishiki 18:00 sonrası akşam yemeği veremez', () {
      final nishiki = pois.firstWhere((p) => p.id == 'ky_nishiki');
      expect(nishiki.servesMeal(MealPeriod.dinner, 18, 22, 55), isFalse);
    });

    test('Kuromon 18:00 kapanışında akşam yemeği veremez', () {
      final kuromon = pois.firstWhere((p) => p.id == 'os_namba');
      expect(kuromon.servesMeal(MealPeriod.dinner, 18, 22, 55), isFalse);
    });

    test('Her şehirde en az bir gerçek akşam yemeği yeri var', () {
      for (final city in const ['Tokyo', 'Kyoto', 'Osaka', 'Nara', 'Hiroshima']) {
        final dinners = mealVenues(city, MealPeriod.dinner, 18, 22, 55);
        expect(dinners, isNotEmpty, reason: '$city akşam yemeği yeri yok');
      }
    });

    test('Akşam yemeği adayları hiçbir zaman kapalı market değildir', () {
      const markets = {'tk_tsukiji', 'ky_nishiki', 'os_namba'};
      for (final city in const ['Tokyo', 'Kyoto', 'Osaka']) {
        final dinners = mealVenues(city, MealPeriod.dinner, 18, 22, 55);
        for (final d in dinners) {
          expect(markets.contains(d.id), isFalse,
              reason: '${d.id} akşam yemeğine uygun sayıldı');
        }
      }
    });
  });

  group('POI gün rolleri (Faz 1.2)', () {
    test('USJ ve DisneySea fullDayExclusive', () {
      expect(pois.firstWhere((p) => p.id == 'os_usj').dayRole,
          PoiDayRole.fullDayExclusive);
      expect(pois.firstWhere((p) => p.id == 'tk_disneysea').dayRole,
          PoiDayRole.fullDayExclusive);
    });

    test('Miyajima excursion rolündedir', () {
      expect(pois.firstWhere((p) => p.id == 'hr_miyajima').dayRole,
          PoiDayRole.excursion);
    });

    test('Horyu-ji uzak cluster half-day anchor', () {
      expect(pois.firstWhere((p) => p.id == 'nr_horyuji').dayRole,
          PoiDayRole.halfDayAnchor);
    });
  });

  group('Sıfır co-located leg (Faz 1.3)', () {
    test('Aynı koordinat 0 dakikalık leg üretir', () {
      const builder = MatrixBuilder();
      final hotel = const TripLocation(
        id: 'hotel',
        name: 'Otel',
        latitude: 35.6938,
        longitude: 139.7034,
        city: 'Tokyo',
        clusterId: 'shinjuku',
      );
      final breakfast = const TripLocation(
        id: 'breakfast',
        name: 'Kahvaltı',
        latitude: 35.6938,
        longitude: 139.7034,
        city: 'Tokyo',
        clusterId: 'shinjuku',
      );
      final matrix = builder.build([hotel, breakfast]);
      final leg = matrix.entries.firstWhere(
        (e) => e.fromLocationId == 'hotel' && e.toLocationId == 'breakfast',
      );
      expect(leg.options.single.doorToDoorMinutes, 0);
      expect(leg.options.single.walkingMinutes, 0);
    });
  });
}
