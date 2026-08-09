// TypeScript packages/shared/src/japanSuggestions.ts'in Dart karşılığı.
// Japonya POI/mekan veritabanı + gün şablonları — generator ve fillEmptyDays
// tarafından kullanılır. Veriler birebir (isim, koordinat, tag) porttur.

import 'types.dart';

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
    this.openHour,
    this.closeHour,
    this.durationMin,
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

  /// Çalışma saatleri (0-24). null = "gün boyu açık" varsayılır ve yalnızca
  /// genel planlama penceresi (09:00-20:00) uygulanır. Erken kapanan yerler
  /// (pazarlar) ya da geç açan yerler burada işaretlenir; üretici bir yeri
  /// ancak açık olduğu saate yerleştirebiliyorsa seçer.
  final int? openHour;
  final int? closeHour;

  /// Yerde geçirilen tipik süre (dk). null → kDefaultActivityMinutes.
  final int? durationMin;

  /// Bu yerin gerçekten ziyaret edilebileceği dakika aralığı — kendi çalışma
  /// saati ile genel planlama penceresinin kesişimi. [start, end)
  (int start, int end) visitWindow(int dayStart, int dayEnd) {
    final open = (openHour ?? 0) * 60;
    final close = (closeHour ?? 24) * 60;
    return (
      open > dayStart ? open : dayStart,
      close < dayEnd ? close : dayEnd,
    );
  }
}

/// Bir mekanın günü ne kadar kapladığı.
/// - full: TÜM gün (Disney, USJ) — başka aktivite yok.
/// - half: YARIM gün (teamLab) — en fazla 1 ek aktivite + öğün.
/// - normal: standart slot.
enum PlaceCoverage { normal, half, full }

/// Sabit ID → coverage. Generator picked place'lerde bunu kontrol eder.
PlaceCoverage coverageOfPlaceId(String id) {
  switch (id) {
    case 'disney':
    case 'usj':
      return PlaceCoverage.full;
    case 'teamlab':
      return PlaceCoverage.half;
    default:
      return PlaceCoverage.normal;
  }
}

/// SAATLİ GİRİŞ — bileti belirli bir saat dilimine kesilen yerler.
///
/// teamLab Planets zaman aralıklı giriş satar; Disneyland/DisneySea ve USJ
/// için de park giriş saati + önceden alınan Express/timed pass vardır.
/// Rota optimizasyonu (hava durumuna göre yeniden dizme dahil) bu öğelerin
/// SAATİNİ DEĞİŞTİREMEZ — kullanıcının elindeki bilet geçersiz olur.
///
/// Kullanım: [isTimeLocked] — öğenin kendi kilidiyle birleştirir.
bool isTimedEntryTitle(String title) {
  final t = title.toLowerCase();
  return t.contains('teamlab') ||
      t.contains('team lab') ||
      t.contains('disneyland') ||
      t.contains('disneysea') ||
      t.contains('disney sea') ||
      t.contains('universal studios') ||
      t.contains('usj');
}

/// Bu öğe rota optimizasyonunda SAATİ/GÜNÜ değiştirilebilir mi?
///
/// İki kaynağı birleştirir:
///  • Öğenin kendi kilidi (`isFixed`) — kullanıcı kilitlediyse ya da üretici
///    ticketedEvent olarak işaretlediyse.
///  • Başlıktan türetme — bu kilit eklenmeden ÖNCE kaydedilmiş planlar da
///    korunsun diye (mevcut kullanıcıların teamLab/Disney günleri bozulmasın).
bool isTimeLocked(TimelineItem item) =>
    item.isFixed || isTimedEntryTitle(item.title);

/// Bir TimelineItem başlığından coverage çıkarır. fillEmptyDays ve
/// post-processor buradan okur (title anahtar/ID'den bağımsız kalabilir).
PlaceCoverage coverageOfTitle(String title) {
  final t = title.toLowerCase();
  if (t.contains('disneyland') ||
      t.contains('disneysea') ||
      t.contains('disney sea')) {
    return PlaceCoverage.full;
  }
  if (t.contains('universal studios') || t.contains('usj')) {
    return PlaceCoverage.full;
  }
  if (t.contains('teamlab') || t.contains('team lab')) {
    return PlaceCoverage.half;
  }
  return PlaceCoverage.normal;
}

