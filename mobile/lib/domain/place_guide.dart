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

  /// "Sabah erken", "Öğleden sonra" gibi kısa öneri.
  final String bestTimeOfDay;

  /// Bir paragraflık faydalı özet — ne için ünlü, ne beklenir.
  final String brief;

  /// Ziyaretçi ipuçları listesi (kısa cümleler).
  final List<String> tips;

  /// Bilet kaç gün önceden alınmalı (null ise gerekmez).
  final int? advanceBookingDays;

  /// 0..5 arası ortalama puan (bilinen halka açık istatistiklerden).
  final double? averageRating;

  /// Ortalama puanın kaç yoruma dayandığı (yaklaşık).
  final int? reviewCount;

  /// Rezervasyon platform ipucu ("Klook", "Smart-EX" vb.).
  final String? bookingHint;
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
    bestTimeOfDay: 'Sabah 07:00–09:00 (kalabalıksız kareler)',
    brief:
        'Tokyo\'nun en eski Budist tapınağı (7. yy). Kaminarimon kapısı, '
        'Nakamise alışveriş caddesi ve ana pagoda başlıca duraklar. Giriş '
        'ücretsiz, dış alan 24 saat açık; ana salon 06:00–17:00 arası.',
    tips: [
      'Sabah 08:00\'den önce fotoğraf için ideal; sonrasında yoğunlaşır.',
      'Nakamise\'de melonpan ve ningyo-yaki (bebek şekilli tatlı) dene.',
      'Kaminarimon fenerinin dibinden fotoğraf çekmek için sıra oluşur.',
      'Cebindeki 100¥\'la omikuji (fal) çekmek gelenek.',
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
    bestTimeOfDay: 'Gün batımı (16:30–18:00) — hem gündüz hem gece manzarası',
    brief:
        '634m ile Japonya\'nın en yüksek yapısı. İki gözlem katı: Tembo Deck '
        '(350m) ve Tembo Galleria (450m). Alt katta Solamachi AVM ve akvaryum.',
    tips: [
      'Kombine bilet (iki gözlem katı) tekli almaktan uygun.',
      'Hafta içi sabahları ya da yağmurlu günler sırasız girmek için iyi.',
      'Fuji görebilmek için hava açık ve öğleden önce olmalı.',
      'Solamachi\'de yerel restoranlar üst kattan uygun fiyatlı.',
    ],
    advanceBookingDays: 30,
    averageRating: 4.4,
    reviewCount: 65000,
    bookingHint: 'Resmî site veya Klook — sezon önce doldurabilir.',
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
    bestTimeOfDay: 'İlk seans (09:00–10:00) — kalabalıksız, sırasız',
    brief:
        'Etkileşimli dijital sanat müzesi. Planets: çıplak ayak, ıslak alanlar var '
        '(paçası kıvrılabilen pantolon ya da şort uygun). Borderless '
        'Azabudai Hills\'te — daha büyük ve labirentimsi.',
    tips: [
      'Bilet saat-slotlu satılır; en az 3-4 hafta önceden al.',
      'Ayna zeminler yansımalı — etek yerine pantolon tercih et.',
      'Çıplak ayak alanı var; büyük çanta locker\'a bırakılır.',
      'Fotoğraf için karanlıkta parlayan salonlar en popüleri.',
    ],
    advanceBookingDays: 30,
    averageRating: 4.6,
    reviewCount: 42000,
    bookingHint: 'teamLab resmî sitesi ya da Klook — cumartesi hızlıca dolar.',
  ),
  PlaceGuide(
    id: 'shibuya-crossing',
    matches: ['shibuya crossing', 'shibuya kavşak', 'shibuya sky', 'shibuya'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/8/88/Shibuya_Crossing%2C_Aerial.jpg/960px-Shibuya_Crossing%2C_Aerial.jpg',
      'https://upload.wikimedia.org/wikipedia/commons/thumb/4/45/SHIBUYA_SCRAMBLE_SQUARE_East_Tower.jpg/960px-SHIBUYA_SCRAMBLE_SQUARE_East_Tower.jpg',
    ],
    visitDurationMin: 90,
    bestTimeOfDay: 'Akşam 18:00–20:00 — hem kalabalık kavşak hem gece manzarası',
    brief:
        'Dünyanın en yoğun yaya kavşağı — bir yeşil ışıkta ~3000 kişi. Shibuya '
        'Sky (229m) açık teraslı gözlem alanı, günbatımı için ünlü.',
    tips: [
      'Kavşağı üstten görmek için Mag\'s Park ya da Shibuya Sky.',
      'Shibuya Sky bileti günü bulunmaz — 1-2 hafta önce al.',
      'Hachiko heykelinden başla, kavşağı geç, sonra Sky\'a çık.',
      'Cuma-Cumartesi akşamı en kalabalık — foto için ideal.',
    ],
    advanceBookingDays: 14,
    averageRating: 4.5,
    reviewCount: 58000,
    bookingHint: 'Shibuya Sky için Klook/JTB.',
  ),
  PlaceGuide(
    id: 'meiji-jingu',
    matches: ['meiji jingu', 'meiji'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/8/8b/Meiji_Jingu_2023-3.jpg/960px-Meiji_Jingu_2023-3.jpg',
    ],
    visitDurationMin: 75,
    bestTimeOfDay: 'Sabah 08:00–10:00 — orman yolu serin ve sakin',
    brief:
        'İmparator Meiji\'ye adanmış Şinto tapınağı; Harajuku\'nun yanında dev '
        'bir koru içinde. Devasa torii kapıları ve sake fıçısı duvarı ünlü. '
        'Giriş ücretsiz, gün doğumu–gün batımı açık.',
    tips: [
      'Hafta sonu sabahları geleneksel Şinto düğününe denk gelebilirsin.',
      'Ana yol çakıllı — rahat ayakkabı iyi olur.',
      'Harajuku/Takeshita caddesiyle aynı gün birleştir.',
      'Ema (dilek tahtası) yazmak için 500¥ ayır.',
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
    bestTimeOfDay: 'Sabah 09:00 açılış — piknik yerleri boşken',
    brief:
        'Tokyo\'nun en bakımlı parkı: Japon, İngiliz ve Fransız bahçeleri bir '
        'arada. Sakura mevsiminin en iyi noktalarından. Giriş 500¥, '
        'pazartesi kapalı.',
    tips: [
      'Alkol ve top oyunları yasak — sakin piknik parkı.',
      'Sakura sezonunda saat 10:00\'dan önce gir; kapıda sıra oluşur.',
      'Sera (tropik bahçe) girişe dahil, kaçırma.',
      'Shinjuku istasyonundan yürüme ~10 dk.',
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
    bestTimeOfDay: 'Öğleden sonra + akşam — neonlar karanlıkta iyi',
    brief:
        'Elektronik ve otaku kültürünün merkezi: anime/manga mağazaları, retro '
        'oyun katları, maid kafeler ve gachapon salonları. Dükkanlar genelde '
        '11:00\'da açılır.',
    tips: [
      'Retro oyun için Super Potato, figür için Radio Kaikan katları.',
      'Pazar günü ana cadde trafiğe kapanıyor (yaya cenneti).',
      'Tax-free alışveriş için pasaportunu yanında taşı.',
      'Gachapon Kaikan\'da yüzlerce kapsül makinesi var — bozukluk hazırla.',
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
    bestTimeOfDay: 'Akşam — kule turuncu aydınlatmayla en fotojenik',
    brief:
        '333m\'lik ikonik kızıl-beyaz kule (1958). Main Deck 150m, Top Deck '
        '250m. Skytree\'den daha nostaljik ve merkezi; Zojoji tapınağıyla '
        'aynı karede çekilir.',
    tips: [
      'Zojoji tapınağı tarafından kule + tapınak karesi klasik.',
      'Top Deck turu saatli ve rezervasyonlu; Main Deck genelde sırasız.',
      'Gece ışıklandırması yaz/kış farklı renkte.',
      'Kırmızı ışıklar kapanmadan (23:00) önce git.',
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
    bestTimeOfDay: 'Sabah — müzeler açılırken (09:30) kalabalık az',
    brief:
        'Tokyo\'nun müze parkı: Ulusal Müze, Bilim Müzesi, hayvanat bahçesi ve '
        'Shinobazu gölü aynı alanda. Sakura mevsiminde Japonya\'nın en ünlü '
        'hanami noktalarından.',
    tips: [
      'Müzelerin çoğu pazartesi kapalı — günü ona göre seç.',
      'Tokyo Ulusal Müzesi tek başına 2+ saat ister; önceliklendir.',
      'Ameyoko pazarı (istasyon tarafı) öğle yemeği için ideal.',
      'Panda görmek istersen hayvanat bahçesine açılışta gir.',
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
    bestTimeOfDay: 'Öğleden sonra; hafta sonu ana cadde yayalaşır',
    brief:
        'Tokyo\'nun lüks alışveriş bölgesi: amiral mağazalar, depachika (gurme '
        'bodrum katları) ve Kabuki-za tiyatrosu. Wako binasının saat kulesi '
        'semtin simgesi.',
    tips: [
      'Cumartesi-pazar 12:00–17:00 ana cadde trafiğe kapanır.',
      'Depachika için Mitsukoshi ya da Matsuya bodrum katı — örnek tadımlar.',
      'Uniqlo Ginza 12 kat — dünyanın en büyüğü.',
      'Kabuki-za\'da tek perde bileti (~1500-2000¥) turist dostu.',
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
    bestTimeOfDay: 'Sabah 08:00–10:00 — tezgahlar taze, kalabalık yönetilebilir',
    brief:
        'Eski balık halinin dış pazarı hâlâ Tokyo\'nun sokak lezzeti merkezi: '
        'tamagoyaki, taze sashimi, uni ve wagyu şişleri. Çoğu tezgah '
        '05:00–14:00 arası çalışır.',
    tips: [
      'Pazar günleri birçok dükkan kapalı — hafta içi git.',
      'Yürürken yemek ayıp sayılır; tezgah kenarında bitir.',
      'Nakiri bıçakları ve yeşil çay hediyelik için iyi.',
      'Öğleden sonra gidersen çoğu şey kapanmış olur.',
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
    bestTimeOfDay: 'Öğleden sonra gel, Rainbow Bridge günbatımıyla bitir',
    brief:
        'Körfezdeki yapay ada: dev Gundam heykeli, alışveriş merkezleri, '
        'Özgürlük Heykeli kopyası ve Rainbow Bridge manzarası. Yurikamome '
        'sürücüsüz treniyle ulaşım başlı başına eğlence.',
    tips: [
      'Yurikamome\'de en ön koltuk — köprü geçişi panoramik.',
      'Gundam heykeli akşam saatlerinde ışık/hareket gösterisi yapıyor.',
      'DiverCity food court hızlı ve uygun akşam yemeği.',
      'Plaj yürüyüşü günbatımında Rainbow Bridge karesi verir.',
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
    bestTimeOfDay: 'Hafta içi sabah 08:00 açılış — hafta sonu ~2× yoğun',
    brief:
        'Tokyo Disney Resort iki park içerir: Disneyland (klasik) ve DisneySea '
        '(dünyada tek — deniz temalı, yetişkin dostu). DisneySea benzersiz '
        'atraksiyonlarıyla öne çıkar.',
    tips: [
      'Premier Access (ücretli hızlı geçiş) uygulamadan gün içinde alınır.',
      'DisneySea\'de Journey to the Center of the Earth + Soaring öncelik.',
      'Resmî uygulamayı önceden indir — bekleme süreleri canlı görünür.',
      'Kapanış saati fişek gösterisini bekle; çıkış treni yoğun olur.',
    ],
    advanceBookingDays: 60,
    averageRating: 4.7,
    reviewCount: 210000,
    bookingHint: 'Resmî Tokyo Disney Resort sitesi ya da Klook.',
  ),
  // ── Kyoto ────────────────────────────────────────────────────────────────
  PlaceGuide(
    id: 'fushimi-inari',
    matches: ['fushimi inari', 'fushimi', 'inari'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/0/0e/Torii_path_with_lantern_at_Fushimi_Inari_Taisha_Shrine%2C_Kyoto%2C_Japan.jpg/960px-Torii_path_with_lantern_at_Fushimi_Inari_Taisha_Shrine%2C_Kyoto%2C_Japan.jpg',
    ],
    visitDurationMin: 120,
    bestTimeOfDay: 'Şafak 06:00–08:00 — kalabalıksız + soft ışık',
    brief:
        'Binlerce kırmızı torii kapılı ünlü Şinto tapınağı. Zirveye kadar yürüyüş '
        '~2 saat + geri dönüş. Torii tüneli fotoğraflarının çekildiği bölüm ilk '
        '15 dakikada, tepede daha az kalabalık ve manzara güzel.',
    tips: [
      'Sabah 07:00\'de git — 09:00 sonrası tur otobüsleri gelir.',
      'JR Inari (yaya 1 dk) veya Keihan Fushimi-Inari (5 dk).',
      'Kapı fotoğrafı için ilk büyük tünel değil, biraz yukarı çık.',
      'Yol üstündeki inari-sushi (tofu sushi) yerel imza tat.',
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
    bestTimeOfDay: 'Sabah 09:00 açılış — pavyonun altın rengi güneşte parlar',
    brief:
        'Yaldızlı üst iki katıyla ünlü Zen tapınağı. Tek yönlü yürüyüş rotası '
        '~30-45 dk. Küçük ama etkileyici — buradan Ryoan-ji taş bahçesine yürüyüş '
        '~15 dk.',
    tips: [
      'Giriş bileti bir dua kağıdı (fuda) — sakla, hediyelik gibi.',
      'Öğleden sonra otobüs çok kalabalık — sabah git.',
      'Yakın: Ryoan-ji (taş bahçe) + Ninnaji (sakura ünlü) aynı otobüs hattı.',
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
    bestTimeOfDay: 'Sabah 07:00–09:00 — bambu ormanı boşken, ışık dikey iner',
    brief:
        'Bambu ormanı, Togetsukyo köprüsü, maymun parkı ve Tenryu-ji tapınağı. '
        'Yürüyüş rotası ~2-3 saat sürer. Sonbaharda momiji (kızıl akçaağaç) '
        'muhteşem.',
    tips: [
      'Sabah 08:00\'den önce git — sonrası tur otobüsleri.',
      'Maymun parkı (Iwatayama) 15 dk tırmanış — çıkışta panorama.',
      'Tenryu-ji bahçesi + kuzey çıkışı → bambu ormanı en verimli rota.',
      'JR Saga-Arashiyama ya da Randen tramvayı.',
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
    bestTimeOfDay: 'Sabah 06:00 açılış — ahşap teras boşken gör',
    brief:
        'Kyoto\'nun simge tapınağı: çivisiz inşa edilmiş dev ahşap terası şehre '
        'bakar. Otowa şelalesinden su içmek dilek geleneği. Giriş 400¥; '
        'çevresindeki Higashiyama yokuşları da gezinin parçası.',
    tips: [
      'Sannenzaka-Ninenzaka yokuşlarından yürüyerek çık — dükkanlar şirin.',
      'Sabah 08:00 öncesi ya da akşam kapanışa yakın en sakini.',
      'Otowa şelalesinde üç sudan yalnız birinden iç (açgözlülük sayılır).',
      'Kiraz ve momiji sezonunda gece ışıklandırması oluyor — ayrıca gir.',
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
    bestTimeOfDay: 'Akşamüstü 17:00–19:00 — geyko/maiko işe çıkma saati',
    brief:
        'Kyoto\'nun geyşa mahallesi: ahşap machiya evleri, çay evleri ve taş '
        'kaplı Hanamikoji caddesi. Shirakawa kanalı boyunca yürüyüş özellikle '
        'akşam atmosferik.',
    tips: [
      'Geyko fotoğrafı çekmek için özel sokaklarda yasak levhalarına dikkat.',
      'Hanamikoji yerine Shirakawa tarafı daha sakin ve fotojenik.',
      'Yasaka tapınağı gece açık — Gion turunu onunla bitir.',
      'Kimono kiralayıp gezmek istersen sabah al, akşam iade.',
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
    bestTimeOfDay: 'Sabah 08:45 açılış — sarayın içi grupsuz gezilir',
    brief:
        'Tokugawa şogunlarının Kyoto sarayı (1603, UNESCO). "Bülbül zemin" '
        'gıcırtısıyla ünlü Ninomaru sarayı ve geniş bahçeler. Giriş + saray '
        '1300¥.',
    tips: [
      'Bülbül zemini duymak için sessiz bir aralık bekle.',
      'Saray içinde fotoğraf yasak — bahçede serbest.',
      'Sesli rehber (Türkçe yok, İngilizce var) hikayeyi çok açıyor.',
      'Ocak, temmuz, ağustos ve aralıkta bazı salı günleri saray kapalı.',
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
    bestTimeOfDay: 'Sabah — Felsefe Yolu yürüyüşüyle birleştir',
    brief:
        '"Gümüş Pavyon" — adının aksine gümüş kaplama yok; kum bahçesi ve yosun '
        'örtüsüyle Zen estetiğinin zirvesi sayılır. Felsefe Yolu\'nun kuzey ucunda.',
    tips: [
      'Felsefe Yolu\'nu Nanzen-ji\'den buraya yürü (~30 dk, sakura ünlü).',
      'Kum konisi (Kogetsudai) sabah ışığında en net görünür.',
      'Tepe yolundan Kyoto manzarası — rotanın sonuna sakla.',
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
    bestTimeOfDay: 'Akşam 18:00 sonrası — fenerler yanınca canlanır',
    brief:
        'Kamo nehrine paralel dar bir sokakta sıralanmış restoran ve izakayalar. '
        'Yazın nehir üstü terasları (kawadoko) açılır. Kyoto\'da akşam yemeği '
        'için en atmosferik sokak.',
    tips: [
      'Rezervasyonsuz gidersen 18:00 öncesi daha kolay yer bulursun.',
      'Menüsü kapıda yazmayan yerler pahalı olabilir — önce sor.',
      'Mayıs-eylül arası kawadoko (nehir terası) olan yer seç.',
      'Gion\'a yürüme mesafesi — ikisini aynı akşama koy.',
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
    bestTimeOfDay: 'Öğlen 10:00–16:00 — tezgahların hepsi açıkken',
    brief:
        '"Kyoto\'nun mutfağı" — 400 yıllık kapalı çarşıda 100+ tezgah: tsukemono '
        '(turşu), tofu tatlıları, yuba, taze deniz ürünü şişleri ve bıçakçılar.',
    tips: [
      'Tako tamago (yumurtalı bebek ahtapot) çarşının klasiği.',
      'Aritsugu bıçakçısında ustadan isim kazıma yaptırabilirsin.',
      'Yürürken yemek yerine tezgah yanında bitirmek adet.',
      'Çarşamba bazı dükkanlar kapalı; pazar kalabalık.',
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
    bestTimeOfDay: 'Sonbaharda sabah 08:30 açılış; diğer mevsimler sakin',
    brief:
        'Kyoto\'nun en büyük Zen tapınaklarından; Tsutenkyo köprüsünden bakılan '
        'akçaağaç vadisi Japonya\'nın en ünlü momiji manzarası. Kasım ortası '
        'zirve sezon.',
    tips: [
      'Momiji sezonunda (kasım) 08:00\'de kapıda ol — 10:00\'da izdiham.',
      'Hojo bahçesinin dama desenli yosun bahçesi modern Zen klasiği.',
      'Fushimi Inari\'ye tek durak — ikisini aynı sabaha koy.',
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
    bestTimeOfDay: 'Akşam 18:00–22:00 — neon ışıklar + street food canlanır',
    brief:
        'Osaka\'nın yeme-içme kalbi. Glico koşucusu tabelası, kanal boyu neonlar '
        've takoyaki tezgahları. Kanalı geçen Ebisu köprüsü klasik fotoğraf '
        'noktası.',
    tips: [
      'Takoyaki için Wanaka veya Kukuru — 45 dk sıra bekleyebilir.',
      'Ichiran ramen — kişisel bölmeler, ilk kez deneyimlemek için ideal.',
      '551 Horai buhar böreği (butaman) yol üzeri atıştırmalık.',
      'Glico tabelası karesi için Ebisu köprüsünün ortası.',
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
    bestTimeOfDay: 'Park açılışından 30 dk önce kapıda ol — ilk saatler en verimli',
    brief:
        'Super Nintendo World, Harry Potter Wizarding World ve Minion Park\'a '
        'ev sahipliği yapan tema parkı. Express Pass olmadan popüler '
        'atraksiyonlarda 90+ dk sıra beklenebilir.',
    tips: [
      'Nintendo World\'e giriş için uygulamadan "Timed Entry" al (ücretsiz).',
      'Express Pass pahalı ama tek günde her şeyi görmek istiyorsan değer.',
      'Öğle yemeğini 11:00 öncesi ya da 14:00 sonrası planla.',
      'JR Universal City istasyonu park girişine 5 dk yürüme.',
    ],
    advanceBookingDays: 60,
    averageRating: 4.5,
    reviewCount: 145000,
    bookingHint: 'Resmî site ya da Klook — Express Pass\'lar haftalar önce tükenir.',
  ),
  PlaceGuide(
    id: 'osaka-castle',
    matches: ['osaka kalesi', 'osaka castle'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/c/ca/Osaka_Castle_03bs3200.jpg/960px-Osaka_Castle_03bs3200.jpg',
    ],
    visitDurationMin: 120,
    bestTimeOfDay: 'Sabah 09:00 açılış — kule asansörü sırasız',
    brief:
        'Hideyoshi\'nin 1583\'te yaptırdığı kalenin betonarme rekonstrüksiyonu; '
        'içi müze, tepesi gözlem katı. Asıl güzellik dev taş surlar, hendekler '
        've park. Kule girişi 600¥.',
    tips: [
      'Nishinomaru bahçesinden kule + hendek karesi en iyisi (sakurada müthiş).',
      'Kule içi asansör kuyruğu öğlen uzar — sabah çık.',
      'Müze katları aşağı inerken gezilir; hikaye üstten başlar.',
      'Parkta sokak müzisyenleri ve food truck\'lar hafta sonu çıkar.',
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
    bestTimeOfDay: 'Akşam — Tsutenkaku kulesi ve tabelalar ışıl ışıl',
    brief:
        'Retro Osaka: 1912\'den kalma "Yeni Dünya" mahallesi, Tsutenkaku kulesi '
        've kushikatsu (çıtır şiş) restoranları. Nostaljik, hafif kitsch ve çok '
        'fotojenik.',
    tips: [
      'Kushikatsu\'da sosa ikinci kez banmak yasak — tek batırış!',
      'Daruma zinciri kushikatsu\'nun klasiği; kuyruk hızlı ilerler.',
      'Tsutenkaku\'nun tepesindeki Billiken heykelinin ayağını ovmak şans.',
      'Janjan Yokocho pasajı retro oyun salonlarıyla dolu.',
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
    bestTimeOfDay: 'Günbatımından 30 dk önce çık — gece geçişini izle',
    brief:
        'İki kuleyi tepede birleştiren "Yüzen Bahçe" gözlem katı (173m). Açık '
        'havada 360° Osaka panoraması; cam eskalatörle çıkış başlı başına '
        'deneyim. Giriş ~2000¥.',
    tips: [
      'Günbatımı slotu için biletini önceden online al.',
      'Açık teras rüzgarlı — ince bir kat fazla giy.',
      'Bodrumdaki Takimi-koji restoran katı Showa dönemi temalı.',
      'Osaka istasyonundan yeraltı geçidiyle ~10 dk yürüme.',
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
    bestTimeOfDay: 'Sabah 09:00–13:00 — deniz ürünleri en tazeyken',
    brief:
        '"Osaka\'nın mutfağı" — 190 yıllık kapalı pazar. Izgara tarak, uni, '
        'wagyu şiş, taze meyve ve fugu tezgahları. Nippombashi istasyonuna '
        'bitişik.',
    tips: [
      'Tezgahtan alıp oracıkta ızgaralatmak en iyisi — "grill?" diye sor.',
      'Meyve tezgahlarındaki dilim kavun/çilek pahalı ama efsane.',
      'Öğleden sonra 15:00 gibi tezgahlar kapanmaya başlar.',
      'Dotonbori\'ye 10 dk yürüme — öğle burada, akşam orada.',
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
    bestTimeOfDay: 'Akşam — Dotonbori\'yle birleşen eğlence saatleri',
    brief:
        'Osaka\'nın güney merkezi (Minami): Shinsaibashi kapalı çarşısı, '
        'Amerikamura gençlik modası ve Namba Parks terasları. Dotonbori\'nin '
        'kapısı sayılır.',
    tips: [
      'Shinsaibashi-suji çarşısı yağmurlu gün planı olarak birebir.',
      'Amerikamura ikinci el/vintage giyim için Osaka\'nın merkezi.',
      'Namba Parks\'ın kademeli çatı bahçesi sakin bir mola noktası.',
      'Den Den Town (Nipponbashi) Osaka\'nın Akihabara\'sı — yürüme mesafesi.',
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
    bestTimeOfDay: 'Sabah — tramvayla nostaljik bir yarım gün',
    brief:
        'Japonya\'daki tüm Sumiyoshi tapınaklarının merkezi (3. yy); Çin/Kore '
        'etkisi öncesi saf Japon mimarisi. Kamburlu kırmızı Sorihashi köprüsü '
        'simgesi. Giriş ücretsiz.',
    tips: [
      'Hankai tramvayıyla git — Osaka\'nın son sokak tramvayı, retro keyif.',
      'Sorihashi köprüsünün yansıma karesi için hendeğin batı yakası.',
      'Ayın ilk günü (tsuitachi-mairi) yerel ziyaretçi akını olur.',
      'Turist azdır — sakin bir "yerel Osaka" molası.',
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
    bestTimeOfDay: 'Günbatımı — Harukas 300 gözlem katından turuncu Osaka',
    brief:
        '300m ile Japonya\'nın en yüksek binalarından. Harukas 300 gözlem katı '
        '58-60. katlarda; camdan zemine kadar açık 360° manzara. Giriş ~2000¥, '
        'altında Kintetsu AVM.',
    tips: [
      'Gözlem katı bileti kapıdan alınır; hafta içi sıra kısa.',
      '58. kattaki açık avlu kafesinde manzaraya karşı kahve iç.',
      'Shitenno-ji tapınağına yürüme ~15 dk — ikisini birleştir.',
      'Gece 22:00\'ye kadar açık — akşam yemeği sonrası da olur.',
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
    bestTimeOfDay: 'Sabah — avlu sessizken',
    brief:
        'Japonya\'nın devlet eliyle kurulan ilk Budist tapınağı (593). Beş katlı '
        'pagoda ve Harukas gökdeleniyle aynı karede eski-yeni kontrastı. İç '
        'avlu 300¥, dış alan ücretsiz.',
    tips: [
      'Ayın 21-22\'sinde tapınak avlusunda bit pazarı kurulur.',
      'Pagodanın içine çıkılabilir (dar merdiven).',
      'Gokuraku-jodo bahçesi ayrı ücret ama çok sakin.',
      'Harukas\'la aynı yarım güne sığar.',
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
    bestTimeOfDay: 'Sabah 09:00 öncesi — geyikler aç ve nazik, kalabalık yok',
    brief:
        '1200+ serbest sika geyiğinin dolaştığı park; geyikler kutsal elçi '
        'sayılır ve selam verir (öğrenilmiş davranış). Todai-ji ve Kasuga '
        'Taisha parkın içinde.',
    tips: [
      'Geyik krakeri (shika senbei, 200¥) alınca hemen etrafın sarılır — '
          'krakerleri arkada tutma, ısırırlar.',
      'Kağıt/harita gibi şeyleri geyiklerden uzak tut — yerler.',
      'Öğlen tur grupları gelince geyikler doyar, ilgisizleşir.',
      'Park + Todai-ji + Kasuga rotası rahat yarım gün.',
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
    bestTimeOfDay: 'Sabah 08:00 açılış — Daibutsu salonu boşken görkemli',
    brief:
        'Dünyanın en büyük ahşap yapılarından Daibutsuden içinde 15m\'lik bronz '
        'Buda (752). Nandaimon kapısındaki Nio muhafız heykelleri de başyapıt. '
        'Giriş 800¥.',
    tips: [
      'Salondaki delikli sütundan geçebilen "aydınlanma" kazanır (çocuk boyu!).',
      'Nandaimon kapısında durup Nio heykellerine yukarıdan bak.',
      'Şubat-ekim 07:30, kasım-mart 08:00 açılış — erken git.',
      'Nigatsu-do terasına çık — Nara ovası manzarası ücretsiz.',
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
    bestTimeOfDay: 'Sabah — fenerli orman yolu loş ışıkta mistik',
    brief:
        'Nara\'nın koruyucu Şinto tapınağı (768, UNESCO); 3000 taş ve bronz '
        'feneriyle ünlü. Ormanın içindeki fener dizili yaklaşım yolu en '
        'atmosferik bölüm. Dış alan ücretsiz.',
    tips: [
      'İç avluya girmesen de fenerli yol tek başına değer.',
      'Şubat başı ve ağustos ortası tüm fenerler yakılır (Mantoro festivali).',
      'Fener deposu odasında (iç avlu) karanlıkta yanan fener simülasyonu var.',
      'Nara parkının geyikleri buraya kadar geliyor.',
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
    bestTimeOfDay: 'Gün batımına doğru — pagoda silueti göletten yansır',
    brief:
        'Fujiwara klanının aile tapınağı (710); beş katlı pagodası Nara\'nın '
        'simgesi. Ulusal Hazine Salonu\'ndaki üç yüzlü Ashura heykeli Japon '
        'sanatının başyapıtlarından.',
    tips: [
      'Ashura heykeli için Ulusal Hazine Salonu\'na gir (700¥) — değer.',
      'Sarusawa göletinin güney kıyısından pagoda yansıma karesi.',
      'Kintetsu Nara istasyonuna 5 dk — Nara turunun ilk durağı yap.',
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
    bestTimeOfDay: 'Sabah — Todai-ji kalabalığından önce sakin mola',
    brief:
        'Nara\'nın en güzel yürüyüş bahçesi; Todai-ji\'nin Nandaimon kapısını ve '
        'Wakakusa tepesini "ödünç manzara" (shakkei) olarak kullanır. Giriş '
        '1200¥, salı kapalı.',
    tips: [
      'Todai-ji ile aynı rotada — arada 15 dakikalık huzur molası.',
      'Bahçe iki bölüm: ön (17. yy) ve arka (Meiji) — arka daha fotojenik.',
      'Bilet küçük Neiraku müzesini de kapsıyor (Çin-Kore bronzları).',
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
    bestTimeOfDay: 'Öğleden sonra — kafeler ve atölyeler açıkken',
    brief:
        'Eski tüccar mahallesi: dar sokaklarda machiya (ahşap şehir evi) '
        'kafeler, zanaat dükkanları ve sake imalathaneleri. Nara\'nın '
        '"yavaş gezilecek" bölümü.',
    tips: [
      'Naramachi Koshi-no-Ie (restore machiya evi) ücretsiz gezilir.',
      'Evlerin saçağındaki kırmızı maymun tılsımları (migawari-zaru) uğur.',
      'Harushika sake imalathanesinde 5 çeşit tadım ~500¥.',
      'Mochi dövme şovuyla ünlü Nakatanidou\'ya uğra (yomogi mochi).',
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
    bestTimeOfDay: 'Sabah — müzeye açılışta gir, parkı sonra yürü',
    brief:
        'Atom bombasının patlama merkezine kurulmuş anıt parkı: Barış Müzesi, '
        'Çocuk Barış Anıtı (origami turnalar) ve anıt mezar. Müze girişi 200¥; '
        'ağır ama önemli bir deneyim.',
    tips: [
      'Müze için en az 1,5 saat ayır; sesli rehber almaya değer.',
      'Sadako\'nun turna anıtına origami turna bırakabilirsin.',
      'Anıt mezarın kemerinden bakınca kubbe tam hizada görünür.',
      'Park içi ücretsiz ve her zaman açık — akşam da huzurlu.',
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
    bestTimeOfDay: 'Gün batımı — nehir kıyısından siluet etkileyici',
    brief:
        'Patlamada ayakta kalan tek yapı; olduğu gibi korunuyor (UNESCO). '
        'Barış Parkı\'nın nehir karşısında; dışarıdan izlenir, içine girilmez.',
    tips: [
      'Motoyasu nehri kıyısından hem kubbe hem yansıma karesi.',
      'Gönüllü rehberler (ücretsiz, İngilizce) çevrede bekliyor — dinle.',
      'Barış Parkı ile birlikte gez; tek başına 20-30 dk yeter.',
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
    bestTimeOfDay: 'Gelgit saatine göre planla — yüksek gelgitte torii "yüzer"',
    brief:
        'Denizin içinde yükselen dev kırmızı torii kapısıyla Japonya\'nın en '
        'ünlü manzaralarından (UNESCO). Adada serbest geyikler, Momijidani '
        'parkı ve Misen dağı teleferiği de var.',
    tips: [
      'Gelgit tablosuna bak: yüksekte torii yüzer, alçakta yanına yürünür — '
          'ikisi de güzel, ikisini de görecek şekilde kal.',
      'Feribot JR hattı — JR Pass geçerli (~10 dk).',
      'Momiji manju (akçaağaç kek) adanın imza tatlısı; sıcak taze al.',
      'Misen dağı teleferik + 30 dk yürüyüşle iç deniz panoraması.',
      'Gece ışıklandırması için adada konaklamak ayrı deneyim.',
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
    bestTimeOfDay: 'Öğleden sonra — Barış Parkı sabahının devamına uyar',
    brief:
        '"Sazan Kalesi" — 1589 orijinali bombada yok oldu, 1958\'de yeniden '
        'yapıldı. İçi samuray kültürü müzesi; hendek ve surlarla çevrili park '
        'ücretsiz, kule 370¥.',
    tips: [
      'Kule tepesinden şehir manzarası — asansör yok, 5 kat merdiven.',
      'Hendek kıyısı yürüyüşü sakura sezonunda çok güzel.',
      'Ninomaru kapı kompleksi (restore) ücretsiz gezilir.',
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
    bestTimeOfDay: 'Sabah — gölet durgunken yansımalar net',
    brief:
        '1620\'den kalma minyatür manzara bahçesi ("daraltılmış manzaralar"). '
        'Göletin ortasındaki taş kemerli Koko-kyo köprüsü simgesi. Giriş 260¥.',
    tips: [
      'Bahçeyi saat yönünde tam tur yürü (~40 dk) — her açı farklı.',
      'Çay evinde matcha + wagashi molası (~500¥).',
      'Hiroshima kalesine 10 dk yürüme — aynı yarım güne koy.',
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
    bestTimeOfDay: 'Öğle — parkta yerel atıştırmalıklar; şubatta Kar Festivali',
    brief:
        'Şehri ikiye bölen 1,5 km\'lik park şeridi; ucundaki Sapporo TV Kulesi '
        'simge. Şubat Kar Festivali\'nin, yazın bira bahçelerinin merkezi.',
    tips: [
      'Yazın (tem-ağu) park boyunca açık hava bira bahçeleri kurulur.',
      'Tokibi (haşlanmış/ızgara mısır) arabaları parkın klasiği.',
      'TV Kulesi yerine Moiwa dağı manzara için daha iyi — parayı ona sakla.',
      'Şubat Kar Festivali\'nde heykeller gece ışıklandırılır.',
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
    bestTimeOfDay: 'Günbatımından 30 dk önce çık — "Japonya\'nın 3 gece manzarası"ndan',
    brief:
        '531m\'lik dağın zirvesinden Sapporo\'nun ışık denizi — Japonya\'nın en '
        'iyi üç gece manzarasından biri seçildi. Teleferik + mini kablolu araç '
        'kombinasyonuyla çıkılır (~2100¥).',
    tips: [
      'Hava kapalıysa gitme — manzara her şey demek.',
      'Zirve terası soğuk olur; yazın bile bir kat fazla al.',
      'Tramvay Ropeway-Iriguchi durağından ücretsiz servis var.',
      '"Aşk kilidi" çiti ve çan zirvenin klasiği.',
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
    bestTimeOfDay: 'Öğleden sonra — tadım + akşam Genghis Khan yemeği',
    brief:
        'Japonya\'nın tek bira müzesi; 1890 kızıl tuğla fabrikada Sapporo '
        'birasının tarihi. Giriş ücretsiz, tadım katı ücretli. Bitişikteki '
        'Beer Garden\'da cengiz han (kuzu ızgara) klasiği.',
    tips: [
      'Tadım setinde "Kaitakushi" (kuruluş dönemi tarifi) sadece burada.',
      'Premium tur (1000¥, rezervasyonlu) tadımlı ve müze arşivli.',
      'Akşam yemeği: Beer Garden\'da jingisukan — rezervasyon önerilir.',
      'Pazartesi kapalı.',
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
    bestTimeOfDay: 'Yol üstünde 20-30 dk\'lık kısa durak',
    brief:
        '1878\'den kalma ahşap saat kulesi — Sapporo\'nun Batı tarzı kolonizasyon '
        'döneminin simgesi. Küçük ve gökdelenlerle çevrili; içi mütevazı bir '
        'müze (200¥).',
    tips: [
      'Beklentiyi düşük tut — "küçükmüş" demek gelenek, yine de fotojenik.',
      'En iyi kare karşı binanın 2. kat terasından.',
      'Odori parkı ve TV kulesiyle aynı yürüyüşe sığar.',
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
    bestTimeOfDay: 'Akşam 19:00 sonrası — neonlar ve ramen sokağı',
    brief:
        'Kuzey Japonya\'nın en büyük eğlence bölgesi: neon kavşağı, binlerce '
        'restoran-bar ve Ramen Yokocho (17 dükkanlık ramen sokağı). Miso '
        'ramenin doğduğu şehirdesin.',
    tips: [
      'Ramen Yokocho\'da miso + tereyağı + mısır kombinasyonu Sapporo usulü.',
      'Nikka Whisky tabelalı kavşak şehrin klasik gece karesi.',
      'Taze deniz ürünü için Nijo pazarı sabah, Susukino izakayaları akşam.',
      'Karaoke ve içki mekanları sabaha kadar açık.',
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
    bestTimeOfDay: 'Sabah 07:00 açılış — tur grupları 09:30\'da gelir',
    brief:
        'Japonya\'nın "üç büyük bahçesi"nden biri; iki ayaklı Kotoji feneri '
        'ülkenin en çok fotoğraflanan bahçe öğesi. Kışın yukitsuri (kar '
        'halatları) manzarası ünlü. Giriş 320¥.',
    tips: [
      'Kotoji feneri sabah ışığında ve kalabalıksız — ilk oraya git.',
      'Kışın kar halatları (yukitsuri) bahçenin imza görüntüsü.',
      'Bitişik Kanazawa kalesiyle birleşik yarım gün planla.',
      'Bahçe içindeki çay evinde göl kenarında matcha molası.',
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
    bestTimeOfDay: 'Kenroku-en sabahının devamında',
    brief:
        'Maeda klanının kalesi; kurşun kiremitli beyaz duvarları ve geleneksel '
        'yöntemlerle restore edilen ahşap yapılarıyla ünlü. Park ücretsiz, '
        'restore binalar 320¥.',
    tips: [
      'Gojukken Nagaya deposunun içindeki ahşap birleşim detaylarına bak.',
      'Ishikawa-mon kapısı Kenroku-en\'e bakar — geçiş oradan.',
      'Gyokusen\'inmaru bahçesi (ücretsiz) gün batımında ışıklandırılıyor.',
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
    bestTimeOfDay: 'Sabah 09:00 öncesi ya da akşamüstü — sokak boşken',
    brief:
        '1820\'den kalma geyşa mahallesi; ahşap kafesli çay evleri şimdi kafe ve '
        'altın varak dükkanı. Kanazawa altın varak üretiminin %99\'unu yapar — '
        'altın kaplama dondurma burada doğdu.',
    tips: [
      'Altın varaklı dondurma (kinpaku soft) ~1000¥ — turistik ama eğlenceli.',
      'Kaikaro çay evi içi gezilebilir (750¥) — altın tatami odası var.',
      'Ana sokağın paralelindeki arka sokaklar daha sakin ve otantik.',
      'Hakuza dükkanında altın varak atölyesi izlenebilir.',
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
    bestTimeOfDay: 'Sabah 09:00–11:00 — kaisendon kuyrukları kısayken',
    brief:
        '"Kanazawa\'nın mutfağı" — 300 yıllık pazar. Japon Denizi\'nden yengeç, '
        'karides ve mevsim balığı; üst kat restoranlarında kaisendon (deniz '
        'ürünlü don) klasiği.',
    tips: [
      'Kaisendon için 11:00 öncesi otur — öğlen kuyruğu 1 saati bulur.',
      'Kış sezonu (kas-mar) kano yengeci zamanı — pahalı ama zirve tat.',
      'Tezgahtan alıp yerinde yenen ızgara tarak/karides de var.',
      'Pazar günü bazı tezgahlar kapalı.',
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
    bestTimeOfDay: 'Hafta içi öğleden önce — "Havuz" eseri sırasız',
    brief:
        'Dairesel camdan çağdaş sanat müzesi; Leandro Erlich\'in "Swimming '
        'Pool"u (havuzun altından bakanlarla göz göze gelirsin) en ünlü eseri. '
        'Çevre galeriler ücretsiz, sergiler biletli.',
    tips: [
      'Havuzun altına inmek için saatli bilet — girişte hemen al.',
      'Hafta sonu havuz kuyruğu 1+ saat; hafta içi git.',
      'Ücretsiz alandaki Turrell odası ve renk küpleri de görülmeye değer.',
      'Pazartesi kapalı. Kenroku-en\'e 5 dk yürüme.',
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
    bestTimeOfDay: 'Sabah 07:00–09:00 — Fuji görüntü şansı sağ pencere',
    brief:
        'Yüksek hızlı tren. Nozomi (en hızlı, JR Pass geçmez), Hikari (JR Pass), '
        'Kodama (her istasyon). Tokyo → Kyoto: ~2 saat 15 dk, ~14.170¥.',
    tips: [
      'Tokyo→Kyoto yönünde Fuji sağda: D veya E koltuğu seç.',
      'Smart-EX uygulaması ile 1 ay önceden koltuk seç.',
      'İstasyonda ekiben (tren bentosu) al — trende yemek geleneği.',
      'Büyük valiz için "oversized baggage" koltuğu rezervasyonu gerekli.',
    ],
    advanceBookingDays: 30,
    averageRating: 4.8,
    reviewCount: 12000,
    bookingHint: 'Smart-EX (global.jr-central.co.jp) veya JR East Reserve.',
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
