// Rota optimizasyonu core testi için POI + otel + istasyon + havaalanı havuzu.
//
// Bu veri yalnızca `tool/route_opt_harness` altındaki test harness'i besler;
// üretim koduna dahil değildir. Koordinatlar gerçek Japonya konumlarına yakındır
// ve harness içinde SADECE sentetik ulaşım süresi türetmek için kullanılır
// (üretim optimizer'ı koordinattan süre üretmez — bkz. ROUTE_OPTIMIZATION.md).

/// Bir yemek yerinin hangi öğünler için gerçekten açık/uygun olduğunu belirtir.
/// Piyasa (market) türü yerler yalnız öğle için; oturmalı lokantalar akşam için
/// uygundur. Bu bilgi kaybolursa kapalı bir yere akşam yemeği yazılabilir
/// (baseline'daki Tsukiji/Nishiki/Kuromon 18:00 akşam yemeği hatası).
enum MealPeriod { breakfast, lunch, dinner }

/// Bir POI'nin gün içindeki rolü. `durationMin >= 300` gibi bir magic number
/// yerine açık şablon; havuz refill edildikten sonra da tema parkı/uzak gezi
/// noktalarının yanlış güne karışmamasını sağlar.
enum PoiDayRole {
  /// Normal, gün içinde başka noktalarla birlikte gezilebilir.
  normal,

  /// Yarım günü tek başına anchor'lar (uzak göl rotası vb.).
  halfDayAnchor,

  /// Tüm günü tek başına doldurur; başka sightseeing noktası eklenmez.
  fullDayExclusive,

  /// Şehir merkezinden ayrı, tam gün süren gezi (feribot/uzak ada vb.).
  excursion,
}

/// Bir gezilecek noktanın statik tanımı.
class PoiSpec {
  const PoiSpec({
    required this.id,
    required this.name,
    required this.city,
    required this.cluster,
    required this.lat,
    required this.lng,
    required this.category,
    required this.durationMin,
    required this.openHour,
    required this.closeHour,
    this.kidFriendly = true,
    this.nightlife = false,
    this.dayRole = PoiDayRole.normal,
    this.mealPeriods = const <MealPeriod>{},
  });

  final String id;
  final String name;
  final String city;
  final String cluster;
  final double lat;
  final double lng;

  /// temple | shrine | museum | nature | shopping | landmark | food | themepark
  final String category;
  final int durationMin;
  final int openHour;
  final int closeHour;
  final bool kidFriendly;
  final bool nightlife;

  /// Gün şablonu — havuz refill'inden bağımsız izolasyon kararı için.
  final PoiDayRole dayRole;

  /// Yalnız food POI'leri için anlamlı: hangi öğünlere hizmet verebilir.
  final Set<MealPeriod> mealPeriods;

  /// Verilen öğün penceresi [start,end) ile yerin çalışma saatinin kesişimi
  /// aktivite süresine yetiyor mu? Öğün desteklenmiyorsa doğrudan false.
  bool servesMeal(MealPeriod period, int windowStartHour, int windowEndHour,
      int neededMinutes) {
    if (mealPeriods.isNotEmpty && !mealPeriods.contains(period)) return false;
    final openStart = openHour * 60;
    final openEnd = closeHour * 60;
    final winStart = windowStartHour * 60;
    final winEnd = windowEndHour * 60;
    final start = openStart > winStart ? openStart : winStart;
    final end = openEnd < winEnd ? openEnd : winEnd;
    return (end - start) >= neededMinutes;
  }
}

/// Bir şehrin merkezî oteli ve şehir-içi/şehirler-arası ulaşım düğümleri.
class CitySpec {
  const CitySpec({
    required this.name,
    required this.hotelId,
    required this.hotelName,
    required this.hotelCluster,
    required this.hotelLat,
    required this.hotelLng,
    required this.shinkansenStation,
    required this.stationLat,
    required this.stationLng,
  });

  final String name;
  final String hotelId;
  final String hotelName;
  final String hotelCluster;
  final double hotelLat;
  final double hotelLng;

  /// Şehirler arası shinkansen istasyonu (transfer günleri için).
  final String shinkansenStation;
  final double stationLat;
  final double stationLng;
}

