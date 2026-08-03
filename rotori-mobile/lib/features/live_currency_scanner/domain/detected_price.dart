import 'dart:ui' show Rect;

import 'japanese_price_tax_type.dart';

/// OCR + parser'ın ürettiği tek bir aday Japon-yeni fiyatı.
///
/// [boundingBox] OCR'ın döndürdüğü **görüntü (image) koordinat** sistemindedir;
/// ekran koordinatına dönüşüm `CameraCoordinateTransformer` ile yapılır.
/// [amountInJpy] tam sayı yendir (JPY minor unit = 1, ondalık yok) — böylece
/// para hesabında double hassasiyet sorunu oluşmaz.
class DetectedPrice {
  const DetectedPrice({
    required this.id,
    required this.amountInJpy,
    required this.rawText,
    required this.boundingBox,
    required this.confidence,
    required this.taxType,
  });

  /// Kararlı kimlik — parser aynı metin bloğu için deterministik üretir.
  final String id;

  /// Fiyat tutarı, tam sayı yen.
  final int amountInJpy;

  /// Normalize edilmemiş ham OCR metni (analitiğe GÖNDERİLMEZ, yalnız debug/UI).
  final String rawText;

  /// OCR görüntü koordinatındaki sınır kutusu.
  final Rect boundingBox;

  /// 0..1 arası güven skoru.
  final double confidence;

  /// Vergi durumu.
  final JapanesePriceTaxType taxType;

  DetectedPrice copyWith({
    String? id,
    int? amountInJpy,
    String? rawText,
    Rect? boundingBox,
    double? confidence,
    JapanesePriceTaxType? taxType,
  }) {
    return DetectedPrice(
      id: id ?? this.id,
      amountInJpy: amountInJpy ?? this.amountInJpy,
      rawText: rawText ?? this.rawText,
      boundingBox: boundingBox ?? this.boundingBox,
      confidence: confidence ?? this.confidence,
      taxType: taxType ?? this.taxType,
    );
  }

  @override
  String toString() =>
      'DetectedPrice(¥$amountInJpy, ${taxType.name}, conf=${confidence.toStringAsFixed(2)})';
}
