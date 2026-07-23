// "Mutlaka bilmeniz gerekenler" — Japonya seyahati öncesi/esnası için pratik
// tavsiyeler ve uyarılar. Belgeler, para, ulaşım, elektronik, sağlık, valiz,
// görgü kuralları ve genel notlar bölümleri madde madde listelenir.
//
// Görsel iskelet compass_screen.dart ile birebir aynıdır: Theme + palette +
// ViewerPaletteScope + geri butonlu AppBar + ListView içinde kart bölümler.
// Her bölüm bir kart (emoji + başlık + madde satırları) — _InfoSection/
// CompassInfoCard görünümünün taklidi.
//
// i18n: Tüm kullanıcı metni `LText(tr, en).of(lang)` ile iki dilli; aktif dil
// `appLangProvider`'dan okunur. Japonca/romaji terimler literal kalır.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/language_store.dart';
import '../../domain/localized_text.dart';
import '../../domain/travel_tips_data.dart';
import '../../domain/types.dart';
import 'viewer_theme.dart';

class MustKnowScreen extends ConsumerWidget {
  const MustKnowScreen({super.key, required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(viewerPaletteProvider);
    final lang = ref.watch(appLangProvider);
    return Theme(
      data: palette.toThemeData(),
      child: ViewerPaletteScope(
        palette: palette,
        child: _MustKnowView(palette: palette, lang: lang),
      ),
    );
  }
}

class _MustKnowView extends StatelessWidget {
  const _MustKnowView({required this.palette, required this.lang});

  final ViewerPalette palette;
  final AppLang lang;

  /// Bölümlere sırayla dağıtılan vurgu renkleri (compass'taki çok renkli görünüm).
  static const _accentOrder = <int>[0, 1, 2, 3, 4, 5];

  Color _accentFor(int index) {
    switch (_accentOrder[index % _accentOrder.length]) {
      case 0:
        return palette.sky;
      case 1:
        return palette.gold;
      case 2:
        return palette.matcha;
      case 3:
        return palette.sunset;
      case 4:
        return palette.sakura;
      default:
        return palette.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          const LText('Mutlaka Bilmeniz Gerekenler', 'Must-Know Before You Go')
              .of(lang),
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        backgroundColor: palette.card,
        foregroundColor: palette.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Text(
            const LText(
              'Japonya\'ya çıkmadan önce ve yolda işine yarayacak pratik '
              'tavsiyeler ve uyarılar.',
              'Practical tips and warnings that will help you before and during '
              'your trip to Japan.',
            ).of(lang),
            style: TextStyle(color: palette.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < kMustKnowSections.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _SectionCard(
              section: kMustKnowSections[i],
              palette: palette,
              lang: lang,
              accent: _accentFor(i),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bölüm kartı — emoji rozeti + başlık + madde satırları (compass _CompassCard).
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.palette,
    required this.lang,
    required this.accent,
  });

  final MustKnowSection section;
  final ViewerPalette palette;
  final AppLang lang;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  section.emoji,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  section.title.of(lang),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final tip in section.tips)
            _TipRow(tip: tip, palette: palette, lang: lang, accent: accent),
        ],
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({
    required this.tip,
    required this.palette,
    required this.lang,
    required this.accent,
  });

  final MustKnowTip tip;
  final ViewerPalette palette;
  final AppLang lang;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: palette.elevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(tip.emoji, style: const TextStyle(fontSize: 15)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tip.text.of(lang),
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
