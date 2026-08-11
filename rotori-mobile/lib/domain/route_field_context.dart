/// Rota motorunun saha bağlamı: takvim, ulaşım gerçekliği, bagaj lojistiği ve
/// tekrar politikası tek bir immutable nesnede toplanır.
///
/// `FieldRealityContext` **opsiyoneldir**. `null` verildiğinde
/// `BeamSearchItineraryOptimizer` v2 davranışını birebir korur; bu, mevcut
/// üretim kalite kapılarının (0 hard violation, %1.69 drop) tek seferde
/// bozulmamasını garanti eden geriye uyumluluk sözleşmesidir.
library;

import 'japan_calendar.dart';
import 'japan_transit_realism.dart';
import 'luggage_logistics.dart';
import 'place_identity_resolver.dart';

// ---------------------------------------------------------------------------
// Intent-aware tekrar politikası
// ---------------------------------------------------------------------------

/// Bir mekanın ardışık/tekrarlı günlere atanabilme kuralı.
enum RepeatPolicy {
  /// Varsayılan: aynı kanonik mekan ardışık iki güne konamaz.
  hardZero,

  /// Bölge veya tematik park — ardışık günlere atanabilir
  /// (Akihabara, Shibuya, USJ, Disney).
  repeatableZone,

  /// Zaman kotalı: ilk ziyaret önerilen süreyi doldurmadıysa kalan süre için
  /// tekrar önerilebilir (büyük müzeler).
  timeQuota,

  /// Kullanıcı bu mekanı açıkça seçti — tüm deduplication kuralları ezilir.
  userOverride,
}

/// Bir mekanın tekrar davranışını belirleyen değişmez tanım.
class RepeatRule {
  const RepeatRule({
    this.policy = RepeatPolicy.hardZero,
    this.recommendedTotalMinutes,
    this.maximumConsecutiveDays = 1,
  });

  /// Kullanıcı iradesi — her şeyi ezer.
  const RepeatRule.userSelected()
      : policy = RepeatPolicy.userOverride,
        recommendedTotalMinutes = null,
        maximumConsecutiveDays = 365;

  /// Bölge / tematik park.
  const RepeatRule.zone({this.maximumConsecutiveDays = 2})
      : policy = RepeatPolicy.repeatableZone,
        recommendedTotalMinutes = null;

  /// Zaman kotalı büyük mekan.
  const RepeatRule.quota(int totalMinutes, {this.maximumConsecutiveDays = 2})
      : policy = RepeatPolicy.timeQuota,
        recommendedTotalMinutes = totalMinutes;

  final RepeatPolicy policy;

  /// `timeQuota` için mekanın tam gezilmesi gereken toplam süre.
  final int? recommendedTotalMinutes;

  /// Ardışık kaç güne atanabileceği.
  final int maximumConsecutiveDays;

  bool get isRepeatableZone => policy == RepeatPolicy.repeatableZone;
  bool get isUserOverride => policy == RepeatPolicy.userOverride;
}

/// Bir mekanın önceki günlerdeki ziyaret geçmişi — kota kararı için.
class RepeatObservation {
  const RepeatObservation({
    required this.identityKey,
    required this.previousDayNumber,
    required this.minutesSpentSoFar,
    required this.consecutiveDayCount,
  });

  final String identityKey;
  final int previousDayNumber;
  final int minutesSpentSoFar;
  final int consecutiveDayCount;
}

enum RepeatDecision {
  /// Tekrar serbest.
  allow,

  /// Ardışık gün tekrarı — kaldırılmalı.
  rejectAdjacentDuplicate,

  /// Ardışık gün limiti aşıldı (bölge/park için).
  rejectConsecutiveLimit,
}

class RepeatVerdict {
  const RepeatVerdict(this.decision, {this.remainingQuotaMinutes, this.reason});

  final RepeatDecision decision;

  /// `timeQuota` politikasında kalan dakika — UI "kaldığın yerden devam et"
  /// mesajı üretebilir.
  final int? remainingQuotaMinutes;

  final String? reason;

  bool get isAllowed => decision == RepeatDecision.allow;
}

/// Tekrar kurallarını uygulayan saf değerlendirici.
class RepeatPolicyEvaluator {
  const RepeatPolicyEvaluator();

