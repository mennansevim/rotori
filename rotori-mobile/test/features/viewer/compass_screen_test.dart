// Pusula (compass) ekranı widget testi — acil numara + fraz render, otel
// adresi kartı, kopyalama panoya yazar + SnackBar gösterir.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/data/plans_repository.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/viewer/compass_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Trip _sampleTrip({bool withHotel = true}) {
  return Trip(
    id: 'trip-compass',
    slug: 'compass-trip',
    title: 'Pusula Test',
    timezone: 'Asia/Tokyo',
    tripStart: '2026-05-01',
    tripEnd: '2026-05-05',
    flights: TripFlights(),
    preferences: TripPreferences(
      travelDates: TravelDates(start: '2026-05-01', end: '2026-05-05'),
      pace: Pace.moderate,
    ),
    hotels: withHotel
        ? [
            HotelStay(
              id: 'h1',
              city: 'Tokyo',
              name: 'Shinjuku Granbell Hotel',
              checkIn: '2026-05-01',
              checkOut: '2026-05-04',
              address: '2-14-5 Kabukicho, Shinjuku, Tokyo',
              addressLocal: '東京都新宿区歌舞伎町2-14-5',
              phone: '+81 3-5155-2666',
            ),
          ]
        : const [],
  );
}

void main() {
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
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: CompassScreen(trip: trip),
          ),
        ),
      ),
    );
  }

  testWidgets('acil numara ve fraz render edilir', (tester) async {
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();

    expect(find.text('🧭 Pusula'), findsOneWidget);
    // Acil numara.
    expect(find.text('110'), findsOneWidget);
    expect(find.text('Polis'), findsOneWidget);

    // Varsayılan (Temel) kategorisinden bir fraz — liste altında olabilir.
    await tester.scrollUntilVisible(
      find.text('すみません'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('すみません'), findsOneWidget);
  });

  testWidgets('otel adresi kartı (taksiciye göster) render edilir',
      (tester) async {
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();

    expect(find.text('Shinjuku Granbell Hotel'), findsOneWidget);
    expect(find.text('東京都新宿区歌舞伎町2-14-5'), findsOneWidget);
    expect(find.text('Taksiciye göster'), findsOneWidget);
  });

  testWidgets('otel yoksa otel kartı gizlenir', (tester) async {
    await tester.pumpWidget(harness(_sampleTrip(withHotel: false)));
    await tester.pump();

    expect(find.text('Taksiciye göster'), findsNothing);
  });

  testWidgets('acil numaraya dokununca panoya kopyalanır + SnackBar',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );

    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();

    await tester.tap(find.text('110'));
    await tester.pump();

    expect(copied, '110');
    expect(find.text('Numara kopyalandı: 110'), findsOneWidget);

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
}
