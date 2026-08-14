// Aciliyet gruplaması — bilet penceresinden türetilir.
//
// Kritik sözleşme: sıralama SERBEST METİNDEN değil, `BookingWindow.
// opensBeforeDays` sayısından gelir. Metinden ayıklamak dile bağımlı ve
// kırılgan olurdu ("45–60 gün önce kontrol et").

import 'package:flutter_test/flutter_test.dart';

import 'package:rotori/domain/booking_windows.dart';
import 'package:rotori/domain/experience_guides.dart';
import 'package:rotori/domain/localized_text.dart';
import 'package:rotori/features/viewer/experience_urgency.dart';

void main() {
  ExperienceGuide guideById(String id) =>
      kExperienceGuides.firstWhere((g) => g.id == id);

  test('lead time yapısal veriden okunur', () {
    expect(experienceLeadDays(guideById('usj')), 60);
    expect(experienceLeadDays(guideById('disneyland')), 60);
    expect(experienceLeadDays(guideById('teamlab-planets')), 28);
    expect(experienceLeadDays(guideById('teamlab-botanical')), 14);
  });

  test('kovalar eşiklere göre ayrılır', () {
    expect(experienceUrgency(guideById('usj')), ExperienceUrgency.early);
    expect(
      experienceUrgency(guideById('teamlab-planets')),
      ExperienceUrgency.weeks,
    );
    expect(
      experienceUrgency(guideById('teamlab-botanical')),
      ExperienceUrgency.late_,
    );
  });

  test('gruplar en acilden başlar ve hiçbir rehber kaybolmaz', () {
    final groups = groupExperiencesByUrgency();

    expect(groups.map((g) => g.urgency).toList(), [
      ExperienceUrgency.early,
      ExperienceUrgency.weeks,
      ExperienceUrgency.late_,
    ]);

    final flattened = groups.expand((g) => g.guides).toList();
    expect(flattened.length, kExperienceGuides.length);
    expect(
      flattened.map((g) => g.id).toSet(),
      kExperienceGuides.map((g) => g.id).toSet(),
    );
  });

  test('kova içinde uzun lead time önce gelir', () {
    for (final group in groupExperiencesByUrgency()) {
      final days = group.guides.map(experienceLeadDays).toList();
      for (var i = 1; i < days.length; i++) {
        expect(
          days[i - 1] ?? 0,
          greaterThanOrEqualTo(days[i] ?? 0),
          reason: '${group.urgency} kovası sıralı değil: $days',
        );
      }
    }
  });

  test('boş kova döndürülmez', () {
    final onlyEarly = groupExperiencesByUrgency([guideById('usj')]);
    expect(onlyEarly, hasLength(1));
    expect(onlyEarly.single.urgency, ExperienceUrgency.early);
  });

  test('bilinmeyen pencere en az acil kovaya düşer', () {
    // reminderWindowId'si kataloğa karşılık gelmeyen bir rehber uydur.
    const orphan = ExperienceGuide(
      id: 'orphan',
      kind: ExperienceGuideKind.digitalArt,
      emoji: '❓',
      title: 'Orphan',
      city: 'Tokyo',
      tagline: LText('x', 'x'),
      duration: LText('1 saat', '1 hour'),
      arrivalBuffer: LText('x', 'x'),
      bookingWindow: LText('x', 'x'),
      bestFor: LText('x', 'x'),
      ticketSteps: [LText('x', 'x')],
      timeline: [],
      highlights: [],
      tips: [LText('x', 'x')],
      officialUrl: 'https://example.com',
      reminderWindowId: 'bilinmeyen-pencere',
    );

    expect(bookingWindowById('bilinmeyen-pencere'), isNull);
    expect(experienceLeadDays(orphan), isNull);
    expect(experienceUrgency(orphan), ExperienceUrgency.late_);
  });
}