  /// [observation] `null` ise mekan önceki günde görülmemiştir → serbest.
  RepeatVerdict evaluate({
    required RepeatRule rule,
    RepeatObservation? observation,
  }) {
    if (rule.isUserOverride) {
      return const RepeatVerdict(
        RepeatDecision.allow,
        reason: 'user-explicit-selection',
      );
    }
    if (observation == null) {
      return const RepeatVerdict(RepeatDecision.allow, reason: 'first-visit');
    }

    switch (rule.policy) {
      case RepeatPolicy.userOverride:
        return const RepeatVerdict(RepeatDecision.allow);

      case RepeatPolicy.hardZero:
        return const RepeatVerdict(
          RepeatDecision.rejectAdjacentDuplicate,
          reason: 'hard-zero-adjacent-duplicate',
        );

      case RepeatPolicy.repeatableZone:
        if (observation.consecutiveDayCount >= rule.maximumConsecutiveDays) {
          return const RepeatVerdict(
            RepeatDecision.rejectConsecutiveLimit,
            reason: 'zone-consecutive-limit',
          );
        }
        return const RepeatVerdict(
          RepeatDecision.allow,
          reason: 'repeatable-zone',
        );

      case RepeatPolicy.timeQuota:
        final quota = rule.recommendedTotalMinutes;
        if (quota == null) {
          return const RepeatVerdict(
            RepeatDecision.rejectAdjacentDuplicate,
            reason: 'quota-missing',
          );
        }
        final remaining = quota - observation.minutesSpentSoFar;
        if (remaining <= 0) {
          return const RepeatVerdict(
            RepeatDecision.rejectAdjacentDuplicate,
            reason: 'quota-satisfied',
          );
        }
        if (observation.consecutiveDayCount >= rule.maximumConsecutiveDays) {
          return RepeatVerdict(
            RepeatDecision.rejectConsecutiveLimit,
            remainingQuotaMinutes: remaining,
            reason: 'quota-consecutive-limit',
          );
        }
        return RepeatVerdict(
          RepeatDecision.allow,
          remainingQuotaMinutes: remaining,
          reason: 'quota-incomplete',
        );
    }
  }
}

/// Katalog verisinden tekrar kuralı türeten varsayılan sınıflandırıcı.
///
/// Katalog açık bir kural taşımadığında kullanılır; kategori ve ad
/// ipuçlarından muhafazakâr karar verir.
RepeatRule inferRepeatRule({
  required String title,
  String? category,
  bool userExplicitSelection = false,
  bool? isRepeatableZone,
  int? recommendedTotalMinutes,
}) {
  if (userExplicitSelection) return const RepeatRule.userSelected();
  if (isRepeatableZone == true) return const RepeatRule.zone();
  if (recommendedTotalMinutes != null && recommendedTotalMinutes > 180) {
    return RepeatRule.quota(recommendedTotalMinutes);
  }

  final haystack = '${title.toLowerCase()} ${(category ?? '').toLowerCase()}';
  const zoneTokens = [
    'akihabara',
    'shibuya',
    'shinjuku',
    'ginza',
    'harajuku',
    'odaiba',
    'dotonbori',
    'namba',
    'arashiyama',
    'gion',
    'pontocho',
    'nakasu',
    'universal studios',
    'usj',
    'disneyland',
    'disneysea',
    'tema park',
    'theme park',
    'tematik',
    'alışveriş',
    'alisveris',
    'shopping',
    'district',
    'bölge',
    'bolge',
  ];
  if (zoneTokens.any(haystack.contains)) return const RepeatRule.zone();
  return const RepeatRule(policy: RepeatPolicy.hardZero);
}

// ---------------------------------------------------------------------------
// Saha bağlamı
// ---------------------------------------------------------------------------

/// Yolcunun o seyahatteki değişmez profili.
class TravellerProfile {
  const TravellerProfile({
    this.railPass = RailPassType.none,
    this.luggageSize = LuggageSize.none,
    this.bagCount = 0,
    this.partySize = 1,
  });

  final RailPassType railPass;
  final LuggageSize luggageSize;
  final int bagCount;
  final int partySize;

  bool get carriesLuggage => !luggageSize.isEmpty && bagCount > 0;
}

