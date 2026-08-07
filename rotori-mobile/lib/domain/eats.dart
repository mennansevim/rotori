// Rotori Eats — küratörlü restoran verisi (saf Dart, offline).
//
// Google Places API yok: veri gömülü/küratörlüdür, dış maliyet sıfırdır.
// İleride Supabase `restaurants` tablosundan beslenecek şekilde tasarlandı
// (aynı alanlar). `mapsQuery` Google Maps arama linki için kullanılır.
//
// Not: `halal` yalnızca gerçekten helal-sertifikalı/helal-dostu olduğu
// doğrulanmış mekanlar için true'dur; uydurma sertifika işaretlenmez.

import 'localized_text.dart';

/// Eats filtre seçenekleri. Free katmanda `halal` ana kullanım senaryosudur.
enum EatsFilter { all, halal, vegetarian }

/// Free katmanda bir filtrede gösterilen en fazla sonuç sayısı.
/// Kalanı premium (ayrı tartışma) ile açılacak.
const int kEatsFreeLimit = 3;

class EatsPlace {
  const EatsPlace({
    required this.id,
    required this.name,
    required this.city,
    required this.area,
    required this.categoryEmoji,
    required this.category,
    required this.description,
    required this.priceBand,
    required this.rating,
    required this.halal,
    required this.vegetarianFriendly,
    required this.mapsQuery,
  });

  final String id;

  /// Özel isim — çevrilmez (ör. "Gyumon").
  final String name;
  final String city; // 'Tokyo' | 'Osaka' | 'Kyoto'
  final String area;
  final String categoryEmoji;
  final LText category;
  final LText description;

  /// Yaklaşık kişi başı fiyat bandı (ör. `¥2,000–4,000`).
  final String priceBand;
  final double rating;
  final bool halal;
  final bool vegetarianFriendly;

  /// Google Maps aramasında kullanılacak sorgu.
  final String mapsQuery;

  bool matches(EatsFilter filter) => switch (filter) {
        EatsFilter.all => true,
        EatsFilter.halal => halal,
        EatsFilter.vegetarian => vegetarianFriendly,
      };
}

/// Verilen filtreye uyan mekanlar (puana göre azalan, kararlı sıralama).
List<EatsPlace> filterEats(List<EatsPlace> places, EatsFilter filter) {
  final out = places.where((p) => p.matches(filter)).toList()
    ..sort((a, b) {
      final byRating = b.rating.compareTo(a.rating);
      return byRating != 0 ? byRating : a.id.compareTo(b.id);
    });
  return out;
}

