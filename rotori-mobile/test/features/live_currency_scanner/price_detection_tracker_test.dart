import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/features/live_currency_scanner/domain/detected_price.dart';
import 'package:japan_trip/features/live_currency_scanner/domain/japanese_price_tax_type.dart';
import 'package:japan_trip/features/live_currency_scanner/infrastructure/tracking/price_detection_tracker.dart';

DetectedPrice _price(int amount, Rect box, {double conf = 0.9}) =>
    DetectedPrice(
      id: '$amount@${box.left}',
      amountInJpy: amount,
      rawText: '¥$amount',
      boundingBox: box,
      confidence: conf,
      taxType: JapanesePriceTaxType.unknown,
    );

void main() {
  test('fiyat ilk karede gösterilmez, ikinci yakın karede görünür', () {
    final tracker = PriceDetectionTracker();
    const box = Rect.fromLTWH(100, 100, 80, 30);

    var visible = tracker.update([_price(1000, box)], 0);
    expect(visible, isEmpty, reason: 'tek görülmede gösterme');

    visible = tracker.update([_price(1000, box.translate(2, 1))], 100);
    expect(visible, hasLength(1));
    expect(visible.first.price.amountInJpy, 1000);
  });

  test('aynı tutarlı iki farklı ürün ayrı iz olarak kalır', () {
    final tracker = PriceDetectionTracker();
    const a = Rect.fromLTWH(50, 50, 60, 24);
    const b = Rect.fromLTWH(400, 600, 60, 24);
    tracker.update([_price(500, a), _price(500, b)], 0);
    final visible = tracker.update([_price(500, a), _price(500, b)], 100);
    expect(visible, hasLength(2));
  });

  test('detection görülmeyince stale süre sonunda kaldırılır', () {
    final tracker = PriceDetectionTracker();
    const box = Rect.fromLTWH(10, 10, 40, 20);
    tracker.update([_price(300, box)], 0);
    tracker.update([_price(300, box)], 100);
    // 800ms sonra boş kare → iz bayatlar (staleTrackMs=700).
    final visible = tracker.update([], 900);
    expect(visible, isEmpty);
  });

  test('kutu exponential smoothing ile yumuşatılır', () {
    final tracker = PriceDetectionTracker();
    const box1 = Rect.fromLTWH(100, 100, 80, 30);
    const box2 = Rect.fromLTWH(120, 100, 80, 30); // 20px sağa (IoU eşleşir)
    tracker.update([_price(1000, box1)], 0);
    final visible = tracker.update([_price(1000, box2)], 100);
    // 100*0.75 + 120*0.25 = 105 → tam sıçramayı takip etmez
    expect(visible.first.smoothedBox.left, closeTo(105, 0.001));
  });

  test('IoU eşiğini geçen kutu aynı ize eşleşir (seenCount artar)', () {
    final tracker = PriceDetectionTracker();
    const box = Rect.fromLTWH(0, 0, 100, 100);
    tracker.update([_price(700, box)], 0);
    tracker.update([_price(700, box.translate(5, 5))], 100);
    final tracks = tracker.allTracks;
    expect(tracks, hasLength(1));
    expect(tracks.first.seenCount, 2);
  });
}
