// Eğlence rehberi — detay ekranı.
//
// Sözleşme: özet ÜSTTE ve tek; dört bölüm katlanır ve aynı anda yalnız biri
// açık. Yüzeyler nötr (gradyan yok) — eski overview kartı doygun kırmızı bir
// gradyandı.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/core/l10n.dart';
import 'package:rotori/data/plans_repository.dart';
import 'package:rotori/domain/experience_guides.dart';
import 'package:rotori/domain/experience_plan.dart';
import 'package:rotori/domain/plan_generation.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/plans/premium_provider.dart';
import 'package:rotori/features/viewer/experience_detail_screen.dart';
import 'package:rotori/features/viewer/viewer_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({kPremiumPrefsKey: true}));

  ExperienceGuide guideById(String id) =>
      kExperienceGuides.firstWhere((g) => g.id == id);

  Widget harness(ExperienceGuide guide) => ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWith(
            (ref) async => SharedPreferences.getInstance(),
          ),
        ],
        child: MaterialApp(home: ExperienceDetailScreen(guide: guide)),
      );

  void tallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 6200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('özet kartı künye ve üç metriği gösterir', (tester) async {
    tallViewport(tester);
    final guide = guideById('teamlab-planets');
    await tester.pumpWidget(harness(guide));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('experience-overview-card')),
        findsOneWidget);
    expect(find.text(guide.title), findsWidgets);
    expect(find.text(guide.city), findsOneWidget);
    expect(find.text('Süre'), findsOneWidget);
    expect(find.text('Erken git'), findsOneWidget);
    expect(find.text('Rezerve'), findsOneWidget);
    expect(find.text(guide.duration.of(AppLang.tr)), findsWidgets);
  });

  testWidgets('özet değerleri tam metin olarak sığar', (tester) async {
    // Regresyon: bu alanlar sayı değil cümle. Üç kolonluk metrik şeridinde
    // "Kapıdan 45–60 dk önce" taşıyor, kart kenarını aşıyordu.
    tallViewport(tester);
    final guide = guideById('usj');
    await tester.pumpWidget(harness(guide));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final card = find.byKey(const ValueKey('experience-overview-card'));
    final cardRight = tester.getRect(card).right;
    for (final value in [
      guide.duration.of(AppLang.tr),
      guide.arrivalBuffer.of(AppLang.tr),
      guide.bookingWindow.of(AppLang.tr),
    ]) {
      final text = find.text(value);
      expect(text, findsWidgets, reason: '$value görünmüyor');
      expect(
        tester.getRect(text.first).right,
        lessThanOrEqualTo(cardRight),
        reason: '"$value" kartın dışına taşıyor',
      );
    }
  });

  testWidgets('hatırlatıcı metni fiili tekrar etmez', (tester) async {
    // Regresyon: `bookingWindow` zaten "…kontrol et" ile bitiyor; şablon
    // sonuna bir "kontrol et" daha ekleyince metin tekrarlıyordu.
    tallViewport(tester);
    await tester.pumpWidget(harness(guideById('usj')));
    await tester.pumpAndSettle();

    expect(find.textContaining('kontrol et kontrol et'), findsNothing);
    expect(
      find.textContaining('45–60 gün önce kontrol et. Rotori'),
      findsOneWidget,
    );
  });

  testWidgets('dört bölüm kapalı başlar, adetleri görünür', (tester) async {
    tallViewport(tester);
    final guide = guideById('usj');
    await tester.pumpWidget(harness(guide));
    await tester.pumpAndSettle();

    for (final title in [
      'Biletten kapıya',
      'Örnek akış',
      'Kaçırma',
      'İşi kurtaran ipuçları',
    ]) {
      expect(find.text(title), findsOneWidget, reason: '$title bölümü yok');
    }

    // Kapalıyken bölüm gövdeleri render edilmez.
    expect(find.text(guide.ticketSteps.first.of(AppLang.tr)), findsNothing);
  });

  testWidgets('bölüm açılıp kapanır', (tester) async {
    tallViewport(tester);
    final guide = guideById('usj');
    await tester.pumpWidget(harness(guide));
    await tester.pumpAndSettle();

    final firstStep = guide.ticketSteps.first.of(AppLang.tr);

    await tester.tap(find.text('Biletten kapıya'));
    await tester.pumpAndSettle();
    expect(find.text(firstStep), findsOneWidget);

    await tester.tap(find.text('Biletten kapıya'));
    await tester.pumpAndSettle();
    expect(find.text(firstStep), findsNothing);
  });

  testWidgets('aynı anda tek bölüm açık kalır', (tester) async {
    tallViewport(tester);
    final guide = guideById('usj');
    await tester.pumpWidget(harness(guide));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Biletten kapıya'));
    await tester.pumpAndSettle();
    expect(find.text(guide.ticketSteps.first.of(AppLang.tr)), findsOneWidget);

    await tester.tap(find.text('Örnek akış'));
    await tester.pumpAndSettle();

    // Bilet adımları kapandı, akış açıldı.
    expect(find.text(guide.ticketSteps.first.of(AppLang.tr)), findsNothing);
    expect(find.text(guide.timeline.first.title.of(AppLang.tr)), findsOneWidget);
  });

  testWidgets('öne çıkanlar açılınca dikey listede görünür', (tester) async {
    tallViewport(tester);
    final guide = guideById('usj');
    await tester.pumpWidget(harness(guide));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kaçırma'));
    await tester.pumpAndSettle();

    final highlights = find.byKey(ValueKey('experience-highlights-${guide.id}'));
    expect(highlights, findsOneWidget);
    for (final h in guide.highlights) {
      expect(find.text(h.title.of(AppLang.tr)), findsOneWidget);
    }
    // Yatay kaydırma şeridi bilinçli olarak kaldırıldı.
    expect(
      find.descendant(of: highlights, matching: find.byType(ListView)),
      findsNothing,
    );
  });

  testWidgets('bilgi kartları nötr yüzey dilini kullanır', (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness(guideById('usj')));
    await tester.pumpAndSettle();

    for (final key in [
      'experience-overview-card',
      'experience-reminder-card',
      'experience-sections',
      'experience-official-actions',
    ]) {
      final container = tester.widget<Container>(find.byKey(ValueKey(key)));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, ViewerPalette.appleLight.card, reason: key);
      expect(decoration.gradient, isNull, reason: key);
    }
  });

  testWidgets('resmî bağlantılar tek satır grubunda toplanır', (tester) async {
    // Eskiden dolu buton + çerçeveli buton + ayrı kart vardı: üç görsel dil.
    tallViewport(tester);
    await tester.pumpWidget(harness(guideById('usj')));
    await tester.pumpAndSettle();

    final group = find.byKey(const ValueKey('experience-official-actions'));
    expect(group, findsOneWidget);

    // Grup içinde buton yığını yok, üçü de aynı satır anatomisinde.
    expect(
      find.descendant(of: group, matching: find.byType(FilledButton)),
      findsNothing,
    );
    expect(
      find.descendant(of: group, matching: find.byType(OutlinedButton)),
      findsNothing,
    );
    for (final key in [
      'experience-official-link',
      'experience-official-app',
      'experience-official-video',
    ]) {
      expect(
        find.descendant(of: group, matching: find.byKey(ValueKey(key))),
        findsOneWidget,
        reason: '$key grubun içinde değil',
      );
    }

    // Ekranda tek birincil buton kalır: hatırlatıcı.
    expect(find.byType(FilledButton), findsOneWidget);
  });

  testWidgets('resmî aksiyonlar ve video görünür', (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness(guideById('usj')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('experience-official-link')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('experience-official-video')), findsOneWidget);
  });

  testWidgets('detaydan Rotori hatırlatıcısı açılır', (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness(guideById('usj')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('experience-add-reminder')));
    await tester.pumpAndSettle();

    expect(find.text('Rotori hatırlatıcısı'), findsOneWidget);
    expect(find.byKey(const ValueKey('reminder-preset-usj-express')),
        findsOneWidget);
  });

  testWidgets('ücretsiz kullanıcıya Premium kapısı gösterilir',
      (tester) async {
    SharedPreferences.setMockInitialValues({kPremiumPrefsKey: false});
    tallViewport(tester);
    await tester.pumpWidget(harness(guideById('usj')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('experience-add-reminder')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('reminder-premium-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('reminder-preset-usj-express')),
        findsNothing);
  });

  group('plana ekle', () {
    Trip tokyoTrip() => buildTripFromCities(
          cityKeys: const ['tokyo'],
          startYmd: '2026-10-15',
          endYmd: '2026-10-21',
        );

    Widget withTrip(ExperienceGuide guide, Trip trip) => ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWith(
              (ref) async => SharedPreferences.getInstance(),
            ),
          ],
          child: MaterialApp(
            home: ExperienceDetailScreen(guide: guide, trip: trip),
          ),
        );

    testWidgets('plan yokken buton hiç gösterilmez', (tester) async {
      tallViewport(tester);
      await tester.pumpWidget(harness(guideById('teamlab-planets')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('experience-add-to-plan')),
        findsNothing,
      );
    });

    testWidgets('plan varken buton görünür', (tester) async {
      tallViewport(tester);
      await tester.pumpWidget(
        withTrip(guideById('teamlab-planets'), tokyoTrip()),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('experience-add-to-plan')),
        findsOneWidget,
      );
      expect(find.text('Plana ekle'), findsOneWidget);
    });

    testWidgets('gün seçici açılır ve seçilen gün deneyime ayrılır',
        (tester) async {
      tallViewport(tester);
      final trip = tokyoTrip();
      final guide = guideById('teamlab-planets');
      await tester.pumpWidget(withTrip(guide, trip));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('experience-add-to-plan')));
      await tester.pumpAndSettle();

      expect(find.text('Hangi güne eklensin?'), findsOneWidget);

      final options = experienceDayOptions(trip, guide);
      final first = options.first.day.dayNumber;
      await tester.tap(
        find.byKey(ValueKey('experience-day-$first')),
      );
      await tester.pumpAndSettle();

      final day = trip.days.firstWhere((d) => d.dayNumber == first);
      expect(day.items.map((i) => i.title), contains(guide.title));
      expect(day.theme, guide.title);
    });

    testWidgets('şehir planda yoksa açıklayıcı mesaj çıkar', (tester) async {
      tallViewport(tester);
      // USJ Osaka'da; plan sadece Tokyo.
      await tester.pumpWidget(withTrip(guideById('usj'), tokyoTrip()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('experience-add-to-plan')));
      await tester.pumpAndSettle();

      expect(find.text('Hangi güne eklensin?'), findsNothing);
      expect(find.textContaining('uygun gün bulunamadı'), findsOneWidget);
    });
  });

  testWidgets('altı rehberin hepsi hatasız render edilir', (tester) async {
    tallViewport(tester);
    for (final guide in kExperienceGuides) {
      await tester.pumpWidget(harness(guide));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '${guide.id} patladı');
      expect(find.byKey(const ValueKey('experience-overview-card')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('experience-reminder-card')),
          findsOneWidget);
    }
  });
}
