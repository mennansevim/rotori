import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/features/live_currency_scanner/domain/currency_code.dart';
import 'package:rotori/features/live_currency_scanner/domain/currency_converter.dart';
import 'package:rotori/features/live_currency_scanner/domain/exchange_rate.dart';
import 'package:rotori/features/live_currency_scanner/domain/scanner_settings.dart';

ExchangeRate _rate(String r, {String target = 'TRY'}) => ExchangeRate(
      baseCurrency: 'JPY',
      targetCurrency: target,
      rate: Decimal.parse(r),
      fetchedAt: DateTime.utc(2026, 8, 1),
      source: 'test',
    );

void main() {
  const converter = CurrencyConverter();

  test('JPY → TRY temel dönüşüm', () {
    final c = converter.convert(
      amountInJpy: 12800,
      rate: _rate('0.25'),
      settings: const ScannerSettings(),
    );
    expect(c.convertedAsDouble, 3200.0);
  });

  test('JPY → USD ondalık 2 hane', () {
    final c = converter.convert(
      amountInJpy: 1000,
      rate: _rate('0.0067', target: 'USD'),
      settings: const ScannerSettings(targetCurrency: CurrencyCode.usd),
    );
    expect(c.convertedAsDouble, closeTo(6.7, 0.0001));
  });

  test('kart/banka farkı %2 uygulanır', () {
    final c = converter.convert(
      amountInJpy: 10000,
      rate: _rate('0.25'),
      settings: const ScannerSettings(cardMarkupPercent: 2),
    );
    // 10000 * 0.25 = 2500 → *1.02 = 2550
    expect(c.convertedAsDouble, 2550.0);
  });

  test('en yakın tam birime yuvarlama', () {
    final c = converter.convert(
      amountInJpy: 12801,
      rate: _rate('0.2534'),
      settings:
          const ScannerSettings(rounding: RoundingPreference.nearestWhole),
    );
    // 12801 * 0.2534 = 3243.7734 → 3244
    expect(c.convertedAsDouble, 3244.0);
  });

  test('en yakın 10 birime yuvarlama', () {
    final c = converter.convert(
      amountInJpy: 12801,
      rate: _rate('0.2534'),
      settings: const ScannerSettings(rounding: RoundingPreference.nearestTen),
    );
    // 3243.77 → 3240
    expect(c.convertedAsDouble, 3240.0);
  });

  test('çok büyük fiyatta hassasiyet korunur (double kayması yok)', () {
    final c = converter.convert(
      amountInJpy: 99999999,
      rate: _rate('0.24'),
      settings: const ScannerSettings(),
    );
    expect(c.convertedAsDouble, 23999999.76);
  });

  test('KRW ondalıksız biçimlenir', () {
    final c = converter.convert(
      amountInJpy: 1000,
      rate: _rate('9.1', target: 'KRW'),
      settings: const ScannerSettings(targetCurrency: CurrencyCode.krw),
    );
    expect(c.convertedAsDouble, 9100.0);
  });
}
