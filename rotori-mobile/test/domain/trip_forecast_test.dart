// Rota günü ↔ şehir ↔ hava eşleştirmesi.
//
// Asıl invariant: 5. gün Kyoto'daysa o güne Tokyo'nun tahmini DÜŞMEZ. Viewer'ın
// gün rozetleri ile hava ekranı aynı fonksiyondan türediği için bu tek test
// dosyası iki yüzeyi birden korur.

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/data/weather_service.dart';
import 'package:rotori/domain/trip_forecast.dart';
import 'package:rotori/domain/types.dart';

TripDestination _dest({
  required String id,
  required String city,
  required String arrival,
  required String departure,
  required int order,
  double? lat,
  double? lng,
}) =>
    TripDestination(
      id: id,
      countryCode: 'JP',
      countryName: 'Japonya',
      city: city,
      arrivalDate: arrival,
      departureDate: departure,
      order: order,
      lat: lat,
      lng: lng,
    );

DayPlan _day(int number, String date) =>
    DayPlan(dayNumber: number, date: date, theme: '');

DayForecast _f(String date, {int code = 0, double max = 30, double min = 20}) =>
    DayForecast(date: date, code: code, tempMax: max, tempMin: min);

void main() {
  _actionableTests();
  _groupingTests();

  // Tokyo 15–17 Ekim, Kyoto 18–20 Ekim.
  final tokyo = _dest(
    id: 'd-tokyo',
    city: 'Tokyo',
    arrival: '2026-10-15',
    departure: '2026-10-17',
    order: 0,
    lat: 35.68,
    lng: 139.65,
  );
  final kyoto = _dest(
    id: 'd-kyoto',
    city: 'Kyoto',
    arrival: '2026-10-18',
    departure: '2026-10-20',
    order: 1,
    lat: 35.01,
    lng: 135.76,
  );

  final days = [
    _day(1, '2026-10-15'),
    _day(2, '2026-10-16'),
    _day(3, '2026-10-17'),
    _day(4, '2026-10-18'),
    _day(5, '2026-10-19'),
    _day(6, '2026-10-20'),
  ];

  group('buildRouteForecast', () {
    test('her güne o günün şehrinin tahmini bağlanır', () {
      final rows = buildRouteForecast(
        days: days,
        destinations: [tokyo, kyoto],
        forecastsByDestinationId: {
          // Tokyo servisi TÜM tarihler için veri döndürüyor (16 günlük ufuk).
          tokyo.id: [
            for (final d in days) _f(d.date, code: 0, max: 30),
          ],
          // Kyoto servisi de öyle — ayırt edici olan sıcaklık.
          kyoto.id: [
            for (final d in days) _f(d.date, code: 61, max: 22),
          ],
        },
      );

      expect(rows, hasLength(6));
      expect(rows.map((r) => r.city).toList(),
          ['Tokyo', 'Tokyo', 'Tokyo', 'Kyoto', 'Kyoto', 'Kyoto']);

      // Kritik: Kyoto günlerine Tokyo verisi sızmamalı.
      for (final row in rows.where((r) => r.city == 'Kyoto')) {
        expect(row.forecast!.tempMax, 22, reason: '${row.date} Kyoto olmalı');
        expect(row.forecast!.code, 61);
      }
      for (final row in rows.where((r) => r.city == 'Tokyo')) {
        expect(row.forecast!.tempMax, 30, reason: '${row.date} Tokyo olmalı');
      }
    });

    test('şehir değişen gün isCityChange ile işaretlenir', () {
      final rows = buildRouteForecast(
        days: days,
        destinations: [tokyo, kyoto],
        forecastsByDestinationId: const {},
      );
      expect(rows.where((r) => r.isCityChange).map((r) => r.date).toList(),
          ['2026-10-18']);
      // İlk gün "değişim" sayılmaz.
      expect(rows.first.isCityChange, isFalse);
    });

    test('tahmin bulunamayan gün null forecast ile döner (uydurulmaz)', () {
      final rows = buildRouteForecast(
        days: days,
        destinations: [tokyo, kyoto],
        forecastsByDestinationId: {
          tokyo.id: [_f('2026-10-15')],
          // Kyoto çağrısı düşmüş — o günler veri-yok kalmalı.
        },
      );
      expect(rows[0].hasForecast, isTrue);
      expect(rows[1].hasForecast, isFalse);
      expect(rows.where((r) => r.city == 'Kyoto').every((r) => !r.hasForecast),
          isTrue);
    });

    test('destinasyon takvimi dışındaki gün şehirsiz kalır', () {
      final rows = buildRouteForecast(
        days: [_day(1, '2026-01-01')],
        destinations: [tokyo, kyoto],
        forecastsByDestinationId: const {},
      );
      expect(rows.single.city, isEmpty);
      expect(rows.single.hasForecast, isFalse);
    });

    test('günler sıralanmamış gelse de çıktı gün numarasına göre sıralıdır', () {
      final rows = buildRouteForecast(
        days: [_day(3, '2026-10-17'), _day(1, '2026-10-15')],
        destinations: [tokyo],
        forecastsByDestinationId: const {},
      );
      expect(rows.map((r) => r.dayNumber).toList(), [1, 3]);
    });
  });

  group('distinctForecastDestinations', () {
    test('koordinatsız destinasyonlar elenir', () {
      final noCoords = _dest(
        id: 'd-x',
        city: 'Nara',
        arrival: '2026-10-21',
        departure: '2026-10-22',
        order: 2,
      );
      final out = distinctForecastDestinations([tokyo, kyoto, noCoords]);
      expect(out.map((d) => d.id).toList(), ['d-tokyo', 'd-kyoto']);
    });

    test('aynı koordinat iki kez çekilmez', () {
      final tokyoAgain = _dest(
        id: 'd-tokyo-2',
        city: 'Tokyo',
        arrival: '2026-10-21',
        departure: '2026-10-22',
        order: 2,
        lat: 35.68,
        lng: 139.65,
      );
      final out = distinctForecastDestinations([tokyo, kyoto, tokyoAgain]);
      expect(out, hasLength(2));
      expect(out.map((d) => d.id), isNot(contains('d-tokyo-2')));
    });

    test('order sırası korunur', () {
      final out = distinctForecastDestinations([kyoto, tokyo]);
      expect(out.map((d) => d.city).toList(), ['Tokyo', 'Kyoto']);
    });
  });

  group('routeForecastByDate', () {
    test('viewer rozet haritası aynı eşleştirmeden türer', () {
      final rows = buildRouteForecast(
        days: days,
        destinations: [tokyo, kyoto],
        forecastsByDestinationId: {
          tokyo.id: [for (final d in days) _f(d.date, max: 30)],
          kyoto.id: [for (final d in days) _f(d.date, max: 22)],
        },
      );
      final byDate = routeForecastByDate(rows);
      expect(byDate, hasLength(6));
      // Rozet de liste de aynı değeri görmeli.
      expect(byDate['2026-10-19']!.tempMax, 22);
      expect(byDate['2026-10-16']!.tempMax, 30);
    });

    test('veri olmayan gün haritaya girmez', () {
      final rows = buildRouteForecast(
        days: days,
        destinations: [tokyo, kyoto],
        forecastsByDestinationId: {
          tokyo.id: [_f('2026-10-15')],
        },
      );
      expect(routeForecastByDate(rows).keys, ['2026-10-15']);
    });
  });

  group('buildRouteForecastFromDateRange', () {
    test('gün listesi yokken tarih aralığından türetir', () {
      final rows = buildRouteForecastFromDateRange(
        startIso: '2026-10-15',
        endIso: '2026-10-20',
        destinations: [tokyo, kyoto],
        forecastsByDestinationId: {
          kyoto.id: [_f('2026-10-19', max: 22)],
        },
      );
      expect(rows, hasLength(6));
      expect(rows.first.date, '2026-10-15');
      expect(rows.last.date, '2026-10-20');
      expect(rows.map((r) => r.dayNumber).toList(), [1, 2, 3, 4, 5, 6]);
      // Şehir çözümü yine destinasyon takviminden gelir.
      expect(rows[4].city, 'Kyoto');
      expect(rows[4].forecast!.tempMax, 22);
    });

    test('geçersiz veya ters aralık boş döner', () {
      expect(
        buildRouteForecastFromDateRange(
          startIso: 'yok',
          endIso: '2026-10-20',
          destinations: [tokyo],
          forecastsByDestinationId: const {},
        ),
        isEmpty,
      );
      expect(
        buildRouteForecastFromDateRange(
          startIso: '2026-10-20',
          endIso: '2026-10-15',
          destinations: [tokyo],
          forecastsByDestinationId: const {},
        ),
        isEmpty,
      );
    });

    test('aşırı uzun aralık 40 günle sınırlanır', () {
      final rows = buildRouteForecastFromDateRange(
        startIso: '2026-01-01',
        endIso: '2027-01-01',
        destinations: const [],
        forecastsByDestinationId: const {},
      );
      expect(rows, hasLength(40));
    });
  });
}

