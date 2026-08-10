// BudgetScreen widget smoke testi — toplam + çevirici render edilir;
// çevirici girdisi/kur değişimi TL çıktısını günceller.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/data/plans_repository.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/viewer/budget_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Maliyetler, ana toplamların (₺1.750 / ₺3.500) plandaki başka hiçbir
// TL değeriyle çakışmayacağı şekilde seçildi (deterministik finder'lar için).
Trip _sampleTrip() => Trip(
      id: 'trip-b',
      slug: 'budget-trip',
      title: 'Bütçe Test',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-07-01',
      tripEnd: '2026-07-02',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-07-01', end: '2026-07-02'),
        pace: Pace.moderate,
        partySize: 2,
        mealBudgetPerPerson: 3000,
      ),
      days: [
        DayPlan(
          dayNumber: 1,
          date: '2026-07-01',
          theme: 'Gün 1',
          items: [
            TimelineItem(
              id: 'a',
              title: 'Tapınak',
              cost: 1000,
              kind: TimelineItemKind.activity,
            ),
            TimelineItem(
              id: 'm',
              title: 'Ramen',
              cost: 2000,
              kind: TimelineItemKind.meal,
            ),
          ],
        ),
        DayPlan(
          dayNumber: 2,
          date: '2026-07-02',
          theme: 'Gün 2',
          items: [
            TimelineItem(
              id: 't',
              title: 'Shinkansen',
              cost: 4000,
              kind: TimelineItemKind.transport,
            ),
          ],
        ),
      ],
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // Tüm bölümlerin (çevirici en altta) tek ekrana sığması için uzun viewport;
  // ListView off-screen çocukları tembel kurar.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

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
            child: BudgetScreen(trip: trip),
          ),
        ),
      ),
    );
  }

  testWidgets('tahmin kartı, kırılım ve çevirici render edilir', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Başlık
    expect(find.text('💰 Bütçe'), findsOneWidget);
    // Yeni tasarımda toplam tek satır yerine tahmin + kategori/gün kırılımı var.
    expect(find.text('Bu rota sizin için tahminen'), findsOneWidget);
    expect(find.text('Kategoriye göre'), findsOneWidget);
    expect(find.text('₺750'), findsOneWidget);
    // Çevirici bölümü
    expect(find.text('Çevirici'), findsOneWidget);
    // Varsayılan kur satırı
    expect(find.text('1 ¥ = ₺0,25'), findsOneWidget);
  });

  testWidgets('çevirici girdisi TL çıktısını günceller', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Çevirici alanı = ekranın ilk TextField'ı; 10000 → 10000*0.25 = ₺2.500
    await tester.enterText(find.byType(TextField).first, '10000');
    await tester.pump();

    expect(find.text('₺2.500'), findsOneWidget);
  });

  testWidgets('kur düzenlenince kur satırı ve çevirici çıktısı güncellenir',
      (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Kuru düzenle dialog'unu aç
    await tester.tap(find.text('Kuru düzenle'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Dialog içindeki TextField'a yeni kur gir (0,5)
    final dialogField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(dialogField, findsOneWidget);
    await tester.enterText(dialogField, '0,5');
    await tester.tap(find.text('Kaydet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Kur satırı güncellenir.
    expect(find.text('1 ¥ = ₺0,5'), findsOneWidget);

    // Çeviriciyi yeni kurla doğrula: 7000 * 0.5 = ₺3.500
    await tester.enterText(find.byType(TextField).first, '7000');
    await tester.pump();
    expect(find.text('₺3.500'), findsOneWidget);

    // Gün toplamı da yeni kura göre artar: (1000+2000) * 0.5 = ₺1.500
    expect(find.text('₺1.500'), findsOneWidget);
  });
}
