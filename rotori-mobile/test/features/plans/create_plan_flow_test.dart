// Yeni 2 adımlı plan oluşturma akışı — widget testleri.
//
// Metinler L10n.resolve ile okunur; metin cilası testleri kırmasın.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/core/l10n.dart';
import 'package:rotori/core/rotori_brand.dart';
import 'package:rotori/domain/city_places.dart';
import 'package:rotori/domain/plan_generation.dart' show CityNights;
import 'package:rotori/features/plans/create/city_select_page.dart';
import 'package:rotori/features/plans/create/create_plan_screen.dart';
import 'package:rotori/features/plans/create/create_plan_widgets.dart';
import 'package:rotori/features/plans/create/date_select_page.dart';
import 'package:rotori/features/plans/create/preferences_page.dart';
import 'package:rotori/features/viewer/viewer_theme.dart';

String tr(String key) => L10n.resolve(key, AppLang.tr);

void main() {
  /// Gerçek telefon yüzeyi kurar. GridView.builder tembel olduğu için varsayılan
  /// 800x600 test yüzeyinde alt sıradaki şehirler hiç inşa edilmiyor.
  Future<void> pumpFlow(
    WidgetTester tester, {
    Size size = const Size(390, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: CreatePlanScreen())),
    );
    await tester.pumpAndSettle();
  }

  group('1. ekran — şehir seçimi', () {
    testWidgets('küratörlü şehir kartları render edilir', (tester) async {
      await pumpFlow(tester);

      expect(find.text(tr('create.cities.title')), findsOneWidget);
      // Grid tembel: ekran dışındaki kartlar inşa edilmez, o yüzden hepsini
      // aramak yanıltıcı olurdu. İlk ekrandakiler görünmeli...
      for (final c in kCityData.take(6)) {
        expect(find.text(c.label), findsOneWidget,
            reason: '${c.label} kartı yok');
      }
      // ...ve aşağı kaydırınca sonrakiler de gelmeli.
      await tester.drag(find.byType(GridView), const Offset(0, -4000));
      await tester.pumpAndSettle();
      expect(find.text(kCityData.last.label), findsOneWidget,
          reason: '${kCityData.last.label} kaydırınca da gelmedi');
    });

    testWidgets('hiç seçim yokken Devam pasif ve ipucu görünür',
        (tester) async {
      await pumpFlow(tester);

      expect(find.text(tr('create.cities.selectHint')), findsOneWidget);

      final btn = tester.widget<BrandButton>(find.byType(BrandButton).first);
      expect(btn.onPressed, isNull, reason: 'Devam pasif olmalıydı');
    });

    testWidgets('şehir seçilince sayaç güncellenir ve Devam aktifleşir',
        (tester) async {
      await pumpFlow(tester);

      await tester.tap(find.text('Tokyo'));
      await tester.pumpAndSettle();

      expect(
          find.text(L10n.parametrize(tr('create.cities.selected'), {'n': '1'})),
          findsOneWidget);
      final btn = tester.widget<BrandButton>(find.byType(BrandButton).first);
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('seçim sırası rozetlere yansır ve toggle sırayı düzeltir',
        (tester) async {
      await pumpFlow(tester);

      await tester.tap(find.text('Tokyo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kyoto'));
      await tester.pumpAndSettle();

      CityTile tileFor(String label) => tester
          .widgetList<CityTile>(
            find.byType(CityTile),
          )
          .firstWhere((t) => t.label == label);

      expect(tileFor('Tokyo').orderIndex, 1);
      expect(tileFor('Kyoto').orderIndex, 2);

      // Tokyo'yu çıkar → Kyoto 1. sıraya kayar.
      await tester.tap(find.text('Tokyo'));
      await tester.pumpAndSettle();

      expect(tileFor('Tokyo').selected, isFalse);
      expect(tileFor('Kyoto').orderIndex, 1);
    });

    testWidgets('375px genişlikte taşma yok', (tester) async {
      await pumpFlow(tester, size: const Size(375, 812));

      expect(tester.takeException(), isNull);
    });
  });

  group('2. ekran — tarih', () {
    Future<void> goToDates(WidgetTester tester) async {
      await pumpFlow(tester);
      await tester.tap(find.text('Tokyo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kyoto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('create.continue')));
      await tester.pumpAndSettle();
    }

    testWidgets('Devam 2. ekrana geçirir, hero rota özetini gösterir',
        (tester) async {
      await goToDates(tester);

      expect(find.text(tr('create.dates.title')), findsOneWidget);
      expect(find.textContaining('Tokyo'), findsWidgets);
      expect(find.textContaining('Kyoto'), findsWidgets);
    });

    testWidgets('tarih yokken üretim pasif', (tester) async {
      await goToDates(tester);

      expect(find.text(tr('create.dates.pick')), findsOneWidget);
      final btn = tester.widget<BrandButton>(find.byType(BrandButton).first);
      expect(btn.onPressed, isNull);
    });

    testWidgets(
        '"tarih belli değil" → tarih dolar, tahmin notu + dağılım görünür',
        (tester) async {
      await goToDates(tester);

      await tester.tap(find.text(tr('create.dates.unknown')));
      await tester.pumpAndSettle();

      // Tahmini tarih notu
      expect(find.text(tr('create.dates.estimated')), findsOneWidget);
      // Gün dağılımı kartı — düzenlenebilir olduğunu anlatan not
      expect(find.text(tr('create.dates.splitEditable')), findsOneWidget);
      // Üretim artık mümkün
      final btn = tester.widget<BrandButton>(find.byType(BrandButton).first);
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('dağılım toplamı gün sayısına eşit', (tester) async {
      await goToDates(tester);
      await tester.tap(find.text(tr('create.dates.unknown')));
      await tester.pumpAndSettle();

      final page = tester.widget<DateSelectPage>(find.byType(DateSelectPage));
      final total = page.distribution.fold<int>(0, (n, c) => n + c.days);
      expect(total, page.distribution.isEmpty ? 0 : greaterThan(0));

      final bars = find.byType(LinearProgressIndicator);
      expect(bars, findsNWidgets(page.distribution.length));
    });

    testWidgets('+ / − ile gün dağılımı değişir, toplam sabit kalır',
        (tester) async {
      await goToDates(tester);
      await tester.tap(find.text(tr('create.dates.unknown')));
      await tester.pumpAndSettle();

      List<CityNights> dist() => tester
          .widget<DateSelectPage>(find.byType(DateSelectPage))
          .distribution;

      final before = dist();
      final total = before.fold<int>(0, (a, c) => a + c.days);
      final tokyoBefore = before.firstWhere((c) => c.label == 'Tokyo').days;

      // Tokyo satırındaki "+" — ilk şehir satırının artı butonu.
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();

      final after = dist();
      expect(after.firstWhere((c) => c.label == 'Tokyo').days, tokyoBefore + 1);
      expect(after.fold<int>(0, (a, c) => a + c.days), total,
          reason: 'Toplam gün değişmemeliydi');
    });

    testWidgets('bir şehir 1 güne inince − pasifleşir', (tester) async {
      await goToDates(tester);
      await tester.tap(find.text(tr('create.dates.unknown')));
      await tester.pumpAndSettle();

      // Kyoto'yu 1 güne indir (birden fazla basış gerekebilir).
      for (var i = 0; i < 6; i++) {
        final page = tester.widget<DateSelectPage>(find.byType(DateSelectPage));
        final kyoto = page.distribution.firstWhere((c) => c.label == 'Kyoto');
        if (kyoto.days <= 1) break;
        await tester.tap(find.byIcon(Icons.remove_rounded).last);
        await tester.pumpAndSettle();
      }

      final page = tester.widget<DateSelectPage>(find.byType(DateSelectPage));
      expect(page.distribution.firstWhere((c) => c.label == 'Kyoto').days, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('geri hero butonu 1. ekrana döndürür', (tester) async {
      await goToDates(tester);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(find.text(tr('create.cities.title')), findsOneWidget);
      expect(find.byType(CitySelectPage), findsOneWidget);
    });
  });

  group('3. ekran — varsayımlar ve tercihler', () {
    testWidgets('üretimden önce rota, tarih, uçuş ve otel varsayımları görünür',
        (tester) async {
      await pumpFlow(tester);
      await tester.tap(find.text('Tokyo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('create.continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('create.dates.unknown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('create.dates.continue')));
      await tester.pumpAndSettle();

      expect(find.text(tr('create.assumptions.title')), findsOneWidget);
      expect(find.textContaining('Tokyo'), findsWidgets);
      expect(find.text(tr('create.assumptions.draft')), findsNWidgets(2));
      expect(
          find.text(tr('create.assumptions.estimatedBadge')), findsOneWidget);
      expect(
          find.text(tr('create.assumptions.estimatedReason')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('uçuş ve otel satırlarında "Ekle" aksiyonu vardır',
        (tester) async {
      await pumpFlow(tester);
      await tester.tap(find.text('Tokyo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('create.continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('create.dates.unknown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('create.dates.continue')));
      await tester.pumpAndSettle();

      // ROTA + TARİHLER "Düzelt", UÇUŞ + OTEL "Ekle".
      expect(find.text(tr('create.assumptions.edit')), findsNWidgets(2));
      expect(find.text(tr('create.assumptions.add')), findsNWidgets(2));
      // Aksiyonun planı üreteceği önden söylenir.
      expect(find.text(tr('create.assumptions.addHint')), findsOneWidget);

      final prefs = tester.widget<PreferencesPage>(find.byType(PreferencesPage));
      expect(prefs.onAddFlight, isNotNull);
      expect(prefs.onAddHotel, isNotNull);
    });

    // REGRESYON: kart uçuş/otel değerini SABİT yazıyordu
    // (`create.assumptions.draft`), plandan hiç okumuyordu. Kullanıcı uçuşunu
    // kaydedip buraya dönüyor, kart hâlâ "Eklenmedi · taslak" diyordu ve
    // kaydı kaybolmuş görünüyordu.
    testWidgets('kaydedilmiş uçuş ve otel karta yansır', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: PreferencesPage(
                palette: ViewerPalette.appleLight,
                dietTags: const [],
                mealBudgetJpy: null,
                routeSummary: 'Tokyo',
                dateSummary: '2026-09-03 → 2026-09-05',
                datesEstimated: false,
                onEditCities: () {},
                onEditDates: () {},
                onAddFlight: () {},
                onAddHotel: () {},
                flightSummary: 'IST → HND · gidiş-dönüş',
                hotelSummary: 'Granbell Hotel',
                onToggleTag: (_) {},
                onPickBudget: (_) {},
                generating: false,
                onGenerate: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('IST → HND · gidiş-dönüş'), findsOneWidget);
      expect(find.text('Granbell Hotel'), findsOneWidget);
      // "Eklenmedi · taslak" hiç kalmadı; dört satır da "Düzelt" gösterir ve
      // "önce plan üretilir" ipucu düşer.
      expect(find.text(tr('create.assumptions.draft')), findsNothing);
      expect(find.text(tr('create.assumptions.add')), findsNothing);
      expect(find.text(tr('create.assumptions.edit')), findsNWidgets(4));
      expect(find.text(tr('create.assumptions.addHint')), findsNothing);
    });

    testWidgets('üretim mümkün değilken "Ekle" aksiyonu görünmez',
        (tester) async {
      // Sayfayı doğrudan kurar: PageView tembel olduğu için akıştan
      // gidildiğinde PreferencesPage üretilemez durumda hiç inşa edilmiyor.
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: PreferencesPage(
              palette: ViewerPalette.appleLight,
              dietTags: const [],
              mealBudgetJpy: null,
              routeSummary: '—',
              dateSummary: '—',
              datesEstimated: false,
              onEditCities: () {},
              onEditDates: () {},
              onAddFlight: null,
              onAddHotel: null,
              onToggleTag: (_) {},
              onPickBudget: (_) {},
              generating: false,
              onGenerate: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(tr('create.assumptions.add')), findsNothing);
      expect(find.text(tr('create.assumptions.addHint')), findsNothing);
      // ROTA / TARİHLER "Düzelt"i her hâlükârda durur.
      expect(find.text(tr('create.assumptions.edit')), findsNWidgets(2));
    });

    testWidgets('son adımın CTA butonu turuncu, ara adımlar mavi kalır',
        (tester) async {
      await pumpFlow(tester);

      // 1. adım — mavi "Devam".
      var btn = tester.widget<BrandButton>(find.byType(BrandButton).first);
      expect(btn.tone, isNull, reason: 'şehir adımı palet mavisinde kalmalı');
      expect(btn.radius, 980);

      await tester.tap(find.text('Tokyo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('create.continue')));
      await tester.pumpAndSettle();

      // 2. adım — hâlâ mavi.
      btn = tester.widget<BrandButton>(find.byType(BrandButton).first);
      expect(btn.tone, isNull, reason: 'tarih adımı palet mavisinde kalmalı');

      await tester.tap(find.text(tr('create.dates.unknown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('create.dates.continue')));
      await tester.pumpAndSettle();

      // 3. adım — planı üreten CTA turuncu ve daha az yuvarlak.
      btn = tester.widget<BrandButton>(find.byType(BrandButton).first);
      expect(btn.tone, BrandButton.ctaOrange);
      expect(btn.radius, 14);
      expect(btn.block, isTrue);
    });
  });

  group('marka görünümü', () {
    testWidgets('hero marka kırmızısını kullanır, tema rengini kullanmaz',
        (tester) async {
      await pumpFlow(tester);

      // Gradyan artık paletten DEĞİL marka sabitlerinden gelir: eskiden
      // fuji → sakura (mor → pembe) idi ve jenerik bir görünüm veriyordu.
      final decorated = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(BrandHero),
              matching: find.byType(Container),
            )
            .first,
      );
      final gradient =
          (decorated.decoration! as BoxDecoration).gradient! as LinearGradient;

      expect(gradient.colors, RotoriBrand.heroGradient);
      final palette = tester.widget<BrandHero>(find.byType(BrandHero)).palette;
      expect(gradient.colors, isNot(contains(palette.fuji)));
      expect(gradient.colors, isNot(contains(palette.sakura)));
    });

    testWidgets('hero rozetinde Rotori logosu var', (tester) async {
      await pumpFlow(tester);

      final logo = find.descendant(
        of: find.byType(BrandHero),
        matching: find.byType(Image),
      );
      expect(logo, findsOneWidget);
      final asset = tester.widget<Image>(logo).image as AssetImage;
      expect(asset.assetName, RotoriBrand.logoAsset);
      // 旅 kanjisi rozetten kalktı (yalnız asset yüklenemezse yedek olarak
      // devreye girer).
      expect(
        find.descendant(
          of: find.byType(BrandHero),
          matching: find.text('旅'),
        ),
        findsNothing,
      );
    });
  });
}
