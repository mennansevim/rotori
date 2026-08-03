import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/features/live_currency_scanner/infrastructure/ocr/ocr_price_extractor.dart';
import 'package:japan_trip/features/live_currency_scanner/infrastructure/ocr/on_device_text_recognizer.dart';

RecognizedFrame _frame(List<(String, Rect)> lines) => RecognizedFrame(
      lines: [
        for (final (text, box) in lines)
          RecognizedTextLine(text: text, boundingBox: box),
      ],
      imageSize: const Size(1000, 1000),
      rotationDegrees: 0,
    );

void main() {
  const extractor = OcrPriceExtractor();

  test('satır kutusu fiyata iliştirilir', () {
    final out = extractor.extract(_frame([
      ('¥12,800', const Rect.fromLTWH(100, 200, 120, 40)),
    ]));
    expect(out, hasLength(1));
    expect(out.first.amountInJpy, 12800);
    expect(out.first.boundingBox, const Rect.fromLTWH(100, 200, 120, 40));
  });

  test('yakın 税込/税抜 çiftinde vergi hariç elenir', () {
    final out = extractor.extract(_frame([
      ('税抜 ¥10,000', const Rect.fromLTWH(100, 200, 120, 30)),
      ('税込 ¥11,000', const Rect.fromLTWH(100, 235, 120, 30)),
    ]));
    final amounts = out.map((e) => e.amountInJpy).toList();
    expect(amounts, contains(11000));
    expect(amounts, isNot(contains(10000)));
  });

  test('uzak 税抜/税込 fiyatları ayrı kalır', () {
    final out = extractor.extract(_frame([
      ('税抜 ¥10,000', const Rect.fromLTWH(100, 100, 120, 30)),
      ('税込 ¥11,000', const Rect.fromLTWH(700, 900, 120, 30)),
    ]));
    final amounts = out.map((e) => e.amountInJpy).toSet();
    expect(amounts, containsAll(<int>[10000, 11000]));
  });

  test('fiyat olmayan satırlar atlanır', () {
    final out = extractor.extract(_frame([
      ('30%', const Rect.fromLTWH(0, 0, 40, 20)),
      ('2026年', const Rect.fromLTWH(0, 30, 60, 20)),
    ]));
    expect(out, isEmpty);
  });
}
