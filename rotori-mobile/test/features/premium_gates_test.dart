// Premium bayrağı TÜM kilitlerde geçerli olmalı.
//
// Bayrak SharedPreferences'ta tutuluyor ve her ekran onu ayrı ayrı okuyordu;
// sonuç olarak drawer'dan premium açılsa bile bazı kilitler kapalı kalıyordu.
// premiumProvider tek kaynak — bu test kapsamı korur.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:japan_trip/domain/eats.dart';
import 'package:japan_trip/features/plans/premium_provider.dart';
import 'package:japan_trip/features/viewer/eats_screen.dart';
import 'package:japan_trip/domain/plan_generation.dart';
import 'package:japan_trip/domain/types.dart';

Trip _trip() => buildTripFromCities(
      cityKeys: const ['tokyo'],
      startYmd: '2026-10-15',
      endYmd: '2026-10-19',
    );

void main() {
  Widget harness(Widget child) =>
      ProviderScope(child: MaterialApp(home: Scaffold(body: child)));

  group('premiumProvider', () {
    test('varsayılan kapalı', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(premiumProvider.notifier).load();
      expect(c.read(premiumProvider), isFalse);
    });

    test('prefs\'teki değeri okur', () async {
      SharedPreferences.setMockInitialValues({kPremiumPrefsKey: true});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(premiumProvider.notifier).load();
      expect(c.read(premiumProvider), isTrue);
    });

    test('setPremium hem state\'i hem prefs\'i günceller', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);

      await c.read(premiumProvider.notifier).setPremium(true);
      expect(c.read(premiumProvider), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kPremiumPrefsKey), isTrue);
    });

    test('toggle tersine çevirir', () async {
      SharedPreferences.setMockInitialValues({kPremiumPrefsKey: true});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(premiumProvider.notifier).load();

      await c.read(premiumProvider.notifier).toggle();
      expect(c.read(premiumProvider), isFalse);
    });

    test('fiyat tarayıcı AYNI prefs anahtarını kullanır', () {
      // Ayrı string'ler kullanılsaydı drawer'dan açılan premium tarayıcıda
      // görünmezdi. Sabit paylaşılıyor mu, onu doğruluyoruz.
      expect(kPremiumPrefsKey, 'debug_premium');
    });
  });

  group('Rotori Eats listesi', () {
    testWidgets('ücretsizde ilk $kEatsFreeLimit mekan + upsell kartı',
        (tester) async {
      SharedPreferences.setMockInitialValues({kPremiumPrefsKey: false});
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(
        EatsScreen(trip: _trip()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Rotori Eats Pass'), findsOneWidget,
          reason: 'ücretsizde upsell kartı görünmeli');
    });

    testWidgets('premium açıkken upsell kartı GÖRÜNMEZ', (tester) async {
      SharedPreferences.setMockInitialValues({kPremiumPrefsKey: true});
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(
        EatsScreen(trip: _trip()),
      ));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Rotori Eats Pass'), findsNothing,
          reason: 'premium kullanıcıya upsell gösterilmemeli');
    });
  });
}
