// Plan üretimi animasyonu — davranış testleri.
//
// Boyanan pikselleri doğrulamıyoruz (golden yok); test edilen şey sözleşme:
// katman üretim sürerken çıkar, mesajı ekran okuyucuya duyurur ve hareket
// azaltma açıkken animasyon dönmez.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rotori/core/l10n.dart';
import 'package:rotori/features/plans/create/rotori_route_loader.dart';
import 'package:rotori/features/viewer/viewer_theme.dart';

String tr(String key) => L10n.resolve(key, AppLang.tr);

void main() {
  Widget harness(Widget child, {bool reduceMotion = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(body: child),
        ),
      );

  testWidgets('yükleyici markı ve mesajı çizer', (tester) async {
    await tester.pumpWidget(
      harness(
        const RotoriRouteLoader(
          palette: ViewerPalette.appleLight,
          message: 'Planın hazırlanıyor…',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('Planın hazırlanıyor…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('animasyon boyunca hata fırlatmaz', (tester) async {
    await tester.pumpWidget(
      harness(const RotoriRouteLoader(palette: ViewerPalette.appleLight)),
    );

    // Tüm zaman çizgisini tara: her segment (kiriş, ayak, rota, sönüm) boyanır.
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'kare $i patladı');
    }
  });

  testWidgets('hareket azaltma açıkken animasyon dönmez', (tester) async {
    await tester.pumpWidget(
      harness(
        const RotoriRouteLoader(palette: ViewerPalette.appleLight),
        reduceMotion: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Dönen bir controller kalsaydı pumpAndSettle asla dönmezdi.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('katman varsayılan üretim mesajını duyurur', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      harness(const RotoriGeneratingOverlay(palette: ViewerPalette.appleLight)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(tr('create.generating')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(RegExp.escape(tr('create.generating')))),
      findsWidgets,
    );
    semantics.dispose();
  });

  testWidgets('her temada çizilir', (tester) async {
    for (final palette in const [
      ViewerPalette.japanDark,
      ViewerPalette.appleLight,
      ViewerPalette.sakuraSoft,
    ]) {
      await tester.pumpWidget(harness(RotoriRouteLoader(palette: palette)));
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull, reason: '${palette.id} patladı');
    }
  });
}
