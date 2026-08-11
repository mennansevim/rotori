/// Plan JSON v3 saha sinyalleri.
///
/// v2 sözleşmesi `TimelineItem` üzerinde düz alanlar kullanıyordu. v3, saha
/// gerçekliğinden doğan meta veriyi **isteğe bağlı iç nesnelere** taşır:
///
/// - `TimelineItem.transit`  → ulaşım riski, pass downgrade, istasyon tamponu
/// - `TimelineItem.repeat`   → tekrar politikası ve zaman kotası
/// - `DayPlan.luggage`       → o günün bagaj stratejisi
/// - `DayPlan.crowd`         → sezonluk yoğunluk çarpanları
/// - `CityTransitionPlan.options` → picker'a sunulan mod seçenekleri
///
/// **Geriye uyumluluk sözleşmesi:** tüm alanlar opsiyoneldir ve varsayılan
/// değerdeyken JSON'a **yazılmaz**. v2 dokümanı v3 okuyucuda kayıpsız açılır;
/// v3 dokümanı v2 okuyucuda bilinmeyen anahtarları yok sayarak açılır.
library;

// ---------------------------------------------------------------------------
// Ortak yardımcılar
// ---------------------------------------------------------------------------

List<String> _stringList(dynamic raw) =>
    raw is List ? List.unmodifiable(raw.whereType<String>()) : const <String>[];

int? _int(dynamic raw) => (raw as num?)?.toInt();

double? _double(dynamic raw) => (raw as num?)?.toDouble();

// ---------------------------------------------------------------------------
// Ulaşım sinyalleri
// ---------------------------------------------------------------------------

/// Bir ulaşım satırının saha riski ve düzeltmeleri.
class TransitSignals {
  const TransitSignals({
    this.hasTrafficRiskDisclaimer = false,
    this.trafficRiskMultiplier,
    this.stationNavigationBufferMin = 0,
    this.requestedService,
    this.effectiveService,
    this.railPass,
    this.surchargeYen,
    this.disclaimers = const [],
  });

  final bool hasTrafficRiskDisclaimer;

  /// Otobüs/taksi için uygulanan trafik çarpanı (1.1 / 1.3).
  final double? trafficRiskMultiplier;

  /// Dev ("labyrinth") istasyon navigasyon tamponu.
  final int stationNavigationBufferMin;

  /// Katalogda önerilen Shinkansen servisi (ör. `nozomi`).
  final String? requestedService;

  /// Pass kısıtından sonra fiilen kullanılan servis (ör. `hikari`).
  final String? effectiveService;

  /// `RailPassType.name`.
  final String? railPass;

  /// Pass kapsamı dışı biniş için tahmini ek ücret.
  final int? surchargeYen;

  /// `TransitDisclaimer.name` listesi — UI metnini l10n çözer.
  final List<String> disclaimers;

  bool get isServiceDowngraded =>
      requestedService != null &&
      effectiveService != null &&
      requestedService != effectiveService;

  bool get isDefault =>
      !hasTrafficRiskDisclaimer &&
      trafficRiskMultiplier == null &&
      stationNavigationBufferMin == 0 &&
      requestedService == null &&
      effectiveService == null &&
      railPass == null &&
      surchargeYen == null &&
      disclaimers.isEmpty;

  TransitSignals copyWith({
    bool? hasTrafficRiskDisclaimer,
    double? trafficRiskMultiplier,
    int? stationNavigationBufferMin,
    String? requestedService,
    String? effectiveService,
    String? railPass,
    int? surchargeYen,
    List<String>? disclaimers,
  }) =>
      TransitSignals(
        hasTrafficRiskDisclaimer:
            hasTrafficRiskDisclaimer ?? this.hasTrafficRiskDisclaimer,
        trafficRiskMultiplier:
            trafficRiskMultiplier ?? this.trafficRiskMultiplier,
        stationNavigationBufferMin:
            stationNavigationBufferMin ?? this.stationNavigationBufferMin,
        requestedService: requestedService ?? this.requestedService,
        effectiveService: effectiveService ?? this.effectiveService,
        railPass: railPass ?? this.railPass,
        surchargeYen: surchargeYen ?? this.surchargeYen,
        disclaimers: disclaimers ?? this.disclaimers,
      );

