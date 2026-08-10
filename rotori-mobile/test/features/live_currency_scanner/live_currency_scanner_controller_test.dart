import 'dart:async';
import 'dart:ui' show Rect;

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotori/features/live_currency_scanner/application/live_currency_scanner_controller.dart';
import 'package:rotori/features/live_currency_scanner/application/live_currency_scanner_state.dart';
import 'package:rotori/features/live_currency_scanner/application/providers.dart';
import 'package:rotori/features/live_currency_scanner/domain/exchange_rate.dart';
import 'package:rotori/features/live_currency_scanner/domain/product_price_query.dart';
import 'package:rotori/features/live_currency_scanner/domain/repositories/product_price_query_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ürün sorgusunda kaynaklar adım adım güncellenir ve en az bir sonuçla tamamlanır',
      () async {
    final hb = Completer<ProductMarketQuote>();
    final ty = Completer<ProductMarketQuote>();
    final az = Completer<ProductMarketQuote>();

    final repo = _ControlledMarketRepo({
      ProductPriceSource.hepsiburada: hb.future,
      ProductPriceSource.trendyol: ty.future,
      ProductPriceSource.amazon: az.future,
    });

    final container = ProviderContainer(
      overrides: [
        productPriceQueryRepositoryProvider.overrideWithValue(repo),
        liveCurrencyScannerControllerProvider.overrideWith(
          (ref) => _SeededScannerController(ref, _seededState()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sub =
        container.listen(liveCurrencyScannerControllerProvider, (_, __) {});
    addTearDown(sub.close);

    final controller =
        container.read(liveCurrencyScannerControllerProvider.notifier);

    final running = controller.startProductPriceQuery();

    var state = container.read(liveCurrencyScannerControllerProvider);
    expect(state.productQueryStatus, ProductPriceQueryStatus.loading);
    expect(state.activeProductQueryCandidate, isNotNull);
    expect(state.productQueryProgress.length, 3);
    expect(
      state.productQueryProgress
          .every((row) => row.status == ProductPriceSourceStatus.loading),
      isTrue,
    );

    hb.complete(_quote(source: ProductPriceSource.hepsiburada, priceTry: 64000));
    await _flush();

    state = container.read(liveCurrencyScannerControllerProvider);
    expect(
      _statusOf(state, ProductPriceSource.hepsiburada),
      ProductPriceSourceStatus.success,
    );
    expect(
      _statusOf(state, ProductPriceSource.trendyol),
      ProductPriceSourceStatus.loading,
    );

    ty.completeError(StateError('temporary failure'), StackTrace.current);
    await _flush();

    state = container.read(liveCurrencyScannerControllerProvider);
    expect(
      _statusOf(state, ProductPriceSource.trendyol),
      ProductPriceSourceStatus.failed,
    );

    az.complete(_quote(source: ProductPriceSource.amazon, priceTry: 70250));
    await running;

    state = container.read(liveCurrencyScannerControllerProvider);
    expect(state.productQueryStatus, ProductPriceQueryStatus.completed);
    expect(state.productPriceComparison, isNotNull);
    expect(state.productPriceComparison!.quotes.length, 2);
    expect(state.productPriceComparison!.quotes.first.source,
        ProductPriceSource.hepsiburada);
    expect(state.productQueryErrorMessageKey, isNull);
  });

  test('tüm kaynaklar başarısızsa query failed + noResults hatası döner',
      () async {
    final hb = Completer<ProductMarketQuote>();
    final ty = Completer<ProductMarketQuote>();
    final az = Completer<ProductMarketQuote>();

    final repo = _ControlledMarketRepo({
      ProductPriceSource.hepsiburada: hb.future,
      ProductPriceSource.trendyol: ty.future,
      ProductPriceSource.amazon: az.future,
    });

    final container = ProviderContainer(
      overrides: [
        productPriceQueryRepositoryProvider.overrideWithValue(repo),
        liveCurrencyScannerControllerProvider.overrideWith(
          (ref) => _SeededScannerController(ref, _seededState()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sub =
        container.listen(liveCurrencyScannerControllerProvider, (_, __) {});
    addTearDown(sub.close);

    final controller =
        container.read(liveCurrencyScannerControllerProvider.notifier);

    final running = controller.startProductPriceQuery();

    hb.completeError(Exception('hb fail'), StackTrace.current);
    ty.completeError(Exception('ty fail'), StackTrace.current);
    az.completeError(Exception('az fail'), StackTrace.current);

    await running;

    final state = container.read(liveCurrencyScannerControllerProvider);
    expect(state.productQueryStatus, ProductPriceQueryStatus.failed);
    expect(state.productPriceComparison, isNull);
    expect(
      state.productQueryErrorMessageKey,
      'scanner.market.error.noResults',
    );
    expect(
      state.productQueryProgress
          .every((row) => row.status == ProductPriceSourceStatus.failed),
      isTrue,
    );
  });
}

ProductPriceSourceStatus _statusOf(
  LiveCurrencyScannerState state,
  ProductPriceSource source,
) {
  return state.productQueryProgress
      .firstWhere((row) => row.source == source)
      .status;
}

LiveCurrencyScannerState _seededState() {
  const candidate = ProductQueryCandidate(
    id: 'c-1',
    title: 'Apple iPhone 15 Pro 256GB',
    amountInJpy: 230000,
    boundingBox: Rect.fromLTWH(100, 160, 320, 110),
    confidence: 0.88,
    searchHints: ['iphone', 'pro', '256gb'],
  );

  return LiveCurrencyScannerState(
    status: ScannerStatus.scanning,
    productQueryCandidate: candidate,
    exchangeRate: ExchangeRate(
      baseCurrency: 'JPY',
      targetCurrency: 'TRY',
      rate: Decimal.parse('0.275'),
      fetchedAt: DateTime.utc(2026, 8, 7),
      source: 'test',
    ),
    rateFreshness: RateFreshness.fresh,
  );
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _ControlledMarketRepo implements ProductPriceQueryRepository {
  _ControlledMarketRepo(this._responses);

  final Map<ProductPriceSource, Future<ProductMarketQuote>> _responses;

  @override
  Future<ProductMarketQuote> fetchQuote({
    required ProductPriceSource source,
    required ProductQueryCandidate candidate,
    required double japanPriceTry,
  }) {
    final future = _responses[source];
    if (future == null) {
      throw StateError('No response registered for ${source.id}');
    }
    return future;
  }
}

class _SeededScannerController extends LiveCurrencyScannerController {
  _SeededScannerController(super.ref, LiveCurrencyScannerState seeded) {
    state = seeded;
  }

  @override
  Future<void> init() async {}
}

ProductMarketQuote _quote({
  required ProductPriceSource source,
  required double priceTry,
}) {
  return ProductMarketQuote(
    source: source,
    matchedTitle: 'mock ${source.id}',
    priceTry: priceTry,
    confidence: 0.81,
    fetchedAt: DateTime.utc(2026, 8, 7),
    isEstimated: true,
  );
}
