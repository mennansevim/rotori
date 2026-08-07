import 'dart:async';
import 'dart:io' show File;
import 'dart:ui' show Rect, Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../live_currency_scanner/infrastructure/camera/camera_frame_adapter.dart';
import '../../live_currency_scanner/infrastructure/ocr/on_device_text_recognizer.dart';
import '../../live_currency_scanner/infrastructure/ocr/text_recognizer_factory.dart';
import '../services/mock_price_repository.dart';
import '../utils/tag_parser.dart';

const Rect kPriceTagViewfinderNormalizedRect =
    Rect.fromLTWH(0.14, 0.28, 0.72, 0.34);
const double kJpyToTryMockRate = 0.22;

/// Bir modelin/fiyatın "kilitli" (kararlı) sayılması için gereken oy sayısı.
const int kStableLockVotes = 3;

/// OCR ekranının üst seviye durumları.
enum ScannerPhase {
  scanning,
  extractedData,
  fetchingMockPrices,
  resultReady,
  error,
}

/// Canlı tarama mı, dondurulmuş (foto çekilmiş) sonuç ekranı mı.
enum ScannerCaptureMode { live, frozen }

class ScannerState {
  const ScannerState({
    this.phase = ScannerPhase.scanning,
    this.mode = ScannerCaptureMode.live,
    this.isCameraReady = false,
    this.isProcessingFrame = false,
    this.isTorchEnabled = false,
    this.productModel,
    this.isModelLocked = false,
    this.jpyPrice,
    this.tryPrice,
    this.recognizedText = '',
    this.capturedImagePath,
    this.marketPrices = const [],
    this.imageSize = Size.zero,
    this.rotationDegrees = 0,
    this.mirrored = false,
    this.errorMessage,
  });

  final ScannerPhase phase;
  final ScannerCaptureMode mode;
  final bool isCameraReady;
  final bool isProcessingFrame;
  final bool isTorchEnabled;

  /// Kararlı (oylanmış) ürün modeli — bulunduktan sonra tek kötü karede silinmez.
  final String? productModel;

  /// Model yeterli kez doğrulandı mı (üstte "hazır" göstergesi için).
  final bool isModelLocked;

  final int? jpyPrice;
  final double? tryPrice;
  final String recognizedText;

  /// Dondurulmuş ekranda arka plan olarak gösterilen çekilmiş kare yolu.
  final String? capturedImagePath;

  final List<Map<String, dynamic>> marketPrices;

  final Size imageSize;
  final int rotationDegrees;
  final bool mirrored;

  final String? errorMessage;

  bool get isLive => mode == ScannerCaptureMode.live;
  bool get isFrozen => mode == ScannerCaptureMode.frozen;
  bool get hasModel => productModel != null && productModel!.isNotEmpty;

  /// Foto çekip sorgulamak için yeterli veri var mı (model şart).
  bool get canCapture => hasModel && isCameraReady;

