// apps/viewer/src/data/cityPlaces.ts'in Dart portu.
// Rota şehirlerinin "iç haritası" için küratörlü popüler nokta listesi.
// Koordinatlar yaklaşık gerçek lat/lng — mini-krokide göreli konumlandırma
// için kullanılır. Veriler React referansıyla birebir aynıdır.

import 'geofence.dart';
import 'localized_text.dart';
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

  /// Kısa kategori etiketi (görsel ipucu, TR+EN) — yalnızca gösterim için.
  final LText category;
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
      CityPlace(id: 'tk-skytree', name: 'Tokyo Skytree', emoji: '🗼', category: LText('Manzara', 'View'), lat: 35.7101, lng: 139.8107),
      CityPlace(id: 'tk-sensoji', name: 'Senso-ji (Asakusa)', emoji: '⛩️', category: LText('Tapınak', 'Temple'), lat: 35.7148, lng: 139.7967),
      CityPlace(id: 'tk-shibuya', name: 'Shibuya Crossing', emoji: '🚥', category: LText('Şehir', 'City'), lat: 35.6595, lng: 139.7005),
      CityPlace(id: 'tk-meiji', name: 'Meiji Jingu', emoji: '🌳', category: LText('Tapınak', 'Temple'), lat: 35.6764, lng: 139.6993),
      CityPlace(id: 'tk-teamlab', name: 'teamLab Planets', emoji: '✨', category: LText('Müze', 'Museum'), lat: 35.6486, lng: 139.7869),
      CityPlace(id: 'tk-teamlab-borderless', name: 'teamLab Borderless', emoji: '✨', category: LText('Müze', 'Museum'), lat: 35.6605, lng: 139.7292),
      CityPlace(id: 'tk-disneyland', name: 'Tokyo Disneyland', emoji: '🏰', category: LText('Tema parkı', 'Theme park'), lat: 35.6329, lng: 139.8804),
      CityPlace(id: 'tk-disneysea', name: 'Tokyo DisneySea', emoji: '🌊', category: LText('Tema parkı', 'Theme park'), lat: 35.6267, lng: 139.8851),
      CityPlace(id: 'tk-shinjuku-gyoen', name: 'Shinjuku Gyoen', emoji: '🌸', category: LText('Park', 'Park'), lat: 35.6852, lng: 139.71),
      CityPlace(id: 'tk-akihabara', name: 'Akihabara', emoji: '🎮', category: LText('Alışveriş', 'Shopping'), lat: 35.7022, lng: 139.7745),
      CityPlace(id: 'tk-tower', name: 'Tokyo Tower', emoji: '🗼', category: LText('Manzara', 'View'), lat: 35.6586, lng: 139.7454),
      CityPlace(id: 'tk-ueno', name: 'Ueno Park', emoji: '🦖', category: LText('Park', 'Park'), lat: 35.7156, lng: 139.7745),
      CityPlace(id: 'tk-ginza', name: 'Ginza', emoji: '🛍️', category: LText('Alışveriş', 'Shopping'), lat: 35.6717, lng: 139.765),
      CityPlace(id: 'tk-tsukiji', name: 'Tsukiji Pazarı', emoji: '🍣', category: LText('Yemek', 'Food'), lat: 35.6655, lng: 139.7707),
      CityPlace(id: 'tk-odaiba', name: 'Odaiba', emoji: '🎡', category: LText('Eğlence', 'Entertainment'), lat: 35.6276, lng: 139.7763),
    ],
  ),
  CityData(
    key: 'kyoto',
    label: 'Kyoto',
    emoji: '⛩️',
    aliases: ['kyoto', 'kioto'],
    places: [
      CityPlace(id: 'ky-fushimi', name: 'Fushimi Inari', emoji: '⛩️', category: LText('Tapınak', 'Temple'), lat: 34.9671, lng: 135.7727),
      CityPlace(id: 'ky-kinkakuji', name: 'Kinkaku-ji', emoji: '🏯', category: LText('Tapınak', 'Temple'), lat: 35.0394, lng: 135.7292),
      CityPlace(id: 'ky-arashiyama', name: 'Arashiyama Bambu', emoji: '🎋', category: LText('Doğa', 'Nature'), lat: 35.017, lng: 135.6716),
      CityPlace(id: 'ky-kiyomizu', name: 'Kiyomizu-dera', emoji: '🛕', category: LText('Tapınak', 'Temple'), lat: 34.9948, lng: 135.785),
      CityPlace(id: 'ky-gion', name: 'Gion', emoji: '🎎', category: LText('Tarihi', 'Historic'), lat: 35.0036, lng: 135.7752),
      CityPlace(id: 'ky-nijo', name: 'Nijo Kalesi', emoji: '🏯', category: LText('Kale', 'Castle'), lat: 35.0142, lng: 135.7483),
      CityPlace(id: 'ky-ginkakuji', name: 'Ginkaku-ji', emoji: '🏯', category: LText('Tapınak', 'Temple'), lat: 35.027, lng: 135.7982),
      CityPlace(id: 'ky-pontocho', name: 'Pontocho', emoji: '🏮', category: LText('Yemek', 'Food'), lat: 35.005, lng: 135.7708),
      CityPlace(id: 'ky-nishiki', name: 'Nishiki Pazarı', emoji: '🍡', category: LText('Yemek', 'Food'), lat: 35.005, lng: 135.7649),
      CityPlace(id: 'ky-tofukuji', name: 'Tofuku-ji', emoji: '🍁', category: LText('Tapınak', 'Temple'), lat: 34.9766, lng: 135.774),
    ],
  ),
  CityData(
    key: 'osaka',
    label: 'Osaka',
    emoji: '🍜',
    aliases: ['osaka', 'ōsaka'],
    places: [
      CityPlace(id: 'os-dotonbori', name: 'Dotonbori', emoji: '🍜', category: LText('Yemek', 'Food'), lat: 34.6687, lng: 135.5031),
      CityPlace(id: 'os-castle', name: 'Osaka Kalesi', emoji: '🏯', category: LText('Kale', 'Castle'), lat: 34.6873, lng: 135.5259),
      CityPlace(id: 'os-usj', name: 'Universal Studios', emoji: '🎢', category: LText('Eğlence', 'Entertainment'), lat: 34.6654, lng: 135.4323),
      CityPlace(id: 'os-shinsekai', name: 'Shinsekai · Tsutenkaku', emoji: '🗼', category: LText('Şehir', 'City'), lat: 34.6525, lng: 135.5063),
      CityPlace(id: 'os-kuromon', name: 'Kuromon Pazarı', emoji: '🐟', category: LText('Yemek', 'Food'), lat: 34.6657, lng: 135.506),
      CityPlace(id: 'os-namba', name: 'Namba', emoji: '🛍️', category: LText('Alışveriş', 'Shopping'), lat: 34.6627, lng: 135.5023),
      CityPlace(id: 'os-sumiyoshi', name: 'Sumiyoshi Taisha', emoji: '⛩️', category: LText('Tapınak', 'Temple'), lat: 34.6126, lng: 135.4933),
      CityPlace(id: 'os-harukas', name: 'Abeno Harukas', emoji: '🏙️', category: LText('Manzara', 'View'), lat: 34.6456, lng: 135.5136),
      CityPlace(id: 'os-shitennoji', name: 'Shitenno-ji', emoji: '🛕', category: LText('Tapınak', 'Temple'), lat: 34.6543, lng: 135.5165),
    ],
  ),
  CityData(
    key: 'nara',
    label: 'Nara',
    emoji: '🦌',
    aliases: ['nara'],
    places: [
      CityPlace(id: 'nr-park', name: 'Nara Parkı (geyikler)', emoji: '🦌', category: LText('Park', 'Park'), lat: 34.6851, lng: 135.843),
      CityPlace(id: 'nr-todaiji', name: 'Todai-ji', emoji: '🛕', category: LText('Tapınak', 'Temple'), lat: 34.689, lng: 135.8398),
      CityPlace(id: 'nr-kasuga', name: 'Kasuga Taisha', emoji: '🏮', category: LText('Tapınak', 'Temple'), lat: 34.6818, lng: 135.8483),
      CityPlace(id: 'nr-kofukuji', name: 'Kofuku-ji', emoji: '🗼', category: LText('Tapınak', 'Temple'), lat: 34.6833, lng: 135.8327),
      CityPlace(id: 'nr-isuien', name: 'Isuien Bahçesi', emoji: '🌳', category: LText('Bahçe', 'Garden'), lat: 34.6868, lng: 135.8366),
      CityPlace(id: 'nr-naramachi', name: 'Naramachi', emoji: '🏘️', category: LText('Tarihi', 'Historic'), lat: 34.6786, lng: 135.8295),
    ],
  ),
  CityData(
    key: 'hiroshima',
    label: 'Hiroshima',
    emoji: '🕊️',
    aliases: ['hiroshima', 'miyajima'],
    places: [
      CityPlace(id: 'hr-peace', name: 'Barış Anıtı Parkı', emoji: '🕊️', category: LText('Anıt', 'Memorial'), lat: 34.3955, lng: 132.4536),
      CityPlace(id: 'hr-dome', name: 'Atom Bombası Kubbesi', emoji: '🏛️', category: LText('Anıt', 'Memorial'), lat: 34.3955, lng: 132.4537),
      CityPlace(id: 'hr-miyajima', name: 'Itsukushima (Miyajima)', emoji: '⛩️', category: LText('Tapınak', 'Temple'), lat: 34.296, lng: 132.3197),
      CityPlace(id: 'hr-castle', name: 'Hiroshima Kalesi', emoji: '🏯', category: LText('Kale', 'Castle'), lat: 34.4026, lng: 132.4593),
      CityPlace(id: 'hr-shukkeien', name: 'Shukkeien Bahçesi', emoji: '🌳', category: LText('Bahçe', 'Garden'), lat: 34.4019, lng: 132.4664),
    ],
  ),
  CityData(
    key: 'sapporo',
    label: 'Sapporo',
    emoji: '❄️',
    aliases: ['sapporo', 'hokkaido', 'hokkaıdo'],
    places: [
      CityPlace(id: 'sp-odori', name: 'Odori Parkı', emoji: '🌳', category: LText('Park', 'Park'), lat: 43.0606, lng: 141.3565),
      CityPlace(id: 'sp-moiwa', name: 'Moiwa Dağı', emoji: '🚠', category: LText('Manzara', 'View'), lat: 43.0276, lng: 141.3239),
      CityPlace(id: 'sp-beer', name: 'Sapporo Bira Müzesi', emoji: '🍺', category: LText('Müze', 'Museum'), lat: 43.0707, lng: 141.3709),
      CityPlace(id: 'sp-clock', name: 'Saat Kulesi', emoji: '🕰️', category: LText('Tarihi', 'Historic'), lat: 43.0628, lng: 141.3536),
      CityPlace(id: 'sp-susukino', name: 'Susukino', emoji: '🏮', category: LText('Yemek', 'Food'), lat: 43.0556, lng: 141.3539),
    ],
  ),
  CityData(
    key: 'kanazawa',
    label: 'Kanazawa',
    emoji: '🌿',
    aliases: ['kanazawa'],
    places: [
      CityPlace(id: 'kz-kenrokuen', name: 'Kenroku-en', emoji: '🌿', category: LText('Bahçe', 'Garden'), lat: 36.5622, lng: 136.6624),
      CityPlace(id: 'kz-castle', name: 'Kanazawa Kalesi', emoji: '🏯', category: LText('Kale', 'Castle'), lat: 36.5653, lng: 136.6592),
      CityPlace(id: 'kz-higashi', name: 'Higashi Chaya', emoji: '🏮', category: LText('Tarihi', 'Historic'), lat: 36.5719, lng: 136.6669),
      CityPlace(id: 'kz-omicho', name: 'Omicho Pazarı', emoji: '🦀', category: LText('Yemek', 'Food'), lat: 36.5715, lng: 136.6573),
      CityPlace(id: 'kz-21c', name: '21. Yüzyıl Müzesi', emoji: '🎨', category: LText('Müze', 'Museum'), lat: 36.5606, lng: 136.6585),
    ],
  ),
  CityData(
    key: 'yokohama',
    label: 'Yokohama',
    emoji: '🎡',
    aliases: ['yokohama'],
    places: [
      CityPlace(id: 'yk-minato', name: 'Minato Mirai', emoji: '🎡', category: LText('Manzara', 'View'), lat: 35.4568, lng: 139.6317),
      CityPlace(id: 'yk-chinatown', name: 'Yokohama Çin Mahallesi', emoji: '🥟', category: LText('Yemek', 'Food'), lat: 35.4437, lng: 139.6455),
      CityPlace(id: 'yk-sankeien', name: 'Sankeien Bahçesi', emoji: '🌸', category: LText('Bahçe', 'Garden'), lat: 35.4127, lng: 139.6588),
      CityPlace(id: 'yk-cupnoodle', name: 'Cup Noodles Müzesi', emoji: '🍜', category: LText('Müze', 'Museum'), lat: 35.4547, lng: 139.6382),
      CityPlace(id: 'yk-akarenga', name: 'Kırmızı Tuğla Ambarı', emoji: '🧱', category: LText('Tarihi', 'Historic'), lat: 35.4527, lng: 139.6425),
    ],
  ),
  CityData(
    key: 'hakone',
    label: 'Hakone',
    emoji: '♨️',
    aliases: ['hakone'],
    places: [
      CityPlace(id: 'hk-shrine', name: 'Hakone Tapınağı', emoji: '⛩️', category: LText('Tapınak', 'Temple'), lat: 35.2044, lng: 139.0257),
      CityPlace(id: 'hk-owakudani', name: 'Owakudani', emoji: '🌋', category: LText('Doğa', 'Nature'), lat: 35.2445, lng: 139.0197),
      CityPlace(id: 'hk-ashi', name: 'Ashi Gölü', emoji: '⛵', category: LText('Göl', 'Lake'), lat: 35.2050, lng: 139.0100),
      CityPlace(id: 'hk-openair', name: 'Açık Hava Müzesi', emoji: '🗿', category: LText('Müze', 'Museum'), lat: 35.2447, lng: 139.0503),
      CityPlace(id: 'hk-gora', name: 'Gora & Onsen', emoji: '♨️', category: LText('Kaplıca', 'Onsen'), lat: 35.2418, lng: 139.0505),
    ],
  ),
  CityData(
    key: 'kamakura',
    label: 'Kamakura',
    emoji: '🗿',
    aliases: ['kamakura', 'enoshima'],
    places: [
      CityPlace(id: 'km-daibutsu', name: 'Büyük Buda (Kotoku-in)', emoji: '🗿', category: LText('Tapınak', 'Temple'), lat: 35.3167, lng: 139.5358),
      CityPlace(id: 'km-hasedera', name: 'Hase-dera', emoji: '🌺', category: LText('Tapınak', 'Temple'), lat: 35.3125, lng: 139.5327),
      CityPlace(id: 'km-hachimangu', name: 'Tsurugaoka Hachimangu', emoji: '⛩️', category: LText('Tapınak', 'Temple'), lat: 35.3259, lng: 139.5563),
      CityPlace(id: 'km-enoshima', name: 'Enoshima Adası', emoji: '🏝️', category: LText('Ada', 'Island'), lat: 35.2996, lng: 139.4805),
      CityPlace(id: 'km-hokokuji', name: 'Hokoku-ji Bambu Bahçesi', emoji: '🎋', category: LText('Bahçe', 'Garden'), lat: 35.3197, lng: 139.5688),
    ],
  ),
  CityData(
    key: 'fuji',
    label: 'Fuji & Kawaguchiko',
    emoji: '🗻',
    aliases: ['fuji', 'kawaguchiko', 'kawaguchi', 'fujikawaguchiko'],
    places: [
      CityPlace(id: 'fj-kawaguchi', name: 'Kawaguchi Gölü', emoji: '🗻', category: LText('Göl', 'Lake'), lat: 35.5171, lng: 138.7520),
      CityPlace(id: 'fj-chureito', name: 'Chureito Pagodası', emoji: '🏯', category: LText('Manzara', 'View'), lat: 35.5006, lng: 138.8000),
      CityPlace(id: 'fj-oshino', name: 'Oshino Hakkai', emoji: '💧', category: LText('Köy', 'Village'), lat: 35.4600, lng: 138.8300),
      CityPlace(id: 'fj-fujiq', name: 'Fuji-Q Highland', emoji: '🎢', category: LText('Eğlence', 'Fun'), lat: 35.4874, lng: 138.7803),
      CityPlace(id: 'fj-5th', name: 'Fuji 5. İstasyon', emoji: '⛰️', category: LText('Doğa', 'Nature'), lat: 35.3956, lng: 138.7331),
    ],
  ),
  CityData(
    key: 'nikko',
    label: 'Nikko',
    emoji: '🍁',
    aliases: ['nikko', 'nikkō'],
    places: [
      CityPlace(id: 'nk-toshogu', name: 'Tosho-gu Tapınağı', emoji: '⛩️', category: LText('Tapınak', 'Temple'), lat: 36.7581, lng: 139.5989),
      CityPlace(id: 'nk-kegon', name: 'Kegon Şelalesi', emoji: '💦', category: LText('Doğa', 'Nature'), lat: 36.7396, lng: 139.5027),
      CityPlace(id: 'nk-chuzenji', name: 'Chuzenji Gölü', emoji: '🏞️', category: LText('Göl', 'Lake'), lat: 36.7333, lng: 139.4833),
      CityPlace(id: 'nk-shinkyo', name: 'Shinkyo Köprüsü', emoji: '🌉', category: LText('Tarihi', 'Historic'), lat: 36.7530, lng: 139.6027),
      CityPlace(id: 'nk-rinnoji', name: 'Rinno-ji', emoji: '🛕', category: LText('Tapınak', 'Temple'), lat: 36.7558, lng: 139.6003),
    ],
  ),
  CityData(
    key: 'nagoya',
    label: 'Nagoya',
    emoji: '🏯',
    aliases: ['nagoya'],
    places: [
      CityPlace(id: 'ng-castle', name: 'Nagoya Kalesi', emoji: '🏯', category: LText('Kale', 'Castle'), lat: 35.1856, lng: 136.8997),
      CityPlace(id: 'ng-atsuta', name: 'Atsuta Jingu', emoji: '⛩️', category: LText('Tapınak', 'Temple'), lat: 35.1280, lng: 136.9078),
      CityPlace(id: 'ng-osu', name: 'Osu Kannon & Çarşı', emoji: '🏮', category: LText('Alışveriş', 'Shopping'), lat: 35.1596, lng: 136.8993),
      CityPlace(id: 'ng-toyota', name: 'Toyota Sanayi Müzesi', emoji: '🚗', category: LText('Müze', 'Museum'), lat: 35.1847, lng: 136.8760),
      CityPlace(id: 'ng-ghibli', name: 'Ghibli Parkı', emoji: '🌰', category: LText('Eğlence', 'Fun'), lat: 35.2337, lng: 137.0798),
    ],
  ),
  CityData(
    key: 'kobe',
    label: 'Kobe',
    emoji: '🥩',
    aliases: ['kobe', 'kōbe'],
    places: [
      CityPlace(id: 'kb-harborland', name: 'Harborland', emoji: '🎡', category: LText('Manzara', 'View'), lat: 34.6795, lng: 135.1802),
      CityPlace(id: 'kb-kitano', name: 'Kitano Ijinkan', emoji: '🏘️', category: LText('Tarihi', 'Historic'), lat: 34.7009, lng: 135.1889),
      CityPlace(id: 'kb-rokko', name: 'Rokko Dağı', emoji: '🚠', category: LText('Manzara', 'View'), lat: 34.7783, lng: 135.2620),
      CityPlace(id: 'kb-nunobiki', name: 'Nunobiki Şelalesi', emoji: '💦', category: LText('Doğa', 'Nature'), lat: 34.7060, lng: 135.1945),
      CityPlace(id: 'kb-nankinmachi', name: 'Nankinmachi (Çin Mahallesi)', emoji: '🥟', category: LText('Yemek', 'Food'), lat: 34.6885, lng: 135.1876),
    ],
  ),
  CityData(
    key: 'himeji',
    label: 'Himeji',
    emoji: '🏰',
    aliases: ['himeji'],
    places: [
      CityPlace(id: 'hm-castle', name: 'Himeji Kalesi', emoji: '🏰', category: LText('Kale', 'Castle'), lat: 34.8394, lng: 134.6939),
      CityPlace(id: 'hm-kokoen', name: 'Koko-en Bahçesi', emoji: '🌿', category: LText('Bahçe', 'Garden'), lat: 34.8383, lng: 134.6913),
      CityPlace(id: 'hm-engyoji', name: 'Engyo-ji (Shosha Dağı)', emoji: '🛕', category: LText('Tapınak', 'Temple'), lat: 34.8672, lng: 134.6564),
      CityPlace(id: 'hm-otemae', name: 'Otemae Caddesi', emoji: '🛍️', category: LText('Alışveriş', 'Shopping'), lat: 34.8300, lng: 134.6930),
      CityPlace(id: 'hm-nadagikkenn', name: 'Himeji Merkez Parkı', emoji: '🎢', category: LText('Eğlence', 'Fun'), lat: 34.9058, lng: 134.6739),
    ],
  ),
  CityData(
    key: 'takayama',
    label: 'Takayama',
    emoji: '🏘️',
    aliases: ['takayama', 'hida', 'shirakawago', 'shirakawa'],
    places: [
      CityPlace(id: 'tk-sanmachi', name: 'Sanmachi Eski Şehir', emoji: '🏘️', category: LText('Tarihi', 'Historic'), lat: 36.1408, lng: 137.2618),
      CityPlace(id: 'tk-jinya', name: 'Takayama Jinya', emoji: '🏯', category: LText('Tarihi', 'Historic'), lat: 36.1387, lng: 137.2585),
      CityPlace(id: 'tk-folk', name: 'Hida Köyü', emoji: '🛖', category: LText('Müze', 'Museum'), lat: 36.1348, lng: 137.2361),
      CityPlace(id: 'tk-market', name: 'Miyagawa Sabah Pazarı', emoji: '🧺', category: LText('Pazar', 'Market'), lat: 36.1428, lng: 137.2614),
      CityPlace(id: 'tk-shirakawa', name: 'Shirakawa-go', emoji: '⛰️', category: LText('Köy', 'Village'), lat: 36.2578, lng: 136.9063),
    ],
  ),
  CityData(
    key: 'matsumoto',
    label: 'Matsumoto',
    emoji: '🏔️',
    aliases: ['matsumoto', 'kamikochi'],
    places: [
      CityPlace(id: 'mt-castle', name: 'Matsumoto Kalesi', emoji: '🏯', category: LText('Kale', 'Castle'), lat: 36.2384, lng: 137.9690),
      CityPlace(id: 'mt-nakamachi', name: 'Nakamachi Caddesi', emoji: '🏘️', category: LText('Tarihi', 'Historic'), lat: 36.2340, lng: 137.9700),
      CityPlace(id: 'mt-kamikochi', name: 'Kamikochi', emoji: '🏔️', category: LText('Doğa', 'Nature'), lat: 36.2500, lng: 137.6333),
      CityPlace(id: 'mt-wasabi', name: 'Daio Wasabi Çiftliği', emoji: '🌱', category: LText('Doğa', 'Nature'), lat: 36.2861, lng: 137.8919),
      CityPlace(id: 'mt-art', name: 'Matsumoto Sanat Müzesi', emoji: '🎨', category: LText('Müze', 'Museum'), lat: 36.2333, lng: 137.9750),
    ],
  ),
  CityData(
    key: 'fukuoka',
    label: 'Fukuoka',
    emoji: '🏮',
    aliases: ['fukuoka', 'hakata', 'dazaifu'],
    places: [
      CityPlace(id: 'fk-ohori', name: 'Ohori Parkı', emoji: '🌳', category: LText('Park', 'Park'), lat: 33.5859, lng: 130.3789),
      CityPlace(id: 'fk-dazaifu', name: 'Dazaifu Tenmangu', emoji: '⛩️', category: LText('Tapınak', 'Temple'), lat: 33.5215, lng: 130.5350),
      CityPlace(id: 'fk-canal', name: 'Canal City Hakata', emoji: '🛍️', category: LText('Alışveriş', 'Shopping'), lat: 33.5897, lng: 130.4110),
      CityPlace(id: 'fk-kushida', name: 'Kushida Tapınağı', emoji: '🎏', category: LText('Tapınak', 'Temple'), lat: 33.5934, lng: 130.4106),
      CityPlace(id: 'fk-yatai', name: 'Nakasu Yatai (sokak tezgâhları)', emoji: '🍜', category: LText('Yemek', 'Food'), lat: 33.5930, lng: 130.4050),
    ],
  ),
  CityData(
    key: 'nagasaki',
    label: 'Nagasaki',
    emoji: '⛪',
    aliases: ['nagasaki'],
    places: [
      CityPlace(id: 'ns-peace', name: 'Barış Parkı', emoji: '🕊️', category: LText('Anıt', 'Memorial'), lat: 32.7726, lng: 129.8636),
      CityPlace(id: 'ns-glover', name: 'Glover Bahçesi', emoji: '🌺', category: LText('Tarihi', 'Historic'), lat: 32.7340, lng: 129.8697),
      CityPlace(id: 'ns-inasa', name: 'Inasa Dağı', emoji: '🌃', category: LText('Manzara', 'View'), lat: 32.7472, lng: 129.8542),
      CityPlace(id: 'ns-dejima', name: 'Dejima', emoji: '🚢', category: LText('Tarihi', 'Historic'), lat: 32.7439, lng: 129.8735),
      CityPlace(id: 'ns-oura', name: 'Oura Kilisesi', emoji: '⛪', category: LText('Tarihi', 'Historic'), lat: 32.7343, lng: 129.8709),
    ],
  ),
  CityData(
    key: 'hakodate',
    label: 'Hakodate',
    emoji: '🦑',
    aliases: ['hakodate'],
    places: [
      CityPlace(id: 'hd-yama', name: 'Hakodate Dağı Manzarası', emoji: '🌃', category: LText('Manzara', 'View'), lat: 41.7595, lng: 140.7043),
      CityPlace(id: 'hd-market', name: 'Sabah Pazarı', emoji: '🦑', category: LText('Pazar', 'Market'), lat: 41.7735, lng: 140.7268),
      CityPlace(id: 'hd-kanemori', name: 'Kanemori Kırmızı Tuğla', emoji: '🧱', category: LText('Alışveriş', 'Shopping'), lat: 41.7654, lng: 140.7130),
      CityPlace(id: 'hd-goryokaku', name: 'Goryokaku', emoji: '⭐', category: LText('Tarihi', 'Historic'), lat: 41.7967, lng: 140.7568),
      CityPlace(id: 'hd-motomachi', name: 'Motomachi', emoji: '⛪', category: LText('Tarihi', 'Historic'), lat: 41.7605, lng: 140.7100),
    ],
  ),
  CityData(
    key: 'okinawa',
    label: 'Okinawa',
    emoji: '🏝️',
    aliases: ['okinawa', 'naha'],
    places: [
      CityPlace(id: 'ok-shuri', name: 'Shuri Kalesi', emoji: '🏯', category: LText('Kale', 'Castle'), lat: 26.2170, lng: 127.7196),
      CityPlace(id: 'ok-kokusai', name: 'Kokusai-dori', emoji: '🛍️', category: LText('Alışveriş', 'Shopping'), lat: 26.2145, lng: 127.6875),
      CityPlace(id: 'ok-churaumi', name: 'Churaumi Akvaryumu', emoji: '🐠', category: LText('Akvaryum', 'Aquarium'), lat: 26.6944, lng: 127.8779),
      CityPlace(id: 'ok-manzamo', name: 'Manzamo Burnu', emoji: '🌊', category: LText('Doğa', 'Nature'), lat: 26.5045, lng: 127.8506),
      CityPlace(id: 'ok-naminoue', name: 'Naminoue Plajı', emoji: '🏖️', category: LText('Plaj', 'Beach'), lat: 26.2200, lng: 127.6690),
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
        (d) => '${d.theme} ${d.items.map((i) => i.title).join(' ')}'.toLowerCase(),
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
    final tokens = p.name.toLowerCase().split(RegExp(r'[^a-zçğıöşüâ0-9\-]+')).where((w) => w.length >= 4);
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
  final origin = (lat != null && lng != null) ? LatLng(lat, lng) : (self != null ? LatLng(self.lat, self.lng) : null);
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
