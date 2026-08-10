import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/core/l10n.dart';
import 'package:rotori/domain/experience_guides.dart';

void main() {
  test('ana tema parkı ve teamLab seçenekleri eksiksizdir', () {
    expect(
      kExperienceGuides.map((guide) => guide.id),
      containsAll(<String>[
        'usj',
        'disneyland',
        'disneysea',
        'teamlab-planets',
        'teamlab-borderless',
        'teamlab-botanical',
      ]),
    );
    expect(
      kExperienceGuides
          .where((guide) => guide.kind == ExperienceGuideKind.themePark),
      hasLength(3),
    );
    expect(
      kExperienceGuides
          .where((guide) => guide.kind == ExperienceGuideKind.digitalArt),
      hasLength(3),
    );
  });

  test('her rehber bilet, zaman çizelgesi, vurgu ve resmi kaynak taşır', () {
    for (final guide in kExperienceGuides) {
      expect(guide.ticketSteps.length, greaterThanOrEqualTo(4),
          reason: guide.id);
      expect(guide.timeline.length, greaterThanOrEqualTo(4), reason: guide.id);
      expect(guide.highlights.length, greaterThanOrEqualTo(3),
          reason: guide.id);
      expect(guide.tips.length, greaterThanOrEqualTo(3), reason: guide.id);
      expect(Uri.parse(guide.officialUrl).isScheme('https'), isTrue,
          reason: guide.id);
      expect(guide.duration.of(AppLang.tr), isNotEmpty, reason: guide.id);
      expect(guide.duration.of(AppLang.en), isNotEmpty, reason: guide.id);
    }
  });

  test('tema parkları güvenli resmi video yönlendirmesi taşır', () {
    final withVideo = kExperienceGuides
        .where((guide) => guide.videoUrl != null)
        .map((guide) => guide.id);
    expect(withVideo, containsAll(['usj', 'disneyland', 'disneysea']));
    expect(
      kExperienceGuides.first.videoUrl,
      contains('youtube.com/user/usjTV'),
    );
  });

  test('her rehber sonradan eklenebilir hatırlatıcı seçimine bağlıdır', () {
    for (final guide in kExperienceGuides) {
      expect(guide.reminderWindowId, isNotNull, reason: guide.id);
    }
  });
}
