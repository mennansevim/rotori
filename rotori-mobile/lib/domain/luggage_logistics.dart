/// İleri seviye bagaj ve lojistik katmanı.
///
/// Şehir geçişi olan bir günde bagajın nereye gittiği rotanın en sık kırılan
/// varsayımıdır: istasyon çıkışı doğrudan aktiviteye bağlanamaz. Bu katman üç
/// saha stratejisini tek bir deterministik karar ağacında birleştirir:
///
/// 1. **Coin Locker** — otel check-in penceresinden önce varış; bagaj
///    istasyonda bırakılır (+arama/bırakma tamponu).
/// 2. **Hotel Drop** — otel istasyona yakınsa/yol üstündeyse resepsiyona
///    bırakılır (sapma + resepsiyon süresi).
/// 3. **Yamato Transport (宅配便 / takuhaibin)** — uzun mesafeli geçişte büyük
///    bagaj kargoya verilir, **ertesi gün** varır; o gün istasyon/otel bagaj
///    tamponu tamamen **bypass** edilir.
///
/// Katman saftır: `DateTime.now()` okumaz, ağa çıkmaz. Tüm ücretler tahmindir.
library;

import 'dart:math' as math;

/// Kullanıcının beyan ettiği bagaj boyutu.
enum LuggageSize {
  /// Bagajsız / sadece sırt çantası.
  none,

  /// Kabin boyu (55cm) — coin locker'ın küçük gözüne sığar.
  cabin,

  /// Orta boy valiz — büyük coin locker gerekir.
  medium,

  /// Büyük valiz (28"+) — istasyon locker'ında yer bulmak zordur.
  large,
}

extension LuggageSizeTraits on LuggageSize {
  bool get isEmpty => this == LuggageSize.none;

  /// Coin locker'da yer bulma olasılığı düşükse `false`.
  bool get fitsTypicalCoinLocker =>
      this == LuggageSize.cabin || this == LuggageSize.medium;

  /// Yürüme ve aktarma cezasını büyüten ağırlık katsayısı.
  double get handlingWeight => switch (this) {
        LuggageSize.none => 0,
        LuggageSize.cabin => 0.5,
        LuggageSize.medium => 1.0,
        LuggageSize.large => 1.6,
      };
}

/// Bagajın o gün nasıl yönetildiği.
enum LuggageHandlingStrategy {
  /// Bagaj yok veya taşıma gerektirmiyor.
  none,

  /// Bagaj gün boyu taşınıyor — en pahalı seçenek, son çare.
  carry,

  /// İstasyon coin locker'ına bırakılıp gün sonunda alınıyor.
  coinLocker,

  /// Otel resepsiyonuna erken bırakılıyor (check-in öncesi).
  hotelEarlyDrop,

  /// Check-in penceresi açık; doğrudan odaya bırakılıyor.
  hotelCheckIn,

  /// Yamato/takuhaibin ile bir sonraki otele gönderiliyor (ertesi gün varış).
  yamatoForward,
}

extension LuggageHandlingStrategyTraits on LuggageHandlingStrategy {
  /// Bu strateji seçildiğinde geçiş günü istasyon/otel bagaj tamponu
  /// **uygulanmaz** — bagaj zaten yolcuda değildir.
  bool get bypassesStationLuggageBuffer =>
      this == LuggageHandlingStrategy.yamatoForward ||
      this == LuggageHandlingStrategy.none;
}

/// Kararın neden verildiğini taşıyan makine-okunur gerekçe.
enum LuggageAdvisory {
  /// Otel check-in saatinden önce varıldı.
  arrivedBeforeCheckIn,

  /// Otel check-in penceresi kapandıktan sonra varış — plan uygulanamaz.
  arrivedAfterCheckInWindow,

  /// Büyük bagaj coin locker'a sığmayabilir.
  oversizedForCoinLocker,

  /// İstasyonda coin locker bulunamayabilir (küçük istasyon).
  coinLockerUnlikelyAtStation,

  /// Yamato seçildi; bagaj ertesi gün varır, gecelik çanta gerekir.
  yamatoOvernightBagRequired,

  /// Yamato son teslim saati kaçırıldı; kargo aynı gün çıkmaz.
  yamatoCutoffMissed,

  /// Mesafe kargo için çok kısa — taşımak daha mantıklı.
  yamatoDistanceTooShort,

