import '../exchange_rate.dart';

/// Kur erişiminin domain sözleşmesi. Kaynak (Supabase/manuel/cache) UI'ya
/// sızmaz; implementasyon infrastructure katmanındadır.
abstract interface class ExchangeRateRepository {
  /// `1 [baseCurrency] = X [targetCurrency]` kurunu döndürür.
  ///
  /// Öncelik: manuel kur (varsa) → cache → remote. [forceRefresh] true ise
  /// (ve manuel değilse) remote denenir; başarısızsa son cache döner.
  /// Hiç kur yoksa [ExchangeRateUnavailable] fırlatır.
  Future<ExchangeRate> getRate({
    required String baseCurrency,
    required String targetCurrency,
    bool forceRefresh = false,
  });

  /// Kullanıcının elle girdiği kuru kaydeder (remote bunu ezmez).
  Future<void> saveManualRate(ExchangeRate rate);

  /// Manuel kuru siler; sonraki okuma tekrar remote/cache'e döner.
  Future<void> clearManualRate({
    required String baseCurrency,
    required String targetCurrency,
  });
}

/// Hiçbir kaynaktan kur elde edilemediğinde.
class ExchangeRateUnavailable implements Exception {
  const ExchangeRateUnavailable(this.baseCurrency, this.targetCurrency);
  final String baseCurrency;
  final String targetCurrency;
  @override
  String toString() => 'ExchangeRateUnavailable($baseCurrency→$targetCurrency)';
}
