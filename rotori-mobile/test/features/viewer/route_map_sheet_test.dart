// Animasyonlu rota haritası — çizim ilerlemesi matematiği (saf fonksiyonlar)
// + sheet'in duraklarla hatasız kurulduğu smoke testi.
//
// Tile'lar ağdan çekilmez: testler _FakeTileProvider enjekte eder.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/core/l10n.dart';
import 'package:japan_trip/data/plans_repository.dart';
import 'package:japan_trip/domain/place_coords.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/viewer/route_map_sheet.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ağ isteği yapmadan 1x1 saydam PNG döndüren test tile sağlayıcısı.
class _FakeTileProvider extends TileProvider {
  static final Uint8List _pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return MemoryImage(_pngBytes);
  }
}

Trip _sampleTrip() {
  return Trip(
    id: 'trip-1',
    slug: 'test-trip',
    title: 'Japonya Test',
    timezone: 'Asia/Tokyo',
    tripStart: '2026-05-13',
    tripEnd: '2026-05-16',
    flights: TripFlights(),
    preferences: TripPreferences(
      travelDates: TravelDates(start: '2026-05-13', end: '2026-05-16'),
      pace: Pace.moderate,
      destinations: [
        TripDestination(
          id: 'd1',
          countryCode: 'JP',
          countryName: 'Japonya',
          city: 'Kyoto',
          lat: 35.0116,
          lng: 135.7681,
          arrivalDate: '2026-05-13',
          departureDate: '2026-05-16',
          order: 0,
        ),
      ],
    ),
    days: [
      DayPlan(
        dayNumber: 1,
        date: '2026-05-13',
        theme: 'Kyoto keşfi',
        items: [
          TimelineItem(id: 'a', title: 'Kinkaku-ji', time: '09:00'),
          TimelineItem(id: 'b', title: 'Arashiyama', time: '12:00'),
          TimelineItem(id: 'c', title: 'Kiyomizu-dera', time: '16:00'),
        ],
      ),
    ],
  );
}

