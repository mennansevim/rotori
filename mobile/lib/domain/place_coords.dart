// Gün planındaki durakların koordinatlarını çözer — çoğu üretilmiş
// TimelineItem'da lat/lng NULL olduğundan, başlık küratörlü şehir noktalarıyla
// (city_places.dart) eşleştirilerek gerçek lat/lng bulunur.
//
// Kullanım:
//   - resolvePlaceCoords(title, cityKey: 'tokyo') → başlığa karşılık gelen nokta
//   - resolveDayStops(day, cityKey: ...) → gün öğelerini sırayla, koordinatlı
//     ResolvedStop listesine çevirir (numaralandırma için 1-index order).
//   - resolveTripStops(trip) → günlere göre gruplanmış duraklar.

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
  });

  final TimelineItem item;
  final double lat;
  final double lng;

  /// Gün içindeki sıra (1-index) — harita pininin numarası.
  final int order;
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
  return t == n || t.contains(n) || n.contains(t);
}

/// Başlığı küratörlü şehir noktalarıyla eşleştirip lat/lng döndürür.
/// [cityKey] verilirse o şehrin noktaları önce denenir; bulunamazsa tüm
/// şehirler taranır. Eşleşme yoksa null.
({double lat, double lng})? resolvePlaceCoords(
  String title, {
  String? cityKey,
}) {
  final t = normalizeTitle(title);
  if (t.isEmpty) return null;

  final preferred = cityDataForKey(cityKey);
  if (preferred != null) {
    for (final p in preferred.places) {
      if (_nameMatches(p, t)) return (lat: p.lat, lng: p.lng);
    }
  }
  for (final c in kCityData) {
    if (identical(c, preferred)) continue;
    for (final p in c.places) {
      if (_nameMatches(p, t)) return (lat: p.lat, lng: p.lng);
    }
  }
  return null;
}

/// Bir günün öğelerini koordinatlı duraklara çevirir. Öğenin kendi lat/lng'si
/// varsa o kullanılır; yoksa başlık eşleşmesinden çözülür. Koordinatı
/// çözülemeyen öğeler atlanır. Sıra gün öğesi sırasıyla korunur (1-index).
List<ResolvedStop> resolveDayStops(DayPlan day, {String? cityKey}) {
  final out = <ResolvedStop>[];
  var order = 0;
  for (final item in day.items) {
    double? lat = item.lat;
    double? lng = item.lng;
    if (lat == null || lng == null) {
      final resolved = resolvePlaceCoords(item.title, cityKey: cityKey);
      if (resolved == null) continue;
      lat = resolved.lat;
      lng = resolved.lng;
    }
    order += 1;
    out.add(ResolvedStop(item: item, lat: lat, lng: lng, order: order));
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
