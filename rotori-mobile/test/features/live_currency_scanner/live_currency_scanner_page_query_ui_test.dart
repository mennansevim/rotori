import 'package:camera/camera.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotori/core/l10n.dart';
import 'package:rotori/features/live_currency_scanner/application/live_currency_scanner_controller.dart';
import 'package:rotori/features/live_currency_scanner/application/live_currency_scanner_state.dart';
import 'package:rotori/features/live_currency_scanner/presentation/pages/live_currency_scanner_page.dart';
import 'package:rotori/features/live_currency_scanner/domain/exchange_rate.dart';
import 'package:rotori/features/live_currency_scanner/domain/product_price_query.dart';
import 'package:rotori/features/viewer/viewer_theme.dart';

void main() {
  testWidgets('sorgulanabilir ürün varsa CTA görünür', (tester) async {
    await _pumpScannerPage(
      tester,
      initialState: _baseStateWithCandidate(),
    );

    expect(find.text('Fiyatı Sorgula'), findsOneWidget);
    expect(find.text('Apple iPhone 15 Pro 256GB'), findsOneWidget);
  });

  testWidgets('CTA tıklanınca sorgu sheeti loading adımlarıyla açılır',
      (tester) async {
    await _pumpScannerPage(
      tester,
      initialState: _baseStateWithCandidate(),
    );

    await tester.tap(find.text('Fiyatı Sorgula'));
    await tester.pump();

    expect(find.text('Pazar fiyatları sorgulanıyor'), findsOneWidget);
    expect(find.text('Hepsiburada'), findsOneWidget);
    expect(find.text('Trendyol'), findsOneWidget);
    expect(find.text('Amazon Türkiye'), findsOneWidget);
    expect(find.text('Sorgulanıyor'), findsNWidgets(3));
  });
}

Future<void> _pumpScannerPage(
  WidgetTester tester, {
  required LiveCurrencyScannerState initialState,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        viewerPaletteProvider.overrideWithValue(ViewerPalette.appleLight),
        liveCurrencyScannerControllerProvider.overrideWith(
          (ref) => _UiFakeScannerController(ref, initialState),
        ),
      ],
      child: const LanguageScope(
        lang: AppLang.tr,
        child: MaterialApp(home: LiveCurrencyScannerPage()),
      ),
    ),
  );
  await tester.pump();
}

LiveCurrencyScannerState _baseStateWithCandidate() {
  const candidate = ProductQueryCandidate(
    id: 'cand-1',
    title: 'Apple iPhone 15 Pro 256GB',
    amountInJpy: 219800,
    boundingBox: Rect.fromLTWH(100, 160, 280, 100),
    confidence: 0.91,
    searchHints: ['iphone', 'pro'],
  );

  return LiveCurrencyScannerState(
    status: ScannerStatus.scanning,
    productQueryCandidate: candidate,
    exchangeRate: ExchangeRate(
      baseCurrency: 'JPY',
      targetCurrency: 'TRY',
      rate: Decimal.parse('0.27'),
      fetchedAt: DateTime.utc(2026, 8, 7),
      source: 'test',
    ),
    rateFreshness: RateFreshness.fresh,
  );
}

class _UiFakeScannerController extends LiveCurrencyScannerController {
  _UiFakeScannerController(super.ref, LiveCurrencyScannerState initial) {
    state = initial;
  }

  @override
  Future<void> init() async {}

  @override
  CameraController? get cameraController => null;

  @override
  Future<void> startProductPriceQuery() async {
    final candidate = state.productQueryCandidate;
    if (candidate == null) return;

    state = state.copyWith(
      productQueryStatus: ProductPriceQueryStatus.loading,
      activeProductQueryCandidate: candidate,
      productQueryProgress: const [
        ProductPriceSourceProgress(
          source: ProductPriceSource.hepsiburada,
          status: ProductPriceSourceStatus.loading,
        ),
        ProductPriceSourceProgress(
          source: ProductPriceSource.trendyol,
          status: ProductPriceSourceStatus.loading,
        ),
        ProductPriceSourceProgress(
          source: ProductPriceSource.amazon,
          status: ProductPriceSourceStatus.loading,
        ),
      ],
      clearProductPriceComparison: true,
      clearProductQueryError: true,
    );
  }

  @override
  void closeProductPriceQuerySheet() {
    state = state.copyWith(
      productQueryStatus: ProductPriceQueryStatus.idle,
      clearActiveProductQueryCandidate: true,
      productQueryProgress: const [],
      clearProductPriceComparison: true,
      clearProductQueryError: true,
    );
  }
}
