import 'dart:async';
import 'dart:io' show File;
import 'dart:ui' show Rect, Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/exchange_rate_store.dart';
import '../../plans/premium_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/tag_price_repository.dart';
import '../../../data/tag_scanner_client.dart';
import '../../live_currency_scanner/infrastructure/camera/camera_frame_adapter.dart';
import '../../live_currency_scanner/infrastructure/ocr/on_device_text_recognizer.dart';
import '../../live_currency_scanner/infrastructure/ocr/text_recognizer_factory.dart';
import '../services/mock_price_repository.dart';
import '../utils/tag_parser.dart';

const Rect kPriceTagViewfinderNormalizedRect =
    Rect.fromLTWH(0.14, 0.28, 0.72, 0.34);
/// Fiyat tarayıcı JPY→TRY kuru için SON ÇARE varsayılanı.
///
/// Normalde canlı kur kullanılır (bkz. [_jpyToTry]); bu sabit yalnızca
/// provider okunamadığında devreye girer.
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
    this.llmResult,
    this.secondaryPrices = const [],
    this.isLlmFallback = false,
    this.isLimitReached = false,
    this.dailyLimitRemaining,
    this.isPremiumUser,
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

  /// LLM'den gelen yapılandırılmış sonuç (başarılıysa).
  final TagScanResult? llmResult;

  /// Kasko, garanti, aksesuar gibi ikincil fiyatlar.
  final List<PriceItem> secondaryPrices;

  /// LLM başarısız olup TagParser fallback kullanıldıysa true.
  final bool isLlmFallback;

  /// Günlük tarama limiti doldu mu.
  final bool isLimitReached;

  /// Kalan günlük tarama hakkı (free user için).
  final int? dailyLimitRemaining;

  /// Premium kullanıcı mı.
  final bool? isPremiumUser;

  bool get isLive => mode == ScannerCaptureMode.live;
  bool get isFrozen => mode == ScannerCaptureMode.frozen;
  bool get hasModel => productModel != null && productModel!.isNotEmpty;

  /// LLM sonucu veya TagParser ile belirlenen marka.
  String? get resolvedBrand => llmResult?.brand;

  /// Foto çekip sorgulamak için yeterli veri var mı (model şart).
  bool get canCapture => hasModel && isCameraReady && !isLimitReached;

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
    TagScanResult? llmResult,
    List<PriceItem>? secondaryPrices,
    bool? isLlmFallback,
    bool? isLimitReached,
    int? dailyLimitRemaining,
    bool? isPremiumUser,
    bool clearModel = false,
    bool clearPrice = false,
    bool clearCapturedImage = false,
    bool clearMarketPrices = false,
    bool clearError = false,
    bool clearLlmResult = false,
    bool clearSecondaryPrices = false,
    bool clearLimitState = false,
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
      llmResult: clearLlmResult ? null : (llmResult ?? this.llmResult),
      secondaryPrices: clearSecondaryPrices
          ? const []
          : (secondaryPrices ?? this.secondaryPrices),
      isLlmFallback: isLlmFallback ?? this.isLlmFallback,
      isLimitReached: clearLimitState
          ? false
          : (isLimitReached ?? this.isLimitReached),
      dailyLimitRemaining: clearLimitState
          ? null
          : (dailyLimitRemaining ?? this.dailyLimitRemaining),
      isPremiumUser:
          clearLimitState ? null : (isPremiumUser ?? this.isPremiumUser),
    );
  }
}

final tagParserProvider = Provider<TagParser>((ref) => const TagParser());

final mockPriceRepositoryProvider =
    Provider<MockPriceRepository>((ref) => const MockPriceRepository());

final tagPriceRepositoryProvider = Provider<TagPriceRepository>((ref) {
  return TagPriceRepository(
    supabase: Supabase.instance.client,
  );
});

final tagScannerClientProvider = Provider<TagScannerClient>((ref) {
  return TagScannerClient(
    supabase: Supabase.instance.client,
  );
});

final scannerControllerProvider =
    StateNotifierProvider.autoDispose<ScannerController, ScannerState>((ref) {
  return ScannerController(ref);
});

class ScannerController extends StateNotifier<ScannerState> {
  ScannerController(this._ref)
      : _recognizer = createTextRecognizer(),
        super(const ScannerState());

