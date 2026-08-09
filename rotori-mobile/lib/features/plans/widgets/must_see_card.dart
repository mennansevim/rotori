// "Bunları da gör" — plan hazır olduktan sonra öneri ekleme kartı.
//
// Eski wizard'da bu seçim Rota adımındaydı ve plan ÜRETİMİNE girdi oluyordu.
// Yeni akışta plan 2 soruyla hazır geliyor, bu yüzden öneri plan ÜZERİNDE
// sunuluyor: kullanıcı seçer, seçilenler mevcut günlerdeki boşluğa eklenir
// (yeniden üretim YOK — elle yapılan düzenlemeler korunur).

import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/japan_suggestions.dart';
import '../../../domain/must_see_suggestions.dart';
import '../../../domain/types.dart';
import '../../viewer/viewer_theme.dart';

class MustSeeCard extends StatefulWidget {
  const MustSeeCard({
    super.key,
    required this.palette,
    required this.trip,
    required this.onAdd,
    required this.onDismiss,
  });

  final ViewerPalette palette;
  final Trip trip;

  /// Seçilen yerleri plana ekler; sonucu (kaç eklendi / sığmayanlar) döner.
  final Future<HighlightPlacement> Function(List<PlaceSuggestion>) onAdd;
  final VoidCallback onDismiss;

  @override
  State<MustSeeCard> createState() => _MustSeeCardState();
}

class _MustSeeCardState extends State<MustSeeCard> {
  final _selected = <String>{};
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final palette = widget.palette;
    final places = missingHighlights(widget.trip, limit: 10);

    // Önerilecek bir şey kalmadıysa kart hiç görünmez.
    if (places.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.auto_awesome_rounded,
                    color: palette.accent, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.s('viewer.mustSee.title'),
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.s('viewer.mustSee.body'),
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded,
                    size: 18, color: palette.textMuted),
                tooltip: s.s('viewer.mustSee.dismiss'),
                onPressed: _busy ? null : widget.onDismiss,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in places)
                _PlaceChip(
                  palette: palette,
                  emoji: p.emoji,
                  label: p.name,
                  city: p.city,
                  selected: _selected.contains(p.id),
                  onTap: _busy
                      ? null
                      : () => setState(() {
                            if (!_selected.remove(p.id)) _selected.add(p.id);
                          }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                disabledBackgroundColor: palette.accent.withValues(alpha: 0.35),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _selected.isEmpty || _busy
                  ? null
                  : () => _add(places),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _selected.isEmpty
                          ? s.s('viewer.mustSee.cta')
                          : s.p('viewer.mustSee.ctaCount',
                              {'n': '${_selected.length}'}),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _add(List<PlaceSuggestion> places) async {
    final picked = places.where((p) => _selected.contains(p.id)).toList();
    if (picked.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.onAdd(picked);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Seçilebilir yer çipi — 44pt dokunma hedefi.
class _PlaceChip extends StatelessWidget {
  const _PlaceChip({
    required this.palette,
    required this.emoji,
    required this.label,
    required this.city,
    required this.selected,
    required this.onTap,
  });

  final ViewerPalette palette;
  final String emoji;
  final String label;
  final String city;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $city',
      child: Material(
        color: selected
            ? palette.accent.withValues(alpha: 0.14)
            : palette.elevated,
        borderRadius: BorderRadius.circular(100),
        child: InkWell(
          borderRadius: BorderRadius.circular(100),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: selected ? palette.accent : palette.border,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? palette.accent : palette.textPrimary,
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.check_rounded, size: 15, color: palette.accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