  /// Varış şehrinde tek gece kalınıyor; kargo yetişmeme riski taşır.
  yamatoStayTooShort,

  /// Otel istasyona uzak; sapma maliyeti coin locker'dan yüksek.
  hotelDetourExpensive,
}

// ---------------------------------------------------------------------------
// Politikalar
// ---------------------------------------------------------------------------

/// Gün içi dakika cinsinden saat (09:30 → 570).
int minutesOfDay(DateTime time) => time.hour * 60 + time.minute;

class HotelLuggagePolicy {
  const HotelLuggagePolicy({
    this.checkInStartMinutes = 15 * 60,
    this.checkInEndMinutes = 22 * 60,
    this.checkOutMinutes = 10 * 60,
    this.acceptsEarlyBagDrop = true,
    this.frontDeskServiceMinutes = 15,
    this.detourMinutesFromStation = 12,
    this.acceptsYamatoHandover = true,
  })  : assert(checkInStartMinutes >= 0),
        assert(checkInEndMinutes > checkInStartMinutes);

  /// Genelde 15:00.
  final int checkInStartMinutes;

  /// Genelde 22:00 — sonrası resepsiyon kapanır, giriş yapılamaz.
  final int checkInEndMinutes;

  final int checkOutMinutes;

  /// Japonya'da standart uygulama; küçük ryokan/minpaku'da olmayabilir.
  final bool acceptsEarlyBagDrop;

  final int frontDeskServiceMinutes;

  /// İstasyondan otele tek yön sapma süresi.
  final int detourMinutesFromStation;

  final bool acceptsYamatoHandover;

  /// Otele gidip bagaj bırakıp rotaya dönmenin toplam maliyeti.
  int get earlyDropRoundTripMinutes =>
      detourMinutesFromStation * 2 + frontDeskServiceMinutes;
}

class CoinLockerPolicy {
  const CoinLockerPolicy({
    this.searchAndStoreMinutes = 20,
    this.retrieveMinutes = 10,
    this.availableAtStation = true,
    this.largeBaySaturationRisk = true,
    this.costYenPerBag = 700,
  });

  /// Brief'in kuralı: erken varışta istasyonda +20 dk arama/bırakma tamponu.
  final int searchAndStoreMinutes;

  final int retrieveMinutes;
  final bool availableAtStation;

  /// Büyük göz doluluk riski — büyük valizde ek uyarı üretir.
  final bool largeBaySaturationRisk;

  final int costYenPerBag;
}

class YamatoPolicy {
  const YamatoPolicy({
    this.minimumTransferMinutes = 120,
    this.handoverMinutes = 20,
    this.sameDayCutoffMinutes = 10 * 60,
    this.deliveryLagDays = 1,
    this.costYenPerBag = 2200,
    this.minimumNightsAtDestination = 2,
    this.eligibleSizes = const {LuggageSize.large, LuggageSize.medium},
  });

  /// Bu eşiğin altındaki geçişte kargo mantıksızdır — taşımak daha ucuz/hızlı.
  final int minimumTransferMinutes;

  /// Otel resepsiyonunda kargo teslim işlemi (form + tartı).
  final int handoverMinutes;

  /// Aynı gün çıkış için son teslim saati (~10:00, otele göre değişir).
  final int sameDayCutoffMinutes;

  /// Şehirlerarası standart teslim gecikmesi.
  final int deliveryLagDays;

  final int costYenPerBag;

  /// Varış şehrinde en az bu kadar gece kalınmalı; tek gecede kargo yetişmez.
  final int minimumNightsAtDestination;

  final Set<LuggageSize> eligibleSizes;
}

class LuggagePolicy {
  const LuggagePolicy({
    this.hotel = const HotelLuggagePolicy(),
    this.coinLocker = const CoinLockerPolicy(),
    this.yamato = const YamatoPolicy(),
  });

  final HotelLuggagePolicy hotel;
  final CoinLockerPolicy coinLocker;
  final YamatoPolicy yamato;
}

// ---------------------------------------------------------------------------
// Karar girdisi / çıktısı
// ---------------------------------------------------------------------------

class LuggageContext {
  const LuggageContext({
    required this.size,
    required this.bagCount,
    required this.arrivalAtDestination,
    this.isCityTransitionDay = true,
    this.hasHotelChange = true,
    this.intercityTransferMinutes = 0,
    this.nightsAtDestination = 1,
    this.originHotelDepartureTime,
    this.coinLockerAvailableAtArrivalStation = true,
    this.userForcedStrategy,
  });