void main() {
  group('routeProgressStops', () {
    test('boş ve tek noktalı rotalarda güvenli döner', () {
      expect(routeProgressStops(const []), isEmpty);
      expect(routeProgressStops(const [LatLng(35, 135)]), [0.0]);
    });

    test('ilk 0, son 1 ve monoton artan', () {
      final stops = routeProgressStops(const [
        LatLng(35.0394, 135.7292), // Kinkaku-ji
        LatLng(35.0094, 135.6667), // Arashiyama
        LatLng(34.9949, 135.7850), // Kiyomizu-dera
      ]);
      expect(stops.length, 3);
      expect(stops.first, 0.0);
      expect(stops.last, 1.0);
      expect(stops[1], greaterThan(0.0));
      expect(stops[1], lessThan(1.0));
    });

    test('uzun bacak toplam ilerlemenin daha büyük payını alır', () {
      // 1→2 bacağı 1 derece, 2→3 bacağı 0.1 derece: ilk bacak ~%91.
      final stops = routeProgressStops(const [
        LatLng(35.0, 135.0),
        LatLng(36.0, 135.0),
        LatLng(36.1, 135.0),
      ]);
      expect(stops[1], closeTo(1.0 / 1.1, 0.001));
    });

    test('üst üste binen noktalarda eşit aralığa düşer', () {
      final stops = routeProgressStops(const [
        LatLng(35.0, 135.0),
        LatLng(35.0, 135.0),
        LatLng(35.0, 135.0),
      ]);
      expect(stops, [0.0, 0.5, 1.0]);
    });
  });

  group('partialRoute', () {
    const route = [
      LatLng(35.0, 135.0),
      LatLng(36.0, 135.0),
      LatLng(37.0, 135.0),
    ];

    test('t=0 tek nokta, t=1 tüm rota', () {
      expect(partialRoute(route, 0), [route.first]);
      expect(partialRoute(route, 1), route);
      // Sınır dışı değerler klamplanır.
      expect(partialRoute(route, -3), [route.first]);
      expect(partialRoute(route, 9), route);
    });

    test('ara ilerlemede uç nokta enterpolasyonla üretilir', () {
      final half = partialRoute(route, 0.5);
      expect(half.length, 2);
      expect(half.first, route.first);
      expect(half.last.latitude, closeTo(36.0, 0.001));
    });

    test('ikinci durağı geçtikten sonra o durak listede yer alır', () {
      final drawn = partialRoute(route, 0.75);
      expect(drawn.length, 3);
      expect(drawn[1], route[1]);
      expect(drawn.last.latitude, closeTo(36.5, 0.001));
    });

    test('iki noktadan az rota olduğu gibi döner', () {
      expect(partialRoute(const [LatLng(35, 135)], 0.5), [
        const LatLng(35, 135),
      ]);
      expect(partialRoute(const [], 0.5), isEmpty);
    });
  });

  group('RouteMapSheet', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Widget harness(Trip trip) {
      return ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWith(
            (ref) async => SharedPreferences.getInstance(),
          ),
        ],
        child: LanguageScope(
          lang: AppLang.tr,
          child: MaterialApp(
            home: Scaffold(
              body: RouteMapSheet(
                trip: trip,
                day: trip.days.first,
                tileProvider: _FakeTileProvider(),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('rota çizimi bittiğinde tüm duraklar pin olarak görünür',
        (tester) async {
      await tester.pumpWidget(harness(_sampleTrip()));
      await tester.pump();

      // Çizim başlarken yalnızca ilk pin belirir; son durak henüz yok.
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const ValueKey('route-stop-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('route-stop-3')), findsNothing);

      // Animasyon tamamlanınca üç durak da yerinde.
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey('route-stop-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('route-stop-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('route-stop-3')), findsOneWidget);

      // Pulse animasyonu sonsuz döner; testi kapatmadan önce durdur.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('aksiyon barı tekrar oynat + yol tarifi sunar',
        (tester) async {
      await tester.pumpWidget(harness(_sampleTrip()));
      await tester.pump();

      expect(find.byKey(const ValueKey('route-map-replay')), findsOneWidget);
      expect(find.byKey(const ValueKey('route-map-fit')), findsOneWidget);
      expect(find.byKey(const ValueKey('route-map-google')), findsOneWidget);

      // Tekrar oynat çizimi baştan başlatır — 3. pin yeniden gizlenir.
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey('route-stop-3')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('route-map-replay')));
      await tester.pump();
      expect(find.byKey(const ValueKey('route-stop-3')), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('pinler durak emojisini ve ad etiketini taşır',
        (tester) async {
      await tester.pumpWidget(harness(_sampleTrip()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      // Küratörlü nokta eşleşmesi emoji sağlar (city_places.dart).
      final stops = resolveDayStops(
        _sampleTrip().days.first,
        cityKey: 'Kyoto',
      );
      expect(stops, hasLength(3));
      expect(stops.every((s) => s.place != null), isTrue);

      // Kamera duraklara sığdığında zoom şehir ölçeğindedir → adlar görünür.
      for (final stop in stops) {
        expect(find.text(stop.item.title), findsOneWidget);
      }

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('zoom kontrolleri harita üstünde durur', (tester) async {
      await tester.pumpWidget(harness(_sampleTrip()));
      await tester.pump();

      expect(find.byKey(const ValueKey('route-map-zoom-in')), findsOneWidget);
      expect(find.byKey(const ValueKey('route-map-zoom-out')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    // Kullanıcı güne oteliden başlıyor: "oradan hareket edeceğim her gün
    // başında". Harita bunu göstermezse günün ilk bacağı görünmez kalır.
    testWidgets('o gün kalınan otel haritada ayrı bir pin olarak görünür',
        (tester) async {
      final trip = _sampleTrip();
      trip.hotels.add(HotelStay(
        id: 'h1',
        city: 'Kyoto',
        name: 'Kyoto Test Ryokan',
        checkIn: '2026-05-13',
        checkOut: '2026-05-16',
        address: 'Nakagyo',
        mapsUrl: 'https://www.google.com/maps/place/R/@35.0116,135.7681,17z',
      ));

      await tester.pumpWidget(harness(trip));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6)); // çizim bitsin

      // Otel pini yatak ikonuyla gelir; rota durakları bu ikonu kullanmaz.
      expect(find.byIcon(Icons.hotel_rounded), findsOneWidget);
      // Adı etiket olarak okunur.
      expect(find.text('Kyoto Test Ryokan'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('koordinatı çözülemeyen otel için pin gösterilmez',
        (tester) async {
      final trip = _sampleTrip();
      trip.hotels.add(HotelStay(
        id: 'h1',
        city: 'Kyoto',
        name: 'Zzz Bilinmeyen Otel',
        checkIn: '2026-05-13',
        checkOut: '2026-05-16',
        address: 'Bilinmeyen Sokak 5',
        mapsUrl: 'https://maps.app.goo.gl/short', // koordinat taşımaz
      ));

      await tester.pumpWidget(harness(trip));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));

      // Yanlış yerde pin göstermektense hiç gösterme.
      expect(find.byIcon(Icons.hotel_rounded), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('o güne ait olmayan otel gösterilmez', (tester) async {
      final trip = _sampleTrip();
      // Gün 2026-05-13; bu konaklama bir hafta sonra.
      trip.hotels.add(HotelStay(
        id: 'h1',
        city: 'Kyoto',
        name: 'Sonraki Hafta Oteli',
        checkIn: '2026-05-20',
        checkOut: '2026-05-23',
        address: 'Nakagyo',
        mapsUrl: 'https://www.google.com/maps/place/R/@35.0116,135.7681,17z',
      ));

      await tester.pumpWidget(harness(trip));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));

      expect(find.byIcon(Icons.hotel_rounded), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('duraksız günde bilgi bandı gösterir', (tester) async {
      final trip = _sampleTrip();
      final empty = Trip(
        id: trip.id,
        slug: trip.slug,
        title: trip.title,
        timezone: trip.timezone,
        tripStart: trip.tripStart,
        tripEnd: trip.tripEnd,
        flights: trip.flights,
        preferences: trip.preferences,
        days: [
          DayPlan(
            dayNumber: 1,
            date: '2026-05-13',
            theme: 'Boş gün',
            items: const [],
          ),
        ],
      );

      await tester.pumpWidget(harness(empty));
      await tester.pump();

      expect(
        find.text(L10n.resolve('map.emptyBanner', AppLang.tr)),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
