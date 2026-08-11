import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/data/affiliate_links.dart';

void main() {
  final links = [
    ...kPreDepartureAffiliates,
    journeyAffiliate,
    hotelAffiliate,
  ];

  test('external recommendation links use safe canonical HTTPS targets', () {
    for (final link in links) {
      final uri = Uri.parse(link.url);

      expect(uri.scheme, 'https', reason: link.url);
      expect(uri.host, isNotEmpty, reason: link.url);
      expect(uri.userInfo, isEmpty, reason: link.url);
      expect(uri.fragment, isEmpty, reason: link.url);
      expect(uri.toString().toLowerCase(), isNot(contains('/affiliate/')),
          reason: link.url);
      expect(uri.toString().toLowerCase(), isNot(contains('rotori')),
          reason: 'Unissued vanity/tracking IDs must not ship: ${link.url}');
    }
  });

  test('recommendation catalog points at the reviewed provider pages', () {
    expect(
      links.map((link) => link.url).toSet(),
      {
        'https://smart-ex.jp/',
        'https://esim.io/destinations/esim-japan',
        'https://www.booking.com/country/jp.html',
        'https://www.klook.com/destination/co1012-japan/',
        'https://www.klook.com/airport-transfers/',
        'https://japanrailpass.net/en/',
      },
    );
  });
}
