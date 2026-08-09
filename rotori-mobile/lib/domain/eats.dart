// Rotori Eats — küratörlü restoran verisi (saf Dart, offline).
//
// Google Places API yok: veri gömülü/küratörlüdür, dış maliyet sıfırdır.
// İleride Supabase `restaurants` tablosundan beslenecek şekilde tasarlandı
// (aynı alanlar). `mapsQuery` Google Maps arama linki için kullanılır.
//
// ## Neden bu model (rakip analizi)
//
// Halal Navi / Halal Gourmet Japan helal aramayı çözer ama bütçe, plan ve
// mutfak bağlamı yoktur. Tabelog yerel kaliteyi çözer ama diyet filtresi ve
// İngilizce dostu pratik bilgileri (kart geçer mi, kuyruk var mı) yoktur.
// Google Maps saati/konumu çözer ama puanları turist enflasyonludur ve helal
// güvenilirliği hakkında hiçbir şey söylemez. HappyCow diyeti çözer ama
// Japonya'ya özgü pratikleri bilmez.
//
// Rotori'nin farkı: kullanıcının PLANINI, BÜTÇESİNİ ve DİYETİNİ aynı anda
// bilmesi. Model bu yüzden üç eksene birden veri taşır:
//   1) güven  → [HalalTrust] / [VeggieLevel] (bool değil, seviye)
//   2) bütçe  → [PriceTier] + gerçek ¥ bandı
//   3) pratik → [EatsAmenity] (kart, İngilizce menü, kuyruk, namaz alanı…)
//
// ## Veri dürüstlüğü kuralı
//
// [HalalTrust.certified] YALNIZCA kamuya açık kaynaklarda helal sertifikalı
// olduğu belgelenmiş mekanlar içindir. Şüphe varsa bir alt seviye seçilir.
// Sertifika durumu değişebildiği için her kayıtta [verifiedOn] vardır ve UI
// kullanıcıyı mekanda teyit etmeye yönlendirir. Uydurma sertifika işaretlenmez.

import 'geofence.dart' show LatLng, distanceMeters;
import 'localized_text.dart';

/// Helal güven seviyesi. Japonya'da tek bir "helal" yoktur; sertifika
/// kuruluşları en az üç farklı durumu ayırır ve bu ayrım Müslüman gezgin için
/// kritiktir (bkz. NPO Japan Halal Association sınıflandırması).
enum HalalTrust {
  /// Tam helal sertifikalı; mutfakta domuz/alkol yok.
  certified,

  /// "Muslim-friendly": yemek helal ama mekanda alkol servisi olabilir veya
  /// mutfak paylaşımlıdır. Mirin/pişirme sakesi kullanımı mümkündür.
  muslimFriendly,

  /// Helal değil ama domuzsuz seçenek net biçimde vardır.
  porkFreeOption,

  /// Helal bilgisi yok / uygun değil.
  none,
}

extension HalalTrustX on HalalTrust {
  /// Sıralamada "daha güvenli" olan daha yüksek puan alır.
  int get weight => switch (this) {
        HalalTrust.certified => 3,
        HalalTrust.muslimFriendly => 2,
        HalalTrust.porkFreeOption => 1,
        HalalTrust.none => 0,
      };

  LText get label => switch (this) {
        HalalTrust.certified => const LText('Helal sertifikalı', 'Halal certified'),
        HalalTrust.muslimFriendly =>
          const LText('Müslüman dostu', 'Muslim-friendly'),
        HalalTrust.porkFreeOption =>
          const LText('Domuzsuz seçenek', 'Pork-free option'),
        HalalTrust.none => const LText('Helal değil', 'Not halal'),
      };

  /// Kullanıcıya seviyenin ne DEMEK olduğunu anlatan kısa açıklama.
  /// Rakiplerin çoğu bunu göstermez; "helal" rozetinin arkasındaki belirsizlik
  /// tam da burada saklanır.
  LText get explainer => switch (this) {
        HalalTrust.certified => const LText(
            'Sertifika kuruluşu onaylı. Mutfakta domuz ve alkol yok.',
            'Approved by a certification body. No pork or alcohol in the kitchen.',
          ),
        HalalTrust.muslimFriendly => const LText(
            'Yemek helal kabul edilir; mekanda alkol servisi veya paylaşımlı '
                'mutfak olabilir. Hassassan sipariş öncesi sor.',
            'Food is treated as halal, but the venue may serve alcohol or share '
                'a kitchen. Ask before ordering if you are strict.',
          ),
        HalalTrust.porkFreeOption => const LText(
            'Helal sertifikası yok; domuzsuz seçenekler net. Et kesimi helal '
                'olmayabilir.',
            'No halal certificate; pork-free options are clear. Meat may not be '
                'halal-slaughtered.',
          ),
        HalalTrust.none => const LText(
            'Helal uyumu belirtilmemiş.',
            'No halal compliance stated.',
          ),
      };

  String get emoji => switch (this) {
        HalalTrust.certified => '🕌',
        HalalTrust.muslimFriendly => '🌙',
        HalalTrust.porkFreeOption => '🚫🐷',
        HalalTrust.none => '',
      };
}

/// Vejetaryen/vegan uygunluk seviyesi — yine bool değil, seviye.
enum VeggieLevel {
  /// Tamamen vegan menü.
  veganMenu,

  /// Tam vejetaryen menü (yumurta/süt olabilir).
  vegetarianMenu,

  /// Karışık menü ama net vejetaryen seçenek var.
  veggieOption,

  /// Vejetaryen seçenek yok/güvenilmez (ör. dashi her yerde).
  none,
}

extension VeggieLevelX on VeggieLevel {
  int get weight => switch (this) {
        VeggieLevel.veganMenu => 3,
        VeggieLevel.vegetarianMenu => 2,
        VeggieLevel.veggieOption => 1,
        VeggieLevel.none => 0,
      };

  LText get label => switch (this) {
        VeggieLevel.veganMenu => const LText('Vegan menü', 'Vegan menu'),
        VeggieLevel.vegetarianMenu =>
          const LText('Vejetaryen menü', 'Vegetarian menu'),
        VeggieLevel.veggieOption =>
          const LText('Vejetaryen seçenek', 'Vegetarian option'),
        VeggieLevel.none => const LText('Vejetaryen yok', 'No vegetarian option'),
      };

  String get emoji => switch (this) {
        VeggieLevel.veganMenu => '🌱',
        VeggieLevel.vegetarianMenu => '🥗',
        VeggieLevel.veggieOption => '🥬',
        VeggieLevel.none => '',
      };
}

/// Kişi başı fiyat kademesi. Bütçe uyumu skoru bunun üzerinden hesaplanır.
enum PriceTier { budget, mid, upper, splurge }

extension PriceTierX on PriceTier {
  String get symbol => switch (this) {
        PriceTier.budget => '¥',
        PriceTier.mid => '¥¥',
        PriceTier.upper => '¥¥¥',
        PriceTier.splurge => '¥¥¥¥',
      };

