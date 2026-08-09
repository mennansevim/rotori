// Rotori Eats sorgu + skorlama motoru (saf Dart, UI'dan bağımsız).
//
// Ayrı dosya çünkü: filtreleme ve "hangisi bana uyar" skoru ürünün asıl
// değeridir; widget testine bağlı kalmadan doğrudan birim testi yazılabilmeli.
//
// ## Katman modeli
//
// Free ve premium arasındaki sınır TEK yerde tanımlıdır: [kFreeFilterDims],
// [kFreeSorts] ve [kEatsFreeVisibleLimit]. UI kilit ikonlarını buradan okur,
// [EatsQuery.forTier] de aynı kaynağı kullanarak premium boyutları temizler.
// Böylece "UI kilitli gösteriyor ama motor yine de uyguluyor" tutarsızlığı
// oluşamaz.

import 'dart:math' as math;

import 'eats.dart';
import 'geofence.dart' show LatLng;
import 'localized_text.dart';

/// Kullanıcının satın alma katmanı.
enum EatsTier { free, premium }

/// Filtre popup'ındaki her bir kriter ekseni.
enum EatsFilterDim {
  text,
  halal,
  veggie,
  city,
  cuisine,
  price,
  rating,
  amenities,
  avoid,
  slot,
  distance,
}

/// Ücretsiz katmanda AÇIK olan filtre eksenleri.
///
/// Neden bu üçlü + arama: diyet ve şehir "hangi mekanlar bana uygun" sorusudur
/// — bunu kilitlemek uygulamayı işe yaramaz kılar ve güveni öldürür. Premium
/// olan kısım "bunlardan hangisi, şu an, benim için doğru" sorusudur.
const Set<EatsFilterDim> kFreeFilterDims = {
  EatsFilterDim.text,
  EatsFilterDim.halal,
  EatsFilterDim.veggie,
  EatsFilterDim.city,
};

/// Ücretsiz katmanda seçilebilen sıralamalar.
const Set<EatsSort> kFreeSorts = {EatsSort.rating};

/// Ücretsiz katmanda bir sorguda gösterilen en fazla sonuç.
/// Katalog gizlenmez; derinlik sınırlanır ve kaç sonucun kilitli olduğu
/// kullanıcıya açıkça söylenir.
const int kEatsFreeVisibleLimit = 6;

/// "Şimdi ne yesem?" önerisinde döndürülen mekan sayısı.
const int kEatsPickCount = 3;

/// Ortalama yürüme hızı (km/sa) — mesafeden dakika türetmek için.
const double kWalkKmh = 4.5;

enum EatsSort { rotoriScore, rating, distance, priceLow, priceHigh }

extension EatsSortX on EatsSort {
  LText get label => switch (this) {
        EatsSort.rotoriScore => const LText('Rotori skoru', 'Rotori score'),
        EatsSort.rating => const LText('Puan', 'Rating'),
        EatsSort.distance => const LText('Mesafe', 'Distance'),
        EatsSort.priceLow => const LText('Önce ucuz', 'Cheapest first'),
        EatsSort.priceHigh => const LText('Önce pahalı', 'Priciest first'),
      };

  bool get isFree => kFreeSorts.contains(this);
}

/// Kullanıcı bağlamı — skorlamayı kişiselleştiren her şey.
class EatsContext {
  const EatsContext({
    this.origin,
    this.dietTags = const <String>{},
    this.mealBudgetJpy,
    this.nowSlot,
    this.partyHasKids = false,
  });

  /// Kullanıcının anlık konumu (GPS) veya günün merkez durağı. Yoksa mesafe
  /// bileşeni nötr puanlanır.
  final LatLng? origin;

  /// Trip tercihlerinden gelen beslenme etiketleri ('halal', 'vegetarian'…).
  final Set<String> dietTags;

  /// Kişi başı öğün bütçesi (JPY).
  final int? mealBudgetJpy;

