// distributeDates — journey_step._resync içinden çağrılan pure helper.
// Yeni eklenen destinasyonların hepsi travelDates.start ile geldiğinden
// tarihleri eşit dilimlere ayırıyoruz; kullanıcı elle düzenlemişse skip
// kararı çağıran taraftadır (heuristik: hepsi start == arrival).

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/trip_factory.dart';
import 'package:rotori/domain/types.dart';

TripDestination _d(String city, int order, {String arrival = '', String dep = ''}) =>
    TripDestination(
      id: 'dest-$city',
      countryCode: 'JP',
      countryName: 'Japonya',
      city: city,
      arrivalDate: arrival,
      departureDate: dep,
      order: order,
    );

void main() {
  group('distributeDates', () {
    test('3 destinasyon / 15 gün → 5+5+5', () {
      final dests = [
        _d('Osaka', 0, arrival: '2026-05-01'),
        _d('Tokyo', 1, arrival: '2026-05-01'),
        _d('Nara', 2, arrival: '2026-05-01'),
      ];
      distributeDates(dests, '2026-05-01', '2026-05-15');
      expect(dests[0].arrivalDate, '2026-05-01');
      expect(dests[0].departureDate, '2026-05-06');
      expect(dests[1].arrivalDate, '2026-05-06');
      expect(dests[1].departureDate, '2026-05-11');
      expect(dests[2].arrivalDate, '2026-05-11');
      expect(dests[2].departureDate, '2026-05-15');
    });

    test('2 destinasyon / 6 gün → 3+3', () {
      final dests = [
        _d('Osaka', 0, arrival: '2026-05-01'),
        _d('Tokyo', 1, arrival: '2026-05-01'),
      ];
      distributeDates(dests, '2026-05-01', '2026-05-06');
      expect(dests[0].arrivalDate, '2026-05-01');
      expect(dests[0].departureDate, '2026-05-04');
      expect(dests[1].arrivalDate, '2026-05-04');
      expect(dests[1].departureDate, '2026-05-06');
    });

    test('artık gün son destinasyona düşer (3 dest / 16 gün → 5+5+6)', () {
      final dests = [
        _d('Osaka', 0, arrival: '2026-05-01'),
        _d('Tokyo', 1, arrival: '2026-05-01'),
        _d('Nara', 2, arrival: '2026-05-01'),
      ];
      distributeDates(dests, '2026-05-01', '2026-05-16');
      // 16 gün / 3 = 5, remainder 1 → last +1
      expect(dests[0].arrivalDate, '2026-05-01');
      expect(dests[1].arrivalDate, '2026-05-06');
      expect(dests[2].arrivalDate, '2026-05-11');
      expect(dests[2].departureDate, '2026-05-16');
    });

    test('boş liste / boş tarih → değişiklik yok', () {
      final empty = <TripDestination>[];
      final out = distributeDates(empty, '2026-05-01', '2026-05-15');
      expect(out, isEmpty);
      final one = [_d('Tokyo', 0, arrival: '2026-05-01', dep: '2026-05-05')];
      distributeDates(one, '', '2026-05-15');
      expect(one[0].arrivalDate, '2026-05-01');
    });

    test('tek destinasyon → tüm aralık', () {
      final one = [_d('Tokyo', 0, arrival: '2026-05-01')];
      distributeDates(one, '2026-05-01', '2026-05-10');
      expect(one[0].arrivalDate, '2026-05-01');
      expect(one[0].departureDate, '2026-05-10');
    });

    test('_resync heuristiği: kullanıcı elle set etmişse skip beklenir '
        '(caller responsibility)', () {
      // Bu fonksiyon her zaman dağıtır — heuristik çağıranda.
      // Buradaki iş: dağıtım algoritmasının deterministik olduğunu göstermek.
      final dests = [
        _d('Osaka', 0, arrival: '2026-05-03'), // kullanıcı elle set etti
        _d('Tokyo', 1, arrival: '2026-05-01'),
      ];
      // Kullanıcının değerlerini bozmadan bırakmak istiyorsak fonksiyonu
      // hiç çağırmamalıyız — çağırırsak beklenen davranış: overwrite.
      distributeDates(dests, '2026-05-01', '2026-05-06');
      expect(dests[0].arrivalDate, '2026-05-01');
      expect(dests[1].arrivalDate, '2026-05-04');
    });
  });
}
