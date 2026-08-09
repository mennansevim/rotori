// googleFlightsUrl + formatTrShortDate — saf tarih/URL testleri.
//
// Kaynak: test/features/welcome_flow_test.dart (wizard sökülürken
// lib/core/date_format.dart ile birlikte buraya taşındı).

import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/core/date_format.dart';
import 'package:japan_trip/core/l10n.dart' show AppLang;

void main() {
  group('googleFlightsUrl', () {
    test('beklenen deep-link biçimini üretir', () {
      final url = googleFlightsUrl(
        from: 'İzmir',
        toIata: 'NRT',
        start: DateTime(2027, 8, 23),
        end: DateTime(2027, 8, 31),
      );
      // q parametresinin URL-encode edilmesi bekleniyor.
      expect(
        url,
        'https://www.google.com/travel/flights?q='
        '${Uri.encodeComponent('Flights from İzmir to NRT on 2027-08-23 through 2027-08-31')}',
      );
      expect(
          url.startsWith('https://www.google.com/travel/flights?q='), isTrue);
    });
  });

  group('formatTrShortDate', () {
    test('"gün Ay-kısa Gün-kısa" biçiminde döndürür', () {
      // 2026-08-23 → Pazar (Paz)
      expect(formatTrShortDate(DateTime(2026, 8, 23)), '23 Ağu Paz');
      // 2027-08-23 → Pazartesi (Pzt)
      expect(formatTrShortDate(DateTime(2027, 8, 23)), '23 Ağu Pzt');
    });
  });

  group('formatShortDate (dil duyarlı)', () {
    test('TR ve EN farklı biçim üretir', () {
      expect(formatShortDate('2026-08-23', AppLang.tr), '23 Ağu Paz');
      expect(formatShortDate('2026-08-23', AppLang.en), 'Sun 23 Aug');
    });

    test('geçersiz girdi olduğu gibi döner', () {
      expect(formatShortDate('', AppLang.tr), '');
      expect(formatShortDate('abc', AppLang.tr), 'abc');
    });
  });
}