  /// Japonya yerel saatine göre içinde bulunulan öğün dilimi.
  final MealSlot? nowSlot;

  final bool partyHasKids;

  bool get wantsHalal => dietTags.contains('halal');
  bool get wantsPorkFree =>
      dietTags.contains('no_pork') || dietTags.contains('halal');
  bool get wantsVegan => dietTags.contains('vegan');
  bool get wantsVegetarian =>
      dietTags.contains('vegetarian') || dietTags.contains('vegan');
}

/// Filtre popup'ının tuttuğu tüm kriterler.
class EatsQuery {
  const EatsQuery({
    this.text = '',
    this.minHalal,
    this.minVeggie,
    this.cities = const <String>{},
    this.cuisines = const <EatsCuisine>{},
    this.priceTiers = const <PriceTier>{},
    this.minRating = 0,
    this.requiredAmenities = const <EatsAmenity>{},
    this.avoidAmenities = const <EatsAmenity>{},
    this.slot,
    this.maxDistanceKm,
    this.sort = EatsSort.rating,
  });

  /// Serbest metin — isim, bölge, mutfak ve imza yemekte aranır.
  final String text;

  /// En düşük kabul edilen helal güven seviyesi (null = kısıt yok).
  final HalalTrust? minHalal;

  /// En düşük kabul edilen vejetaryen seviyesi (null = kısıt yok).
  final VeggieLevel? minVeggie;

  final Set<String> cities;
  final Set<EatsCuisine> cuisines;
  final Set<PriceTier> priceTiers;
  final double minRating;
  final Set<EatsAmenity> requiredAmenities;
  final Set<EatsAmenity> avoidAmenities;
  final MealSlot? slot;
  final double? maxDistanceKm;
  final EatsSort sort;

  EatsQuery copyWith({
    String? text,
    HalalTrust? minHalal,
    bool clearHalal = false,
    VeggieLevel? minVeggie,
    bool clearVeggie = false,
    Set<String>? cities,
    Set<EatsCuisine>? cuisines,
    Set<PriceTier>? priceTiers,
    double? minRating,
    Set<EatsAmenity>? requiredAmenities,
    Set<EatsAmenity>? avoidAmenities,
    MealSlot? slot,
    bool clearSlot = false,
    double? maxDistanceKm,
    bool clearDistance = false,
    EatsSort? sort,
  }) {
    return EatsQuery(
      text: text ?? this.text,
      minHalal: clearHalal ? null : (minHalal ?? this.minHalal),
      minVeggie: clearVeggie ? null : (minVeggie ?? this.minVeggie),
      cities: cities ?? this.cities,
      cuisines: cuisines ?? this.cuisines,
      priceTiers: priceTiers ?? this.priceTiers,
      minRating: minRating ?? this.minRating,
      requiredAmenities: requiredAmenities ?? this.requiredAmenities,
      avoidAmenities: avoidAmenities ?? this.avoidAmenities,
      slot: clearSlot ? null : (slot ?? this.slot),
      maxDistanceKm: clearDistance ? null : (maxDistanceKm ?? this.maxDistanceKm),
      sort: sort ?? this.sort,
    );
  }

  /// Hangi eksenler dolu? Aktif filtre rozetleri ve kilit uyarıları buradan.
  Set<EatsFilterDim> get activeDims => {
        if (text.trim().isNotEmpty) EatsFilterDim.text,
        if (minHalal != null) EatsFilterDim.halal,
        if (minVeggie != null) EatsFilterDim.veggie,
        if (cities.isNotEmpty) EatsFilterDim.city,
        if (cuisines.isNotEmpty) EatsFilterDim.cuisine,
        if (priceTiers.isNotEmpty) EatsFilterDim.price,
        if (minRating > 0) EatsFilterDim.rating,
        if (requiredAmenities.isNotEmpty) EatsFilterDim.amenities,
        if (avoidAmenities.isNotEmpty) EatsFilterDim.avoid,
        if (slot != null) EatsFilterDim.slot,
        if (maxDistanceKm != null) EatsFilterDim.distance,
      };