const List<PlaceSuggestion> kJapanPopular = [
  PlaceSuggestion(id: 'sensoji', name: 'Senso-ji Asakusa', city: 'Tokyo', emoji: '⛩️', category: 'culture', typicalSteps: 8000, openHour: 6, closeHour: 17, bestForDayTheme: 'Asakusa & tapınak',
      imageUrl: 'https://images.unsplash.com/photo-1583400400287-ec8bdcc4b91b?w=400&q=60'),
  PlaceSuggestion(id: 'skytree', name: 'Tokyo Skytree', city: 'Tokyo', emoji: '🗼', category: 'fun', typicalSteps: 12000, openHour: 10, closeHour: 21,
      imageUrl: 'https://images.unsplash.com/photo-1554797589-7241bb691973?w=400&q=60'),
  PlaceSuggestion(id: 'shibuya', name: 'Shibuya Sky & Crossing', city: 'Tokyo', emoji: '📸', category: 'fun', typicalSteps: 15000, openHour: 10, closeHour: 22,
      imageUrl: 'https://images.unsplash.com/photo-1542051841857-5f90071e7989?w=400&q=60'),
  PlaceSuggestion(id: 'meiji', name: 'Meiji Jingu', city: 'Tokyo', emoji: '🌳', category: 'culture', typicalSteps: 9000, openHour: 6, closeHour: 17,
      imageUrl: 'https://images.unsplash.com/photo-1522547902298-51566e4fb383?w=400&q=60'),
  PlaceSuggestion(id: 'teamlab', name: 'teamLab Planets', city: 'Tokyo', emoji: '🪐', category: 'fun', typicalSteps: 11000, openHour: 9, closeHour: 21,
      imageUrl: 'https://images.unsplash.com/photo-1567013127542-490d757e51fc?w=400&q=60'),
  PlaceSuggestion(id: 'disney', name: 'Tokyo Disneyland', city: 'Tokyo', emoji: '🏰', category: 'fun', typicalSteps: 22000, openHour: 9, closeHour: 21,
      imageUrl: 'https://images.unsplash.com/photo-1624601573012-efb68931cc8f?w=400&q=60'),
  PlaceSuggestion(id: 'dotonbori', name: 'Dotonbori', city: 'Osaka', emoji: '🐙', category: 'food', typicalSteps: 10000, openHour: 11, closeHour: 23,
      imageUrl: 'https://images.unsplash.com/photo-1590559899731-a382839e5549?w=400&q=60'),
  PlaceSuggestion(id: 'usj', name: 'Universal Studios Japan', city: 'Osaka', emoji: '🎢', category: 'fun', typicalSteps: 20000, openHour: 9, closeHour: 21,
      imageUrl: 'https://images.unsplash.com/photo-1526318472351-c75fcf070305?w=400&q=60'),
  PlaceSuggestion(id: 'fushimi', name: 'Fushimi Inari', city: 'Kyoto', emoji: '⛩️', category: 'culture', typicalSteps: 14000, openHour: 0, closeHour: 24,
      imageUrl: 'https://images.unsplash.com/photo-1478436127897-769e1538f1a2?w=400&q=60'),
  PlaceSuggestion(id: 'nara', name: 'Nara Park & Todai-ji', city: 'Nara', emoji: '🦌', category: 'nature', typicalSteps: 16000, openHour: 8, closeHour: 17,
      imageUrl: 'https://images.unsplash.com/photo-1580100482008-c410e58c58af?w=400&q=60'),
  PlaceSuggestion(id: 'osaka-castle', name: 'Osaka Kalesi', city: 'Osaka', emoji: '🏯', category: 'culture', typicalSteps: 12000, openHour: 9, closeHour: 17,
      imageUrl: 'https://images.unsplash.com/photo-1590253230532-a67f6bc61b1e?w=400&q=60'),
  PlaceSuggestion(id: 'kuromon', name: 'Kuromon Market', city: 'Osaka', emoji: '🍣', category: 'food', typicalSteps: 8000, openHour: 9, closeHour: 17,
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
    this.city = '',
  });

  final String id;

  /// Şablonun ait olduğu şehir — generator günün şehrine göre filtreler
  /// (boş = şehir-bağımsız).
  final String city;

  /// i18n anahtarı (prefix `tmpl.`) — `L10n.resolve(label, lang)` ile çözülür.
  final String label;

  /// i18n anahtarı (prefix `tmpl.`) — `L10n.resolve(theme, lang)` ile çözülür.
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

// NOT: `label` ve `theme` alanları i18n anahtarıdır (prefix `tmpl.`); generator
// bunları `L10n.resolve(...)` ile seçili dile çözer. `id`, `emoji`, `places`,
// `stepsEstimate` sabit kalır. Özel isim içeren temalarda tr==en.
const List<DayTemplate> kJapanDayTemplates = [
  DayTemplate(id: 'tokyo-arrival', label: 'tmpl.tokyoArrival.label', theme: 'tmpl.tokyoArrival.theme', emoji: '🛬', places: [], stepsEstimate: 5000, city: 'Tokyo'),
  DayTemplate(id: 'asakusa-skytree', label: 'tmpl.asakusaSkytree.label', theme: 'tmpl.asakusaSkytree.theme', emoji: '🗼', places: ['sensoji', 'skytree'], stepsEstimate: 15000, city: 'Tokyo'),
  DayTemplate(id: 'shibuya', label: 'tmpl.shibuya.label', theme: 'tmpl.shibuya.theme', emoji: '🌸', places: ['meiji', 'shibuya'], stepsEstimate: 16000, city: 'Tokyo'),
  DayTemplate(id: 'disney-day', label: 'tmpl.disney.label', theme: 'tmpl.disney.theme', emoji: '🏰', places: ['disney'], stepsEstimate: 22000, city: 'Tokyo'),
  DayTemplate(id: 'teamlab-day', label: 'tmpl.teamlabDay.label', theme: 'tmpl.teamlabDay.theme', emoji: '🪐', places: ['teamlab'], stepsEstimate: 10000, city: 'Tokyo'),
  DayTemplate(id: 'osaka-move', label: 'tmpl.osakaMove.label', theme: 'tmpl.osakaMove.theme', emoji: '🚄', places: ['dotonbori'], stepsEstimate: 11000, city: 'Osaka'),
  DayTemplate(id: 'usj-day', label: 'tmpl.usjDay.label', theme: 'tmpl.usjDay.theme', emoji: '🎢', places: ['usj'], stepsEstimate: 20000, city: 'Osaka'),
  DayTemplate(id: 'kyoto-day', label: 'tmpl.kyotoDay.label', theme: 'tmpl.kyotoDay.theme', emoji: '⛩️', places: ['fushimi'], stepsEstimate: 18000, city: 'Kyoto'),
  DayTemplate(id: 'nara-day', label: 'tmpl.naraDay.label', theme: 'tmpl.naraDay.theme', emoji: '🦌', places: ['nara'], stepsEstimate: 16000, city: 'Nara'),
];