  static TransitSignals? tryFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    return TransitSignals(
      hasTrafficRiskDisclaimer:
          (j['hasTrafficRiskDisclaimer'] as bool?) ?? false,
      trafficRiskMultiplier: _double(j['trafficRiskMultiplier']),
      stationNavigationBufferMin: _int(j['stationNavigationBufferMin']) ?? 0,
      requestedService: j['requestedService'] as String?,
      effectiveService: j['effectiveService'] as String?,
      railPass: j['railPass'] as String?,
      surchargeYen: _int(j['surchargeYen']),
      disclaimers: _stringList(j['disclaimers']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (hasTrafficRiskDisclaimer) 'hasTrafficRiskDisclaimer': true,
        if (trafficRiskMultiplier != null)
          'trafficRiskMultiplier': trafficRiskMultiplier,
        if (stationNavigationBufferMin > 0)
          'stationNavigationBufferMin': stationNavigationBufferMin,
        if (requestedService != null) 'requestedService': requestedService,
        if (effectiveService != null) 'effectiveService': effectiveService,
        if (railPass != null) 'railPass': railPass,
        if (surchargeYen != null) 'surchargeYen': surchargeYen,
        if (disclaimers.isNotEmpty) 'disclaimers': disclaimers,
      };
}

// ---------------------------------------------------------------------------
// Tekrar politikası sinyalleri
// ---------------------------------------------------------------------------

class RepeatSignals {
  const RepeatSignals({
    this.policy,
    this.isRepeatableZone = false,
    this.userExplicitSelection = false,
    this.recommendedTotalMinutes,
    this.completedMinutes,
    this.maximumConsecutiveDays,
  });

  /// `RepeatPolicy.name` — `hardZero` | `repeatableZone` | `timeQuota` |
  /// `userOverride`. `null` ise varsayılan (`hardZero`) uygulanır.
  final String? policy;

  final bool isRepeatableZone;

  /// Kullanıcı bu mekanı elle seçtiyse deduplication ezilir.
  final bool userExplicitSelection;

  /// Mekanın tam gezilmesi için önerilen toplam süre (zaman kotası).
  final int? recommendedTotalMinutes;

  /// Önceki günlerde bu mekanda geçirilmiş toplam süre.
  final int? completedMinutes;

  final int? maximumConsecutiveDays;

  /// Kota dolmadıysa kalan süre; kota tanımlı değilse `null`.
  int? get remainingQuotaMinutes {
    final quota = recommendedTotalMinutes;
    if (quota == null) return null;
    final done = completedMinutes ?? 0;
    final remaining = quota - done;
    return remaining > 0 ? remaining : 0;
  }

  bool get isDefault =>
      policy == null &&
      !isRepeatableZone &&
      !userExplicitSelection &&
      recommendedTotalMinutes == null &&
      completedMinutes == null &&
      maximumConsecutiveDays == null;

  RepeatSignals copyWith({
    String? policy,
    bool? isRepeatableZone,
    bool? userExplicitSelection,
    int? recommendedTotalMinutes,
    int? completedMinutes,
    int? maximumConsecutiveDays,
  }) =>
      RepeatSignals(
        policy: policy ?? this.policy,
        isRepeatableZone: isRepeatableZone ?? this.isRepeatableZone,
        userExplicitSelection:
            userExplicitSelection ?? this.userExplicitSelection,
        recommendedTotalMinutes:
            recommendedTotalMinutes ?? this.recommendedTotalMinutes,
        completedMinutes: completedMinutes ?? this.completedMinutes,
        maximumConsecutiveDays:
            maximumConsecutiveDays ?? this.maximumConsecutiveDays,
      );

