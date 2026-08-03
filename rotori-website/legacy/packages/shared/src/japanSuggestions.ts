export interface PlaceSuggestion {
  id: string;
  name: string;
  city: string;
  emoji: string;
  category: 'culture' | 'nature' | 'food' | 'fun' | 'shopping' | 'transport';
  typicalSteps?: number;
  bestForDayTheme?: string;
  /** Küratörlü puan (yoksa id'den türetilir) */
  rating?: number;
  /** Çocuk dostu (yoksa kategoriden türetilir) */
  kidFriendly?: boolean;
}

export const JAPAN_POPULAR: PlaceSuggestion[] = [
  { id: 'sensoji', name: 'Senso-ji Asakusa', city: 'Tokyo', emoji: '⛩️', category: 'culture', typicalSteps: 8000, bestForDayTheme: 'Asakusa & tapınak' },
  { id: 'skytree', name: 'Tokyo Skytree', city: 'Tokyo', emoji: '🗼', category: 'fun', typicalSteps: 12000 },
  { id: 'shibuya', name: 'Shibuya Sky & Crossing', city: 'Tokyo', emoji: '📸', category: 'fun', typicalSteps: 15000 },
  { id: 'meiji', name: 'Meiji Jingu', city: 'Tokyo', emoji: '🌳', category: 'culture', typicalSteps: 9000 },
  { id: 'teamlab', name: 'teamLab Planets', city: 'Tokyo', emoji: '🪐', category: 'fun', typicalSteps: 11000 },
  { id: 'disney', name: 'Tokyo Disneyland', city: 'Tokyo', emoji: '🏰', category: 'fun', typicalSteps: 22000 },
  { id: 'dotonbori', name: 'Dotonbori', city: 'Osaka', emoji: '🐙', category: 'food', typicalSteps: 10000 },
  { id: 'usj', name: 'Universal Studios Japan', city: 'Osaka', emoji: '🎢', category: 'fun', typicalSteps: 20000 },
  { id: 'fushimi', name: 'Fushimi Inari', city: 'Kyoto', emoji: '⛩️', category: 'culture', typicalSteps: 14000 },
  { id: 'nara', name: 'Nara Park & Todai-ji', city: 'Nara', emoji: '🦌', category: 'nature', typicalSteps: 16000 },
  { id: 'osaka-castle', name: 'Osaka Kalesi', city: 'Osaka', emoji: '🏯', category: 'culture', typicalSteps: 12000 },
  { id: 'kuromon', name: 'Kuromon Market', city: 'Osaka', emoji: '🍣', category: 'food', typicalSteps: 8000 },
];

export interface DayTemplate {
  id: string;
  label: string;
  theme: string;
  emoji: string;
  places: string[];
  stepsEstimate: number;
}

/**
 * Hap bilgiler — Japonya gezisinde gün gün küçük pratik uyarılar.
 * Viewer DayCard altında rotasyonla gösterilir.
 */
export const JAPAN_TIPS: string[] = [
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

export const JAPAN_DAY_TEMPLATES: DayTemplate[] = [
  { id: 'tokyo-arrival', label: 'Varış günü', theme: "Tokyo'ya varış & check-in", emoji: '🛬', places: [], stepsEstimate: 5000 },
  { id: 'asakusa-skytree', label: 'Asakusa + Skytree', theme: 'Asakusa & Skytree', emoji: '🗼', places: ['sensoji', 'skytree'], stepsEstimate: 15000 },
  { id: 'shibuya', label: 'Shibuya günü', theme: 'Shibuya & Harajuku', emoji: '🌸', places: ['meiji', 'shibuya'], stepsEstimate: 16000 },
  { id: 'disney-day', label: 'Disneyland', theme: 'Tokyo Disneyland', emoji: '🏰', places: ['disney'], stepsEstimate: 22000 },
  { id: 'osaka-move', label: 'Osaka geçiş', theme: "Shinkansen & Dotonbori", emoji: '🚄', places: ['dotonbori'], stepsEstimate: 11000 },
  { id: 'kyoto-day', label: 'Kyoto günübirlik', theme: 'Kyoto & Fushimi Inari', emoji: '⛩️', places: ['fushimi'], stepsEstimate: 18000 },
  { id: 'nara-day', label: 'Nara günübirlik', theme: 'Nara turu', emoji: '🦌', places: ['nara'], stepsEstimate: 16000 },
];
