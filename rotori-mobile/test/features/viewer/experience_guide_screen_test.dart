// Eğlence rehberi — indeks ekranı.
//
// Ekran artık yalnızca SEÇTİRİYOR ve gruplar KATEGORİ değil BİLET
// PENCERESİ: en acil rehber en üstte. İçerik `ExperienceDetailScreen`'e
// taşındı (bkz. experience_detail_screen_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/data/plans_repository.dart';
import 'package:rotori/domain/experience_guides.dart';
import 'package:rotori/domain/plan_generation.dart';
import 'package:rotori/features/plans/premium_provider.dart';
import 'package:rotori/features/viewer/experience_detail_screen.dart';
import 'package:rotori/features/viewer/experience_guide_screen.dart';
import 'package:rotori/features/viewer/viewer_theme.dart';
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

  testWidgets('altı rehber aciliyet gruplarında listelenir', (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Eğlence rehberi'), findsOneWidget);

    // Gruplar kategori değil BİLET PENCERESİ.
    expect(find.text('TEMA PARKLARI'), findsNothing);
    expect(find.textContaining('ÖNCE BUNU AL'), findsOneWidget);
    expect(find.text('BİRKAÇ HAFTA ÖNCE'), findsOneWidget);
    expect(find.text('SON HAFTALARDA YETER'), findsOneWidget);

    for (final guide in kExperienceGuides) {
      expect(
        find.byKey(ValueKey('experience-guide-card-${guide.id}')),
        findsOneWidget,
        reason: '${guide.id} satırı yok',
      );
      expect(find.text(guide.title), findsOneWidget);
    }
  });

  testWidgets('en acil grup en üstte durur', (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    double topOf(String id) => tester
        .getTopLeft(find.byKey(ValueKey('experience-guide-card-$id')))
        .dy;

    // 60 gün (USJ, Disney) → 28 gün (teamLab Planets) → 14 gün (Botanical).
    expect(topOf('usj'), lessThan(topOf('teamlab-planets')));
    expect(topOf('teamlab-planets'), lessThan(topOf('teamlab-botanical')));
  });

  testWidgets('324px hero kaldırıldı', (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // Eski hero başlığı ve SliverAppBar gitti; ilk ekran doğrudan içerik.
    expect(find.textContaining('Bilet Hazır'), findsNothing);
    expect(find.byType(SliverAppBar), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('satıra dokununca detay ekranı açılır', (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.byType(ExperienceDetailScreen), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('experience-guide-card-disneyland')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ExperienceDetailScreen), findsOneWidget);
    expect(find.text('Tokyo Disneyland'), findsWidgets);
    expect(find.textContaining('11–13 saat'), findsWidgets);
  });

  testWidgets('kategori filtresi yoktur', (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Tümü'), findsNothing);
    expect(find.text('Tema parkları'), findsNothing);
  });

  testWidgets('grup kapları nötr yüzey dilini kullanır', (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final groups = find.byType(ExperienceGroup);
    expect(groups, findsNWidgets(3));

    for (var i = 0; i < 3; i++) {
      final container = tester.widget<Container>(
        find
            .descendant(of: groups.at(i), matching: find.byType(Container))
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, ViewerPalette.appleLight.card, reason: 'grup $i');
      expect(decoration.gradient, isNull, reason: 'grup $i');
    }
  });

  testWidgets('tazelik notu listenin altında ve kart değil', (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final note = find.byKey(const ValueKey('experience-freshness-note'));
    expect(note, findsOneWidget);
    // Artık dolu bir kart değil, sessiz bir dipnot.
    expect(tester.widget(note), isA<Padding>());

    // Konumu: son satırın ALTINDA.
    final lastCard = find.byKey(
      ValueKey('experience-guide-card-${kExperienceGuides.last.id}'),
    );
    expect(
      tester.getTopLeft(note).dy,
      greaterThan(tester.getTopLeft(lastCard).dy),
    );
  });

  testWidgets('her satırda hatırlatıcı butonu vardır', (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    for (final guide in kExperienceGuides) {
      expect(
        find.byKey(ValueKey('experience-reminder-${guide.id}')),
        findsOneWidget,
        reason: '${guide.id} satırında hatırlatıcı yok',
      );
    }
  });

  testWidgets('satırdaki zil Rotori hatırlatıcısını açar', (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('experience-reminder-usj')));
    await tester.pumpAndSettle();

    expect(find.text('Rotori hatırlatıcısı'), findsOneWidget);
    expect(find.byKey(const ValueKey('reminder-preset-usj-express')),
        findsOneWidget);
  });

  testWidgets('ücretsiz kullanıcıya zilden Premium kapısı çıkar',
      (tester) async {
    SharedPreferences.setMockInitialValues({kPremiumPrefsKey: false});
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('experience-reminder-usj')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('reminder-premium-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('reminder-preset-usj-express')),
        findsNothing);
  });

  group('plana ekle çipi', () {
    Widget withTrip() => ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWith(
              (ref) async => SharedPreferences.getInstance(),
            ),
          ],
          child: MaterialApp(
            home: ExperienceGuideScreen(
              trip: buildTripFromCities(
                cityKeys: const ['tokyo'],
                startYmd: '2026-10-15',
                endYmd: '2026-10-21',
              ),
            ),
          ),
        );

    testWidgets('plan yokken çip hiç gösterilmez', (tester) async {
      tallViewport(tester);
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.text('Plana ekle'), findsNothing);
    });

    testWidgets('plan varken her satırda ETİKETSİZ ikon vardır',
        (tester) async {
      tallViewport(tester);
      await tester.pumpWidget(withTrip());
      await tester.pumpAndSettle();

      for (final guide in kExperienceGuides) {
        expect(
          find.byKey(ValueKey('experience-add-to-plan-${guide.id}')),
          findsOneWidget,
          reason: '${guide.id} satırında ikon yok',
        );
      }

      // Etiket YOK: altı satırda tekrarlanan "Plana ekle" yazısı sayfanın en
      // yüksek sesli öğesi oluyor ve başlıkları kırpıyordu. Anlamı tooltip ve
      // Semantics taşıyor.
      expect(find.text('Plana ekle'), findsNothing);
      expect(
        find.byTooltip('Plana ekle'),
        findsNWidgets(kExperienceGuides.length),
      );
      expect(
        find.byIcon(Icons.playlist_add_rounded),
        findsNWidgets(kExperienceGuides.length),
      );
    });

    // Başlık bütçesi.
    //
    // **Why eşik testi, "hiç kırpılmasın" değil:** en uzun başlıklar
    // (Universal Studios Japan, teamLab Botanical Garden) 375px'te YALNIZ zil
    // varken de sığmıyor — ellipsis bu ekranın önceden beri kabul ettiği
    // davranış. Buradaki risk farklı: sağa ikinci bir aksiyon eklemek
    // başlığın payını sessizce eritebilir. Eşik onu yakalar.
    testWidgets('ikinci aksiyon başlık payını 190px altına düşürmez',
        (tester) async {
      tester.view.physicalSize = const Size(375, 6200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(withTrip());
      await tester.pumpAndSettle();

      for (final guide in kExperienceGuides) {
        expect(
          tester.getSize(find.text(guide.title)).width,
          greaterThanOrEqualTo(190),
          reason: '${guide.id} başlığına kalan yer daraldı',
        );
      }
    });

    // Satır zaten rozet + başlık + zil taşıyor; çip dar telefonda taşmamalı.
    testWidgets('375px genişlikte satır taşmaz', (tester) async {
      tester.view.physicalSize = const Size(375, 6200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(withTrip());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('çip gün seçiciyi açar', (tester) async {
      tallViewport(tester);
      await tester.pumpWidget(withTrip());
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('experience-add-to-plan-disneyland')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hangi güne eklensin?'), findsOneWidget);
      // Satırın kendisi açılmadı — çip dokunuşu soğurdu.
      expect(find.byType(ExperienceDetailScreen), findsNothing);
    });
  });
}
