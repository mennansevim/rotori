import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/features/shared/rotori_premium_sheet.dart';

void main() {
  testWidgets(
      'premium uyarısı ortak mor-altın yüzeyi ve tek kapatma aksiyonunu kullanır',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showRotoriPremiumSheet<void>(
              context,
              title: 'Rotori Pro özelliği',
              body: 'Bu özellik Rotori Pro ile açılır.',
              closeLabel: 'Anladım',
              benefits: const [
                RotoriPremiumBenefit(
                  icon: Icons.route_rounded,
                  text: 'Rotayı öne çıkarır',
                ),
                RotoriPremiumBenefit(
                  icon: Icons.map_rounded,
                  text: 'Durakları haritada gösterir',
                ),
              ],
            ),
            child: const Text('Aç'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('rotori-premium-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('rotori-premium-emblem')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('rotori-premium-benefit-0')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('rotori-premium-benefit-1')), findsOneWidget);
    expect(find.text('Rotori Pro özelliği'), findsOneWidget);
    expect(find.text('Anladım'), findsOneWidget);

    final surface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('rotori-premium-surface')),
    );
    final decoration = surface.decoration as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    expect(
      gradient.colors,
      const [Color(0xFF211A47), Color(0xFF3A286D)],
    );

    await tester.tap(find.text('Anladım'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rotori-premium-sheet')), findsNothing);
  });

  testWidgets('premium uyarısı büyük yazıda taşmadan kaydırılabilir',
      (tester) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showRotoriPremiumSheet<void>(
              context,
              title: 'Rotori Pro özelliği',
              body:
                  'Uzun açıklamalar büyük yazı ayarında da rahatça okunabilmeli.',
              closeLabel: 'Anladım',
              benefits: const [
                RotoriPremiumBenefit(icon: Icons.route, text: 'Birinci fayda'),
                RotoriPremiumBenefit(icon: Icons.map, text: 'İkinci fayda'),
                RotoriPremiumBenefit(icon: Icons.tune, text: 'Üçüncü fayda'),
              ],
            ),
            child: const Text('Aç'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
