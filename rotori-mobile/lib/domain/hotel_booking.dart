// Otel/rezervasyon saf yardımcıları — UI'dan bağımsız.
//
// Kaynak: features/planner/steps/hotels_step.dart (wizard sökülürken buraya
// taşındı; testleri test/domain/hotel_booking_test.dart altında sürüyor).

import 'types.dart';

/// parseBookingUrl çıktısı (React ParsedBooking karşılığı).
class ParsedBooking {
  const ParsedBooking({
    this.name,
    this.city,
    this.checkIn,
    this.checkOut,
    this.mapsUrl,
    required this.source,
  });
  final String? name;
  final String? city;
  final String? checkIn;
  final String? checkOut;
  final String? mapsUrl;

  /// 'booking' | 'hostelworld' | 'booking-mytrips' | 'unknown'
  final String source;
}

String _titleCase(String slug) => slug
    .replaceAll(RegExp(r'[-_]+'), ' ')
    .split(' ')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

/// HotelsStep.tsx parseBookingUrl birebir.
ParsedBooking? parseBookingUrl(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final Uri url;
  try {
    url = Uri.parse(text);
    if (!url.hasScheme || url.host.isEmpty) return null;
  } catch (_) {
    return null;
  }
  final host = url.host.toLowerCase();
  final checkIn = url.queryParameters['checkin'];
  final checkOut = url.queryParameters['checkout'];

  if (host.contains('booking.com')) {
    final path = url.path.toLowerCase();
    if (path.contains('mytrips') ||
        path.contains('myreservations') ||
        path.contains('myaccount')) {
      return const ParsedBooking(source: 'booking-mytrips');
    }
    final m = RegExp(r'/hotel/([a-z]{2})/([^./]+)', caseSensitive: false)
        .firstMatch(url.path);
    if (m == null) {
      return ParsedBooking(
          source: 'booking', checkIn: checkIn, checkOut: checkOut);
    }
    return ParsedBooking(
      source: 'booking',
      name: _titleCase(m.group(2)!),
      checkIn: checkIn,
      checkOut: checkOut,
    );
  }

  if (host.contains('hostelworld.com')) {
    final segs = url.pathSegments.where((s) => s.isNotEmpty).toList();
    final idx = segs.indexWhere((s) => RegExp(r'hosteldetails', caseSensitive: false).hasMatch(s));
    final nameSlug = idx >= 0
        ? (idx + 1 < segs.length ? segs[idx + 1] : null)
        : (segs.length >= 3 ? segs[segs.length - 3] : null);
    final citySlug = idx >= 0
        ? (idx + 2 < segs.length ? segs[idx + 2] : null)
        : (segs.length >= 2 ? segs[segs.length - 2] : null);
    return ParsedBooking(
      source: 'hostelworld',
      name: nameSlug != null ? _titleCase(nameSlug) : null,
      city: citySlug != null ? _titleCase(citySlug) : null,
      checkIn: checkIn,
      checkOut: checkOut,
    );
  }

  return ParsedBooking(source: 'unknown', checkIn: checkIn, checkOut: checkOut);
}

/// HotelsStep.tsx hotelsComplete — otel zorunlu değil: kullanıcı otel
/// eklemek yerine yalnızca konaklanacak bölge yazmışsa da tamamlanmış sayılır.
/// (Taksi/rehber semtin adını bilirse yeter.)
bool hotelsComplete(Trip trip) {
  if (trip.preferences.destinations.isEmpty) return false;
  final stayArea = trip.preferences.stayArea?.trim() ?? '';
  if (stayArea.isNotEmpty) return true;
  if (trip.hotels.isEmpty) return false;
  return trip.hotels.every((h) =>
      h.city.trim().isNotEmpty &&
      h.name.trim().isNotEmpty &&
      h.address.trim().isNotEmpty &&
      h.checkIn.isNotEmpty &&
      h.checkOut.isNotEmpty);
}
