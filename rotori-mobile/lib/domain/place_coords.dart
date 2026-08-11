// Gün planındaki durakların koordinatlarını çözer — çoğu üretilmiş
// TimelineItem'da lat/lng NULL olduğundan, başlık küratörlü şehir noktalarıyla
// (city_places.dart) eşleştirilerek gerçek lat/lng bulunur.
//
// Kullanım:
//   - resolvePlaceCoords(title, cityKey: 'tokyo') → başlığa karşılık gelen nokta
//   - resolveDayStops(day, cityKey: ...) → gün öğelerini sırayla, koordinatlı
//     ResolvedStop listesine çevirir (numaralandırma için 1-index order).
//   - resolveTripStops(trip) → günlere göre gruplanmış duraklar.

import 'dart:math' as math;

import '../features/shared/ticket_support.dart' show normalizeTitle;
import 'city_places.dart';
import 'destination_profiles.dart' show getDestinationForDate;
import 'types.dart';

/// Bir günün haritada gösterilecek, koordinatı çözülmüş tek durağı.
class ResolvedStop {
  const ResolvedStop({
    required this.item,
    required this.lat,
    required this.lng,
    required this.order,
    this.place,
  });

  final TimelineItem item;
  final double lat;
  final double lng;

  /// Gün içindeki sıra (1-index) — harita pininin numarası.
  final int order;

  /// Başlığın eşleştiği küratörlü şehir noktası — varsa emoji/kategori gibi
  /// gösterim ipuçları buradan gelir. Öğenin kendi lat/lng'siyle çözülen ya da
  /// hiç eşleşmeyen duraklarda null.
  final CityPlace? place;
}

/// Gevşek bir şehir dizesini ('Tokyo', 'tokyo', 'Kyoto (ITM)') küratörlü
/// CityData'ya eşler: key/label/alias üzerinden (normalize edilmiş içerir).
CityData? cityDataForKey(String? cityKey) {
  if (cityKey == null) return null;
  final k = normalizeTitle(cityKey);
  if (k.isEmpty) return null;
  for (final c in kCityData) {
    if (normalizeTitle(c.key) == k || normalizeTitle(c.label) == k) return c;
  }
  // Alias veya kısmi içerme (ör. "Tokyo (HND)" → "tokyo").
  for (final c in kCityData) {
    if (c.aliases.any((a) => k.contains(normalizeTitle(a)))) return c;
    if (k.contains(normalizeTitle(c.label))) return c;
  }
  return null;
}

/// Bir noktanın adı [t] başlığıyla eşleşiyor mu?
/// Normalize edilmiş eşitlik veya iki yönlü içerme.
bool _nameMatches(CityPlace p, String t) {
  final n = normalizeTitle(p.name);
  if (n.isEmpty || t.isEmpty) return false;
  if (t == n || t.contains(n) || n.contains(t)) return true;

  // Üretilen gün başlıkları bazen iki deneyimi tek başlıkta birleştirir
  // ("Shibuya Sky & Crossing", "Asakusa & Skytree"). Tam alt-dize eşleşmesi
  // bu durumda gerçek POI'yi kaçırıp durağı şehir merkezine düşürüyordu.
  // Yalnız anlamlı yer kelimelerinin tamamı başlıkta varsa eşleştir; tek bir
  // genel şehir kelimesi üzerinden tahmin yapma.
  final placeTokens = _meaningfulPlaceTokens(n);
  if (placeTokens.isEmpty) return false;
  final titleTokens = normalizeTitle(t).split(RegExp(r'\s+')).toSet();
  return placeTokens.every(titleTokens.contains);
}

const _genericPlaceTokens = {
  'tokyo',
  'kyoto',
  'osaka',
  'hiroshima',
  'parkı',
  'park',
  'bahçesi',
  'garden',
};

Set<String> _meaningfulPlaceTokens(String value) {
  return value
      .split(RegExp(r'\s+'))
      .where(
          (token) => token.length >= 3 && !_genericPlaceTokens.contains(token))
      .toSet();
}

