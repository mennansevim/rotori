// Drawer "KEŞFET" bölümü — bütün araçlar tek sakin inset-group içinde.
//
// Bu test üç şeyi korur:
//   1) her keşif aracının adı ve açıklaması ekranda yazılı,
//   2) altı aksiyon aynı grupta satır olarak sunuluyor,
//   3) fiyat etiketi tarayıcı Premium durum rozetini kaybetmiyor.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rotori/core/l10n.dart';
import 'package:rotori/core/supabase_client.dart';
import 'package:rotori/domain/plan_generation.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/plans/plan_providers.dart';
import 'package:rotori/features/plans/plan_viewer_screen.dart';
import 'package:rotori/features/plans/premium_provider.dart';

String tr(String key) => L10n.resolve(key, AppLang.tr);

void main() {
  Trip weekTrip() => buildTripFromCities(
        cityKeys: const ['tokyo'],
        startYmd: '2026-10-15',
        endYmd: '2026-10-21',
      );

  Widget harness(Trip trip) => ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(null),
          planByIdProvider.overrideWith((ref, id) => Stream<Trip>.value(trip)),
        ],
        child: MaterialApp(home: PlanViewerScreen(planId: trip.id)),
      );

  Future<void> openDrawer(WidgetTester tester, Trip trip) async {
    // Uzun viewport: KEŞFET bölümü kaydırmadan görünür olsun.
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(trip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('her keşif aracı adıyla ve açıklamasıyla görünür',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await openDrawer(tester, weekTrip());

    // Adlar
    expect(find.text(tr('viewer.tt.eats')), findsOneWidget);
    expect(find.text(tr('viewer.tt.weather')), findsOneWidget);
    expect(find.text(tr('viewer.tt.budget')), findsOneWidget);
    expect(find.text(tr('viewer.tt.checklist')), findsOneWidget);
    expect(find.text(tr('scanner.price_tag')), findsOneWidget);

    // Açıklamalar — eskiden hiçbiri yazılı değildi.
    expect(find.text(tr('drawer.discover.eats.short')), findsOneWidget);
    expect(find.text(tr('drawer.discover.weather.sub')), findsOneWidget);
    expect(find.text(tr('drawer.discover.budget.sub')), findsOneWidget);
    expect(find.text(tr('drawer.discover.checklist.sub')), findsOneWidget);
    expect(find.text(tr('drawer.discover.scanner.heroSub')), findsOneWidget);
    expect(find.text(tr('viewer.tt.experienceGuide')), findsOneWidget);
    expect(
        find.text(tr('drawer.discover.experienceGuide.sub')), findsOneWidget);
  });

  testWidgets('fiyat tarayıcı kartı premium durum rozetini gösterir',
      (tester) async {
    for (final premium in [false, true]) {
      SharedPreferences.setMockInitialValues({kPremiumPrefsKey: premium});
      await openDrawer(tester, weekTrip());
      await tester.pump(const Duration(milliseconds: 200));

      final scannerHero = find.byKey(const ValueKey('drawer-scanner-hero'));
      expect(scannerHero, findsOneWidget);
      expect(
        find.descendant(
          of: scannerHero,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Text && (widget.data?.startsWith('Premium') ?? false),
          ),
        ),
        findsOneWidget,
        reason: 'premium=$premium',
      );
    }
  });

  testWidgets('keşif araçları tek sakin grupta ve satır düzeninde görünür',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await openDrawer(tester, weekTrip());

    final group = find.byKey(const ValueKey('drawer-discover-group'));
    expect(group, findsOneWidget);
    expect(
      find.descendant(
        of: group,
        matching: find.byIcon(Icons.chevron_right_rounded),
      ),
      findsNWidgets(6),
    );
    expect(
      find.descendant(
        of: group,
        matching: find.byIcon(Icons.north_east_rounded),
      ),
      findsNothing,
    );

    final gradientDecoration = find.descendant(
      of: group,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).gradient != null,
      ),
    );
    expect(gradientDecoration, findsNothing);
  });

  testWidgets('keşif ikonları renklerle ayrışır, çıkış ayrı grupta kalır',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await openDrawer(tester, weekTrip());

    final discoverGroup = find.byKey(const ValueKey('drawer-discover-group'));
    final actionIcons = <IconData>[
      Icons.document_scanner_outlined,
      Icons.attractions_rounded,
      Icons.cloud_outlined,
      Icons.account_balance_wallet_outlined,
      Icons.checklist_rounded,
      Icons.ramen_dining_rounded,
    ];
    final tones = <Color?>{
      for (final icon in actionIcons)
        tester
            .widget<Icon>(
              find.descendant(
                of: discoverGroup,
                matching: find.byIcon(icon),
              ),
            )
            .color,
    };
    expect(tones, hasLength(actionIcons.length));

    final accountActions =
        find.byKey(const ValueKey('drawer-account-actions'));
    final signOutGroup = find.byKey(const ValueKey('drawer-signout-group'));
    expect(accountActions, findsOneWidget);
    expect(signOutGroup, findsOneWidget);
    expect(
      find.descendant(
        of: accountActions,
        matching: find.text(tr('drawer.signout')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: signOutGroup,
        matching: find.text(tr('drawer.signout')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Eats kartına dokununca drawer kapanır ve Eats ekranı açılır',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await openDrawer(tester, weekTrip());

    await tester.tap(find.text(tr('drawer.discover.eats.short')));
    await tester.pumpAndSettle();

    // Yemek rehberi açıldı: kategori çipleri ve yemek sayacı geliyor.
    expect(find.text('Neyi yiyebilirsin?'), findsOneWidget);
    expect(find.textContaining('yemek'), findsWidgets);
  });

  // Premium anahtarı.
  //
  // Anahtar `kDebugMode` ile korunuyordu; önizleme hedefi (`flutter run
  // --release -t lib/preview_main.dart`) release derlendiği için orada HİÇ
  // görünmüyor, dolayısıyla premium arkasındaki ekranlar önizlemede
  // denenemiyordu. Artık `showDebugTools` bayrağına bağlı — preview girişi
  // açıyor, üretim girişi açmıyor.
  testWidgets('premium anahtarı drawer\'da görünür ve premium\'u açar',
      (tester) async {
    SharedPreferences.setMockInitialValues({kPremiumPrefsKey: false});
    final trip = weekTrip();
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: ProviderContainer(overrides: [
          currentUserProvider.overrideWithValue(null),
          planByIdProvider.overrideWith((ref, id) => Stream<Trip>.value(trip)),
        ]),
        child: MaterialApp(home: PlanViewerScreen(planId: trip.id)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final tile = find.text('Premium (debug)');
    await tester.scrollUntilVisible(
      tile,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tile, findsOneWidget);

    // Kapalı başlar, dokununca açılır.
    Switch switchWidget() => tester.widget<Switch>(find.byType(Switch));
    expect(switchWidget().value, isFalse);

    await tester.tap(tile);
    // pumpAndSettle DEĞİL: viewer'da sürekli koşan animasyonlar var (sakura
    // katmanı gibi), ağaç hiç "settle" olmuyor.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(switchWidget().value, isTrue,
        reason: 'anahtar premium durumunu değiştirmedi');
  });
}