  ScannerState copyWith({
    ScannerPhase? phase,
    ScannerCaptureMode? mode,
    bool? isCameraReady,
    bool? isProcessingFrame,
    bool? isTorchEnabled,
    String? productModel,
    bool? isModelLocked,
    int? jpyPrice,
    double? tryPrice,
    String? recognizedText,
    String? capturedImagePath,
    List<Map<String, dynamic>>? marketPrices,
    Size? imageSize,
    int? rotationDegrees,
    bool? mirrored,
    String? errorMessage,
    bool clearModel = false,
    bool clearPrice = false,
    bool clearCapturedImage = false,
    bool clearMarketPrices = false,
    bool clearError = false,
  }) {
    return ScannerState(
      phase: phase ?? this.phase,
      mode: mode ?? this.mode,
      isCameraReady: isCameraReady ?? this.isCameraReady,
      isProcessingFrame: isProcessingFrame ?? this.isProcessingFrame,
      isTorchEnabled: isTorchEnabled ?? this.isTorchEnabled,
      productModel: clearModel ? null : (productModel ?? this.productModel),
      isModelLocked: isModelLocked ?? this.isModelLocked,
      jpyPrice: clearPrice ? null : (jpyPrice ?? this.jpyPrice),
      tryPrice: clearPrice ? null : (tryPrice ?? this.tryPrice),
      recognizedText: recognizedText ?? this.recognizedText,
      capturedImagePath: clearCapturedImage
          ? null
          : (capturedImagePath ?? this.capturedImagePath),
      marketPrices:
          clearMarketPrices ? const [] : (marketPrices ?? this.marketPrices),
      imageSize: imageSize ?? this.imageSize,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      mirrored: mirrored ?? this.mirrored,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final tagParserProvider = Provider<TagParser>((ref) => const TagParser());

final mockPriceRepositoryProvider =
    Provider<MockPriceRepository>((ref) => const MockPriceRepository());

final scannerControllerProvider =
    StateNotifierProvider.autoDispose<ScannerController, ScannerState>((ref) {
  return ScannerController(ref);
});

class ScannerController extends StateNotifier<ScannerState> {
  ScannerController(this._ref)
      : _recognizer = createTextRecognizer(),
        super(const ScannerState());

  static const Duration _ocrThrottle = Duration(milliseconds: 450);

  final Ref _ref;
  final OnDeviceTextRecognizer _recognizer;
  final CameraFrameAdapter _frameAdapter = const CameraFrameAdapter();

  CameraController? _camera;
  bool _ocrInFlight = false;
  bool _disposed = false;
  DateTime _lastOcrAt = DateTime.fromMillisecondsSinceEpoch(0);

  int _fetchToken = 0;

  // Çok-kareli oylama: OCR titremesine karşı model/fiyatı kararlı kılar.
  // Oylar merkez-ağırlıklıdır: viewfinder merkezine yakın metin daha çok oy alır.
  final Map<String, double> _modelVotes = <String, double>{};
  final Map<int, double> _priceVotes = <int, double>{};

  TagParser get _tagParser => _ref.read(tagParserProvider);
  MockPriceRepository get _mockRepo => _ref.read(mockPriceRepositoryProvider);

  CameraController? get cameraController => _camera;

  Future<void> init() async {
    if (_disposed) return;
    await _startCamera();
  }

  Future<void> _startCamera() async {
    state = state.copyWith(
      phase: ScannerPhase.scanning,
      clearError: true,
      isCameraReady: false,
    );

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setError('Kamera bulunamadı.');
        return;
      }

      final back = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final camera = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );

      _camera = camera;
      await camera.initialize();

      if (_disposed) {
        await camera.dispose();
        return;
      }

      await camera.startImageStream(_onFrame);

      state = state.copyWith(
        phase: ScannerPhase.scanning,
        isCameraReady: true,
        rotationDegrees: back.sensorOrientation,
        mirrored: back.lensDirection == CameraLensDirection.front,
        clearError: true,
      );
    } on CameraException catch (error, stackTrace) {
      _debug('camera.start', error, stackTrace);
      _setError('Kamera başlatılamadı. İzinleri kontrol edin.');
    } catch (error, stackTrace) {
      _debug('camera.start.unknown', error, stackTrace);
      _setError('Tarayıcı başlatılırken beklenmeyen hata oluştu.');
    }
  }

  void _onFrame(CameraImage image) {
    if (_disposed || _ocrInFlight || state.isFrozen) return;

    final now = DateTime.now();
    if (now.difference(_lastOcrAt) < _ocrThrottle) {
      return;
    }

    _ocrInFlight = true;
    _lastOcrAt = now;

    unawaited(_processFrame(image).whenComplete(() {
      _ocrInFlight = false;
    }));
  }

  Future<void> _processFrame(CameraImage image) async {
    try {
      final frame = _frameAdapter.fromCameraImage(
        image,
        rotationDegrees: state.rotationDegrees,
      );

      final recognized = await _recognizer.recognize(frame);
      if (_disposed || state.isFrozen) return;

      final roiLines = _roiLines(recognized);
      if (roiLines.isEmpty) return;

      // Model: her satırı ayrı değerlendirip merkeze yakınlığına göre oy ver.
      // Böylece yandaki komşu ürünün kodu değil, çerçeve ortasındaki ürün kazanır.
      for (final line in roiLines) {
        final token = _tagParser.extractModelToken(line.text);
        if (token != null && token.isNotEmpty) {
          _modelVotes.update(token, (v) => v + line.weight,
              ifAbsent: () => line.weight);
        }
        final linePrice = _tagParser.extractJpyPriceInLine(line.text);
        if (linePrice != null) {
          _priceVotes.update(linePrice, (v) => v + line.weight,
              ifAbsent: () => line.weight);
        }
      }

      final bestModel = _topVote(_modelVotes);
      final bestJpy = _topVote(_priceVotes);

      final nextModel = bestModel?.key ?? state.productModel;
      final nextJpy = bestJpy?.key ?? state.jpyPrice;
      final nextTry = nextJpy == null ? null : nextJpy * kJpyToTryMockRate;
      final locked = (bestModel?.value ?? 0) >= kStableLockVotes;

      state = state.copyWith(
        phase: (nextModel != null || nextJpy != null)
            ? ScannerPhase.extractedData
            : ScannerPhase.scanning,
        productModel: nextModel,
        isModelLocked: locked,
        jpyPrice: nextJpy,
        tryPrice: nextTry,
        recognizedText:
            roiLines.map((l) => l.text).join('\n'),
        imageSize: recognized.imageSize,
        clearError: true,
      );
    } catch (error, stackTrace) {
      _debug('ocr.process', error, stackTrace);
      // Tek kare hatası akışı bozmaz; kullanıcıyı hataya düşürme.
    }
  }

