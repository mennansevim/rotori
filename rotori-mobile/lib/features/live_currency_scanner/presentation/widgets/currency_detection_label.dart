import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/l10n.dart';
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
    required this.exchangeRate,
    required this.targetCurrency,
    required this.confidence,
    required this.taxType,
    required this.palette,
    required this.lowConfidenceThreshold,
    this.onTap,
  });

  final int amountInJpy;
  final double converted;
  final double exchangeRate;
  final CurrencyCode targetCurrency;
  final double confidence;
  final JapanesePriceTaxType taxType;
  final ViewerPalette palette;
  final double lowConfidenceThreshold;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final p = palette;
    final isLow = confidence < lowConfidenceThreshold;
    final accent = isLow ? p.textSecondary : p.accent;
    final rateUnit = _rateUnit(targetCurrency);
    final rateLabel = s.s('scanner.rateShort');

    return Semantics(
      label:
          '${MoneyFormat.jpy(amountInJpy)} ${MoneyFormat.format(converted, targetCurrency)}',
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: isLow ? 0.22 : 0.32),
                    Colors.white.withValues(alpha: isLow ? 0.10 : 0.16),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: isLow ? 0.35 : 0.55),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.24),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: accent.withValues(alpha: isLow ? 0.18 : 0.30),
                    blurRadius: 16,
                    spreadRadius: 0.8,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -12,
                    left: -26,
                    child: IgnorePointer(
                      child: Container(
                        width: 118,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.38),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          MoneyFormat.format(converted, targetCurrency),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: const Color(0xFFF8FAFF),
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            height: 1.0,
                            shadows: [
                              Shadow(
                                color: accent.withValues(alpha: 0.55),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          MoneyFormat.jpy(amountInJpy),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xCC2F3640),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$rateLabel: ${exchangeRate.toStringAsFixed(2)} $rateUnit',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0x9A20242A),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _rateUnit(CurrencyCode currency) {
    return switch (currency) {
      CurrencyCode.tryl => 'TL',
      _ => currency.iso,
    };
  }
}
