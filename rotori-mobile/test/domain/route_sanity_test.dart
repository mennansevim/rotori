// Rota tutarlılık kontrolü — mantıksız şehir sırasını yakalar, mantıklı
// olanda susar (yanlış alarm kartı değersizleştirir).

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/city_places.dart';
import 'package:rotori/domain/route_sanity.dart';

void main() {
  group('cityCenter', () {
    test('her küratörlü şehir için merkez döner', () {
      for (final c in kCityData) {
        expect(cityCenter(c.key), isNotNull, reason: '${c.key} merkezsiz');
      }
    });

    test('bilinmeyen anahtar null', () {
      expect(cityCenter('atlantis'), isNull);
    });

    test('merkez Japonya sınırları içinde', () {
      for (final c in kCityData) {
        final center = cityCenter(c.key)!;
        expect(center.$1, inInclusiveRange(24, 46), reason: '${c.key} enlem');
        expect(center.$2, inInclusiveRange(122, 146), reason: '${c.key} boylam');
      }
    });
  });

  group('mantıksız rotayı yakalar', () {
    test('Kansai turunun ortasına Sapporo girerse uyarır', () {
      // Kullanıcının bildirdiği durum: araya uzak bir şehir sıkışıyor.
      final r = checkRouteOrder(const ['tokyo', 'nara', 'sapporo', 'kyoto']);
      expect(r.hasSuggestion, isTrue);
      expect(r.savedKm, greaterThan(500));
      // Sapporo sona atılmalı — arada kalmamalı.
      expect(r.suggestedOrder.last, 'sapporo');
    });

    test('yol üstündeki şehir atlanırsa uyarır', () {
      // Hakone Tokyo-Osaka arasında; sona bırakmak gereksiz gidiş-dönüş.
      final r = checkRouteOrder(const ['tokyo', 'osaka', 'hakone']);
      expect(r.hasSuggestion, isTrue);
      expect(r.suggestedOrder, ['tokyo', 'hakone', 'osaka']);
    });

    test('ilk şehir DEĞİŞMEZ — kullanıcı oraya uçuyor', () {
      for (final route in [
        const ['sapporo', 'osaka', 'tokyo'],
        const ['fukuoka', 'tokyo', 'kyoto'],
        const ['okinawa', 'sapporo', 'tokyo'],
      ]) {
        final r = checkRouteOrder(route);
        expect(r.suggestedOrder.first, route.first,
            reason: '${route.first} başlangıç olmaktan çıkarıldı');
      }
    });
  });

  group('mantıklı rotada susar', () {
    test('zaten optimal Kansai sırası uyarı üretmez', () {
      final r = checkRouteOrder(const ['tokyo', 'kyoto', 'osaka', 'nara']);
      expect(r.hasSuggestion, isFalse,
          reason: 'küçük fark için uyarmak kartı değersizleştirir');
    });

    test('tek şehir', () {
      final r = checkRouteOrder(const ['tokyo']);
      expect(r.hasSuggestion, isFalse);
      expect(r.suggestedOrder, ['tokyo']);
    });

    test('iki şehirde "yanlış sıra" yoktur', () {
      final r = checkRouteOrder(const ['sapporo', 'okinawa']);
      expect(r.hasSuggestion, isFalse);
      expect(r.suggestedOrder, ['sapporo', 'okinawa']);
    });

    test('bilinmeyen şehirler çökertmez', () {
      final r = checkRouteOrder(const ['tokyo', 'atlantis', 'kyoto']);
      expect(r.suggestedOrder, isNotEmpty);
    });

    test('boş liste', () {
      final r = checkRouteOrder(const []);
      expect(r.hasSuggestion, isFalse);
      expect(r.suggestedOrder, isEmpty);
    });
  });

  group('öneri gerçekten daha kısa', () {
    test('önerilen sıra hiçbir zaman mevcut sıradan uzun değildir', () {
      for (final route in [
        const ['tokyo', 'sapporo', 'kyoto', 'fukuoka'],
        const ['osaka', 'tokyo', 'hiroshima', 'nara', 'kobe'],
        const ['kyoto', 'hakodate', 'nara', 'okinawa', 'tokyo', 'kobe'],
      ]) {
        final r = checkRouteOrder(route);
        expect(r.suggestedKm, lessThanOrEqualTo(r.currentKm + 0.001),
            reason: '${route.join(">")} için öneri daha uzun');
      }
    });

    test('öneri aynı şehir kümesini korur — şehir eklemez/silmez', () {
      const route = ['tokyo', 'sapporo', 'kyoto', 'fukuoka', 'nara'];
      final r = checkRouteOrder(route);
      expect(r.suggestedOrder.toSet(), route.toSet());
      expect(r.suggestedOrder.length, route.length);
    });

    test('çok şehirli rotada da makul sürede sonuç verir (sezgisel dal)', () {
      // 10 şehir → permütasyon imkânsız, sezgisel dal çalışmalı.
      const route = [
        'tokyo', 'sapporo', 'kyoto', 'fukuoka', 'nara',
        'osaka', 'kobe', 'hiroshima', 'nagoya', 'yokohama',
      ];
      final r = checkRouteOrder(route);
      expect(r.suggestedOrder.toSet(), route.toSet());
      expect(r.suggestedKm, lessThanOrEqualTo(r.currentKm + 0.001));
    });
  });
}
