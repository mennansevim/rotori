// Popüler yerler için küratörlü rehber bilgisi:
// fotoğraflar (kaydırma için), ortalama ziyaret süresi, ön rezervasyon
// penceresi, günün en iyi zamanı, ortalama puan ve ziyaretçi ipuçları.
//
// PlaceGuide `matchPlaceGuide(title)` ile item başlığındaki anahtar kelimeler
// üzerinden çözülür. Eşleşme yoksa null döner — sheet fallback UI'ye düşer.
//
// Görsel URL'leri Wikimedia Commons'tan alınmıştır ve 960px thumb formatında
// tek tek doğrulanmıştır (Wikimedia yalnız 250/500/960/1280px sunar —
// başka genişlik 400 döndürür, değiştirme).
//
// Kullanıcıya görünen serbest metinler (brief, tips, bestTimeOfDay,
// bookingHint) iki dillidir: `LText(tr, en)` — bkz. localized_text.dart.

import 'localized_text.dart';

class PlaceGuide {
  const PlaceGuide({
    required this.id,
    required this.matches,
    required this.imageUrls,
    required this.visitDurationMin,
    required this.bestTimeOfDay,
    required this.brief,
    required this.tips,
    this.advanceBookingDays,
    this.averageRating,
    this.reviewCount,
    this.bookingHint,
  });

  final String id;

  /// Başlıkta aranan lowercased anahtar kelimeler (herhangi biri eşleşirse).
  final List<String> matches;

  /// Kaydırılabilir fotoğraf listesi (Wikimedia Commons, 960px, doğrulanmış).
  final List<String> imageUrls;

  /// Ortalama ziyaret süresi (dakika).
  final int visitDurationMin;

  /// "Sabah erken", "Öğleden sonra" gibi kısa öneri (TR+EN).
  final LText bestTimeOfDay;

  /// Bir paragraflık faydalı özet — ne için ünlü, ne beklenir (TR+EN).
  final LText brief;

  /// Ziyaretçi ipuçları listesi (kısa cümleler, TR+EN).
  final List<LText> tips;

  /// Bilet kaç gün önceden alınmalı (null ise gerekmez).
  final int? advanceBookingDays;

  /// 0..5 arası ortalama puan (bilinen halka açık istatistiklerden).
  final double? averageRating;

  /// Ortalama puanın kaç yoruma dayandığı (yaklaşık).
  final int? reviewCount;

  /// Rezervasyon platform ipucu ("Klook", "Smart-EX" vb., TR+EN).
  final LText? bookingHint;
}

