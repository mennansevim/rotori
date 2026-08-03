import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/features/live_currency_scanner/domain/exchange_rate.dart';
import 'package:japan_trip/features/live_currency_scanner/domain/repositories/exchange_rate_repository.dart';
import 'package:japan_trip/features/live_currency_scanner/infrastructure/exchange_rates/exchange_rate_local_data_source.dart';
import 'package:japan_trip/features/live_currency_scanner/infrastructure/exchange_rates/exchange_rate_remote_data_source.dart';
import 'package:japan_trip/features/live_currency_scanner/infrastructure/exchange_rates/exchange_rate_repository_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRemote implements ExchangeRateRemoteDataSource {
  _FakeRemote(this.result, {this.shouldThrow = false});
  ExchangeRate? result;
  bool shouldThrow;
  int calls = 0;

  @override
  Future<ExchangeRate?> fetch(
      {required String base, required String target}) async {
    calls++;
    if (shouldThrow) throw Exception('network');
    return result;
  }
}

ExchangeRate _rate(String r, DateTime at, {String source = 'supabase'}) =>
    ExchangeRate(
      baseCurrency: 'JPY',
      targetCurrency: 'TRY',
      rate: Decimal.parse(r),
      fetchedAt: at,
      source: source,
    );

void main() {
  late SharedPreferences prefs;
  late ExchangeRateLocalDataSource local;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    local = ExchangeRateLocalDataSource(prefs);
  });

  test('remote başarılı → cache edilir ve döner', () async {
    final now = DateTime.utc(2026, 8, 1, 12);
    final remote = _FakeRemote(_rate('0.25', now));
    final repo = ExchangeRateRepositoryImpl(
      local: local,
      remote: remote,
      clock: () => now,
    );
    final r = await repo.getRate(baseCurrency: 'JPY', targetCurrency: 'TRY');
    expect(r.rate, Decimal.parse('0.25'));
    expect(local.readCached('JPY', 'TRY')?.rate, Decimal.parse('0.25'));
  });

  test('offline (remote throw) → son cache döner', () async {
    final now = DateTime.utc(2026, 8, 1, 12);
    await local.cache(_rate('0.24', now.subtract(const Duration(hours: 1))));
    final remote = _FakeRemote(null, shouldThrow: true);
    final repo = ExchangeRateRepositoryImpl(
      local: local,
      remote: remote,
      clock: () => now,
    );
    final r = await repo.getRate(
        baseCurrency: 'JPY', targetCurrency: 'TRY', forceRefresh: true);
    expect(r.rate, Decimal.parse('0.24'));
  });

  test('manuel kur remote/cache önünde gelir', () async {
    final now = DateTime.utc(2026, 8, 1, 12);
    await local.saveManual(_rate('0.30', now, source: 'manual'));
    await local.cache(_rate('0.25', now));
    final remote = _FakeRemote(_rate('0.25', now));
    final repo = ExchangeRateRepositoryImpl(
      local: local,
      remote: remote,
      clock: () => now,
    );
    final r = await repo.getRate(baseCurrency: 'JPY', targetCurrency: 'TRY');
    expect(r.rate, Decimal.parse('0.30'));
    expect(r.isManual, isTrue);
    expect(remote.calls, 0, reason: 'manuel varken remote çağrılmaz');
  });

  test('taze cache varken remote çağrılmaz', () async {
    final now = DateTime.utc(2026, 8, 1, 12);
    await local.cache(_rate('0.25', now.subtract(const Duration(hours: 1))));
    final remote = _FakeRemote(_rate('0.99', now));
    final repo = ExchangeRateRepositoryImpl(
      local: local,
      remote: remote,
      clock: () => now,
    );
    final r = await repo.getRate(baseCurrency: 'JPY', targetCurrency: 'TRY');
    expect(r.rate, Decimal.parse('0.25'));
    expect(remote.calls, 0);
  });

  test('hiç kur yoksa ExchangeRateUnavailable fırlatır', () async {
    final now = DateTime.utc(2026, 8, 1, 12);
    final remote = _FakeRemote(null);
    final repo = ExchangeRateRepositoryImpl(
      local: local,
      remote: remote,
      clock: () => now,
    );
    expect(
      () => repo.getRate(baseCurrency: 'JPY', targetCurrency: 'TRY'),
      throwsA(isA<ExchangeRateUnavailable>()),
    );
  });

  test('manuel kur silinince tekrar cache/remote yoluna döner', () async {
    final now = DateTime.utc(2026, 8, 1, 12);
    await local.saveManual(_rate('0.30', now));
    await repoClearAndExpect(local, now);
  });
}

Future<void> repoClearAndExpect(
    ExchangeRateLocalDataSource local, DateTime now) async {
  await local.clearManual('JPY', 'TRY');
  final remote = _FakeRemote(_rate('0.25', now));
  final repo = ExchangeRateRepositoryImpl(
    local: local,
    remote: remote,
    clock: () => now,
  );
  final r = await repo.getRate(baseCurrency: 'JPY', targetCurrency: 'TRY');
  expect(r.rate, Decimal.parse('0.25'));
}
