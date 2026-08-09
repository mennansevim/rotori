// Rotori Eats sorgu + skorlama motoru birim testleri.
//
// Kritik davranışlar:
//   - free katman premium eksenleri UYGULAMAZ (motor ile UI aynı gerçeği
//     göstermeli — sessizce premium filtre çalıştırılmamalı),
//   - free katman `premiumOnly` kayıtları görmez,
//   - helal/vejetaryen filtresi SEVİYE eşiğidir, bool değil,
//   - skor bilinmeyen bileşenleri nötr puanlar (konum kapalı olan cezalanmaz).

import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/eats.dart';
import 'package:japan_trip/domain/eats_query.dart';
import 'package:japan_trip/domain/geofence.dart' show LatLng;
import 'package:japan_trip/domain/localized_text.dart';

EatsPlace _place({
  required String id,
  HalalTrust halal = HalalTrust.none,
  VeggieLevel veggie = VeggieLevel.none,
  double rating = 4.0,
  PriceTier tier = PriceTier.mid,
  int minJpy = 1000,
  int maxJpy = 2000,
  EatsCuisine cuisine = EatsCuisine.ramen,
  Set<EatsAmenity> amenities = const {},
  Set<MealSlot> slots = const {MealSlot.lunch, MealSlot.dinner},
  bool premiumOnly = false,
  double lat = 35.68,
  double lng = 139.76,
  String city = 'Tokyo',
}) {
  return EatsPlace(
    id: id,
    name: id,
    nameJa: id,
    city: city,
    area: 'Area',
    lat: lat,
    lng: lng,
    cuisine: cuisine,
    description: const LText('d', 'd'),
    signature: const LText('s', 's'),
    priceTier: tier,
    priceMinJpy: minJpy,
    priceMaxJpy: maxJpy,
    rating: rating,
    halal: halal,
    veggie: veggie,
    amenities: amenities,
    slots: slots,
    verifiedOn: '2026-07',
    mapsQuery: id,
    premiumOnly: premiumOnly,
  );
}

