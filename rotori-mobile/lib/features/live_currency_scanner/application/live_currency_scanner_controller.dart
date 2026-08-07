import 'dart:async';

import 'package:camera/camera.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/currency_code.dart';
import '../domain/exchange_rate.dart';
import '../domain/product_price_query.dart';
import '../domain/repositories/exchange_rate_repository.dart';
import '../domain/repositories/product_price_query_repository.dart';
import '../domain/scanner_settings.dart';
import '../infrastructure/camera/camera_frame_adapter.dart';
import '../infrastructure/ocr/ocr_price_extractor.dart';
import '../infrastructure/ocr/on_device_text_recognizer.dart';
import '../infrastructure/ocr/text_recognizer_factory.dart';
import '../infrastructure/parsing/product_query_candidate_resolver.dart';
import '../infrastructure/tracking/price_detection_tracker.dart';
import 'live_currency_scanner_state.dart';
import 'providers.dart';

/// Kamera yaşam döngüsü + OCR analiz döngüsünü yöneten controller.
///
/// - Aynı anda tek OCR koşusu (single-flight); eski kareler kuyruğa alınmaz.
/// - OCR yaklaşık [ScannerPerformanceProfile.processingInterval] aralığında.
/// - Kamera preview OCR yüzünden bloklanmaz (analiz izole `Future`).
/// - Ekran kapanınca stream durur, controller + recognizer dispose edilir.
class LiveCurrencyScannerController
    extends StateNotifier<LiveCurrencyScannerState> {
  LiveCurrencyScannerController(this._ref)
      : _recognizer = createTextRecognizer(),
        super(const LiveCurrencyScannerState());

  final Ref _ref;
  final OnDeviceTextRecognizer _recognizer;
  final CameraFrameAdapter _adapter = const CameraFrameAdapter();
  final PriceDetectionTracker _tracker = PriceDetectionTracker();

  CameraController? _camera;
  bool _processing = false;
  final Stopwatch _sinceLastProcess = Stopwatch();
  bool _disposed = false;
  int _consecutiveFrameFailures = 0;
  int _productQueryRunToken = 0;

  OcrPriceExtractor get _extractor => _ref.read(ocrPriceExtractorProvider);
  ProductQueryCandidateResolver get _candidateResolver =>
      _ref.read(productQueryCandidateResolverProvider);
  ProductPriceQueryRepository get _productPriceRepo =>
      _ref.read(productPriceQueryRepositoryProvider);
  ExchangeRateRepository? get _rateRepo =>
      _ref.read(exchangeRateRepositoryProvider);
  ScannerSettings get _settings =>
      _ref.read(scannerSettingsControllerProvider).settings;

  /// Kamera + kur akışını başlatır.
  Future<void> init() async {
    if (_disposed) return;
    await _loadRate();
    await _startCamera();
  }

  Future<void> _startCamera() async {
    state = state.copyWith(
        status: ScannerStatus.initializingCamera, clearError: true);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        state = state.copyWith(status: ScannerStatus.cameraUnavailable);
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );
      _camera = controller;
      try {
        await controller.initialize();
      } on CameraException catch (e, st) {
        _logException('camera.initialize', e, st);
        state = state.copyWith(
          status: _mapCameraError(e),
          errorMessageKey: 'scanner.error.cameraInit',
        );
        return;
      }
      if (_disposed) {
        await controller.dispose();
        return;
      }
      _sinceLastProcess.start();
      try {
        await controller.startImageStream(_onFrame);
      } on CameraException catch (e, st) {
        _logException('camera.startImageStream', e, st);
        state = state.copyWith(
          status: _mapCameraError(e),
          errorMessageKey: 'scanner.error.streamStart',
        );
        return;
      }
      state = state.copyWith(
        status: ScannerStatus.scanning,
        rotationDegrees: back.sensorOrientation,
        mirrored: back.lensDirection == CameraLensDirection.front,
      );
    } on CameraException catch (e, st) {
      _logException('camera.start', e, st);
      state = state.copyWith(
        status: _mapCameraError(e),
        errorMessageKey: 'scanner.error.cameraInit',
      );
    } catch (e, st) {
      _logException('camera.start.unknown', e, st);
      state = state.copyWith(
        status: ScannerStatus.failure,
        errorMessageKey: 'scanner.error.unknown',
      );
    }
  }

  ScannerStatus _mapCameraError(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
        return ScannerStatus.permissionDenied;
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return ScannerStatus.permissionPermanentlyDenied;
      case 'cameraNotFound':
        return ScannerStatus.cameraUnavailable;
      default:
        return ScannerStatus.failure;
    }
  }

  void _onFrame(CameraImage image) {
    if (_disposed || _processing) return;
    if (_sinceLastProcess.elapsed <
        _settings.performanceProfile.processingInterval) {
      return;
    }
    _processing = true;
    _sinceLastProcess.reset();
    // Analizi izole future olarak yürüt — preview thread'ini bloklamaz.
    unawaited(_analyze(image).whenComplete(() => _processing = false));
  }

  Future<void> _analyze(CameraImage image) async {
    try {
      final frame = _adapter.fromCameraImage(
        image,
        rotationDegrees: state.rotationDegrees,
      );
      final recognized = await _recognizer.recognize(frame);
      if (_disposed) return;
      final prices = _extractor.extract(recognized);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final visible = _tracker.update(prices, nowMs);
      final candidate = _candidateResolver.resolve(
        frame: recognized,
        tracks: visible,
      );
      if (_disposed) return;
      _consecutiveFrameFailures = 0;
      state = state.copyWith(
        status: ScannerStatus.scanning,
        trackedPrices: visible,
        productQueryCandidate: candidate,
        clearProductQueryCandidate: candidate == null,
        imageSize: recognized.imageSize == frame.imageSize
            ? recognized.imageSize
            : frame.imageSize,
        lastFrameProcessedAt: DateTime.now(),
        isProcessingFrame: false,
      );
    } catch (e, st) {
      _consecutiveFrameFailures++;
      _logException('ocr.frame', e, st);
      // Tek kare hatası akışı bozmaz; ancak seri hata varsa güvenli fail'e düş.
      if (_consecutiveFrameFailures >= 8 && !_disposed) {
        state = state.copyWith(
          status: ScannerStatus.failure,
          errorMessageKey: 'scanner.error.previewStability',
        );
        unawaited(_disposeCamera());
      }
    }
  }

  Future<void> _loadRate() async {
    final repo = _rateRepo;
    final settings = _settings;
    // Manuel kur açıksa ve değeri varsa remote'a hiç gitme.
    if (settings.useManualRate && settings.manualRate != null) {
      final manual = _manualRate(settings);
      if (manual != null) {
        state = state.copyWith(
          exchangeRate: manual,
          targetCurrency: settings.targetCurrency,
          rateFreshness: RateFreshness.fresh,
        );
        return;
      }
    }
    if (repo == null) {
      state = state.copyWith(
          targetCurrency: settings.targetCurrency,
          rateFreshness: RateFreshness.missing);
      return;
    }
    try {
      final rate = await repo.getRate(
        baseCurrency: CurrencyCode.baseIso,
        targetCurrency: settings.targetCurrency.iso,
        forceRefresh: settings.autoUpdateRate,
      );
      state = state.copyWith(
        exchangeRate: rate,
        targetCurrency: settings.targetCurrency,
        rateFreshness: freshnessFor(rate.fetchedAt, DateTime.now()),
      );
    } on ExchangeRateUnavailable {
      state = state.copyWith(
        targetCurrency: settings.targetCurrency,
        rateFreshness: RateFreshness.missing,
      );
    } catch (_) {
      state = state.copyWith(rateFreshness: RateFreshness.missing);
    }
  }

  ExchangeRate? _manualRate(ScannerSettings settings) {
    final raw = settings.manualRate;
    if (raw == null) return null;
    final parsed = Decimal.tryParse(raw);
    if (parsed == null) return null;
    return ExchangeRate(
      baseCurrency: CurrencyCode.baseIso,
      targetCurrency: settings.targetCurrency.iso,
      rate: parsed,
      fetchedAt: DateTime.now().toUtc(),
      source: 'manual',
      isManual: true,
    );
  }

  /// Hedef para birimini değiştirir; kuru yeniden yükler.
  Future<void> setTargetCurrency(CurrencyCode code) async {
    await _ref
        .read(scannerSettingsControllerProvider.notifier)
        .setTargetCurrency(code);
    await _loadRate();
  }

  Future<void> refreshRate() async => _loadRate();

  Future<void> startProductPriceQuery() async {
    if (_disposed || state.isProductQueryRunning) return;
    final candidate = state.productQueryCandidate;
    final rate = state.exchangeRate;
    if (candidate == null || rate == null) return;

    final token = ++_productQueryRunToken;
    final japanPriceTry = candidate.amountInJpy * rate.rate.toDouble();
    var progress = [
      for (final source in ProductPriceSource.values)
        ProductPriceSourceProgress(
          source: source,
          status: ProductPriceSourceStatus.loading,
        ),
    ];

    state = state.copyWith(
      productQueryStatus: ProductPriceQueryStatus.loading,
      activeProductQueryCandidate: candidate,
      productQueryProgress: progress,
      clearProductPriceComparison: true,
      clearProductQueryError: true,
    );

    final pending = <_PendingSourceQuery>[
      for (final source in ProductPriceSource.values)
        _PendingSourceQuery(
          source: source,
          future: _fetchSourceOutcome(
            source: source,
            candidate: candidate,
            japanPriceTry: japanPriceTry,
          ),
        ),
    ];

    final quotes = <ProductMarketQuote>[];

    while (pending.isNotEmpty) {
      final completed = await Future.any(
        pending.map((item) async => (item: item, outcome: await item.future)),
      );

      if (_disposed || token != _productQueryRunToken) return;

      pending.remove(completed.item);
      final outcome = completed.outcome;

      progress = [
        for (final row in progress)
          if (row.source == outcome.source)
            row.copyWith(
              status: outcome.quote == null
                  ? ProductPriceSourceStatus.failed
                  : ProductPriceSourceStatus.success,
              quote: outcome.quote,
            )
          else
            row,
      ];

      if (outcome.quote != null) {
        quotes.add(outcome.quote!);
      } else if (outcome.error != null && outcome.stackTrace != null) {
        _logException(
          'market.${outcome.source.id}',
          outcome.error!,
          outcome.stackTrace!,
        );
      }

      state = state.copyWith(productQueryProgress: progress);
    }

    if (_disposed || token != _productQueryRunToken) return;

    if (quotes.isEmpty) {
      state = state.copyWith(
        productQueryStatus: ProductPriceQueryStatus.failed,
        productQueryErrorMessageKey: 'scanner.market.error.noResults',
      );
      return;
    }

    final comparison = ProductPriceComparison.fromQuotes(
      candidate: candidate,
      japanPriceTry: japanPriceTry,
      quotes: quotes,
    ).withSortedQuotes();

    state = state.copyWith(
      productQueryStatus: ProductPriceQueryStatus.completed,
      productPriceComparison: comparison,
      clearProductQueryError: true,
    );
  }

  void closeProductPriceQuerySheet() {
    _productQueryRunToken++;
    state = state.copyWith(
      productQueryStatus: ProductPriceQueryStatus.idle,
      clearActiveProductQueryCandidate: true,
      productQueryProgress: const [],
      clearProductPriceComparison: true,
      clearProductQueryError: true,
    );
  }

  Future<_SourceQueryOutcome> _fetchSourceOutcome({
    required ProductPriceSource source,
    required ProductQueryCandidate candidate,
    required double japanPriceTry,
  }) async {
    try {
      final quote = await _productPriceRepo.fetchQuote(
        source: source,
        candidate: candidate,
        japanPriceTry: japanPriceTry,
      );
      return _SourceQueryOutcome(source: source, quote: quote);
    } catch (error, stackTrace) {
      return _SourceQueryOutcome(
        source: source,
        quote: null,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> toggleFlash() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    final next = !state.flashEnabled;
    try {
      await cam.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      state = state.copyWith(flashEnabled: next);
    } catch (e, st) {
      _logException('camera.flash', e, st);
      // Flash olmayan cihaz — sessizce yoksay.
    }
  }

  /// Uygulama arka plana geçince kamerayı durdur, öne gelince yeniden başlat.
  Future<void> handleAppLifecycle(AppLifecycleState lifecycle) async {
    final cam = _camera;
    if (lifecycle == AppLifecycleState.inactive ||
        lifecycle == AppLifecycleState.paused) {
      if (cam != null && cam.value.isStreamingImages) {
        try {
          await cam.stopImageStream();
        } catch (e, st) {
          _logException('camera.stopImageStream.pause', e, st);
        }
      }
      _tracker.reset();
      state = state.copyWith(status: ScannerStatus.paused, trackedPrices: []);
    } else if (lifecycle == AppLifecycleState.resumed) {
      if (cam == null || !cam.value.isInitialized) {
        await _startCamera();
      } else if (!cam.value.isStreamingImages) {
        try {
          await cam.startImageStream(_onFrame);
          state = state.copyWith(status: ScannerStatus.scanning);
        } catch (e, st) {
          _logException('camera.startImageStream.resume', e, st);
          await _startCamera();
        }
      }
    }
  }

  /// İzin reddi sonrası yeniden dene.
  Future<void> retry() async {
    await _disposeCamera();
    _consecutiveFrameFailures = 0;
    await _startCamera();
  }

  Future<void> _disposeCamera() async {
    final cam = _camera;
    _camera = null;
    if (cam != null) {
      try {
        if (cam.value.isStreamingImages) await cam.stopImageStream();
      } catch (_) {}
      try {
        await cam.dispose();
      } catch (_) {}
    }
  }

  CameraController? get cameraController => _camera;

  void reportUiException(String tag, Object error, StackTrace stackTrace) {
    _logException('ui.$tag', error, stackTrace);
    state = state.copyWith(
      status: ScannerStatus.failure,
      errorMessageKey: 'scanner.error.previewStability',
    );
  }

  void _logException(String scope, Object error, StackTrace stackTrace) {
    debugPrint('[LiveCurrencyScanner][$scope] $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  @override
  void dispose() {
    _disposed = true;
    _productQueryRunToken++;
    _tracker.reset();
    unawaited(_disposeCamera());
    unawaited(_disposeRecognizer());
    super.dispose();
  }

  Future<void> _disposeRecognizer() async {
    try {
      await _recognizer.dispose();
    } catch (e, st) {
      _logException('ocr.dispose', e, st);
    }
  }
}

class _PendingSourceQuery {
  const _PendingSourceQuery({required this.source, required this.future});

  final ProductPriceSource source;
  final Future<_SourceQueryOutcome> future;
}

class _SourceQueryOutcome {
  const _SourceQueryOutcome({
    required this.source,
    this.quote,
    this.error,
    this.stackTrace,
  });

  final ProductPriceSource source;
  final ProductMarketQuote? quote;
  final Object? error;
  final StackTrace? stackTrace;
}

/// Kamera + OCR akışını yöneten controller (autoDispose — ekran kapanınca
/// kamera tamamen serbest bırakılır).
final liveCurrencyScannerControllerProvider = StateNotifierProvider.autoDispose<
    LiveCurrencyScannerController, LiveCurrencyScannerState>((ref) {
  return LiveCurrencyScannerController(ref);
});
