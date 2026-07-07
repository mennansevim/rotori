// packages/shared/src/geo/airports.ts birebir Dart portu.

class Airport {
  const Airport({
    required this.iata,
    required this.city,
    required this.countryCode,
    required this.countryName,
    required this.lat,
    required this.lng,
  });
  final String iata;
  final String city;
  final String countryCode;
  final String countryName;
  final double lat;
  final double lng;
}

const List<Airport> kAirports = [
  // Türkiye
  Airport(iata: 'IST', city: 'İstanbul', countryCode: 'TR', countryName: 'Türkiye', lat: 41.2753, lng: 28.7519),
  Airport(iata: 'SAW', city: 'İstanbul (Sabiha)', countryCode: 'TR', countryName: 'Türkiye', lat: 40.8986, lng: 29.3092),
  Airport(iata: 'ESB', city: 'Ankara', countryCode: 'TR', countryName: 'Türkiye', lat: 40.1281, lng: 32.9951),
  Airport(iata: 'ADB', city: 'İzmir', countryCode: 'TR', countryName: 'Türkiye', lat: 38.2924, lng: 27.157),
  Airport(iata: 'AYT', city: 'Antalya', countryCode: 'TR', countryName: 'Türkiye', lat: 36.8987, lng: 30.8005),
  // Japonya
  Airport(iata: 'HND', city: 'Tokyo (Haneda)', countryCode: 'JP', countryName: 'Japonya', lat: 35.5494, lng: 139.7798),
  Airport(iata: 'NRT', city: 'Tokyo (Narita)', countryCode: 'JP', countryName: 'Japonya', lat: 35.772, lng: 140.3929),
  Airport(iata: 'KIX', city: 'Osaka (Kansai)', countryCode: 'JP', countryName: 'Japonya', lat: 34.4347, lng: 135.244),
  Airport(iata: 'ITM', city: 'Osaka (Itami)', countryCode: 'JP', countryName: 'Japonya', lat: 34.7855, lng: 135.4382),
  Airport(iata: 'CTS', city: 'Sapporo', countryCode: 'JP', countryName: 'Japonya', lat: 42.7752, lng: 141.6923),
  Airport(iata: 'FUK', city: 'Fukuoka', countryCode: 'JP', countryName: 'Japonya', lat: 33.5859, lng: 130.451),
  Airport(iata: 'OKA', city: 'Okinawa', countryCode: 'JP', countryName: 'Japonya', lat: 26.1958, lng: 127.646),
  // Güney Kore
  Airport(iata: 'ICN', city: 'Seul (Incheon)', countryCode: 'KR', countryName: 'Güney Kore', lat: 37.4602, lng: 126.4407),
  Airport(iata: 'GMP', city: 'Seul (Gimpo)', countryCode: 'KR', countryName: 'Güney Kore', lat: 37.5583, lng: 126.7906),
  Airport(iata: 'PUS', city: 'Busan', countryCode: 'KR', countryName: 'Güney Kore', lat: 35.1795, lng: 128.9382),
  // Diğer hub'lar (kısaltılmış — arama için)
  Airport(iata: 'DXB', city: 'Dubai', countryCode: 'AE', countryName: 'BAE', lat: 25.2532, lng: 55.3657),
  Airport(iata: 'DOH', city: 'Doha', countryCode: 'QA', countryName: 'Katar', lat: 25.2731, lng: 51.608),
  Airport(iata: 'FRA', city: 'Frankfurt', countryCode: 'DE', countryName: 'Almanya', lat: 50.0379, lng: 8.5622),
  Airport(iata: 'CDG', city: 'Paris (Charles de Gaulle)', countryCode: 'FR', countryName: 'Fransa', lat: 49.0097, lng: 2.5479),
  Airport(iata: 'LHR', city: 'Londra (Heathrow)', countryCode: 'GB', countryName: 'İngiltere', lat: 51.47, lng: -0.4543),
  Airport(iata: 'AMS', city: 'Amsterdam', countryCode: 'NL', countryName: 'Hollanda', lat: 52.3105, lng: 4.7683),
];

final Map<String, Airport> _byIata = {for (final a in kAirports) a.iata: a};

Airport? getAirport(String iata) => _byIata[iata.toUpperCase()];

/// searchAirports — TS ile aynı skorlama.
List<Airport> searchAirports(String query, {int limit = 8, List<String>? countryCodes}) {
  final filter = (countryCodes != null && countryCodes.isNotEmpty) ? countryCodes.toSet() : null;
  final pool = filter != null ? kAirports.where((a) => filter.contains(a.countryCode)).toList() : kAirports;
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return pool.take(limit).toList();
  final scored = <({Airport a, int score})>[];
  for (final a in pool) {
    final iata = a.iata.toLowerCase();
    final city = a.city.toLowerCase();
    final country = a.countryName.toLowerCase();
    var score = -1;
    if (iata == q) {
      score = 100;
    } else if (iata.startsWith(q)) {
      score = 90;
    } else if (city.startsWith(q)) {
      score = 80;
    } else if (city.contains(q)) {
      score = 60;
    } else if (country.startsWith(q)) {
      score = 50;
    } else if (country.contains(q)) {
      score = 40;
    }
    if (score >= 0) scored.add((a: a, score: score));
  }
  scored.sort((x, y) => y.score.compareTo(x.score));
  return scored.take(limit).map((s) => s.a).toList();
}

String formatAirport(Airport a) => '${a.city} · ${a.iata}';