  static const Duration _ocrThrottle = Duration(milliseconds: 450);
  static const int _maxBufferLines = 80;

  final Ref _ref;
  final OnDeviceTextRecognizer _recognizer;
  final CameraFrameAdapter _frameAdapter = const CameraFrameAdapter();

  CameraController? _camera;
  bool _ocrInFlight = false;
  bool _disposed = false;
  DateTime _lastOcrAt = DateTime.fromMillisecondsSinceEpoch(0);

  int _fetchToken = 0;

  // Çok-kareli oylama: OCR titremesine karşı model/fiyatı kararlı kılar.
  final Map<String, double> _modelVotes = <String, double>{};
  final Map<int, double> _priceVotes = <int, double>{};

  // LLM'e gönderilmek üzere OCR metin birikimi.
  final Set<String> _ocrLineBuffer = <String>{};

  TagParser get _tagParser => _ref.read(tagParserProvider);
  TagPriceRepository get _priceRepo => _ref.read(tagPriceRepositoryProvider);
  TagScannerClient get _tagClient => _ref.read(tagScannerClientProvider);

  CameraController? get cameraController => _camera;

  bool _debugPremium = false;

  /// Güncel JPY→TRY kuru — canlı/cache'li kur deposundan. Depo okunamazsa
  /// sabit varsayılana düşer.
  double get _jpyToTry {
    try {
      final r = _ref.read(jpyToTryProvider);
      if (r > 0 && r.isFinite) return r;
    } catch (_) {}
    return kJpyToTryMockRate;
  }

  Future<void> init() async {
    // Debug premium bayrağı — anahtar premium_provider.dart ile ORTAK
    // (kPremiumPrefsKey). Ekran ayrıca provider'ı canlı okuyor; burası
    // yalnızca limit hesabının açılış değeri.
    try {
      final prefs = await SharedPreferences.getInstance();
      _debugPremium = prefs.getBool(kPremiumPrefsKey) ?? false;
    } catch (_) {}
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

      // OCR metnini LLM buffer'ına ekle (benzersiz satırlar).
      for (final line in roiLines) {
        final trimmed = line.text.trim();
        if (trimmed.isNotEmpty && _ocrLineBuffer.length < _maxBufferLines) {
          _ocrLineBuffer.add(trimmed);
        }
      }

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
      final nextTry = nextJpy == null ? null : nextJpy * _jpyToTry;
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

  /// Kareyi dondurur: fotoğrafı çeker, canlı OCR'ı durdurur ve
  /// LLM (Edge Function) ile yapılandırılmış etiket analizi yapar.
  /// LLM başarısız olursa TagParser'a fallback yapar.
  Future<void> capture() async {
    if (_disposed || state.isFrozen) return;

    if (state.isLimitReached) return;

    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;

    // Anlık sayaç: backend cevabını beklemeden 1 azalt.
    final currentRemaining = state.dailyLimitRemaining;
    final nextRemaining = currentRemaining != null ? currentRemaining - 1 : null;

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
      dailyLimitRemaining: nextRemaining,
      isLimitReached: nextRemaining != null && nextRemaining <= 0,
      capturedImagePath: imagePath,
      clearMarketPrices: true,
      clearLlmResult: true,
      clearSecondaryPrices: true,
      clearError: true,
    );

    await _callLlmAndFetchPrices();
  }

