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
  // --- Dünya geneli başlıca kalkış merkezleri (herhangi bir yerden Japonya'ya) ---
  // Kuzey Amerika
  Airport(iata: 'JFK', city: 'New York (JFK)', countryCode: 'US', countryName: 'ABD', lat: 40.6413, lng: -73.7781),
  Airport(iata: 'EWR', city: 'New York (Newark)', countryCode: 'US', countryName: 'ABD', lat: 40.6895, lng: -74.1745),
  Airport(iata: 'LAX', city: 'Los Angeles', countryCode: 'US', countryName: 'ABD', lat: 33.9416, lng: -118.4085),
  Airport(iata: 'SFO', city: 'San Francisco', countryCode: 'US', countryName: 'ABD', lat: 37.6213, lng: -122.379),
  Airport(iata: 'ORD', city: 'Chicago', countryCode: 'US', countryName: 'ABD', lat: 41.9742, lng: -87.9073),
  Airport(iata: 'SEA', city: 'Seattle', countryCode: 'US', countryName: 'ABD', lat: 47.4502, lng: -122.3088),
  Airport(iata: 'IAD', city: 'Washington', countryCode: 'US', countryName: 'ABD', lat: 38.9531, lng: -77.4565),
  Airport(iata: 'YYZ', city: 'Toronto', countryCode: 'CA', countryName: 'Kanada', lat: 43.6777, lng: -79.6248),
  Airport(iata: 'YVR', city: 'Vancouver', countryCode: 'CA', countryName: 'Kanada', lat: 49.1967, lng: -123.1815),
  Airport(iata: 'MEX', city: 'Mexico City', countryCode: 'MX', countryName: 'Meksika', lat: 19.4363, lng: -99.0721),
  Airport(iata: 'GRU', city: 'São Paulo', countryCode: 'BR', countryName: 'Brezilya', lat: -23.4356, lng: -46.4731),
  Airport(iata: 'EZE', city: 'Buenos Aires', countryCode: 'AR', countryName: 'Arjantin', lat: -34.8222, lng: -58.5358),
  // Avrupa
  Airport(iata: 'MAD', city: 'Madrid', countryCode: 'ES', countryName: 'İspanya', lat: 40.4983, lng: -3.5676),
  Airport(iata: 'BCN', city: 'Barcelona', countryCode: 'ES', countryName: 'İspanya', lat: 41.2974, lng: 2.0833),
  Airport(iata: 'FCO', city: 'Roma', countryCode: 'IT', countryName: 'İtalya', lat: 41.8003, lng: 12.2389),
  Airport(iata: 'MXP', city: 'Milano', countryCode: 'IT', countryName: 'İtalya', lat: 45.6301, lng: 8.7255),
  Airport(iata: 'MUC', city: 'Münih', countryCode: 'DE', countryName: 'Almanya', lat: 48.3538, lng: 11.7861),
  Airport(iata: 'ZRH', city: 'Zürih', countryCode: 'CH', countryName: 'İsviçre', lat: 47.4647, lng: 8.5492),
  Airport(iata: 'VIE', city: 'Viyana', countryCode: 'AT', countryName: 'Avusturya', lat: 48.1103, lng: 16.5697),
  Airport(iata: 'CPH', city: 'Kopenhag', countryCode: 'DK', countryName: 'Danimarka', lat: 55.618, lng: 12.6508),
  Airport(iata: 'ARN', city: 'Stockholm', countryCode: 'SE', countryName: 'İsveç', lat: 59.6519, lng: 17.9186),
  Airport(iata: 'DUB', city: 'Dublin', countryCode: 'IE', countryName: 'İrlanda', lat: 53.4264, lng: -6.2499),
  Airport(iata: 'MAN', city: 'Manchester', countryCode: 'GB', countryName: 'İngiltere', lat: 53.3654, lng: -2.2728),
  Airport(iata: 'ZAG', city: 'Zagreb', countryCode: 'HR', countryName: 'Hırvatistan', lat: 45.7429, lng: 16.0688),
  Airport(iata: 'ATH', city: 'Atina', countryCode: 'GR', countryName: 'Yunanistan', lat: 37.9364, lng: 23.9445),
  Airport(iata: 'SVO', city: 'Moskova', countryCode: 'RU', countryName: 'Rusya', lat: 55.9726, lng: 37.4146),
  // Orta Doğu & Afrika
  Airport(iata: 'AUH', city: 'Abu Dabi', countryCode: 'AE', countryName: 'BAE', lat: 24.433, lng: 54.6511),
  Airport(iata: 'JED', city: 'Cidde', countryCode: 'SA', countryName: 'Suudi Arabistan', lat: 21.6796, lng: 39.1565),
  Airport(iata: 'RUH', city: 'Riyad', countryCode: 'SA', countryName: 'Suudi Arabistan', lat: 24.9576, lng: 46.6988),
  Airport(iata: 'TLV', city: 'Tel Aviv', countryCode: 'IL', countryName: 'İsrail', lat: 32.0114, lng: 34.8867),
  Airport(iata: 'CAI', city: 'Kahire', countryCode: 'EG', countryName: 'Mısır', lat: 30.1219, lng: 31.4056),
  Airport(iata: 'JNB', city: 'Johannesburg', countryCode: 'ZA', countryName: 'Güney Afrika', lat: -26.1392, lng: 28.246),
  Airport(iata: 'NBO', city: 'Nairobi', countryCode: 'KE', countryName: 'Kenya', lat: -1.3192, lng: 36.9278),
  // Asya & Pasifik
  Airport(iata: 'SIN', city: 'Singapur', countryCode: 'SG', countryName: 'Singapur', lat: 1.3644, lng: 103.9915),
  Airport(iata: 'HKG', city: 'Hong Kong', countryCode: 'HK', countryName: 'Hong Kong', lat: 22.308, lng: 113.9185),
  Airport(iata: 'BKK', city: 'Bangkok', countryCode: 'TH', countryName: 'Tayland', lat: 13.69, lng: 100.7501),
  Airport(iata: 'KUL', city: 'Kuala Lumpur', countryCode: 'MY', countryName: 'Malezya', lat: 2.7456, lng: 101.7099),
  Airport(iata: 'PVG', city: 'Şangay', countryCode: 'CN', countryName: 'Çin', lat: 31.1443, lng: 121.8083),
  Airport(iata: 'PEK', city: 'Pekin', countryCode: 'CN', countryName: 'Çin', lat: 40.0799, lng: 116.6031),
  Airport(iata: 'TPE', city: 'Taipei', countryCode: 'TW', countryName: 'Tayvan', lat: 25.0777, lng: 121.2328),
  Airport(iata: 'MNL', city: 'Manila', countryCode: 'PH', countryName: 'Filipinler', lat: 14.5086, lng: 121.0195),
  Airport(iata: 'CGK', city: 'Cakarta', countryCode: 'ID', countryName: 'Endonezya', lat: -6.1256, lng: 106.6559),
  Airport(iata: 'DEL', city: 'Yeni Delhi', countryCode: 'IN', countryName: 'Hindistan', lat: 28.5562, lng: 77.1),
  Airport(iata: 'BOM', city: 'Mumbai', countryCode: 'IN', countryName: 'Hindistan', lat: 19.0896, lng: 72.8656),
  Airport(iata: 'SYD', city: 'Sydney', countryCode: 'AU', countryName: 'Avustralya', lat: -33.9399, lng: 151.1753),
  Airport(iata: 'MEL', city: 'Melbourne', countryCode: 'AU', countryName: 'Avustralya', lat: -37.6733, lng: 144.8433),
  Airport(iata: 'AKL', city: 'Auckland', countryCode: 'NZ', countryName: 'Yeni Zelanda', lat: -37.0082, lng: 174.785),
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
