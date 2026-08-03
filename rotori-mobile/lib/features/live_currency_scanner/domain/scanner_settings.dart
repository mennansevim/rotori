import 'currency_code.dart';

/// Çevrilen tutarın yuvarlanma tercihi.
enum RoundingPreference {
  /// Yuvarlama yok — para biriminin ondalık hanesi kadar gösterilir.
  none,

  /// En yakın tam birime (1 TL / 1 ₩ vb).
  nearestWhole,

  /// En yakın 10 birime.
  nearestTen;

  static RoundingPreference fromName(String? raw) => switch (raw) {
        'nearestWhole' => RoundingPreference.nearestWhole,
        'nearestTen' => RoundingPreference.nearestTen,
        _ => RoundingPreference.none,
      };
}

/// OCR analiz sıklığı profili — cihaz gücüne / pil durumuna göre ayarlanır.
enum ScannerPerformanceProfile {
  batterySaver,
  balanced,
  highAccuracy;

  /// İki OCR koşusu arasındaki minimum süre.
  Duration get processingInterval => switch (this) {
        ScannerPerformanceProfile.batterySaver =>
          const Duration(milliseconds: 500),
        ScannerPerformanceProfile.balanced => const Duration(milliseconds: 300),
        ScannerPerformanceProfile.highAccuracy =>
          const Duration(milliseconds: 200),
      };

  static ScannerPerformanceProfile fromName(String? raw) => switch (raw) {
        'batterySaver' => ScannerPerformanceProfile.batterySaver,
        'highAccuracy' => ScannerPerformanceProfile.highAccuracy,
        _ => ScannerPerformanceProfile.balanced,
      };
}

/// Kullanıcının canlı para çevirici tercihleri — kalıcı, immutable.
class ScannerSettings {
  const ScannerSettings({
    this.targetCurrency = CurrencyCode.tryl,
    this.autoUpdateRate = true,
    this.useManualRate = false,
    this.manualRate,
    this.cardMarkupPercent = 0,
    this.rounding = RoundingPreference.none,
    this.performanceProfile = ScannerPerformanceProfile.balanced,
  });

  /// Hedef para birimi (varsayılan TRY).
  final CurrencyCode targetCurrency;

  /// Otomatik kur güncelleme açık mı?
  final bool autoUpdateRate;

  /// Manuel kur kullanılıyor mu? Açıkken remote kur ezmez.
  final bool useManualRate;

  /// Manuel kur değeri (`1 JPY = manualRate TARGET`), string olarak saklanır
  /// (Decimal hassasiyeti korunur). null ise manuel kur yok.
  final String? manualRate;

  /// Kart/banka fark yüzdesi (ör. 2 → %2). İsteğe bağlı, 0 = kapalı.
  final double cardMarkupPercent;

  /// Yuvarlama tercihi.
  final RoundingPreference rounding;

  /// OCR analiz sıklığı profili.
  final ScannerPerformanceProfile performanceProfile;

  ScannerSettings copyWith({
    CurrencyCode? targetCurrency,
    bool? autoUpdateRate,
    bool? useManualRate,
    String? manualRate,
    bool clearManualRate = false,
    double? cardMarkupPercent,
    RoundingPreference? rounding,
    ScannerPerformanceProfile? performanceProfile,
  }) {
    return ScannerSettings(
      targetCurrency: targetCurrency ?? this.targetCurrency,
      autoUpdateRate: autoUpdateRate ?? this.autoUpdateRate,
      useManualRate: useManualRate ?? this.useManualRate,
      manualRate: clearManualRate ? null : (manualRate ?? this.manualRate),
      cardMarkupPercent: cardMarkupPercent ?? this.cardMarkupPercent,
      rounding: rounding ?? this.rounding,
      performanceProfile: performanceProfile ?? this.performanceProfile,
    );
  }

  Map<String, dynamic> toJson() => {
        'targetCurrency': targetCurrency.iso,
        'autoUpdateRate': autoUpdateRate,
        'useManualRate': useManualRate,
        'manualRate': manualRate,
        'cardMarkupPercent': cardMarkupPercent,
        'rounding': rounding.name,
        'performanceProfile': performanceProfile.name,
      };

  static ScannerSettings fromJson(Map<String, dynamic> json) => ScannerSettings(
        targetCurrency: CurrencyCode.fromIso(json['targetCurrency'] as String?),
        autoUpdateRate: (json['autoUpdateRate'] as bool?) ?? true,
        useManualRate: (json['useManualRate'] as bool?) ?? false,
        manualRate: json['manualRate'] as String?,
        cardMarkupPercent: (json['cardMarkupPercent'] as num?)?.toDouble() ?? 0,
        rounding: RoundingPreference.fromName(json['rounding'] as String?),
        performanceProfile: ScannerPerformanceProfile.fromName(
            json['performanceProfile'] as String?),
      );
}
