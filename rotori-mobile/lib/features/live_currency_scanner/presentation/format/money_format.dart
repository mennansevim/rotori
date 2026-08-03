import '../../domain/currency_code.dart';

/// Basit para biçimlendirme — binlik `.`, ondalık `,` (TR biçimi). intl
/// bağımlılığı eklemeden, sembol + gruplu tam kısım + ondalık üretir.
class MoneyFormat {
  const MoneyFormat._();

  /// [value] tutarını [currency] sembolü ve ondalık hanesiyle biçimler.
  /// Örn. (3260.0, TRY) → `₺3.260`, (12.5, USD) → `$12,50`.
  static String format(double value, CurrencyCode currency) {
    final digits = currency.decimalDigits;
    final rounded = value.toStringAsFixed(digits);
    final parts = rounded.split('.');
    final intPart = parts[0];
    final grouped = _group(intPart);
    if (digits == 0) return '${currency.symbol}$grouped';
    return '${currency.symbol}$grouped,${parts[1]}';
  }

  /// Kaynak JPY tutarı — her zaman ¥ ve gruplu tam sayı.
  static String jpy(int amount) => '¥${_group(amount.toString())}';

  static String _group(String intDigits) {
    final neg = intDigits.startsWith('-');
    final digits = neg ? intDigits.substring(1) : intDigits;
    final buffer = StringBuffer();
    final n = digits.length;
    for (var i = 0; i < n; i++) {
      if (i > 0 && (n - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return neg ? '-$buffer' : buffer.toString();
  }
}
