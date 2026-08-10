// "Rotan gereksiz uzun görünüyor" kartı — yalnız gerçek sorunda görünür.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rotori/core/l10n.dart';
import 'package:rotori/domain/route_sanity.dart';
import 'package:rotori/features/plans/create/route_warning_card.dart';
import 'package:rotori/features/viewer/viewer_theme.dart';

String tr(String key) => L10n.resolve(key, AppLang.tr);

void main() {
  const palette = ViewerPalette.appleLight;

  Widget harness(
    List<String> order, {
    void Function(List<String>)? onApply,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RouteWarningCard(
              palette: palette,
              sanity: checkRouteOrder(order),
              currentOrder: order,
              onApply: onApply ?? (_) {},
            ),
          ),
        ),
      );

  testWidgets('mantıksız rotada uyarı + öneri gösterir', (tester) async {
    await tester.pumpWidget(
      harness(const ['tokyo', 'nara', 'sapporo', 'kyoto']),
    );
    await tester.pumpAndSettle();

    expect(find.text(tr('create.route.longTitle')), findsOneWidget);
    expect(find.text(tr('create.route.current')), findsOneWidget);
    expect(find.text(tr('create.route.fix')), findsOneWidget);
    // Kazanç km'si metne giriyor mu?
    expect(find.textContaining('KM'), findsOneWidget);
  });

  testWidgets('mantıklı rotada HİÇ render edilmez', (tester) async {
    await tester.pumpWidget(
      harness(const ['tokyo', 'kyoto', 'osaka', 'nara']),
    );
    await tester.pumpAndSettle();

    expect(find.text(tr('create.route.longTitle')), findsNothing);
  });

  testWidgets('tek şehirde görünmez', (tester) async {
    await tester.pumpWidget(harness(const ['tokyo']));
    await tester.pumpAndSettle();
    expect(find.text(tr('create.route.longTitle')), findsNothing);
  });

  testWidgets('düzelt butonu önerilen sırayı geri verir', (tester) async {
    List<String>? applied;
    await tester.pumpWidget(harness(
      const ['tokyo', 'nara', 'sapporo', 'kyoto'],
      onApply: (o) => applied = o,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(tr('create.route.fix')));
    await tester.pumpAndSettle();

    expect(applied, isNotNull);
    expect(applied!.first, 'tokyo', reason: 'iniş şehri değişmemeli');
    expect(applied!.toSet(), {'tokyo', 'nara', 'sapporo', 'kyoto'});
    expect(applied, isNot(['tokyo', 'nara', 'sapporo', 'kyoto']),
        reason: 'sıra gerçekten değişmeliydi');
  });

  testWidgets('375px dar ekranda taşma olmaz', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness(const ['tokyo', 'nara', 'sapporo', 'kyoto', 'fukuoka']),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
