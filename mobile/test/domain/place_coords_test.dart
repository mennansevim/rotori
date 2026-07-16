// place_coords.dart birim testleri — başlıktan koordinat çözümü ve gün
// duraklarının sıralı/koordinatlı listeye dönüşümü.

import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/place_coords.dart';
import 'package:japan_trip/domain/types.dart';

void main() {
  group('resolvePlaceCoords', () {
    test('bilinen yer (Tokyo Skytree) koordinat döndürür', () {
      final coords = resolvePlaceCoords('Tokyo Skytree');
      expect(coords, isNotNull);
      expect(coords!.lat, closeTo(35.7101, 0.001));
      expect(coords.lng, closeTo(139.8107, 0.001));
    });

    test('emoji önekli başlık (🗼 Tokyo Skytree) yine eşleşir', () {
      final coords = resolvePlaceCoords('🗼 Tokyo Skytree');
      expect(coords, isNotNull);
      expect(coords!.lat, closeTo(35.7101, 0.001));
    });

    test('cityKey tercih edilen şehri önceler', () {
      final coords = resolvePlaceCoords('Osaka Kalesi', cityKey: 'Osaka');
      expect(coords, isNotNull);
      expect(coords!.lat, closeTo(34.6873, 0.001));
    });

    test('anlamsız başlık null döndürür', () {
      expect(resolvePlaceCoords('Zxqw Uydurma Yer 12345'), isNull);
      expect(resolvePlaceCoords(''), isNull);
    });
  });

  group('resolveDayStops', () {
    test('2 bilinen + 1 bilinmeyen öğe → 2 durak, sıralı', () {
      final day = DayPlan(
        dayNumber: 1,
        date: '2026-05-13',
        theme: 'Test',
        items: [
          TimelineItem(id: 'a', title: 'Tokyo Skytree'),
          TimelineItem(id: 'b', title: 'Zxqw Uydurma Yer'),
          TimelineItem(id: 'c', title: 'Shibuya Crossing'),
        ],
      );

      final stops = resolveDayStops(day, cityKey: 'Tokyo');
      expect(stops.length, 2);
      // Sıra gün öğesi sırasıyla, 1-index numaralı.
      expect(stops[0].item.title, 'Tokyo Skytree');
      expect(stops[0].order, 1);
      expect(stops[1].item.title, 'Shibuya Crossing');
      expect(stops[1].order, 2);
    });

    test('öğenin kendi lat/lng değeri varsa o kullanılır', () {
      final day = DayPlan(
        dayNumber: 1,
        date: '2026-05-13',
        theme: 'Test',
        items: [
          TimelineItem(id: 'x', title: 'Özel Nokta', lat: 12.34, lng: 56.78),
        ],
      );
      final stops = resolveDayStops(day);
      expect(stops.length, 1);
      expect(stops.first.lat, 12.34);
      expect(stops.first.lng, 56.78);
    });
  });
}