  /// Kademe için tipik kişi başı üst sınır (JPY) — bütçe eşleşmesinde kullanılır.
  int get typicalCeilingJpy => switch (this) {
        PriceTier.budget => 1500,
        PriceTier.mid => 3500,
        PriceTier.upper => 7000,
        PriceTier.splurge => 15000,
      };

  LText get label => switch (this) {
        PriceTier.budget => const LText('Ekonomik', 'Budget'),
        PriceTier.mid => const LText('Orta', 'Mid'),
        PriceTier.upper => const LText('Üst', 'Upper'),
        PriceTier.splurge => const LText('Özel gün', 'Splurge'),
      };

  /// Kişi başı bütçeye (JPY) karşılık gelen en yüksek uygun kademe.
  static PriceTier forBudget(int jpyPerPerson) {
    if (jpyPerPerson <= 1500) return PriceTier.budget;
    if (jpyPerPerson <= 3500) return PriceTier.mid;
    if (jpyPerPerson <= 7000) return PriceTier.upper;
    return PriceTier.splurge;
  }
}

/// Mutfak türü — filtre popup'ındaki ana kategori ekseni.
enum EatsCuisine {
  ramen,
  sushi,
  yakiniku,
  curry,
  okonomiyaki,
  tempura,
  udonSoba,
  izakaya,
  kaiseki,
  burger,
  cafe,
  streetFood,
  kushikatsu,
  worldFood,
}

extension EatsCuisineX on EatsCuisine {
  String get emoji => switch (this) {
        EatsCuisine.ramen => '🍜',
        EatsCuisine.sushi => '🍣',
        EatsCuisine.yakiniku => '🥩',
        EatsCuisine.curry => '🍛',
        EatsCuisine.okonomiyaki => '🥞',
        EatsCuisine.tempura => '🍤',
        EatsCuisine.udonSoba => '🍲',
        EatsCuisine.izakaya => '🍢',
        EatsCuisine.kaiseki => '🍱',
        EatsCuisine.burger => '🍔',
        EatsCuisine.cafe => '☕',
        EatsCuisine.streetFood => '🥟',
        EatsCuisine.kushikatsu => '🍡',
        EatsCuisine.worldFood => '🌏',
      };

  LText get label => switch (this) {
        EatsCuisine.ramen => const LText('Ramen', 'Ramen'),
        EatsCuisine.sushi => const LText('Suşi', 'Sushi'),
        EatsCuisine.yakiniku => const LText('Yakiniku', 'Yakiniku'),
        EatsCuisine.curry => const LText('Köri', 'Curry'),
        EatsCuisine.okonomiyaki => const LText('Okonomiyaki', 'Okonomiyaki'),
        EatsCuisine.tempura => const LText('Tempura', 'Tempura'),
        EatsCuisine.udonSoba => const LText('Udon / Soba', 'Udon / Soba'),
        EatsCuisine.izakaya => const LText('İzakaya', 'Izakaya'),
        EatsCuisine.kaiseki => const LText('Kaiseki / Set', 'Kaiseki / Set'),
        EatsCuisine.burger => const LText('Burger', 'Burger'),
        EatsCuisine.cafe => const LText('Kafe / Tatlı', 'Cafe / Sweets'),
        EatsCuisine.streetFood => const LText('Sokak lezzeti', 'Street food'),
        EatsCuisine.kushikatsu => const LText('Kushikatsu', 'Kushikatsu'),
        EatsCuisine.worldFood => const LText('Dünya mutfağı', 'World food'),
      };
}

/// Kabaca servis saati dilimi. Doğrulanmamış tam çalışma saati YAZMIYORUZ;
/// "şu an açık" filtresi bu dilimler üzerinden TAHMİN yapar ve UI bunu
/// açıkça "tahmini" diye etiketler.
enum MealSlot { breakfast, lunch, dinner, lateNight }

extension MealSlotX on MealSlot {
  LText get label => switch (this) {
        MealSlot.breakfast => const LText('Kahvaltı', 'Breakfast'),
        MealSlot.lunch => const LText('Öğle', 'Lunch'),
        MealSlot.dinner => const LText('Akşam', 'Dinner'),
        MealSlot.lateNight => const LText('Gece geç', 'Late night'),
      };

  String get emoji => switch (this) {
        MealSlot.breakfast => '🌅',
        MealSlot.lunch => '☀️',
        MealSlot.dinner => '🌆',
        MealSlot.lateNight => '🌙',
      };

  /// Japonya yerel saatine göre içinde bulunulan dilim.
  static MealSlot forHour(int hour) {
    if (hour >= 6 && hour < 11) return MealSlot.breakfast;
    if (hour >= 11 && hour < 16) return MealSlot.lunch;
    if (hour >= 16 && hour < 22) return MealSlot.dinner;
    return MealSlot.lateNight;
  }
}

/// Pratik özellikler. Japonya'ya özgü acı noktalar burada modellenir:
/// nakit-only kasa, İngilizce menü yokluğu, kuyruk, rezervasyon zorunluluğu.
enum EatsAmenity {
  cardOk,
  englishMenu,
  noReservationNeeded,
  reservationRecommended,
  soloFriendly,
  kidFriendly,
  prayerSpace,
  alcoholFree,
  takeaway,
  wheelchairOk,

  // --- Uyarı nitelikleri (filtrede "kaçın" tarafında) ---
  cashOnly,
  queueLikely,
}

extension EatsAmenityX on EatsAmenity {
  /// Uyarı niteliği mi? Filtre popup'ında "Kaçın" bölümüne düşer.
  bool get isCaution =>
      this == EatsAmenity.cashOnly || this == EatsAmenity.queueLikely;

  String get emoji => switch (this) {
        EatsAmenity.cardOk => '💳',
        EatsAmenity.englishMenu => '🇬🇧',
        EatsAmenity.noReservationNeeded => '🚶',
        EatsAmenity.reservationRecommended => '📅',
        EatsAmenity.soloFriendly => '🧍',
        EatsAmenity.kidFriendly => '👶',
        EatsAmenity.prayerSpace => '🕋',
        EatsAmenity.alcoholFree => '🚱',
        EatsAmenity.takeaway => '🥡',
        EatsAmenity.wheelchairOk => '♿',
        EatsAmenity.cashOnly => '💴',
        EatsAmenity.queueLikely => '⏳',
      };

