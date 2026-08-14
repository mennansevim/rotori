// Deneyimi plana ekleme — gün devralma.
//
// En kritik sözleşme: KİLİTLİ duraklar korunur. Kullanıcı bileti almış
// olabilir; uçuş ve otel saatleri plan verisinden geliyor olabilir.

import 'package:flutter_test/flutter_test.dart';

import 'package:rotori/core/l10n.dart';
import 'package:rotori/domain/experience_guides.dart';
import 'package:rotori/domain/experience_plan.dart';
import 'package:rotori/domain/plan_generation.dart';
import 'package:rotori/domain/types.dart';

void main() {
  ExperienceGuide guideById(String id) =>
      kExperienceGuides.firstWhere((g) => g.id == id);

  Trip tokyoTrip() => buildTripFromCities(
        cityKeys: const ['tokyo'],
        startYmd: '2026-10-15',
        endYmd: '2026-10-21',
      );

  group('süre ayrıştırma', () {
    test('saat ifadeleri dakikaya çevrilir', () {
      expect(parseExperienceMinutes('10–12 saat'), 600);
      expect(parseExperienceMinutes('2–2,5 saat'), 120);
      expect(parseExperienceMinutes('11–13 hours'), 660);
      expect(parseExperienceMinutes('1,5–2 saat'), 90);
    });

    test('ayrıştırılamayan veya saçma değerler null döner', () {
      expect(parseExperienceMinutes('yarım gün'), isNull);
      expect(parseExperienceMinutes(''), isNull);
      // 16 saatten uzun bir "deneyim" gerçekçi değil.
      expect(parseExperienceMinutes('20 saat'), isNull);
    });

    test('katalogdaki her rehberin süresi ayrıştırılabilir', () {
      for (final guide in kExperienceGuides) {
        expect(
          parseExperienceMinutes(guide.duration.of(AppLang.tr)),
          isNotNull,
          reason: '${guide.id} süresi okunamadı',
        );
      }
    });
  });

  group('uygun günler', () {
    test('şehri eşleşen günler döner, ilk ve son gün hariç', () {
      final trip = tokyoTrip();
      final options = experienceDayOptions(trip, guideById('teamlab-planets'));

      expect(options, isNotEmpty);
      // teamLab Planets "Toyosu, Tokyo" — günün şehri "Tokyo" ile eşleşir.
      expect(options.every((o) => o.city == 'Tokyo'), isTrue);
      expect(options.any((o) => o.day.dayNumber == 1), isFalse);
      expect(
        options.any((o) => o.day.dayNumber == trip.days.length),
        isFalse,
      );
    });

    test('şehir planda yoksa boş döner', () {
      final trip = tokyoTrip();
      // USJ Osaka'da; bu plan sadece Tokyo.
      expect(experienceDayOptions(trip, guideById('usj')), isEmpty);
    });

    test('her seçenek ne kaybedileceğini bildirir', () {
      final trip = tokyoTrip();
      final option =
          experienceDayOptions(trip, guideById('teamlab-planets')).first;
      expect(
        option.replaceableCount + option.lockedCount,
        option.day.items.length,
      );
    });
  });

  group('günü devralma', () {
    test('gün deneyime ayrılır, kilitsiz duraklar silinir', () {
      final trip = tokyoTrip();
      final guide = guideById('teamlab-planets');
      final target = experienceDayOptions(trip, guide).first;
      final dayNumber = target.day.dayNumber;
      final before = target.day.items.length;

      final result = applyExperienceToDay(
        trip: trip,
        guide: guide,
        dayNumber: dayNumber,
        title: guide.title,
        description: 'x',
        durationText: '2–2,5 saat',
      );

      expect(result, isNotNull);
      expect(result!.dayNumber, dayNumber);
      expect(result.removed, before);

      final day = trip.days.firstWhere((d) => d.dayNumber == dayNumber);
      expect(day.items, hasLength(1));
      expect(day.items.single.title, guide.title);
      expect(day.items.single.durationMin, 120);
      expect(day.theme, guide.title);
      // Yeniden üretimde öne alınsın diye tercihe yazılır.
      expect(trip.preferences.mustSee, contains(guide.title));
    });

    test('KİLİTLİ duraklar korunur ve saate göre sıralanır', () {
      final trip = tokyoTrip();
      final guide = guideById('teamlab-planets');
      final target = experienceDayOptions(trip, guide).first;
      final day = trip.days.firstWhere(
        (d) => d.dayNumber == target.day.dayNumber,
      );

      // Sabah 07:00'a kilitli bir durak koy.
      final locked = day.items.first
        ..time = '07:00'
        ..scheduledTime = '07:00';
      locked.pinByUser(reason: 'Bilet alındı');
      final lockedId = locked.id;

      final result = applyExperienceToDay(
        trip: trip,
        guide: guide,
        dayNumber: day.dayNumber,
        title: guide.title,
        description: 'x',
        durationText: '2 saat',
      );

      expect(result!.keptLocked, 1);
      final after = trip.days.firstWhere((d) => d.dayNumber == day.dayNumber);
      expect(after.items.map((i) => i.id), contains(lockedId));
      // 07:00 kilitli durak, 09:00 deneyimden ÖNCE gelir.
      expect(after.items.first.id, lockedId);
      expect(after.items.last.title, guide.title);
    });

    test('bilinmeyen gün numarası null döner ve plana dokunmaz', () {
      final trip = tokyoTrip();
      final before = trip.days.map((d) => d.items.length).toList();

      final result = applyExperienceToDay(
        trip: trip,
        guide: guideById('teamlab-planets'),
        dayNumber: 999,
        title: 'x',
        description: 'x',
        durationText: '2 saat',
      );

      expect(result, isNull);
      expect(trip.days.map((d) => d.items.length).toList(), before);
    });
  });
}
