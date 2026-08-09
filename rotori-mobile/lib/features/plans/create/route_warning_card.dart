// "Rotan uzun görünüyor" — coğrafi olarak mantıksız şehir sırasını yakalar.
//
// Şehir seçim ekranında SEÇİM SIRASI = ROTA SIRASI. Kullanıcı şehirleri akla
// geldiği sırayla seçiyor; araya uzak bir şehir girdiğinde (ör. Kansai turunun
// ortasına Sapporo) bunu plan üretilene kadar fark etmiyor. Bu kart farkı
// üretimden ÖNCE gösterir ve tek dokunuşla düzeltir.

import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/city_places.dart';
import '../../../domain/route_sanity.dart';
import '../../viewer/viewer_theme.dart';

class RouteWarningCard extends StatelessWidget {
  const RouteWarningCard({
    super.key,
    required this.palette,
    required this.sanity,
    required this.currentOrder,
    required this.onApply,
  });

  final ViewerPalette palette;
  final RouteSanity sanity;

  /// Kullanıcının şu anki seçim sırası — kart bunu "önce" satırında gösterir.
  final List<String> currentOrder;

  /// Önerilen sırayı uygula.
  final void Function(List<String> order) onApply;

  static String _label(String cityKey) {
    final match = kCityData.where((c) => c.key == cityKey);
    if (match.isEmpty) return cityKey;
    return '${match.first.emoji} ${match.first.label}';
  }

  static String _chain(List<String> keys) =>
      keys.map(_label).join('  →  ');

  @override
  Widget build(BuildContext context) {
    if (!sanity.hasSuggestion) return const SizedBox.shrink();
    final s = LanguageScope.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.gold.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, size: 18, color: palette.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.s('create.route.longTitle'),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _RouteLine(
            palette: palette,
            caption: s.s('create.route.current'),
            chain: _chain(currentOrder),
            muted: true,
          ),
          const SizedBox(height: 8),
          _RouteLine(
            palette: palette,
            caption: s.p('create.route.suggested',
                {'km': '${sanity.savedKm.round()}'}),
            chain: _chain(sanity.suggestedOrder),
            muted: false,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: palette.accent),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => onApply(sanity.suggestedOrder),
              child: Text(
                s.s('create.route.fix'),
                style: TextStyle(
                  color: palette.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteLine extends StatelessWidget {
  const _RouteLine({
    required this.palette,
    required this.caption,
    required this.chain,
    required this.muted,
  });

  final ViewerPalette palette;
  final String caption;
  final String chain;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          caption,
          style: TextStyle(
            color: muted ? palette.textMuted : palette.accent,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          chain,
          style: TextStyle(
            color: muted ? palette.textSecondary : palette.textPrimary,
            fontSize: 13,
            height: 1.35,
            decoration: muted ? TextDecoration.lineThrough : null,
            decorationColor: palette.textMuted,
            fontWeight: muted ? FontWeight.w500 : FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