/// Başlığı küratörlü şehir noktalarıyla eşleştirip eşleşen noktayı döndürür.
/// [cityKey] verilirse o şehrin noktaları önce denenir; bulunamazsa tüm
/// şehirler taranır. Eşleşme yoksa null.
CityPlace? resolveCityPlace(String title, {String? cityKey}) {
  final t = normalizeTitle(title);
  if (t.isEmpty) return null;

  final preferred = cityDataForKey(cityKey);
  if (preferred != null) {
    for (final p in preferred.places) {
      if (_nameMatches(p, t)) return p;
    }
  }
  for (final c in kCityData) {
    if (identical(c, preferred)) continue;
    for (final p in c.places) {
      if (_nameMatches(p, t)) return p;
    }
  }
  return null;
}

/// Başlığı küratörlü şehir noktalarıyla eşleştirip lat/lng döndürür.
/// Eşleşme yoksa null. Bkz. [resolveCityPlace].
({double lat, double lng})? resolvePlaceCoords(
  String title, {
  String? cityKey,
}) {
  final p = resolveCityPlace(title, cityKey: cityKey);
  return p == null ? null : (lat: p.lat, lng: p.lng);
}

/// Bir günün öğelerini koordinatlı duraklara çevirir. Öğenin kendi lat/lng'si
/// varsa o kullanılır; yoksa başlık eşleşmesinden çözülür. Koordinatı
/// çözülemeyen öğeler için [fallbackLat]/[fallbackLng] verilmişse o noktanın
/// çevresine küçük, deterministik bir kayma ile yerleştirilir (üst üste
/// binmesin) — böylece günün TÜM durakları haritada nokta olarak görünür.
/// Fallback verilmezse çözülemeyen öğeler eskisi gibi atlanır.
List<ResolvedStop> resolveDayStops(
  DayPlan day, {
  String? cityKey,
  double? fallbackLat,
  double? fallbackLng,
}) {
  final out = <ResolvedStop>[];
  var order = 0;
  var unresolved = 0;
  for (final item in day.items) {
    double? lat = item.lat;
    double? lng = item.lng;
    // Emoji/kategori ipucu için başlık eşleşmesi her durumda denenir — öğenin
    // kendi koordinatı olsa bile küratörlü nokta gösterim bilgisi taşır.
    final matched = resolveCityPlace(item.title, cityKey: cityKey);
    if (lat == null || lng == null) {
      if (matched != null) {
        lat = matched.lat;
        lng = matched.lng;
      } else if (fallbackLat != null && fallbackLng != null) {
        // Şehir merkezi etrafında spiral bir kayma (~250-500m) ver: her
        // çözülemeyen öğe farklı bir açı/yarıçapta konumlanır.
        final angle = unresolved * 2.399963; // altın açı (rad)
        final radius = 0.0035 + unresolved * 0.0012;
        lat = fallbackLat + radius * math.cos(angle);
        lng = fallbackLng + radius * math.sin(angle);
        unresolved += 1;
      } else {
        continue;
      }
    }
    order += 1;
    out.add(
      ResolvedStop(
        item: item,
        lat: lat,
        lng: lng,
        order: order,
        place: matched,
      ),
    );
  }
  return out;
}

/// Trip'in tüm günlerini, gün numarasına göre koordinatlı duraklara çevirir.
/// Her gün için o güne denk gelen destinasyonun şehri cityKey olarak kullanılır.
Map<int, List<ResolvedStop>> resolveTripStops(Trip trip) {
  final dests = [...trip.preferences.destinations]
    ..sort((a, b) => a.order.compareTo(b.order));
  final out = <int, List<ResolvedStop>>{};
  for (final day in trip.days) {
    final dest = getDestinationForDate(dests, day.date);
    out[day.dayNumber] = resolveDayStops(day, cityKey: dest?.city);
  }
  return out;
}