  int get activeCount => activeDims.length;

  /// Premium eksenlerden en az biri dolu mu? (free kullanıcıya "bunlar kilitli"
  /// demek için.)
  bool get usesPremiumDims =>
      activeDims.any((d) => !kFreeFilterDims.contains(d)) || !sort.isFree;

  /// Katmana göre uygulanabilir sorgu. Free'de premium eksenler DÜŞÜRÜLÜR —
  /// motor ile UI'ın aynı gerçeği göstermesi için tek kapı burasıdır.
  EatsQuery forTier(EatsTier tier) {
    if (tier == EatsTier.premium) return this;
    return EatsQuery(
      text: kFreeFilterDims.contains(EatsFilterDim.text) ? text : '',
      minHalal: minHalal,
      minVeggie: minVeggie,
      cities: cities,
      sort: sort.isFree ? sort : EatsSort.rating,
    );
  }
}

/// Tek bir sonuç satırı — mekan + hesaplanmış bağlam.
class EatsResult {
  const EatsResult({
    required this.place,
    required this.score,
    required this.reasons,
    this.distanceKm,
  });

  final EatsPlace place;

  /// 0–100 Rotori uyum skoru.
  final int score;

  /// Skorun neden yüksek olduğunu anlatan kısa gerekçeler (en güçlü önce).
  final List<LText> reasons;

  final double? distanceKm;

  /// Yürüyerek yaklaşık dakika (mesafe biliniyorsa).
  int? get walkMinutes =>
      distanceKm == null ? null : math.max(1, (distanceKm! / kWalkKmh * 60).round());
}

/// Sorguyu çalıştırır: filtrele → skorla → sırala.
///
/// [tier] free ise premium eksenler [EatsQuery.forTier] ile düşürülür ve
/// `premiumOnly` kayıtlar listeden çıkarılır. Sonuç KIRPILMAZ — kaç sonucun
/// kilitli olduğunu çağıran hesaplayabilsin diye tam liste döner.
List<EatsResult> runEatsQuery(
  List<EatsPlace> places, {
  EatsQuery query = const EatsQuery(),
  EatsContext context = const EatsContext(),
  EatsTier tier = EatsTier.premium,
}) {
  final q = query.forTier(tier);
  final needle = q.text.trim().toLowerCase();

  final out = <EatsResult>[];
  for (final p in places) {
    if (tier == EatsTier.free && p.premiumOnly) continue;
    if (!_matches(p, q, needle, context)) continue;
    final distanceKm = p.distanceKmFrom(context.origin);
    if (q.maxDistanceKm != null &&
        (distanceKm == null || distanceKm > q.maxDistanceKm!)) {
      continue;
    }
    final scored = scoreEatsPlace(p, context: context, distanceKm: distanceKm);
    out.add(EatsResult(
      place: p,
      score: scored.score,
      reasons: scored.reasons,
      distanceKm: distanceKm,
    ));
  }

  out.sort((a, b) => _compare(a, b, q.sort));
  return out;
}

bool _matches(
  EatsPlace p,
  EatsQuery q,
  String needle,
  EatsContext context,
) {
  if (q.minHalal != null && p.halal.weight < q.minHalal!.weight) return false;
  if (q.minVeggie != null && p.veggie.weight < q.minVeggie!.weight) return false;
  if (q.cities.isNotEmpty && !q.cities.contains(p.city)) return false;
  if (q.cuisines.isNotEmpty && !q.cuisines.contains(p.cuisine)) return false;
  if (q.priceTiers.isNotEmpty && !q.priceTiers.contains(p.priceTier)) {
    return false;
  }
  if (p.rating < q.minRating) return false;
  if (!q.requiredAmenities.every(p.amenities.contains)) return false;
  if (q.avoidAmenities.any(p.amenities.contains)) return false;
  if (q.slot != null && !p.slots.contains(q.slot)) return false;

  if (needle.isNotEmpty) {
    final haystack = [
      p.name,
      p.nameJa,
      p.area,
      p.city,
      p.cuisine.label.tr,
      p.cuisine.label.en,
      p.signature.tr,
      p.signature.en,
    ].join(' ').toLowerCase();
    if (!haystack.contains(needle)) return false;
  }
  return true;
}

