import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/core/l10n.dart';
import 'package:rotori/features/price_tag_scanner/view/scanner_screen.dart';

void main() {
  testWidgets('fiyat tarayıcı premium uyarısı ortak standardı kullanır',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LanguageScope(
          lang: AppLang.tr,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPriceTagPremiumSheet(context),
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('rotori-premium-sheet')),
      findsOneWidget,
    );
    expect(find.text('Rotori Pro özelliği'), findsOneWidget);
    expect(find.text('Anladım'), findsOneWidget);
  });
}