  static RepeatSignals? tryFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    return RepeatSignals(
      policy: j['policy'] as String?,
      isRepeatableZone: (j['isRepeatableZone'] as bool?) ?? false,
      userExplicitSelection: (j['userExplicitSelection'] as bool?) ?? false,
      recommendedTotalMinutes: _int(j['recommendedTotalMinutes']),
      completedMinutes: _int(j['completedMinutes']),
      maximumConsecutiveDays: _int(j['maximumConsecutiveDays']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (policy != null) 'policy': policy,
        if (isRepeatableZone) 'isRepeatableZone': true,
        if (userExplicitSelection) 'userExplicitSelection': true,
        if (recommendedTotalMinutes != null)
          'recommendedTotalMinutes': recommendedTotalMinutes,
        if (completedMinutes != null) 'completedMinutes': completedMinutes,
        if (maximumConsecutiveDays != null)
          'maximumConsecutiveDays': maximumConsecutiveDays,
      };
}

// ---------------------------------------------------------------------------
// Kapanış (teishukubi) sinyalleri
// ---------------------------------------------------------------------------

class ClosureSignals {
  const ClosureSignals({
    this.weeklyClosedWeekdays = const [],
    this.holidayShiftApplied = false,
    this.closureCause,
    this.shiftedFromDate,
  });

  /// `DateTime.monday` … `DateTime.sunday` (1..7).
  final List<int> weeklyClosedWeekdays;

  /// Pazartesi resmî tatile denk geldiği için kapanış kaydırıldı.
  final bool holidayShiftApplied;

  /// `ClosureCause.name`.
  final String? closureCause;

  /// Kayan kapanışta asıl kapanış günü (ISO `yyyy-MM-dd`).
  final String? shiftedFromDate;

  bool get isDefault =>
      weeklyClosedWeekdays.isEmpty &&
      !holidayShiftApplied &&
      closureCause == null &&
      shiftedFromDate == null;

  static ClosureSignals? tryFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    return ClosureSignals(
      weeklyClosedWeekdays: j['weeklyClosedWeekdays'] is List
          ? List.unmodifiable((j['weeklyClosedWeekdays'] as List)
              .whereType<num>()
              .map((e) => e.toInt()))
          : const [],
      holidayShiftApplied: (j['holidayShiftApplied'] as bool?) ?? false,
      closureCause: j['closureCause'] as String?,
      shiftedFromDate: j['shiftedFromDate'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (weeklyClosedWeekdays.isNotEmpty)
          'weeklyClosedWeekdays': weeklyClosedWeekdays,
        if (holidayShiftApplied) 'holidayShiftApplied': true,
        if (closureCause != null) 'closureCause': closureCause,
        if (shiftedFromDate != null) 'shiftedFromDate': shiftedFromDate,
      };
}

// ---------------------------------------------------------------------------
// Bagaj sinyalleri (gün seviyesi)
// ---------------------------------------------------------------------------

class LuggageSignals {
  const LuggageSignals({
    required this.strategy,
    this.size,
    this.bagCount,
    this.originHandoverMin = 0,
    this.arrivalHandlingMin = 0,
    this.retrievalMin = 0,
    this.estimatedCostYen = 0,
    this.baggageAvailableAfterDays = 0,
    this.advisories = const [],
    this.reasonCode,
  });

  /// `LuggageHandlingStrategy.name` — `coinLocker` | `hotelEarlyDrop` |
  /// `hotelCheckIn` | `yamatoForward` | `carry` | `none`.
  final String strategy;

  /// `LuggageSize.name`.
  final String? size;
  final int? bagCount;

  /// Kaynak otelde kargo teslimi için ayrılan süre.
  final int originHandoverMin;