class AirportSpec {
  const AirportSpec({
    required this.code,
    required this.name,
    required this.city,
    required this.lat,
    required this.lng,
    required this.accessMode,
    required this.accessMinutes,
    required this.accessCostYen,
  });

  final String code;
  final String name;
  final String city;
  final double lat;
  final double lng;
  final String accessMode; // airportExpress | limousineBus | rapidTrain
  final int accessMinutes; // havaalanı <-> şehir merkezi
  final int accessCostYen;
}

const cities = <String, CitySpec>{
  'Tokyo': CitySpec(
    name: 'Tokyo',
    hotelId: 'hotel_tokyo',
    hotelName: 'Shinjuku Konak Otel',
    hotelCluster: 'shinjuku',
    hotelLat: 35.6938,
    hotelLng: 139.7034,
    shinkansenStation: 'Tokyo Station',
    stationLat: 35.6812,
    stationLng: 139.7671,
  ),
  'Kyoto': CitySpec(
    name: 'Kyoto',
    hotelId: 'hotel_kyoto',
    hotelName: 'Karasuma Ryokan',
    hotelCluster: 'central',
    hotelLat: 35.0037,
    hotelLng: 135.7595,
    shinkansenStation: 'Kyoto Station',
    stationLat: 34.9858,
    stationLng: 135.7588,
  ),
  'Osaka': CitySpec(
    name: 'Osaka',
    hotelId: 'hotel_osaka',
    hotelName: 'Namba Grand Otel',
    hotelCluster: 'south',
    hotelLat: 34.6660,
    hotelLng: 135.5010,
    shinkansenStation: 'Shin-Osaka Station',
    stationLat: 34.7332,
    stationLng: 135.5000,
  ),
  'Nara': CitySpec(
    name: 'Nara',
    hotelId: 'hotel_nara',
    hotelName: 'Naramachi Otel',
    hotelCluster: 'park',
    hotelLat: 34.6851,
    hotelLng: 135.8048,
    shinkansenStation: 'Kyoto Station', // Nara shinkansen yok; Kyoto üzerinden
    stationLat: 34.9858,
    stationLng: 135.7588,
  ),
  'Hakone': CitySpec(
    name: 'Hakone',
    hotelId: 'hotel_hakone',
    hotelName: 'Gora Onsen Ryokan',
    hotelCluster: 'gora',
    hotelLat: 35.2447,
    hotelLng: 139.0500,
    shinkansenStation: 'Odawara Station',
    stationLat: 35.2560,
    stationLng: 139.1552,
  ),
  'Hiroshima': CitySpec(
    name: 'Hiroshima',
    hotelId: 'hotel_hiroshima',
    hotelName: 'Peace Park Otel',
    hotelCluster: 'center',
    hotelLat: 34.3955,
    hotelLng: 132.4596,
    shinkansenStation: 'Hiroshima Station',
    stationLat: 34.3977,
    stationLng: 132.4756,
  ),
};

const airports = <String, AirportSpec>{
  'NRT': AirportSpec(
    code: 'NRT',
    name: 'Narita Uluslararası',
    city: 'Tokyo',
    lat: 35.7719,
    lng: 140.3929,
    accessMode: 'airportExpress',
    accessMinutes: 92,
    accessCostYen: 3070,
  ),
  'HND': AirportSpec(
    code: 'HND',
    name: 'Haneda',
    city: 'Tokyo',
    lat: 35.5494,
    lng: 139.7798,
    accessMode: 'rapidTrain',
    accessMinutes: 42,
    accessCostYen: 640,
  ),
  'KIX': AirportSpec(
    code: 'KIX',
    name: 'Kansai Uluslararası',
    city: 'Osaka',
    lat: 34.4342,
    lng: 135.2440,
    accessMode: 'airportExpress',
    accessMinutes: 68,
    accessCostYen: 1210,
  ),
  'ITM': AirportSpec(
    code: 'ITM',
    name: 'Osaka İtami',
    city: 'Osaka',
    lat: 34.7855,
    lng: 135.4382,
    accessMode: 'limousineBus',
    accessMinutes: 30,
    accessCostYen: 650,
  ),
};

