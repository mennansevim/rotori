// Bir güne ait konaklamayı ve o konaklamanın koordinatını çözer.
//
// **Neden gerekli:** Gün rotası haritası yalnızca gezilecek durakları
// gösteriyordu. Ama kullanıcı güne oteliden başlıyor — "bugün nereden yola
// çıkıyorum, ilk durak ne kadar uzakta" sorusunun cevabı haritada yoktu.
//
// [HotelStay] modelinde lat/lng ALANI YOK (bkz. types.dart). Koordinat bu
// yüzden sırayla şu kaynaklardan çözülür:
//   1. `mapsUrl` içindeki koordinat (kullanıcı Google Maps linki yapıştırdıysa
//      en kesin kaynak),
//   2. otel adı/adresi küratörlü şehir noktalarıyla eşleşiyorsa o nokta,
//   3. hiçbiri yoksa null — çağıran otel pinini GÖSTERMEZ. Şehir merkezine
//      düşmek, oteli yanlış bir yerde göstermekten daha kötüdür: kullanıcı
//      sabah oraya yürümeye kalkar.

import 'geofence.dart' show LatLng;
import 'place_coords.dart';
import 'types.dart';

/// [ymd] (YYYY-MM-DD) tarihinde kalınan otel.
///
/// Öncelik, o gecenin gerçekten geçirildiği konaklamadır: `checkIn <= tarih <
/// checkOut`. Hiçbiri uymazsa çıkış GÜNÜ olan konaklama döner — o sabah da
/// yola otelden çıkılır.
HotelStay? hotelForDate(List<HotelStay> hotels, String ymd) {
  if (hotels.isEmpty || ymd.isEmpty) return null;
  final date = DateTime.tryParse(ymd);
  if (date == null) return null;
  final day = DateTime(date.year, date.month, date.day);

  HotelStay? checkoutDayMatch;
  for (final h in hotels) {
    final ci = DateTime.tryParse(h.checkIn);
    final co = DateTime.tryParse(h.checkOut);
    if (ci == null || co == null) continue;
    final inDay = DateTime(ci.year, ci.month, ci.day);
    final outDay = DateTime(co.year, co.month, co.day);

    if (!day.isBefore(inDay) && day.isBefore(outDay)) return h;
    if (day == outDay) checkoutDayMatch ??= h;
  }
  return checkoutDayMatch;
}

/// Otelin haritada gösterilebilir koordinatı. Çözülemezse null.
LatLng? hotelCoords(HotelStay hotel) {
  final fromUrl = latLngFromMapsUrl(hotel.mapsUrl);
  if (fromUrl != null) return fromUrl;

  // Küratörlü nokta eşleşmesi — otel adı bilinen bir yer adı taşıyorsa
  // (ör. "Shinjuku Washington Hotel") en azından doğru semte düşer.
  for (final query in [hotel.name, hotel.address]) {
    if (query.trim().isEmpty) continue;
    final match = resolvePlaceCoords(query, cityKey: hotel.city);
    if (match != null) return LatLng(match.lat, match.lng);
  }
  return null;
}

/// Google Maps bağlantısından koordinat çıkarır.
///
/// Desteklenen biçimler (Maps'in paylaş/kopyala çıktılarının hepsi):
///   - `.../@35.6812,139.7671,17z`
///   - `?q=35.6812,139.7671` · `?ll=...` · `?destination=...` · `?daddr=...`
///   - `...!3d35.6812!4d139.7671`
///   - düz `35.6812,139.7671`
///
/// Kısaltılmış `maps.app.goo.gl` linkleri koordinat TAŞIMAZ; çözmek için ağ
/// isteği gerekir — bu katman çevrimdışı olduğundan null döner.
LatLng? latLngFromMapsUrl(String? url) {
  final raw = url?.trim();
  if (raw == null || raw.isEmpty) return null;

  final patterns = <RegExp>[
    RegExp(r'!3d(-?\d{1,3}\.\d+)!4d(-?\d{1,3}\.\d+)'),
    RegExp(r'@(-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)'),
    RegExp(
      r'(?:[?&](?:q|ll|sll|daddr|destination|center)=)(-?\d{1,3}\.\d+),\s*(-?\d{1,3}\.\d+)',
    ),
    RegExp(r'^(-?\d{1,3}\.\d+),\s*(-?\d{1,3}\.\d+)$'),
  ];

  for (final re in patterns) {
    final m = re.firstMatch(raw);
    if (m == null) continue;
    final lat = double.tryParse(m.group(1)!);
    final lng = double.tryParse(m.group(2)!);
    if (lat == null || lng == null) continue;
    if (lat.abs() > 90 || lng.abs() > 180) continue;
    return LatLng(lat, lng);
  }
  return null;
}
