// Google Maps'e derin bağlantı yardımcıları.
//
// Neden ayrı bir modül: place_detail_sheet, day_map_screen, reward_map_screen
// ve viewer drawer aynı davranışı ister — iOS'ta önce `comgooglemaps://` scheme
// (Google Maps app varsa doğrudan onu açar), sonra `https://www.google.com/maps`
// web fallback (Google Maps app yoksa Safari/Chrome üzerinden Google Maps
// web'i açar). Android'de `https://` linki Google Maps app'e intent-filter
// üzerinden düşer; ek şeye gerek yok.
//
// Fonksiyonlar:
//   - openGoogleMapsPoint(lat, lng, label?) → tek nokta arama
//   - openGoogleMapsRoute(waypoints) → çoklu waypoint (dir?api=1) rota
//
// Google Maps `dir` URL'i **en fazla 9 waypoint** destekler (origin + max 9
// ara nokta + destination). Aşılırsa `openGoogleMapsRoute` listeyi otomatik
// ilk 9 ara noktaya trim eder ve `truncated=true` döner — çağıran isterse
// kullanıcıya bildirim gösterir.

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Google Maps'te tek bir noktayı aç. Label opsiyonel — Google Maps arama
/// çubuğunda görünsün diye eklenir; koordinat yine önceliklidir.
Future<bool> openGoogleMapsPoint({
  required double lat,
  required double lng,
  String? label,
}) async {
  final labelPart = (label != null && label.trim().isNotEmpty)
      ? '&query_place_id=&query=${Uri.encodeQueryComponent(label.trim())}'
      : '';
  // iOS deep link scheme — Google Maps app varsa doğrudan açar.
  final appUri = Uri.parse(
    'comgooglemaps://?q=$lat,$lng${label != null ? '($label)' : ''}',
  );
  final webUri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=$lat,$lng$labelPart',
  );
  return _launchWithFallback(appUri: appUri, webUri: webUri);
}

/// Sonuç: Google Maps `dir` URL'i açıldı mı + waypoint sayısı kesilmiş mi.
class GoogleMapsRouteResult {
  const GoogleMapsRouteResult({required this.launched, required this.truncated});
  final bool launched;
  final bool truncated;
}

/// Çoklu waypoint rota — Google Maps `dir` URL'i ile açar. Sıra korunur;
/// ilk nokta origin, son nokta destination, ortadakiler waypoints.
///
/// Google Maps sınırı: en fazla 9 ara nokta (waypoints). Liste
/// [1 origin, ≤9 waypoints, 1 destination] = **en fazla 11 nokta**. Fazlası
/// gelirse ilk 9 ara nokta alınır; kalanlar atılır ve `truncated=true`.
///
/// Boş veya tek noktalı liste geçersiz → `openGoogleMapsPoint` kullanın.
Future<GoogleMapsRouteResult> openGoogleMapsRoute({
  required List<({double lat, double lng, String? label})> points,
  String travelMode = 'transit',
}) async {
  if (points.length < 2) {
    return const GoogleMapsRouteResult(launched: false, truncated: false);
  }
  final origin = points.first;
  final destination = points.last;
  var middle = points.sublist(1, points.length - 1);
  final truncated = middle.length > 9;
  if (truncated) middle = middle.sublist(0, 9);

  // Yardımcı — record destructuring için mini map.
  String point({required double lat, required double lng}) => '$lat,$lng';

  final originStr = point(lat: origin.lat, lng: origin.lng);
  final destStr = point(lat: destination.lat, lng: destination.lng);
  final waypointsStr = middle
      .map((p) => point(lat: p.lat, lng: p.lng))
      .join('|');

  final params = <String, String>{
    'api': '1',
    'origin': originStr,
    'destination': destStr,
    if (waypointsStr.isNotEmpty) 'waypoints': waypointsStr,
    'travelmode': travelMode,
  };
  final query = params.entries
      .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');

  // iOS scheme — comgooglemaps://?saddr=...&daddr=...&waypoints=... (farklı
  // param adları; iyi haber Google Maps app hem `comgooglemaps` hem `https`
  // URL'ini yorumlar → https ile go).
  final webUri = Uri.parse('https://www.google.com/maps/dir/?$query');
  final appUri = Uri.parse(
    'comgooglemaps://?saddr=$originStr&daddr=$destStr'
    '${waypointsStr.isNotEmpty ? '&waypoints=$waypointsStr' : ''}'
    '&directionsmode=$travelMode',
  );
  final ok = await _launchWithFallback(appUri: appUri, webUri: webUri);
  return GoogleMapsRouteResult(launched: ok, truncated: truncated);
}

/// Önce iOS Google Maps app scheme'ini dener; başarısız olursa web URL'i
/// açar. Android'de `canLaunchUrl(comgooglemaps://)` false döner ve
/// otomatik web fallback devreye girer — Android'de web URL zaten Google
/// Maps app'e intent-filter üzerinden düşer.
Future<bool> _launchWithFallback({
  required Uri appUri,
  required Uri webUri,
}) async {
  try {
    if (await canLaunchUrl(appUri)) {
      final ok = await launchUrl(appUri, mode: LaunchMode.externalApplication);
      if (ok) return true;
    }
  } catch (_) {
    // canLaunchUrl bazı platformlarda MissingPluginException fırlatabilir
    // (ör. bazı test ortamları) — sessizce web fallback'e düş.
  }
  try {
    final ok = await launchUrl(webUri, mode: LaunchMode.externalApplication);
    if (ok) return true;
  } catch (_) {}
  // Son çare: URL'i panoya kopyala; çağıran SnackBar ile bildirim verebilir.
  await Clipboard.setData(ClipboardData(text: webUri.toString()));
  return false;
}
