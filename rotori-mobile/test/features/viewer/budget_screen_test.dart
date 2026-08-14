// BudgetScreen widget testi — tahmin kartı, gider dağılımı pastası ve kur
// satırı. Çevirici bölümü kaldırıldı (ayrı Canlı Fiyat Çevirici ekranı var);
// "Örnek birim fiyatlar" çipleri de kaldırıldı.

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

  // Tüm bölümlerin tek ekrana sığması için uzun viewport; ListView off-screen
  // çocukları tembel kurar.
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

  testWidgets('tahmin kartı ve kırılım render edilir', (tester) async {
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
    // Varsayılan kur satırı
    expect(find.text('1 ¥ = ₺0,25'), findsOneWidget);

    // Kaldırılanlar geri gelmesin.
    expect(find.text('Çevirici'), findsNothing);
    expect(find.text('Örnek birim fiyatlar'), findsNothing);
    // Kur kartı sıkıştı: başlık ve "elle güncellenir" dipnotu yok.
    expect(find.text('Para birimi'), findsNothing);
    expect(find.textContaining('Kur elle güncellenir'), findsNothing);
  });

  testWidgets('kur düzenlenince kur satırı ve gün toplamı güncellenir',
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

    // Gün toplamı yeni kura göre artar: (1000+2000) * 0.5 = ₺1.500
    expect(find.text('₺1.500'), findsOneWidget);
  });

  group('gider dağılımı pastası', () {
    /// Pastanın o anki dilim paylarını painter'dan okur — ekranda ne çizildiği
    /// bu; yüzde etiketleri ayrı yoldan hesaplanıyor.
    List<double> paintedShares(WidgetTester tester) {
      final paint = tester.widget<CustomPaint>(
        find
            .descendant(
              of: find.byKey(const ValueKey('budget-share-pie')),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      final painter = paint.painter! as dynamic;
      return (painter.slices as List)
          .map<double>((s) => (s.share as double))
          .toList();
    }

    // Renk çakışması REGRESYON testi.
    //
    // İlk iki denemede dilim renkleri `ViewerPalette` tonlarından seçilmişti ve
    // ayırt edilemiyorlardı: açık temada accent/sky/accentStrong neredeyse aynı
    // mavi, koyu temada accent ile fuji birebir aynı mor. Bu test paletten
    // ton seçmeye geri dönüşü yakalar.
    testWidgets('dilim renkleri birbirinden ayırt edilebilir', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(_sampleTrip()));
      await tester.pumpAndSettle();

      final paint = tester.widget<CustomPaint>(
        find
            .descendant(
              of: find.byKey(const ValueKey('budget-share-pie')),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      final colors = ((paint.painter! as dynamic).slices as List)
          .map<Color>((s) => (s.color as Color))
          .toList();
      expect(colors.length, greaterThanOrEqualTo(6));

      for (var i = 0; i < colors.length; i++) {
        for (var j = i + 1; j < colors.length; j++) {
          final a = colors[i];
          final b = colors[j];
          // sRGB kanal uzaklığı — "neredeyse aynı" iki rengi ayırmaya yeter.
          final d = ((a.r - b.r).abs() +
                  (a.g - b.g).abs() +
                  (a.b - b.b).abs()) *
              255;
          expect(
            d,
            greaterThan(90),
            reason: 'dilim $i ve $j renkleri çok yakın: $a / $b',
          );
        }
      }
    });

    testWidgets('pasta hesabın altında, paylar toplamı %100', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(_sampleTrip()));
      await tester.pumpAndSettle();

      final pie = find.byKey(const ValueKey('budget-share-pie'));
      expect(pie, findsOneWidget);
      expect(find.text('Gider dağılımı'), findsOneWidget);

      final shares = paintedShares(tester);
      expect(shares, isNotEmpty);
      expect(
        shares.fold<double>(0, (a, b) => a + b),
        closeTo(1.0, 0.001),
        reason: 'dilimler tam daireyi doldurmuyor',
      );
      // Lejand azalan sırada: en büyük kalem başta.
      for (var i = 1; i < shares.length; i++) {
        expect(shares[i], lessThanOrEqualTo(shares[i - 1] + 0.0001));
      }

      // Pasta hesabın HEMEN ALTINDA: kalem satırlarından sonra, nottan önce.
      // "Uçak bileti" iki yerde geçiyor (kalem satırı + lejand); ilki satır.
      expect(
        tester.getTopLeft(pie).dy,
        greaterThan(tester.getTopLeft(find.text('Uçak bileti').first).dy),
      );
      expect(
        tester.getTopLeft(pie).dy,
        lessThan(tester.getTopLeft(find.textContaining('Tahmin 2026')).dy),
      );
    });

    testWidgets('bir kalem elle değişince paylar güncellenir', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(_sampleTrip()));
      await tester.pumpAndSettle();

      final before = paintedShares(tester);

      // Uçak biletini çok yüksek bir değere sabitle → payı baskın olmalı.
      await tester.tap(find.text('Uçak bileti').first);
      await tester.pumpAndSettle();
      final dialogField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      expect(dialogField, findsOneWidget);
      await tester.enterText(dialogField, '9000000');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      final after = paintedShares(tester);
      expect(after, isNot(equals(before)));
      // Baskın kalem ilk dilim ve payı yarıdan fazla.
      expect(after.first, greaterThan(0.5));
    });

    // "Hareketli" olması sözleşmenin parçası: dilimler yeni paya SIÇRAMAZ,
    // akar. Yukarıdaki testler `disableAnimations: true` ile koşuyor (o yolda
    // doğrudan son duruma oturmalı); bu test animasyonlu yolu sürüyor.
    testWidgets('dilimler son paya animasyonla ulaşır', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWith(
              (ref) async => SharedPreferences.getInstance(),
            ),
          ],
          child: MaterialApp(home: BudgetScreen(trip: _sampleTrip())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // İlk kare: sıfırdan büyümeye başlamış, henüz tamamlanmamış.
      final mid = paintedShares(tester);
      expect(mid.fold<double>(0, (a, b) => a + b), lessThan(0.99));

      await tester.pumpAndSettle();
      final settled = paintedShares(tester);
      expect(settled.fold<double>(0, (a, b) => a + b), closeTo(1.0, 0.001));
      expect(settled, isNot(equals(mid)));
    });
  });
}