  final LuggageSize size;
  final int bagCount;

  /// Varış şehrindeki istasyona ulaşım saati.
  final DateTime arrivalAtDestination;

  final bool isCityTransitionDay;
  final bool hasHotelChange;

  /// Şehirlerarası geçişin saf yolculuk süresi (kargo eşiği için).
  final int intercityTransferMinutes;

  final int nightsAtDestination;

  /// Yamato teslimi kaynak otelden yapılır; cutoff kontrolü buna bakar.
  final DateTime? originHotelDepartureTime;

  final bool coinLockerAvailableAtArrivalStation;

  /// Kullanıcı iradesi — verilirse karar ağacı ezilir (uygulanabilirse).
  final LuggageHandlingStrategy? userForcedStrategy;
}

class LuggagePlan {
  const LuggagePlan({
    required this.strategy,
    required this.originHandoverMinutes,
    required this.arrivalHandlingMinutes,
    required this.retrievalMinutes,
    required this.estimatedCostYen,
    required this.advisories,
    required this.reasonCode,
    this.baggageAvailableAfterDays = 0,
  });

  factory LuggagePlan.none() => const LuggagePlan(
        strategy: LuggageHandlingStrategy.none,
        originHandoverMinutes: 0,
        arrivalHandlingMinutes: 0,
        retrievalMinutes: 0,
        estimatedCostYen: 0,
        advisories: {},
        reasonCode: 'no-luggage',
      );

  final LuggageHandlingStrategy strategy;

  /// Kaynak şehirde harcanan süre (Yamato teslimi).
  final int originHandoverMinutes;

  /// Varışta bagajı yerleştirmek için harcanan süre (locker / otel).
  final int arrivalHandlingMinutes;

  /// Gün sonunda bagajı geri almak için gereken süre (coin locker).
  final int retrievalMinutes;

  final int estimatedCostYen;
  final Set<LuggageAdvisory> advisories;

  /// Deterministik, loglanabilir karar kimliği.
  final String reasonCode;

  /// Yamato'da 1 — bagaj ertesi gün ulaşır.
  final int baggageAvailableAfterDays;

  bool get bypassesStationLuggageBuffer =>
      strategy.bypassesStationLuggageBuffer;

  /// Geçiş günü rotaya eklenen toplam bagaj süresi.
  int get totalScheduleImpactMinutes =>
      originHandoverMinutes + arrivalHandlingMinutes + retrievalMinutes;
}

/// Otel check-in penceresi hard kısıt sonucu.
enum HotelCheckInStatus {
  /// Check-in penceresi içinde — sorunsuz.
  withinWindow,

  /// Pencereden önce — bagaj çözümü gerekir ama plan geçerlidir.
  beforeWindow,

  /// Pencereden sonra — **hard violation**, gün planı uygulanamaz.
  afterWindow,
}

HotelCheckInStatus evaluateHotelCheckIn({
  required DateTime arrival,
  HotelLuggagePolicy policy = const HotelLuggagePolicy(),
}) {
  final minute = minutesOfDay(arrival);
  if (minute < policy.checkInStartMinutes) {
    return HotelCheckInStatus.beforeWindow;
  }
  if (minute > policy.checkInEndMinutes) return HotelCheckInStatus.afterWindow;
  return HotelCheckInStatus.withinWindow;
}

// ---------------------------------------------------------------------------
// Karar ağacı
// ---------------------------------------------------------------------------

class LuggageStrategyResolver {
  const LuggageStrategyResolver({this.policy = const LuggagePolicy()});

  final LuggagePolicy policy;

