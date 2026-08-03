import 'package:flutter/material.dart';

import '../../../viewer/viewer_theme.dart';
import '../../domain/currency_code.dart';
import '../../domain/japanese_price_tax_type.dart';
import '../format/money_format.dart';

/// Algılanan fiyatın üstünde/altında görünen minimal çeviri etiketi.
///
/// Orijinal (¥) fiyat küçük, çevrilen fiyat belirgin. Düşük güvende daha
/// temkinli (soluk) görünür.
class CurrencyDetectionLabel extends StatelessWidget {
  const CurrencyDetectionLabel({
    super.key,
    required this.amountInJpy,
    required this.converted,
    required this.targetCurrency,
    required this.confidence,
    required this.taxType,
    required this.palette,
    required this.lowConfidenceThreshold,
    this.onTap,
  });

  final int amountInJpy;
  final double converted;
  final CurrencyCode targetCurrency;
  final double confidence;
  final JapanesePriceTaxType taxType;
  final ViewerPalette palette;
  final double lowConfidenceThreshold;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final isLow = confidence < lowConfidenceThreshold;
    final bg = Colors.black.withValues(alpha: isLow ? 0.55 : 0.78);
    final accent = isLow ? p.textSecondary : p.accent;

    return Semantics(
      label:
          '${MoneyFormat.jpy(amountInJpy)} ${MoneyFormat.format(converted, targetCurrency)}',
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: accent.withValues(alpha: isLow ? 0.4 : 0.9),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  MoneyFormat.jpy(amountInJpy),
                  style: const TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  MoneyFormat.format(converted, targetCurrency),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                    shadows: [
                      Shadow(
                          color: accent.withValues(alpha: .8), blurRadius: 6),
                    ],
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
