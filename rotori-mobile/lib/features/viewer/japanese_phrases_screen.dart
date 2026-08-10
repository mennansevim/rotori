// Pratik Japonca kelimeler & cümleler ekranı — seyahatte işe yarayan frazlar.
// Görev #8.
//
// compass_screen.dart'taki _PhrasesSection görünümünün birebir taklidi: kategori
// sekmeleri (Wrap) + kopyalanabilir fraz satırları (jp büyük, romaji gri italik,
// anlam üstte). Uzun içerik olduğu için ListView. Viewer paletine uyumlu
// (Theme + ViewerPaletteScope). Satıra dokununca Japonca telaffuzu sesli okunur;
// kopyalama ayrı küçük aksiyon olarak korunur.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/language_store.dart';
import '../../data/tts_service.dart';
import '../../domain/japanese_phrases_data.dart';
import '../../domain/localized_text.dart';
import '../../domain/types.dart';
import '../plans/premium_provider.dart';
import 'offline_translator_card.dart';
import 'viewer_theme.dart';

class JapanesePhrasesScreen extends ConsumerWidget {
  const JapanesePhrasesScreen({super.key, required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(viewerPaletteProvider);
    return Theme(
      data: palette.toThemeData(),
      child: ViewerPaletteScope(
        palette: palette,
        child: _PhrasesView(trip: trip, palette: palette),
      ),
    );
  }
}

class _PhrasesView extends ConsumerStatefulWidget {
  const _PhrasesView({required this.trip, required this.palette});

  final Trip trip;
  final ViewerPalette palette;

  @override
  ConsumerState<_PhrasesView> createState() => _PhrasesViewState();
}

class _PhrasesViewState extends ConsumerState<_PhrasesView> {
  int _activeCat = 0;

  void _copy(String text, AppLang lang) {
    Clipboard.setData(ClipboardData(text: text));
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          const LText('Kopyalandı: ', 'Copied: ').of(lang) + text,
        ),
        duration: const Duration(milliseconds: 1400),
        backgroundColor: widget.palette.elevated,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Frazı ja-JP olarak seslendirir + kısa bir SnackBar ile geri bildirim
  /// verir. Web'de ses çalmazsa (voice yüklenmediyse) kullanıcı en
  /// azından çağrının tetiklendiğini görsün.
  Future<void> _speak(String text, AppLang lang) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.volume_up_rounded, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                const LText('Sesli: ', 'Speaking: ').of(lang) + text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 1400),
        backgroundColor: widget.palette.elevated,
        behavior: SnackBarBehavior.floating,
      ),
    );
    await ref.read(ttsServiceProvider).speakJa(text);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final lang = ref.watch(appLangProvider);
    final category = kJapanesePhraseCategories[_activeCat];

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          const LText(
                  'Japonca Kelimeler & Cümleler', 'Japanese Words & Phrases')
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
              'Bir ifadeye dokununca Japonca telaffuzu duyarsınız. Kopyalamak için sağdaki simgeyi kullanın.',
              'Tap a phrase to hear the Japanese pronunciation. Use the copy icon to copy it.',
            ).of(lang),
            style: TextStyle(color: palette.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 16),
          OfflineTranslatorCard(
            palette: palette,
            lang: lang,
            isPremium: ref.watch(premiumProvider),
          ),
          const SizedBox(height: 16),
          _PhraseCard(
            palette: palette,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: kJapanesePhraseCategories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => _CategoryTab(
                      category: kJapanesePhraseCategories[i],
                      selected: i == _activeCat,
                      palette: palette,
                      lang: lang,
                      onTap: () => setState(() => _activeCat = i),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final p in category.phrases)
                  _PhraseRow(
                    phrase: p,
                    palette: palette,
                    lang: lang,
                    onCopy: () => _copy(p.jp, lang),
                    onSpeak: () => _speak(p.jp, lang),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kart kabuğu — başlık ikonu + başlık/alt başlık + içerik (compass _CompassCard).
// ---------------------------------------------------------------------------

class _PhraseCard extends StatelessWidget {
  const _PhraseCard({
    required this.palette,
    required this.child,
  });

  final ViewerPalette palette;
  final Widget child;

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
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kategori sekmesi (compass _CategoryTab birebir).
// ---------------------------------------------------------------------------

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.category,
    required this.selected,
    required this.palette,
    required this.lang,
    required this.onTap,
  });

  final JpPhraseCategory category;
  final bool selected;
  final ViewerPalette palette;
  final AppLang lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          selected ? palette.accent.withValues(alpha: 0.18) : palette.elevated,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            '${category.emoji} ${category.title.of(lang)}',
            style: TextStyle(
              color: selected ? palette.accent : palette.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kopyalanabilir fraz satırı (compass _PhraseRow birebir).
// ---------------------------------------------------------------------------

class _PhraseRow extends StatelessWidget {
  const _PhraseRow({
    required this.phrase,
    required this.palette,
    required this.lang,
    required this.onCopy,
    required this.onSpeak,
  });

  final JpPhrase phrase;
  final ViewerPalette palette;
  final AppLang lang;
  final VoidCallback onCopy;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: palette.elevated,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onSpeak,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        phrase.meaning.of(lang),
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 3),
                      // Okunuş (romaji) — asıl kopyalanabilir/okunabilir metin.
                      // Boşsa jp'yi büyük göster.
                      Text(
                        (phrase.romaji != null && phrase.romaji!.isNotEmpty)
                            ? phrase.romaji!
                            : phrase.jp,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      if (phrase.romaji != null &&
                          phrase.romaji!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        // Japon karakterleri (referans) — küçük ve muted.
                        Text(
                          phrase.jp,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: const LText('Kopyala', 'Copy').of(lang),
                  child: InkResponse(
                    onTap: onCopy,
                    radius: 22,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.copy_rounded,
                        size: 19,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
