import 'package:decimal/decimal.dart';

import 'currency_code.dart';
import 'exchange_rate.dart';

/// Uygulamayla birlikte gelen yaklaşık yedek kurlar (`1 JPY = X hedef`).
///
/// **Why:** Supabase `exchange_rates` tablosu boşsa, oturum yoksa veya cihaz
/// çevrimdışıysa çevirici "Kur bulunamadı" ile tamamen kullanılamaz hale
/// geliyordu. Bu tablo son çare olarak kullanılır; değerler yaklaşıktır ve
/// kasıtlı olarak eski tarihli döndürülür (UI "kur eski" uyarısı gösterir).
class FallbackExchangeRates {
  const FallbackExchangeRates._();

  /// Yedek kur seti — derleme anına yakın yaklaşık değerler.
  static const _reference = <String, String>{
    'TRY': '0.30',
    'USD': '0.0067',
    'EUR': '0.0062',
    'GBP': '0.0053',
    'KRW': '9.3',
    'CNY': '0.048',
  };

  /// Yedek kurun temsili "elde edildi" tarihi. Bilinçli olarak eskidir ki
  /// UI bunun canlı bir kur olmadığını göstersin ve remote her zaman denensin.
  static final DateTime referenceDate = DateTime.utc(2026, 1, 1);

  /// [base] → [target] için yedek kur; tanımlı değilse null.
  static ExchangeRate? lookup(String base, String target) {
    if (base.toUpperCase() != CurrencyCode.baseIso) return null;
    final raw = _reference[target.toUpperCase()];
    if (raw == null) return null;
    return ExchangeRate(
      baseCurrency: CurrencyCode.baseIso,
      targetCurrency: target.toUpperCase(),
      rate: Decimal.parse(raw),
      fetchedAt: referenceDate,
      source: 'fallback',
    );
  }
}
