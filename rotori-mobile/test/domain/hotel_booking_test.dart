// hotelsComplete + parseBookingUrl — saf domain testleri.
//
// Kaynak: test/features/hotels_flow_test.dart (wizard sökülürken buraya
// taşındı; UI'dan bağımsız oldukları için korunuyor).

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/hotel_booking.dart';
import 'package:rotori/domain/trip_factory.dart';
import 'package:rotori/domain/types.dart';


Trip _tripWithDest() {
  final t = createEmptyTrip();
  t.preferences.destinations.add(TripDestination(
    id: 'd1',
    countryCode: 'JP',
    countryName: 'Japonya',
    city: 'Tokyo',
    arrivalDate: t.preferences.travelDates.start,
    departureDate: t.preferences.travelDates.end,
    order: 0,
  ));
  return t;
}


void main() {
  group('hotelsComplete gating', () {
    test('otel ve stayArea yoksa false', () {
      expect(hotelsComplete(_tripWithDest()), isFalse);
    });

    test('sadece stayArea doluysa (otel yok) true', () {
      final t = _tripWithDest();
      t.preferences.stayArea = 'Shinjuku';
      expect(hotelsComplete(t), isTrue);
    });

    test('stayArea whitespace ise false gibi davranır', () {
      final t = _tripWithDest();
      t.preferences.stayArea = '   ';
      expect(hotelsComplete(t), isFalse);
    });

    test('eksik adresli otel false', () {
      final t = _tripWithDest();
      t.hotels.add(HotelStay(
        id: 'h1',
        city: 'Tokyo',
        name: 'Hotel A',
        checkIn: t.preferences.travelDates.start,
        checkOut: t.preferences.travelDates.end,
        address: '',
      ));
      expect(hotelsComplete(t), isFalse);
    });

    test('tüm alanlar dolu otel true', () {
      final t = _tripWithDest();
      t.hotels.add(HotelStay(
        id: 'h1',
        city: 'Tokyo',
        name: 'Hotel A',
        checkIn: t.preferences.travelDates.start,
        checkOut: t.preferences.travelDates.end,
        address: '1-2-3 Shibuya',
      ));
      expect(hotelsComplete(t), isTrue);
    });

    test('bir otel eksikse tümü false (every mantığı)', () {
      final t = _tripWithDest();
      t.hotels.add(HotelStay(
        id: 'h1',
        city: 'Tokyo',
        name: 'Hotel A',
        checkIn: t.preferences.travelDates.start,
        checkOut: t.preferences.travelDates.end,
        address: '1-2-3 Shibuya',
      ));
      t.hotels.add(HotelStay(
        id: 'h2',
        city: '',
        name: '',
        checkIn: '',
        checkOut: '',
        address: '',
      ));
      expect(hotelsComplete(t), isFalse);
    });
  });

  group('parseBookingUrl', () {
    test('booking hotel linkinden isim çıkarır', () {
      final p = parseBookingUrl(
          'https://www.booking.com/hotel/jp/hotel-grand-city.html?checkin=2026-10-15&checkout=2026-10-18');
      expect(p, isNotNull);
      expect(p!.source, 'booking');
      expect(p.name, 'Hotel Grand City');
      expect(p.checkIn, '2026-10-15');
      expect(p.checkOut, '2026-10-18');
    });

    test('booking mytrips linki booking-mytrips döndürür', () {
      final p = parseBookingUrl('https://www.booking.com/mytrips/index.html');
      expect(p!.source, 'booking-mytrips');
    });

    test('desteklenmeyen site unknown', () {
      final p = parseBookingUrl('https://airbnb.com/rooms/123');
      expect(p!.source, 'unknown');
    });

    test('geçersiz metin null', () {
      expect(parseBookingUrl('merhaba'), isNull);
      expect(parseBookingUrl(''), isNull);
    });
  });
}
