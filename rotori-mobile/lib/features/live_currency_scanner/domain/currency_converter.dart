import 'package:decimal/decimal.dart';

import 'currency_code.dart';
import 'exchange_rate.dart';
import 'scanner_settings.dart';

/// Bir JPY tutarının hedef para birimine çevrilmiş sonucu.
class CurrencyConversion {
  const CurrencyConversion({
    required this.amountInJpy,
    required this.targetCurrency,
    required this.convertedMinorAdjusted,
    required this.rate,
    required this.cardMarkupPercent,
  });

  final int amountInJpy;
  final CurrencyCode targetCurrency;

  /// Kart farkı + yuvarlama uygulanmış nihai tutar (Decimal, tam hassasiyet).
  final Decimal convertedMinorAdjusted;

  /// Kullanılan kur (`1 JPY = rate TARGET`).
  final Decimal rate;

  final double cardMarkupPercent;

  double get convertedAsDouble => convertedMinorAdjusted.toDouble();
}

/// JPY → hedef para birimi dönüşümü. Saf Dart, Decimal tabanlı (double kayması
/// yok). Kart/banka farkı ve yuvarlama tercihi burada uygulanır.
class CurrencyConverter {
  const CurrencyConverter();

  /// [amountInJpy] tutarını [rate] ve [settings] ile çevirir.
  ///
  /// Hesap:
  ///   converted = jpy × rate
  ///   adjusted  = converted × (1 + cardMarkup/100)
  ///   result    = round(adjusted, rounding)
  CurrencyConversion convert({
    required int amountInJpy,
    required ExchangeRate rate,
    required ScannerSettings settings,
  }) {
    final jpy = Decimal.fromInt(amountInJpy);
    final converted = jpy * rate.rate;

    // Kart/banka farkı: converted × (1 + markup/100).
    final markup = settings.cardMarkupPercent;
    Decimal adjusted = converted;
    if (markup != 0) {
      final factor = (Decimal.one +
          (Decimal.parse(markup.toString()) / Decimal.fromInt(100))
              .toDecimal(scaleOnInfinitePrecision: 12));
      adjusted = (converted * factor);
    }

    final rounded = _applyRounding(adjusted, settings);

    return CurrencyConversion(
      amountInJpy: amountInJpy,
      targetCurrency: settings.targetCurrency,
      convertedMinorAdjusted: rounded,
      rate: rate.rate,
      cardMarkupPercent: markup,
    );
  }

  Decimal _applyRounding(Decimal value, ScannerSettings settings) {
    switch (settings.rounding) {
      case RoundingPreference.none:
        final digits = settings.targetCurrency.decimalDigits;
        return _roundToScale(value, digits);
      case RoundingPreference.nearestWhole:
        return _roundToScale(value, 0);
      case RoundingPreference.nearestTen:
        final tens = _roundToScale(
            (value / Decimal.fromInt(10))
                .toDecimal(scaleOnInfinitePrecision: 12),
            0);
        return tens * Decimal.fromInt(10);
    }
  }

  Decimal _roundToScale(Decimal value, int scale) {
    // Rational round(): yarıyı yukarı yuvarlar, negatif değerleri de doğru ele
    // alır. Decimal.round yalnızca tam sayıya yuvarladığından ölçek için
    // 10^scale ile ölçekleyip geri bölüyoruz.
    if (scale <= 0) {
      return value.round();
    }
    final factor = Decimal.fromInt(10).pow(scale).toDecimal();
    final scaled = (value * factor).round();
    return (scaled / factor).toDecimal(scaleOnInfinitePrecision: scale);
  }
}
