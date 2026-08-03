import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_client.dart';
import '../../../data/plans_repository.dart' show sharedPrefsProvider;
import '../domain/currency_converter.dart';
import '../domain/repositories/exchange_rate_repository.dart';
import '../domain/repositories/scanner_settings_repository.dart';
import '../infrastructure/exchange_rates/exchange_rate_local_data_source.dart';
import '../infrastructure/exchange_rates/exchange_rate_remote_data_source.dart';
import '../infrastructure/exchange_rates/exchange_rate_repository_impl.dart';
import '../infrastructure/ocr/ocr_price_extractor.dart';
import '../infrastructure/settings/scanner_settings_repository_impl.dart';
import 'live_currency_scanner_state.dart';
import 'scanner_settings_controller.dart';

/// Kur repository — SharedPreferences cache + (oturum varsa) Supabase remote.
/// Prefs hazır değilse null döner; controller güvenli biçimde bekler.
final exchangeRateRepositoryProvider = Provider<ExchangeRateRepository?>((ref) {
  final prefs = ref.watch(sharedPrefsProvider).valueOrNull;
  if (prefs == null) return null;
  final local = ExchangeRateLocalDataSource(prefs);
  final session = ref.watch(currentSessionProvider);
  final remote = session == null
      ? null
      : ExchangeRateRemoteDataSource(ref.watch(supabaseProvider));
  return ExchangeRateRepositoryImpl(local: local, remote: remote);
});

/// Ayar repository — SharedPreferences.
final scannerSettingsRepositoryProvider =
    Provider<ScannerSettingsRepository?>((ref) {
  final prefs = ref.watch(sharedPrefsProvider).valueOrNull;
  if (prefs == null) return null;
  return ScannerSettingsRepositoryImpl(prefs);
});

/// Ayar controller'ı.
final scannerSettingsControllerProvider =
    StateNotifierProvider<ScannerSettingsController, ScannerSettingsUiState>(
        (ref) {
  return ScannerSettingsController(ref);
});

/// JPY → hedef dönüşümü (saf domain servisi).
final currencyConverterProvider =
    Provider<CurrencyConverter>((ref) => const CurrencyConverter());

/// OCR sonucundan fiyat çıkaran saf servis.
final ocrPriceExtractorProvider =
    Provider<OcrPriceExtractor>((ref) => const OcrPriceExtractor());

/// [DateTime.now] anına göre kur tazeliği.
RateFreshness freshnessFor(DateTime fetchedAt, DateTime now) {
  final age = now.toUtc().difference(fetchedAt.toUtc());
  if (age.isNegative) return RateFreshness.fresh;
  if (age >= const Duration(hours: 48)) return RateFreshness.stale;
  if (age >= const Duration(hours: 24)) return RateFreshness.aging;
  return RateFreshness.fresh;
}