  /// Varışta bagajı yerleştirme süresi (locker / otel).
  final int arrivalHandlingMin;

  /// Gün sonunda bagajı geri alma süresi.
  final int retrievalMin;

  final int estimatedCostYen;

  /// Yamato'da 1 — bagaj ertesi gün ulaşır.
  final int baggageAvailableAfterDays;

  /// `LuggageAdvisory.name` listesi.
  final List<String> advisories;

  final String? reasonCode;

  /// Bu strateji istasyon/otel bagaj tamponunu atlar mı?
  bool get bypassesStationLuggageBuffer =>
      strategy == 'yamatoForward' || strategy == 'none';

  int get totalScheduleImpactMin =>
      originHandoverMin + arrivalHandlingMin + retrievalMin;

  static LuggageSignals? tryFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final strategy = j['strategy'] as String?;
    if (strategy == null || strategy.isEmpty) return null;
    return LuggageSignals(
      strategy: strategy,
      size: j['size'] as String?,
      bagCount: _int(j['bagCount']),
      originHandoverMin: _int(j['originHandoverMin']) ?? 0,
      arrivalHandlingMin: _int(j['arrivalHandlingMin']) ?? 0,
      retrievalMin: _int(j['retrievalMin']) ?? 0,
      estimatedCostYen: _int(j['estimatedCostYen']) ?? 0,
      baggageAvailableAfterDays: _int(j['baggageAvailableAfterDays']) ?? 0,
      advisories: _stringList(j['advisories']),
      reasonCode: j['reasonCode'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'strategy': strategy,
        if (size != null) 'size': size,
        if (bagCount != null) 'bagCount': bagCount,
        if (originHandoverMin > 0) 'originHandoverMin': originHandoverMin,
        if (arrivalHandlingMin > 0) 'arrivalHandlingMin': arrivalHandlingMin,
        if (retrievalMin > 0) 'retrievalMin': retrievalMin,
        if (estimatedCostYen > 0) 'estimatedCostYen': estimatedCostYen,
        if (baggageAvailableAfterDays > 0)
          'baggageAvailableAfterDays': baggageAvailableAfterDays,
        if (advisories.isNotEmpty) 'advisories': advisories,
        if (reasonCode != null) 'reasonCode': reasonCode,
      };
}

// ---------------------------------------------------------------------------
// Kalabalık sinyalleri (gün seviyesi)
// ---------------------------------------------------------------------------

class CrowdSignals {
  const CrowdSignals({
    required this.season,
    this.durationMultiplier = 1,
    this.walkingMultiplier = 1,
    this.isPublicHoliday = false,
  });

  /// `CrowdSeason.name` — `normal` | `sakura` | `goldenWeek` | `obon` |
  /// `newYear` | `autumnFoliage`.
  final String season;

  final double durationMultiplier;
  final double walkingMultiplier;
  final bool isPublicHoliday;

  bool get isDefault =>
      season == 'normal' &&
      durationMultiplier == 1 &&
      walkingMultiplier == 1 &&
      !isPublicHoliday;