int _compare(EatsResult a, EatsResult b, EatsSort sort) {
  int tie() => a.place.id.compareTo(b.place.id);
  switch (sort) {
    case EatsSort.rotoriScore:
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : tie();
    case EatsSort.rating:
      final c = b.place.rating.compareTo(a.place.rating);
      return c != 0 ? c : tie();
    case EatsSort.distance:
      final ad = a.distanceKm, bd = b.distanceKm;
      if (ad == null && bd == null) return tie();
      if (ad == null) return 1;
      if (bd == null) return -1;
      final c = ad.compareTo(bd);
      return c != 0 ? c : tie();
    case EatsSort.priceLow:
      final c = a.place.priceMinJpy.compareTo(b.place.priceMinJpy);
      return c != 0 ? c : tie();
    case EatsSort.priceHigh:
      final c = b.place.priceMaxJpy.compareTo(a.place.priceMaxJpy);
      return c != 0 ? c : tie();
  }
}

/// Skoru oluşturan sinyaller. Her biri BİLİNİYOR ya da BİLİNMİYOR olabilir.
enum EatsSignal { diet, rating, budget, distance }

extension EatsSignalX on EatsSignal {
  LText get label => switch (this) {
        EatsSignal.diet => const LText('Diyet uyumu', 'Diet fit'),
        EatsSignal.rating =>
          const LText('Gezgin puanı', 'Traveller rating'),
        EatsSignal.budget => const LText('Bütçe uyumu', 'Budget fit'),
        EatsSignal.distance => const LText('Mesafe', 'Distance'),
      };

  /// Sinyal bilinmiyorken kullanıcıya NE yapması gerektiğini söyler.
  LText get missingHint => switch (this) {
        EatsSignal.diet => const LText(
            'Beslenme tercihini seç',
            'Pick your dietary preference',
          ),
        EatsSignal.rating => const LText('—', '—'),
        EatsSignal.budget => const LText(
            'Öğün bütçeni gir',
            'Set your meal budget',
          ),
        EatsSignal.distance => const LText(
            'Konumu aç',
            'Turn on location',
          ),
      };

  /// Bu sinyalin skordaki ağırlığı (bilindiğinde).
  int get weight => switch (this) {
        EatsSignal.diet => 35,
        EatsSignal.rating => 25,
        EatsSignal.budget => 20,
        EatsSignal.distance => 20,
      };
}

/// Tek bir skor bileşeni.
class EatsScorePart {
  const EatsScorePart({
    required this.signal,
    required this.value,
    required this.known,
  });

  final EatsSignal signal;

  /// 0..[signal.weight]. [known] false ise anlamsızdır (0).
  final int value;

  /// Girdi kullanıcıdan alınmış mı? False ise bu bileşen skora GİRMEZ.
  final bool known;

  int get max => signal.weight;
}

/// Skor kırılımı — premium detay sheet'i bunu satır satır gösterir.
///
/// **Neden "known" bayrağı var:** İlk sürümde bilinmeyen bileşenlere nötr puan
/// (diyet 22, bütçe 12, mesafe 12) veriliyordu. Sonuç, hiçbir tercih
/// girilmemiş bir gezide bile kendinden emin görünen bir "65/100"du — oysa
/// 65'in 46'sı tamamen uydurmaydı. Uygulama beslenme tercihini ve öğün
/// bütçesini HİÇBİR YERDE sormuyordu; dolayısıyla bu her kullanıcıda böyleydi.
/// Artık bilinmeyen bileşen skora katılmaz ve arayüzde "eksik" olarak,
/// doldurma çağrısıyla birlikte gösterilir.
class EatsScore {
  const EatsScore({
    required this.score,
    required this.parts,
    required this.reasons,
  });

