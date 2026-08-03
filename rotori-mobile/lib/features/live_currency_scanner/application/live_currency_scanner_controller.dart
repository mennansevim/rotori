import 'dart:async';

import 'package:camera/camera.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/currency_code.dart';
import '../domain/exchange_rate.dart';
import '../domain/repositories/exchange_rate_repository.dart';
import '../domain/scanner_settings.dart';
import '../infrastructure/camera/camera_frame_adapter.dart';
import '../infrastructure/ocr/ocr_price_extractor.dart';
import '../infrastructure/ocr/on_device_text_recognizer.dart';
import '../infrastructure/ocr/text_recognizer_factory.dart';
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

  OcrPriceExtractor get _extractor => _ref.read(ocrPriceExtractorProvider);
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
      await controller.initialize();
      if (_disposed) {
        await controller.dispose();
        return;
      }
      _sinceLastProcess.start();
      await controller.startImageStream(_onFrame);
      state = state.copyWith(
        status: ScannerStatus.scanning,
        rotationDegrees: back.sensorOrientation,
        mirrored: back.lensDirection == CameraLensDirection.front,
      );
    } on CameraException catch (e) {
      state = state.copyWith(status: _mapCameraError(e));
    } catch (_) {
      state = state.copyWith(status: ScannerStatus.failure);
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
      if (_disposed) return;
      state = state.copyWith(
        status: ScannerStatus.scanning,
        trackedPrices: visible,
        imageSize: recognized.imageSize == frame.imageSize
            ? recognized.imageSize
            : frame.imageSize,
        lastFrameProcessedAt: DateTime.now(),
        isProcessingFrame: false,
      );
    } catch (_) {
      // Tek kare hatası akışı bozmaz.
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

  Future<void> toggleFlash() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    final next = !state.flashEnabled;
    try {
      await cam.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      state = state.copyWith(flashEnabled: next);
    } catch (_) {
      // Flash olmayan cihaz — sessizce yoksay.
    }
  }

  /// Uygulama arka plana geçince kamerayı durdur, öne gelince yeniden başlat.
  Future<void> handleAppLifecycle(AppLifecycleState lifecycle) async {
    final cam = _camera;
    if (lifecycle == AppLifecycleState.inactive ||
        lifecycle == AppLifecycleState.paused) {
      if (cam != null && cam.value.isStreamingImages) {
        await cam.stopImageStream();
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
        } catch (_) {
          await _startCamera();
        }
      }
    }
  }

  /// İzin reddi sonrası yeniden dene.
  Future<void> retry() async {
    await _disposeCamera();
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

  @override
  void dispose() {
    _disposed = true;
    _tracker.reset();
    unawaited(_disposeCamera());
    unawaited(_recognizer.dispose());
    super.dispose();
  }
}

/// Kamera + OCR akışını yöneten controller (autoDispose — ekran kapanınca
/// kamera tamamen serbest bırakılır).
final liveCurrencyScannerControllerProvider = StateNotifierProvider.autoDispose<
    LiveCurrencyScannerController, LiveCurrencyScannerState>((ref) {
  return LiveCurrencyScannerController(ref);
});