/// Şehirlerarası shinkansen yaklaşık süre/maliyeti (yönden bağımsız simetrik).
const _shinkansen = <String, ({int minutes, int costYen, int transfers})>{
  'Tokyo|Kyoto': (minutes: 138, costYen: 13320, transfers: 0),
  'Tokyo|Osaka': (minutes: 150, costYen: 13870, transfers: 0),
  'Tokyo|Hiroshima': (minutes: 240, costYen: 18380, transfers: 0),
  'Tokyo|Hakone': (minutes: 35, costYen: 3540, transfers: 0), // Kodama/Odawara
  'Tokyo|Nara': (minutes: 165, costYen: 13500, transfers: 1),
  'Kyoto|Osaka': (minutes: 15, costYen: 570, transfers: 0), // özel tren
  'Kyoto|Nara': (minutes: 45, costYen: 720, transfers: 0),
  'Kyoto|Hiroshima': (minutes: 102, costYen: 11410, transfers: 0),
  'Kyoto|Hakone': (minutes: 175, costYen: 12730, transfers: 1),
  'Osaka|Nara': (minutes: 38, costYen: 570, transfers: 0),
  'Osaka|Hiroshima': (minutes: 90, costYen: 10440, transfers: 0),
  'Osaka|Hakone': (minutes: 190, costYen: 13200, transfers: 1),
  'Nara|Hiroshima': (minutes: 150, costYen: 11800, transfers: 1),
  'Hakone|Hiroshima': (minutes: 280, costYen: 19500, transfers: 1),
  'Nara|Hakone': (minutes: 210, costYen: 13800, transfers: 2),
};

({int minutes, int costYen, int transfers}) shinkansenBetween(
    String a, String b) {
  return _shinkansen['$a|$b'] ??
      _shinkansen['$b|$a'] ??
      (minutes: 180, costYen: 14000, transfers: 1);
}

