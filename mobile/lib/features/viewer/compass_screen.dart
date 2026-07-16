// Pusula — cepte taşınan hızlı başvuru ekranı: acil numaralar, otel adresi
// (taksiciye göster) ve kopyalanabilir Japonca fraz kartları.
//
// React viewer'daki Pusula.tsx bileşeninin Flutter portu. Viewer paletine
// uyumlu (Theme + ViewerPaletteScope). Kopyalama işlemleri panoya yazar ve
// SnackBar ile geri bildirim verir — otomatik arama YOK, dış çağrı YOK.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/compass_data.dart';
import '../../domain/types.dart';
import 'viewer_theme.dart';

class CompassScreen extends ConsumerWidget {
  const CompassScreen({super.key, required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(viewerPaletteProvider);
    return Theme(
      data: palette.toThemeData(),
      child: ViewerPaletteScope(
        palette: palette,
        child: _CompassView(trip: trip, palette: palette),
      ),
    );
  }
}

class _CompassView extends StatelessWidget {
  const _CompassView({required this.trip, required this.palette});

  final Trip trip;
  final ViewerPalette palette;

  void _copy(BuildContext context, String text, String feedback) {
    Clipboard.setData(ClipboardData(text: text));
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(feedback),
        duration: const Duration(milliseconds: 1400),
        backgroundColor: palette.elevated,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hotel = trip.hotels.isNotEmpty ? trip.hotels.first : null;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          '🧭 Pusula',
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
            'Cebinde taşı — acil, dil, kültür',
            style: TextStyle(color: palette.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 16),
          _EmergencySection(
            palette: palette,
            onCopy: (number) =>
                _copy(context, number, 'Numara kopyalandı: $number'),
          ),
          if (hotel != null) ...[
            const SizedBox(height: 16),
            _HotelSection(
              hotel: hotel,
              palette: palette,
              onCopy: (addr) =>
                  _copy(context, addr, 'Adres kopyalandı'),
            ),
          ],
          const SizedBox(height: 16),
          _PhrasesSection(
            palette: palette,
            onCopy: (jp) => _copy(context, jp, 'Kopyalandı: $jp'),
          ),
          for (final card in kCompassInfoCards) ...[
            const SizedBox(height: 16),
            _InfoSection(card: card, palette: palette),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kart kabuğu — başlık ikonu + başlık/alt başlık + içerik.
// ---------------------------------------------------------------------------

class _CompassCard extends StatelessWidget {
  const _CompassCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.palette,
    required this.child,
    this.borderColor,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final Color accent;
  final ViewerPalette palette;
  final Widget child;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? palette.border),
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
                child: Text(emoji, style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1) Acil numaralar — tıklanınca panoya kopyalar.
// ---------------------------------------------------------------------------

class _EmergencySection extends StatelessWidget {
  const _EmergencySection({required this.palette, required this.onCopy});

  final ViewerPalette palette;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    return _CompassCard(
      emoji: '🚨',
      title: 'Acil Numaralar',
      subtitle: 'Japonya · dokun, kopyalansın',
      accent: palette.sunset,
      palette: palette,
      borderColor: palette.sunset.withValues(alpha: 0.35),
      child: Column(
        children: [
          for (final e in kCompassEmergencyNumbers)
            _EmergencyRow(entry: e, palette: palette, onCopy: onCopy),
        ],
      ),
    );
  }
}

class _EmergencyRow extends StatelessWidget {
  const _EmergencyRow({
    required this.entry,
    required this.palette,
    required this.onCopy,
  });

  final CompassEmergencyNumber entry;
  final ViewerPalette palette;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: palette.sunset.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onCopy(entry.number),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Text(
                  entry.number,
                  style: TextStyle(
                    color: palette.sunset,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.label,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.copy_rounded, size: 18, color: palette.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2) Otel adresi (taksiciye göster).
// ---------------------------------------------------------------------------

class _HotelSection extends StatelessWidget {
  const _HotelSection({
    required this.hotel,
    required this.palette,
    required this.onCopy,
  });

  final HotelStay hotel;
  final ViewerPalette palette;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    final local = hotel.addressLocal;
    return _CompassCard(
      emoji: '🏨',
      title: 'Otel adresi',
      subtitle: 'Taksiciye göster',
      accent: palette.sky,
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hotel.name,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          if (hotel.address.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              hotel.address,
              style: TextStyle(color: palette.textSecondary, fontSize: 14),
            ),
          ],
          if (local != null && local.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.elevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.border),
              ),
              child: Text(
                local,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
          ],
          if (hotel.phone != null && hotel.phone!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '📞 ${hotel.phone}',
              style: TextStyle(color: palette.textSecondary, fontSize: 14),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => onCopy(
                (local != null && local.isNotEmpty) ? local : hotel.address,
              ),
              icon: const Text('📋', style: TextStyle(fontSize: 14)),
              label: const Text('Kopyala'),
              style: FilledButton.styleFrom(
                backgroundColor: palette.sky,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3) Faydalı ifadeler — kategoriye göre gruplu; dokununca Japoncayı kopyalar.
// ---------------------------------------------------------------------------

class _PhrasesSection extends StatefulWidget {
  const _PhrasesSection({required this.palette, required this.onCopy});

  final ViewerPalette palette;
  final ValueChanged<String> onCopy;

  @override
  State<_PhrasesSection> createState() => _PhrasesSectionState();
}

class _PhrasesSectionState extends State<_PhrasesSection> {
  int _activeCat = 0;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final category = kCompassPhraseCategories[_activeCat];

    return _CompassCard(
      emoji: '🗣️',
      title: 'Japonca fraz kartları',
      subtitle: 'Cümleye dokun, kopyalansın',
      accent: palette.gold,
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < kCompassPhraseCategories.length; i++)
                _CategoryTab(
                  category: kCompassPhraseCategories[i],
                  selected: i == _activeCat,
                  palette: palette,
                  onTap: () => setState(() => _activeCat = i),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final p in category.phrases)
            _PhraseRow(phrase: p, palette: palette, onCopy: widget.onCopy),
        ],
      ),
    );
  }
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.category,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final CompassPhraseCategory category;
  final bool selected;
  final ViewerPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? palette.accent.withValues(alpha: 0.18)
          : palette.elevated,
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
            '${category.emoji} ${category.title}',
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

class _PhraseRow extends StatelessWidget {
  const _PhraseRow({
    required this.phrase,
    required this.palette,
    required this.onCopy,
  });

  final CompassPhrase phrase;
  final ViewerPalette palette;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: palette.elevated,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onCopy(phrase.jp),
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
                        phrase.meaning,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        phrase.jp,
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
                        Text(
                          phrase.romaji!,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.copy_rounded, size: 18, color: palette.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4) Pratik bilgiler (Para & Döviz, Kültür kuralları).
// ---------------------------------------------------------------------------

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.card, required this.palette});

  final CompassInfoCard card;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return _CompassCard(
      emoji: card.emoji,
      title: card.title,
      subtitle: card.subtitle,
      accent: palette.matcha,
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in card.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                  children: [
                    if (line.label != null && line.label!.isNotEmpty)
                      TextSpan(
                        text: '${line.label} ',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    TextSpan(text: line.text),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