// ---------------------------------------------------------------------------
// Hava temelli optimizasyonun teklif penceresi.
// ---------------------------------------------------------------------------

void _actionableTests() {
  group('isForecastActionable', () {
    final today = DateTime(2026, 8, 12);

    test('bugün ve 7 gün içi teklif edilebilir', () {
      for (final d in [
        '2026-08-12',
        '2026-08-13',
        '2026-08-18',
        '2026-08-19',
      ]) {
        expect(isForecastActionable(dateIso: d, today: today), isTrue,
            reason: d);
      }
    });

    test('8. günden sonrası kesin değil — teklif edilmez', () {
      for (final d in ['2026-08-20', '2026-08-27', '2026-09-01']) {
        expect(isForecastActionable(dateIso: d, today: today), isFalse,
            reason: d);
      }
    });

    test('geçmiş gün teklif edilmez', () {
      expect(isForecastActionable(dateIso: '2026-08-11', today: today), isFalse);
    });

    test('geçersiz tarih güvenli tarafa düşer', () {
      expect(isForecastActionable(dateIso: '', today: today), isFalse);
      expect(isForecastActionable(dateIso: 'yarın', today: today), isFalse);
    });

    test('saat bileşeni sonucu değiştirmez', () {
      expect(
        isForecastActionable(
          dateIso: '2026-08-19',
          today: DateTime(2026, 8, 12, 23, 59),
        ),
        isTrue,
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Şehir başlıklarına gruplama.
// ---------------------------------------------------------------------------

void _groupingTests() {
  DayPlan d(int n, String date) =>
      DayPlan(dayNumber: n, date: date, theme: '');

  TripDestination dest(String id, String city, String a, String b, int o) =>
      TripDestination(
        id: id,
        countryCode: 'JP',
        countryName: 'Japonya',
        city: city,
        arrivalDate: a,
        departureDate: b,
        order: o,
        lat: 35.0 + o,
        lng: 135.0 + o,
      );

  group('groupRouteForecastByCity', () {
    test('ardışık aynı şehir günleri tek blokta toplanır', () {
      final rows = buildRouteForecast(
        days: [
          d(1, '2026-10-15'),
          d(2, '2026-10-16'),
          d(3, '2026-10-17'),
          d(4, '2026-10-18'),
        ],
        destinations: [
          dest('t', 'Tokyo', '2026-10-15', '2026-10-16', 0),
          dest('k', 'Kyoto', '2026-10-17', '2026-10-18', 1),
        ],
        forecastsByDestinationId: const {},
      );
      final segments = groupRouteForecastByCity(rows);

      expect(segments.map((s) => s.city).toList(), ['Tokyo', 'Kyoto']);
      expect(segments[0].dayCount, 2);
      expect(segments[0].startDate, '2026-10-15');
      expect(segments[0].endDate, '2026-10-16');
      expect(segments[1].startDate, '2026-10-17');
    });

    test('şehre geri dönüş AYRI blok olur (takvim yanlış anlatılmaz)', () {
      final rows = buildRouteForecast(
        days: [
          d(1, '2026-10-15'),
          d(2, '2026-10-16'),
          d(3, '2026-10-17'),
        ],
        destinations: [
          dest('t1', 'Tokyo', '2026-10-15', '2026-10-15', 0),
          dest('k', 'Kyoto', '2026-10-16', '2026-10-16', 1),
          dest('t2', 'Tokyo', '2026-10-17', '2026-10-17', 2),
        ],
        forecastsByDestinationId: const {},
      );
      final segments = groupRouteForecastByCity(rows);
      expect(segments.map((s) => s.city).toList(), ['Tokyo', 'Kyoto', 'Tokyo']);
      expect(segments.every((s) => s.dayCount == 1), isTrue);
    });

    test('tek şehirli gezi tek blok verir', () {
      final rows = buildRouteForecast(
        days: [d(1, '2026-10-15'), d(2, '2026-10-16')],
        destinations: [dest('t', 'Tokyo', '2026-10-15', '2026-10-16', 0)],
        forecastsByDestinationId: const {},
      );
      expect(groupRouteForecastByCity(rows), hasLength(1));
    });

    test('şehri çözülemeyen günler kendi bloğunda toplanır', () {
      final rows = buildRouteForecast(
        days: [d(1, '2026-01-01'), d(2, '2026-10-15')],
        destinations: [dest('t', 'Tokyo', '2026-10-15', '2026-10-16', 0)],
        forecastsByDestinationId: const {},
      );
      final segments = groupRouteForecastByCity(rows);
      expect(segments, hasLength(2));
      expect(segments.first.city, isEmpty);
      expect(segments.last.city, 'Tokyo');
    });

    test('boş girdi boş liste verir', () {
      expect(groupRouteForecastByCity(const []), isEmpty);
    });

    test('hasAnyForecast blokta veri olup olmadığını bildirir', () {
      final rows = buildRouteForecast(
        days: [d(1, '2026-10-15'), d(2, '2026-10-17')],
        destinations: [
          dest('t', 'Tokyo', '2026-10-15', '2026-10-15', 0),
          dest('k', 'Kyoto', '2026-10-17', '2026-10-17', 1),
        ],
        forecastsByDestinationId: {
          't': const [
            DayForecast(
              date: '2026-10-15',
              code: 0,
              tempMax: 30,
              tempMin: 20,
            ),
          ],
        },
      );
      final segments = groupRouteForecastByCity(rows);
      expect(segments.first.hasAnyForecast, isTrue);
      expect(segments.last.hasAnyForecast, isFalse);
    });
  });
}