  /// En yüksek oyu alan (değer, oy) çiftini döndürür; boşsa null.
  MapEntry<T, double>? _topVote<T>(Map<T, double> votes) {
    if (votes.isEmpty) return null;
    MapEntry<T, double>? best;
    for (final entry in votes.entries) {
      if (best == null || entry.value > best.value) best = entry;
    }
    return best;
  }

  /// ROI (viewfinder) içine düşen satırları, merkeze yakınlık ağırlığıyla döndürür.
  /// Ağırlık merkezde ~1.0, kenarlarda ~0.2'ye iner; yatay uzaklığa daha duyarlıdır
  /// (yan yana duran komşu ürünleri elemek için).
  List<_RoiLine> _roiLines(RecognizedFrame frame) {
    if (frame.lines.isEmpty || frame.imageSize == Size.zero) {
      return const <_RoiLine>[];
    }

    final w = frame.imageSize.width;
    final h = frame.imageSize.height;
    final roi = Rect.fromLTWH(
      w * kPriceTagViewfinderNormalizedRect.left,
      h * kPriceTagViewfinderNormalizedRect.top,
      w * kPriceTagViewfinderNormalizedRect.width,
      h * kPriceTagViewfinderNormalizedRect.height,
    );
    final cx = roi.center.dx;
    final cy = roi.center.dy;
    final halfW = roi.width / 2;
    final halfH = roi.height / 2;

    final out = <_RoiLine>[];
    for (final line in frame.lines) {
      final box = line.boundingBox;
      if (!box.overlaps(roi)) continue;

      // Yatay uzaklığı dikeyden daha çok cezalandır (komşu ürünler yanda durur).
      final dx = ((box.center.dx - cx) / (halfW == 0 ? 1 : halfW)).abs();
      final dy = ((box.center.dy - cy) / (halfH == 0 ? 1 : halfH)).abs();
      final dist = (dx * 1.4 + dy * 0.6) / 2;
      final weight = (1.0 - dist).clamp(0.2, 1.0);

      out.add(_RoiLine(text: line.text, box: box, weight: weight));
    }

    out.sort((a, b) {
      final topDelta = (a.box.top - b.box.top).abs();
      if (topDelta < 8) return a.box.left.compareTo(b.box.left);
      return a.box.top.compareTo(b.box.top);
    });

    return out;
  }

  /// Kareyi dondurur: fotoğrafı çeker, canlı OCR'ı durdurur ve tek seferlik
  /// pazar sorgusu başlatır. Sonuç ekranı artık titremez (sabit kalır).
  Future<void> capture() async {
    if (_disposed || state.isFrozen || !state.hasModel) return;
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;

    String? imagePath;
    try {
      if (camera.value.isStreamingImages) {
        await camera.stopImageStream();
      }
      final file = await camera.takePicture();
      imagePath = file.path;
    } catch (error, stackTrace) {
      _debug('camera.capture', error, stackTrace);
    }

    if (_disposed) return;

    state = state.copyWith(
      mode: ScannerCaptureMode.frozen,
      phase: ScannerPhase.fetchingMockPrices,
      capturedImagePath: imagePath,
      clearMarketPrices: true,
      clearError: true,
    );

    await _fetchMockPrices();
  }

  /// Dondurulmuş ekrandan canlı taramaya geri döner.
  Future<void> resumeScanning() async {
    if (_disposed) return;

    final path = state.capturedImagePath;
    if (path != null) {
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }

    _fetchToken++;
    _modelVotes.clear();
    _priceVotes.clear();

    state = state.copyWith(
      mode: ScannerCaptureMode.live,
      phase: ScannerPhase.scanning,
      isModelLocked: false,
      clearModel: true,
      clearPrice: true,
      clearCapturedImage: true,
      clearMarketPrices: true,
      clearError: true,
    );

    final camera = _camera;
    if (camera != null &&
        camera.value.isInitialized &&
        !camera.value.isStreamingImages) {
      try {
        await camera.startImageStream(_onFrame);
      } catch (error, stackTrace) {
        _debug('camera.resumeStream', error, stackTrace);
        await _startCamera();
      }
    } else if (camera == null || !camera.value.isInitialized) {
      await _startCamera();
    }
  }

