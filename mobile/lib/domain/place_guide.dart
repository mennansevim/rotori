// Popüler yerler için küratörlü rehber bilgisi:
// fotoğraflar (kaydırma için), ortalama ziyaret süresi, ön rezervasyon
// penceresi, günün en iyi zamanı, ortalama puan ve ziyaretçi ipuçları.
//
// PlaceGuide `matchPlaceGuide(title)` ile item başlığındaki anahtar kelimeler
// üzerinden çözülür. Eşleşme yoksa null döner — sheet fallback UI'ye düşer.

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

  /// Kaydırılabilir fotoğraf listesi. Wikipedia Commons ya da yerin resmi kaynağı.
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
  PlaceGuide(
    id: 'sensoji',
    matches: ['senso-ji', 'sensoji', 'senso ji', 'asakusa'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/f/f5/Senso-ji_%2816273325925%29.jpg/1024px-Senso-ji_%2816273325925%29.jpg',
      'https://upload.wikimedia.org/wikipedia/commons/thumb/6/60/Kaminarimon_2020.jpg/1024px-Kaminarimon_2020.jpg',
      'https://upload.wikimedia.org/wikipedia/commons/thumb/5/56/Nakamise-dori_Street_-_Sensoji_Temple_-_Asakusa_-_Tokyo_-_Japan_-_02_%2836651472090%29.jpg/1024px-Nakamise-dori_Street_-_Sensoji_Temple_-_Asakusa_-_Tokyo_-_Japan_-_02_%2836651472090%29.jpg',
    ],
    visitDurationMin: 90,
    bestTimeOfDay: 'Sabah 07:00–09:00 (kalabalıksız kareler)',
    brief:
        'Tokyo\'nun en eski Budist tapınağı (7. yy). Kaminarimon kapısı, '
        'Nakamise alışveriş caddesi ve ana pagoda başlıca duraklar. Giriş '
        'ücretsiz, 24 saat açık; iç mekân 06:00–17:00 arası.',
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
      'https://upload.wikimedia.org/wikipedia/commons/thumb/1/17/Tokyo_Skytree_2014_%E2%85%A2.jpg/800px-Tokyo_Skytree_2014_%E2%85%A2.jpg',
      'https://upload.wikimedia.org/wikipedia/commons/thumb/1/1a/Tokyo_Skytree_from_bridge.jpg/1024px-Tokyo_Skytree_from_bridge.jpg',
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
      'https://upload.wikimedia.org/wikipedia/commons/thumb/9/9f/TeamLab_Borderless_1.jpg/1024px-TeamLab_Borderless_1.jpg',
      'https://upload.wikimedia.org/wikipedia/commons/thumb/4/40/TeamLab_Borderless_2.jpg/1024px-TeamLab_Borderless_2.jpg',
    ],
    visitDurationMin: 150,
    bestTimeOfDay: 'İlk seans (09:00–10:00) — kalabalıksız, sırasız',
    brief:
        'Etkileşimli dijital sanat müzesi. Planets: çıplak ayak, ıslak alanlar var '
        '(pantolonu paçadan kıvırabileceğin kısa şort/etek uygun). Borderless '
        'Azabudai Hills\'te yeni açıldı — daha büyük ve karmaşık.',
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
    matches: [
      'shibuya crossing',
      'shibuya kavşak',
      'shibuya sky',
      'shibuya',
    ],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e2/Shibuya_Crossing_%2850302134256%29.jpg/1024px-Shibuya_Crossing_%2850302134256%29.jpg',
      'https://upload.wikimedia.org/wikipedia/commons/thumb/5/57/Shibuya_Sky_%2848731022367%29.jpg/1024px-Shibuya_Sky_%2848731022367%29.jpg',
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
    id: 'usj',
    matches: ['universal studios', 'usj', 'universal japan'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/4/4f/Universal_Studios_Japan_%2827661840418%29.jpg/1024px-Universal_Studios_Japan_%2827661840418%29.jpg',
    ],
    visitDurationMin: 600,
    bestTimeOfDay: 'Sabah 08:30 park açılışı — Express Pass\'sız bile queue kısa',
    brief:
        'Super Nintendo World, Harry Potter Wizarding World ve Minion Park \'a '
        'ev sahipliği yapan tema parkı. Express Pass olmadan popüler '
        'atraksiyonlarda 90+ dk sıra beklenebilir.',
    tips: [
      'Express Pass 7 (4200¥+) Minion Coaster + Nintendo dahil — değeri var.',
      'Nintendo World\'e "Timed Entry Ticket" veya Express Pass şart.',
      'Sabah 09:00\'dan önce park girişinde ol; ilk saatler en verimlisi.',
      'Öğle yemeği için 11:00\'dan önce ya da 14:00\'dan sonra planla.',
      'JR Universal Studios istasyonu direkt park girişine bağlar.',
    ],
    advanceBookingDays: 60,
    averageRating: 4.5,
    reviewCount: 145000,
    bookingHint: 'Klook\'ta Türkçe destek + kredi kartı — resmi sitede yalnız iyakan.',
  ),
  PlaceGuide(
    id: 'tokyo-disney',
    matches: ['disneyland', 'disneysea', 'tokyo disney', 'disney'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/7/76/Tokyo_Disneyland_castle_%282018%29.jpg/1024px-Tokyo_Disneyland_castle_%282018%29.jpg',
    ],
    visitDurationMin: 600,
    bestTimeOfDay: 'Hafta içi sabah 08:00 açılış — hafta sonu ~2× yoğun',
    brief:
        'Tokyo Disney Resort iki park içerir: Disneyland (klasik) ve DisneySea '
        '(dünyada tek — deniz temalı, yetişkin dostu). DisneySea nadir bulunan '
        'attraksiyonlarıyla öne çıkar.',
    tips: [
      'Premier Access uygulama üzerinden gün içi alınır — giriş bileti şart.',
      'DisneySea\'da Journey to the Center of the Earth + Toy Story Mania öncelik.',
      'Popcorn kovaları hediye/keçi olarak sınırlı sayıda çıkar — kuyruk oluşur.',
      'Karpuzu-yürüyen su kırışıklığı: geçit süresini akışta doldur.',
      'Nihon-koku Nikkei çıkış saatinde (21:00 civarı) tren dolu — bir sonrakini bekle.',
    ],
    advanceBookingDays: 60,
    averageRating: 4.7,
    reviewCount: 210000,
    bookingHint: 'Resmî Tokyo Disney Resort sitesi ya da Klook.',
  ),
  PlaceGuide(
    id: 'shinkansen',
    matches: ['shinkansen', 'nozomi', 'sakura', 'bullet train'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/a/a7/Shinkansen_N700A_Series_Set_G13.jpg/1024px-Shinkansen_N700A_Series_Set_G13.jpg',
    ],
    visitDurationMin: 135, // Tokyo-Kyoto ~2s 15dk
    bestTimeOfDay: 'Sabah 07:00–09:00 — Fuji görüntü şansı sağ pencere',
    brief:
        'Yüksek hızlı tren. Nozomi (en hızlı, JR Pass geçmez), Hikari (JR Pass), '
        'Kodama (her istasyon). Tokyo → Kyoto: ~2 saat 15 dk, ~14.170¥.',
    tips: [
      'Sağ pencere (D) koltuğu — Fuji manzarası (sabah, açık havada).',
      'Smart-EX uygulaması ile 1 ay önceden koltuk seç.',
      'İstasyonda ekiben (raylı yemek) al — trende yemek geleneği.',
      'JR Pass sahipleri Nozomi\'de değil Hikari\'de binmelidir.',
    ],
    advanceBookingDays: 30,
    averageRating: 4.8,
    reviewCount: 12000,
    bookingHint: 'Smart-EX (globalny.jr-central.co.jp) veya JR East Reserve.',
  ),
  PlaceGuide(
    id: 'fushimi-inari',
    matches: ['fushimi inari', 'fushimi', 'inari'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5a/Fushimi_Inari-taisha%2C_Fushimi-ku_Kyoto_January2015.jpg/1024px-Fushimi_Inari-taisha%2C_Fushimi-ku_Kyoto_January2015.jpg',
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
      'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c3/Kinkaku-ji_the_Golden_Temple_in_Kyoto_overlooking_the_lake_-_high_rez.JPG/1024px-Kinkaku-ji_the_Golden_Temple_in_Kyoto_overlooking_the_lake_-_high_rez.JPG',
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
      'https://upload.wikimedia.org/wikipedia/commons/thumb/4/45/Arashiyama_Bamboo_Grove%2C_Kyoto%2C_Japan.jpg/1024px-Arashiyama_Bamboo_Grove%2C_Kyoto%2C_Japan.jpg',
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
    id: 'dotonbori',
    matches: ['dotonbori', 'dōtonbori', 'dontonbori', 'dötonbori'],
    imageUrls: [
      'https://upload.wikimedia.org/wikipedia/commons/thumb/3/3b/Dotonbori_at_night_%2810293068894%29.jpg/1024px-Dotonbori_at_night_%2810293068894%29.jpg',
    ],
    visitDurationMin: 150,
    bestTimeOfDay: 'Akşam 18:00–22:00 — neon ışıklar + street food canlanır',
    brief:
        'Osaka\'nın yeme-içme kalbi. Glico koşucusu tabelası, Kuidaore çukur '
        'sokakları ve takoyaki. Kanalı geçen köprü klasik fotoğraf noktası.',
    tips: [
      'Takoyaki için Wanaka veya Kukuru — 45 dk sıra bekleyebilir.',
      'Ichiran ramen — kişisel bölmeler, ilk kez deneyimlemek için ideal.',
      '551 Horai buhar böreği (butaman) yol üzeri atıştırmalık.',
      'Nakaza Cuidaore önündeki animatronik satsuma davulcusu foto sebebi.',
    ],
    averageRating: 4.5,
    reviewCount: 89000,
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