  LuggagePlan resolve(LuggageContext context) {
    if (context.size.isEmpty || context.bagCount <= 0) {
      return LuggagePlan.none();
    }
    if (!context.isCityTransitionDay || !context.hasHotelChange) {
      // Otel değişmiyorsa bagaj odada kalır; rotaya süre eklenmez.
      return const LuggagePlan(
        strategy: LuggageHandlingStrategy.none,
        originHandoverMinutes: 0,
        arrivalHandlingMinutes: 0,
        retrievalMinutes: 0,
        estimatedCostYen: 0,
        advisories: {},
        reasonCode: 'no-hotel-change',
      );
    }

    final forced = context.userForcedStrategy;
    if (forced != null) {
      final plan = _buildForStrategy(forced, context);
      if (plan != null) return plan;
    }

    // --- 1) Yamato uygunluk kapısı ----------------------------------------
    final yamato = _evaluateYamato(context);
    if (yamato != null) return yamato;

    // --- 2) Check-in penceresi -------------------------------------------
    final checkIn = evaluateHotelCheckIn(
      arrival: context.arrivalAtDestination,
      policy: policy.hotel,
    );

    if (checkIn == HotelCheckInStatus.withinWindow ||
        checkIn == HotelCheckInStatus.afterWindow) {
      // Pencere içinde (veya kapanmış — hard kısıt ayrıca raporlanır) doğrudan
      // odaya çıkılır; ek locker tamponu gereksizdir.
      return LuggagePlan(
        strategy: LuggageHandlingStrategy.hotelCheckIn,
        originHandoverMinutes: 0,
        arrivalHandlingMinutes: policy.hotel.detourMinutesFromStation +
            policy.hotel.frontDeskServiceMinutes,
        retrievalMinutes: 0,
        estimatedCostYen: 0,
        advisories: checkIn == HotelCheckInStatus.afterWindow
            ? const {LuggageAdvisory.arrivedAfterCheckInWindow}
            : const {},
        reasonCode: 'hotel-check-in-window',
      );
    }

    // --- 3) Erken varış: coin locker vs otele erken bırakma ---------------
    return _resolveEarlyArrival(context);
  }

  /// Erken varışta iki seçenek dakika bazında yarışır. Sabit kural yerine
  /// karşılaştırma kullanılır; Kyoto gibi oteli istasyona 3 dk olan şehirlerde
  /// coin locker'a para vermek gereksizdir.
  LuggagePlan _resolveEarlyArrival(LuggageContext context) {
    final advisories = <LuggageAdvisory>{LuggageAdvisory.arrivedBeforeCheckIn};

    final lockerAvailable = policy.coinLocker.availableAtStation &&
        context.coinLockerAvailableAtArrivalStation;
    if (!lockerAvailable) {
      advisories.add(LuggageAdvisory.coinLockerUnlikelyAtStation);
    }
    if (context.size == LuggageSize.large &&
        policy.coinLocker.largeBaySaturationRisk) {
      advisories.add(LuggageAdvisory.oversizedForCoinLocker);
    }

    final lockerMinutes = policy.coinLocker.searchAndStoreMinutes;
    final hotelMinutes = policy.hotel.earlyDropRoundTripMinutes;

    final lockerViable = lockerAvailable && context.size.fitsTypicalCoinLocker;
    final hotelViable = policy.hotel.acceptsEarlyBagDrop;

    if (hotelViable && (!lockerViable || hotelMinutes <= lockerMinutes)) {
      return LuggagePlan(
        strategy: LuggageHandlingStrategy.hotelEarlyDrop,
        originHandoverMinutes: 0,
        arrivalHandlingMinutes: hotelMinutes,
        retrievalMinutes: 0,
        estimatedCostYen: 0,
        advisories: Set.unmodifiable(advisories),
        reasonCode: 'early-arrival-hotel-drop',
      );
    }

    if (lockerViable || !hotelViable) {
      if (hotelViable && hotelMinutes > lockerMinutes) {
        advisories.add(LuggageAdvisory.hotelDetourExpensive);
      }
      return LuggagePlan(
        strategy: LuggageHandlingStrategy.coinLocker,
        originHandoverMinutes: 0,
        arrivalHandlingMinutes: lockerMinutes,
        retrievalMinutes: policy.coinLocker.retrieveMinutes,
        estimatedCostYen: policy.coinLocker.costYenPerBag * context.bagCount,
        advisories: Set.unmodifiable(advisories),
        reasonCode: 'early-arrival-coin-locker',
      );
    }

    // Ne locker ne otel — bagaj taşınır. Rotaya süre eklenmez ama maliyet
    // yürüme/aktarma cezası olarak `CostFunction` tarafına yansır.
    return LuggagePlan(
      strategy: LuggageHandlingStrategy.carry,
      originHandoverMinutes: 0,
      arrivalHandlingMinutes: 0,
      retrievalMinutes: 0,
      estimatedCostYen: 0,
      advisories: Set.unmodifiable(advisories),
      reasonCode: 'early-arrival-carry',
    );
  }

