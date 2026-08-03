// packages/shared/src/geo/airlines.ts birebir Dart portu.

class Airline {
  const Airline({required this.code, required this.name, this.country, this.icao});
  final String code;
  final String name;
  final String? country;
  final String? icao;
}

const List<Airline> kAirlines = [
  Airline(code: 'TK', name: 'Turkish Airlines', country: 'Türkiye', icao: 'THY'),
  Airline(code: 'PC', name: 'Pegasus Airlines', country: 'Türkiye', icao: 'PGT'),
  Airline(code: 'XQ', name: 'SunExpress', country: 'Türkiye', icao: 'SXS'),
  Airline(code: 'JL', name: 'Japan Airlines', country: 'Japonya', icao: 'JAL'),
  Airline(code: 'NH', name: 'ANA (All Nippon Airways)', country: 'Japonya', icao: 'ANA'),
  Airline(code: 'KE', name: 'Korean Air', country: 'Güney Kore', icao: 'KAL'),
  Airline(code: 'OZ', name: 'Asiana Airlines', country: 'Güney Kore', icao: 'AAR'),
  Airline(code: 'CI', name: 'China Airlines', country: 'Tayvan', icao: 'CAL'),
  Airline(code: 'BR', name: 'EVA Air', country: 'Tayvan', icao: 'EVA'),
  Airline(code: 'CX', name: 'Cathay Pacific', country: 'Hong Kong', icao: 'CPA'),
  Airline(code: 'SQ', name: 'Singapore Airlines', country: 'Singapur', icao: 'SIA'),
  Airline(code: 'TG', name: 'Thai Airways', country: 'Tayland', icao: 'THA'),
  Airline(code: 'QR', name: 'Qatar Airways', country: 'Katar', icao: 'QTR'),
  Airline(code: 'EK', name: 'Emirates', country: 'BAE', icao: 'UAE'),
  Airline(code: 'EY', name: 'Etihad Airways', country: 'BAE', icao: 'ETD'),
  Airline(code: 'SV', name: 'Saudia', country: 'S. Arabistan', icao: 'SVA'),
  Airline(code: 'LH', name: 'Lufthansa', country: 'Almanya', icao: 'DLH'),
  Airline(code: 'AF', name: 'Air France', country: 'Fransa', icao: 'AFR'),
  Airline(code: 'KL', name: 'KLM', country: 'Hollanda', icao: 'KLM'),
  Airline(code: 'BA', name: 'British Airways', country: 'Birleşik Krallık', icao: 'BAW'),
  Airline(code: 'QF', name: 'Qantas', country: 'Avustralya', icao: 'QFA'),
  Airline(code: 'CA', name: 'Air China', country: 'Çin', icao: 'CCA'),
  Airline(code: 'FZ', name: 'flydubai', country: 'BAE', icao: 'FDB'),
];

final Map<String, Airline> _byCode = {for (final a in kAirlines) a.code: a};

String airlineLabel(String code) {
  final a = _byCode[code.toUpperCase()];
  return a != null ? '${a.name} ($code)' : code;
}

List<Airline> searchAirlines(String query, {int limit = 8}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return kAirlines.take(limit).toList();
  final scored = <({Airline a, int score})>[];
  for (final a in kAirlines) {
    final name = a.name.toLowerCase();
    final code = a.code.toLowerCase();
    var score = 999;
    if (code == q) {
      score = 0;
    } else if (name.startsWith(q)) {
      score = 1;
    } else if (code.startsWith(q)) {
      score = 2;
    } else if (name.contains(q)) {
      score = 3;
    } else if ((a.country ?? '').toLowerCase().contains(q)) {
      score = 4;
    }
    if (score < 999) scored.add((a: a, score: score));
  }
  scored.sort((x, y) => x.score.compareTo(y.score));
  return scored.take(limit).map((s) => s.a).toList();
}