  /// Kullanıcı OCR'ın yanlış okuduğu modeli elle düzeltir; sorgu tazelenir.
  Future<void> setModelOverride(String model) async {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return;

    state = state.copyWith(
      productModel: trimmed,
      isModelLocked: true,
    );

    if (state.isFrozen) {
      await _fetchMockPrices();
    }
  }

  Future<void> _fetchMockPrices() async {
    final model = state.productModel;
    if (model == null || model.isEmpty) return;

    final referenceTry =
        state.tryPrice ?? (state.jpyPrice ?? 0) * kJpyToTryMockRate;
    final token = ++_fetchToken;

    state = state.copyWith(
      phase: ScannerPhase.fetchingMockPrices,
      clearMarketPrices: true,
      clearError: true,
    );

    try {
      final response = await _mockRepo.fetchMarketplacePrices(
        productModel: model,
        referenceTryPrice: referenceTry,
      );

      if (_disposed || token != _fetchToken) return;

      final marketPrices = _extractMarketPrices(response['platforms']);

      state = state.copyWith(
        phase: ScannerPhase.resultReady,
        marketPrices: marketPrices,
        clearError: true,
      );
    } catch (error, stackTrace) {
      _debug('mock.fetch', error, stackTrace);
      if (_disposed || token != _fetchToken) return;
      _setError('Mock pazar fiyatları alınamadı.');
    }
  }

  List<Map<String, dynamic>> _extractMarketPrices(Object? rawPlatforms) {
    if (rawPlatforms is! List) {
      return const <Map<String, dynamic>>[];
    }

    return rawPlatforms
        .whereType<Map<dynamic, dynamic>>()
        .map((entry) => entry.map(
              (key, value) => MapEntry(key.toString(), value),
            ))
        .toList(growable: false);
  }

  Future<void> toggleTorch() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;

    final enable = !state.isTorchEnabled;

    try {
      await camera.setFlashMode(enable ? FlashMode.torch : FlashMode.off);
      state = state.copyWith(isTorchEnabled: enable);
    } catch (error, stackTrace) {
      _debug('camera.torch', error, stackTrace);
    }
  }

  Future<void> handleLifecycle(AppLifecycleState lifecycle) async {
    final camera = _camera;

    if (lifecycle == AppLifecycleState.inactive ||
        lifecycle == AppLifecycleState.paused) {
      if (camera != null && camera.value.isStreamingImages) {
        try {
          await camera.stopImageStream();
        } catch (_) {}
      }
      return;
    }

    if (lifecycle == AppLifecycleState.resumed) {
      if (camera == null || !camera.value.isInitialized) {
        await _startCamera();
        return;
      }

      if (!camera.value.isStreamingImages) {
        try {
          await camera.startImageStream(_onFrame);
        } catch (error, stackTrace) {
          _debug('camera.resume', error, stackTrace);
          await _startCamera();
        }
      }
    }
  }

  Future<void> retry() async {
    _fetchToken++;
    _modelVotes.clear();
    _priceVotes.clear();
    await _disposeCamera();
    state = const ScannerState();
    await _startCamera();
  }

  Future<void> _disposeCamera() async {
    final camera = _camera;
    _camera = null;

    if (camera == null) return;

    try {
      if (camera.value.isStreamingImages) {
        await camera.stopImageStream();
      }
    } catch (_) {}

    try {
      await camera.dispose();
    } catch (_) {}
  }

  void _setError(String message) {
    state = state.copyWith(
      phase: ScannerPhase.error,
      isCameraReady: false,
      errorMessage: message,
    );
  }

  void _debug(String scope, Object error, StackTrace stackTrace) {
    debugPrint('[PriceTagScanner][$scope] $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  @override
  void dispose() {
    _disposed = true;
    _fetchToken++;
    _ocrInFlight = false;
    unawaited(_disposeCamera());
    unawaited(_recognizer.dispose());
    super.dispose();
  }
}

/// ROI içindeki tek bir OCR satırı + merkeze yakınlık ağırlığı.
class _RoiLine {
  const _RoiLine({
    required this.text,
    required this.box,
    required this.weight,
  });

  final String text;
  final Rect box;
  final double weight;
}
