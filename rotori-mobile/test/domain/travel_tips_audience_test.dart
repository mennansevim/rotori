// Rehber maddelerinin hedef kitlesi + Suica içeriğinin bütünlüğü.

import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/core/l10n.dart' show AppLang;
import 'package:japan_trip/domain/localized_text.dart';
import 'package:japan_trip/domain/travel_tips_data.dart';

void main() {
  MustKnowSection suica() => kMustKnowSections
      .firstWhere((s) => s.title.tr.toLowerCase().contains('suica'));

  group('Suica bölümü', () {
    test('rehberde var ve hem yetişkin hem çocuk maddesi taşıyor', () {
      final s = suica();
      final adult =
          s.tips.where((t) => t.audience == MustKnowAudience.all).toList();
      final kids =
          s.tips.where((t) => t.audience == MustKnowAudience.withKids).toList();

      expect(adult.length, greaterThanOrEqualTo(4),
          reason: 'yetişkin için nasıl alınır anlatılmalı');
      expect(kids.length, greaterThanOrEqualTo(3),
          reason: 'çocuk kartı ayrı bir süreç, tek maddeye sığmaz');
    });

    test('çocuk maddeleri kritik kısıtı söylüyor', () {
      final kids = suica()
          .tips
          .where((t) => t.audience == MustKnowAudience.withKids)
          .map((t) => t.text.tr.toLowerCase())
          .join(' ');
      // Çocuk Suica'sı otomattan/telefondan ALINAMAZ — gezinin en kolay
      // gözden kaçan kısıtı bu.
      expect(kids, contains('gişe'));
      expect(kids, contains('pasaport'));
    });

    test('mobil Suica en üstte — en kolay yol önce', () {
      expect(suica().tips.first.text.tr.toLowerCase(), contains('mobil'));
    });
  });

  group('hedef kitle sözleşmesi', () {
    test('varsayılan hedef kitle herkes', () {
      const t = MustKnowTip(emoji: '·', text: LText('a', 'b'));
      expect(t.audience, MustKnowAudience.all);
    });

    test('çocuk maddeleri yalnız Suica bölümünde değil de olsa işaretli', () {
      // withKids maddesi olan her bölümün en az bir "herkese açık" maddesi
      // olmalı; aksi halde çocuksuz gezide bölüm bomboş görünürdü.
      for (final s in kMustKnowSections) {
        final hasKidTips =
            s.tips.any((t) => t.audience == MustKnowAudience.withKids);
        if (!hasKidTips) continue;
        expect(s.tips.any((t) => t.audience == MustKnowAudience.all), isTrue,
            reason: '${s.title.tr} çocuksuz gezide boş kalırdı');
      }
    });
  });

  group('içerik bütünlüğü', () {
    test('her bölümün başlığı ve en az bir maddesi var', () {
      for (final s in kMustKnowSections) {
        expect(s.title.tr, isNotEmpty);
        expect(s.title.en, isNotEmpty);
        expect(s.tips, isNotEmpty, reason: '${s.title.tr} boş');
      }
    });

    test('her madde iki dilde dolu', () {
      for (final s in kMustKnowSections) {
        for (final t in s.tips) {
          expect(t.text.tr.length, greaterThan(20),
              reason: '${s.title.tr}: TR metni çok kısa');
          expect(t.text.en.length, greaterThan(20),
              reason: '${s.title.tr}: EN metni çok kısa');
          expect(t.emoji, isNotEmpty);
        }
      }
    });

    test('of(lang) doğru dili döndürür', () {
      final t = suica().tips.first;
      expect(t.text.of(AppLang.tr), t.text.tr);
      expect(t.text.of(AppLang.en), t.text.en);
    });
  });
}