void main() {
  group('filtreleme', () {
    test('helal filtresi seviye eşiğidir — altındakiler elenir', () {
      final places = [
        _place(id: 'certified', halal: HalalTrust.certified),
        _place(id: 'friendly', halal: HalalTrust.muslimFriendly),
        _place(id: 'porkfree', halal: HalalTrust.porkFreeOption),
        _place(id: 'none'),
      ];

      final strict = runEatsQuery(
        places,
        query: const EatsQuery(minHalal: HalalTrust.certified),
      );
      expect(strict.map((r) => r.place.id), ['certified']);

      final relaxed = runEatsQuery(
        places,
        query: const EatsQuery(minHalal: HalalTrust.porkFreeOption),
      );
      expect(
        relaxed.map((r) => r.place.id).toSet(),
        {'certified', 'friendly', 'porkfree'},
      );
    });

    test('vejetaryen filtresi de seviye eşiğidir', () {
      final places = [
        _place(id: 'vegan', veggie: VeggieLevel.veganMenu),
        _place(id: 'option', veggie: VeggieLevel.veggieOption),
        _place(id: 'none'),
      ];
      final out = runEatsQuery(
        places,
        query: const EatsQuery(minVeggie: VeggieLevel.veganMenu),
      );
      expect(out.map((r) => r.place.id), ['vegan']);
    });

    test('kaçınılan olanak (nakit-only) sonucu eler', () {
      final places = [
        _place(id: 'cash', amenities: {EatsAmenity.cashOnly}),
        _place(id: 'card', amenities: {EatsAmenity.cardOk}),
      ];
      final out = runEatsQuery(
        places,
        query: const EatsQuery(avoidAmenities: {EatsAmenity.cashOnly}),
      );
      expect(out.map((r) => r.place.id), ['card']);
    });

    test('şart koşulan olanakların HEPSİ bulunmalı', () {
      final places = [
        _place(id: 'both', amenities: {EatsAmenity.cardOk, EatsAmenity.englishMenu}),
        _place(id: 'one', amenities: {EatsAmenity.cardOk}),
      ];
      final out = runEatsQuery(
        places,
        query: const EatsQuery(
          requiredAmenities: {EatsAmenity.cardOk, EatsAmenity.englishMenu},
        ),
      );
      expect(out.map((r) => r.place.id), ['both']);
    });

    test('mesafe filtresi konum yoksa hiçbir şeyi geçirmez', () {
      final places = [_place(id: 'a')];
      final out = runEatsQuery(
        places,
        query: const EatsQuery(maxDistanceKm: 1),
      );
      expect(out, isEmpty);
    });

    test('mesafe filtresi konum varken yarıçapı uygular', () {
      final places = [
        _place(id: 'near', lat: 35.6810, lng: 139.7670),
        _place(id: 'far', lat: 34.6690, lng: 135.5010),
      ];
      final out = runEatsQuery(
        places,
        query: const EatsQuery(maxDistanceKm: 5),
        context: const EatsContext(origin: LatLng(35.6812, 139.7671)),
      );
      expect(out.map((r) => r.place.id), ['near']);
    });
  });

  group('katman (free/premium)', () {
    test('free katman premiumOnly kayıtları göstermez', () {
      final places = [
        _place(id: 'public'),
        _place(id: 'curated', premiumOnly: true),
      ];
      final free = runEatsQuery(places, tier: EatsTier.free);
      expect(free.map((r) => r.place.id), ['public']);

      final paid = runEatsQuery(places, tier: EatsTier.premium);
      expect(paid.length, 2);
    });

    test('free katmanda premium filtre eksenleri UYGULANMAZ', () {
      final places = [
        _place(id: 'ramen', cuisine: EatsCuisine.ramen),
        _place(id: 'sushi', cuisine: EatsCuisine.sushi),
      ];
      // Premium eksen (mutfak) dolu; free'de düşürülmeli, iki sonuç da kalmalı.
      final free = runEatsQuery(
        places,
        query: const EatsQuery(cuisines: {EatsCuisine.ramen}),
        tier: EatsTier.free,
      );
      expect(free.length, 2);

      final paid = runEatsQuery(
        places,
        query: const EatsQuery(cuisines: {EatsCuisine.ramen}),
        tier: EatsTier.premium,
      );
      expect(paid.map((r) => r.place.id), ['ramen']);
    });

    test('free katmanda premium sıralama puana düşer', () {
      final places = [
        _place(id: 'cheapLowRating', rating: 3.5, minJpy: 500),
        _place(id: 'pricyHighRating', rating: 4.8, minJpy: 5000),
      ];
      final free = runEatsQuery(
        places,
        query: const EatsQuery(sort: EatsSort.priceLow),
        tier: EatsTier.free,
      );
      expect(free.first.place.id, 'pricyHighRating');
    });

    test('free katmanda diyet ve şehir filtreleri ÇALIŞIR', () {
      final places = [
        _place(id: 'tokyoHalal', halal: HalalTrust.certified, city: 'Tokyo'),
        _place(id: 'kyotoHalal', halal: HalalTrust.certified, city: 'Kyoto'),
        _place(id: 'tokyoPlain', city: 'Tokyo'),
      ];
      final out = runEatsQuery(
        places,
        query: const EatsQuery(
          minHalal: HalalTrust.certified,
          cities: {'Tokyo'},
        ),
        tier: EatsTier.free,
      );
      expect(out.map((r) => r.place.id), ['tokyoHalal']);
    });

    test('usesPremiumDims premium eksen dolduğunda true olur', () {
      expect(const EatsQuery(cities: {'Tokyo'}).usesPremiumDims, isFalse);
      expect(
        const EatsQuery(priceTiers: {PriceTier.budget}).usesPremiumDims,
        isTrue,
      );
      expect(const EatsQuery(sort: EatsSort.distance).usesPremiumDims, isTrue);
    });
  });

  group('sıralama', () {
    test('mesafe sıralamasında konumsuz sonuçlar sona düşer', () {
      final places = [
        _place(id: 'far', lat: 34.6690, lng: 135.5010),
        _place(id: 'near', lat: 35.6810, lng: 139.7670),
      ];
      final out = runEatsQuery(
        places,
        query: const EatsQuery(sort: EatsSort.distance),
        context: const EatsContext(origin: LatLng(35.6812, 139.7671)),
      );
      expect(out.map((r) => r.place.id), ['near', 'far']);
    });

    test('eşit puanlarda sıralama kararlıdır (id\'ye göre)', () {
      final places = [
        _place(id: 'b', rating: 4.0),
        _place(id: 'a', rating: 4.0),
      ];
      final out = runEatsQuery(places);
      expect(out.map((r) => r.place.id), ['a', 'b']);
    });
  });

  group('skorlama', () {
    int partValue(EatsScore s, EatsSignal signal) =>
        s.parts.firstWhere((p) => p.signal == signal).value;
    bool partKnown(EatsScore s, EatsSignal signal) =>
        s.parts.firstWhere((p) => p.signal == signal).known;

    test('helal isteyen kullanıcıda sertifikalı en yüksek diyet puanını alır', () {
      const ctx = EatsContext(dietTags: {'halal'});
      final certified = scoreEatsPlace(
        _place(id: 'c', halal: HalalTrust.certified),
        context: ctx,
      );
      final friendly = scoreEatsPlace(
        _place(id: 'f', halal: HalalTrust.muslimFriendly),
        context: ctx,
      );
      final none = scoreEatsPlace(_place(id: 'n'), context: ctx);

      expect(
        partValue(certified, EatsSignal.diet),
        greaterThan(partValue(friendly, EatsSignal.diet)),
      );
      expect(
        partValue(friendly, EatsSignal.diet),
        greaterThan(partValue(none, EatsSignal.diet)),
      );
      expect(partValue(none, EatsSignal.diet), 0);
    });

    // Bu davranış bilinçli olarak DEĞİŞTİ. Eskiden bilinmeyen bileşenlere
    // nötr puan veriliyordu (diyet 22, bütçe 12, mesafe 12) ve hiçbir tercih
    // girilmemiş bir gezide bile kendinden emin bir "65/100" çıkıyordu.
    test('bilinmeyen sinyal skora GİRMEZ, eksik olarak işaretlenir', () {
      final s = scoreEatsPlace(_place(id: 'a'));

      expect(partKnown(s, EatsSignal.diet), isFalse);
      expect(partKnown(s, EatsSignal.budget), isFalse);
      expect(partKnown(s, EatsSignal.distance), isFalse);
      expect(partKnown(s, EatsSignal.rating), isTrue);

      expect(s.knownCount, 1);
      expect(s.missingSignals, hasLength(3));
      // Diyet ve bütçe yoksa ortada kişiselleştirilmiş bir şey yok.
      expect(s.isPersonalized, isFalse);
    });

    test('skor yalnızca bilinen sinyaller üzerinden normalize edilir', () {
      // Sadece puan biliniyor: 4.0 → (4-3)/2*25 = 12.5 → 13; 13/25 = %52.
      final s = scoreEatsPlace(_place(id: 'a', rating: 4.0));
      expect(s.score, closeTo(52, 2));
    });

    test('tercih girilince kişiselleştirilmiş sayılır', () {
      final s = scoreEatsPlace(
        _place(id: 'a', halal: HalalTrust.certified),
        context: const EatsContext(dietTags: {'halal'}),
      );
      expect(s.isPersonalized, isTrue);
      expect(s.knownCount, 2);
    });

    test('bütçe içindeki mekan tam bütçe puanı alır', () {
      const ctx = EatsContext(mealBudgetJpy: 3000);
      final inBudget = scoreEatsPlace(
        _place(id: 'in', minJpy: 900, maxJpy: 1800),
        context: ctx,
      );
      final overBudget = scoreEatsPlace(
        _place(id: 'over', minJpy: 8000, maxJpy: 14000),
        context: ctx,
      );
      expect(partValue(inBudget, EatsSignal.budget), 20);
      expect(
        partValue(overBudget, EatsSignal.budget),
        lessThan(partValue(inBudget, EatsSignal.budget)),
      );
      expect(inBudget.isPersonalized, isTrue);
    });

    test('skor 0–100 aralığında kalır', () {
      const ctx = EatsContext(
        dietTags: {'halal'},
        mealBudgetJpy: 20000,
        partyHasKids: true,
        nowSlot: MealSlot.lunch,
        origin: LatLng(35.6810, 139.7670),
      );
      final s = scoreEatsPlace(
        _place(
          id: 'max',
          halal: HalalTrust.certified,
          rating: 5.0,
          amenities: {EatsAmenity.kidFriendly},
          lat: 35.6811,
          lng: 139.7671,
        ),
        context: ctx,
        distanceKm: 0.05,
      );
      expect(s.score, inInclusiveRange(0, 100));
      expect(s.knownCount, 4);
      expect(s.missingSignals, isEmpty);
    });

    test('tüm sinyaller bilinmiyorken sıralama yine tutarlı kalır', () {
      // Normalize payda tüm mekanlarda aynı olduğu için göreli sıra bozulmaz.
      final high = scoreEatsPlace(_place(id: 'h', rating: 4.8));
      final low = scoreEatsPlace(_place(id: 'l', rating: 3.6));
      expect(high.score, greaterThan(low.score));
    });
  });

  group('pickEatsNow', () {
    test('öğün dilimi çok daraltırsa kısıtı gevşetip yine öneri döner', () {
      final places = [
        _place(id: 'a', slots: {MealSlot.lunch}),
        _place(id: 'b', slots: {MealSlot.lunch}),
        _place(id: 'c', slots: {MealSlot.lunch}),
      ];
      // Gece geç saatte hiçbiri açık değil; motor yine de öneri üretmeli.
      final picks = pickEatsNow(
        places,
        context: const EatsContext(nowSlot: MealSlot.lateNight),
      );
      expect(picks, isNotEmpty);
      expect(picks.length, lessThanOrEqualTo(kEatsPickCount));
    });

    test('en fazla kEatsPickCount öneri döner', () {
      final places = [
        for (var i = 0; i < 10; i++) _place(id: 'p$i'),
      ];
      final picks = pickEatsNow(
        places,
        context: const EatsContext(nowSlot: MealSlot.lunch),
      );
      expect(picks.length, kEatsPickCount);
    });
  });

  group('küratörlü veri bütünlüğü', () {
    test('id\'ler benzersiz', () {
      final ids = kEatsPlaces.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('fiyat aralığı tutarlı ve kademesiyle uyumlu', () {
      for (final p in kEatsPlaces) {
        expect(p.priceMinJpy, lessThanOrEqualTo(p.priceMaxJpy), reason: p.id);
        expect(p.priceMinJpy, greaterThan(0), reason: p.id);
      }
    });

    test('her mekanın en az bir servis dilimi ve koordinatı var', () {
      for (final p in kEatsPlaces) {
        expect(p.slots, isNotEmpty, reason: p.id);
        expect(p.lat, isNot(0), reason: p.id);
        expect(p.lng, isNot(0), reason: p.id);
      }
    });

    test('nakit-only ve kart-geçer aynı anda işaretlenmemiş', () {
      for (final p in kEatsPlaces) {
        final contradiction = p.amenities.contains(EatsAmenity.cashOnly) &&
            p.amenities.contains(EatsAmenity.cardOk);
        expect(contradiction, isFalse, reason: p.id);
      }
    });

    test('helal sertifikalı mekanların hepsinde doğrulama tarihi var', () {
      for (final p in kEatsPlaces.where((p) => p.halal == HalalTrust.certified)) {
        expect(p.verifiedOn, matches(RegExp(r'^\d{4}-\d{2}$')), reason: p.id);
      }
    });

    test('her diyet ekseninde ücretsiz katmanı dolduracak kadar mekan var', () {
      for (final q in [
        const EatsQuery(minHalal: HalalTrust.muslimFriendly),
        const EatsQuery(minVeggie: VeggieLevel.veggieOption),
        const EatsQuery(),
      ]) {
        final out = runEatsQuery(kEatsPlaces, query: q, tier: EatsTier.free);
        expect(out.length, greaterThanOrEqualTo(kEatsFreeVisibleLimit),
            reason: q.activeDims.toString());
      }
    });
  });
}
