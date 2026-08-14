// Tren bütçe tahmini — gerçekçilik sözleşmesi.
//
// Eski model iki yönden yanlıştı:
//  1. Şehir içi ulaşım GEZİ BAŞINA sabitti (¥7.000–20.000): 3 günlük gezi ile
//     14 günlük gezi aynı yerel ulaşım maliyetini alıyordu.
//  2. Şehirlerarası bacak üst sınırı ¥24.000'di — tablonun KENDİ referans
//     fiyatı olan Tokyo–Kyoto Nozomi (¥14.170) ile çelişiyordu.
// Sonuç: 7 günlük Tokyo+Kyoto gezisinde 2 kişi için ¥88.000 (₺26.585) tren
// tahmini çıkıyor, konaklamadan pahalı görünüyordu.

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/cost_estimate.dart';
import 'package:rotori/domain/plan_generation.dart';

CostLine _train(
  List<String> cities,
  String start,
  String end, {
  int adults = 2,
  int children = 0,
}) {
  final trip = buildTripFromCities(
    cityKeys: cities,
    startYmd: start,
    endYmd: end,
  );
  trip.preferences.partySize = adults + children;
  trip.preferences.childrenCount = children;
  final e = estimateTripCost(trip, UnitCostTable.defaults());
  return e.lines.firstWhere((l) => l.category == CostCategory.train);
}

/// Tablonun kendi referans fiyatı — testin dayanağı.
int _refShinkansen() => UnitCostTable.defaults()
    .references
    .firstWhere((r) => r.key == 'shinkansen_tokyo_kyoto')
    .jpy;

void main() {
  group('şehirlerarası bacak', () {
    test('üst sınır kendi referans fiyatının makul üstünde kalır', () {
      final t = UnitCostTable.defaults();
      final ref = _refShinkansen(); // Tokyo–Kyoto Nozomi ~¥14.170
      expect(t.trainIntercityMax, greaterThanOrEqualTo(ref),
          reason: 'gerçek bileti karşılamıyor');
      expect(t.trainIntercityMax, lessThan(ref * 2),
          reason: 'referansın iki katı — kullanıcıyı yanlış yönlendirir');
    });

    test('bacak sayısı arttıkça tahmin artar', () {
      final iki = _train(const ['tokyo', 'kyoto'], '2026-10-15', '2026-10-21');
      final uc =
          _train(const ['tokyo', 'kyoto', 'osaka'], '2026-10-15', '2026-10-21');
      expect(uc.maxJpy, greaterThan(iki.maxJpy));
    });
  });

  group('şehir içi ulaşım GÜNE bağlı', () {
    test('uzun gezi kısa geziden pahalı', () {
      // Aynı şehir sayısı, farklı gün — eskiden İKİSİ DE AYNI çıkıyordu.
      final kisa = _train(const ['tokyo', 'kyoto'], '2026-10-15', '2026-10-18');
      final uzun = _train(const ['tokyo', 'kyoto'], '2026-10-15', '2026-10-28');
      expect(uzun.maxJpy, greaterThan(kisa.maxJpy),
          reason: 'yerel ulaşım gün sayısıyla ölçeklenmiyor');
    });

    test('günlük yerel maliyet metro/pass gerçeğine yakın', () {
      final t = UnitCostTable.defaults();
      // Metro bileti ¥210, günlük pass ¥800 — günlük tavan bunun katı olmalı,
      // 10 katı değil.
      expect(t.trainLocalDayMin, greaterThanOrEqualTo(200));
      expect(t.trainLocalDayMax, lessThanOrEqualTo(3000));
    });
  });

  group('7 günlük Tokyo+Kyoto — kullanıcının bildirdiği senaryo', () {
    test('2 yetişkin için tahmin gerçekçi aralıkta', () {
      final tr = _train(const ['tokyo', 'kyoto'], '2026-10-15', '2026-10-21');

      // Kişi başı: 7 gün yerel + 1 shinkansen bacağı.
      final perAdultMax = tr.maxJpy / 2;
      expect(perAdultMax, lessThan(30000),
          reason: 'kişi başı ¥30.000 üstü tren tahmini abartı');
      expect(tr.minJpy, greaterThan(0));
      expect(tr.maxJpy, greaterThan(tr.minJpy));
    });

    test('JR Pass fiyatı HESABA KATILMAZ', () {
      // Pass önerilmiyor; tahmin pass fiyatına kilitlenmemeli. 7 günlük pass
      // ¥50.000 — tahminin ona eşitlenmesi pass varsayıldığını gösterirdi.
      final tr = _train(const ['tokyo', 'kyoto'], '2026-10-15', '2026-10-21');
      expect(tr.maxJpy, isNot(100000)); // 2 × ¥50.000
      expect(tr.maxJpy / 2, isNot(50000));
    });
  });

  group('çocuk indirimi', () {
    test('çocuk yetişkinden ucuz sayılır', () {
      final yetiskin = _train(
          const ['tokyo', 'kyoto'], '2026-10-15', '2026-10-21',
          adults: 2);
      final cocuklu = _train(
          const ['tokyo', 'kyoto'], '2026-10-15', '2026-10-21',
          adults: 2, children: 2);
      expect(cocuklu.maxJpy, greaterThan(yetiskin.maxJpy));
      // İki çocuk iki yetişkin kadar TUTMAMALI (yarım ücret).
      expect(cocuklu.maxJpy, lessThan(yetiskin.maxJpy * 2));
    });
  });
}