  LText get label => switch (this) {
        EatsAmenity.cardOk => const LText('Kart geçer', 'Cards accepted'),
        EatsAmenity.englishMenu => const LText('İngilizce menü', 'English menu'),
        EatsAmenity.noReservationNeeded =>
          const LText('Rezervasyon gerekmez', 'No reservation needed'),
        EatsAmenity.reservationRecommended =>
          const LText('Rezervasyon önerilir', 'Reservation recommended'),
        EatsAmenity.soloFriendly => const LText('Tek kişilik uygun', 'Solo friendly'),
        EatsAmenity.kidFriendly => const LText('Çocuk dostu', 'Kid friendly'),
        EatsAmenity.prayerSpace => const LText('Namaz alanı', 'Prayer space'),
        EatsAmenity.alcoholFree => const LText('Alkolsüz mekan', 'Alcohol-free venue'),
        EatsAmenity.takeaway => const LText('Paket servis', 'Takeaway'),
        EatsAmenity.wheelchairOk =>
          const LText('Tekerlekli sandalye', 'Wheelchair access'),
        EatsAmenity.cashOnly => const LText('Sadece nakit', 'Cash only'),
        EatsAmenity.queueLikely => const LText('Kuyruk olası', 'Queue likely'),
      };
}

/// Bir restoran kaydı.
class EatsPlace {
  const EatsPlace({
    required this.id,
    required this.name,
    required this.nameJa,
    required this.city,
    required this.area,
    required this.lat,
    required this.lng,
    required this.cuisine,
    required this.description,
    required this.signature,
    required this.priceTier,
    required this.priceMinJpy,
    required this.priceMaxJpy,
    required this.rating,
    required this.halal,
    required this.veggie,
    required this.amenities,
    required this.slots,
    required this.verifiedOn,
    required this.mapsQuery,
    this.insiderTip,
    this.tabelogScore,
    this.premiumOnly = false,
  });

  final String id;

  /// Özel isim — çevrilmez (ör. "Gyumon").
  final String name;

  /// Japonca tabela adı — kullanıcı personele GÖSTEREBİLSİN diye.
  /// Rakiplerin çoğunda yok; sokakta tabelayı bulmanın en hızlı yolu budur.
  final String nameJa;

  final String city; // 'Tokyo' | 'Osaka' | 'Kyoto'
  final String area;
  final double lat;
  final double lng;

  final EatsCuisine cuisine;
  final LText description;

  /// Ne yenmeli — karar hızlandıran tek cümle.
  final LText signature;

  final PriceTier priceTier;

  /// Yaklaşık kişi başı fiyat aralığı (JPY).
  final int priceMinJpy;
  final int priceMaxJpy;

  /// Google ölçeğine yakın yaklaşık puan (turist enflasyonlu — UI bunu söyler).
  final double rating;

  /// Tabelog ölçeğinde yerel puan (3.5+ zaten üst seviyedir). Doğrulanmış veri
  /// olmadan DOLDURULMAZ; null ise UI yalnızca Google ölçeğini gösterir.
  final double? tabelogScore;

  final HalalTrust halal;
  final VeggieLevel veggie;
  final Set<EatsAmenity> amenities;
  final Set<MealSlot> slots;

  /// Premium içgörü — "ne zaman git, ne söyle, neye dikkat et".
  final LText? insiderTip;

  /// Verinin son gözden geçirilme ayı (YYYY-MM). Helal sertifikası değişebilir.
  final String verifiedOn;

  /// Rotori Seçkisi — yalnızca premium'da görünen küratörlü kayıt.
  final bool premiumOnly;

  final String mapsQuery;

  String get priceBand =>
      '¥${_group(priceMinJpy)}–${_group(priceMaxJpy)}';

  String get categoryEmoji => cuisine.emoji;

  LText get category => cuisine.label;

  bool get halalFriendly => halal.weight >= HalalTrust.muslimFriendly.weight;

  bool get vegetarianFriendly => veggie.weight >= VeggieLevel.veggieOption.weight;

  double? distanceKmFrom(LatLng? origin) => origin == null
      ? null
      : distanceMeters(origin, LatLng(lat, lng)) / 1000.0;
}

