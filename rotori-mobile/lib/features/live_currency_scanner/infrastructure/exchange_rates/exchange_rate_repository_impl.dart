import '../../domain/exchange_rate.dart';
import '../../domain/repositories/exchange_rate_repository.dart';
import '../../domain/scanner_tuning.dart';
import 'exchange_rate_local_data_source.dart';
import 'exchange_rate_remote_data_source.dart';

/// Kur repository implementasyonu — manuel > cache > remote önceliğiyle.
///
/// Offline dayanıklı: remote hatasında son cache döner. [remote] null olabilir
/// (oturum yoksa) — bu durumda yalnız cache/manuel kullanılır. Saat testler
/// için enjekte edilebilir.
class ExchangeRateRepositoryImpl implements ExchangeRateRepository {
  ExchangeRateRepositoryImpl({
    required ExchangeRateLocalDataSource local,
    ExchangeRateRemoteDataSource? remote,
    DateTime Function()? clock,
  })  : _local = local,
        _remote = remote,
        _clock = clock ?? DateTime.now;

  final ExchangeRateLocalDataSource _local;
  final ExchangeRateRemoteDataSource? _remote;
  final DateTime Function() _clock;

  @override
  Future<ExchangeRate> getRate({
    required String baseCurrency,
    required String targetCurrency,
    bool forceRefresh = false,
  }) async {
    // 1) Manuel kur her şeyin önünde.
    final manual = _local.readManual(baseCurrency, targetCurrency);
    if (manual != null) return manual;

    final cached = _local.readCached(baseCurrency, targetCurrency);
    final now = _clock();

    final shouldRefresh = forceRefresh ||
        cached == null ||
        cached.ageFrom(now) >= ScannerTuning.refreshAfter;

    if (shouldRefresh && _remote != null) {
      try {
        final fresh = await _remote.fetch(
          base: baseCurrency,
          target: targetCurrency,
        );
        if (fresh != null) {
          await _local.cache(fresh);
          return fresh;
        }
      } catch (_) {
        // Ağ/parse hatası — sessizce cache'e düş (offline dayanıklılık).
      }
    }

    if (cached != null) return cached;
    throw ExchangeRateUnavailable(baseCurrency, targetCurrency);
  }

  @override
  Future<void> saveManualRate(ExchangeRate rate) => _local.saveManual(rate);

  @override
  Future<void> clearManualRate({
    required String baseCurrency,
    required String targetCurrency,
  }) =>
      _local.clearManual(baseCurrency, targetCurrency);
}
