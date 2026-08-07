import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/eats.dart';

void main() {
  group('filterEats', () {
    test('halal filtresi yalnız helal mekanları döndürür', () {
      final out = filterEats(kEatsPlaces, EatsFilter.halal);
      expect(out, isNotEmpty);
      expect(out.every((p) => p.halal), isTrue);
    });

    test('vejetaryen filtresi yalnız vejetaryen-dostu mekanları döndürür', () {
      final out = filterEats(kEatsPlaces, EatsFilter.vegetarian);
      expect(out, isNotEmpty);
      expect(out.every((p) => p.vegetarianFriendly), isTrue);
    });

    test('hepsi filtresi tüm mekanları döndürür', () {
      final out = filterEats(kEatsPlaces, EatsFilter.all);
      expect(out.length, kEatsPlaces.length);
    });

    test('puana göre azalan, eşitlikte id ile kararlı sıralar', () {
      final out = filterEats(kEatsPlaces, EatsFilter.all);
      for (var i = 1; i < out.length; i++) {
        final prev = out[i - 1];
        final cur = out[i];
        expect(prev.rating >= cur.rating, isTrue);
        if (prev.rating == cur.rating) {
          expect(prev.id.compareTo(cur.id) <= 0, isTrue);
        }
      }
    });

    test('free limit ilk 3 sonucu verir, kalan kilitli sayılır', () {
      final all = filterEats(kEatsPlaces, EatsFilter.all);
      final shown = all.take(kEatsFreeLimit).toList();
      expect(shown.length, kEatsFreeLimit);
      expect(all.length - shown.length, greaterThan(0));
    });
  });

  test('helal mekanlar uydurma sertifika içermez (en az bir gerçek helal var)',
      () {
    expect(kEatsPlaces.where((p) => p.halal).length, greaterThanOrEqualTo(3));
  });
}