/// Şehir başına gezilecek POI havuzu (kümelenmiş, kategorili).
const pois = <PoiSpec>[
  // ---------------- TOKYO ----------------
  PoiSpec(id: 'tk_shibuya', name: 'Shibuya Crossing', city: 'Tokyo', cluster: 'west', lat: 35.6595, lng: 139.7005, category: 'landmark', durationMin: 60, openHour: 0, closeHour: 24),
  PoiSpec(id: 'tk_harajuku', name: 'Takeshita Dori', city: 'Tokyo', cluster: 'west', lat: 35.6702, lng: 139.7027, category: 'shopping', durationMin: 75, openHour: 10, closeHour: 20),
  PoiSpec(id: 'tk_meiji', name: 'Meiji Jingu', city: 'Tokyo', cluster: 'west', lat: 35.6764, lng: 139.6993, category: 'shrine', durationMin: 70, openHour: 6, closeHour: 17),
  PoiSpec(id: 'tk_yoyogi', name: 'Yoyogi Park', city: 'Tokyo', cluster: 'west', lat: 35.6720, lng: 139.6950, category: 'nature', durationMin: 60, openHour: 5, closeHour: 20),
  PoiSpec(id: 'tk_shinjukugyoen', name: 'Shinjuku Gyoen', city: 'Tokyo', cluster: 'shinjuku', lat: 35.6852, lng: 139.7100, category: 'nature', durationMin: 80, openHour: 9, closeHour: 16),
  PoiSpec(id: 'tk_govbldg', name: 'Tokyo Metropolitan Gözlem', city: 'Tokyo', cluster: 'shinjuku', lat: 35.6896, lng: 139.6917, category: 'landmark', durationMin: 45, openHour: 9, closeHour: 22),
  PoiSpec(id: 'tk_asakusa', name: 'Senso-ji', city: 'Tokyo', cluster: 'east', lat: 35.7148, lng: 139.7967, category: 'temple', durationMin: 75, openHour: 6, closeHour: 17),
  PoiSpec(id: 'tk_skytree', name: 'Tokyo Skytree', city: 'Tokyo', cluster: 'east', lat: 35.7101, lng: 139.8107, category: 'landmark', durationMin: 90, openHour: 10, closeHour: 21),
  PoiSpec(id: 'tk_ueno', name: 'Ueno Park & Zoo', city: 'Tokyo', cluster: 'east', lat: 35.7156, lng: 139.7745, category: 'nature', durationMin: 100, openHour: 9, closeHour: 17),
  PoiSpec(id: 'tk_akihabara', name: 'Akihabara', city: 'Tokyo', cluster: 'east', lat: 35.7022, lng: 139.7745, category: 'shopping', durationMin: 90, openHour: 10, closeHour: 20),
  PoiSpec(id: 'tk_ginza', name: 'Ginza', city: 'Tokyo', cluster: 'central', lat: 35.6717, lng: 139.7650, category: 'shopping', durationMin: 90, openHour: 11, closeHour: 20),
  PoiSpec(id: 'tk_imperial', name: 'İmparatorluk Sarayı Bahçesi', city: 'Tokyo', cluster: 'central', lat: 35.6852, lng: 139.7528, category: 'nature', durationMin: 70, openHour: 9, closeHour: 16),
  PoiSpec(id: 'tk_teamlab', name: 'teamLab Planets', city: 'Tokyo', cluster: 'bay', lat: 35.6486, lng: 139.7906, category: 'museum', durationMin: 120, openHour: 9, closeHour: 21),
  PoiSpec(id: 'tk_odaiba', name: 'Odaiba & Gundam', city: 'Tokyo', cluster: 'bay', lat: 35.6250, lng: 139.7757, category: 'landmark', durationMin: 110, openHour: 10, closeHour: 21),
  PoiSpec(id: 'tk_disneysea', name: 'Tokyo DisneySea', city: 'Tokyo', cluster: 'bay', lat: 35.6267, lng: 139.8850, category: 'themepark', durationMin: 480, openHour: 9, closeHour: 21, dayRole: PoiDayRole.fullDayExclusive),
  PoiSpec(id: 'tk_tsukiji', name: 'Tsukiji Dış Çarşı', city: 'Tokyo', cluster: 'central', lat: 35.6654, lng: 139.7707, category: 'food', durationMin: 70, openHour: 5, closeHour: 14, mealPeriods: {MealPeriod.lunch}),

  // ---------------- KYOTO ----------------
  PoiSpec(id: 'ky_fushimi', name: 'Fushimi Inari', city: 'Kyoto', cluster: 'south', lat: 34.9671, lng: 135.7727, category: 'shrine', durationMin: 120, openHour: 0, closeHour: 24),
  PoiSpec(id: 'ky_tofukuji', name: 'Tofuku-ji', city: 'Kyoto', cluster: 'south', lat: 34.9761, lng: 135.7743, category: 'temple', durationMin: 70, openHour: 9, closeHour: 16),
  PoiSpec(id: 'ky_kiyomizu', name: 'Kiyomizu-dera', city: 'Kyoto', cluster: 'higashiyama', lat: 34.9949, lng: 135.7850, category: 'temple', durationMin: 90, openHour: 6, closeHour: 18),
  PoiSpec(id: 'ky_gion', name: 'Gion & Hanamikoji', city: 'Kyoto', cluster: 'higashiyama', lat: 35.0037, lng: 135.7752, category: 'landmark', durationMin: 75, openHour: 0, closeHour: 24, nightlife: true),
  PoiSpec(id: 'ky_yasaka', name: 'Yasaka Jinja', city: 'Kyoto', cluster: 'higashiyama', lat: 35.0036, lng: 135.7785, category: 'shrine', durationMin: 45, openHour: 0, closeHour: 24),
  PoiSpec(id: 'ky_ginkakuji', name: 'Ginkaku-ji', city: 'Kyoto', cluster: 'higashiyama', lat: 35.0270, lng: 135.7982, category: 'temple', durationMin: 70, openHour: 8, closeHour: 17),
  PoiSpec(id: 'ky_philosopher', name: 'Filozof Yolu', city: 'Kyoto', cluster: 'higashiyama', lat: 35.0250, lng: 135.7950, category: 'nature', durationMin: 60, openHour: 0, closeHour: 24),
  PoiSpec(id: 'ky_kinkakuji', name: 'Kinkaku-ji', city: 'Kyoto', cluster: 'north', lat: 35.0394, lng: 135.7292, category: 'temple', durationMin: 70, openHour: 9, closeHour: 17),
  PoiSpec(id: 'ky_ryoanji', name: 'Ryoan-ji', city: 'Kyoto', cluster: 'north', lat: 35.0345, lng: 135.7182, category: 'temple', durationMin: 60, openHour: 8, closeHour: 17),
  PoiSpec(id: 'ky_arashiyama', name: 'Arashiyama Bambu Ormanı', city: 'Kyoto', cluster: 'west', lat: 35.0170, lng: 135.6720, category: 'nature', durationMin: 100, openHour: 0, closeHour: 24),
  PoiSpec(id: 'ky_tenryuji', name: 'Tenryu-ji', city: 'Kyoto', cluster: 'west', lat: 35.0158, lng: 135.6739, category: 'temple', durationMin: 70, openHour: 8, closeHour: 17),
  PoiSpec(id: 'ky_nijo', name: 'Nijo Kalesi', city: 'Kyoto', cluster: 'central', lat: 35.0142, lng: 135.7481, category: 'landmark', durationMin: 80, openHour: 9, closeHour: 16),
  PoiSpec(id: 'ky_nishiki', name: 'Nishiki Çarşısı', city: 'Kyoto', cluster: 'central', lat: 35.0050, lng: 135.7649, category: 'food', durationMin: 70, openHour: 10, closeHour: 18, mealPeriods: {MealPeriod.lunch}),

  // ---------------- OSAKA ----------------
  PoiSpec(id: 'os_dotonbori', name: 'Dotonbori', city: 'Osaka', cluster: 'south', lat: 34.6687, lng: 135.5013, category: 'landmark', durationMin: 90, openHour: 0, closeHour: 24, nightlife: true),
  PoiSpec(id: 'os_shinsaibashi', name: 'Shinsaibashi', city: 'Osaka', cluster: 'south', lat: 34.6750, lng: 135.5010, category: 'shopping', durationMin: 90, openHour: 11, closeHour: 21),
  PoiSpec(id: 'os_namba', name: 'Namba & Kuromon', city: 'Osaka', cluster: 'south', lat: 34.6660, lng: 135.5060, category: 'food', durationMin: 70, openHour: 9, closeHour: 18, mealPeriods: {MealPeriod.lunch}),
  PoiSpec(id: 'os_castle', name: 'Osaka Kalesi', city: 'Osaka', cluster: 'central', lat: 34.6873, lng: 135.5262, category: 'landmark', durationMin: 100, openHour: 9, closeHour: 17),
  PoiSpec(id: 'os_umeda', name: 'Umeda Sky Building', city: 'Osaka', cluster: 'north', lat: 34.7052, lng: 135.4903, category: 'landmark', durationMin: 80, openHour: 9, closeHour: 22),
  PoiSpec(id: 'os_hep', name: 'Umeda Alışveriş', city: 'Osaka', cluster: 'north', lat: 34.7043, lng: 135.4990, category: 'shopping', durationMin: 90, openHour: 11, closeHour: 21),
  PoiSpec(id: 'os_usj', name: 'Universal Studios Japan', city: 'Osaka', cluster: 'bay', lat: 34.6654, lng: 135.4323, category: 'themepark', durationMin: 480, openHour: 9, closeHour: 21, dayRole: PoiDayRole.fullDayExclusive),
  PoiSpec(id: 'os_aquarium', name: 'Kaiyukan Akvaryum', city: 'Osaka', cluster: 'bay', lat: 34.6545, lng: 135.4289, category: 'museum', durationMin: 120, openHour: 10, closeHour: 20),
  PoiSpec(id: 'os_tsutenkaku', name: 'Tsutenkaku & Shinsekai', city: 'Osaka', cluster: 'south', lat: 34.6525, lng: 135.5063, category: 'landmark', durationMin: 70, openHour: 9, closeHour: 21),

  // ---------------- NARA ----------------
  PoiSpec(id: 'nr_park', name: 'Nara Geyik Parkı', city: 'Nara', cluster: 'park', lat: 34.6851, lng: 135.8430, category: 'nature', durationMin: 90, openHour: 0, closeHour: 24),
  PoiSpec(id: 'nr_todaiji', name: 'Todai-ji', city: 'Nara', cluster: 'park', lat: 34.6890, lng: 135.8398, category: 'temple', durationMin: 80, openHour: 7, closeHour: 17),
  PoiSpec(id: 'nr_kasuga', name: 'Kasuga Taisha', city: 'Nara', cluster: 'park', lat: 34.6819, lng: 135.8483, category: 'shrine', durationMin: 70, openHour: 6, closeHour: 18),
  PoiSpec(id: 'nr_naramachi', name: 'Naramachi', city: 'Nara', cluster: 'center', lat: 34.6790, lng: 135.8290, category: 'landmark', durationMin: 60, openHour: 10, closeHour: 18),
  PoiSpec(id: 'nr_horyuji', name: 'Horyu-ji', city: 'Nara', cluster: 'west', lat: 34.6144, lng: 135.7345, category: 'temple', durationMin: 90, openHour: 8, closeHour: 17, dayRole: PoiDayRole.halfDayAnchor),

  // ---------------- HAKONE ----------------
  PoiSpec(id: 'hk_owakudani', name: 'Owakudani', city: 'Hakone', cluster: 'gora', lat: 35.2440, lng: 139.0197, category: 'nature', durationMin: 90, openHour: 9, closeHour: 16),
  PoiSpec(id: 'hk_openair', name: 'Açık Hava Müzesi', city: 'Hakone', cluster: 'gora', lat: 35.2447, lng: 139.0500, category: 'museum', durationMin: 110, openHour: 9, closeHour: 17),
  PoiSpec(id: 'hk_ashi', name: 'Ashi Gölü Korsan Gemisi', city: 'Hakone', cluster: 'lake', lat: 35.2010, lng: 139.0250, category: 'nature', durationMin: 90, openHour: 9, closeHour: 17),
  PoiSpec(id: 'hk_shrine', name: 'Hakone Jinja', city: 'Hakone', cluster: 'lake', lat: 35.2044, lng: 139.0258, category: 'shrine', durationMin: 60, openHour: 0, closeHour: 24),
  PoiSpec(id: 'hk_onsen', name: 'Yunessun Onsen', city: 'Hakone', cluster: 'yumoto', lat: 35.2320, lng: 139.1030, category: 'nature', durationMin: 120, openHour: 9, closeHour: 19),

  // ---------------- HIROSHIMA ----------------
  PoiSpec(id: 'hr_peace', name: 'Barış Anıtı Parkı', city: 'Hiroshima', cluster: 'center', lat: 34.3955, lng: 132.4536, category: 'museum', durationMin: 110, openHour: 8, closeHour: 18),
  PoiSpec(id: 'hr_castle', name: 'Hiroshima Kalesi', city: 'Hiroshima', cluster: 'center', lat: 34.4025, lng: 132.4592, category: 'landmark', durationMin: 70, openHour: 9, closeHour: 18),
  PoiSpec(id: 'hr_miyajima', name: 'Miyajima Itsukushima', city: 'Hiroshima', cluster: 'miyajima', lat: 34.2960, lng: 132.3197, category: 'shrine', durationMin: 180, openHour: 6, closeHour: 18, dayRole: PoiDayRole.excursion),
  PoiSpec(id: 'hr_hondori', name: 'Hondori Çarşısı', city: 'Hiroshima', cluster: 'center', lat: 34.3930, lng: 132.4580, category: 'shopping', durationMin: 70, openHour: 10, closeHour: 20),

  // ---------------- AKŞAM YEMEĞİ LOKANTALARI (dinner-capable) ----------------
  // Baseline'da her şehirde tek market POI hem öğle hem akşam için tekrar
  // kullanılıyordu; market 14:00/18:00'de kapandığından akşam yemeği kapalı
  // yere yazılıyordu. Aşağıdaki oturmalı lokantalar 17:00–23:00 arası açıktır
  // ve öğle+akşam servisi verir; şehrin merkez/otel kümelerine dağıtılmıştır.
  PoiSpec(id: 'tk_dinner_shinjuku', name: 'Omoide Yokocho Izakaya', city: 'Tokyo', cluster: 'shinjuku', lat: 35.6939, lng: 139.6996, category: 'food', durationMin: 75, openHour: 11, closeHour: 23, mealPeriods: {MealPeriod.lunch, MealPeriod.dinner}),
  PoiSpec(id: 'tk_dinner_ginza', name: 'Ginza Kappo', city: 'Tokyo', cluster: 'central', lat: 35.6717, lng: 139.7660, category: 'food', durationMin: 80, openHour: 17, closeHour: 23, mealPeriods: {MealPeriod.dinner}),
  PoiSpec(id: 'tk_dinner_asakusa', name: 'Asakusa Robata', city: 'Tokyo', cluster: 'east', lat: 35.7118, lng: 139.7960, category: 'food', durationMin: 75, openHour: 17, closeHour: 23, mealPeriods: {MealPeriod.dinner}),
  PoiSpec(id: 'ky_dinner_pontocho', name: 'Pontocho Kaiseki', city: 'Kyoto', cluster: 'central', lat: 35.0060, lng: 135.7710, category: 'food', durationMin: 85, openHour: 17, closeHour: 22, mealPeriods: {MealPeriod.dinner}),
  PoiSpec(id: 'ky_dinner_gion', name: 'Gion Izakaya', city: 'Kyoto', cluster: 'higashiyama', lat: 35.0037, lng: 135.7760, category: 'food', durationMin: 75, openHour: 11, closeHour: 22, mealPeriods: {MealPeriod.lunch, MealPeriod.dinner}),
  PoiSpec(id: 'os_dinner_dotonbori', name: 'Dotonbori Okonomiyaki', city: 'Osaka', cluster: 'south', lat: 34.6685, lng: 135.5020, category: 'food', durationMin: 75, openHour: 11, closeHour: 23, mealPeriods: {MealPeriod.lunch, MealPeriod.dinner}),
  PoiSpec(id: 'os_dinner_umeda', name: 'Umeda Kushikatsu', city: 'Osaka', cluster: 'north', lat: 34.7045, lng: 135.4980, category: 'food', durationMin: 75, openHour: 17, closeHour: 23, mealPeriods: {MealPeriod.dinner}),
  PoiSpec(id: 'nr_dinner_naramachi', name: 'Naramachi Teishoku', city: 'Nara', cluster: 'center', lat: 34.6788, lng: 135.8295, category: 'food', durationMin: 70, openHour: 11, closeHour: 22, mealPeriods: {MealPeriod.lunch, MealPeriod.dinner}),
  PoiSpec(id: 'hk_dinner_gora', name: 'Gora Kaiseki', city: 'Hakone', cluster: 'gora', lat: 35.2450, lng: 139.0505, category: 'food', durationMin: 90, openHour: 17, closeHour: 22, mealPeriods: {MealPeriod.dinner}),
  PoiSpec(id: 'hr_dinner_center', name: 'Hiroshima Okonomi-mura', city: 'Hiroshima', cluster: 'center', lat: 34.3938, lng: 132.4585, category: 'food', durationMin: 75, openHour: 11, closeHour: 23, mealPeriods: {MealPeriod.lunch, MealPeriod.dinner}),
];

/// Şehir başına yemek (öğle/akşam) için kullanılabilecek food POI'leri.
List<PoiSpec> foodPois(String city) =>
    pois.where((p) => p.city == city && p.category == 'food').toList();

/// Verilen öğün ve pencere için gerçekten açık olan yemek yerleri.
/// [neededMinutes] aktivite süresidir; kesişim buna yetmiyorsa yer elenir.
List<PoiSpec> mealVenues(
  String city,
  MealPeriod period,
  int windowStartHour,
  int windowEndHour,
  int neededMinutes,
) =>
    pois
        .where((p) =>
            p.city == city &&
            p.category == 'food' &&
            p.servesMeal(period, windowStartHour, windowEndHour, neededMinutes))
        .toList();

List<PoiSpec> sightseeingPois(String city) => pois
    .where((p) =>
        p.city == city &&
        p.category != 'food')
    .toList();
