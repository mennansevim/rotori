// Japonya destinasyon profili — profiles.ts (JP) + japanSuggestions.ts + dietary.ts birebir.

class Cuisine {
  const Cuisine(this.id, this.label, this.emoji);
  final String id;
  final String label;
  final String emoji;
}

class DietaryOption {
  const DietaryOption(this.id, this.label, this.emoji, this.description);
  final String id;
  final String label;
  final String emoji;
  final String description;
}

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.id,
    required this.name,
    required this.city,
    required this.emoji,
    required this.category,
    this.typicalSteps,
    this.bestForDayTheme,
  });
  final String id;
  final String name;
  final String city;
  final String emoji;
  final String category; // culture | fun | food | nature
  final int? typicalSteps;
  final String? bestForDayTheme;
}

const String kJpFlag = '🇯🇵';
const String kJpCurrency = 'JPY';

const List<Cuisine> kJpCuisines = [
  Cuisine('ramen', 'Ramen', '🍜'),
  Cuisine('sushi', 'Sushi / sashimi', '🍣'),
  Cuisine('izakaya', 'Izakaya', '🍶'),
  Cuisine('matcha', 'Matcha & tatlı', '🍵'),
  Cuisine('yakiniku', 'Yakiniku', '🥩'),
  Cuisine('street', 'Konbini / sokak', '🏪'),
];

const List<String> kJpDishes = [
  'Tonkotsu veya shoyu ramen',
  'Nigiri sushi & omakase',
  'Okonomiyaki (Osaka)',
  'Takoyaki',
  'Wagyu yakiniku',
  'Onigiri & konbini kahvaltısı',
  'Matcha latte & mochi',
  'Udon / soba',
  'Yakitori',
  'Kaiseki (özel gün)',
];

/// JP dietaryOptionIds: no_pork, seafood_ok, meat_ok (dietary.ts).
const List<DietaryOption> kJpDietaryOptions = [
  DietaryOption('no_pork', 'Domuz yok', '🐷', 'Domuz eti ve domuz yağı içermesin'),
  DietaryOption('seafood_ok', 'Deniz ürünü sever', '🦐', 'Sushi, sashimi, deniz ürünleri uygun'),
  DietaryOption('meat_ok', 'Et sever', '🥩', 'Wagyu, yakiniku, et ağırlıklı menüler'),
];

const List<PlaceSuggestion> kJapanPopular = [
  PlaceSuggestion(id: 'sensoji', name: 'Senso-ji Asakusa', city: 'Tokyo', emoji: '⛩️', category: 'culture', typicalSteps: 8000, bestForDayTheme: 'Asakusa & tapınak'),
  PlaceSuggestion(id: 'skytree', name: 'Tokyo Skytree', city: 'Tokyo', emoji: '🗼', category: 'fun', typicalSteps: 12000),
  PlaceSuggestion(id: 'shibuya', name: 'Shibuya Sky & Crossing', city: 'Tokyo', emoji: '📸', category: 'fun', typicalSteps: 15000),
  PlaceSuggestion(id: 'meiji', name: 'Meiji Jingu', city: 'Tokyo', emoji: '🌳', category: 'culture', typicalSteps: 9000),
  PlaceSuggestion(id: 'teamlab', name: 'teamLab Planets', city: 'Tokyo', emoji: '🪐', category: 'fun', typicalSteps: 11000),
  PlaceSuggestion(id: 'disney', name: 'Tokyo Disneyland', city: 'Tokyo', emoji: '🏰', category: 'fun', typicalSteps: 22000),
  PlaceSuggestion(id: 'dotonbori', name: 'Dotonbori', city: 'Osaka', emoji: '🐙', category: 'food', typicalSteps: 10000),
  PlaceSuggestion(id: 'usj', name: 'Universal Studios Japan', city: 'Osaka', emoji: '🎢', category: 'fun', typicalSteps: 20000),
  PlaceSuggestion(id: 'fushimi', name: 'Fushimi Inari', city: 'Kyoto', emoji: '⛩️', category: 'culture', typicalSteps: 14000),
  PlaceSuggestion(id: 'nara', name: 'Nara Park & Todai-ji', city: 'Nara', emoji: '🦌', category: 'nature', typicalSteps: 16000),
  PlaceSuggestion(id: 'osaka-castle', name: 'Osaka Kalesi', city: 'Osaka', emoji: '🏯', category: 'culture', typicalSteps: 12000),
  PlaceSuggestion(id: 'kuromon', name: 'Kuromon Market', city: 'Osaka', emoji: '🍣', category: 'food', typicalSteps: 8000),
];
