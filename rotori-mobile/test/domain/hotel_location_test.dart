// Gün → otel eşleşmesi ve Google Maps linkinden koordinat çıkarma.
//
// Kritik davranış: koordinat ÇÖZÜLEMEZSE null dönmeli. Şehir merkezine
// düşmek, oteli yanlış yerde göstermek demektir — kullanıcı sabah oraya
// yürümeye kalkar.

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/hotel_location.dart';
import 'package:rotori/domain/types.dart';

HotelStay _hotel({
  required String id,
  required String checkIn,
  required String checkOut,
  String city = 'Tokyo',
  String name = 'Test Hotel',
  String address = '',
  String? mapsUrl,
}) =>
    HotelStay(
      id: id,
      city: city,
      name: name,
      checkIn: checkIn,
      checkOut: checkOut,
      address: address,
      mapsUrl: mapsUrl,
    );

void main() {
  group('hotelForDate', () {
    final tokyo = _hotel(id: 'a', checkIn: '2026-10-15', checkOut: '2026-10-18');
    final kyoto = _hotel(
      id: 'b',
      city: 'Kyoto',
      checkIn: '2026-10-18',
      checkOut: '2026-10-21',
    );
    final hotels = [tokyo, kyoto];

    test('konaklamanın ortasındaki gün doğru oteli verir', () {
      expect(hotelForDate(hotels, '2026-10-16')?.id, 'a');
      expect(hotelForDate(hotels, '2026-10-19')?.id, 'b');
    });

    test('giriş günü o otele sayılır', () {
      expect(hotelForDate(hotels, '2026-10-15')?.id, 'a');
    });

    test('şehir değişim gününde YENİ otel kazanır', () {
      // 18'inde Tokyo'dan çıkış, Kyoto'ya giriş var. O gün Kyoto'da
      // uyunacağı için gün Kyoto oteline aittir.
      expect(hotelForDate(hotels, '2026-10-18')?.id, 'b');
    });

    test('son çıkış gününde hâlâ o otelden çıkılır', () {
      // 21'inde konaklama yok ama sabah Kyoto otelinden çıkılıyor.
      expect(hotelForDate(hotels, '2026-10-21')?.id, 'b');
    });

    test('kapsam dışı tarih ve boş liste null döner', () {
      expect(hotelForDate(hotels, '2026-09-01'), isNull);
      expect(hotelForDate(const [], '2026-10-16'), isNull);
      expect(hotelForDate(hotels, ''), isNull);
    });

    test('bozuk tarihli konaklama çökmeye yol açmaz', () {
      final broken = [_hotel(id: 'x', checkIn: 'abc', checkOut: '')];
      expect(hotelForDate(broken, '2026-10-16'), isNull);
    });
  });

  group('latLngFromMapsUrl', () {
    test('@lat,lng biçimini çözer', () {
      final p = latLngFromMapsUrl(
        'https://www.google.com/maps/place/Hotel/@35.6812,139.7671,17z',
      );
      expect(p, isNotNull);
      expect(p!.lat, closeTo(35.6812, 1e-6));
      expect(p.lng, closeTo(139.7671, 1e-6));
    });

    test('!3d!4d biçimi @ üzerinde önceliklidir (yer koordinatı daha kesin)',
        () {
      final p = latLngFromMapsUrl(
        'https://www.google.com/maps/place/X/@35.0,139.0,17z/data=!3d35.6586!4d139.7454',
      );
      expect(p!.lat, closeTo(35.6586, 1e-6));
      expect(p.lng, closeTo(139.7454, 1e-6));
    });

    test('q / ll / destination sorgu parametrelerini çözer', () {
      for (final url in [
        'https://maps.google.com/?q=34.6937,135.5023',
        'https://maps.google.com/?ll=34.6937,135.5023&z=15',
        'https://www.google.com/maps/dir/?api=1&destination=34.6937,135.5023',
      ]) {
        final p = latLngFromMapsUrl(url);
        expect(p, isNotNull, reason: url);
        expect(p!.lat, closeTo(34.6937, 1e-6), reason: url);
      }
    });

    test('düz "lat,lng" dizesini çözer', () {
      final p = latLngFromMapsUrl('35.0116, 135.7681');
      expect(p!.lat, closeTo(35.0116, 1e-6));
      expect(p.lng, closeTo(135.7681, 1e-6));
    });

    test('kısaltılmış link ve boş girdi null döner', () {
      expect(latLngFromMapsUrl('https://maps.app.goo.gl/aBcD1234'), isNull);
      expect(latLngFromMapsUrl(''), isNull);
      expect(latLngFromMapsUrl(null), isNull);
    });

    test('aralık dışı koordinat reddedilir', () {
      expect(latLngFromMapsUrl('https://x/@99.5,200.4,17z'), isNull);
    });
  });

  group('hotelCoords', () {
    test('mapsUrl varsa onu kullanır', () {
      final h = _hotel(
        id: 'a',
        checkIn: '2026-10-15',
        checkOut: '2026-10-18',
        mapsUrl: 'https://www.google.com/maps/place/H/@35.6595,139.7005,17z',
      );
      final p = hotelCoords(h);
      expect(p!.lat, closeTo(35.6595, 1e-6));
    });

    test('koordinat çözülemezse null döner — şehir merkezine DÜŞMEZ', () {
      final h = _hotel(
        id: 'a',
        checkIn: '2026-10-15',
        checkOut: '2026-10-18',
        name: 'Zzz Bilinmeyen Otel',
        address: 'Bilinmeyen Sokak 5',
        mapsUrl: 'https://maps.app.goo.gl/short',
      );
      expect(hotelCoords(h), isNull);
    });
  });
}