/// Küratörlü başlangıç listesi. Helal ağırlıklı; Tokyo/Osaka/Kyoto.
const List<EatsPlace> kEatsPlaces = [
  // --- Tokyo ---------------------------------------------------------------
  EatsPlace(
    id: 'tk-gyumon',
    name: 'Gyumon',
    city: 'Tokyo',
    area: 'Shibuya',
    categoryEmoji: '🍜',
    category: LText('Helal Ramen', 'Halal Ramen'),
    description: LText(
      'Helal sertifikalı wagyu ramen ve yakiniku. Shibuya\'da ulaşım kolay.',
      'Halal-certified wagyu ramen and yakiniku. Easy to reach in Shibuya.',
    ),
    priceBand: '¥2,000–4,000',
    rating: 4.6,
    halal: true,
    vegetarianFriendly: false,
    mapsQuery: 'Gyumon Halal Wagyu Ramen Shibuya Tokyo',
  ),
  EatsPlace(
    id: 'tk-naritaya',
    name: 'Naritaya',
    city: 'Tokyo',
    area: 'Asakusa',
    categoryEmoji: '🍜',
    category: LText('Helal Ramen', 'Halal Ramen'),
    description: LText(
      'Asakusa\'da helal tavuk bazlı ramen; müslüman dostu menü.',
      'Halal chicken-based ramen in Asakusa; Muslim-friendly menu.',
    ),
    priceBand: '¥1,200–2,500',
    rating: 4.5,
    halal: true,
    vegetarianFriendly: false,
    mapsQuery: 'Naritaya Halal Ramen Asakusa Tokyo',
  ),
  EatsPlace(
    id: 'tk-wagyu-halal-vegan',
    name: 'Wagyu Halal & Vegan Burger',
    city: 'Tokyo',
    area: 'Shibuya',
    categoryEmoji: '🍔',
    category: LText('Helal / Vegan Burger', 'Halal / Vegan Burger'),
    description: LText(
      'Helal wagyu burger; vegan seçenekleri de var. Sulu, kalın patty.',
      'Halal wagyu burger; vegan options too. Juicy, thick patty.',
    ),
    priceBand: '¥1,500–2,500',
    rating: 4.9,
    halal: true,
    vegetarianFriendly: true,
    mapsQuery: 'Wagyu Halal Vegan Steak Hamburger Tokyo',
  ),
  EatsPlace(
    id: 'tk-gyukatsu-motomura',
    name: 'Gyukatsu Motomura',
    city: 'Tokyo',
    area: 'Shinjuku',
    categoryEmoji: '🥩',
    category: LText('Gyukatsu', 'Gyukatsu'),
    description: LText(
      'Kızarmış dana pane; masada taş üstünde pişirilir. Kuyruk olabilir.',
      'Breaded beef cutlet grilled on a hot stone at your table. Expect a queue.',
    ),
    priceBand: '¥1,500–2,500',
    rating: 4.4,
    halal: false,
    vegetarianFriendly: false,
    mapsQuery: 'Gyukatsu Motomura Shinjuku Tokyo',
  ),
  EatsPlace(
    id: 'tk-coco-ichibanya',
    name: 'CoCo Ichibanya',
    city: 'Tokyo',
    area: 'Zincir',
    categoryEmoji: '🍛',
    category: LText('Japon Körisi', 'Japanese Curry'),
    description: LText(
      'Vejetaryen köri seçeneği sunan güvenilir zincir; acılık ayarlanır.',
      'Reliable chain with a vegetarian curry option; adjustable spice level.',
    ),
    priceBand: '¥900–1,600',
    rating: 4.0,
    halal: false,
    vegetarianFriendly: true,
    mapsQuery: 'CoCo Ichibanya vegetarian curry Tokyo',
  ),

  // --- Osaka ---------------------------------------------------------------
  EatsPlace(
    id: 'os-okonomiyaki-kiji',
    name: 'Okonomiyaki Kiji',
    city: 'Osaka',
    area: 'Umeda',
    categoryEmoji: '🥞',
    category: LText('Okonomiyaki', 'Okonomiyaki'),
    description: LText(
      'Umeda\'da efsane okonomiyaki. Yerel favori; öğle kuyruğu uzayabilir.',
      'Legendary okonomiyaki in Umeda. Local favorite; lunch queues can grow.',
    ),
    priceBand: '¥800–1,800',
    rating: 4.5,
    halal: false,
    vegetarianFriendly: false,
    mapsQuery: 'Okonomiyaki Kiji Umeda Osaka',
  ),
  EatsPlace(
    id: 'os-kobe-aburi-bokujo',
    name: 'Kobe Aburi Bokujo',
    city: 'Osaka',
    area: 'Umeda',
    categoryEmoji: '🥩',
    category: LText('Yakiniku / Kobe', 'Yakiniku / Kobe'),
    description: LText(
      'Umeda\'da Kobe sığırı yakiniku. Özel gün için ideal; rezervasyon önerilir.',
      'Kobe beef yakiniku in Umeda. Great for a special night; book ahead.',
    ),
    priceBand: '¥3,000–6,000',
    rating: 4.5,
    halal: false,
    vegetarianFriendly: false,
    mapsQuery: 'Kobe Aburi Bokujo Umeda Osaka',
  ),

  // --- Kyoto ---------------------------------------------------------------
  EatsPlace(
    id: 'ky-towzen',
    name: 'Towzen',
    city: 'Kyoto',
    area: 'Nakagyo',
    categoryEmoji: '🍜',
    category: LText('Vegan Ramen', 'Vegan Ramen'),
    description: LText(
      'Bitkisel bazlı vegan ramen; et/balık sosu (dashi) yok.',
      'Plant-based vegan ramen; no meat or fish stock (dashi).',
    ),
    priceBand: '¥1,000–2,000',
    rating: 4.4,
    halal: false,
    vegetarianFriendly: true,
    mapsQuery: 'Towzen vegan ramen Kyoto',
  ),
];
