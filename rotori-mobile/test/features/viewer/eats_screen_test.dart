// Rotori Eats — Japon yemekleri rehberi widget testleri.
//
// Ekran tamamen ücretsiz: paywall, katman rozeti ve kilit YOKTUR. Bu
// testler hem işlevi hem de "diyet bilgisi paywall'a konmaz" kararını korur.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/data/plans_repository.dart';
import 'package:japan_trip/domain/japanese_dishes.dart';
import 'package:japan_trip/domain/japanese_dishes_data.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/viewer/eats_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Trip _trip({List<String> diet = const []}) => Trip(
      id: 'trip-eats',
      slug: 'eats',
      title: 'Eats Test',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-07-01',
      tripEnd: '2026-07-02',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-07-01', end: '2026-07-02'),
        pace: Pace.moderate,
        dietaryTags: diet,
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 14000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget harness(Trip trip) => ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWith(
            (ref) async => SharedPreferences.getInstance(),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: EatsScreen(trip: trip),
            ),
          ),
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
  }

  group('liste', () {
    testWidgets('yemekler adı, Japoncası ve sayısıyla listelenir',
        (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(_trip()));
      await settle(tester);

      expect(find.text('${kJapaneseDishes.length} yemek'), findsOneWidget);
      expect(find.text('Ramen'), findsOneWidget);
      expect(find.textContaining('ラーメン'), findsWidgets);
    });

    testWidgets('kategori seçimi listeyi daraltır', (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(_trip()));
      await settle(tester);

      // Aynı metin hem kategori çipinde hem kartların alt satırında geçiyor;
      // çip listenin en üstünde olduğu için ilk eşleşme odur.
      await tester.tap(find.textContaining('Erişteler').first);
      await tester.pump();

      final noodles =
          kJapaneseDishes.where((d) => d.category == DishCategory.noodles);
      expect(find.text('${noodles.length} yemek'), findsOneWidget);
      expect(find.text('Ramen'), findsOneWidget);
      expect(find.text('Takoyaki'), findsNothing);
    });

    testWidgets('arama Japonca ada göre de çalışır', (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(_trip()));
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'たこ焼き');
      await tester.pump();

      expect(find.text('1 yemek'), findsOneWidget);
      expect(find.text('Takoyaki'), findsOneWidget);
    });
  });

  group('diyet hükmü', () {
    testWidgets('tercih yokken hüküm verilmez, çağrı gösterilir',
        (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(_trip()));
      await settle(tester);

      expect(find.text('Neyi yiyebilirsin?'), findsOneWidget);
      // Hiçbir kartta rozet olmamalı — uydurma "uygun" yok.
      expect(find.textContaining('Yiyebilirsin'), findsNothing);
    });

    testWidgets('helal seçiliyken rozetler ve gerekçeler çıkar',
        (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(_trip(diet: ['halal'])));
      await settle(tester);

      expect(find.text('Sana göre işaretleniyor'), findsOneWidget);
      expect(find.textContaining('Uygun değil'), findsWidgets);
    });

    testWidgets('uygun olmayan yemekte alternatif tür önerilir',
        (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(_trip(diet: ['no_pork'])));
      await settle(tester);

      // Ramen domuz bazlıdır ama tori paitan/vegan türü var.
      expect(
        find.textContaining('türünü yiyebilirsin'),
        findsWidgets,
      );
    });

    testWidgets('"sadece yiyebileceklerim" anahtarı listeyi kısaltır',
        (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(_trip(diet: ['vegan'])));
      await settle(tester);

      final before = kJapaneseDishes.length;
      expect(find.text('$before yemek'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(find.text('$before yemek'), findsNothing);
    });
  });

  group('yemek detayı', () {
    testWidgets('malzemeler, nasıl yenir ve Japonca ad gösterilir',
        (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(_trip()));
      await settle(tester);

      await tester.tap(find.text('Ramen'));
      await tester.pumpAndSettle();

      expect(find.text('Nedir'), findsOneWidget);
      expect(find.text('İçinde ne var'), findsOneWidget);
      expect(find.text('Nasıl yenir'), findsOneWidget);
      expect(find.text('Türleri'), findsOneWidget);
      expect(find.textContaining('Personele göstermek için'), findsOneWidget);
    });

    testWidgets('alt tür seçmek hükmü değiştirir', (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(_trip(diet: ['no_pork'])));
      await settle(tester);

      await tester.tap(find.text('Ramen'));
      await tester.pumpAndSettle();

      // Genel ramen domuz bazlı → uygun değil.
      expect(find.textContaining('⛔'), findsWidgets);

      // Vegan ramen türüne geç → artık "sor".
      await tester.tap(find.text('Vegan ramen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('⚠️'), findsWidgets);
    });

    testWidgets('gizli risk uyarısı gösterilir', (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(_trip()));
      await settle(tester);

      await tester.tap(find.text('Miso çorbası'));
      await tester.pumpAndSettle();

      expect(find.text('Dikkat'), findsOneWidget);
      expect(find.textContaining('dashi'), findsWidgets);
    });
  });

  group('ücretsizlik', () {
    testWidgets('hiçbir yerde paywall, kilit ya da Pass rozeti yok',
        (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(_trip(diet: ['halal'])));
      await settle(tester);

      expect(find.text('Rotori Eats Pass'), findsNothing);
      expect(find.text('Hepsini aç'), findsNothing);
      expect(find.text('Pass aktif'), findsNothing);
      expect(find.byIcon(Icons.lock_rounded), findsNothing);
    });
  });

  group('menü kelimeleri', () {
    testWidgets('menüde tanınacak kelimeler listelenir', (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(_trip()));
      await settle(tester);

      expect(find.text('Menüde tanıman gereken kelimeler'), findsOneWidget);
      expect(find.text('だし / 出汁'), findsOneWidget);
    });
  });
}
