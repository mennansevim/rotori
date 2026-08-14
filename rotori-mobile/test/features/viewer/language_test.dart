// Dil (i18n) altyapı testleri:
//  1) Resolver birim testi — aynı anahtar TR/EN farklı metin döner; {placeholder}
//     doldurma çalışır; LanguageScope.of fallback'i TR'dir.
//  2) Widget testi — bir viewer ekranı LanguageScope(lang: en) ile İngilizce
//     etiket render eder; LanguageScope olmadan (varsayılan) Türkçe kalır.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/core/l10n.dart';
import 'package:rotori/data/plans_repository.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/viewer/budget_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Trip _sampleTrip() => Trip(
      id: 'trip-lang',
      slug: 'lang-trip',
      title: 'Dil Test',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-07-01',
      tripEnd: '2026-07-02',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-07-01', end: '2026-07-02'),
        pace: Pace.moderate,
        partySize: 2,
      ),
      days: [
        DayPlan(dayNumber: 1, date: '2026-07-01', theme: 'Gün 1', items: []),
      ],
    );

void main() {
  group('L10n resolver', () {
    test('aynı anahtar dile göre farklı metin döner', () {
      expect(L10n.resolve('budget.converter', AppLang.tr), 'Çevirici');
      expect(L10n.resolve('budget.converter', AppLang.en), 'Converter');
    });

    test('bilinmeyen anahtar kendini döner (dev sinyali)', () {
      expect(L10n.resolve('yok.boyle.anahtar', AppLang.en), 'yok.boyle.anahtar');
    });

    test('parametrize {placeholder} doldurur', () {
      final tr = L10n.parametrize(
        L10n.resolve('checklist.ready', AppLang.tr),
        {'done': '3', 'total': '8'},
      );
      final en = L10n.parametrize(
        L10n.resolve('checklist.ready', AppLang.en),
        {'done': '3', 'total': '8'},
      );
      expect(tr, '3 / 8 hazır');
      expect(en, '3 / 8 ready');
    });

    test('ay/gün dizileri dile göre değişir', () {
      expect(L10n.monthsFor(AppLang.tr)[7], 'Temmuz');
      expect(L10n.monthsFor(AppLang.en)[7], 'July');
      expect(L10n.weekdaysFor(AppLang.en)[1], 'Monday');
    });
  });

  group('LanguageScope', () {
    testWidgets('of() varsayılanı TR resolver döner (scope yoksa)',
        (tester) async {
      late LanguageScope scope;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (context) {
            scope = LanguageScope.of(context);
            return const SizedBox.shrink();
          }),
        ),
      );
      expect(scope.lang, AppLang.tr);
      expect(scope.s('budget.converter'), 'Çevirici');
    });
  });

  group('Viewer İngilizce render', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Widget harness(Trip trip, {required AppLang lang}) {
      return ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWith(
            (ref) async => SharedPreferences.getInstance(),
          ),
        ],
        child: LanguageScope(
          lang: lang,
          child: MaterialApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: BudgetScreen(trip: trip),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('lang=en İngilizce etiketleri gösterir', (tester) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(harness(_sampleTrip(), lang: AppLang.en));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('💰 Budget'), findsOneWidget);
      expect(find.text('Edit rate'), findsOneWidget);
      // Çevirici bölümü kaldırıldı; dil kontrolü artık pasta başlığı üzerinden.
      expect(find.text('Cost distribution'), findsOneWidget);
      // Türkçe karşılıkları görünmemeli.
      expect(find.text('Gider dağılımı'), findsNothing);
      expect(find.text('💰 Bütçe'), findsNothing);
    });

    testWidgets('lang=tr Türkçe kalır', (tester) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(harness(_sampleTrip(), lang: AppLang.tr));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('💰 Bütçe'), findsOneWidget);
      expect(find.text('Gider dağılımı'), findsOneWidget);
    });
  });
}