  /// LLM çağrısı → sonuç → TR pazar fiyatları.
  /// Başarısız olursa TagParser fallback.
  Future<void> _callLlmAndFetchPrices() async {
    final token = ++_fetchToken;

    // Birikmiş OCR metin satırlarını al.
    final ocrLines = _ocrLineBuffer.toList();
    final hasBuffer = ocrLines.isNotEmpty;

    if (hasBuffer) {
      try {
        final llmResult = await _tagClient.parse(ocrLines: ocrLines);

        if (_disposed || token != _fetchToken) return;

        // LLM sonucu TagParser'dan daha iyi: ana ürün + kasko ayrımı yaptı.
        final nextModel = llmResult.productModel ?? state.productModel;
        final nextJpy = llmResult.mainPriceJpy ?? state.jpyPrice;
        final nextTry = nextJpy == null
            ? (state.tryPrice)
            : nextJpy * _jpyToTry;
        final secondary = llmResult.secondaryPrices;

        state = state.copyWith(
          productModel: nextModel,
          jpyPrice: nextJpy,
          tryPrice: nextTry,
          isModelLocked: true,
          llmResult: llmResult,
          secondaryPrices: secondary,
          isLlmFallback: false,
          dailyLimitRemaining: llmResult.limitRemaining,
          isPremiumUser: (llmResult.limitPremium == true) || _debugPremium,
          isLimitReached: _debugPremium
              ? false
              : llmResult.limitRemaining == 0 &&
                  !(llmResult.limitPremium == true),
          clearError: true,
        );

        // Pazar fiyatlarını getir (phase'i fetchingMockPrices yapar).
        await _fetchMarketPrices();
        return;

      } on TagScannerLimitExceeded catch (e) {
        if (_disposed || token != _fetchToken) return;

        state = state.copyWith(
          phase: ScannerPhase.error,
          isLimitReached: true,
          dailyLimitRemaining: 0,
          errorMessage: e.toString(),
        );
        return;

      } on TagScannerApiException catch (e) {
        _debug('llm.api', e, StackTrace.current);
        // LLM API hatası → TagParser fallback'e devam et.
      } catch (error, stackTrace) {
        _debug('llm.unexpected', error, stackTrace);
        // Beklenmeyen hata → TagParser fallback'e devam et.
      }
    }

    // --- LLM başarısız oldu: TagParser fallback ---
    _fallbackToTagParser(token);
  }

  /// LLM başarısız olduğunda TagParser ile çalışır.
  void _fallbackToTagParser(int token) {
    if (_disposed || token != _fetchToken) return;

    final fullText = _ocrLineBuffer.toList().join('\n');
    if (fullText.isEmpty) {
      _setError('Etiket metni okunamadı. Daha net bir açıyla tekrar deneyin.');
      return;
    }

    final parseResult = _tagParser.parse(fullText);
    final model = parseResult.productModel ?? state.productModel;
    final jpy = parseResult.jpyPrice ?? state.jpyPrice;
    final tr = jpy == null ? (state.tryPrice) : jpy * _jpyToTry;

    state = state.copyWith(
      phase: (model != null || jpy != null)
          ? ScannerPhase.extractedData
          : ScannerPhase.error,
      productModel: model,
      isModelLocked: model != null,
      jpyPrice: jpy,
      tryPrice: tr,
      isLlmFallback: true,
      clearError: model == null && jpy == null ? false : true,
      errorMessage: model == null && jpy == null
          ? 'Model ve fiyat tespit edilemedi. El ile girin veya tekrar tarayın.'
          : null,
    );

    if (model != null || jpy != null) {
      // Pazar fiyatlarını yine de getir (mock).
      unawaited(_fetchMarketPrices());
    }
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
    _ocrLineBuffer.clear();

    state = state.copyWith(
      mode: ScannerCaptureMode.live,
      phase: ScannerPhase.scanning,
      isModelLocked: false,
      clearModel: true,
      clearPrice: true,
      clearCapturedImage: true,
      clearMarketPrices: true,
      clearLlmResult: true,
      clearSecondaryPrices: true,
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
      await _fetchMarketPrices();
    }
  }

  Future<void> _fetchMarketPrices() async {
    final model = state.productModel;
    if (model == null || model.isEmpty) return;

    final referenceTry =
        state.tryPrice ?? (state.jpyPrice ?? 0) * _jpyToTry;
    final referenceJpy = state.jpyPrice;
    final token = ++_fetchToken;

    state = state.copyWith(
      phase: ScannerPhase.fetchingMockPrices,
      clearMarketPrices: true,
      clearError: true,
    );

    try {
      final response = await _priceRepo.fetchMarketplacePrices(
        productModel: model,
        referenceTryPrice: referenceTry,
        referenceJpyPrice: referenceJpy,
      );

      if (_disposed || token != _fetchToken) return;

      final marketPrices = _extractMarketPrices(response['platforms']);

      state = state.copyWith(
        phase: ScannerPhase.resultReady,
        marketPrices: marketPrices,
        clearError: true,
      );
    } catch (error, stackTrace) {
      _debug('market.fetch', error, stackTrace);
      if (_disposed || token != _fetchToken) return;
      _setError('TR pazar fiyatları alınamadı.');
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
    _ocrLineBuffer.clear();
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