const List<PlaceGuide> _kGuides = [
  // ── Tokyo ────────────────────────────────────────────────────────────────
  PlaceGuide(
    id: 'sensoji',
    matches: ['senso-ji', 'sensoji', 'senso ji', 'asakusa'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/4/43/Sensoji_2023.jpg/960px-Sensoji_2023.jpg',
      'https://upload.wikimedia.org/wikipedia/commons/thumb/8/81/Day2-2_%2840909714314%29.jpg/960px-Day2-2_%2840909714314%29.jpg',
      'https://upload.wikimedia.org/wikipedia/commons/thumb/f/f2/Asakusa_Nakamise_-01.jpg/960px-Asakusa_Nakamise_-01.jpg',
    ],
    visitDurationMin: 90,
    bestTimeOfDay: LText(
      'Sabah 07:00–09:00 (kalabalıksız kareler)',
      'Morning 07:00–09:00 (crowd-free shots)',
    ),
    brief: LText(
      'Tokyo\'nun en eski Budist tapınağı (7. yy). Kaminarimon kapısı, '
      'Nakamise alışveriş caddesi ve ana pagoda başlıca duraklar. Giriş '
      'ücretsiz, dış alan 24 saat açık; ana salon 06:00–17:00 arası.',
      'Tokyo\'s oldest Buddhist temple (7th century). The Kaminarimon gate, '
      'Nakamise shopping street and the main pagoda are the key stops. Entry '
      'is free and the grounds are open 24 hours; the main hall is open '
      '06:00–17:00.',
    ),
    tips: [
      LText(
        'Sabah 08:00\'den önce fotoğraf için ideal; sonrasında yoğunlaşır.',
        'Best for photos before 08:00; it gets crowded after that.',
      ),
      LText(
        'Nakamise\'de melonpan ve ningyo-yaki (bebek şekilli tatlı) dene.',
        'Try melonpan and ningyo-yaki (doll-shaped cakes) along Nakamise.',
      ),
      LText(
        'Kaminarimon fenerinin dibinden fotoğraf çekmek için sıra oluşur.',
        'A queue forms to shoot from right under the Kaminarimon lantern.',
      ),
      LText(
        'Cebindeki 100¥\'la omikuji (fal) çekmek gelenek.',
        'Drawing an omikuji (paper fortune) with a spare 100¥ is a tradition.',
      ),
    ],
    averageRating: 4.5,
    reviewCount: 96000,
  ),
  PlaceGuide(
    id: 'skytree',
    matches: ['tokyo skytree', 'skytree'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/8/84/Tokyo_Skytree_2014_%E2%85%A2.jpg/960px-Tokyo_Skytree_2014_%E2%85%A2.jpg',
    ],
    visitDurationMin: 120,
    bestTimeOfDay: LText(
      'Gün batımı (16:30–18:00) — hem gündüz hem gece manzarası',
      'Sunset (16:30–18:00) — for both daytime and night views',
    ),
    brief: LText(
      '634m ile Japonya\'nın en yüksek yapısı. İki gözlem katı: Tembo Deck '
      '(350m) ve Tembo Galleria (450m). Alt katta Solamachi AVM ve akvaryum.',
      'At 634m, Japan\'s tallest structure. Two observation decks: Tembo Deck '
      '(350m) and Tembo Galleria (450m). The Solamachi mall and an aquarium '
      'sit at the base.',
    ),
    tips: [
      LText(
        'Kombine bilet (iki gözlem katı) tekli almaktan uygun.',
        'A combo ticket (both decks) is cheaper than buying them separately.',
      ),
      LText(
        'Hafta içi sabahları ya da yağmurlu günler sırasız girmek için iyi.',
        'Weekday mornings or rainy days are good for skipping the queue.',
      ),
      LText(
        'Fuji görebilmek için hava açık ve öğleden önce olmalı.',
        'To spot Mt. Fuji you need clear skies and a morning visit.',
      ),
      LText(
        'Solamachi\'de yerel restoranlar üst kattan uygun fiyatlı.',
        'Restaurants in Solamachi are cheaper than the ones up top.',
      ),
    ],
    advanceBookingDays: 30,
    averageRating: 4.4,
    reviewCount: 65000,
    bookingHint: LText(
      'Resmî site veya Klook — sezon önce doldurabilir.',
      'Official site or Klook — can sell out ahead in peak season.',
    ),
  ),
  PlaceGuide(
    id: 'teamlab',
    matches: ['teamlab', 'team lab', 'teamlab planets', 'teamlab borderless'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/6/69/At_teamLab_Planets_%2848277793276%29.jpg/960px-At_teamLab_Planets_%2848277793276%29.jpg',
      'https://upload.wikimedia.org/wikipedia/commons/thumb/8/80/At_teamLab_Planets_%2848277798316%29.jpg/960px-At_teamLab_Planets_%2848277798316%29.jpg',
      'https://upload.wikimedia.org/wikipedia/commons/thumb/f/ff/Photos_at_teamlab_planets_tokyo.jpg/960px-Photos_at_teamlab_planets_tokyo.jpg',
    ],
    visitDurationMin: 150,
    bestTimeOfDay: LText(
      'İlk seans (09:00–10:00) — kalabalıksız, sırasız',
      'First session (09:00–10:00) — no crowds, no queues',
    ),
    brief: LText(
      'Etkileşimli dijital sanat müzesi. Planets: çıplak ayak, ıslak alanlar var '
      '(paçası kıvrılabilen pantolon ya da şort uygun). Borderless '
      'Azabudai Hills\'te — daha büyük ve labirentimsi.',
      'An interactive digital art museum. Planets is barefoot with wet areas '
      '(roll-up trousers or shorts work best). Borderless, in Azabudai Hills, '
      'is larger and more maze-like.',
    ),
    tips: [
      LText(
        'Bilet saat-slotlu satılır; en az 3-4 hafta önceden al.',
        'Tickets are sold in timed slots; book at least 3–4 weeks ahead.',
      ),
      LText(
        'Ayna zeminler yansımalı — etek yerine pantolon tercih et.',
        'The mirrored floors are reflective — wear trousers rather than a skirt.',
      ),
      LText(
        'Çıplak ayak alanı var; büyük çanta locker\'a bırakılır.',
        'There is a barefoot area; large bags go into a locker.',
      ),
      LText(
        'Fotoğraf için karanlıkta parlayan salonlar en popüleri.',
        'The halls that glow in the dark are the most popular for photos.',
      ),
    ],
    advanceBookingDays: 30,
    averageRating: 4.6,
    reviewCount: 42000,
    bookingHint: LText(
      'teamLab resmî sitesi ya da Klook — cumartesi hızlıca dolar.',
      'teamLab official site or Klook — Saturdays fill up fast.',
    ),
  ),
  PlaceGuide(
    id: 'shibuya-crossing',
    matches: ['shibuya crossing', 'shibuya kavşak', 'shibuya sky', 'shibuya'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/8/88/Shibuya_Crossing%2C_Aerial.jpg/960px-Shibuya_Crossing%2C_Aerial.jpg',
      'https://upload.wikimedia.org/wikipedia/commons/thumb/4/45/SHIBUYA_SCRAMBLE_SQUARE_East_Tower.jpg/960px-SHIBUYA_SCRAMBLE_SQUARE_East_Tower.jpg',
    ],
    visitDurationMin: 90,
    bestTimeOfDay: LText(
      'Akşam 18:00–20:00 — hem kalabalık kavşak hem gece manzarası',
      'Evening 18:00–20:00 — for the packed crossing and the night view',
    ),
    brief: LText(
      'Dünyanın en yoğun yaya kavşağı — bir yeşil ışıkta ~3000 kişi. Shibuya '
      'Sky (229m) açık teraslı gözlem alanı, günbatımı için ünlü.',
      'The world\'s busiest pedestrian crossing — around 3,000 people per green '
      'light. Shibuya Sky (229m) is an open-air rooftop deck famous for sunset.',
    ),
    tips: [
      LText(
        'Kavşağı üstten görmek için Mag\'s Park ya da Shibuya Sky.',
        'For an overhead view of the crossing, try Mag\'s Park or Shibuya Sky.',
      ),
      LText(
        'Shibuya Sky bileti günü bulunmaz — 1-2 hafta önce al.',
        'Same-day Shibuya Sky tickets are hard to get — book 1–2 weeks ahead.',
      ),
      LText(
        'Hachiko heykelinden başla, kavşağı geç, sonra Sky\'a çık.',
        'Start at the Hachiko statue, cross the intersection, then head up to Sky.',
      ),
      LText(
        'Cuma-Cumartesi akşamı en kalabalık — foto için ideal.',
        'Friday and Saturday evenings are busiest — ideal for photos.',
      ),
    ],
    advanceBookingDays: 14,
    averageRating: 4.5,
    reviewCount: 58000,
    bookingHint: LText(
      'Shibuya Sky için Klook/JTB.',
      'Klook or JTB for Shibuya Sky.',
    ),
  ),
  PlaceGuide(
    id: 'meiji-jingu',
    matches: ['meiji jingu', 'meiji'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/8/8b/Meiji_Jingu_2023-3.jpg/960px-Meiji_Jingu_2023-3.jpg',
    ],
    visitDurationMin: 75,
    bestTimeOfDay: LText(
      'Sabah 08:00–10:00 — orman yolu serin ve sakin',
      'Morning 08:00–10:00 — the forest path is cool and calm',
    ),
    brief: LText(
      'İmparator Meiji\'ye adanmış Şinto tapınağı; Harajuku\'nun yanında dev '
      'bir koru içinde. Devasa torii kapıları ve sake fıçısı duvarı ünlü. '
      'Giriş ücretsiz, gün doğumu–gün batımı açık.',
      'A Shinto shrine dedicated to Emperor Meiji, set in a huge forest next to '
      'Harajuku. Famous for its giant torii gates and the wall of sake barrels. '
      'Free entry, open sunrise to sunset.',
    ),
    tips: [
      LText(
        'Hafta sonu sabahları geleneksel Şinto düğününe denk gelebilirsin.',
        'On weekend mornings you may catch a traditional Shinto wedding.',
      ),
      LText(
        'Ana yol çakıllı — rahat ayakkabı iyi olur.',
        'The main path is gravel — comfortable shoes help.',
      ),
      LText(
        'Harajuku/Takeshita caddesiyle aynı gün birleştir.',
        'Combine it with Harajuku / Takeshita Street on the same day.',
      ),
      LText(
        'Ema (dilek tahtası) yazmak için 500¥ ayır.',
        'Set aside 500¥ to write an ema (wishing plaque).',
      ),
    ],
    averageRating: 4.6,
    reviewCount: 75000,
  ),
  PlaceGuide(
    id: 'shinjuku-gyoen',
    matches: ['shinjuku gyoen', 'gyoen'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/9/9d/Shinjuku_Gyoen_National_Garden_-_sakura_3.JPG/960px-Shinjuku_Gyoen_National_Garden_-_sakura_3.JPG',
    ],
    visitDurationMin: 90,
    bestTimeOfDay: LText(
      'Sabah 09:00 açılış — piknik yerleri boşken',
      'At the 09:00 opening — while the picnic spots are still empty',
    ),
    brief: LText(
      'Tokyo\'nun en bakımlı parkı: Japon, İngiliz ve Fransız bahçeleri bir '
      'arada. Sakura mevsiminin en iyi noktalarından. Giriş 500¥, '
      'pazartesi kapalı.',
      'Tokyo\'s best-kept park, blending Japanese, English and French gardens. '
      'One of the top cherry-blossom spots. Entry 500¥, closed Mondays.',
    ),
    tips: [
      LText(
        'Alkol ve top oyunları yasak — sakin piknik parkı.',
        'Alcohol and ball games are banned — a calm picnic park.',
      ),
      LText(
        'Sakura sezonunda saat 10:00\'dan önce gir; kapıda sıra oluşur.',
        'In cherry-blossom season arrive before 10:00; queues form at the gate.',
      ),
      LText(
        'Sera (tropik bahçe) girişe dahil, kaçırma.',
        'The greenhouse (tropical garden) is included — don\'t miss it.',
      ),
      LText(
        'Shinjuku istasyonundan yürüme ~10 dk.',
        'About a 10-minute walk from Shinjuku Station.',
      ),
    ],
    averageRating: 4.5,
    reviewCount: 45000,
  ),
  PlaceGuide(
    id: 'akihabara',
    matches: ['akihabara', 'akiba'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/6/60/Sotokanda%2C_Akihabara_Electric_Town_at_night_20231114.png/960px-Sotokanda%2C_Akihabara_Electric_Town_at_night_20231114.png',
    ],
    visitDurationMin: 150,
    bestTimeOfDay: LText(
      'Öğleden sonra + akşam — neonlar karanlıkta iyi',
      'Afternoon into evening — the neon looks best after dark',
    ),
    brief: LText(
      'Elektronik ve otaku kültürünün merkezi: anime/manga mağazaları, retro '
      'oyun katları, maid kafeler ve gachapon salonları. Dükkanlar genelde '
      '11:00\'da açılır.',
      'The hub of electronics and otaku culture: anime/manga shops, retro game '
      'floors, maid cafés and gachapon arcades. Shops usually open around 11:00.',
    ),
    tips: [
      LText(
        'Retro oyun için Super Potato, figür için Radio Kaikan katları.',
        'Super Potato for retro games; the Radio Kaikan floors for figures.',
      ),
      LText(
        'Pazar günü ana cadde trafiğe kapanıyor (yaya cenneti).',
        'On Sundays the main street closes to traffic (a pedestrian paradise).',
      ),
      LText(
        'Tax-free alışveriş için pasaportunu yanında taşı.',
        'Carry your passport for tax-free shopping.',
      ),
      LText(
        'Gachapon Kaikan\'da yüzlerce kapsül makinesi var — bozukluk hazırla.',
        'Gachapon Kaikan has hundreds of capsule machines — bring coins.',
      ),
    ],
    averageRating: 4.4,
    reviewCount: 30000,
  ),
  PlaceGuide(
    id: 'tokyo-tower',
    matches: ['tokyo tower', 'tokyo kulesi'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/5/58/Tokyo_Tower_2023.jpg/960px-Tokyo_Tower_2023.jpg',
    ],
    visitDurationMin: 90,
    bestTimeOfDay: LText(
      'Akşam — kule turuncu aydınlatmayla en fotojenik',
      'Evening — the tower is most photogenic under its orange lights',
    ),
    brief: LText(
      '333m\'lik ikonik kızıl-beyaz kule (1958). Main Deck 150m, Top Deck '
      '250m. Skytree\'den daha nostaljik ve merkezi; Zojoji tapınağıyla '
      'aynı karede çekilir.',
      'The iconic 333m red-and-white tower (1958). Main Deck at 150m, Top Deck '
      'at 250m. More nostalgic and central than Skytree; it frames beautifully '
      'with Zojoji Temple.',
    ),
    tips: [
      LText(
        'Zojoji tapınağı tarafından kule + tapınak karesi klasik.',
        'The tower-and-temple shot from the Zojoji side is a classic.',
      ),
      LText(
        'Top Deck turu saatli ve rezervasyonlu; Main Deck genelde sırasız.',
        'The Top Deck tour is timed and reserved; the Main Deck is usually queue-free.',
      ),
      LText(
        'Gece ışıklandırması yaz/kış farklı renkte.',
        'The night lighting is a different color in summer and winter.',
      ),
      LText(
        'Kırmızı ışıklar kapanmadan (23:00) önce git.',
        'Go before the red lights switch off (23:00).',
      ),
    ],
    averageRating: 4.5,
    reviewCount: 85000,
  ),
  PlaceGuide(
    id: 'ueno-park',
    matches: ['ueno'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/1/18/Ueno_park.jpg/960px-Ueno_park.jpg',
    ],
    visitDurationMin: 120,
    bestTimeOfDay: LText(
      'Sabah — müzeler açılırken (09:30) kalabalık az',
      'Morning — crowds are thin as the museums open (09:30)',
    ),
    brief: LText(
      'Tokyo\'nun müze parkı: Ulusal Müze, Bilim Müzesi, hayvanat bahçesi ve '
      'Shinobazu gölü aynı alanda. Sakura mevsiminde Japonya\'nın en ünlü '
      'hanami noktalarından.',
      'Tokyo\'s museum park: the National Museum, the Science Museum, a zoo and '
      'Shinobazu Pond all in one place. One of Japan\'s most famous hanami '
      'spots in cherry-blossom season.',
    ),
    tips: [
      LText(
        'Müzelerin çoğu pazartesi kapalı — günü ona göre seç.',
        'Most museums close on Mondays — plan your day accordingly.',
      ),
      LText(
        'Tokyo Ulusal Müzesi tek başına 2+ saat ister; önceliklendir.',
        'The Tokyo National Museum alone needs 2+ hours; prioritize it.',
      ),
      LText(
        'Ameyoko pazarı (istasyon tarafı) öğle yemeği için ideal.',
        'Ameyoko market (by the station) is ideal for lunch.',
      ),
      LText(
        'Panda görmek istersen hayvanat bahçesine açılışta gir.',
        'If you want to see the pandas, enter the zoo at opening.',
      ),
    ],
    averageRating: 4.4,
    reviewCount: 60000,
  ),
  PlaceGuide(
    id: 'ginza',
    matches: ['ginza'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5b/Ginza-WAKO_at_night.jpg/960px-Ginza-WAKO_at_night.jpg',
    ],
    visitDurationMin: 120,
    bestTimeOfDay: LText(
      'Öğleden sonra; hafta sonu ana cadde yayalaşır',
      'Afternoon; on weekends the main street goes pedestrian-only',
    ),
    brief: LText(
      'Tokyo\'nun lüks alışveriş bölgesi: amiral mağazalar, depachika (gurme '
      'bodrum katları) ve Kabuki-za tiyatrosu. Wako binasının saat kulesi '
      'semtin simgesi.',
      'Tokyo\'s luxury shopping district: flagship stores, depachika (gourmet '
      'food basements) and the Kabuki-za theatre. The Wako building\'s clock '
      'tower is the neighborhood\'s emblem.',
    ),
    tips: [
      LText(
        'Cumartesi-pazar 12:00–17:00 ana cadde trafiğe kapanır.',
        'On Saturdays and Sundays the main street closes to traffic 12:00–17:00.',
      ),
      LText(
        'Depachika için Mitsukoshi ya da Matsuya bodrum katı — örnek tadımlar.',
        'For depachika, the Mitsukoshi or Matsuya basement — with free samples.',
      ),
      LText(
        'Uniqlo Ginza 12 kat — dünyanın en büyüğü.',
        'Uniqlo Ginza has 12 floors — the largest in the world.',
      ),
      LText(
        'Kabuki-za\'da tek perde bileti (~1500-2000¥) turist dostu.',
        'A single-act ticket at Kabuki-za (~1,500–2,000¥) is tourist-friendly.',
      ),
    ],
    averageRating: 4.4,
    reviewCount: 40000,
  ),
  PlaceGuide(
    id: 'tsukiji',
    matches: ['tsukiji'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/5/51/Tsukiji_Outer_Market_-02.jpg/960px-Tsukiji_Outer_Market_-02.jpg',
    ],
    visitDurationMin: 90,
    bestTimeOfDay: LText(
      'Sabah 08:00–10:00 — tezgahlar taze, kalabalık yönetilebilir',
      'Morning 08:00–10:00 — stalls are fresh and crowds manageable',
    ),
    brief: LText(
      'Eski balık halinin dış pazarı hâlâ Tokyo\'nun sokak lezzeti merkezi: '
      'tamagoyaki, taze sashimi, uni ve wagyu şişleri. Çoğu tezgah '
      '05:00–14:00 arası çalışır.',
      'The old fish market\'s outer market is still Tokyo\'s street-food hub: '
      'tamagoyaki, fresh sashimi, uni and wagyu skewers. Most stalls run '
      '05:00–14:00.',
    ),
    tips: [
      LText(
        'Pazar günleri birçok dükkan kapalı — hafta içi git.',
        'Many shops close on Sundays — go on a weekday.',
      ),
      LText(
        'Yürürken yemek ayıp sayılır; tezgah kenarında bitir.',
        'Eating while walking is frowned upon; finish beside the stall.',
      ),
      LText(
        'Nakiri bıçakları ve yeşil çay hediyelik için iyi.',
        'Nakiri knives and green tea make good souvenirs.',
      ),
      LText(
        'Öğleden sonra gidersen çoğu şey kapanmış olur.',
        'If you go in the afternoon, most stalls will have closed.',
      ),
    ],
    averageRating: 4.4,
    reviewCount: 40000,
  ),
  PlaceGuide(
    id: 'odaiba',
    matches: ['odaiba'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/4/4a/Odaiba_close_up_-_2025_Jan_14_01-27PM.jpeg/960px-Odaiba_close_up_-_2025_Jan_14_01-27PM.jpeg',
    ],
    visitDurationMin: 180,
    bestTimeOfDay: LText(
      'Öğleden sonra gel, Rainbow Bridge günbatımıyla bitir',
      'Come in the afternoon and finish with the Rainbow Bridge at sunset',
    ),
    brief: LText(
      'Körfezdeki yapay ada: dev Gundam heykeli, alışveriş merkezleri, '
      'Özgürlük Heykeli kopyası ve Rainbow Bridge manzarası. Yurikamome '
      'sürücüsüz treniyle ulaşım başlı başına eğlence.',
      'A man-made island in the bay: a giant Gundam statue, malls, a replica '
      'Statue of Liberty and Rainbow Bridge views. Getting there on the '
      'driverless Yurikamome train is fun in itself.',
    ),
    tips: [
      LText(
        'Yurikamome\'de en ön koltuk — köprü geçişi panoramik.',
        'Grab the front seat on the Yurikamome — the bridge crossing is panoramic.',
      ),
      LText(
        'Gundam heykeli akşam saatlerinde ışık/hareket gösterisi yapıyor.',
        'The Gundam statue puts on a light-and-motion show in the evening.',
      ),
      LText(
        'DiverCity food court hızlı ve uygun akşam yemeği.',
        'The DiverCity food court is a quick, affordable dinner.',
      ),
      LText(
        'Plaj yürüyüşü günbatımında Rainbow Bridge karesi verir.',
        'A walk along the beach gives you the Rainbow Bridge shot at sunset.',
      ),
    ],
    averageRating: 4.4,
    reviewCount: 35000,
  ),
  PlaceGuide(
    id: 'tokyo-disney',
    matches: ['disneyland', 'disneysea', 'tokyo disney', 'disney'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/4/4b/Tokyo_Disneyland_Cinderella_Castle_2023-07-02.jpg/960px-Tokyo_Disneyland_Cinderella_Castle_2023-07-02.jpg',
    ],
    visitDurationMin: 600,
    bestTimeOfDay: LText(
      'Hafta içi sabah 08:00 açılış — hafta sonu ~2× yoğun',
      'Weekday 08:00 opening — weekends are about twice as busy',
    ),
    brief: LText(
      'Tokyo Disney Resort iki park içerir: Disneyland (klasik) ve DisneySea '
      '(dünyada tek — deniz temalı, yetişkin dostu). DisneySea benzersiz '
      'atraksiyonlarıyla öne çıkar.',
      'Tokyo Disney Resort has two parks: Disneyland (the classic) and '
      'DisneySea (one of a kind — sea-themed and adult-friendly). DisneySea '
      'stands out for its unique attractions.',
    ),
    tips: [
      LText(
        'Premier Access (ücretli hızlı geçiş) uygulamadan gün içinde alınır.',
        'Premier Access (paid fast pass) is bought through the app during the day.',
      ),
      LText(
        'DisneySea\'de Journey to the Center of the Earth + Soaring öncelik.',
        'At DisneySea, prioritize Journey to the Center of the Earth and Soaring.',
      ),
      LText(
        'Resmî uygulamayı önceden indir — bekleme süreleri canlı görünür.',
        'Download the official app in advance — wait times show live.',
      ),
      LText(
        'Kapanış saati fişek gösterisini bekle; çıkış treni yoğun olur.',
        'Stay for the closing fireworks; the train out gets crowded.',
      ),
    ],
    advanceBookingDays: 60,
    averageRating: 4.7,
    reviewCount: 210000,
    bookingHint: LText(
      'Resmî Tokyo Disney Resort sitesi ya da Klook.',
      'Official Tokyo Disney Resort site or Klook.',
    ),
  ),
  // ── Kyoto ────────────────────────────────────────────────────────────────
  PlaceGuide(
    id: 'fushimi-inari',
    matches: ['fushimi inari', 'fushimi', 'inari'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/0/0e/Torii_path_with_lantern_at_Fushimi_Inari_Taisha_Shrine%2C_Kyoto%2C_Japan.jpg/960px-Torii_path_with_lantern_at_Fushimi_Inari_Taisha_Shrine%2C_Kyoto%2C_Japan.jpg',
    ],
    visitDurationMin: 120,
    bestTimeOfDay: LText(
      'Şafak 06:00–08:00 — kalabalıksız + soft ışık',
      'Dawn 06:00–08:00 — no crowds and soft light',
    ),
    brief: LText(
      'Binlerce kırmızı torii kapılı ünlü Şinto tapınağı. Zirveye kadar yürüyüş '
      '~2 saat + geri dönüş. Torii tüneli fotoğraflarının çekildiği bölüm ilk '
      '15 dakikada, tepede daha az kalabalık ve manzara güzel.',
      'A famous Shinto shrine with thousands of red torii gates. The hike to '
      'the summit takes about 2 hours plus the way back. The photogenic torii '
      'tunnels are within the first 15 minutes; the top is quieter with a nice '
      'view.',
    ),
    tips: [
      LText(
        'Sabah 07:00\'de git — 09:00 sonrası tur otobüsleri gelir.',
        'Go at 07:00 — tour buses arrive after 09:00.',
      ),
      LText(
        'JR Inari (yaya 1 dk) veya Keihan Fushimi-Inari (5 dk).',
        'JR Inari (1-min walk) or Keihan Fushimi-Inari (5 min).',
      ),
      LText(
        'Kapı fotoğrafı için ilk büyük tünel değil, biraz yukarı çık.',
        'For the gate photo, climb a bit past the first big tunnel.',
      ),
      LText(
        'Yol üstündeki inari-sushi (tofu sushi) yerel imza tat.',
        'The inari-sushi (tofu sushi) along the way is the local signature bite.',
      ),
    ],
    averageRating: 4.7,
    reviewCount: 87000,
  ),
  PlaceGuide(
    id: 'kinkakuji',
    matches: ['kinkaku-ji', 'kinkakuji', 'altın pavyon', 'golden pavilion'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/0/0f/Golden_Pavilion_Kinkaku-ji_water_mirror_2024.jpg/960px-Golden_Pavilion_Kinkaku-ji_water_mirror_2024.jpg',
    ],
    visitDurationMin: 60,
    bestTimeOfDay: LText(
      'Sabah 09:00 açılış — pavyonun altın rengi güneşte parlar',
      'At the 09:00 opening — the pavilion\'s gold gleams in the sun',
    ),
    brief: LText(
      'Yaldızlı üst iki katıyla ünlü Zen tapınağı. Tek yönlü yürüyüş rotası '
      '~30-45 dk. Küçük ama etkileyici — buradan Ryoan-ji taş bahçesine yürüyüş '
      '~15 dk.',
      'A Zen temple famous for its two gold-leafed upper floors. The one-way '
      'walking route takes about 30–45 min. Small but striking — it\'s about a '
      '15-min walk from here to the Ryoan-ji rock garden.',
    ),
    tips: [
      LText(
        'Giriş bileti bir dua kağıdı (fuda) — sakla, hediyelik gibi.',
        'The entry ticket is a prayer slip (fuda) — keep it as a souvenir.',
      ),
      LText(
        'Öğleden sonra otobüs çok kalabalık — sabah git.',
        'Buses are packed in the afternoon — go in the morning.',
      ),
      LText(
        'Yakın: Ryoan-ji (taş bahçe) + Ninnaji (sakura ünlü) aynı otobüs hattı.',
        'Nearby: Ryoan-ji (rock garden) and Ninna-ji (famous for sakura) on the same bus line.',
      ),
    ],
    averageRating: 4.4,
    reviewCount: 52000,
  ),
  PlaceGuide(
    id: 'arashiyama',
    matches: ['arashiyama', 'bambu', 'bamboo'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/d/de/Arashiyama_013.jpg/960px-Arashiyama_013.jpg',
    ],
    visitDurationMin: 180,
    bestTimeOfDay: LText(
      'Sabah 07:00–09:00 — bambu ormanı boşken, ışık dikey iner',
      'Morning 07:00–09:00 — the bamboo grove is empty and light falls straight down',
    ),
    brief: LText(
      'Bambu ormanı, Togetsukyo köprüsü, maymun parkı ve Tenryu-ji tapınağı. '
      'Yürüyüş rotası ~2-3 saat sürer. Sonbaharda momiji (kızıl akçaağaç) '
      'muhteşem.',
      'The bamboo grove, Togetsukyo Bridge, the monkey park and Tenryu-ji '
      'Temple. The walking route takes about 2–3 hours. The momiji (crimson '
      'maples) are spectacular in autumn.',
    ),
    tips: [
      LText(
        'Sabah 08:00\'den önce git — sonrası tur otobüsleri.',
        'Go before 08:00 — after that come the tour buses.',
      ),
      LText(
        'Maymun parkı (Iwatayama) 15 dk tırmanış — çıkışta panorama.',
        'The monkey park (Iwatayama) is a 15-min climb — with a panorama at the top.',
      ),
      LText(
        'Tenryu-ji bahçesi + kuzey çıkışı → bambu ormanı en verimli rota.',
        'Tenryu-ji garden then the north exit into the bamboo grove is the most efficient route.',
      ),
      LText(
        'JR Saga-Arashiyama ya da Randen tramvayı.',
        'Take JR Saga-Arashiyama or the Randen tram.',
      ),
    ],
    averageRating: 4.6,
    reviewCount: 74000,
  ),
  PlaceGuide(
    id: 'kiyomizu',
    matches: ['kiyomizu'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/3/3c/Kiyomizu.jpg/960px-Kiyomizu.jpg',
    ],
    visitDurationMin: 90,
    bestTimeOfDay: LText(
      'Sabah 06:00 açılış — ahşap teras boşken gör',
      'At the 06:00 opening — see the wooden terrace while it\'s empty',
    ),
    brief: LText(
      'Kyoto\'nun simge tapınağı: çivisiz inşa edilmiş dev ahşap terası şehre '
      'bakar. Otowa şelalesinden su içmek dilek geleneği. Giriş 400¥; '
      'çevresindeki Higashiyama yokuşları da gezinin parçası.',
      'Kyoto\'s emblematic temple: a huge nail-free wooden terrace overlooking '
      'the city. Drinking from the Otowa waterfall is a wish-making tradition. '
      'Entry 400¥; the surrounding Higashiyama slopes are part of the visit.',
    ),
    tips: [
      LText(
        'Sannenzaka-Ninenzaka yokuşlarından yürüyerek çık — dükkanlar şirin.',
        'Walk up via the Sannenzaka–Ninenzaka slopes — the shops are charming.',
      ),
      LText(
        'Sabah 08:00 öncesi ya da akşam kapanışa yakın en sakini.',
        'Quietest before 08:00 or near closing in the evening.',
      ),
      LText(
        'Otowa şelalesinde üç sudan yalnız birinden iç (açgözlülük sayılır).',
        'At the Otowa waterfall, drink from only one of the three streams (taking all is seen as greedy).',
      ),
      LText(
        'Kiraz ve momiji sezonunda gece ışıklandırması oluyor — ayrıca gir.',
        'There are night illuminations in cherry-blossom and momiji season — worth a separate visit.',
      ),
    ],
    averageRating: 4.5,
    reviewCount: 60000,
  ),
  PlaceGuide(
    id: 'gion',
    matches: ['gion'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/2/23/150124_Gion_Kyoto_Japan01s3.jpg/960px-150124_Gion_Kyoto_Japan01s3.jpg',
    ],
    visitDurationMin: 90,
    bestTimeOfDay: LText(
      'Akşamüstü 17:00–19:00 — geyko/maiko işe çıkma saati',
      'Early evening 17:00–19:00 — when geiko/maiko head to work',
    ),
    brief: LText(
      'Kyoto\'nun geyşa mahallesi: ahşap machiya evleri, çay evleri ve taş '
      'kaplı Hanamikoji caddesi. Shirakawa kanalı boyunca yürüyüş özellikle '
      'akşam atmosferik.',
      'Kyoto\'s geisha district: wooden machiya houses, tea houses and the '
      'stone-paved Hanamikoji Street. A walk along the Shirakawa canal is '
      'especially atmospheric in the evening.',
    ),
    tips: [
      LText(
        'Geyko fotoğrafı çekmek için özel sokaklarda yasak levhalarına dikkat.',
        'Watch for no-photo signs on the private lanes when shooting geiko.',
      ),
      LText(
        'Hanamikoji yerine Shirakawa tarafı daha sakin ve fotojenik.',
        'The Shirakawa side is calmer and more photogenic than Hanamikoji.',
      ),
      LText(
        'Yasaka tapınağı gece açık — Gion turunu onunla bitir.',
        'Yasaka Shrine is open at night — end your Gion walk there.',
      ),
      LText(
        'Kimono kiralayıp gezmek istersen sabah al, akşam iade.',
        'If you want to explore in a rented kimono, pick it up in the morning and return it in the evening.',
      ),
    ],
    averageRating: 4.5,
    reviewCount: 45000,
  ),
  PlaceGuide(
    id: 'nijo',
    matches: ['nijo'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/NinomaruPalace.jpg/960px-NinomaruPalace.jpg',
    ],
    visitDurationMin: 90,
    bestTimeOfDay: LText(
      'Sabah 08:45 açılış — sarayın içi grupsuz gezilir',
      'At the 08:45 opening — tour the palace before the groups arrive',
    ),
    brief: LText(
      'Tokugawa şogunlarının Kyoto sarayı (1603, UNESCO). "Bülbül zemin" '
      'gıcırtısıyla ünlü Ninomaru sarayı ve geniş bahçeler. Giriş + saray '
      '1300¥.',
      'The Kyoto castle of the Tokugawa shoguns (1603, UNESCO). The Ninomaru '
      'Palace, famous for its squeaking "nightingale floors," plus expansive '
      'gardens. Entry + palace 1,300¥.',
    ),
    tips: [
      LText(
        'Bülbül zemini duymak için sessiz bir aralık bekle.',
        'Wait for a quiet moment to hear the nightingale floor.',
      ),
      LText(
        'Saray içinde fotoğraf yasak — bahçede serbest.',
        'Photography is banned inside the palace but allowed in the garden.',
      ),
      LText(
        'Sesli rehber (Türkçe yok, İngilizce var) hikayeyi çok açıyor.',
        'The audio guide (no Turkish, but English is available) really brings the story to life.',
      ),
      LText(
        'Ocak, temmuz, ağustos ve aralıkta bazı salı günleri saray kapalı.',
        'The palace closes on some Tuesdays in January, July, August and December.',
      ),
    ],
    averageRating: 4.4,
    reviewCount: 35000,
  ),
  PlaceGuide(
    id: 'ginkakuji',
    matches: ['ginkaku'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/0/06/Ginkakuji_Kyoto03-r.jpg/960px-Ginkakuji_Kyoto03-r.jpg',
    ],
    visitDurationMin: 60,
    bestTimeOfDay: LText(
      'Sabah — Felsefe Yolu yürüyüşüyle birleştir',
      'Morning — combine it with a walk along the Philosopher\'s Path',
    ),
    brief: LText(
      '"Gümüş Pavyon" — adının aksine gümüş kaplama yok; kum bahçesi ve yosun '
      'örtüsüyle Zen estetiğinin zirvesi sayılır. Felsefe Yolu\'nun kuzey ucunda.',
      'The "Silver Pavilion" — despite the name there is no silver coating; its '
      'sand garden and moss carpet are considered the peak of Zen aesthetics. '
      'At the north end of the Philosopher\'s Path.',
    ),
    tips: [
      LText(
        'Felsefe Yolu\'nu Nanzen-ji\'den buraya yürü (~30 dk, sakura ünlü).',
        'Walk the Philosopher\'s Path from Nanzen-ji to here (~30 min, famous for sakura).',
      ),
      LText(
        'Kum konisi (Kogetsudai) sabah ışığında en net görünür.',
        'The sand cone (Kogetsudai) looks sharpest in morning light.',
      ),
      LText(
        'Tepe yolundan Kyoto manzarası — rotanın sonuna sakla.',
        'The hillside path offers a Kyoto view — save it for the end of the route.',
      ),
    ],
    averageRating: 4.4,
    reviewCount: 25000,
  ),
  PlaceGuide(
    id: 'pontocho',
    matches: ['pontocho'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/6/68/Pontocho_by_Wolfiewolf_in_Nabeyacho%2C_Kyoto.jpg/960px-Pontocho_by_Wolfiewolf_in_Nabeyacho%2C_Kyoto.jpg',
    ],
    visitDurationMin: 60,
    bestTimeOfDay: LText(
      'Akşam 18:00 sonrası — fenerler yanınca canlanır',
      'After 18:00 — it comes alive once the lanterns light up',
    ),
    brief: LText(
      'Kamo nehrine paralel dar bir sokakta sıralanmış restoran ve izakayalar. '
      'Yazın nehir üstü terasları (kawadoko) açılır. Kyoto\'da akşam yemeği '
      'için en atmosferik sokak.',
      'Restaurants and izakayas lined along a narrow lane parallel to the Kamo '
      'River. In summer the riverside terraces (kawadoko) open. Kyoto\'s most '
      'atmospheric street for dinner.',
    ),
    tips: [
      LText(
        'Rezervasyonsuz gidersen 18:00 öncesi daha kolay yer bulursun.',
        'Without a reservation, you\'ll find a table more easily before 18:00.',
      ),
      LText(
        'Menüsü kapıda yazmayan yerler pahalı olabilir — önce sor.',
        'Places that don\'t post a menu at the door can be pricey — ask first.',
      ),
      LText(
        'Mayıs-eylül arası kawadoko (nehir terası) olan yer seç.',
        'Between May and September, pick a spot with a kawadoko (river terrace).',
      ),
      LText(
        'Gion\'a yürüme mesafesi — ikisini aynı akşama koy.',
        'Walking distance to Gion — pair the two in one evening.',
      ),
    ],
    averageRating: 4.4,
    reviewCount: 20000,
  ),
  PlaceGuide(
    id: 'nishiki',
    matches: ['nishiki'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/c/ce/Nishiki_Ichiba_by_matsuyuki.jpg/960px-Nishiki_Ichiba_by_matsuyuki.jpg',
    ],
    visitDurationMin: 75,
    bestTimeOfDay: LText(
      'Öğlen 10:00–16:00 — tezgahların hepsi açıkken',
      'Midday 10:00–16:00 — when all the stalls are open',
    ),
    brief: LText(
      '"Kyoto\'nun mutfağı" — 400 yıllık kapalı çarşıda 100+ tezgah: tsukemono '
      '(turşu), tofu tatlıları, yuba, taze deniz ürünü şişleri ve bıçakçılar.',
      '"Kyoto\'s kitchen" — a 400-year-old covered arcade with 100+ stalls: '
      'tsukemono (pickles), tofu sweets, yuba, fresh seafood skewers and knife '
      'makers.',
    ),
    tips: [
      LText(
        'Tako tamago (yumurtalı bebek ahtapot) çarşının klasiği.',
        'Tako tamago (baby octopus with an egg inside) is the market\'s classic.',
      ),
      LText(
        'Aritsugu bıçakçısında ustadan isim kazıma yaptırabilirsin.',
        'At the Aritsugu knife shop you can have your name engraved by a craftsman.',
      ),
      LText(
        'Yürürken yemek yerine tezgah yanında bitirmek adet.',
        'The custom is to finish beside the stall rather than eat while walking.',
      ),
      LText(
        'Çarşamba bazı dükkanlar kapalı; pazar kalabalık.',
        'Some shops close on Wednesdays; Sundays are crowded.',
      ),
    ],
    averageRating: 4.3,
    reviewCount: 50000,
  ),
  PlaceGuide(
    id: 'tofukuji',
    matches: ['tofuku'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/7/76/TofukujiHondo.jpg/960px-TofukujiHondo.jpg',
    ],
    visitDurationMin: 75,
    bestTimeOfDay: LText(
      'Sonbaharda sabah 08:30 açılış; diğer mevsimler sakin',
      'The 08:30 opening in autumn; quiet in other seasons',
    ),
    brief: LText(
      'Kyoto\'nun en büyük Zen tapınaklarından; Tsutenkyo köprüsünden bakılan '
      'akçaağaç vadisi Japonya\'nın en ünlü momiji manzarası. Kasım ortası '
      'zirve sezon.',
      'One of Kyoto\'s largest Zen temples; the maple valley seen from the '
      'Tsutenkyo bridge is Japan\'s most famous momiji view. Mid-November is '
      'peak season.',
    ),
    tips: [
      LText(
        'Momiji sezonunda (kasım) 08:00\'de kapıda ol — 10:00\'da izdiham.',
        'In momiji season (November) be at the gate by 08:00 — it\'s a crush by 10:00.',
      ),
      LText(
        'Hojo bahçesinin dama desenli yosun bahçesi modern Zen klasiği.',
        'The Hojo garden\'s checkerboard moss garden is a modern Zen classic.',
      ),
      LText(
        'Fushimi Inari\'ye tek durak — ikisini aynı sabaha koy.',
        'One stop from Fushimi Inari — pair the two in one morning.',
      ),
    ],
    averageRating: 4.4,
    reviewCount: 15000,
  ),
  // ── Osaka ────────────────────────────────────────────────────────────────
  PlaceGuide(
    id: 'dotonbori',
    matches: ['dotonbori', 'dōtonbori', 'dontonbori', 'dötonbori'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/f/f4/Osaka_Dotonbori_Ebisu_Bridge.jpg/960px-Osaka_Dotonbori_Ebisu_Bridge.jpg',
    ],
    visitDurationMin: 150,
    bestTimeOfDay: LText(
      'Akşam 18:00–22:00 — neon ışıklar + street food canlanır',
      'Evening 18:00–22:00 — neon lights and street food come alive',
    ),
    brief: LText(
      'Osaka\'nın yeme-içme kalbi. Glico koşucusu tabelası, kanal boyu neonlar '
      've takoyaki tezgahları. Kanalı geçen Ebisu köprüsü klasik fotoğraf '
      'noktası.',
      'The heart of Osaka\'s food scene. The Glico running-man sign, canal-side '
      'neon and takoyaki stalls. The Ebisu bridge over the canal is the classic '
      'photo spot.',
    ),
    tips: [
      LText(
        'Takoyaki için Wanaka veya Kukuru — 45 dk sıra bekleyebilir.',
        'For takoyaki, Wanaka or Kukuru — expect up to a 45-min queue.',
      ),
      LText(
        'Ichiran ramen — kişisel bölmeler, ilk kez deneyimlemek için ideal.',
        'Ichiran ramen — private booths, ideal for a first-timer.',
      ),
      LText(
        '551 Horai buhar böreği (butaman) yol üzeri atıştırmalık.',
        '551 Horai\'s steamed pork buns (butaman) are a great on-the-go snack.',
      ),
      LText(
        'Glico tabelası karesi için Ebisu köprüsünün ortası.',
        'For the Glico-sign shot, stand in the middle of the Ebisu bridge.',
      ),
    ],
    averageRating: 4.5,
    reviewCount: 89000,
  ),
  PlaceGuide(
    id: 'usj',
    matches: ['universal studios', 'usj', 'universal japan'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/b/b5/Universal_Studios_Japan_entrance.jpg/960px-Universal_Studios_Japan_entrance.jpg',
      'https://upload.wikimedia.org/wikipedia/commons/thumb/b/b3/Super_Nintendo_World_Entrance_5th_Anniversary_decoration_at_Universal_Studios_Japan.jpg/960px-Super_Nintendo_World_Entrance_5th_Anniversary_decoration_at_Universal_Studios_Japan.jpg',
    ],
    visitDurationMin: 600,
    bestTimeOfDay: LText(
      'Park açılışından 30 dk önce kapıda ol — ilk saatler en verimli',
      'Be at the gate 30 min before opening — the first hours are most productive',
    ),
    brief: LText(
      'Super Nintendo World, Harry Potter Wizarding World ve Minion Park\'a '
      'ev sahipliği yapan tema parkı. Express Pass olmadan popüler '
      'atraksiyonlarda 90+ dk sıra beklenebilir.',
      'A theme park home to Super Nintendo World, the Harry Potter Wizarding '
      'World and Minion Park. Without an Express Pass, popular rides can mean '
      '90+ min queues.',
    ),
    tips: [
      LText(
        'Nintendo World\'e giriş için uygulamadan "Timed Entry" al (ücretsiz).',
        'Get a (free) "Timed Entry" for Nintendo World from the app.',
      ),
      LText(
        'Express Pass pahalı ama tek günde her şeyi görmek istiyorsan değer.',
        'The Express Pass is pricey but worth it if you want to see everything in one day.',
      ),
      LText(
        'Öğle yemeğini 11:00 öncesi ya da 14:00 sonrası planla.',
        'Plan lunch before 11:00 or after 14:00.',
      ),
      LText(
        'JR Universal City istasyonu park girişine 5 dk yürüme.',
        'JR Universal City station is a 5-min walk from the park entrance.',
      ),
    ],
    advanceBookingDays: 60,
    averageRating: 4.5,
    reviewCount: 145000,
    bookingHint: LText(
      'Resmî site ya da Klook — Express Pass\'lar haftalar önce tükenir.',
      'Official site or Klook — Express Passes sell out weeks ahead.',
    ),
  ),
  PlaceGuide(
    id: 'osaka-castle',
    matches: ['osaka kalesi', 'osaka castle'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/c/ca/Osaka_Castle_03bs3200.jpg/960px-Osaka_Castle_03bs3200.jpg',
    ],
    visitDurationMin: 120,
    bestTimeOfDay: LText(
      'Sabah 09:00 açılış — kule asansörü sırasız',
      'At the 09:00 opening — no queue for the keep\'s elevator',
    ),
    brief: LText(
      'Hideyoshi\'nin 1583\'te yaptırdığı kalenin betonarme rekonstrüksiyonu; '
      'içi müze, tepesi gözlem katı. Asıl güzellik dev taş surlar, hendekler '
      've park. Kule girişi 600¥.',
      'A concrete reconstruction of the castle Hideyoshi built in 1583; a '
      'museum inside, an observation deck on top. The real beauty is the '
      'massive stone walls, moats and park. Keep entry 600¥.',
    ),
    tips: [
      LText(
        'Nishinomaru bahçesinden kule + hendek karesi en iyisi (sakurada müthiş).',
        'The keep-and-moat shot from Nishinomaru garden is the best (stunning during sakura).',
      ),
      LText(
        'Kule içi asansör kuyruğu öğlen uzar — sabah çık.',
        'The keep\'s elevator queue grows by midday — go up in the morning.',
      ),
      LText(
        'Müze katları aşağı inerken gezilir; hikaye üstten başlar.',
        'Tour the museum floors on the way down; the story starts at the top.',
      ),
      LText(
        'Parkta sokak müzisyenleri ve food truck\'lar hafta sonu çıkar.',
        'Street musicians and food trucks appear in the park on weekends.',
      ),
    ],
    averageRating: 4.5,
    reviewCount: 75000,
  ),
  PlaceGuide(
    id: 'shinsekai',
    matches: ['shinsekai', 'tsutenkaku'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/9/95/Shinsekai_and_Tsutenkaku_at_night_2019-04-12.jpg/960px-Shinsekai_and_Tsutenkaku_at_night_2019-04-12.jpg',
    ],
    visitDurationMin: 90,
    bestTimeOfDay: LText(
      'Akşam — Tsutenkaku kulesi ve tabelalar ışıl ışıl',
      'Evening — the Tsutenkaku tower and signs are all aglow',
    ),
    brief: LText(
      'Retro Osaka: 1912\'den kalma "Yeni Dünya" mahallesi, Tsutenkaku kulesi '
      've kushikatsu (çıtır şiş) restoranları. Nostaljik, hafif kitsch ve çok '
      'fotojenik.',
      'Retro Osaka: the "New World" district dating to 1912, the Tsutenkaku '
      'tower and kushikatsu (crispy fried skewer) restaurants. Nostalgic, a '
      'little kitsch and very photogenic.',
    ),
    tips: [
      LText(
        'Kushikatsu\'da sosa ikinci kez banmak yasak — tek batırış!',
        'Double-dipping kushikatsu in the sauce is forbidden — one dip only!',
      ),
      LText(
        'Daruma zinciri kushikatsu\'nun klasiği; kuyruk hızlı ilerler.',
        'The Daruma chain is the kushikatsu classic; the queue moves fast.',
      ),
      LText(
        'Tsutenkaku\'nun tepesindeki Billiken heykelinin ayağını ovmak şans.',
        'Rubbing the feet of the Billiken statue atop Tsutenkaku is said to bring luck.',
      ),
      LText(
        'Janjan Yokocho pasajı retro oyun salonlarıyla dolu.',
        'The Janjan Yokocho arcade is packed with retro game halls.',
      ),
    ],
    averageRating: 4.3,
    reviewCount: 30000,
  ),
  PlaceGuide(
    id: 'umeda-sky',
    matches: ['umeda'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/f/f9/2018_Umeda_Sky_Building.jpg/960px-2018_Umeda_Sky_Building.jpg',
    ],
    visitDurationMin: 90,
    bestTimeOfDay: LText(
      'Günbatımından 30 dk önce çık — gece geçişini izle',
      'Head up 30 min before sunset — watch it turn to night',
    ),
    brief: LText(
      'İki kuleyi tepede birleştiren "Yüzen Bahçe" gözlem katı (173m). Açık '
      'havada 360° Osaka panoraması; cam eskalatörle çıkış başlı başına '
      'deneyim. Giriş ~2000¥.',
      'The "Floating Garden" observatory (173m) linking two towers at the top. '
      'An open-air 360° Osaka panorama; the ride up the glass escalator is an '
      'experience in itself. Entry ~2,000¥.',
    ),
    tips: [
      LText(
        'Günbatımı slotu için biletini önceden online al.',
        'Buy your ticket online in advance for the sunset slot.',
      ),
      LText(
        'Açık teras rüzgarlı — ince bir kat fazla giy.',
        'The open deck is windy — bring an extra layer.',
      ),
      LText(
        'Bodrumdaki Takimi-koji restoran katı Showa dönemi temalı.',
        'The Takimi-koji restaurant floor in the basement is Showa-era themed.',
      ),
      LText(
        'Osaka istasyonundan yeraltı geçidiyle ~10 dk yürüme.',
        'About a 10-min walk from Osaka Station via the underground passage.',
      ),
    ],
    averageRating: 4.4,
    reviewCount: 30000,
  ),
  PlaceGuide(
    id: 'kuromon',
    matches: ['kuromon'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/f/f4/Kuromon-ichiba_in_201408.JPG/960px-Kuromon-ichiba_in_201408.JPG',
    ],
    visitDurationMin: 75,
    bestTimeOfDay: LText(
      'Sabah 09:00–13:00 — deniz ürünleri en tazeyken',
      'Morning 09:00–13:00 — when the seafood is freshest',
    ),
    brief: LText(
      '"Osaka\'nın mutfağı" — 190 yıllık kapalı pazar. Izgara tarak, uni, '
      'wagyu şiş, taze meyve ve fugu tezgahları. Nippombashi istasyonuna '
      'bitişik.',
      '"Osaka\'s kitchen" — a 190-year-old covered market. Grilled scallops, '
      'uni, wagyu skewers, fresh fruit and fugu stalls. Right next to '
      'Nippombashi station.',
    ),
    tips: [
      LText(
        'Tezgahtan alıp oracıkta ızgaralatmak en iyisi — "grill?" diye sor.',
        'Best to buy from a stall and have it grilled on the spot — just ask "grill?"',
      ),
      LText(
        'Meyve tezgahlarındaki dilim kavun/çilek pahalı ama efsane.',
        'The sliced melon and strawberries at the fruit stalls are pricey but legendary.',
      ),
      LText(
        'Öğleden sonra 15:00 gibi tezgahlar kapanmaya başlar.',
        'Stalls start closing around 15:00 in the afternoon.',
      ),
      LText(
        'Dotonbori\'ye 10 dk yürüme — öğle burada, akşam orada.',
        'A 10-min walk to Dotonbori — lunch here, dinner there.',
      ),
    ],
    averageRating: 4.3,
    reviewCount: 35000,
  ),
  PlaceGuide(
    id: 'namba',
    matches: ['namba'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/9/91/Namba_Station.JPG/960px-Namba_Station.JPG',
    ],
    visitDurationMin: 120,
    bestTimeOfDay: LText(
      'Akşam — Dotonbori\'yle birleşen eğlence saatleri',
      'Evening — the nightlife hours that blend into Dotonbori',
    ),
    brief: LText(
      'Osaka\'nın güney merkezi (Minami): Shinsaibashi kapalı çarşısı, '
      'Amerikamura gençlik modası ve Namba Parks terasları. Dotonbori\'nin '
      'kapısı sayılır.',
      'Osaka\'s southern hub (Minami): the Shinsaibashi covered arcade, '
      'Amerikamura youth fashion and the Namba Parks terraces. Considered the '
      'gateway to Dotonbori.',
    ),
    tips: [
      LText(
        'Shinsaibashi-suji çarşısı yağmurlu gün planı olarak birebir.',
        'The Shinsaibashi-suji arcade is perfect as a rainy-day plan.',
      ),
      LText(
        'Amerikamura ikinci el/vintage giyim için Osaka\'nın merkezi.',
        'Amerikamura is Osaka\'s center for second-hand and vintage clothing.',
      ),
      LText(
        'Namba Parks\'ın kademeli çatı bahçesi sakin bir mola noktası.',
        'Namba Parks\' terraced rooftop garden is a calm rest stop.',
      ),
      LText(
        'Den Den Town (Nipponbashi) Osaka\'nın Akihabara\'sı — yürüme mesafesi.',
        'Den Den Town (Nipponbashi) is Osaka\'s Akihabara — within walking distance.',
      ),
    ],
    averageRating: 4.3,
    reviewCount: 25000,
  ),
  PlaceGuide(
    id: 'sumiyoshi',
    matches: ['sumiyoshi'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/f/fd/Sumiyoshi-taisha%2C_keidai-2.jpg/960px-Sumiyoshi-taisha%2C_keidai-2.jpg',
    ],
    visitDurationMin: 75,
    bestTimeOfDay: LText(
      'Sabah — tramvayla nostaljik bir yarım gün',
      'Morning — a nostalgic half-day by tram',
    ),
    brief: LText(
      'Japonya\'daki tüm Sumiyoshi tapınaklarının merkezi (3. yy); Çin/Kore '
      'etkisi öncesi saf Japon mimarisi. Kamburlu kırmızı Sorihashi köprüsü '
      'simgesi. Giriş ücretsiz.',
      'The head of all Sumiyoshi shrines in Japan (3rd century); pure Japanese '
      'architecture predating Chinese and Korean influence. The humpbacked red '
      'Sorihashi bridge is its emblem. Free entry.',
    ),
    tips: [
      LText(
        'Hankai tramvayıyla git — Osaka\'nın son sokak tramvayı, retro keyif.',
        'Go by the Hankai tram — Osaka\'s last street tram, a retro treat.',
      ),
      LText(
        'Sorihashi köprüsünün yansıma karesi için hendeğin batı yakası.',
        'For the Sorihashi bridge reflection shot, use the west side of the moat.',
      ),
      LText(
        'Ayın ilk günü (tsuitachi-mairi) yerel ziyaretçi akını olur.',
        'On the first of the month (tsuitachi-mairi), locals flock in.',
      ),
      LText(
        'Turist azdır — sakin bir "yerel Osaka" molası.',
        'Few tourists — a quiet slice of "local Osaka."',
      ),
    ],
    averageRating: 4.5,
    reviewCount: 15000,
  ),
  PlaceGuide(
    id: 'harukas',
    matches: ['abeno', 'harukas'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/f/ff/Illuminated_Tenn%C5%8Dji_Park_and_Abeno_Harukas%2C_November_2015%2C_Osaka.jpg/960px-Illuminated_Tenn%C5%8Dji_Park_and_Abeno_Harukas%2C_November_2015%2C_Osaka.jpg',
    ],
    visitDurationMin: 90,
    bestTimeOfDay: LText(
      'Günbatımı — Harukas 300 gözlem katından turuncu Osaka',
      'Sunset — Osaka turns orange from the Harukas 300 deck',
    ),
    brief: LText(
      '300m ile Japonya\'nın en yüksek binalarından. Harukas 300 gözlem katı '
      '58-60. katlarda; camdan zemine kadar açık 360° manzara. Giriş ~2000¥, '
      'altında Kintetsu AVM.',
      'At 300m, one of Japan\'s tallest buildings. The Harukas 300 observatory '
      'is on floors 58–60; a 360° view open to a glass floor. Entry ~2,000¥, '
      'with the Kintetsu mall below.',
    ),
    tips: [
      LText(
        'Gözlem katı bileti kapıdan alınır; hafta içi sıra kısa.',
        'The observatory ticket is bought at the door; the queue is short on weekdays.',
      ),
      LText(
        '58. kattaki açık avlu kafesinde manzaraya karşı kahve iç.',
        'Have a coffee facing the view at the open-atrium café on the 58th floor.',
      ),
      LText(
        'Shitenno-ji tapınağına yürüme ~15 dk — ikisini birleştir.',
        'About a 15-min walk to Shitenno-ji Temple — combine the two.',
      ),
      LText(
        'Gece 22:00\'ye kadar açık — akşam yemeği sonrası da olur.',
        'Open until 22:00 — an after-dinner visit works too.',
      ),
    ],
    averageRating: 4.4,
    reviewCount: 25000,
  ),
  PlaceGuide(
    id: 'shitennoji',
    matches: ['shitenno'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c6/Shitennoji_%26_Abeno_Harukas.jpg/960px-Shitennoji_%26_Abeno_Harukas.jpg',
    ],
    visitDurationMin: 75,
    bestTimeOfDay: LText(
      'Sabah — avlu sessizken',
      'Morning — while the courtyard is quiet',
    ),
    brief: LText(
      'Japonya\'nın devlet eliyle kurulan ilk Budist tapınağı (593). Beş katlı '
      'pagoda ve Harukas gökdeleniyle aynı karede eski-yeni kontrastı. İç '
      'avlu 300¥, dış alan ücretsiz.',
      'Japan\'s first state-founded Buddhist temple (593). Its five-story '
      'pagoda frames an old-versus-new contrast with the Harukas skyscraper. '
      'Inner courtyard 300¥, outer grounds free.',
    ),
    tips: [
      LText(
        'Ayın 21-22\'sinde tapınak avlusunda bit pazarı kurulur.',
        'A flea market is held in the temple courtyard on the 21st–22nd of each month.',
      ),
      LText(
        'Pagodanın içine çıkılabilir (dar merdiven).',
        'You can climb inside the pagoda (narrow stairs).',
      ),
      LText(
        'Gokuraku-jodo bahçesi ayrı ücret ama çok sakin.',
        'The Gokuraku-jodo garden costs extra but is very peaceful.',
      ),
      LText(
        'Harukas\'la aynı yarım güne sığar.',
        'It fits into the same half-day as Harukas.',
      ),
    ],
    averageRating: 4.3,
    reviewCount: 12000,
  ),
  // ── Nara ─────────────────────────────────────────────────────────────────
  PlaceGuide(
    id: 'nara-park',
    matches: ['nara park', 'nara parkı', 'geyik'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/b/b4/Nara_Park_-_panoramio_%282%29.jpg/960px-Nara_Park_-_panoramio_%282%29.jpg',
    ],
    visitDurationMin: 150,
    bestTimeOfDay: LText(
      'Sabah 09:00 öncesi — geyikler aç ve nazik, kalabalık yok',
      'Before 09:00 — the deer are hungry and gentle, and there are no crowds',
    ),
    brief: LText(
      '1200+ serbest sika geyiğinin dolaştığı park; geyikler kutsal elçi '
      'sayılır ve selam verir (öğrenilmiş davranış). Todai-ji ve Kasuga '
      'Taisha parkın içinde.',
      'A park roamed by 1,200+ free sika deer; the deer are considered sacred '
      'messengers and even bow (a learned behavior). Todai-ji and Kasuga Taisha '
      'are inside the park.',
    ),
    tips: [
      LText(
        'Geyik krakeri (shika senbei, 200¥) alınca hemen etrafın sarılır — '
        'krakerleri arkada tutma, ısırırlar.',
        'The moment you buy deer crackers (shika senbei, 200¥) you\'ll be '
        'surrounded — don\'t hide them behind your back, they\'ll nip.',
      ),
      LText(
        'Kağıt/harita gibi şeyleri geyiklerden uzak tut — yerler.',
        'Keep paper and maps away from the deer — they\'ll eat them.',
      ),
      LText(
        'Öğlen tur grupları gelince geyikler doyar, ilgisizleşir.',
        'Once tour groups arrive at midday the deer are full and lose interest.',
      ),
      LText(
        'Park + Todai-ji + Kasuga rotası rahat yarım gün.',
        'The Park + Todai-ji + Kasuga route makes an easy half-day.',
      ),
    ],
    averageRating: 4.6,
    reviewCount: 80000,
  ),
  PlaceGuide(
    id: 'todaiji',
    matches: ['todai'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/2/2f/T%C5%8Ddai-ji_Kon-d%C5%8D.jpg/960px-T%C5%8Ddai-ji_Kon-d%C5%8D.jpg',
    ],
    visitDurationMin: 90,
    bestTimeOfDay: LText(
      'Sabah 08:00 açılış — Daibutsu salonu boşken görkemli',
      'At the 08:00 opening — the Daibutsu hall is majestic while empty',
    ),
    brief: LText(
      'Dünyanın en büyük ahşap yapılarından Daibutsuden içinde 15m\'lik bronz '
      'Buda (752). Nandaimon kapısındaki Nio muhafız heykelleri de başyapıt. '
      'Giriş 800¥.',
      'A 15m bronze Buddha (752) inside the Daibutsuden, one of the world\'s '
      'largest wooden buildings. The Nio guardian statues at the Nandaimon gate '
      'are also masterpieces. Entry 800¥.',
    ),
    tips: [
      LText(
        'Salondaki delikli sütundan geçebilen "aydınlanma" kazanır (çocuk boyu!).',
        'Squeezing through the hole in the hall\'s pillar earns "enlightenment" (child-sized!).',
      ),
      LText(
        'Nandaimon kapısında durup Nio heykellerine yukarıdan bak.',
        'Pause at the Nandaimon gate and look up at the Nio statues.',
      ),
      LText(
        'Şubat-ekim 07:30, kasım-mart 08:00 açılış — erken git.',
        'Opens 07:30 Feb–Oct and 08:00 Nov–Mar — go early.',
      ),
      LText(
        'Nigatsu-do terasına çık — Nara ovası manzarası ücretsiz.',
        'Climb up to the Nigatsu-do terrace — the view over the Nara plain is free.',
      ),
    ],
    averageRating: 4.6,
    reviewCount: 55000,
  ),
  PlaceGuide(
    id: 'kasuga',
    matches: ['kasuga'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/0/0d/Kasuga-taisha11bs3200.jpg/960px-Kasuga-taisha11bs3200.jpg',
    ],
    visitDurationMin: 75,
    bestTimeOfDay: LText(
      'Sabah — fenerli orman yolu loş ışıkta mistik',
      'Morning — the lantern-lined forest path is mystical in the dim light',
    ),
    brief: LText(
      'Nara\'nın koruyucu Şinto tapınağı (768, UNESCO); 3000 taş ve bronz '
      'feneriyle ünlü. Ormanın içindeki fener dizili yaklaşım yolu en '
      'atmosferik bölüm. Dış alan ücretsiz.',
      'Nara\'s guardian Shinto shrine (768, UNESCO), famous for its 3,000 stone '
      'and bronze lanterns. The lantern-lined approach through the forest is '
      'the most atmospheric part. Outer grounds free.',
    ),
    tips: [
      LText(
        'İç avluya girmesen de fenerli yol tek başına değer.',
        'Even without entering the inner hall, the lantern path alone is worth it.',
      ),
      LText(
        'Şubat başı ve ağustos ortası tüm fenerler yakılır (Mantoro festivali).',
        'All lanterns are lit in early February and mid-August (the Mantoro festival).',
      ),
      LText(
        'Fener deposu odasında (iç avlu) karanlıkta yanan fener simülasyonu var.',
        'The lantern-storage room (inner hall) has a simulation of lanterns glowing in the dark.',
      ),
      LText(
        'Nara parkının geyikleri buraya kadar geliyor.',
        'Nara Park\'s deer wander all the way up here.',
      ),
    ],
    averageRating: 4.5,
    reviewCount: 25000,
  ),
  PlaceGuide(
    id: 'kofukuji',
    matches: ['kofuku'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/7/77/Kofukuji12st5s3200.jpg/960px-Kofukuji12st5s3200.jpg',
    ],
    visitDurationMin: 60,
    bestTimeOfDay: LText(
      'Gün batımına doğru — pagoda silueti göletten yansır',
      'Toward sunset — the pagoda\'s silhouette reflects off the pond',
    ),
    brief: LText(
      'Fujiwara klanının aile tapınağı (710); beş katlı pagodası Nara\'nın '
      'simgesi. Ulusal Hazine Salonu\'ndaki üç yüzlü Ashura heykeli Japon '
      'sanatının başyapıtlarından.',
      'The Fujiwara clan\'s family temple (710); its five-story pagoda is a '
      'symbol of Nara. The three-faced Ashura statue in the National Treasure '
      'Hall is a masterpiece of Japanese art.',
    ),
    tips: [
      LText(
        'Ashura heykeli için Ulusal Hazine Salonu\'na gir (700¥) — değer.',
        'Enter the National Treasure Hall for the Ashura statue (700¥) — worth it.',
      ),
      LText(
        'Sarusawa göletinin güney kıyısından pagoda yansıma karesi.',
        'The pagoda reflection shot is from the south shore of Sarusawa Pond.',
      ),
      LText(
        'Kintetsu Nara istasyonuna 5 dk — Nara turunun ilk durağı yap.',
        'Five minutes from Kintetsu Nara station — make it the first stop on your Nara tour.',
      ),
    ],
    averageRating: 4.4,
    reviewCount: 15000,
  ),
  PlaceGuide(
    id: 'isuien',
    matches: ['isuien'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/a/af/Isuien_and_Nandaimon.JPG/960px-Isuien_and_Nandaimon.JPG',
    ],
    visitDurationMin: 60,
    bestTimeOfDay: LText(
      'Sabah — Todai-ji kalabalığından önce sakin mola',
      'Morning — a calm break before the Todai-ji crowds',
    ),
    brief: LText(
      'Nara\'nın en güzel yürüyüş bahçesi; Todai-ji\'nin Nandaimon kapısını ve '
      'Wakakusa tepesini "ödünç manzara" (shakkei) olarak kullanır. Giriş '
      '1200¥, salı kapalı.',
      'Nara\'s finest strolling garden; it uses Todai-ji\'s Nandaimon gate and '
      'Wakakusa hill as "borrowed scenery" (shakkei). Entry 1,200¥, closed '
      'Tuesdays.',
    ),
    tips: [
      LText(
        'Todai-ji ile aynı rotada — arada 15 dakikalık huzur molası.',
        'On the same route as Todai-ji — a 15-minute pocket of calm in between.',
      ),
      LText(
        'Bahçe iki bölüm: ön (17. yy) ve arka (Meiji) — arka daha fotojenik.',
        'The garden has two parts: front (17th c.) and back (Meiji) — the back is more photogenic.',
      ),
      LText(
        'Bilet küçük Neiraku müzesini de kapsıyor (Çin-Kore bronzları).',
        'The ticket also covers the small Neiraku Museum (Chinese and Korean bronzes).',
      ),
    ],
    averageRating: 4.4,
    reviewCount: 3000,
  ),
  PlaceGuide(
    id: 'naramachi',
    matches: ['naramachi'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/8/86/Street_in_Naramachi_area_%286156072416%29.jpg/960px-Street_in_Naramachi_area_%286156072416%29.jpg',
    ],
    visitDurationMin: 75,
    bestTimeOfDay: LText(
      'Öğleden sonra — kafeler ve atölyeler açıkken',
      'Afternoon — while the cafés and workshops are open',
    ),
    brief: LText(
      'Eski tüccar mahallesi: dar sokaklarda machiya (ahşap şehir evi) '
      'kafeler, zanaat dükkanları ve sake imalathaneleri. Nara\'nın '
      '"yavaş gezilecek" bölümü.',
      'An old merchant quarter: machiya (wooden townhouse) cafés, craft shops '
      'and sake breweries along narrow lanes. Nara\'s "slow-travel" corner.',
    ),
    tips: [
      LText(
        'Naramachi Koshi-no-Ie (restore machiya evi) ücretsiz gezilir.',
        'Naramachi Koshi-no-Ie (a restored machiya house) is free to visit.',
      ),
      LText(
        'Evlerin saçağındaki kırmızı maymun tılsımları (migawari-zaru) uğur.',
        'The red monkey charms under the eaves (migawari-zaru) are good-luck talismans.',
      ),
      LText(
        'Harushika sake imalathanesinde 5 çeşit tadım ~500¥.',
        'A five-sake tasting at the Harushika brewery is about 500¥.',
      ),
      LText(
        'Mochi dövme şovuyla ünlü Nakatanidou\'ya uğra (yomogi mochi).',
        'Stop by Nakatanidou, famous for its mochi-pounding show (yomogi mochi).',
      ),
    ],
    averageRating: 4.3,
    reviewCount: 8000,
  ),
  // ── Hiroshima ────────────────────────────────────────────────────────────
  PlaceGuide(
    id: 'peace-park',
    matches: ['barış anıtı', 'peace memorial', 'barış parkı'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/b/b2/20181111_Hiroshima_Memorial_Cenotaph-1.jpg/960px-20181111_Hiroshima_Memorial_Cenotaph-1.jpg',
    ],
    visitDurationMin: 120,
    bestTimeOfDay: LText(
      'Sabah — müzeye açılışta gir, parkı sonra yürü',
      'Morning — enter the museum at opening, then walk the park',
    ),
    brief: LText(
      'Atom bombasının patlama merkezine kurulmuş anıt parkı: Barış Müzesi, '
      'Çocuk Barış Anıtı (origami turnalar) ve anıt mezar. Müze girişi 200¥; '
      'ağır ama önemli bir deneyim.',
      'A memorial park built at the atomic bomb\'s hypocenter: the Peace '
      'Museum, the Children\'s Peace Monument (origami cranes) and the '
      'cenotaph. Museum entry 200¥; a heavy but important experience.',
    ),
    tips: [
      LText(
        'Müze için en az 1,5 saat ayır; sesli rehber almaya değer.',
        'Set aside at least 1.5 hours for the museum; the audio guide is worth it.',
      ),
      LText(
        'Sadako\'nun turna anıtına origami turna bırakabilirsin.',
        'You can leave an origami crane at Sadako\'s crane monument.',
      ),
      LText(
        'Anıt mezarın kemerinden bakınca kubbe tam hizada görünür.',
        'Looking through the cenotaph\'s arch, the dome lines up exactly.',
      ),
      LText(
        'Park içi ücretsiz ve her zaman açık — akşam da huzurlu.',
        'The park is free and always open — peaceful in the evening too.',
      ),
    ],
    averageRating: 4.7,
    reviewCount: 60000,
  ),
  PlaceGuide(
    id: 'genbaku-dome',
    matches: ['atom bombası', 'genbaku', 'a-bomb', 'kubbe'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/7/77/Genbaku_Dome04-r.JPG/960px-Genbaku_Dome04-r.JPG',
    ],
    visitDurationMin: 30,
    bestTimeOfDay: LText(
      'Gün batımı — nehir kıyısından siluet etkileyici',
      'Sunset — the silhouette from the riverbank is striking',
    ),
    brief: LText(
      'Patlamada ayakta kalan tek yapı; olduğu gibi korunuyor (UNESCO). '
      'Barış Parkı\'nın nehir karşısında; dışarıdan izlenir, içine girilmez.',
      'The only structure left standing after the blast, preserved as it was '
      '(UNESCO). Across the river from the Peace Park; viewed from outside, no '
      'entry.',
    ),
    tips: [
      LText(
        'Motoyasu nehri kıyısından hem kubbe hem yansıma karesi.',
        'From the bank of the Motoyasu River you get both the dome and its reflection.',
      ),
      LText(
        'Gönüllü rehberler (ücretsiz, İngilizce) çevrede bekliyor — dinle.',
        'Volunteer guides (free, in English) wait nearby — take a moment to listen.',
      ),
      LText(
        'Barış Parkı ile birlikte gez; tek başına 20-30 dk yeter.',
        'See it together with the Peace Park; 20–30 min alone is enough.',
      ),
    ],
    averageRating: 4.6,
    reviewCount: 40000,
  ),
  PlaceGuide(
    id: 'miyajima',
    matches: ['itsukushima', 'miyajima'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/e/ef/Itsukushima_Shrine_Torii_Gate_%2813890465459%29.jpg/960px-Itsukushima_Shrine_Torii_Gate_%2813890465459%29.jpg',
    ],
    visitDurationMin: 300,
    bestTimeOfDay: LText(
      'Gelgit saatine göre planla — yüksek gelgitte torii "yüzer"',
      'Plan around the tide — at high tide the torii "floats"',
    ),
    brief: LText(
      'Denizin içinde yükselen dev kırmızı torii kapısıyla Japonya\'nın en '
      'ünlü manzaralarından (UNESCO). Adada serbest geyikler, Momijidani '
      'parkı ve Misen dağı teleferiği de var.',
      'One of Japan\'s most famous views, with a giant red torii gate rising '
      'from the sea (UNESCO). The island also has free-roaming deer, Momijidani '
      'Park and the Mt. Misen ropeway.',
    ),
    tips: [
      LText(
        'Gelgit tablosuna bak: yüksekte torii yüzer, alçakta yanına yürünür — '
        'ikisi de güzel, ikisini de görecek şekilde kal.',
        'Check the tide table: at high tide the torii floats, at low tide you '
        'can walk up to it — both are lovely, so time your stay to see both.',
      ),
      LText(
        'Feribot JR hattı — JR Pass geçerli (~10 dk).',
        'The ferry is a JR line — JR Pass is valid (~10 min).',
      ),
      LText(
        'Momiji manju (akçaağaç kek) adanın imza tatlısı; sıcak taze al.',
        'Momiji manju (maple-leaf cakes) are the island\'s signature treat; get them hot and fresh.',
      ),
      LText(
        'Misen dağı teleferik + 30 dk yürüyüşle iç deniz panoraması.',
        'Mt. Misen offers an Inland Sea panorama via the ropeway plus a 30-min walk.',
      ),
      LText(
        'Gece ışıklandırması için adada konaklamak ayrı deneyim.',
        'Staying overnight on the island for the evening illumination is a whole other experience.',
      ),
    ],
    averageRating: 4.7,
    reviewCount: 50000,
  ),
  PlaceGuide(
    id: 'hiroshima-castle',
    matches: ['hiroshima kalesi', 'hiroshima castle'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/2/29/Keep_tower%2C_Hiroshima_Castle%2C_Southwest_remote_view_20190417_1.jpg/960px-Keep_tower%2C_Hiroshima_Castle%2C_Southwest_remote_view_20190417_1.jpg',
    ],
    visitDurationMin: 75,
    bestTimeOfDay: LText(
      'Öğleden sonra — Barış Parkı sabahının devamına uyar',
      'Afternoon — a natural follow-on from a Peace Park morning',
    ),
    brief: LText(
      '"Sazan Kalesi" — 1589 orijinali bombada yok oldu, 1958\'de yeniden '
      'yapıldı. İçi samuray kültürü müzesi; hendek ve surlarla çevrili park '
      'ücretsiz, kule 370¥.',
      'The "Carp Castle" — the 1589 original was destroyed by the bomb and '
      'rebuilt in 1958. Inside is a samurai-culture museum; the moat-and-wall '
      'park is free, the keep 370¥.',
    ),
    tips: [
      LText(
        'Kule tepesinden şehir manzarası — asansör yok, 5 kat merdiven.',
        'A city view from the top of the keep — no elevator, five floors of stairs.',
      ),
      LText(
        'Hendek kıyısı yürüyüşü sakura sezonunda çok güzel.',
        'The moat-side walk is lovely during cherry-blossom season.',
      ),
      LText(
        'Ninomaru kapı kompleksi (restore) ücretsiz gezilir.',
        'The (restored) Ninomaru gate complex is free to visit.',
      ),
    ],
    averageRating: 4.2,
    reviewCount: 20000,
  ),
  PlaceGuide(
    id: 'shukkeien',
    matches: ['shukkei'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/f/f3/Rainbow_bridge_in_Shukkei-en_Hiroshima.jpg/960px-Rainbow_bridge_in_Shukkei-en_Hiroshima.jpg',
    ],
    visitDurationMin: 60,
    bestTimeOfDay: LText(
      'Sabah — gölet durgunken yansımalar net',
      'Morning — reflections are crisp while the pond is still',
    ),
    brief: LText(
      '1620\'den kalma minyatür manzara bahçesi ("daraltılmış manzaralar"). '
      'Göletin ortasındaki taş kemerli Koko-kyo köprüsü simgesi. Giriş 260¥.',
      'A miniature landscape garden from 1620 ("shrunken scenery"). The '
      'stone-arched Koko-kyo bridge in the middle of the pond is its emblem. '
      'Entry 260¥.',
    ),
    tips: [
      LText(
        'Bahçeyi saat yönünde tam tur yürü (~40 dk) — her açı farklı.',
        'Walk a full clockwise loop of the garden (~40 min) — every angle differs.',
      ),
      LText(
        'Çay evinde matcha + wagashi molası (~500¥).',
        'A matcha and wagashi break at the tea house (~500¥).',
      ),
      LText(
        'Hiroshima kalesine 10 dk yürüme — aynı yarım güne koy.',
        'A 10-min walk to Hiroshima Castle — put them in the same half-day.',
      ),
    ],
    averageRating: 4.3,
    reviewCount: 8000,
  ),
  // ── Sapporo ──────────────────────────────────────────────────────────────
  PlaceGuide(
    id: 'odori',
    matches: ['odori'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/0/0d/Hokkaido_Sapporo_Odori_Park.jpg/960px-Hokkaido_Sapporo_Odori_Park.jpg',
    ],
    visitDurationMin: 60,
    bestTimeOfDay: LText(
      'Öğle — parkta yerel atıştırmalıklar; şubatta Kar Festivali',
      'Midday — local snacks in the park; the Snow Festival in February',
    ),
    brief: LText(
      'Şehri ikiye bölen 1,5 km\'lik park şeridi; ucundaki Sapporo TV Kulesi '
      'simge. Şubat Kar Festivali\'nin, yazın bira bahçelerinin merkezi.',
      'A 1.5km strip of park splitting the city in two, with the landmark '
      'Sapporo TV Tower at one end. The center of February\'s Snow Festival and '
      'summer\'s beer gardens.',
    ),
    tips: [
      LText(
        'Yazın (tem-ağu) park boyunca açık hava bira bahçeleri kurulur.',
        'In summer (Jul–Aug), open-air beer gardens line the park.',
      ),
      LText(
        'Tokibi (haşlanmış/ızgara mısır) arabaları parkın klasiği.',
        'The tokibi (boiled/grilled corn) carts are a park classic.',
      ),
      LText(
        'TV Kulesi yerine Moiwa dağı manzara için daha iyi — parayı ona sakla.',
        'Mt. Moiwa beats the TV Tower for the view — save your money for that.',
      ),
      LText(
        'Şubat Kar Festivali\'nde heykeller gece ışıklandırılır.',
        'During February\'s Snow Festival the sculptures are lit at night.',
      ),
    ],
    averageRating: 4.4,
    reviewCount: 20000,
  ),
  PlaceGuide(
    id: 'moiwa',
    matches: ['moiwa'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/7/7d/Moiwa_Mountain_in_Sapporo_in_2009.jpg/960px-Moiwa_Mountain_in_Sapporo_in_2009.jpg',
    ],
    visitDurationMin: 120,
    bestTimeOfDay: LText(
      'Günbatımından 30 dk önce çık — "Japonya\'nın 3 gece manzarası"ndan',
      'Head up 30 min before sunset — one of "Japan\'s 3 night views"',
    ),
    brief: LText(
      '531m\'lik dağın zirvesinden Sapporo\'nun ışık denizi — Japonya\'nın en '
      'iyi üç gece manzarasından biri seçildi. Teleferik + mini kablolu araç '
      'kombinasyonuyla çıkılır (~2100¥).',
      'From the summit of this 531m mountain, Sapporo becomes a sea of light — '
      'named one of Japan\'s three best night views. You go up via a ropeway '
      'plus a mini cable car (~2,100¥).',
    ),
    tips: [
      LText(
        'Hava kapalıysa gitme — manzara her şey demek.',
        'Skip it if the weather is overcast — the view is everything here.',
      ),
      LText(
        'Zirve terası soğuk olur; yazın bile bir kat fazla al.',
        'The summit deck gets cold; bring an extra layer even in summer.',
      ),
      LText(
        'Tramvay Ropeway-Iriguchi durağından ücretsiz servis var.',
        'There\'s a free shuttle from the Ropeway-Iriguchi tram stop.',
      ),
      LText(
        '"Aşk kilidi" çiti ve çan zirvenin klasiği.',
        'The "love lock" fence and bell are a summit classic.',
      ),
    ],
    averageRating: 4.5,
    reviewCount: 12000,
  ),
  PlaceGuide(
    id: 'sapporo-beer',
    matches: ['bira müzesi', 'beer museum', 'sapporo bira'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/a/a7/Sapporo_Beer_Museum.JPG/960px-Sapporo_Beer_Museum.JPG',
    ],
    visitDurationMin: 90,
    bestTimeOfDay: LText(
      'Öğleden sonra — tadım + akşam Genghis Khan yemeği',
      'Afternoon — a tasting, then a Genghis Khan dinner in the evening',
    ),
    brief: LText(
      'Japonya\'nın tek bira müzesi; 1890 kızıl tuğla fabrikada Sapporo '
      'birasının tarihi. Giriş ücretsiz, tadım katı ücretli. Bitişikteki '
      'Beer Garden\'da cengiz han (kuzu ızgara) klasiği.',
      'Japan\'s only beer museum, telling the story of Sapporo beer in an 1890 '
      'red-brick factory. Free entry, paid tasting floor. Next door, the Beer '
      'Garden serves the classic Genghis Khan (grilled lamb).',
    ),
    tips: [
      LText(
        'Tadım setinde "Kaitakushi" (kuruluş dönemi tarifi) sadece burada.',
        'The tasting set\'s "Kaitakushi" (a founding-era recipe) is available only here.',
      ),
      LText(
        'Premium tur (1000¥, rezervasyonlu) tadımlı ve müze arşivli.',
        'The premium tour (1,000¥, reserved) includes a tasting and the museum archive.',
      ),
      LText(
        'Akşam yemeği: Beer Garden\'da jingisukan — rezervasyon önerilir.',
        'For dinner: jingisukan at the Beer Garden — a reservation is recommended.',
      ),
      LText(
        'Pazartesi kapalı.',
        'Closed Mondays.',
      ),
    ],
    averageRating: 4.3,
    reviewCount: 15000,
  ),
  PlaceGuide(
    id: 'sapporo-clock',
    matches: ['saat kulesi', 'clock tower'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/4/42/Sapporo-Clock-Tower-2018.jpg/960px-Sapporo-Clock-Tower-2018.jpg',
    ],
    visitDurationMin: 30,
    bestTimeOfDay: LText(
      'Yol üstünde 20-30 dk\'lık kısa durak',
      'A quick 20–30 min stop along the way',
    ),
    brief: LText(
      '1878\'den kalma ahşap saat kulesi — Sapporo\'nun Batı tarzı kolonizasyon '
      'döneminin simgesi. Küçük ve gökdelenlerle çevrili; içi mütevazı bir '
      'müze (200¥).',
      'A wooden clock tower from 1878 — a symbol of Sapporo\'s Western-style '
      'pioneer era. Small and hemmed in by skyscrapers; inside is a modest '
      'museum (200¥).',
    ),
    tips: [
      LText(
        'Beklentiyi düşük tut — "küçükmüş" demek gelenek, yine de fotojenik.',
        'Keep expectations low — saying "it\'s small" is a tradition, yet it\'s still photogenic.',
      ),
      LText(
        'En iyi kare karşı binanın 2. kat terasından.',
        'The best shot is from the 2nd-floor terrace of the building across the street.',
      ),
      LText(
        'Odori parkı ve TV kulesiyle aynı yürüyüşe sığar.',
        'It fits into the same walk as Odori Park and the TV Tower.',
      ),
    ],
    averageRating: 4.0,
    reviewCount: 10000,
  ),
  PlaceGuide(
    id: 'susukino',
    matches: ['susukino'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/3/34/Spectaculars_of_Susukino-Sapporo.jpg/960px-Spectaculars_of_Susukino-Sapporo.jpg',
    ],
    visitDurationMin: 120,
    bestTimeOfDay: LText(
      'Akşam 19:00 sonrası — neonlar ve ramen sokağı',
      'After 19:00 — the neon and the ramen alley',
    ),
    brief: LText(
      'Kuzey Japonya\'nın en büyük eğlence bölgesi: neon kavşağı, binlerce '
      'restoran-bar ve Ramen Yokocho (17 dükkanlık ramen sokağı). Miso '
      'ramenin doğduğu şehirdesin.',
      'Northern Japan\'s largest entertainment district: a neon crossing, '
      'thousands of restaurants and bars, and Ramen Yokocho (a 17-shop ramen '
      'alley). You\'re in the city where miso ramen was born.',
    ),
    tips: [
      LText(
        'Ramen Yokocho\'da miso + tereyağı + mısır kombinasyonu Sapporo usulü.',
        'At Ramen Yokocho, the miso + butter + corn combo is the Sapporo way.',
      ),
      LText(
        'Nikka Whisky tabelalı kavşak şehrin klasik gece karesi.',
        'The crossing with the Nikka Whisky sign is the city\'s classic night shot.',
      ),
      LText(
        'Taze deniz ürünü için Nijo pazarı sabah, Susukino izakayaları akşam.',
        'For fresh seafood: Nijo market in the morning, Susukino izakayas in the evening.',
      ),
      LText(
        'Karaoke ve içki mekanları sabaha kadar açık.',
        'Karaoke and drinking spots stay open until morning.',
      ),
    ],
    averageRating: 4.3,
    reviewCount: 18000,
  ),
  // ── Kanazawa ─────────────────────────────────────────────────────────────
  PlaceGuide(
    id: 'kenrokuen',
    matches: ['kenroku'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/3/31/Stone_lantern_Kenrokuen.jpg/960px-Stone_lantern_Kenrokuen.jpg',
    ],
    visitDurationMin: 90,
    bestTimeOfDay: LText(
      'Sabah 07:00 açılış — tur grupları 09:30\'da gelir',
      'At the 07:00 opening — tour groups arrive by 09:30',
    ),
    brief: LText(
      'Japonya\'nın "üç büyük bahçesi"nden biri; iki ayaklı Kotoji feneri '
      'ülkenin en çok fotoğraflanan bahçe öğesi. Kışın yukitsuri (kar '
      'halatları) manzarası ünlü. Giriş 320¥.',
      'One of Japan\'s "three great gardens"; the two-legged Kotoji lantern is '
      'the country\'s most-photographed garden feature. The winter yukitsuri '
      '(snow ropes) are famous. Entry 320¥.',
    ),
    tips: [
      LText(
        'Kotoji feneri sabah ışığında ve kalabalıksız — ilk oraya git.',
        'The Kotoji lantern is best in morning light and without crowds — head there first.',
      ),
      LText(
        'Kışın kar halatları (yukitsuri) bahçenin imza görüntüsü.',
        'In winter, the snow ropes (yukitsuri) are the garden\'s signature sight.',
      ),
      LText(
        'Bitişik Kanazawa kalesiyle birleşik yarım gün planla.',
        'Plan a combined half-day with the adjacent Kanazawa Castle.',
      ),
      LText(
        'Bahçe içindeki çay evinde göl kenarında matcha molası.',
        'A lakeside matcha break at the garden\'s tea house.',
      ),
    ],
    averageRating: 4.5,
    reviewCount: 30000,
  ),
  PlaceGuide(
    id: 'kanazawa-castle',
    matches: ['kanazawa kalesi', 'kanazawa castle'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/8/88/Kanazawa-M-5937.jpg/960px-Kanazawa-M-5937.jpg',
    ],
    visitDurationMin: 75,
    bestTimeOfDay: LText(
      'Kenroku-en sabahının devamında',
      'As a follow-on to a Kenroku-en morning',
    ),
    brief: LText(
      'Maeda klanının kalesi; kurşun kiremitli beyaz duvarları ve geleneksel '
      'yöntemlerle restore edilen ahşap yapılarıyla ünlü. Park ücretsiz, '
      'restore binalar 320¥.',
      'The Maeda clan\'s castle, famous for its lead-tiled white walls and '
      'wooden buildings restored using traditional methods. The park is free, '
      'the restored buildings 320¥.',
    ),
    tips: [
      LText(
        'Gojukken Nagaya deposunun içindeki ahşap birleşim detaylarına bak.',
        'Look at the wooden joinery details inside the Gojukken Nagaya storehouse.',
      ),
      LText(
        'Ishikawa-mon kapısı Kenroku-en\'e bakar — geçiş oradan.',
        'The Ishikawa-mon gate faces Kenroku-en — cross over there.',
      ),
      LText(
        'Gyokusen\'inmaru bahçesi (ücretsiz) gün batımında ışıklandırılıyor.',
        'The Gyokusen\'inmaru garden (free) is illuminated at sunset.',
      ),
    ],
    averageRating: 4.3,
    reviewCount: 15000,
  ),
  PlaceGuide(
    id: 'higashi-chaya',
    matches: ['higashi chaya', 'chaya'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5e/Higashi_Chaya_district%2C_Kanazawa_%283809893551%29.jpg/960px-Higashi_Chaya_district%2C_Kanazawa_%283809893551%29.jpg',
    ],
    visitDurationMin: 75,
    bestTimeOfDay: LText(
      'Sabah 09:00 öncesi ya da akşamüstü — sokak boşken',
      'Before 09:00 or in the early evening — while the street is empty',
    ),
    brief: LText(
      '1820\'den kalma geyşa mahallesi; ahşap kafesli çay evleri şimdi kafe ve '
      'altın varak dükkanı. Kanazawa altın varak üretiminin %99\'unu yapar — '
      'altın kaplama dondurma burada doğdu.',
      'A geisha district dating to 1820; the lattice-fronted tea houses are now '
      'cafés and gold-leaf shops. Kanazawa makes 99% of Japan\'s gold leaf — '
      'the gold-covered ice cream was born here.',
    ),
    tips: [
      LText(
        'Altın varaklı dondurma (kinpaku soft) ~1000¥ — turistik ama eğlenceli.',
        'Gold-leaf ice cream (kinpaku soft) is ~1,000¥ — touristy but fun.',
      ),
      LText(
        'Kaikaro çay evi içi gezilebilir (750¥) — altın tatami odası var.',
        'You can tour inside the Kaikaro tea house (750¥) — it has a gold tatami room.',
      ),
      LText(
        'Ana sokağın paralelindeki arka sokaklar daha sakin ve otantik.',
        'The back lanes parallel to the main street are calmer and more authentic.',
      ),
      LText(
        'Hakuza dükkanında altın varak atölyesi izlenebilir.',
        'You can watch a gold-leaf workshop at the Hakuza shop.',
      ),
    ],
    averageRating: 4.4,
    reviewCount: 18000,
  ),
  PlaceGuide(
    id: 'omicho',
    matches: ['omicho'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/c/ce/Omicho_covered_market_western_entrance%2C_Kanazawa%2C_2016.jpg/960px-Omicho_covered_market_western_entrance%2C_Kanazawa%2C_2016.jpg',
    ],
    visitDurationMin: 75,
    bestTimeOfDay: LText(
      'Sabah 09:00–11:00 — kaisendon kuyrukları kısayken',
      'Morning 09:00–11:00 — while the kaisendon queues are short',
    ),
    brief: LText(
      '"Kanazawa\'nın mutfağı" — 300 yıllık pazar. Japon Denizi\'nden yengeç, '
      'karides ve mevsim balığı; üst kat restoranlarında kaisendon (deniz '
      'ürünlü don) klasiği.',
      '"Kanazawa\'s kitchen" — a 300-year-old market. Crab, shrimp and seasonal '
      'fish from the Sea of Japan; kaisendon (a seafood rice bowl) is the '
      'classic at the upstairs restaurants.',
    ),
    tips: [
      LText(
        'Kaisendon için 11:00 öncesi otur — öğlen kuyruğu 1 saati bulur.',
        'Grab a seat before 11:00 for kaisendon — the midday queue hits an hour.',
      ),
      LText(
        'Kış sezonu (kas-mar) kano yengeci zamanı — pahalı ama zirve tat.',
        'Winter (Nov–Mar) is snow-crab season — expensive but peak flavor.',
      ),
      LText(
        'Tezgahtan alıp yerinde yenen ızgara tarak/karides de var.',
        'There are also grilled scallops and shrimp to buy and eat on the spot.',
      ),
      LText(
        'Pazar günü bazı tezgahlar kapalı.',
        'Some stalls close on Sundays.',
      ),
    ],
    averageRating: 4.3,
    reviewCount: 20000,
  ),
  PlaceGuide(
    id: 'kanazawa-21c',
    matches: ['21. yüzyıl', '21st century', 'yüzyıl müzesi'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/b/b2/21st_Century_Museum_of_Contemporary_Art%2C_Kanazawa011.jpg/960px-21st_Century_Museum_of_Contemporary_Art%2C_Kanazawa011.jpg',
    ],
    visitDurationMin: 105,
    bestTimeOfDay: LText(
      'Hafta içi öğleden önce — "Havuz" eseri sırasız',
      'Weekday morning — no queue for the "Pool" artwork',
    ),
    brief: LText(
      'Dairesel camdan çağdaş sanat müzesi; Leandro Erlich\'in "Swimming '
      'Pool"u (havuzun altından bakanlarla göz göze gelirsin) en ünlü eseri. '
      'Çevre galeriler ücretsiz, sergiler biletli.',
      'A circular glass contemporary-art museum; Leandro Erlich\'s "Swimming '
      'Pool" (you meet the eyes of people looking up from beneath the pool) is '
      'its most famous work. The surrounding galleries are free, exhibitions '
      'ticketed.',
    ),
    tips: [
      LText(
        'Havuzun altına inmek için saatli bilet — girişte hemen al.',
        'A timed ticket is needed to go beneath the pool — buy it right at the entrance.',
      ),
      LText(
        'Hafta sonu havuz kuyruğu 1+ saat; hafta içi git.',
        'The pool queue is 1+ hour on weekends; go on a weekday.',
      ),
      LText(
        'Ücretsiz alandaki Turrell odası ve renk küpleri de görülmeye değer.',
        'The Turrell room and color cubes in the free area are also worth seeing.',
      ),
      LText(
        'Pazartesi kapalı. Kenroku-en\'e 5 dk yürüme.',
        'Closed Mondays. A 5-min walk to Kenroku-en.',
      ),
    ],
    averageRating: 4.4,
    reviewCount: 25000,
  ),
  // ── Ulaşım ───────────────────────────────────────────────────────────────
  PlaceGuide(
    id: 'shinkansen',
    matches: ['shinkansen', 'nozomi', 'hikari', 'bullet train'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/8/88/Series-N700S-J2.jpg/960px-Series-N700S-J2.jpg',
    ],
    visitDurationMin: 135, // Tokyo-Kyoto ~2s 15dk
    bestTimeOfDay: LText(
      'Sabah 07:00–09:00 — Fuji görüntü şansı sağ pencere',
      'Morning 07:00–09:00 — a chance to see Fuji from the right-side window',
    ),
    brief: LText(
      'Yüksek hızlı tren. Nozomi (en hızlı, JR Pass geçmez), Hikari (JR Pass), '
      'Kodama (her istasyon). Tokyo → Kyoto: ~2 saat 15 dk, ~14.170¥.',
      'The high-speed train. Nozomi (fastest, not valid with the JR Pass), '
      'Hikari (JR Pass), Kodama (every station). Tokyo → Kyoto: ~2 hours 15 '
      'min, ~14,170¥.',
    ),
    tips: [
      LText(
        'Tokyo→Kyoto yönünde Fuji sağda: D veya E koltuğu seç.',
        'Heading Tokyo→Kyoto, Fuji is on the right: pick seat D or E.',
      ),
      LText(
        'Smart-EX uygulaması ile 1 ay önceden koltuk seç.',
        'Reserve your seat up to a month ahead with the Smart-EX app.',
      ),
      LText(
        'İstasyonda ekiben (tren bentosu) al — trende yemek geleneği.',
        'Grab an ekiben (train bento) at the station — eating on board is a tradition.',
      ),
      LText(
        'Büyük valiz için "oversized baggage" koltuğu rezervasyonu gerekli.',
        'A large suitcase requires an "oversized baggage" seat reservation.',
      ),
    ],
    advanceBookingDays: 30,
    averageRating: 4.8,
    reviewCount: 12000,
    bookingHint: LText(
      'Smart-EX (global.jr-central.co.jp) veya JR East Reserve.',
      'Smart-EX (global.jr-central.co.jp) or JR East Reserve.',
    ),
  ),
];

PlaceGuide? matchPlaceGuide(String title) {
  final t = title.toLowerCase();
  for (final g in _kGuides) {
    for (final m in g.matches) {
      if (t.contains(m)) return g;
    }
  }
  return null;
}
