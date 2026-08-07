import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/features/live_currency_scanner/domain/detected_price.dart';
import 'package:japan_trip/features/live_currency_scanner/domain/japanese_price_tax_type.dart';
import 'package:japan_trip/features/live_currency_scanner/domain/tracked_price.dart';
import 'package:japan_trip/features/live_currency_scanner/infrastructure/ocr/on_device_text_recognizer.dart';
import 'package:japan_trip/features/live_currency_scanner/infrastructure/parsing/product_query_candidate_resolver.dart';

void main() {
  const resolver = ProductQueryCandidateResolver();

  test('elektronik ürün satırı ve fiyat iziyle aday üretir', () {
    const trackBox = Rect.fromLTWH(120, 520, 160, 56);
    final track = _track(
      box: trackBox,
      amountInJpy: 154800,
      confidence: 0.93,
      seenCount: 4,
    );

    const frame = RecognizedFrame(
      lines: [
        RecognizedTextLine(
          text: 'Apple iPhone 15 Pro 256GB',
          boundingBox: Rect.fromLTWH(110, 450, 290, 44),
        ),
        RecognizedTextLine(
          text: '税込 ¥154,800',
          boundingBox: Rect.fromLTWH(120, 520, 180, 42),
        ),
      ],
      imageSize: Size(1080, 1920),
      rotationDegrees: 0,
    );

    final candidate = resolver.resolve(frame: frame, tracks: [track]);

    expect(candidate, isNotNull);
    expect(candidate!.title, contains('iPhone'));
    expect(candidate.amountInJpy, 154800);
    expect(candidate.confidence, greaterThan(0.6));
    expect(candidate.searchHints, isNotEmpty);
    expect(candidate.boundingBox.left, lessThanOrEqualTo(trackBox.left));
    expect(candidate.boundingBox.bottom, greaterThanOrEqualTo(trackBox.bottom));
  });

  test('yalnız sayısal OCR satırlarında aday üretmez', () {
    final track = _track(
      box: const Rect.fromLTWH(100, 480, 150, 50),
      amountInJpy: 99800,
      confidence: 0.88,
      seenCount: 3,
    );

    const frame = RecognizedFrame(
      lines: [
        RecognizedTextLine(
          text: '¥99,800',
          boundingBox: Rect.fromLTWH(110, 490, 140, 38),
        ),
        RecognizedTextLine(
          text: '税込',
          boundingBox: Rect.fromLTWH(92, 450, 64, 30),
        ),
      ],
      imageSize: Size(1080, 1920),
      rotationDegrees: 0,
    );

    final candidate = resolver.resolve(frame: frame, tracks: [track]);

    expect(candidate, isNull);
  });

  test('anahtar/model sinyali zayıf ve uzak satırları eler', () {
    final track = _track(
      box: const Rect.fromLTWH(120, 1400, 150, 48),
      amountInJpy: 76000,
      confidence: 0.9,
      seenCount: 4,
    );

    const frame = RecognizedFrame(
      lines: [
        RecognizedTextLine(
          text: 'season campaign limited',
          boundingBox: Rect.fromLTWH(760, 180, 220, 34),
        ),
      ],
      imageSize: Size(1080, 1920),
      rotationDegrees: 0,
    );

    final candidate = resolver.resolve(frame: frame, tracks: [track]);

    expect(candidate, isNull);
  });
}

TrackedPrice _track({
  required Rect box,
  required int amountInJpy,
  required double confidence,
  required int seenCount,
}) {
  return TrackedPrice(
    price: DetectedPrice(
      id: 'track-$amountInJpy',
      amountInJpy: amountInJpy,
      rawText: '¥$amountInJpy',
      boundingBox: box,
      confidence: confidence,
      taxType: JapanesePriceTaxType.taxIncluded,
    ),
    smoothedBox: box,
    seenCount: seenCount,
    firstSeenAtMs: 100,
    lastSeenAtMs: 160,
  );
}
