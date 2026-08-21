import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/domain/weather_route_order.dart';

void main() {
  test('yağmurda kapalı alanları açık hava duraklarından önce önerir', () {
    final items = [
      TimelineItem(id: 'park', title: 'Ueno Parkı'),
      TimelineItem(id: 'museum', title: 'Tokyo Ulusal Müzesi'),
      TimelineItem(
        id: 'meal',
        title: 'Ramen restoranı',
        kind: TimelineItemKind.meal,
      ),
      TimelineItem(id: 'garden', title: 'Shinjuku Gyoen Bahçesi'),
    ];

    expect(
      weatherPreferredActivityOrder(items),
      ['museum', 'meal', 'park', 'garden'],
    );
  });

  test('kapalı ve açık alan karışımı yoksa mevcut sırayı korur', () {
    final items = [
      TimelineItem(id: 'a', title: 'Serbest zaman'),
      TimelineItem(id: 'b', title: 'Şehir merkezi'),
    ];

    expect(weatherPreferredActivityOrder(items), ['a', 'b']);
  });

  test('katalog placeId kategorisini sınıflandırmada kullanır', () {
    final items = [
      TimelineItem(id: 'out', title: 'Gezi', placeId: 'tk-ueno'),
      TimelineItem(id: 'in', title: 'Gezi', placeId: 'tk-teamlab'),
    ];

    expect(weatherPreferredActivityOrder(items), ['in', 'out']);
  });
}
