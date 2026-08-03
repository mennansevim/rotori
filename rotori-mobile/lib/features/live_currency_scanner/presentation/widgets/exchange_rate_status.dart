import 'package:flutter/material.dart';

import '../../../../core/l10n.dart';
import '../../../viewer/viewer_theme.dart';
import '../../application/live_currency_scanner_state.dart';
import '../../domain/exchange_rate.dart';

/// Kur durumu şeridi — güncel/eski uyarısı, kaynak, son güncelleme, manuel rozet.
class ExchangeRateStatus extends StatelessWidget {
  const ExchangeRateStatus({
    super.key,
    required this.rate,
    required this.freshness,
    required this.palette,
  });

  final ExchangeRate? rate;
  final RateFreshness freshness;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final p = palette;
    final r = rate;

    final (label, color, icon) = switch (freshness) {
      RateFreshness.fresh => (
          s.s('scanner.rateFresh'),
          p.matcha,
          Icons.check_circle_outline,
        ),
      RateFreshness.aging || RateFreshness.stale => (
          s.s('scanner.rateStale'),
          p.gold,
          Icons.schedule,
        ),
      RateFreshness.missing => (
          s.s('scanner.rateMissing'),
          p.sunset,
          Icons.error_outline,
        ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (r != null && r.isManual) ...[
                      const SizedBox(width: 6),
                      _ManualBadge(
                          color: p.accent, text: s.s('scanner.manualRate')),
                    ],
                  ],
                ),
                if (r != null)
                  Text(
                    '1¥ = ${r.rate.toDouble().toStringAsFixed(4)} ${r.targetCurrency} · '
                    '${s.s('scanner.lastUpdated')}: ${_time(r.fetchedAt.toLocal())}',
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _time(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _ManualBadge extends StatelessWidget {
  const _ManualBadge({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
