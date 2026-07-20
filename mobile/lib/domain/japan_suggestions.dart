// TypeScript packages/shared/src/japanSuggestions.ts'in Dart karşılığı.
// Japonya POI/mekan veritabanı + gün şablonları — generator ve fillEmptyDays
// tarafından kullanılır. Veriler birebir (isim, koordinat, tag) porttur.

/// Öneri mekan kaydı.
/// [category] TS union karşılığı string:
/// 'culture' | 'nature' | 'food' | 'fun' | 'shopping' | 'transport'.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.id,
    required this.name,
    required this.city,
    required this.emoji,
    required this.category,
    this.typicalSteps,
    this.bestForDayTheme,
    this.rating,
    this.kidFriendly,
    this.imageUrl,
  });

  final String id;
  final String name;
  final String city;
  final String emoji;
  final String category;
  final int? typicalSteps;
  final String? bestForDayTheme;

  /// Küratörlü puan (yoksa id'den türetilir — bkz. explore.placeRating).
  final double? rating;

  /// Çocuk dostu (yoksa kategoriden türetilir — bkz. explore.isKidFriendly).
  final bool? kidFriendly;

  /// Kart görseli (public Unsplash/Wikimedia URL). Yoksa emoji fallback.
  final String? imageUrl;
}

const List<PlaceSuggestion> kJapanPopular = [
  PlaceSuggestion(id: 'sensoji', name: 'Senso-ji Asakusa', city: 'Tokyo', emoji: '⛩️', category: 'culture', typicalSteps: 8000, bestForDayTheme: 'Asakusa & tapınak',
      imageUrl: 'https://images.unsplash.com/photo-1583400400287-ec8bdcc4b91b?w=400&q=60'),
  PlaceSuggestion(id: 'skytree', name: 'Tokyo Skytree', city: 'Tokyo', emoji: '🗼', category: 'fun', typicalSteps: 12000,
      imageUrl: 'https://images.unsplash.com/photo-1554797589-7241bb691973?w=400&q=60'),
  PlaceSuggestion(id: 'shibuya', name: 'Shibuya Sky & Crossing', city: 'Tokyo', emoji: '📸', category: 'fun', typicalSteps: 15000,
      imageUrl: 'https://images.unsplash.com/photo-1542051841857-5f90071e7989?w=400&q=60'),
  PlaceSuggestion(id: 'meiji', name: 'Meiji Jingu', city: 'Tokyo', emoji: '🌳', category: 'culture', typicalSteps: 9000,
      imageUrl: 'https://images.unsplash.com/photo-1522547902298-51566e4fb383?w=400&q=60'),
  PlaceSuggestion(id: 'teamlab', name: 'teamLab Planets', city: 'Tokyo', emoji: '🪐', category: 'fun', typicalSteps: 11000,
      imageUrl: 'https://images.unsplash.com/photo-1567013127542-490d757e51fc?w=400&q=60'),
  PlaceSuggestion(id: 'disney', name: 'Tokyo Disneyland', city: 'Tokyo', emoji: '🏰', category: 'fun', typicalSteps: 22000,
      imageUrl: 'https://images.unsplash.com/photo-1624601573012-efb68931cc8f?w=400&q=60'),
  PlaceSuggestion(id: 'dotonbori', name: 'Dotonbori', city: 'Osaka', emoji: '🐙', category: 'food', typicalSteps: 10000,
      imageUrl: 'https://images.unsplash.com/photo-1590559899731-a382839e5549?w=400&q=60'),
  PlaceSuggestion(id: 'usj', name: 'Universal Studios Japan', city: 'Osaka', emoji: '🎢', category: 'fun', typicalSteps: 20000,
      imageUrl: 'https://images.unsplash.com/photo-1526318472351-c75fcf070305?w=400&q=60'),
  PlaceSuggestion(id: 'fushimi', name: 'Fushimi Inari', city: 'Kyoto', emoji: '⛩️', category: 'culture', typicalSteps: 14000,
      imageUrl: 'https://images.unsplash.com/photo-1478436127897-769e1538f1a2?w=400&q=60'),
  PlaceSuggestion(id: 'nara', name: 'Nara Park & Todai-ji', city: 'Nara', emoji: '🦌', category: 'nature', typicalSteps: 16000,
      imageUrl: 'https://images.unsplash.com/photo-1580100482008-c410e58c58af?w=400&q=60'),
  PlaceSuggestion(id: 'osaka-castle', name: 'Osaka Kalesi', city: 'Osaka', emoji: '🏯', category: 'culture', typicalSteps: 12000,
      imageUrl: 'https://images.unsplash.com/photo-1590253230532-a67f6bc61b1e?w=400&q=60'),
  PlaceSuggestion(id: 'kuromon', name: 'Kuromon Market', city: 'Osaka', emoji: '🍣', category: 'food', typicalSteps: 8000,
      imageUrl: 'https://images.unsplash.com/photo-1580442151529-343f2f6e0e27?w=400&q=60'),
];