  /// 0–100, YALNIZCA bilinen sinyaller üzerinden normalize edilmiş.
  final int score;

  final List<EatsScorePart> parts;
  final List<LText> reasons;

  Iterable<EatsScorePart> get knownParts => parts.where((p) => p.known);

  List<EatsSignal> get missingSignals =>
      parts.where((p) => !p.known).map((p) => p.signal).toList(growable: false);

  int get knownCount => knownParts.length;
  int get totalCount => parts.length;

  /// Kişiselleştirmenin temeli: diyet ya da bütçe. İkisi de yoksa skor
  /// yalnızca herkese aynı gelen puandan ibarettir — sayı olarak gösterilmez.
  bool get isPersonalized => parts.any(
        (p) =>
            p.known &&
            (p.signal == EatsSignal.diet || p.signal == EatsSignal.budget),
      );
}

/// Rotori uyum skoru.
///
/// Ağırlıklar: diyet 35, puan 25, bütçe 20, mesafe 20. Bir sinyal
/// bilinmiyorsa hem paydan hem paydadan DÜŞER — nötr puanla doldurulmaz.
/// Böylece "bilmiyorum" ile "orta düzeyde uyuyor" karışmaz.
EatsScore scoreEatsPlace(
  EatsPlace p, {
  EatsContext context = const EatsContext(),
  double? distanceKm,
}) {
  final reasons = <LText>[];

  // --- Diyet uyumu ---------------------------------------------------------
  final dietKnown = context.dietTags.isNotEmpty;
  var diet = 0;
  if (dietKnown) {
    if (context.wantsHalal) {
      diet = switch (p.halal) {
        HalalTrust.certified => 35,
        HalalTrust.muslimFriendly => 26,
        HalalTrust.porkFreeOption => 12,
        HalalTrust.none => 0,
      };
      if (p.halal == HalalTrust.certified) {
        reasons.add(const LText(
          'Helal sertifikalı — tercihinle tam uyumlu',
          'Halal certified — a perfect match for your preference',
        ));
      }
    } else if (context.wantsVegan) {
      diet = switch (p.veggie) {
        VeggieLevel.veganMenu => 35,
        VeggieLevel.vegetarianMenu => 18,
        VeggieLevel.veggieOption => 10,
        VeggieLevel.none => 0,
      };
      if (p.veggie == VeggieLevel.veganMenu) {
        reasons.add(const LText(
          'Tam vegan mutfak — dashi riski yok',
          'Fully vegan kitchen — no hidden dashi',
        ));
      }
    } else if (context.wantsVegetarian) {
      diet = switch (p.veggie) {
        VeggieLevel.veganMenu || VeggieLevel.vegetarianMenu => 33,
        VeggieLevel.veggieOption => 20,
        VeggieLevel.none => 0,
      };
    } else if (context.wantsPorkFree) {
      diet = p.halal.weight >= HalalTrust.porkFreeOption.weight ? 30 : 8;
    } else {
      // Etiket var ama Eats verisiyle eşleşmiyor (ör. yalnızca 'gluten_free').
      // Bu bir bilgi eksikliği değil; kısıt bu veri setinde ayrıştırılamıyor.
      diet = 22;
    }
  }

  // --- Puan (her zaman bilinir) --------------------------------------------
  final ratingPart = (((p.rating - 3.0) / 2.0).clamp(0.0, 1.0) * 25).round();
  if (p.rating >= 4.4) {
    reasons.add(const LText('Gezgin puanı yüksek', 'Highly rated by travellers'));
  }

  // --- Bütçe uyumu ---------------------------------------------------------
  final b = context.mealBudgetJpy;
  final budgetKnown = b != null && b > 0;
  var budget = 0;
  if (budgetKnown) {
    if (p.priceMaxJpy <= b) {
      budget = 20;
      reasons.add(LText(
        'Öğün bütçenin (¥$b) tamamen içinde',
        'Fully within your ¥$b meal budget',
      ));
    } else if (p.priceMinJpy <= b) {
      budget = 14;
    } else {
      final over = (p.priceMinJpy - b) / b;
      budget = (10 - (over * 12)).clamp(0, 10).round();
    }
  }

  // --- Mesafe --------------------------------------------------------------
  final distanceKnown = distanceKm != null;
  var distance = 0;
  if (distanceKnown) {
    if (distanceKm <= 0.4) {
      distance = 20;
      reasons.add(const LText('Yürüme mesafesinde', 'Within a short walk'));
    } else if (distanceKm <= 1.0) {
      distance = 17;
      reasons.add(const LText('Yürüme mesafesinde', 'Within a short walk'));
    } else if (distanceKm <= 2.5) {
      distance = 13;
    } else if (distanceKm <= 6) {
      distance = 8;
    } else if (distanceKm <= 12) {
      distance = 3;
    }
  }

  final parts = <EatsScorePart>[
    EatsScorePart(signal: EatsSignal.diet, value: diet, known: dietKnown),
    EatsScorePart(signal: EatsSignal.rating, value: ratingPart, known: true),
    EatsScorePart(signal: EatsSignal.budget, value: budget, known: budgetKnown),
    EatsScorePart(
      signal: EatsSignal.distance,
      value: distance,
      known: distanceKnown,
    ),
  ];

  // Yalnızca bilinen sinyaller üzerinden normalize et.
  var earned = 0;
  var possible = 0;
  for (final part in parts) {
    if (!part.known) continue;
    earned += part.value;
    possible += part.max;
  }

  // Bağlam bonusları — gerekçeye yansır, küçük katkı verir.
  if (context.partyHasKids && p.amenities.contains(EatsAmenity.kidFriendly)) {
    earned += 3;
    possible += 3;
    reasons.add(const LText('Çocuklu aile için uygun', 'Works with kids'));
  }
  if (p.amenities.contains(EatsAmenity.cashOnly)) {
    reasons.add(const LText(
      'Sadece nakit — yanında yeterli ¥ olsun',
      'Cash only — carry enough yen',
    ));
  }

  final normalized = possible == 0 ? 0 : (earned / possible * 100).round();

  return EatsScore(
    score: normalized.clamp(0, 100),
    parts: parts,
    reasons: reasons.take(3).toList(growable: false),
  );
}

/// "Şimdi ne yesem?" — konum, saat, bütçe ve diyeti birlikte kullanarak en
/// uygun [kEatsPickCount] mekanı seçer.
///
/// Bu, rakiplerin tek tek çözdüğü üç soruyu (nerede / ne kadar / yiyebilir
/// miyim) tek dokunuşta birleştiren premium çekirdektir.
List<EatsResult> pickEatsNow(
  List<EatsPlace> places, {
  required EatsContext context,
  EatsQuery base = const EatsQuery(),
}) {
  final q = base.copyWith(
    slot: context.nowSlot,
    sort: EatsSort.rotoriScore,
  );
  final results = runEatsQuery(
    places,
    query: q,
    context: context,
    tier: EatsTier.premium,
  );
  if (results.length >= kEatsPickCount) {
    return results.take(kEatsPickCount).toList(growable: false);
  }
  // Öğün dilimi çok daraltmışsa dilim kısıtını bırak — boş ekran gösterme.
  final relaxed = runEatsQuery(
    places,
    query: base.copyWith(clearSlot: true, sort: EatsSort.rotoriScore),
    context: context,
    tier: EatsTier.premium,
  );
  return relaxed.take(kEatsPickCount).toList(growable: false);
}
