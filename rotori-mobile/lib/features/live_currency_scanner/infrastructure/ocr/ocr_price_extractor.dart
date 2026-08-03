import 'dart:ui' show Rect;

import '../../domain/detected_price.dart';
import '../../domain/japanese_price_tax_type.dart';
import '../../domain/scanner_tuning.dart';
import '../parsing/japanese_price_parser.dart';
import 'on_device_text_recognizer.dart';

/// OCR sonucunu ([RecognizedFrame]) parser + kutu bilgisiyle birleştirip
/// [DetectedPrice] listesine dönüştürür. Saf Dart, birim testlenebilir.
///
/// Aynı ürüne ait 税込/税抜 çifti, kutu yakınlığı + oran ile eşleştirilip ana
/// gösterimde vergi dahil olan bırakılır.
class OcrPriceExtractor {
  const OcrPriceExtractor({
    this.parser = const JapanesePriceParser(),
  });

  final JapanesePriceParser parser;

  List<DetectedPrice> extract(RecognizedFrame frame) {
    final raw = <DetectedPrice>[];
    for (final line in frame.lines) {
      final candidates = parser.parseLine(line.text);
      for (var i = 0; i < candidates.length; i++) {
        final c = candidates[i];
        raw.add(DetectedPrice(
          id: _stableId(line.boundingBox, c.amountInJpy, i),
          amountInJpy: c.amountInJpy,
          rawText: c.rawText,
          boundingBox: line.boundingBox,
          confidence: c.confidence,
          taxType: c.taxType,
        ));
      }
    }
    return _resolveTaxPairsByBox(raw);
  }

  /// Kutu + tutar temelli deterministik kimlik (kararlı overlay eşleşmesi).
  String _stableId(Rect box, int amount, int index) {
    final cx = box.center.dx.round();
    final cy = box.center.dy.round();
    return 'p_${amount}_${cx}_${cy}_$index';
  }

  /// Kutu yakınlığındaki 税込/税抜 çiftinde vergi hariç olanı eler.
  List<DetectedPrice> _resolveTaxPairsByBox(List<DetectedPrice> prices) {
    if (prices.length < 2) return prices;
    final drop = <String>{};
    for (final inc in prices.where((p) => p.taxType.isIncluded)) {
      for (final exc in prices.where((p) => p.taxType.isExcluded)) {
        if (drop.contains(exc.id)) continue;
        final ratio = inc.amountInJpy / exc.amountInJpy;
        final ratioOk = ratio >= ScannerTuning.taxPairMinRatio &&
            ratio <= ScannerTuning.taxPairMaxRatio;
        if (ratioOk && _boxesNear(inc.boundingBox, exc.boundingBox)) {
          drop.add(exc.id);
        }
      }
    }
    if (drop.isEmpty) return prices;
    return prices.where((p) => !drop.contains(p.id)).toList();
  }

  bool _boxesNear(Rect a, Rect b) {
    final dy = (a.center.dy - b.center.dy).abs();
    final dx = (a.center.dx - b.center.dx).abs();
    final ref = (a.height + b.height) / 2;
    if (ref <= 0) return false;
    final maxGap = ref * ScannerTuning.taxPairProximityRatio;
    return dy <= maxGap && dx <= maxGap * 2;
  }

  /// Vergi dahil ana fiyat için, aynı ürünün vergi hariç eşdeğerini bulur
  /// (detay kartında her ikisini göstermek için). Bulunamazsa null.
  static JapanesePriceTaxType primaryTaxType(List<DetectedPrice> prices) {
    if (prices.any((p) => p.taxType.isIncluded)) {
      return JapanesePriceTaxType.taxIncluded;
    }
    return JapanesePriceTaxType.unknown;
  }
}
