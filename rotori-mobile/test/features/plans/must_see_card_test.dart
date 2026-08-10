// "Bunları da gör" kartı — görünürlük, seçim ve plana ekleme akışı.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rotori/core/l10n.dart';
import 'package:rotori/domain/japan_suggestions.dart';
import 'package:rotori/domain/must_see_suggestions.dart';
import 'package:rotori/domain/plan_generation.dart';
import 'package:rotori/domain/trip_factory.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/plans/widgets/must_see_card.dart';
import 'package:rotori/features/viewer/viewer_theme.dart';

String tr(String key) => L10n.resolve(key, AppLang.tr);

void main() {
  const palette = ViewerPalette.appleLight;

  Widget harness(
    Trip trip, {
    Future<HighlightPlacement> Function(List<PlaceSuggestion>)? onAdd,
    VoidCallback? onDismiss,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MustSeeCard(
              palette: palette,
              trip: trip,
              onAdd: onAdd ??
                  (picks) async => HighlightPlacement(
                        placed: {for (final p in picks) p.name: 2},
                        unplaced: const [],
                      ),
              onDismiss: onDismiss ?? () {},
            ),
          ),
        ),
      );

  Trip tokyoTrip() => buildTripFromCities(
        cityKeys: const ['tokyo', 'kyoto'],
        startYmd: '2026-10-15',
        endYmd: '2026-10-24',
      );

  testWidgets('öneri varsa kart başlık + çiplerle görünür', (tester) async {
    await tester.pumpWidget(harness(tokyoTrip()));
    await tester.pumpAndSettle();

    expect(find.text(tr('viewer.mustSee.title')), findsOneWidget);
    expect(find.text(tr('viewer.mustSee.body')), findsOneWidget);
    // En az bir öneri çipi
    expect(find.byType(InkWell), findsWidgets);
  });

  testWidgets('hiç öneri kalmadıysa kart hiç render edilmez', (tester) async {
    // Destinasyonsuz plan → missingHighlights boş.
    final trip = createEmptyTrip()..preferences.destinations.clear();
    await tester.pumpWidget(harness(trip));
    await tester.pumpAndSettle();

    expect(find.text(tr('viewer.mustSee.title')), findsNothing);
  });

  testWidgets('seçim yokken ekle butonu pasif', (tester) async {
    await tester.pumpWidget(harness(tokyoTrip()));
    await tester.pumpAndSettle();

    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull);
    expect(find.text(tr('viewer.mustSee.cta')), findsOneWidget);
  });

  testWidgets('çip seçilince buton aktifleşir ve sayıyı gösterir',
      (tester) async {
    final trip = tokyoTrip();
    final first = missingHighlights(trip, limit: 10).first;

    await tester.pumpWidget(harness(trip));
    await tester.pumpAndSettle();

    await tester.tap(find.text(first.name));
    await tester.pumpAndSettle();

    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNotNull);
    expect(
      find.text(L10n.parametrize(tr('viewer.mustSee.ctaCount'), {'n': '1'})),
      findsOneWidget,
    );
  });

  testWidgets('ekle butonu seçilen yerleri onAdd\'e geçirir', (tester) async {
    final trip = tokyoTrip();
    final picks = missingHighlights(trip, limit: 10);
    List<PlaceSuggestion>? received;

    await tester.pumpWidget(harness(
      trip,
      onAdd: (p) async {
        received = p;
        return HighlightPlacement(
          placed: {for (final x in p) x.name: 2},
          unplaced: const [],
        );
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(picks[0].name));
    await tester.tap(find.text(picks[1].name));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(received, isNotNull);
    expect(received!.map((p) => p.name).toSet(),
        {picks[0].name, picks[1].name});
  });

  testWidgets('çipe ikinci dokunuş seçimi kaldırır', (tester) async {
    final trip = tokyoTrip();
    final first = missingHighlights(trip, limit: 10).first;

    await tester.pumpWidget(harness(trip));
    await tester.pumpAndSettle();

    await tester.tap(find.text(first.name));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);

    await tester.tap(find.text(first.name));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });

  testWidgets('✕ onDismiss tetikler', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(
      harness(tokyoTrip(), onDismiss: () => dismissed = true),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
  });

  testWidgets('375px dar ekranda taşma olmaz', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(tokyoTrip()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