String _group(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

// ---------------------------------------------------------------------------
// Küratörlü veri
// ---------------------------------------------------------------------------

/// Verinin son toplu gözden geçirme ayı — UI'da "son kontrol" olarak gösterilir.
const String kEatsDataVerifiedOn = '2026-07';

/// Küratörlü liste. Tokyo / Kyoto / Osaka; helal, vejetaryen ve klasik Japon
/// mutfağı dengeli dağıtılmıştır — tek bir kitleye kilitlenmez.
const List<EatsPlace> kEatsPlaces = [
  // === TOKYO ===============================================================
  EatsPlace(
    id: 'tk-gyumon',
    name: 'Gyumon',
    nameJa: '牛門',
    city: 'Tokyo',
    area: 'Shibuya',
    lat: 35.6558,
    lng: 139.6989,
    cuisine: EatsCuisine.yakiniku,
    description: LText(
      'Helal sertifikalı wagyu yakiniku; eti masanda kendin pişiriyorsun.',
      'Halal-certified wagyu yakiniku; you grill the meat at your table.',
    ),
    signature: LText('Helal wagyu kalbi seti', 'Halal wagyu heart set'),
    priceTier: PriceTier.upper,
    priceMinJpy: 3000,
    priceMaxJpy: 6000,
    rating: 4.6,
    halal: HalalTrust.certified,
    veggie: VeggieLevel.none,
    amenities: {
      EatsAmenity.cardOk,
      EatsAmenity.englishMenu,
      EatsAmenity.reservationRecommended,
      EatsAmenity.alcoholFree,
    },
    slots: {MealSlot.dinner},
    insiderTip: LText(
      'Akşam 19:00 sonrası doluyor; Shibuya turundan önce öğleden sonra ara.',
      'Fills up after 19:00; call in the afternoon before your Shibuya walk.',
    ),
    verifiedOn: '2026-07',
    mapsQuery: 'Gyumon Halal Yakiniku Shibuya Tokyo',
  ),
  EatsPlace(
    id: 'tk-naritaya',
    name: 'Naritaya',
    nameJa: '成田屋',
    city: 'Tokyo',
    area: 'Asakusa',
    lat: 35.7148,
    lng: 139.7955,
    cuisine: EatsCuisine.ramen,
    description: LText(
      'Asakusa\'da helal tavuk bazlı ramen; Senso-ji turuna beş dakika.',
      'Halal chicken-based ramen in Asakusa; five minutes from Senso-ji.',
    ),
    signature: LText('Tavuk paitan ramen', 'Chicken paitan ramen'),
    priceTier: PriceTier.mid,
    priceMinJpy: 1200,
    priceMaxJpy: 2500,
    rating: 4.5,
    halal: HalalTrust.certified,
    veggie: VeggieLevel.veggieOption,
    amenities: {
      EatsAmenity.englishMenu,
      EatsAmenity.noReservationNeeded,
      EatsAmenity.soloFriendly,
      EatsAmenity.alcoholFree,
      EatsAmenity.prayerSpace,
      EatsAmenity.queueLikely,
    },
    slots: {MealSlot.lunch, MealSlot.dinner},
    insiderTip: LText(
      'Senso-ji sabah turundan hemen sonra 11:30\'da git — kuyruk daha yok.',
      'Go at 11:30 right after the morning Senso-ji walk — no queue yet.',
    ),
    verifiedOn: '2026-07',
    mapsQuery: 'Naritaya Halal Ramen Asakusa Tokyo',
  ),
  EatsPlace(
    id: 'tk-honolu-ebisu',
    name: 'Honolu Halal Ramen',
    nameJa: 'ほのる',
    city: 'Tokyo',
    area: 'Ebisu',
    lat: 35.6467,
    lng: 139.7100,
    cuisine: EatsCuisine.ramen,
    description: LText(
      'Ebisu istasyonuna yakın helal ramen; yoğun tavuk suyu, koyu tat.',
      'Halal ramen near Ebisu station; rich chicken broth, deep flavour.',
    ),
    signature: LText('Tori paitan + kızarmış sarımsak', 'Tori paitan + burnt garlic'),
    priceTier: PriceTier.mid,
    priceMinJpy: 1100,
    priceMaxJpy: 2000,
    rating: 4.4,
    halal: HalalTrust.certified,
    veggie: VeggieLevel.none,
    amenities: {
      EatsAmenity.englishMenu,
      EatsAmenity.noReservationNeeded,
      EatsAmenity.soloFriendly,
      EatsAmenity.cashOnly,
    },
    slots: {MealSlot.lunch, MealSlot.dinner},
    verifiedOn: '2026-07',
    mapsQuery: 'Honolu Halal Ramen Ebisu Tokyo',
  ),
  EatsPlace(
    id: 'tk-ayamya',
    name: 'Ayam-Ya',
    nameJa: '鶏屋',
    city: 'Tokyo',
    area: 'Okachimachi',
    lat: 35.7075,
    lng: 139.7745,
    cuisine: EatsCuisine.ramen,
    description: LText(
      'Helal tavuk ramen zinciri; Ueno/Akihabara arasında pratik durak.',
      'Halal chicken ramen shop; a practical stop between Ueno and Akihabara.',
    ),
    signature: LText('Shoyu tavuk ramen', 'Shoyu chicken ramen'),
    priceTier: PriceTier.budget,
    priceMinJpy: 950,
    priceMaxJpy: 1600,
    rating: 4.3,
    halal: HalalTrust.certified,
    veggie: VeggieLevel.none,
    amenities: {
      EatsAmenity.englishMenu,
      EatsAmenity.noReservationNeeded,
      EatsAmenity.soloFriendly,
      EatsAmenity.alcoholFree,
      EatsAmenity.cashOnly,
    },
    slots: {MealSlot.lunch, MealSlot.dinner},
    verifiedOn: '2026-07',
    mapsQuery: 'Ayam-Ya Halal Ramen Okachimachi Tokyo',
  ),
  EatsPlace(
    id: 'tk-sekai-cafe',
    name: 'Sekai Cafe',
    nameJa: '世界カフェ',
    city: 'Tokyo',
    area: 'Asakusa',
    lat: 35.7117,
    lng: 139.7938,
    cuisine: EatsCuisine.cafe,
    description: LText(
      'Helal + vegan + glutensiz aynı menüde; Asakusa\'da mola için ideal.',
      'Halal, vegan and gluten-free on one menu; ideal Asakusa break.',
    ),
    signature: LText('Helal sığır burger + matcha latte', 'Halal beef burger + matcha latte'),
    priceTier: PriceTier.budget,
    priceMinJpy: 800,
    priceMaxJpy: 1800,
    rating: 4.2,
    halal: HalalTrust.muslimFriendly,
    veggie: VeggieLevel.vegetarianMenu,
    amenities: {
      EatsAmenity.cardOk,
      EatsAmenity.englishMenu,
      EatsAmenity.noReservationNeeded,
      EatsAmenity.kidFriendly,
      EatsAmenity.alcoholFree,
      EatsAmenity.takeaway,
      EatsAmenity.prayerSpace,
    },
    slots: {MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner},
    insiderTip: LText(
      'Sabah 09:00\'da açılır — Senso-ji\'ye gitmeden kahvaltı için en kolay yer.',
      'Opens at 09:00 — the easiest breakfast before heading to Senso-ji.',
    ),
    verifiedOn: '2026-07',
    mapsQuery: 'Sekai Cafe Asakusa Tokyo',
  ),
  EatsPlace(
    id: 'tk-coco-ichibanya',
    name: 'CoCo Ichibanya',
    nameJa: 'CoCo壱番屋',
    city: 'Tokyo',
    area: 'Zincir / Chain',
    lat: 35.6990,
    lng: 139.7745,
    cuisine: EatsCuisine.curry,
    description: LText(
      'Her yerde bulunan güvenilir köri zinciri; vejetaryen köri sosu ayrı.',
      'Reliable curry chain found everywhere; separate vegetarian curry sauce.',
    ),
    signature: LText('Vejetaryen köri, acılık 3', 'Vegetarian curry, spice level 3'),
    priceTier: PriceTier.budget,
    priceMinJpy: 900,
    priceMaxJpy: 1600,
    rating: 4.0,
    halal: HalalTrust.porkFreeOption,
    veggie: VeggieLevel.veggieOption,
    amenities: {
      EatsAmenity.cardOk,
      EatsAmenity.englishMenu,
      EatsAmenity.noReservationNeeded,
      EatsAmenity.soloFriendly,
      EatsAmenity.kidFriendly,
      EatsAmenity.takeaway,
    },
    slots: {MealSlot.lunch, MealSlot.dinner, MealSlot.lateNight},
    insiderTip: LText(
      'Akihabara ve Shinjuku şubelerinde helal menü ayrı hazırlanır — şubeye sor.',
      'Some Akihabara and Shinjuku branches prepare a separate halal menu — ask.',
    ),
    verifiedOn: '2026-07',
    mapsQuery: 'CoCo Ichibanya vegetarian curry Tokyo',
  ),
  EatsPlace(
    id: 'tk-ts-tantan',
    name: 'T\'s TanTan',
    nameJa: 'Tʼs たんたん',
    city: 'Tokyo',
    area: 'Tokyo Station',
    lat: 35.6812,
    lng: 139.7671,
    cuisine: EatsCuisine.ramen,
    description: LText(
      'Tokyo İstasyonu içinde %100 vegan tantanmen; shinkansen öncesi kurtarıcı.',
      'Fully vegan tantanmen inside Tokyo Station; a pre-shinkansen lifesaver.',
    ),
    signature: LText('Altın susamlı vegan tantanmen', 'Golden sesame vegan tantanmen'),
    priceTier: PriceTier.budget,
    priceMinJpy: 900,
    priceMaxJpy: 1500,
    rating: 4.4,
    halal: HalalTrust.porkFreeOption,
    veggie: VeggieLevel.veganMenu,
    amenities: {
      EatsAmenity.englishMenu,
      EatsAmenity.noReservationNeeded,
      EatsAmenity.soloFriendly,
      EatsAmenity.alcoholFree,
      EatsAmenity.takeaway,
      EatsAmenity.queueLikely,
    },
    slots: {MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner},
    insiderTip: LText(
      'Keiyo Street tarafında; şehirlerarası tren gününde 30 dk erken gel.',
      'On Keiyo Street; on intercity travel days arrive 30 min early.',
    ),
    verifiedOn: '2026-07',
    mapsQuery: 'T\'s TanTan vegan ramen Tokyo Station',
  ),
  EatsPlace(
    id: 'tk-ain-soph',
    name: 'Ain Soph. Journey',
    nameJa: 'アインソフ',
    city: 'Tokyo',
    area: 'Shinjuku',
    lat: 35.6925,
    lng: 139.7043,
    cuisine: EatsCuisine.cafe,
    description: LText(
      'Tam vegan mutfak; ünlü pancake\'i için gidiliyor. Shinjuku merkezde.',
      'Fully vegan kitchen; people come for the pancakes. Central Shinjuku.',
    ),
    signature: LText('Vegan fluffy pancake', 'Vegan fluffy pancake'),
    priceTier: PriceTier.mid,
    priceMinJpy: 1500,
    priceMaxJpy: 3000,
    rating: 4.3,
    halal: HalalTrust.porkFreeOption,
    veggie: VeggieLevel.veganMenu,
    amenities: {
      EatsAmenity.cardOk,
      EatsAmenity.englishMenu,
      EatsAmenity.reservationRecommended,
      EatsAmenity.queueLikely,
    },
    slots: {MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner},
    verifiedOn: '2026-07',
    mapsQuery: 'Ain Soph Journey vegan Shinjuku Tokyo',
  ),
  EatsPlace(
    id: 'tk-gyukatsu-motomura',
    name: 'Gyukatsu Motomura',
    nameJa: '牛かつもと村',
    city: 'Tokyo',
    area: 'Shinjuku',
    lat: 35.6906,
    lng: 139.7004,
    cuisine: EatsCuisine.tempura,
    description: LText(
      'Kızarmış dana pane; masadaki sıcak taşta kendin pişiriyorsun.',
      'Breaded beef cutlet you finish yourself on a hot stone at the table.',
    ),
    signature: LText('130g gyukatsu seti', '130g gyukatsu set'),
    priceTier: PriceTier.mid,
    priceMinJpy: 1500,
    priceMaxJpy: 2500,
    rating: 4.4,
    halal: HalalTrust.none,
    veggie: VeggieLevel.none,
    amenities: {
      EatsAmenity.englishMenu,
      EatsAmenity.noReservationNeeded,
      EatsAmenity.soloFriendly,
      EatsAmenity.cashOnly,
      EatsAmenity.queueLikely,
    },
    slots: {MealSlot.lunch, MealSlot.dinner},
    insiderTip: LText(
      'Kuyruk 40 dk\'yı bulur; 11:00 açılışında ya da 15:00 civarı git.',
      'Queues hit 40 min; go at the 11:00 opening or around 15:00.',
    ),
    verifiedOn: '2026-07',
    mapsQuery: 'Gyukatsu Motomura Shinjuku Tokyo',
  ),
  EatsPlace(
    id: 'tk-uobei-shibuya',
    name: 'Uobei Genki Sushi',
    nameJa: '魚べい',
    city: 'Tokyo',
    area: 'Shibuya',
    lat: 35.6588,
    lng: 139.6986,
    cuisine: EatsCuisine.sushi,
    description: LText(
      'Dokunmatik ekranla sipariş, suşi rayla geliyor. Ucuz ve hızlı.',
      'Order on a touchscreen, sushi arrives on a rail. Cheap and fast.',
    ),
    signature: LText('Somon + karides tabağı', 'Salmon + shrimp plates'),
    priceTier: PriceTier.budget,
    priceMinJpy: 1000,
    priceMaxJpy: 2200,
    rating: 4.1,
    halal: HalalTrust.none,
    veggie: VeggieLevel.veggieOption,
    amenities: {
      EatsAmenity.cardOk,
      EatsAmenity.englishMenu,
      EatsAmenity.noReservationNeeded,
      EatsAmenity.soloFriendly,
      EatsAmenity.kidFriendly,
      EatsAmenity.queueLikely,
    },
    slots: {MealSlot.lunch, MealSlot.dinner, MealSlot.lateNight},
    insiderTip: LText(
      'Ekranı İngilizceye çevir; çocuklu ailede en stressiz suşi deneyimi.',
      'Switch the screen to English; the least stressful sushi run with kids.',
    ),
    verifiedOn: '2026-07',
    mapsQuery: 'Uobei Genki Sushi Shibuya Tokyo',
  ),
  EatsPlace(
    id: 'tk-tsukiji-outer',
    name: 'Tsukiji Outer Market',
    nameJa: '築地場外市場',
    city: 'Tokyo',
    area: 'Tsukiji',
    lat: 35.6655,
    lng: 139.7707,
    cuisine: EatsCuisine.streetFood,
    description: LText(
      'Onlarca tezgah: tamagoyaki, ızgara deniz ürünü, taze meyve. Sabah gidilir.',
      'Dozens of stalls: tamagoyaki, grilled seafood, fresh fruit. A morning stop.',
    ),
    signature: LText('Tamagoyaki çubuğu + ızgara tarak', 'Tamagoyaki skewer + grilled scallop'),
    priceTier: PriceTier.budget,
    priceMinJpy: 500,
    priceMaxJpy: 2500,
    rating: 4.4,
    halal: HalalTrust.none,
    veggie: VeggieLevel.veggieOption,
    amenities: {
      EatsAmenity.noReservationNeeded,
      EatsAmenity.soloFriendly,
      EatsAmenity.kidFriendly,
      EatsAmenity.takeaway,
      EatsAmenity.cashOnly,
      EatsAmenity.queueLikely,
    },
    slots: {MealSlot.breakfast, MealSlot.lunch},
    insiderTip: LText(
      'Çoğu tezgah 14:00\'te kapanır ve nakit ister; 08:00–10:00 arası en iyisi.',
      'Most stalls close by 14:00 and want cash; 08:00–10:00 is the sweet spot.',
    ),
    verifiedOn: '2026-07',
    mapsQuery: 'Tsukiji Outer Market Tokyo',
  ),
  EatsPlace(
    id: 'tk-afuri-harajuku',
    name: 'AFURI',
    nameJa: '阿夫利',
    city: 'Tokyo',
    area: 'Harajuku',
    lat: 35.6702,
    lng: 139.7052,
    cuisine: EatsCuisine.ramen,
    description: LText(
      'Yuzu aromalı hafif ramen; ağır domuz suyunu sevmeyenler için ideal.',
      'Light yuzu-scented ramen; ideal if heavy pork broth is not your thing.',
    ),
    signature: LText('Yuzu shio ramen', 'Yuzu shio ramen'),
    priceTier: PriceTier.mid,
    priceMinJpy: 1200,
    priceMaxJpy: 2000,
    rating: 4.3,
    halal: HalalTrust.none,
    veggie: VeggieLevel.veggieOption,
    amenities: {
      EatsAmenity.englishMenu,
      EatsAmenity.noReservationNeeded,
      EatsAmenity.soloFriendly,
      EatsAmenity.cardOk,
    },
    slots: {MealSlot.lunch, MealSlot.dinner, MealSlot.lateNight},
    insiderTip: LText(
      'Vegan yuzu ramen ayrı kazanda pişer; menüde "vegan" yazan satırı seç.',
      'The vegan yuzu ramen uses a separate pot; pick the line marked "vegan".',
    ),
    verifiedOn: '2026-07',
    mapsQuery: 'AFURI ramen Harajuku Tokyo',
  ),
  EatsPlace(
    id: 'tk-kanda-matsuya',
    name: 'Kanda Matsuya',
    nameJa: 'かんだ まつや',
    city: 'Tokyo',
    area: 'Kanda',
    lat: 35.6947,
    lng: 139.7690,
    cuisine: EatsCuisine.udonSoba,
    description: LText(
      '1884\'ten beri el yapımı soba; ahşap iç mekan, gerçek eski Tokyo.',
      'Handmade soba since 1884; wooden interior, genuinely old Tokyo.',
    ),
    signature: LText('Mori soba (soğuk)', 'Mori soba (cold)'),
    priceTier: PriceTier.mid,
    priceMinJpy: 900,
    priceMaxJpy: 2200,
    rating: 4.2,
    halal: HalalTrust.none,
    veggie: VeggieLevel.veggieOption,
    amenities: {
      EatsAmenity.noReservationNeeded,
      EatsAmenity.cashOnly,
      EatsAmenity.queueLikely,
    },
    slots: {MealSlot.lunch, MealSlot.dinner},
    premiumOnly: true,
    insiderTip: LText(
      'Menü çoğunlukla Japonca — "mori soba" de, yeter. Pazar kapalı.',
      'The menu is mostly Japanese — just say "mori soba". Closed Sundays.',
    ),
    verifiedOn: '2026-07',
    mapsQuery: 'Kanda Matsuya soba Tokyo',
  ),
  EatsPlace(
    id: 'tk-wagyu-halal-vegan',
    name: 'Wagyu Halal & Vegan Burger',
    nameJa: '和牛ハラールバーガー',
    city: 'Tokyo',
    area: 'Shibuya',
    lat: 35.6595,
    lng: 139.6975,
    cuisine: EatsCuisine.burger,
    description: LText(
      'Helal wagyu burger; aynı mutfakta vegan patty seçeneği de var.',
      'Halal wagyu burger; the same kitchen also does a vegan patty.',
    ),
    signature: LText('Wagyu burger + trüflü patates', 'Wagyu burger + truffle fries'),
    priceTier: PriceTier.mid,
    priceMinJpy: 1500,
    priceMaxJpy: 2500,
    rating: 4.5,
    halal: HalalTrust.muslimFriendly,
    veggie: VeggieLevel.veggieOption,
    amenities: {
      EatsAmenity.cardOk,
      EatsAmenity.englishMenu,
      EatsAmenity.noReservationNeeded,
      EatsAmenity.takeaway,
      EatsAmenity.alcoholFree,
    },
    slots: {MealSlot.lunch, MealSlot.dinner},
    verifiedOn: '2026-07',
    mapsQuery: 'Wagyu Halal Vegan Steak Hamburger Shibuya Tokyo',
  ),

  // === KYOTO ===============================================================
  EatsPlace(
    id: 'ky-towzen',
    name: 'Towzen',
    nameJa: 'とうぜん',
    city: 'Kyoto',
    area: 'Nakagyo',
    lat: 35.0092,
    lng: 135.7620,
    cuisine: EatsCuisine.ramen,
    description: LText(
      'Bitkisel bazlı vegan ramen; et/balık suyu (dashi) hiç kullanılmıyor.',
      'Plant-based vegan ramen; no meat or fish stock (dashi) at all.',
    ),
    signature: LText('Miso vegan ramen', 'Miso vegan ramen'),
    priceTier: PriceTier.budget,
    priceMinJpy: 1000,
    priceMaxJpy: 2000,
    rating: 4.4,
    halal: HalalTrust.porkFreeOption,
    veggie: VeggieLevel.veganMenu,
    amenities: {
      EatsAmenity.englishMenu,
      EatsAmenity.noReservationNeeded,
      EatsAmenity.soloFriendly,
      EatsAmenity.alcoholFree,
      EatsAmenity.cashOnly,
    },
    slots: {MealSlot.lunch, MealSlot.dinner},
    verifiedOn: '2026-07',
    mapsQuery: 'Towzen vegan ramen Kyoto',
  ),
  EatsPlace(
    id: 'ky-naritaya-gion',
    name: 'Naritaya Kyoto',
    nameJa: '成田屋 京都',
    city: 'Kyoto',
    area: 'Gion',
    lat: 35.0037,
    lng: 135.7780,
    cuisine: EatsCuisine.ramen,
    description: LText(
      'Gion\'da helal ramen; tapınak turu ile Nishiki arasında tam yolda.',
      'Halal ramen in Gion; right between the temple walk and Nishiki.',
    ),
    signature: LText('Helal tavuk ramen + gyoza', 'Halal chicken ramen + gyoza'),
    priceTier: PriceTier.mid,
    priceMinJpy: 1200,
    priceMaxJpy: 2200,
    rating: 4.3,
    halal: HalalTrust.certified,
    veggie: VeggieLevel.veggieOption,
    amenities: {
      EatsAmenity.englishMenu,
      EatsAmenity.noReservationNeeded,
      EatsAmenity.soloFriendly,
      EatsAmenity.alcoholFree,
      EatsAmenity.prayerSpace,
    },
    slots: {MealSlot.lunch, MealSlot.dinner},
    verifiedOn: '2026-07',
    mapsQuery: 'Naritaya Halal Ramen Gion Kyoto',
  ),
  EatsPlace(
    id: 'ky-vegan-uzu',
    name: 'Vegan Ramen UZU',
    nameJa: 'ヴィーガンラーメンうず',
    city: 'Kyoto',
    area: 'Nakagyo',
    lat: 35.0135,
    lng: 135.7713,
    cuisine: EatsCuisine.ramen,
    description: LText(
      'Sanat galerisiyle iç içe, tasarım odaklı vegan ramen. Kyoto\'ya özgü.',
      'Design-led vegan ramen sharing space with an art gallery. Very Kyoto.',
    ),
    signature: LText('Beyaz miso vegan ramen', 'White miso vegan ramen'),
    priceTier: PriceTier.mid,
    priceMinJpy: 1400,
    priceMaxJpy: 2600,
    rating: 4.4,
    halal: HalalTrust.porkFreeOption,
    veggie: VeggieLevel.veganMenu,
    amenities: {
      EatsAmenity.cardOk,
      EatsAmenity.englishMenu,
      EatsAmenity.reservationRecommended,
      EatsAmenity.soloFriendly,
    },
    slots: {MealSlot.lunch, MealSlot.dinner},
    premiumOnly: true,
    verifiedOn: '2026-07',
    mapsQuery: 'Vegan Ramen UZU Kyoto',
  ),
  EatsPlace(
    id: 'ky-nishiki',
    name: 'Nishiki Market',
    nameJa: '錦市場',
    city: 'Kyoto',
    area: 'Nakagyo',
    lat: 35.0050,
    lng: 135.7648,
    cuisine: EatsCuisine.streetFood,
    description: LText(
      '400 metrelik kapalı çarşı; turşu, soya tatlısı, taze tofu ve şiş.',
      'A 400 m covered arcade; pickles, soy sweets, fresh tofu and skewers.',
    ),
    signature: LText('Taze yuba + soya donutu', 'Fresh yuba + soy doughnut'),
    priceTier: PriceTier.budget,
    priceMinJpy: 400,
    priceMaxJpy: 2000,
    rating: 4.3,
    halal: HalalTrust.none,
    veggie: VeggieLevel.veggieOption,
    amenities: {
      EatsAmenity.noReservationNeeded,
      EatsAmenity.kidFriendly,
      EatsAmenity.takeaway,
      EatsAmenity.cashOnly,
      EatsAmenity.queueLikely,
    },
    slots: {MealSlot.breakfast, MealSlot.lunch},
    insiderTip: LText(
      'Yürürken yemek hoş karşılanmıyor — tezgahın önünde durup bitir.',
      'Eating while walking is frowned upon — finish it standing at the stall.',
    ),
    verifiedOn: '2026-07',
    mapsQuery: 'Nishiki Market Kyoto',
  ),
  EatsPlace(
    id: 'ky-menbaka',
    name: 'Menbaka Fire Ramen',
    nameJa: '麺屋 棣鄂',
    city: 'Kyoto',
    area: 'Nijo',
    lat: 35.0146,
    lng: 135.7500,
    cuisine: EatsCuisine.ramen,
    description: LText(
      'Kaseye alev püskürtülen "ateş rameni"; gösteri kısmı yemeğin yarısı.',
      'Ramen with a burst of flame over the bowl; the show is half the meal.',
    ),
    signature: LText('Negi fire ramen', 'Negi fire ramen'),
    priceTier: PriceTier.mid,
    priceMinJpy: 1200,
    priceMaxJpy: 2000,
    rating: 4.2,
    halal: HalalTrust.none,
    veggie: VeggieLevel.none,
    amenities: {
      EatsAmenity.englishMenu,
      EatsAmenity.noReservationNeeded,
      EatsAmenity.soloFriendly,
      EatsAmenity.cashOnly,
      EatsAmenity.queueLikely,
    },
    slots: {MealSlot.lunch},
    insiderTip: LText(
      'Alev anında ellerini masaya koy ve öne eğilme; personel uyarıyor.',
      'Keep your hands on the table and do not lean in during the flame.',
    ),
    verifiedOn: '2026-07',
    mapsQuery: 'Menbaka Fire Ramen Kyoto',
  ),
  EatsPlace(
    id: 'ky-izuju',
    name: 'Izuju',
    nameJa: 'いづ重',
    city: 'Kyoto',
    area: 'Gion',
    lat: 35.0037,
    lng: 135.7787,
    cuisine: EatsCuisine.sushi,
    description: LText(
      'Yasaka Tapınağı karşısında 100 yıllık Kyoto usulü saba suşi.',
      'Century-old Kyoto-style saba sushi across from Yasaka Shrine.',
    ),
    signature: LText('Saba (uskumru) bo-zushi', 'Saba (mackerel) bo-zushi'),
    priceTier: PriceTier.upper,
    priceMinJpy: 2500,
    priceMaxJpy: 5000,
    rating: 4.2,
    halal: HalalTrust.none,
    veggie: VeggieLevel.none,
    amenities: {
      EatsAmenity.noReservationNeeded,
      EatsAmenity.takeaway,
      EatsAmenity.cashOnly,
    },
    slots: {MealSlot.lunch, MealSlot.dinner},
    premiumOnly: true,
    insiderTip: LText(
      'Paket alıp Maruyama Parkı\'nda yemek en Kyoto\'lu öğle molası.',
      'Take it away and eat in Maruyama Park — the most Kyoto lunch there is.',
    ),
    verifiedOn: '2026-07',
    mapsQuery: 'Izuju sushi Gion Kyoto',
  ),
  EatsPlace(
    id: 'ky-shigetsu',
    name: 'Shigetsu (Tenryu-ji)',
    nameJa: '篩月',
    city: 'Kyoto',
    area: 'Arashiyama',
    lat: 35.0159,
    lng: 135.6737,
    cuisine: EatsCuisine.kaiseki,
    description: LText(
      'Tapınak içinde shojin ryori — tamamen bitkisel Budist manastır mutfağı.',
      'Shojin ryori inside the temple — fully plant-based Buddhist cuisine.',
    ),
    signature: LText('Üç tepsili shojin seti', 'Three-tray shojin set'),
    priceTier: PriceTier.upper,
    priceMinJpy: 3300,
    priceMaxJpy: 6600,
    rating: 4.3,
    halal: HalalTrust.porkFreeOption,
    veggie: VeggieLevel.veganMenu,
    amenities: {
      EatsAmenity.reservationRecommended,
      EatsAmenity.alcoholFree,
      EatsAmenity.englishMenu,
      EatsAmenity.cashOnly,
    },
    slots: {MealSlot.lunch},
    insiderTip: LText(
      'Sadece öğle servisi ve rezervasyon şart; Arashiyama bambu turuyla eşleştir.',
      'Lunch only and reservation required; pair it with the Arashiyama bamboo walk.',
    ),
    verifiedOn: '2026-07',
    mapsQuery: 'Shigetsu Tenryuji shojin ryori Arashiyama Kyoto',
  ),

  // === OSAKA ===============================================================
  EatsPlace(
    id: 'os-okonomiyaki-kiji',
    name: 'Okonomiyaki Kiji',
    nameJa: 'きじ',
    city: 'Osaka',
    area: 'Umeda',
    lat: 34.7025,
    lng: 135.4959,
    cuisine: EatsCuisine.okonomiyaki,
    description: LText(
      'Umeda Sky Building altında efsane okonomiyaki. Yerel favori.',
      'Legendary okonomiyaki under the Umeda Sky Building. A local favourite.',
    ),
    signature: LText('Modanyaki (noodle\'lı)', 'Modanyaki (with noodles)'),
    priceTier: PriceTier.budget,
    priceMinJpy: 800,
    priceMaxJpy: 1800,
    rating: 4.5,
    halal: HalalTrust.none,
    veggie: VeggieLevel.none,
    amenities: {
      EatsAmenity.noReservationNeeded,
      EatsAmenity.soloFriendly,
      EatsAmenity.cashOnly,
      EatsAmenity.queueLikely,
    },
    slots: {MealSlot.lunch, MealSlot.dinner},
    insiderTip: LText(
      'Öğle kuyruğu 30 dk\'yı bulur; 11:30 ya da 14:30 en boş saatler.',
      'Lunch queues reach 30 min; 11:30 or 14:30 are the quiet windows.',
    ),
    verifiedOn: '2026-07',
    mapsQuery: 'Okonomiyaki Kiji Umeda Osaka',
  ),
  EatsPlace(
    id: 'os-matsuri-halal',
    name: 'Matsuri Halal Yakiniku',
    nameJa: '祭 ハラール',
    city: 'Osaka',
    area: 'Namba',
    lat: 34.6655,
    lng: 135.5017,
    cuisine: EatsCuisine.yakiniku,
    description: LText(
      'Namba\'da helal wagyu yakiniku; Dotonbori gezisinin akşam durağı.',
      'Halal wagyu yakiniku in Namba; the evening stop on a Dotonbori night.',
    ),
    signature: LText('Helal wagyu karışık tabak', 'Halal wagyu mixed platter'),
    priceTier: PriceTier.upper,
    priceMinJpy: 3500,
    priceMaxJpy: 7000,
    rating: 4.4,
    halal: HalalTrust.muslimFriendly,
    veggie: VeggieLevel.veggieOption,
    amenities: {
      EatsAmenity.cardOk,
      EatsAmenity.englishMenu,
      EatsAmenity.reservationRecommended,
      EatsAmenity.prayerSpace,
    },
    slots: {MealSlot.dinner, MealSlot.lateNight},
    verifiedOn: '2026-07',
    mapsQuery: 'Halal Yakiniku Namba Osaka',
  ),
  EatsPlace(
    id: 'os-paprika-vegan',
    name: 'Paprika Shokudo Vegan',
    nameJa: 'パプリカ食堂',
    city: 'Osaka',
    area: 'Namba',
    lat: 34.6702,
    lng: 135.4986,
    cuisine: EatsCuisine.kaiseki,
    description: LText(
      'Tamamen vegan Japon ev yemeği; teishoku (set menü) formatında.',
      'Fully vegan Japanese home cooking served as teishoku (set menu).',
    ),
    signature: LText('Vegan karaage teishoku', 'Vegan karaage teishoku'),
    priceTier: PriceTier.mid,
    priceMinJpy: 1200,
    priceMaxJpy: 2500,
    rating: 4.4,
    halal: HalalTrust.porkFreeOption,
    veggie: VeggieLevel.veganMenu,
    amenities: {
      EatsAmenity.englishMenu,
      EatsAmenity.reservationRecommended,
      EatsAmenity.soloFriendly,
      EatsAmenity.cardOk,
    },
    slots: {MealSlot.lunch, MealSlot.dinner},
    verifiedOn: '2026-07',
    mapsQuery: 'Paprika Shokudo Vegan Namba Osaka',
  ),
  EatsPlace(
    id: 'os-daruma',
    name: 'Kushikatsu Daruma',
    nameJa: '串カツだるま',
    city: 'Osaka',
    area: 'Shinsekai',
    lat: 34.6524,
    lng: 135.5063,
    cuisine: EatsCuisine.kushikatsu,
    description: LText(
      'Osaka\'nın simgesi kızarmış şiş; sosa iki kez batırmak yasak.',
      'Osaka\'s signature fried skewers; double-dipping the sauce is banned.',
    ),
    signature: LText('Karışık şiş seti', 'Mixed skewer set'),
    priceTier: PriceTier.budget,
    priceMinJpy: 1000,
    priceMaxJpy: 2500,
    rating: 4.1,
    halal: HalalTrust.none,
    veggie: VeggieLevel.veggieOption,
    amenities: {
      EatsAmenity.englishMenu,
      EatsAmenity.noReservationNeeded,
      EatsAmenity.soloFriendly,
      EatsAmenity.cardOk,
      EatsAmenity.queueLikely,
    },
    slots: {MealSlot.lunch, MealSlot.dinner, MealSlot.lateNight},
    insiderTip: LText(
      'Ortak sos kabına ikinci kez batırma; lahana yaprağıyla sos "taşı".',
      'Never double-dip the shared sauce; ferry sauce with the cabbage leaf.',
    ),
    verifiedOn: '2026-07',
    mapsQuery: 'Kushikatsu Daruma Shinsekai Osaka',
  ),
  EatsPlace(
    id: 'os-kobe-aburi',
    name: 'Kobe Aburi Bokujo',
    nameJa: '神戸炙り牧場',
    city: 'Osaka',
    area: 'Umeda',
    lat: 34.7018,
    lng: 135.4972,
    cuisine: EatsCuisine.yakiniku,
    description: LText(
      'Umeda\'da Kobe sığırı yakiniku. Özel gece için; rezervasyon şart gibi.',
      'Kobe beef yakiniku in Umeda. For a special night; practically book-only.',
    ),
    signature: LText('Kobe sirloin 2 dilim', 'Kobe sirloin, two slices'),
    priceTier: PriceTier.splurge,
    priceMinJpy: 6000,
    priceMaxJpy: 14000,
    rating: 4.5,
    halal: HalalTrust.none,
    veggie: VeggieLevel.none,
    amenities: {
      EatsAmenity.cardOk,
      EatsAmenity.englishMenu,
      EatsAmenity.reservationRecommended,
    },
    slots: {MealSlot.dinner},
    verifiedOn: '2026-07',
    mapsQuery: 'Kobe Aburi Bokujo Umeda Osaka',
  ),
  EatsPlace(
    id: 'os-ichiran-dotonbori',
    name: 'Ichiran',
    nameJa: '一蘭',
    city: 'Osaka',
    area: 'Dotonbori',
    lat: 34.6687,
    lng: 135.5013,
    cuisine: EatsCuisine.ramen,
    description: LText(
      'Tek kişilik bölmelerde tonkotsu ramen; sipariş formla, konuşmadan.',
      'Tonkotsu ramen in solo booths; you order on a form, no talking needed.',
    ),
    signature: LText('Klasik tonkotsu, sertlik "futsu"', 'Classic tonkotsu, "futsu" firmness'),
    priceTier: PriceTier.budget,
    priceMinJpy: 1000,
    priceMaxJpy: 1900,
    rating: 4.2,
    halal: HalalTrust.none,
    veggie: VeggieLevel.none,
    amenities: {
      EatsAmenity.englishMenu,
      EatsAmenity.noReservationNeeded,
      EatsAmenity.soloFriendly,
      EatsAmenity.queueLikely,
    },
    slots: {
      MealSlot.breakfast,
      MealSlot.lunch,
      MealSlot.dinner,
      MealSlot.lateNight,
    },
    insiderTip: LText(
      'Domuz suyu bazlıdır — helal/domuzsuz arıyorsan bu mekanı atla.',
      'The broth is pork-based — skip this one if you need halal or pork-free.',
    ),
    verifiedOn: '2026-07',
    mapsQuery: 'Ichiran Dotonbori Osaka',
  ),
];