/// Bir günün saha koşulları — optimizer bu nesneyi okur.
class FieldRealityContext {
  FieldRealityContext({
    required this.travelDate,
    this.cityId,
    this.traveller = const TravellerProfile(),
    JapanPublicHolidayCalendar? calendar,
    ClosureResolver? closureResolver,
    JapanCrowdModel? crowdModel,
    TransitRealismModel? transitModel,
    PlaceIdentityResolver? identityResolver,
    this.luggageResolver = const LuggageStrategyResolver(),
    this.repeatEvaluator = const RepeatPolicyEvaluator(),
    this.hotelPolicy = const HotelLuggagePolicy(),
    this.luggagePlan,
    this.enforceHotelCheckInWindow = true,
    this.applySeasonalDurationInflation = true,
    this.passCoversAllLegs = true,
  })  : calendar = calendar ?? kJapanHolidayCalendar,
        closureResolver = closureResolver ?? kJapanClosureResolver,
        crowdModel = crowdModel ?? kJapanCrowdModel,
        transitModel = transitModel ?? TransitRealismModel(),
        identityResolver = identityResolver ?? kPlaceIdentityResolver;

  /// Planlanan günün tarihi (yerel).
  final DateTime travelDate;

  /// O günün baskın şehri — sezon penceresi ve kalabalık için.
  final String? cityId;

  final TravellerProfile traveller;

  final JapanPublicHolidayCalendar calendar;
  final ClosureResolver closureResolver;
  final JapanCrowdModel crowdModel;
  final TransitRealismModel transitModel;
  final PlaceIdentityResolver identityResolver;
  final LuggageStrategyResolver luggageResolver;
  final RepeatPolicyEvaluator repeatEvaluator;
  final HotelLuggagePolicy hotelPolicy;

  /// O gün için çözülmüş bagaj planı. `null` ise bagaj kısıtı uygulanmaz.
  final LuggagePlan? luggagePlan;

  final bool enforceHotelCheckInWindow;
  final bool applySeasonalDurationInflation;

  /// Bölgesel pass'in bu günün tüm bacaklarını kapsayıp kapsamadığı.
  final bool passCoversAllLegs;

  /// Kategori başına sezon çarpanı önbelleği. Beam search `inflateDuration`'ı
  /// aday başına çağırır; çarpan tarih+şehir+kategori için sabittir.
  final Map<CrowdSensitivity, double> _durationMultiplierCache = {};

  CrowdSeason get season => crowdModel.seasonFor(travelDate, cityId: cityId);

  bool get isPublicHoliday => calendar.isPublicHoliday(travelDate);

  double get walkingCrowdMultiplier =>
      crowdModel.walkingMultiplier(date: travelDate, cityId: cityId);

  /// Bagaj Yamato ile gönderildiyse istasyon/otel bagaj tamponu uygulanmaz.
  bool get bypassesLuggageBuffer =>
      luggagePlan?.bypassesStationLuggageBuffer ?? true;

  /// Sezonluk süre çarpanını bir aktiviteye uygular.
  int inflateDuration(int minutes, {String? category}) {
    if (!applySeasonalDurationInflation) return minutes;
    return applyCrowdMultiplier(
      minutes,
      durationMultiplierFor(crowdSensitivityForCategory(category)),
    );
  }

  /// Duyarlılık sınıfı için sezon çarpanı (önbellekli).
  double durationMultiplierFor(CrowdSensitivity sensitivity) =>
      _durationMultiplierCache.putIfAbsent(
        sensitivity,
        () => crowdModel.durationMultiplier(
          date: travelDate,
          cityId: cityId,
          sensitivity: sensitivity,
        ),
      );

  FieldRealityContext copyWith({
    DateTime? travelDate,
    String? cityId,
    TravellerProfile? traveller,
    LuggagePlan? luggagePlan,
    bool? enforceHotelCheckInWindow,
    bool? applySeasonalDurationInflation,
    bool? passCoversAllLegs,
  }) =>
      FieldRealityContext(
        travelDate: travelDate ?? this.travelDate,
        cityId: cityId ?? this.cityId,
        traveller: traveller ?? this.traveller,
        calendar: calendar,
        closureResolver: closureResolver,
        crowdModel: crowdModel,
        transitModel: transitModel,
        identityResolver: identityResolver,
        luggageResolver: luggageResolver,
        repeatEvaluator: repeatEvaluator,
        hotelPolicy: hotelPolicy,
        luggagePlan: luggagePlan ?? this.luggagePlan,
        enforceHotelCheckInWindow:
            enforceHotelCheckInWindow ?? this.enforceHotelCheckInWindow,
        applySeasonalDurationInflation: applySeasonalDurationInflation ??
            this.applySeasonalDurationInflation,
        passCoversAllLegs: passCoversAllLegs ?? this.passCoversAllLegs,
      );
}
