// apps/viewer/src/data/cityPlaces.ts'in Dart portu.
// Rota şehirlerinin "iç haritası" için küratörlü popüler nokta listesi.
// Koordinatlar yaklaşık gerçek lat/lng — mini-krokide göreli konumlandırma
// için kullanılır. Veriler React referansıyla birebir aynıdır.

import 'geofence.dart';
import 'types.dart';

/// Geofence yarıçapı (m) — nokta merkezli ziyaret algılama.
const double kPlaceRadiusM = 120;

/// Bir noktada kazanılan XP.
const int kPlaceXp = 25;

class CityPlace {
  const CityPlace({
    required this.id,
    required this.name,
    required this.emoji,
    required this.category,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String name;
  final String emoji;

  /// Kısa kategori etiketi (görsel ipucu).
  final String category;
  final double lat;
  final double lng;
}

class CityData {
  const CityData({
    required this.key,
    required this.label,
    required this.emoji,
    required this.aliases,
    required this.places,
  });

  /// Eşleştirme anahtarı (ör. "tokyo").
  final String key;
  final String label;
  final String emoji;

  /// trip içinde bu şehri yakalamak için aranan küçük-harf takma adlar.
  final List<String> aliases;
  final List<CityPlace> places;
}

const List<CityData> kCityData = [
  CityData(
    key: 'tokyo',
    label: 'Tokyo',
    emoji: '🗼',
    aliases: ['tokyo', 'tokio'],
    places: [
      CityPlace(id: 'tk-skytree', name: 'Tokyo Skytree', emoji: '🗼', category: 'Manzara', lat: 35.7101, lng: 139.8107),
      CityPlace(id: 'tk-sensoji', name: 'Senso-ji (Asakusa)', emoji: '⛩️', category: 'Tapınak', lat: 35.7148, lng: 139.7967),
      CityPlace(id: 'tk-shibuya', name: 'Shibuya Crossing', emoji: '🚥', category: 'Şehir', lat: 35.6595, lng: 139.7005),
      CityPlace(id: 'tk-meiji', name: 'Meiji Jingu', emoji: '🌳', category: 'Tapınak', lat: 35.6764, lng: 139.6993),
      CityPlace(id: 'tk-teamlab', name: 'teamLab Planets', emoji: '✨', category: 'Müze', lat: 35.6486, lng: 139.7869),
      CityPlace(id: 'tk-shinjuku-gyoen', name: 'Shinjuku Gyoen', emoji: '🌸', category: 'Park', lat: 35.6852, lng: 139.71),
      CityPlace(id: 'tk-akihabara', name: 'Akihabara', emoji: '🎮', category: 'Alışveriş', lat: 35.7022, lng: 139.7745),
      CityPlace(id: 'tk-tower', name: 'Tokyo Tower', emoji: '🗼', category: 'Manzara', lat: 35.6586, lng: 139.7454),
      CityPlace(id: 'tk-ueno', name: 'Ueno Park', emoji: '🦖', category: 'Park', lat: 35.7156, lng: 139.7745),
      CityPlace(id: 'tk-ginza', name: 'Ginza', emoji: '🛍️', category: 'Alışveriş', lat: 35.6717, lng: 139.765),
      CityPlace(id: 'tk-tsukiji', name: 'Tsukiji Pazarı', emoji: '🍣', category: 'Yemek', lat: 35.6655, lng: 139.7707),
      CityPlace(id: 'tk-odaiba', name: 'Odaiba', emoji: '🎡', category: 'Eğlence', lat: 35.6276, lng: 139.7763),
    ],
  ),
  CityData(
    key: 'kyoto',
    label: 'Kyoto',
    emoji: '⛩️',
    aliases: ['kyoto', 'kioto'],
    places: [
      CityPlace(id: 'ky-fushimi', name: 'Fushimi Inari', emoji: '⛩️', category: 'Tapınak', lat: 34.9671, lng: 135.7727),
      CityPlace(id: 'ky-kinkakuji', name: 'Kinkaku-ji', emoji: '🏯', category: 'Tapınak', lat: 35.0394, lng: 135.7292),
      CityPlace(id: 'ky-arashiyama', name: 'Arashiyama Bambu', emoji: '🎋', category: 'Doğa', lat: 35.017, lng: 135.6716),
      CityPlace(id: 'ky-kiyomizu', name: 'Kiyomizu-dera', emoji: '🛕', category: 'Tapınak', lat: 34.9948, lng: 135.785),
      CityPlace(id: 'ky-gion', name: 'Gion', emoji: '🎎', category: 'Tarihi', lat: 35.0036, lng: 135.7752),
      CityPlace(id: 'ky-nijo', name: 'Nijo Kalesi', emoji: '🏯', category: 'Kale', lat: 35.0142, lng: 135.7483),
      CityPlace(id: 'ky-ginkakuji', name: 'Ginkaku-ji', emoji: '🏯', category: 'Tapınak', lat: 35.027, lng: 135.7982),
      CityPlace(id: 'ky-pontocho', name: 'Pontocho', emoji: '🏮', category: 'Yemek', lat: 35.005, lng: 135.7708),
      CityPlace(id: 'ky-nishiki', name: 'Nishiki Pazarı', emoji: '🍡', category: 'Yemek', lat: 35.005, lng: 135.7649),
      CityPlace(id: 'ky-tofukuji', name: 'Tofuku-ji', emoji: '🍁', category: 'Tapınak', lat: 34.9766, lng: 135.774),
    ],
  ),
  CityData(
    key: 'osaka',
    label: 'Osaka',
    emoji: '🍜',
    aliases: ['osaka', 'ōsaka'],
    places: [
      CityPlace(id: 'os-dotonbori', name: 'Dotonbori', emoji: '🍜', category: 'Yemek', lat: 34.6687, lng: 135.5031),
      CityPlace(id: 'os-castle', name: 'Osaka Kalesi', emoji: '🏯', category: 'Kale', lat: 34.6873, lng: 135.5259),
      CityPlace(id: 'os-usj', name: 'Universal Studios', emoji: '🎢', category: 'Eğlence', lat: 34.6654, lng: 135.4323),
      CityPlace(id: 'os-shinsekai', name: 'Shinsekai · Tsutenkaku', emoji: '🗼', category: 'Şehir', lat: 34.6525, lng: 135.5063),
      CityPlace(id: 'os-umeda', name: 'Umeda Sky Building', emoji: '🌆', category: 'Manzara', lat: 34.7054, lng: 135.4902),
      CityPlace(id: 'os-kuromon', name: 'Kuromon Pazarı', emoji: '🐟', category: 'Yemek', lat: 34.6657, lng: 135.506),
      CityPlace(id: 'os-namba', name: 'Namba', emoji: '🛍️', category: 'Alışveriş', lat: 34.6627, lng: 135.5023),
      CityPlace(id: 'os-sumiyoshi', name: 'Sumiyoshi Taisha', emoji: '⛩️', category: 'Tapınak', lat: 34.6126, lng: 135.4933),
      CityPlace(id: 'os-harukas', name: 'Abeno Harukas', emoji: '🏙️', category: 'Manzara', lat: 34.6456, lng: 135.5136),
      CityPlace(id: 'os-shitennoji', name: 'Shitenno-ji', emoji: '🛕', category: 'Tapınak', lat: 34.6543, lng: 135.5165),
    ],
  ),
  CityData(
    key: 'nara',
    label: 'Nara',
    emoji: '🦌',
    aliases: ['nara'],
    places: [
      CityPlace(id: 'nr-park', name: 'Nara Parkı (geyikler)', emoji: '🦌', category: 'Park', lat: 34.6851, lng: 135.843),
      CityPlace(id: 'nr-todaiji', name: 'Todai-ji', emoji: '🛕', category: 'Tapınak', lat: 34.689, lng: 135.8398),
      CityPlace(id: 'nr-kasuga', name: 'Kasuga Taisha', emoji: '🏮', category: 'Tapınak', lat: 34.6818, lng: 135.8483),
      CityPlace(id: 'nr-kofukuji', name: 'Kofuku-ji', emoji: '🗼', category: 'Tapınak', lat: 34.6833, lng: 135.8327),
      CityPlace(id: 'nr-isuien', name: 'Isuien Bahçesi', emoji: '🌳', category: 'Bahçe', lat: 34.6868, lng: 135.8366),
      CityPlace(id: 'nr-naramachi', name: 'Naramachi', emoji: '🏘️', category: 'Tarihi', lat: 34.6786, lng: 135.8295),
    ],
  ),
  CityData(
    key: 'hiroshima',
    label: 'Hiroshima',
    emoji: '🕊️',
    aliases: ['hiroshima', 'miyajima'],
    places: [
      CityPlace(id: 'hr-peace', name: 'Barış Anıtı Parkı', emoji: '🕊️', category: 'Anıt', lat: 34.3955, lng: 132.4536),
      CityPlace(id: 'hr-dome', name: 'Atom Bombası Kubbesi', emoji: '🏛️', category: 'Anıt', lat: 34.3955, lng: 132.4537),
      CityPlace(id: 'hr-miyajima', name: 'Itsukushima (Miyajima)', emoji: '⛩️', category: 'Tapınak', lat: 34.296, lng: 132.3197),
      CityPlace(id: 'hr-castle', name: 'Hiroshima Kalesi', emoji: '🏯', category: 'Kale', lat: 34.4026, lng: 132.4593),
      CityPlace(id: 'hr-shukkeien', name: 'Shukkeien Bahçesi', emoji: '🌳', category: 'Bahçe', lat: 34.4019, lng: 132.4664),
    ],
  ),
  CityData(
    key: 'sapporo',
    label: 'Sapporo',
    emoji: '❄️',
    aliases: ['sapporo', 'hokkaido', 'hokkaıdo'],
    places: [
      CityPlace(id: 'sp-odori', name: 'Odori Parkı', emoji: '🌳', category: 'Park', lat: 43.0606, lng: 141.3565),
      CityPlace(id: 'sp-moiwa', name: 'Moiwa Dağı', emoji: '🚠', category: 'Manzara', lat: 43.0276, lng: 141.3239),
      CityPlace(id: 'sp-beer', name: 'Sapporo Bira Müzesi', emoji: '🍺', category: 'Müze', lat: 43.0707, lng: 141.3709),
      CityPlace(id: 'sp-clock', name: 'Saat Kulesi', emoji: '🕰️', category: 'Tarihi', lat: 43.0628, lng: 141.3536),
      CityPlace(id: 'sp-susukino', name: 'Susukino', emoji: '🏮', category: 'Yemek', lat: 43.0556, lng: 141.3539),
    ],
  ),
  CityData(
    key: 'kanazawa',
    label: 'Kanazawa',
    emoji: '🌿',
    aliases: ['kanazawa'],
    places: [
      CityPlace(id: 'kz-kenrokuen', name: 'Kenroku-en', emoji: '🌿', category: 'Bahçe', lat: 36.5622, lng: 136.6624),
      CityPlace(id: 'kz-castle', name: 'Kanazawa Kalesi', emoji: '🏯', category: 'Kale', lat: 36.5653, lng: 136.6592),
      CityPlace(id: 'kz-higashi', name: 'Higashi Chaya', emoji: '🏮', category: 'Tarihi', lat: 36.5719, lng: 136.6669),
      CityPlace(id: 'kz-omicho', name: 'Omicho Pazarı', emoji: '🦀', category: 'Yemek', lat: 36.5715, lng: 136.6573),
      CityPlace(id: 'kz-21c', name: '21. Yüzyıl Müzesi', emoji: '🎨', category: 'Müze', lat: 36.5606, lng: 136.6585),
    ],
  ),
];

final Map<String, CityData> _cityByKey = {
  for (final c in kCityData) c.key: c,
};

/// Bir şehir anahtarı için küratörlü veri.
CityData? getCityData(String key) => _cityByKey[key];

/// Trip içinden rota şehirlerini tespit eder. destinations/oteller/uçuş ve gün
/// temaları taranır; küratörlü veriye sahip şehirler, ilk geçtikleri güne göre
/// rota sırasıyla döner. (React: getRouteCities)
List<CityData> detectTripCities(Trip trip) {
  final dayThemes = trip.days
      .map(
        (d) =>
            '${d.theme} ${d.items.map((i) => i.title).join(' ')}'.toLowerCase(),
      )
      .toList();
  final staticSignals = [
    ...trip.preferences.destinations.map((d) => d.city),
    ...trip.hotels.map((h) => h.city),
    ...trip.flights.legs.map((f) => f.city),
    ...trip.flights.outbound.map((f) => f.city),
    ...trip.flights.returnLegs.map((f) => f.city),
    trip.title,
  ].join(' | ').toLowerCase();

  final scored = <({CityData city, int firstDay, int order})>[];
  for (var i = 0; i < kCityData.length; i++) {
    final city = kCityData[i];
    bool matches(String text) => city.aliases.any(text.contains);
    var firstDay = dayThemes.indexWhere(matches);
    final inStatic = matches(staticSignals);
    // Gün bilgisi yok ama statik sinyalde geçiyor.
    if (firstDay < 0 && inStatic) firstDay = 999;
    if (firstDay >= 0) scored.add((city: city, firstDay: firstDay, order: i));
  }
  // Kararlı sıralama: eşit firstDay'de kürasyon sırası korunur
  // (JS Array.sort kararlıdır; Dart sort değildir → order tie-break).
  scored.sort((a, b) {
    final byDay = a.firstDay.compareTo(b.firstDay);
    return byDay != 0 ? byDay : a.order.compareTo(b.order);
  });
  return scored.map((s) => s.city).toList();
}

/// Bir şehirde başlığa karşılık gelen noktayı bulur. Önce tam kapsama
/// (contains) dener; olmazsa yer adının 4+ harfli parçalarını arar
/// ("Senso-ji (Asakusa)" ↔ "Senso-ji Tapınağı" gibi).
CityPlace? _matchPlaceInCity(CityData city, String t) {
  for (final p in city.places) {
    final n = p.name.toLowerCase();
    if (t.contains(n) || n.contains(t)) return p;
  }
  for (final p in city.places) {
    final tokens = p.name
        .toLowerCase()
        .split(RegExp(r'[^a-zçğıöşüâ0-9\-]+'))
        .where((w) => w.length >= 4);
    if (tokens.any(t.contains)) return p;
  }
  return null;
}

/// Gerçek yakınlık önerisi: bir nokta + ona olan kuş uçuşu mesafe.
class NearbyPlace {
  const NearbyPlace({required this.place, required this.distanceM});
  final CityPlace place;
  final double distanceM;
}

/// Öğeye gerçekten yakın küratörlü noktalar, mesafeye göre artan sırada.
/// Konum önce verilen [lat]/[lng]'den, yoksa başlık eşleşmesinden çözülür.
/// Çözülemezse boş liste döner — uydurma "yakında" önerisi göstermeyiz.
List<NearbyPlace> nearbyCityPlaces({
  required String title,
  double? lat,
  double? lng,
  int limit = 3,
}) {
  final t = title.toLowerCase().trim();
  CityData? city;
  CityPlace? self;
  if (t.isNotEmpty) {
    for (final c in kCityData) {
      final m = _matchPlaceInCity(c, t);
      if (m != null) {
        city = c;
        self = m;
        break;
      }
    }
  }
  final origin = (lat != null && lng != null)
      ? LatLng(lat, lng)
      : (self != null ? LatLng(self.lat, self.lng) : null);
  if (origin == null) return const [];
  // Başlıktan şehir çıkmadıysa koordinata en yakın noktanın şehrini al;
  // en yakın nokta bile 30 km+ uzaktaysa öneri anlamsız olur.
  if (city == null) {
    var best = double.infinity;
    for (final c in kCityData) {
      for (final p in c.places) {
        final d = distanceMeters(origin, LatLng(p.lat, p.lng));
        if (d < best) {
          best = d;
          city = c;
        }
      }
    }
    if (best > 30000) return const [];
  }
  final out = [
    for (final p in city!.places)
      if (p.id != self?.id)
        NearbyPlace(
          place: p,
          distanceM: distanceMeters(origin, LatLng(p.lat, p.lng)),
        ),
  ]..sort((a, b) => a.distanceM.compareTo(b.distanceM));
  return out.take(limit).toList();
}

/// Şehir noktalarını GPS geofence'lerine çevirir. Ziyaret, kullanıcının nokta
/// yarıçapında en az 10 dk (kDefaultMinDwell) kalmasıyla otomatik tamamlanır;
/// geofence id'si CityPlace id'si ile aynıdır (UI ile eşleşsin diye).
List<Geofence> cityPlacesToGeofences(List<CityData> cities) {
  return [
    for (final c in cities)
      for (final p in c.places)
        Geofence(
          id: p.id,
          name: p.name,
          city: c.label,
          lat: p.lat,
          lng: p.lng,
          radiusMeters: kPlaceRadiusM,
          minDwellSeconds: kDefaultMinDwell,
          xp: kPlaceXp,
          emoji: p.emoji,
        ),
  ];
}
