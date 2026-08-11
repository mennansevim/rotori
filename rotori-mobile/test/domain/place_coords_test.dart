// place_coords.dart birim testleri — başlıktan koordinat çözümü ve gün
// duraklarının sıralı/koordinatlı listeye dönüşümü.

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/place_coords.dart';
import 'package:rotori/domain/types.dart';

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

    test('birleşik Shibuya başlığı gerçek Crossing noktasını bulur', () {
      final coords = resolvePlaceCoords(
        'Shibuya Sky & Crossing',
        cityKey: 'Tokyo',
      );
      expect(coords, isNotNull);
      expect(coords!.lat, closeTo(35.6595, 0.001));
      expect(coords.lng, closeTo(139.7005, 0.001));
    });

    test('birleşik Asakusa başlığı Skytree noktasını şehir merkezine düşürmez',
        () {
      final coords = resolvePlaceCoords(
        'Asakusa & Skytree',
        cityKey: 'Tokyo',
      );
      expect(coords, isNotNull);
      expect(coords!.lat, closeTo(35.7101, 0.001));
      expect(coords.lng, closeTo(139.8107, 0.001));
    });

    test('Tokyo Disneyland offline POI koordinatını çözer', () {
      final coords = resolvePlaceCoords(
        'Tokyo Disneyland',
        cityKey: 'Tokyo',
      );

      expect(coords, isNotNull);
      expect(coords!.lat, closeTo(35.6329, 0.001));
      expect(coords.lng, closeTo(139.8804, 0.001));
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

    test('fallback verilince çözülemeyen öğeler de nokta olur (hepsi görünür)',
        () {
      final day = DayPlan(
        dayNumber: 1,
        date: '2026-05-13',
        theme: 'Test',
        items: [
          TimelineItem(id: 'a', title: 'Tokyo Skytree'),
          TimelineItem(id: 'b', title: 'Zxqw Uydurma Yer 1'),
          TimelineItem(id: 'c', title: 'Zxqw Uydurma Yer 2'),
          TimelineItem(id: 'd', title: 'Zxqw Uydurma Yer 3'),
          TimelineItem(id: 'e', title: 'Zxqw Uydurma Yer 4'),
        ],
      );
      final stops = resolveDayStops(
        day,
        cityKey: 'Tokyo',
        fallbackLat: 35.68,
        fallbackLng: 139.76,
      );
      // Tüm 5 öğe nokta olmalı.
      expect(stops.length, 5);
      // Sıra 1..5 korunur.
      expect(stops.map((s) => s.order).toList(), [1, 2, 3, 4, 5]);
      // Fallback noktaları şehir merkezi civarında ama üst üste değil (farklı).
      final fallbackPoints = stops.skip(1).toList();
      final uniqueCoords =
          fallbackPoints.map((s) => '${s.lat},${s.lng}').toSet();
      expect(uniqueCoords.length, fallbackPoints.length,
          reason: 'fallback noktaları üst üste binmemeli');
      for (final s in fallbackPoints) {
        expect(s.lat, closeTo(35.68, 0.05));
        expect(s.lng, closeTo(139.76, 0.05));
      }
    });

    test('fallback verilmezse çözülemeyen öğeler eskisi gibi atlanır', () {
      final day = DayPlan(
        dayNumber: 1,
        date: '2026-05-13',
        theme: 'Test',
        items: [
          TimelineItem(id: 'a', title: 'Tokyo Skytree'),
          TimelineItem(id: 'b', title: 'Zxqw Uydurma Yer'),
        ],
      );
      final stops = resolveDayStops(day, cityKey: 'Tokyo');
      expect(stops.length, 1);
    });
  });
}
