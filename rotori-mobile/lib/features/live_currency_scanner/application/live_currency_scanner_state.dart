import 'dart:ui' show Size;

import '../domain/currency_code.dart';
import '../domain/exchange_rate.dart';
import '../domain/product_price_query.dart';
import '../domain/tracked_price.dart';

/// Tarayıcı yaşam döngüsü durumu.
enum ScannerStatus {
  initial,
  requestingPermission,
  initializingCamera,
  ready,
  scanning,
  paused,
  permissionDenied,
  permissionPermanentlyDenied,
  cameraUnavailable,
  failure,
}

/// Kur tazelik durumu (UI uyarısı için).
enum RateFreshness { fresh, aging, stale, missing }

/// Canlı para çevirici ekranının immutable durumu.
class LiveCurrencyScannerState {
  const LiveCurrencyScannerState({
    this.status = ScannerStatus.initial,
    this.trackedPrices = const [],
    this.targetCurrency = CurrencyCode.tryl,
    this.exchangeRate,
    this.rateFreshness = RateFreshness.missing,
    this.flashEnabled = false,
    this.isProcessingFrame = false,
    this.lastFrameProcessedAt,
    this.imageSize = Size.zero,
    this.rotationDegrees = 0,
    this.mirrored = false,
    this.productQueryCandidate,
    this.activeProductQueryCandidate,
    this.productQueryStatus = ProductPriceQueryStatus.idle,
    this.productQueryProgress = const [],
    this.productPriceComparison,
    this.productQueryErrorMessageKey,
    this.errorMessageKey,
  });

  final ScannerStatus status;
  final List<TrackedPrice> trackedPrices;
  final CurrencyCode targetCurrency;
  final ExchangeRate? exchangeRate;
  final RateFreshness rateFreshness;
  final bool flashEnabled;
  final bool isProcessingFrame;
  final DateTime? lastFrameProcessedAt;

  /// OCR kaynağının görüntü boyutu (koordinat dönüşümü için).
  final Size imageSize;
  final int rotationDegrees;
  final bool mirrored;

  /// Kamerada şu anda sorgulanabilir olarak bulunan ürün adayı.
  final ProductQueryCandidate? productQueryCandidate;

  /// Kullanıcının sorgulamayı başlattığı anın sabit ürün adayı.
  final ProductQueryCandidate? activeProductQueryCandidate;

  /// HB/TY/Amazon sorgu üst durum makinesi.
  final ProductPriceQueryStatus productQueryStatus;

  /// Kaynak bazlı ilerleme satırları.
  final List<ProductPriceSourceProgress> productQueryProgress;

  /// Sorgu tamamlandığında hesaplanan karşılaştırma özeti.
  final ProductPriceComparison? productPriceComparison;

  /// Ürün sorgu akışı için kullanıcıya gösterilecek hata anahtarı.
  final String? productQueryErrorMessageKey;

  /// Kullanıcıya gösterilecek i18n hata anahtarı (teknik metin değil).
  final String? errorMessageKey;

  bool get isLive =>
      status == ScannerStatus.ready || status == ScannerStatus.scanning;

  bool get hasDetections => trackedPrices.isNotEmpty;

    bool get hasQueryableProduct => productQueryCandidate != null;

    bool get isProductQueryRunning =>
      productQueryStatus == ProductPriceQueryStatus.loading;

    bool get isProductQuerySheetVisible =>
      productQueryStatus != ProductPriceQueryStatus.idle;

  LiveCurrencyScannerState copyWith({
    ScannerStatus? status,
    List<TrackedPrice>? trackedPrices,
    CurrencyCode? targetCurrency,
    ExchangeRate? exchangeRate,
    RateFreshness? rateFreshness,
    bool? flashEnabled,
    bool? isProcessingFrame,
    DateTime? lastFrameProcessedAt,
    Size? imageSize,
    int? rotationDegrees,
    bool? mirrored,
    ProductQueryCandidate? productQueryCandidate,
    ProductQueryCandidate? activeProductQueryCandidate,
    ProductPriceQueryStatus? productQueryStatus,
    List<ProductPriceSourceProgress>? productQueryProgress,
    ProductPriceComparison? productPriceComparison,
    String? productQueryErrorMessageKey,
    String? errorMessageKey,
    bool clearProductQueryCandidate = false,
    bool clearActiveProductQueryCandidate = false,
    bool clearProductQueryError = false,
    bool clearProductPriceComparison = false,
    bool clearError = false,
  }) {
    return LiveCurrencyScannerState(
      status: status ?? this.status,
      trackedPrices: trackedPrices ?? this.trackedPrices,
      targetCurrency: targetCurrency ?? this.targetCurrency,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      rateFreshness: rateFreshness ?? this.rateFreshness,
      flashEnabled: flashEnabled ?? this.flashEnabled,
      isProcessingFrame: isProcessingFrame ?? this.isProcessingFrame,
      lastFrameProcessedAt: lastFrameProcessedAt ?? this.lastFrameProcessedAt,
      imageSize: imageSize ?? this.imageSize,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      mirrored: mirrored ?? this.mirrored,
          productQueryCandidate: clearProductQueryCandidate
            ? null
            : (productQueryCandidate ?? this.productQueryCandidate),
          activeProductQueryCandidate: clearActiveProductQueryCandidate
            ? null
            : (activeProductQueryCandidate ?? this.activeProductQueryCandidate),
        productQueryStatus: productQueryStatus ?? this.productQueryStatus,
        productQueryProgress: productQueryProgress ?? this.productQueryProgress,
        productPriceComparison: clearProductPriceComparison
          ? null
          : (productPriceComparison ?? this.productPriceComparison),
        productQueryErrorMessageKey: clearProductQueryError
          ? null
          : (productQueryErrorMessageKey ?? this.productQueryErrorMessageKey),
      errorMessageKey:
          clearError ? null : (errorMessageKey ?? this.errorMessageKey),
    );
  }
}