/// Hazır gün şablonu — places alanı PlaceSuggestion id listesi.
class DayTemplate {
  const DayTemplate({
    required this.id,
    required this.label,
    required this.theme,
    required this.emoji,
    required this.places,
    required this.stepsEstimate,
  });

  final String id;
  final String label;
  final String theme;
  final String emoji;
  final List<String> places;
  final int stepsEstimate;
}

/// Hap bilgiler — Japonya gezisinde gün gün küçük pratik uyarılar.
/// Viewer DayCard altında rotasyonla gösterilir.
const List<String> kJapanTips = [
  'Japonya’da bazı küçük restoranlar sadece nakit kabul edebilir — yanına ~5000¥ nakit al.',
  'Metroda büyük valizle yoğun saatlerde hareket etmek zor olabilir — 07:30–09:30 ve 17:30–19:30 arası kalabalık.',
  'Tapınak ve shrine alanlarında erken saatler (08:00–09:00) çok daha sakin olur.',
  'Çocukla geziyorsan öğleden sonra 1 uzun mola planlamak iyi olur — Japon parkları ideal.',
  'Don Quijote gece geç saatlere kadar açık ama bazı şubeler 24/7 değil — kontrol et.',
  'Tax-free alışverişte pasaport yanında olmalı; 5000¥ üstü harcamada uygulanır.',
  'Bazı popüler restoranlarda sıra beklemek normaldir — 30 dk kuyruk standart.',
  'Japonya’da sokakta çöp kutusu bulmak zor — küçük poşet taşımak faydalıdır.',
  'JR Pass otelden alınamaz; Japonya’ya gitmeden online sipariş edip değişim kuponu al.',
  'Suica/Pasmo kartına 1000¥ koy, biten yerini istasyonda yükle — konbini’de de yükleyebilirsin.',
  'Yamato ile valiz gönderim genelde ertesi gün; uzak şehre 2 gün sürebilir.',
  'Vending machine her köşede — soğuk/sıcak içecek 130–180¥ arası.',
  'Çoğu Japon banyosunda terlik vardır — ayrı tuvalet terliği unutma.',
  'IC kart (Suica/Pasmo) hem metro hem konbini’de geçer; cüzdana koyma, tek kullanım kartı taşı.',
  'Wi-Fi’ı önceden eSIM ile çöz — istasyonlarda ücretsiz olanlar yavaş.',
];

const List<DayTemplate> kJapanDayTemplates = [
  DayTemplate(id: 'tokyo-arrival', label: 'Varış günü', theme: "Tokyo'ya varış & check-in", emoji: '🛬', places: [], stepsEstimate: 5000),
  DayTemplate(id: 'asakusa-skytree', label: 'Asakusa + Skytree', theme: 'Asakusa & Skytree', emoji: '🗼', places: ['sensoji', 'skytree'], stepsEstimate: 15000),
  DayTemplate(id: 'shibuya', label: 'Shibuya günü', theme: 'Shibuya & Harajuku', emoji: '🌸', places: ['meiji', 'shibuya'], stepsEstimate: 16000),
  DayTemplate(id: 'disney-day', label: 'Disneyland', theme: 'Tokyo Disneyland', emoji: '🏰', places: ['disney'], stepsEstimate: 22000),
  DayTemplate(id: 'osaka-move', label: 'Osaka geçiş', theme: 'Shinkansen & Dotonbori', emoji: '🚄', places: ['dotonbori'], stepsEstimate: 11000),
  DayTemplate(id: 'kyoto-day', label: 'Kyoto günübirlik', theme: 'Kyoto & Fushimi Inari', emoji: '⛩️', places: ['fushimi'], stepsEstimate: 18000),
  DayTemplate(id: 'nara-day', label: 'Nara günübirlik', theme: 'Nara turu', emoji: '🦌', places: ['nara'], stepsEstimate: 16000),
];