  /// Yamato uygunsa planı, değilse `null` döner (gerekçe akışta kaybolmasın
  /// diye uygunsuzluk nedeni erken varış planına advisory olarak taşınmaz —
  /// çağıran isterse [yamatoRejectionFor] ile sorar).
  LuggagePlan? _evaluateYamato(LuggageContext context) {
    if (yamatoRejectionFor(context) != null) return null;
    return LuggagePlan(
      strategy: LuggageHandlingStrategy.yamatoForward,
      originHandoverMinutes: policy.yamato.handoverMinutes,
      arrivalHandlingMinutes: 0,
      retrievalMinutes: 0,
      estimatedCostYen: policy.yamato.costYenPerBag * context.bagCount,
      advisories: const {LuggageAdvisory.yamatoOvernightBagRequired},
      reasonCode: 'yamato-forward',
      baggageAvailableAfterDays: policy.yamato.deliveryLagDays,
    );
  }

  /// Yamato neden seçilemedi? Uygunsa `null`.
  LuggageAdvisory? yamatoRejectionFor(LuggageContext context) {
    if (!policy.hotel.acceptsYamatoHandover) {
      return LuggageAdvisory.yamatoCutoffMissed;
    }
    if (!policy.yamato.eligibleSizes.contains(context.size)) {
      return LuggageAdvisory.yamatoDistanceTooShort;
    }
    if (context.intercityTransferMinutes <
        policy.yamato.minimumTransferMinutes) {
      return LuggageAdvisory.yamatoDistanceTooShort;
    }
    if (context.nightsAtDestination <
        policy.yamato.minimumNightsAtDestination) {
      return LuggageAdvisory.yamatoStayTooShort;
    }
    final departure = context.originHotelDepartureTime;
    if (departure != null &&
        minutesOfDay(departure) > policy.yamato.sameDayCutoffMinutes) {
      return LuggageAdvisory.yamatoCutoffMissed;
    }
    return null;
  }

  LuggagePlan? _buildForStrategy(
    LuggageHandlingStrategy strategy,
    LuggageContext context,
  ) =>
      switch (strategy) {
        LuggageHandlingStrategy.yamatoForward => _evaluateYamato(context),
        LuggageHandlingStrategy.coinLocker => LuggagePlan(
            strategy: LuggageHandlingStrategy.coinLocker,
            originHandoverMinutes: 0,
            arrivalHandlingMinutes: policy.coinLocker.searchAndStoreMinutes,
            retrievalMinutes: policy.coinLocker.retrieveMinutes,
            estimatedCostYen:
                policy.coinLocker.costYenPerBag * context.bagCount,
            advisories: const {},
            reasonCode: 'user-forced-coin-locker',
          ),
        LuggageHandlingStrategy.hotelEarlyDrop => LuggagePlan(
            strategy: LuggageHandlingStrategy.hotelEarlyDrop,
            originHandoverMinutes: 0,
            arrivalHandlingMinutes: policy.hotel.earlyDropRoundTripMinutes,
            retrievalMinutes: 0,
            estimatedCostYen: 0,
            advisories: const {},
            reasonCode: 'user-forced-hotel-drop',
          ),
        LuggageHandlingStrategy.carry => const LuggagePlan(
            strategy: LuggageHandlingStrategy.carry,
            originHandoverMinutes: 0,
            arrivalHandlingMinutes: 0,
            retrievalMinutes: 0,
            estimatedCostYen: 0,
            advisories: {},
            reasonCode: 'user-forced-carry',
          ),
        _ => null,
      };
}

/// Bagaj taşınıyorken yürüme/aktarma cezasının büyüme katsayısı.
/// `CostFunction` bunu kullanır; hard kısıt değildir.
double luggageDiscomfortFactor(
    LuggageHandlingStrategy strategy, LuggageSize size) {
  if (strategy != LuggageHandlingStrategy.carry) return 0;
  return size.handlingWeight;
}

/// Coin locker doluluk riskini dakika cinsinden muhafazakâr tampona çevirir.
int coinLockerContingencyMinutes({
  required LuggageSize size,
  CoinLockerPolicy policy = const CoinLockerPolicy(),
}) {
  if (!policy.largeBaySaturationRisk) return 0;
  return size == LuggageSize.large
      ? math.max(0, policy.searchAndStoreMinutes ~/ 2)
      : 0;
}
