// plan_generation.dart — "şehir + tarih → dolu plan" sözleşmesinin testleri.
//
// Widget yok, hızlı. Yeni oluşturma akışının doğruluğu buraya yaslanıyor.

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/activity_identity.dart';
import 'package:rotori/domain/city_places.dart';
import 'package:rotori/domain/destination_profiles.dart';
import 'package:rotori/domain/itinerary_generator.dart'
    show kDayEndMinutes, kDayStartMinutes;
import 'package:rotori/domain/japan_suggestions.dart';
import 'package:rotori/domain/plan_generation.dart';
import 'package:rotori/domain/trip_factory.dart';
import 'package:rotori/domain/types.dart';

void main() {
  const start = '2026-10-01';
  const end = '2026-10-07'; // 7 gün (dahil)

  group('buildTripFromCities', () {
    test('tek şehir — her gün dolu plan üretir', () {
      final trip = buildTripFromCities(
        cityKeys: const ['tokyo'],
        startYmd: start,
        endYmd: end,
      );

      expect(trip.days.length, 7);
      for (final d in trip.days) {
        expect(d.items, isNotEmpty, reason: 'Gün ${d.dayNumber} boş kaldı');
      }
    });

    test('iki şehir — ikisine de gün düşer', () {
      final trip = buildTripFromCities(
        cityKeys: const ['tokyo', 'kyoto'],
        startYmd: start,
        endYmd: end,
      );
      final dests = trip.preferences.destinations;
      expect(dests.length, 2);

      final covered = <String>{};
      for (final d in trip.days) {
        final dd = getDestinationForDate(dests, d.date);
        if (dd != null) covered.add(dd.city);
      }
      expect(covered, containsAll(<String>['Tokyo', 'Kyoto']));
    });

    test('üç şehir — şehirler arası Shinkansen/tren transferi eklenir', () {
      final trip = buildTripFromCities(
        cityKeys: const ['tokyo', 'kyoto', 'osaka'],
        startYmd: '2026-10-01',
        endYmd: '2026-10-12',
      );

      // applyCityTransitions "A → B" başlıklı transport item'ları ekler.
      final cityHops = trip.days
          .expand((d) => d.items)
          .where((i) =>
              i.kind == TimelineItemKind.transport && i.title.contains('→'))
          .map((i) => i.title)
          .toList();

      expect(cityHops.length, greaterThanOrEqualTo(2),
          reason: 'Tokyo→Kyoto ve Kyoto→Osaka geçişleri bekleniyordu, '
              'bulunan: $cityHops');
      expect(cityHops.any((t) => t.contains('Kyoto')), isTrue);
    });

    test('countryCode daima JP, city daima kCityData.label', () {
      final trip = buildTripFromCities(
        cityKeys: const ['tokyo', 'nara', 'hiroshima'],
        startYmd: start,
        endYmd: end,
      );
      final labels = kCityData.map((c) => c.label).toSet();
      for (final d in trip.preferences.destinations) {
        expect(d.countryCode, 'JP');
        expect(labels, contains(d.city));
      }
    });

    test('order 0..n-1, seçim sırası korunur', () {
      final trip = buildTripFromCities(
        cityKeys: const ['osaka', 'tokyo'],
        startYmd: start,
        endYmd: end,
      );
      final dests = [...trip.preferences.destinations]
        ..sort((a, b) => a.order.compareTo(b.order));
      expect(dests.map((d) => d.city).toList(), ['Osaka', 'Tokyo']);
      expect(dests.map((d) => d.order).toList(), [0, 1]);
    });

    test('bilinmeyen şehir anahtarı sessizce atlanır', () {
      final trip = buildTripFromCities(
        cityKeys: const ['tokyo', 'atlantis'],
        startYmd: start,
        endYmd: end,
      );
      expect(trip.preferences.destinations.length, 1);
      expect(trip.preferences.destinations.single.city, 'Tokyo');
    });

    test('datesEstimated bayrağı trip\'e yazılır', () {
      final trip = buildTripFromCities(
        cityKeys: const ['tokyo'],
        startYmd: start,
        endYmd: end,
        datesEstimated: true,
      );
      expect(trip.preferences.datesEstimated, isTrue);
      // JSON round-trip'te de korunmalı.
      expect(trip.toJson()['preferences']['datesEstimated'], isTrue);
    });

    test('otel transferi varış saati, süre ve ulaşım türlerini gösterir', () {
      final trip = buildTripFromCities(
        cityKeys: const ['tokyo'],
        startYmd: start,
        endYmd: end,
      );
      final transfer = trip.days.first.items.firstWhere(
        (item) => item.title.contains('Otele transfer'),
      );

      expect(transfer.description, contains('varış'));
      expect(transfer.description, contains('60 dk'));
      expect(transfer.description, contains('Tren'));
      expect(transfer.description, contains('Otobüs'));
      expect(transfer.description, contains('Taksi'));
      expect(transfer.description, isNot(contains('Airport Limousine')));
      expect(transfer.description, isNot(contains('Narita Express')));
    });

    test('mekan süresi ve açılış saatleri rota verisine taşınır', () {
      final trip = buildTripFromCities(
        cityKeys: const ['tokyo'],
        startYmd: start,
        endYmd: end,
      );
      final activity = trip.days
          .expand((day) => day.items)
          .firstWhere((item) => item.title.contains('Tokyo Skytree'));

      expect(activity.durationMin, isNotNull);
      expect(activity.openingTime, '10:00');
      expect(activity.closingTime, '21:00');
      final restored = TimelineItem.fromJson(activity.toJson());
      expect(restored.openingTime, activity.openingTime);
      expect(restored.closingTime, activity.closingTime);
    });

    test('aynı mekan alias adı ve katalog kimliğiyle ardışık güne gelemez', () {
      expect(
        canonicalPlaceIdentity(
          title: '🎢 Universal Studios Japan',
          placeId: 'usj',
          cityId: 'Osaka',
        ),
        canonicalPlaceIdentity(
          title: '🎢 Universal Studios',
          placeId: 'os-usj',
          cityId: 'Osaka',
        ),
      );

      final trip = buildTripFromCities(
        cityKeys: const ['osaka'],
        startYmd: '2026-10-01',
        endYmd: '2026-10-14',
      );
      expect(
        findConsecutiveActivityDuplicates(trip.days),
        isEmpty,
        reason: 'Gerçek üretim hattı ardışık gün mekan tekrarı üretemez.',
      );
      final usj = trip.days
          .expand((day) => day.items)
          .where((item) =>
              canonicalPlaceIdentity(
                title: item.title,
                placeId: item.placeId,
                cityId: item.cityId,
              ) ==
              'osaka:usj')
          .toList();
      expect(usj, hasLength(1));
      expect(TimelineItem.fromJson(usj.single.toJson()).placeId, isNotNull);
    });
  });

  group('previewCityDistribution', () {
    test('toplam == toplam gün sayısı', () {
      final preview = previewCityDistribution(
        const ['tokyo', 'kyoto'],
        start,
        end,
      );
      final total = preview.fold<int>(0, (n, c) => n + c.days);
      expect(total, inclusiveDays(start, end));
    });

    test('önizleme GERÇEK üretimle birebir aynı — yalan söylemiyor', () {
      const keys = ['tokyo', 'kyoto', 'osaka'];
      const s = '2026-10-01';
      const e = '2026-10-10';

      final preview = previewCityDistribution(keys, s, e);

      // Aynı girdiyle gerçek trip üret, gün→şehir eşleşmesini say.
      final trip = buildTripFromCities(cityKeys: keys, startYmd: s, endYmd: e);
      final dests = trip.preferences.destinations;
      final actual = <String, int>{};
      for (final d in trip.days) {
        final dd = getDestinationForDate(dests, d.date);
        if (dd != null) actual[dd.city] = (actual[dd.city] ?? 0) + 1;
      }

      for (final c in preview) {
        expect(c.days, actual[c.label] ?? 0,
            reason:
                '${c.label}: önizleme ${c.days}, gerçek ${actual[c.label]}');
      }
    });

    test('emoji ve etiket kCityData\'dan gelir', () {
      final preview = previewCityDistribution(const ['tokyo'], start, end);
      final tokyo = kCityData.firstWhere((c) => c.key == 'tokyo');
      expect(preview.single.label, tokyo.label);
      expect(preview.single.emoji, tokyo.emoji);
    });
  });

  group('suggestDateRange', () {
    test('şehir başına ~3 gece, 5-14 arasına kırpılır', () {
      final one = suggestDateRange(cityCount: 1, now: DateTime(2026, 1, 1));
      expect(inclusiveDays(one.start, one.end), 6); // 5 gece + 1

      final three = suggestDateRange(cityCount: 3, now: DateTime(2026, 1, 1));
      expect(inclusiveDays(three.start, three.end), 10); // 9 gece + 1

      final many = suggestDateRange(cityCount: 9, now: DateTime(2026, 1, 1));
      expect(inclusiveDays(many.start, many.end), 15); // 14 gece + 1
    });

    test('gelecekteki ilk iyi sezonu seçer', () {
      final r = suggestDateRange(cityCount: 2, now: DateTime(2026, 1, 1));
      final s = DateTime.parse(r.start);
      expect(s.isAfter(DateTime(2026, 1, 1)), isTrue);
      // kSuggestedRanges'teki ilk 'good' kayıt 2026-10-15.
      expect(r.start, '2026-10-15');
    });

    test('sezon listesi tükendiğinde bugün+90 fallback', () {
      final now = DateTime(2030, 1, 1);
      final r = suggestDateRange(cityCount: 2, now: now);
      expect(DateTime.parse(r.start), now.add(const Duration(days: 90)));
    });
  });

  group('tripHasFlightInfo', () {
    test('boş trip false — createEmptyTrip boş bacaklar üretiyor', () {
      // outbound.isNotEmpty yeterli olsaydı burası true dönerdi; tuzak bu.
      final trip = createEmptyTrip();
      expect(trip.flights.outbound, isNotEmpty);
      expect(tripHasFlightInfo(trip), isFalse);
    });

    test('yeni üretilen plan false — kullanıcı henüz uçuş girmedi', () {
      final trip = buildTripFromCities(
        cityKeys: const ['tokyo'],
        startYmd: start,
        endYmd: end,
      );
      expect(tripHasFlightInfo(trip), isFalse);
    });

    test('şehir + havaalanı dolunca true', () {
      final trip = createEmptyTrip();
      trip.flights.outbound.first
        ..city = 'İstanbul'
        ..airport = 'IST';
      expect(tripHasFlightInfo(trip), isTrue);
    });
  });

  group('içerik kalitesi (A: tekrar koruması, B: ağırlıklı dağılım)', () {
    test('tek şablonlu şehirde (Kyoto) ardışık günler aynı temayı tekrarlamaz',
        () {
      // Kyoto'nun yalnızca 1 gün şablonu var — eski algoritma
      // (seq % templateCount) her Kyoto gününe AYNI şablonu veriyordu.
      final trip = buildTripFromCities(
        cityKeys: const ['tokyo', 'kyoto'],
        startYmd: '2026-10-15',
        endYmd: '2026-10-21', // 7 gün
      );
      final themes = trip.days.map((d) => d.theme).toList();
      expect(themes.toSet().length, themes.length,
          reason: 'Tekrarlanan tema(lar) var: $themes');
    });

    test(
        'ikinci şehir (az şablonlu) gerçek bir gezi günü alır, '
        'sadece ayrılış gününe sıkışmaz', () {
      final trip = buildTripFromCities(
        cityKeys: const ['tokyo', 'kyoto'],
        startYmd: '2026-10-15',
        endYmd: '2026-10-21',
      );
      final dests = trip.preferences.destinations;
      final kyotoDays = trip.days
          .where((d) => getDestinationForDate(dests, d.date)?.city == 'Kyoto')
          .length;
      // Kyoto en az 2 gün almalı (1 içerik günü + ayrılış), sadece 1 değil.
      expect(kyotoDays, greaterThanOrEqualTo(2));
    });

    test(
        'içerik zengin şehir (Tokyo, 4 şablon) daha çok gün alır ama '
        'ağırlık ham şablon oranı kadar keskin değildir', () {
      final dist = previewCityDistribution(
        const ['tokyo', 'kyoto'],
        '2026-10-15',
        '2026-10-21', // 7 gün
      );
      final tokyo = dist.firstWhere((c) => c.label == 'Tokyo').days;
      final kyoto = dist.firstWhere((c) => c.label == 'Kyoto').days;
      expect(tokyo, greaterThan(kyoto)); // Tokyo hâlâ daha fazla
      expect(kyoto, greaterThanOrEqualTo(2)); // ama Kyoto ezilmiyor
      expect(tokyo + kyoto, 7);
    });

    test('_weightedDaySplit dolaylı: eşit ağırlıklı şehirler eşit gün alır',
        () {
      // Sapporo ve Kanazawa'nın ikisi de şablonsuz, benzer yer sayısına
      // sahip → dağılım birbirine yakın olmalı (kör 50/50'den sapmamalı).
      final dist = previewCityDistribution(
          const ['sapporo', 'kanazawa'], '2026-10-01', '2026-10-07');
      final days = dist.map((c) => c.days).toList();
      expect((days[0] - days[1]).abs(), lessThanOrEqualTo(1));
    });
  });

  group('kullanıcı gün dağılımı (dayOverrides)', () {
    test('suggestedDaySplit toplamı gün sayısına eşit', () {
      final split = suggestedDaySplit(const ['tokyo', 'kyoto'], start, end);
      expect(split.values.fold<int>(0, (a, b) => a + b),
          inclusiveDays(start, end));
      expect(split.keys, containsAll(<String>['tokyo', 'kyoto']));
    });

    test('override aynen uygulanır — önizleme ve üretim ikisi de uyar', () {
      const override = {'tokyo': 2, 'kyoto': 5}; // önerilenin tersi
      final preview = previewCityDistribution(
        const ['tokyo', 'kyoto'],
        start,
        end,
        dayOverrides: override,
      );
      expect(preview.firstWhere((c) => c.label == 'Tokyo').days, 2);
      expect(preview.firstWhere((c) => c.label == 'Kyoto').days, 5);

      final trip = buildTripFromCities(
        cityKeys: const ['tokyo', 'kyoto'],
        startYmd: start,
        endYmd: end,
        dayOverrides: override,
      );
      final dests = trip.preferences.destinations;
      final actual = <String, int>{};
      for (final d in trip.days) {
        final dd = getDestinationForDate(dests, d.date);
        if (dd != null) actual[dd.city] = (actual[dd.city] ?? 0) + 1;
      }
      expect(actual['Tokyo'], 2);
      expect(actual['Kyoto'], 5);
    });

    test('toplamı tutmayan override yok sayılır, ağırlıklı dağılıma düşer', () {
      const bad = {'tokyo': 1, 'kyoto': 1}; // toplam 2 ≠ 7
      final preview = previewCityDistribution(
        const ['tokyo', 'kyoto'],
        start,
        end,
        dayOverrides: bad,
      );
      expect(preview.fold<int>(0, (a, c) => a + c.days), 7);
    });
  });

  group('planlama penceresi 09:00-20:00', () {
    test('hiçbir aktivite 09:00 öncesine ya da 20:00 sonrasına düşmez', () {
      for (final keys in [
        const ['tokyo'],
        const ['tokyo', 'kyoto', 'osaka'],
        const ['nara', 'hiroshima'],
      ]) {
        final trip = buildTripFromCities(
          cityKeys: keys,
          startYmd: '2026-10-15',
          endYmd: '2026-10-24',
        );
        for (final d in trip.days) {
          for (final i in d.items) {
            // Varış/dönüş günü uçuş saatine bağlıdır — pencere dışı olabilir.
            if (i.kind == TimelineItemKind.transport) continue;
            final t = i.time ?? i.scheduledTime;
            if (t == null || !t.contains(':')) continue;
            final parts = t.split(':');
            final min = int.parse(parts[0]) * 60 + int.parse(parts[1]);
            final isFirstOrLast =
                d.dayNumber == 1 || d.dayNumber == trip.days.length;
            if (isFirstOrLast) continue;
            expect(min, greaterThanOrEqualTo(kDayStartMinutes),
                reason: 'G${d.dayNumber} "${i.title}" $t çok erken');
            expect(min, lessThanOrEqualTo(kDayEndMinutes),
                reason: 'G${d.dayNumber} "${i.title}" $t çok geç');
          }
        }
      }
    });

    test('erken kapanan yer geç slota yerleştirilmez', () {
      // Kuromon Market 09-17 arası açık; 17:00'den sonra planlanmamalı.
      final trip = buildTripFromCities(
        cityKeys: const ['osaka'],
        startYmd: '2026-10-15',
        endYmd: '2026-10-22',
      );
      for (final d in trip.days) {
        for (final i in d.items) {
          if (!i.title.toLowerCase().contains('kuromon')) continue;
          final t = i.time ?? i.scheduledTime ?? '';
          final parts = t.split(':');
          final min = int.parse(parts[0]) * 60 + int.parse(parts[1]);
          expect(min + 90, lessThanOrEqualTo(17 * 60),
              reason: 'Kuromon kapanıştan sonra planlandı: $t');
        }
      }
    });

    test('visitWindow çalışma saatini gün penceresiyle kesiştirir', () {
      const market = PlaceSuggestion(
        id: 'x',
        name: 'X',
        city: 'Osaka',
        emoji: '🍣',
        category: 'food',
        openHour: 9,
        closeHour: 17,
      );
      final (s2, e2) = market.visitWindow(kDayStartMinutes, kDayEndMinutes);
      expect(s2, 9 * 60);
      expect(e2, 17 * 60); // kapanış 20:00'den önce → kapanış kazanır

      const allDay = PlaceSuggestion(
        id: 'y',
        name: 'Y',
        city: 'Kyoto',
        emoji: '⛩️',
        category: 'culture',
      );
      final (s3, e3) = allDay.visitWindow(kDayStartMinutes, kDayEndMinutes);
      expect(s3, kDayStartMinutes);
      expect(e3, kDayEndMinutes);
    });
  });

  group('sınırlar', () {
    test('şehir sayısı gün sayısını aşınca en az bir şehir 0 gün alır', () {
      // Bilinen sınır: distributeDates slice'ı klipliyor. UI bu durumda
      // üretim butonunu kilitler; burada davranış kayıt altına alınıyor.
      final preview = previewCityDistribution(
        const ['tokyo', 'kyoto', 'osaka', 'nara', 'hiroshima'],
        '2026-10-01',
        '2026-10-03', // 3 gün, 5 şehir
      );
      expect(preview.any((c) => c.days == 0), isTrue);
    });

    test('boş şehir listesi — üretim çökmüyor', () {
      final preview = previewCityDistribution(const [], start, end);
      expect(preview, isEmpty);
    });

    test('geçersiz tarih aralığı inclusiveDays 0 döner', () {
      expect(inclusiveDays('', ''), 0);
      expect(inclusiveDays('2026-10-10', '2026-10-01'), 0);
    });
  });
}
