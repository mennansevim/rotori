import 'city_places.dart';
import 'types.dart';

enum WeatherExposure { indoor, neutral, outdoor }

/// Yağışlı günlerde rota motoruna verilecek semantik sıra ipucunu üretir.
///
/// Bu bir hard constraint değildir: saatli/kilitli duraklar yerinde kalır,
/// rota motoru ulaşım ve açılış saatlerini yine bağımsız doğrular.
List<String> weatherPreferredActivityOrder(List<TimelineItem> items) {
  final classified = [
    for (var index = 0; index < items.length; index++)
      (
        item: items[index],
        index: index,
        exposure: inferWeatherExposure(items[index]),
      ),
  ];
  final hasIndoor =
      classified.any((entry) => entry.exposure == WeatherExposure.indoor);
  final hasOutdoor =
      classified.any((entry) => entry.exposure == WeatherExposure.outdoor);
  if (!hasIndoor || !hasOutdoor) {
    return items.map((item) => item.id).toList(growable: false);
  }

  final sorted = [...classified]..sort((a, b) {
      final byExposure = _priority(a.exposure).compareTo(_priority(b.exposure));
      return byExposure != 0 ? byExposure : a.index.compareTo(b.index);
    });
  return sorted.map((entry) => entry.item.id).toList(growable: false);
}

WeatherExposure inferWeatherExposure(TimelineItem item) {
  final catalogCategory = _catalogCategory(item.placeId);
  final haystack = [
    item.title,
    item.description,
    item.tips,
    catalogCategory,
  ].whereType<String>().join(' ').toLowerCase();

  const outdoorTokens = [
    'açık hava',
    'acik hava',
    'open air',
    'park',
    'bahçe',
    'bahce',
    'garden',
    'doğa',
    'doga',
    'nature',
    'dağ',
    'dag',
    'mount',
    'plaj',
    'beach',
    'göl',
    'gol',
    'lake',
    'ada',
    'island',
    'crossing',
    'caddesi',
    'street',
    'sokak',
    'tapınak',
    'tapinak',
    'temple',
    'shrine',
    'bambu',
    'bamboo',
  ];
  if (outdoorTokens.any(haystack.contains)) return WeatherExposure.outdoor;

  const indoorTokens = [
    'müze',
    'muze',
    'museum',
    'akvaryum',
    'aquarium',
    'galeri',
    'gallery',
    'sanat merkezi',
    'art center',
    'alışveriş',
    'alisveris',
    'shopping',
    'mall',
    'çarşı',
    'carsi',
    'kapalı pazar',
    'indoor market',
    'teamlab',
    'akvaryum',
    'aquarium',
    'onsen',
    'kaplıca',
    'kaplica',
    'restoran',
    'restaurant',
    'ramen',
    'kafe',
    'cafe',
  ];
  if (indoorTokens.any(haystack.contains)) return WeatherExposure.indoor;

  if (item.kind == TimelineItemKind.meal ||
      item.kind == TimelineItemKind.hotel) {
    return WeatherExposure.indoor;
  }
  return WeatherExposure.neutral;
}

int _priority(WeatherExposure exposure) => switch (exposure) {
      WeatherExposure.indoor => 0,
      WeatherExposure.neutral => 1,
      WeatherExposure.outdoor => 2,
    };

String? _catalogCategory(String? placeId) {
  if (placeId == null || placeId.isEmpty) return null;
  for (final city in kCityData) {
    for (final place in city.places) {
      if (place.id == placeId) {
        return '${place.category.tr} ${place.category.en}';
      }
    }
  }
  return null;
}
