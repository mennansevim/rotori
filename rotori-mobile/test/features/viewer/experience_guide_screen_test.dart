import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/data/plans_repository.dart';
import 'package:rotori/features/plans/premium_provider.dart';
import 'package:rotori/features/viewer/experience_guide_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({kPremiumPrefsKey: true}));

  Widget harness() => ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWith(
            (ref) async => SharedPreferences.getInstance(),
          ),
        ],
        child: const MaterialApp(home: ExperienceGuideScreen()),
      );

  void tallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 6200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('başlık, USJ bilet akışı ve resmi video aksiyonu görünür',
      (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Bilet Hazır'), findsOneWidget);
    expect(find.text('Universal Studios Japan'), findsWidgets);
    expect(find.text('Biletten kapıya'), findsOneWidget);
    expect(find.byKey(const ValueKey('experience-official-video')),
        findsOneWidget);
  });

  testWidgets('Disneyland seçilince içerik ve resmi video tanıtımı güncellenir',
      (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('experience-guide-card-disneyland')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tokyo Disneyland'), findsWidgets);
    expect(find.textContaining('11–13 saat'), findsWidgets);
    expect(find.byKey(const ValueKey('experience-official-video')),
        findsOneWidget);
  });

  testWidgets('kategori filtreleri kaldırıldı ve oyuncaklar yatay kaydırılır',
      (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.text('Tümü'), findsNothing);
    expect(find.text('Tema parkları'), findsNothing);
    final highlights = tester.widget<ListView>(
      find.byKey(const ValueKey('experience-highlights-usj')),
    );
    expect(highlights.scrollDirection, Axis.horizontal);
  });

  testWidgets('rehberden Rotori hatırlatıcısı açılır', (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('experience-add-reminder')));
    await tester.pumpAndSettle();

    expect(find.text('Rotori hatırlatıcısı'), findsOneWidget);
    expect(find.byKey(const ValueKey('reminder-preset-usj-express')),
        findsOneWidget);
  });

  testWidgets('ücretsiz kullanıcıya rehberde Premium kapısı gösterilir',
      (tester) async {
    SharedPreferences.setMockInitialValues({kPremiumPrefsKey: false});
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('experience-add-reminder')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('reminder-premium-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('reminder-preset-usj-express')),
        findsNothing);
  });
}