  static CrowdSignals? tryFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final season = j['season'] as String?;
    if (season == null || season.isEmpty) return null;
    return CrowdSignals(
      season: season,
      durationMultiplier: _double(j['durationMultiplier']) ?? 1,
      walkingMultiplier: _double(j['walkingMultiplier']) ?? 1,
      isPublicHoliday: (j['isPublicHoliday'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'season': season,
        if (durationMultiplier != 1) 'durationMultiplier': durationMultiplier,
        if (walkingMultiplier != 1) 'walkingMultiplier': walkingMultiplier,
        if (isPublicHoliday) 'isPublicHoliday': true,
      };
}

// ---------------------------------------------------------------------------
// Şehir geçişi seçenekleri (picker sözleşmesi)
// ---------------------------------------------------------------------------

/// Kullanıcının şehir geçişi picker'ında göreceği tek bir mod seçeneği.
///
/// Seçenek listesi motor tarafından üretilir; UI yalnız gösterir ve seçer.
/// Böylece "üst rozet Otobüs ama timeline JR Special Rapid" sınıfı projeksiyon
/// kayması yapısal olarak imkânsız hale gelir.
class CityTransitionOption {
  const CityTransitionOption({
    required this.mode,
    required this.durationMinutes,
    this.serviceLabel,
    this.estimatedFareYen,
    this.fareLabel,
    this.isRecommended = false,
    this.isPassCovered = false,
    this.isBlockedByPass = false,
    this.hasTrafficRiskDisclaimer = false,
    this.disclaimers = const [],
    this.emoji,
  });

  /// `kTransportModes` değerlerinden biri.
  final String mode;

  /// Saha düzeltmeleri uygulandıktan sonraki süre.
  final int durationMinutes;

  /// Shinkansen için servis adı ("Hikari"). Diğer modlarda `null`.
  final String? serviceLabel;

  final int? estimatedFareYen;

  /// Serbest metin ücret etiketi (bilinmeyen çiftlerde "Operatöre göre").
  final String? fareLabel;

  final bool isRecommended;

  /// Kullanıcının pass'i bu seçeneği kapsıyor mu?
  final bool isPassCovered;

  /// Pass kısıtı nedeniyle **seçilemez** (JR Pass + Nozomi).
  final bool isBlockedByPass;

  final bool hasTrafficRiskDisclaimer;

  /// `TransitDisclaimer.name` listesi.
  final List<String> disclaimers;

  final String? emoji;

  CityTransitionOption copyWith({
    int? durationMinutes,
    String? serviceLabel,
    bool? isBlockedByPass,
    bool? isPassCovered,
    List<String>? disclaimers,
  }) =>
      CityTransitionOption(
        mode: mode,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        serviceLabel: serviceLabel ?? this.serviceLabel,
        estimatedFareYen: estimatedFareYen,
        fareLabel: fareLabel,
        isRecommended: isRecommended,
        isPassCovered: isPassCovered ?? this.isPassCovered,
        isBlockedByPass: isBlockedByPass ?? this.isBlockedByPass,
        hasTrafficRiskDisclaimer: hasTrafficRiskDisclaimer,
        disclaimers: disclaimers ?? this.disclaimers,
        emoji: emoji,
      );

  static CityTransitionOption? tryFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final mode = j['mode'] as String?;
    if (mode == null || mode.isEmpty) return null;
    return CityTransitionOption(
      mode: mode,
      durationMinutes: _int(j['durationMinutes']) ?? 0,
      serviceLabel: j['serviceLabel'] as String?,
      estimatedFareYen: _int(j['estimatedFareYen']),
      fareLabel: j['fareLabel'] as String?,
      isRecommended: (j['isRecommended'] as bool?) ?? false,
      isPassCovered: (j['isPassCovered'] as bool?) ?? false,
      isBlockedByPass: (j['isBlockedByPass'] as bool?) ?? false,
      hasTrafficRiskDisclaimer:
          (j['hasTrafficRiskDisclaimer'] as bool?) ?? false,
      disclaimers: _stringList(j['disclaimers']),
      emoji: j['emoji'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'durationMinutes': durationMinutes,
        if (serviceLabel != null) 'serviceLabel': serviceLabel,
        if (estimatedFareYen != null) 'estimatedFareYen': estimatedFareYen,
        if (fareLabel != null) 'fareLabel': fareLabel,
        if (isRecommended) 'isRecommended': true,
        if (isPassCovered) 'isPassCovered': true,
        if (isBlockedByPass) 'isBlockedByPass': true,
        if (hasTrafficRiskDisclaimer) 'hasTrafficRiskDisclaimer': true,
        if (disclaimers.isNotEmpty) 'disclaimers': disclaimers,
        if (emoji != null) 'emoji': emoji,
      };
}
