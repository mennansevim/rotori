/// Japonya ulaşım saha gerçekliği: demiryolu pass kısıtları, dev istasyon
/// navigasyon tamponu ve karayolu trafik risk matrisi.
///
/// Bu katman **saf**tır: `TransportOption` üretmez, yalnız verilen seçeneği
/// saha koşullarına göre *yeniden değerler* — ya geçersiz (infeasible) sayar
/// ya da süre/tampon/uyarı ekleyerek düzeltir.
///
/// Tüm süreler tahmindir. Canlı tren gecikmesi veya gerçek zamanlı trafik
/// verisi **kapsam dışıdır**; bu yüzden risk taşıyan her düzeltme UI'a
/// `disclaimer` olarak taşınır ve kullanıcıya kesinlik vaadi verilmez.
library;

import 'dart:math' as math;

import 'minute_math.dart';
import 'route_matrix.dart';

// ---------------------------------------------------------------------------
// Demiryolu pass katmanı
// ---------------------------------------------------------------------------

/// Kullanıcının elindeki demiryolu bileti tipi.
enum RailPassType {
  /// Pass yok — tüm servisler geçerli, ücret tam.
  none,

  /// 全国版 Japan Rail Pass.
  nationalJrPass,

  /// Bölgesel JR Pass (JR East / JR West / JR Kyushu / JR Hokkaido …).
  regionalJrPass,

  /// JR olmayan pass (Kansai Thru Pass, Osaka Amazing Pass …). Shinkansen'i
  /// hiç kapsamaz; Shinkansen seçilirse tam ücret ödenir.
  nonJrPass,
}

extension RailPassCapabilities on RailPassType {
  bool get coversJrLines =>
      this == RailPassType.nationalJrPass ||
      this == RailPassType.regionalJrPass;

  /// Bölgesel pass yalnız kendi bölgesinde geçerlidir; şehirlerarası uzun
  /// hatlarda kapsam dışı kalabilir. Kapsam kontrolü çağıranın sorumluluğu.
  bool get isRegionallyScoped => this == RailPassType.regionalJrPass;
}

/// Shinkansen servis sınıfı. Hız sırası: Nozomi/Mizuho > Hikari/Sakura >
/// Kodama/Tsubame.
enum ShinkansenService {
  nozomi,
  mizuho,
  hikari,
  sakura,
  kodama,
  tsubame,

  /// Tokaido–Sanyo dışı hatlar (Hokuriku, Tohoku, Kyushu ekspresleri).
  /// JR Pass bunları kapsar; kısıt uygulanmaz.
  otherLine,
}

/// JR Pass ile kullanılamayan servisler.
///
/// Saha notu: Ekim 2023'ten beri ulusal JR Pass, ek ücret (特急券差額)
/// ödenerek Nozomi/Mizuho'ya biniş imkânı sunuyor. Rotori'nin offline
/// modeli **varsayılan olarak** bunu geçersiz sayar (ürün kararı: kullanıcıya
/// "pass'in yeter" deyip istasyonda sürpriz ücret çıkarmamak). Gerçek davranış
/// [RailPassPolicy.allowNozomiWithSurcharge] ile temsil edilebilir.
const Set<ShinkansenService> kJrPassExcludedServices = {
  ShinkansenService.nozomi,
  ShinkansenService.mizuho,
};

/// Pass kapsamı dışı bir servisle ne yapılacağı.
enum PassExclusionBehaviour {
  /// Seçenek **geçersiz** sayılır. Rota matrisi için doğru davranıştır:
  /// sağlayıcı somut bir Nozomi seferi verdiyse, onu "aslında Hikari'ydi"
  /// diye yeniden etiketlemek sahada var olmayan bir tren uydurmak olur.
  reject,

  /// Seçenek korunur ama süre daha yavaş servise göre uzatılır. Şehirlerarası
  /// geçiş satırı gibi **tahmini** kayıtlar için uygundur.
  downgradeInPlace,
}

class RailPassPolicy {
  const RailPassPolicy({
    this.excludedServiceBehaviour = PassExclusionBehaviour.reject,
    this.allowNozomiWithSurcharge = false,
    this.hikariDurationMultiplier = 1.20,
    this.sakuraDurationMultiplier = 1.10,
    this.kodamaDurationMultiplier = 1.55,
    this.downgradeAddsTransfers = 0,
  });

  /// Pass'in kapsamadığı servis nasıl ele alınır.
  final PassExclusionBehaviour excludedServiceBehaviour;

  /// `true` ise Nozomi/Mizuho geçersiz sayılmaz; yalnız ek ücret uyarısı
  /// eklenir ve süre değişmez. [excludedServiceBehaviour]'dan önce gelir.
  final bool allowNozomiWithSurcharge;

  /// Nozomi süresine göre Hikari çarpanı (brief: +%15–20).
  final double hikariDurationMultiplier;

  /// Mizuho süresine göre Sakura çarpanı — Sakura, Mizuho'ya çok yakındır.
  final double sakuraDurationMultiplier;

  /// Yalnız Kodama servisi varsa uygulanan çarpan (her istasyonda durur).
  final double kodamaDurationMultiplier;

  /// Downgrade edilen servis aktarma gerektiriyorsa eklenecek aktarma sayısı.
  final int downgradeAddsTransfers;
}

/// Serbest metinden ("Shinkansen Nozomi", "nozomi-tokaido") servis çözer.
/// Tanınmayan değer `null` döner — bilinmeyen servise kısıt uygulanmaz.
ShinkansenService? shinkansenServiceFromText(String? raw) {
  if (raw == null) return null;
  final value = raw.toLowerCase();
  if (value.contains('nozomi')) return ShinkansenService.nozomi;
  if (value.contains('mizuho')) return ShinkansenService.mizuho;
  if (value.contains('hikari')) return ShinkansenService.hikari;
  if (value.contains('sakura')) return ShinkansenService.sakura;
  if (value.contains('kodama')) return ShinkansenService.kodama;
  if (value.contains('tsubame')) return ShinkansenService.tsubame;
  const otherLines = [
    'hayabusa',
    'hayate',
    'komachi',
    'yamabiko',
    'nasuno',
    'toki',
    'tanigawa',
    'kagayaki',
    'hakutaka',
    'tsurugi',
    'asama',
    'tsubasa',
  ];
  if (otherLines.any(value.contains)) return ShinkansenService.otherLine;
  if (value.contains('shinkansen')) return ShinkansenService.otherLine;
  return null;
}

/// Bir servisin pass ile geçerli downgrade karşılığı.
class ShinkansenDowngrade {
  const ShinkansenDowngrade({
    required this.replacement,
    required this.durationMultiplier,
    required this.addedTransferCount,
  });

  final ShinkansenService replacement;
  final double durationMultiplier;
  final int addedTransferCount;
}

// ---------------------------------------------------------------------------
// İstasyon karmaşıklığı katmanı
// ---------------------------------------------------------------------------

/// İstasyonun içinde kaybolma / uzun peron yürüyüşü riski.
enum StationComplexity {
  /// Tek peron, tek çıkış — ek tampon gerekmez.
  simple,

  /// Standart şehir içi istasyon.
  normal,

  /// "Labyrinth" — çok hatlı devasa kompleks (Shinjuku, Tokyo, Umeda…).
  labyrinth,
}

extension StationComplexityBuffer on StationComplexity {
  /// Yürüme/aktarma süresine eklenecek navigasyon tamponu.
  int get navigationBufferMinutes => switch (this) {
        StationComplexity.simple => 0,
        StationComplexity.normal => 0,
        StationComplexity.labyrinth => 15,
      };
}

/// İsim/kimlik eşleşmesiyle istasyon karmaşıklığı çözen kayıt defteri.
///
/// `TripLocation`'a alan eklemeden çalışır — eski planlar ve mevcut katalog
/// olduğu gibi kullanılabilir. Katalog açık değer verirse [overrides] kazanır.
class StationComplexityRegistry {
  StationComplexityRegistry({
    Map<String, StationComplexity> overrides = const {},
    Set<String> additionalLabyrinthTokens = const {},
  })  : overrides = Map.unmodifiable({
          for (final entry in overrides.entries)
            _normalize(entry.key): entry.value,
        }),
        _labyrinthTokens = Set.unmodifiable({
          ..._defaultLabyrinthTokens,
          ...additionalLabyrinthTokens.map(_normalize),
        }),
        _labyrinthAliases = Set.unmodifiable(_defaultLabyrinthAliases);

  final Map<String, StationComplexity> overrides;
  final Set<String> _labyrinthTokens;
  final Set<String> _labyrinthAliases;

  /// Japonya'nın "içinde kaybolunan" istasyonları. Token eşleşmesi ada göre
  /// yapılır. Romaji adlarda token, Japonca adlarda açık alias kullanılır;
  /// böylece `東京国立博物館` gibi istasyon olmayan yerler yalnız şehir adı
  /// içerdiği için yanlışlıkla labyrinth sayılmaz.
  static const Set<String> _defaultLabyrinthTokens = {
    'shinjuku',
    'tokyostation',
    'tokyoeki',
    'shibuya',
    'ikebukuro',
    'umeda',
    'osakastation',
    'osakaeki',
    'shinosaka',
    'namba',
    'tennoji',
    'kyotostation',
    'kyotoeki',
    'nagoyastation',
    'nagoyaeki',
    'yokohamastation',
    'shinagawa',
    'ueno',
    'hakata',
    'sendaistation',
    'sapporostation',
    'oomiya',
    'omiya',
  };

  static const Set<String> _defaultLabyrinthAliases = {
    '新宿',
    '新宿駅',
    '東京駅',
    '渋谷',
    '渋谷駅',
    '池袋',
    '池袋駅',
    '梅田',
    '梅田駅',
    '大阪駅',
    '新大阪',
    '新大阪駅',
    '難波',
    '難波駅',
    '天王寺',
    '天王寺駅',
    '京都駅',
    '名古屋駅',
    '横浜駅',
    '品川',
    '品川駅',
    '上野',
    '上野駅',
    '博多',
    '博多駅',
    '仙台駅',
    '札幌駅',
    '大宮',
    '大宮駅',
  };

  StationComplexity resolve({String? locationId, String? name}) {
    for (final raw in [locationId, name]) {
      if (raw == null || raw.isEmpty) continue;
      final normalized = _normalize(raw);
      final override = overrides[normalized];
      if (override != null) return override;
    }
    for (final raw in [locationId, name]) {
      if (raw == null || raw.isEmpty) continue;
      final normalized = _normalize(raw);
      if (_labyrinthAliases.contains(normalized)) {
        return StationComplexity.labyrinth;
      }
      if (_labyrinthTokens.any(normalized.contains)) {
        return StationComplexity.labyrinth;
      }
    }
    return StationComplexity.normal;
  }

  bool isLabyrinth({String? locationId, String? name}) =>
      resolve(locationId: locationId, name: name) ==
      StationComplexity.labyrinth;

  static String _normalize(String value) => value.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9\u3040-\u30ff\u3400-\u9fff々ヶ]+'),
        '',
      );
}

// ---------------------------------------------------------------------------
// Karayolu trafik risk matrisi
// ---------------------------------------------------------------------------

/// Otobüs/taksi için trafik belirsizliği çarpanı.
class TrafficRiskPolicy {
  const TrafficRiskPolicy({
    this.peakMultiplier = 1.30,
    this.offPeakMultiplier = 1.10,
    this.weekendLeisureMultiplier = 1.15,
    this.morningPeak = const (7 * 60, 9 * 60 + 30),
    this.eveningPeak = const (17 * 60, 19 * 60 + 30),
  });

  final double peakMultiplier;
  final double offPeakMultiplier;

  /// Hafta sonu / resmî tatilde işe gidiş zirvesi yoktur ama turistik
  /// koridorlarda gün ortası tıkanır.
  final double weekendLeisureMultiplier;

  final (int, int) morningPeak;
  final (int, int) eveningPeak;

  bool isPeak(DateTime departure) {
    final minute = departure.hour * 60 + departure.minute;
    bool within((int, int) window) =>
        minute >= window.$1 && minute <= window.$2;
    return within(morningPeak) || within(eveningPeak);
  }

  bool isWeekend(DateTime departure) =>
      departure.weekday == DateTime.saturday ||
      departure.weekday == DateTime.sunday;

  double multiplierFor(
    DateTime departure, {
    bool isPublicHoliday = false,
  }) {
    if (isWeekend(departure) || isPublicHoliday) {
      return weekendLeisureMultiplier;
    }
    return isPeak(departure) ? peakMultiplier : offPeakMultiplier;
  }
}

/// Trafik riskine tabi modlar. Raylı sistem Japonya'da dakikliğiyle bilinir;
/// çarpan uygulanmaz.
const Set<TransportMode> kTrafficExposedModes = {
  TransportMode.bus,
  TransportMode.taxi,
};

// ---------------------------------------------------------------------------
// Model çıktısı
// ---------------------------------------------------------------------------

enum TransitInfeasibilityReason {
  /// JR Pass sahibinin binemeyeceği servis (Nozomi/Mizuho).
  passExcludedService,

  /// Seçenek geçerli değil (negatif süre vb.) — matris hatası.
  malformedOption,
}

/// UI'da gösterilecek uyarı türleri. Metin değil **anahtar** taşınır; l10n
/// çözümlemesi sunum katmanının işidir.
enum TransitDisclaimer {
  /// `hasTrafficRiskDisclaimer` — varış saati trafiğe bağlı.
  trafficRisk,

  /// Dev istasyon navigasyon tamponu eklendi.
  stationNavigationBuffer,

  /// JR Pass nedeniyle daha yavaş servise düşüldü.
  railPassDowngrade,

  /// Nozomi/Mizuho'ya ek ücretle binildi.
  railPassSurcharge,

  /// Pass bu hattı kapsamıyor, tam ücret.
  railPassNotCovered,

  /// Kalabalık sezon nedeniyle yürüme süresi uzatıldı.
  seasonalCrowding,
}

/// `TransitRealismModel` çıktısı — orijinal seçeneği değiştirmez, üzerine
/// uygulanacak düzeltmeleri taşır.
class TransitRealismOutcome {
  const TransitRealismOutcome._({
    required this.isFeasible,
    required this.doorToDoorMinutes,
    required this.walkingMinutes,
    required this.transferCount,
    required this.stationNavigationBufferMinutes,
    required this.trafficRiskMultiplier,
    required this.disclaimers,
    required this.effectiveService,
    required this.surchargeYen,
    this.infeasibilityReason,
  });

  factory TransitRealismOutcome.infeasible(
    TransitInfeasibilityReason reason, {
    ShinkansenService? service,
  }) =>
      TransitRealismOutcome._(
        isFeasible: false,
        doorToDoorMinutes: 0,
        walkingMinutes: 0,
        transferCount: 0,
        stationNavigationBufferMinutes: 0,
        trafficRiskMultiplier: 1,
        disclaimers: const {},
        effectiveService: service,
        surchargeYen: 0,
        infeasibilityReason: reason,
      );

  final bool isFeasible;

  /// Tüm düzeltmeler (trafik çarpanı + istasyon tamponu + pass downgrade)
  /// uygulandıktan sonraki kapıdan kapıya süre.
  final int doorToDoorMinutes;
  final int walkingMinutes;
  final int transferCount;

  /// Yürüme süresine dahil edilen dev istasyon tamponu — UI ayrı gösterebilir.
  final int stationNavigationBufferMinutes;

  final double trafficRiskMultiplier;
  final Set<TransitDisclaimer> disclaimers;
  final ShinkansenService? effectiveService;

  /// Pass kapsamı dışı biniş için tahmini ek ücret (kişi başı ¥).
  final int surchargeYen;

  final TransitInfeasibilityReason? infeasibilityReason;

  bool get hasTrafficRiskDisclaimer =>
      disclaimers.contains(TransitDisclaimer.trafficRisk);

  bool get hasStationNavigationBuffer => stationNavigationBufferMinutes > 0;
}

/// Ulaşım seçeneğini saha gerçekliğine göre yeniden değerleyen saf model.
class TransitRealismModel {
  TransitRealismModel({
    StationComplexityRegistry? stations,
    this.railPassPolicy = const RailPassPolicy(),
    this.trafficPolicy = const TrafficRiskPolicy(),
  }) : stations = stations ?? StationComplexityRegistry();

  final StationComplexityRegistry stations;
  final RailPassPolicy railPassPolicy;
  final TrafficRiskPolicy trafficPolicy;

  /// Nozomi/Mizuho için pass ile geçerli karşılık.
  ShinkansenDowngrade? downgradeFor(ShinkansenService service) =>
      switch (service) {
        ShinkansenService.nozomi => ShinkansenDowngrade(
            replacement: ShinkansenService.hikari,
            durationMultiplier: railPassPolicy.hikariDurationMultiplier,
            addedTransferCount: railPassPolicy.downgradeAddsTransfers,
          ),
        ShinkansenService.mizuho => ShinkansenDowngrade(
            replacement: ShinkansenService.sakura,
            durationMultiplier: railPassPolicy.sakuraDurationMultiplier,
            addedTransferCount: railPassPolicy.downgradeAddsTransfers,
          ),
        _ => null,
      };

  /// Ana giriş noktası.
  ///
  /// [departure] trafik zirvesi kararında; [fromName]/[toName] istasyon
  /// karmaşıklığında; [railPass] Shinkansen kısıtında kullanılır.
  /// [walkingMultiplier] sezonluk kalabalık modelinden gelir (1.0 = etkisiz).
  TransitRealismOutcome evaluate(
    TransportOption option, {
    required DateTime departure,
    RailPassType railPass = RailPassType.none,
    String? fromLocationId,
    String? fromName,
    String? toLocationId,
    String? toName,
    double walkingMultiplier = 1.0,
    bool passCoversThisLeg = true,
    bool isPublicHoliday = false,
  }) {
    if (!option.isValid) {
      return TransitRealismOutcome.infeasible(
        TransitInfeasibilityReason.malformedOption,
      );
    }

    final disclaimers = <TransitDisclaimer>{};
    var rideMinutes = option.doorToDoorMinutes.toDouble();
    var walking = option.walkingMinutes.toDouble();
    var transfers = option.transferCount;
    var surcharge = 0;

    // --- 1) Demiryolu pass kısıtı -----------------------------------------
    final service = _serviceFor(option);
    var effectiveService = service;
    if (service != null && option.mode == TransportMode.shinkansen) {
      final restricted =
          railPass.coversJrLines && kJrPassExcludedServices.contains(service);
      if (restricted && passCoversThisLeg) {
        if (railPassPolicy.allowNozomiWithSurcharge) {
          disclaimers.add(TransitDisclaimer.railPassSurcharge);
          surcharge = option.estimatedCostYen;
        } else {
          final downgrade = downgradeFor(service);
          if (railPassPolicy.excludedServiceBehaviour ==
                  PassExclusionBehaviour.reject ||
              downgrade == null) {
            return TransitRealismOutcome.infeasible(
              TransitInfeasibilityReason.passExcludedService,
              service: service,
            );
          }
          rideMinutes *= downgrade.durationMultiplier;
          transfers += downgrade.addedTransferCount;
          effectiveService = downgrade.replacement;
          disclaimers.add(TransitDisclaimer.railPassDowngrade);
        }
      } else if (railPass.coversJrLines && !passCoversThisLeg) {
        // Bölgesel pass kapsamı dışına çıkıldı — ücret tam.
        disclaimers.add(TransitDisclaimer.railPassNotCovered);
      } else if (railPass == RailPassType.nonJrPass) {
        disclaimers.add(TransitDisclaimer.railPassNotCovered);
      }
    }

    // --- 2) Karayolu trafik riski -----------------------------------------
    var trafficMultiplier = 1.0;
    if (kTrafficExposedModes.contains(option.mode)) {
      trafficMultiplier = _trafficMultiplier(
        departure,
        isPublicHoliday: isPublicHoliday,
      );
      rideMinutes *= trafficMultiplier;
      disclaimers.add(TransitDisclaimer.trafficRisk);
    }

    // --- 3) Sezonluk kalabalık (yürüme yavaşlaması) ------------------------
    // Kalabalık treni yavaşlatmaz, yürüyüşü yavaşlatır — çarpan yalnız
    // erişim/aktarma yürüyüşüne uygulanır.
    if (walkingMultiplier > 1 && walking > 0) {
      walking *= walkingMultiplier;
      disclaimers.add(TransitDisclaimer.seasonalCrowding);
    }

    // --- 4) Dev istasyon navigasyon tamponu -------------------------------
    final navigationBuffer = _navigationBuffer(
      option: option,
      fromLocationId: fromLocationId,
      fromName: fromName,
      toLocationId: toLocationId,
      toName: toName,
    );
    if (navigationBuffer > 0) {
      walking += navigationBuffer;
      disclaimers.add(TransitDisclaimer.stationNavigationBuffer);
    }

    // Yürüme artışı kapıdan kapıya süreye de yansır: peron yürüyüşü yolculuk
    // süresinin *içinde* değil, üstünedir.
    final walkingDelta = walking - option.walkingMinutes;
    final doorToDoor = rideMinutes + math.max(0.0, walkingDelta);

    return TransitRealismOutcome._(
      isFeasible: true,
      doorToDoorMinutes: ceilMinutes(doorToDoor),
      walkingMinutes: ceilMinutes(walking),
      transferCount: transfers,
      stationNavigationBufferMinutes: navigationBuffer,
      trafficRiskMultiplier: trafficMultiplier,
      disclaimers: Set.unmodifiable(disclaimers),
      effectiveService: effectiveService,
      surchargeYen: surcharge,
    );
  }

  ShinkansenService? _serviceFor(TransportOption option) {
    if (option.mode != TransportMode.shinkansen) return null;
    return shinkansenServiceFromText(option.lineId) ??
        shinkansenServiceFromText(option.providerId);
  }

  double _trafficMultiplier(
    DateTime departure, {
    required bool isPublicHoliday,
  }) =>
      trafficPolicy.multiplierFor(
        departure,
        isPublicHoliday: isPublicHoliday,
      );

  /// Tampon yalnız istasyon kullanan modlarda geçerlidir; kapı önünden alan
  /// taksi veya doğrudan yürüyüş için istasyon labirenti yoktur.
  int _navigationBuffer({
    required TransportOption option,
    String? fromLocationId,
    String? fromName,
    String? toLocationId,
    String? toName,
  }) {
    const stationModes = {
      TransportMode.train,
      TransportMode.metro,
      TransportMode.shinkansen,
      TransportMode.regionalTrain,
    };
    if (!stationModes.contains(option.mode)) return 0;

    var buffer = 0;
    final origin = stations.resolve(locationId: fromLocationId, name: fromName);
    final destination =
        stations.resolve(locationId: toLocationId, name: toName);
    buffer += origin.navigationBufferMinutes;
    buffer += destination.navigationBufferMinutes;

    // Aynı yolculukta iki labirent istasyon varsa çift tampon uygulanır; bu
    // saha gerçeğidir (Shinjuku'dan çık → Tokyo'da peron değiştir).
    return buffer;
  }
}

/// Şehirlerarası geçiş satırı (`DayPlan.cityTransition`) için pass etkisi.
///
/// `city_transfers.dart` metin tabanlı `CityTransfer` üretir; bu yardımcı,
/// pass'in geçiş satırındaki servis adını ve süresini nasıl değiştirdiğini
/// tek yerde tanımlar.
class CityTransferPassAdjustment {
  const CityTransferPassAdjustment({
    required this.isServiceChanged,
    required this.originalService,
    required this.effectiveService,
    required this.adjustedMinutes,
    required this.disclaimers,
  });

  final bool isServiceChanged;
  final ShinkansenService? originalService;
  final ShinkansenService? effectiveService;
  final int adjustedMinutes;
  final Set<TransitDisclaimer> disclaimers;
}

CityTransferPassAdjustment adjustCityTransferForPass({
  required String modeLabel,
  required int baseMinutes,
  required RailPassType railPass,
  RailPassPolicy policy = const RailPassPolicy(),
  bool passCoversThisLeg = true,
}) {
  final service = shinkansenServiceFromText(modeLabel);
  if (service == null ||
      !railPass.coversJrLines ||
      !passCoversThisLeg ||
      !kJrPassExcludedServices.contains(service)) {
    return CityTransferPassAdjustment(
      isServiceChanged: false,
      originalService: service,
      effectiveService: service,
      adjustedMinutes: baseMinutes,
      disclaimers: railPass == RailPassType.nonJrPass && service != null
          ? const {TransitDisclaimer.railPassNotCovered}
          : const {},
    );
  }
  if (policy.allowNozomiWithSurcharge) {
    return CityTransferPassAdjustment(
      isServiceChanged: false,
      originalService: service,
      effectiveService: service,
      adjustedMinutes: baseMinutes,
      disclaimers: const {TransitDisclaimer.railPassSurcharge},
    );
  }
  final multiplier = service == ShinkansenService.mizuho
      ? policy.sakuraDurationMultiplier
      : policy.hikariDurationMultiplier;
  final replacement = service == ShinkansenService.mizuho
      ? ShinkansenService.sakura
      : ShinkansenService.hikari;
  return CityTransferPassAdjustment(
    isServiceChanged: true,
    originalService: service,
    effectiveService: replacement,
    adjustedMinutes: scaleMinutes(baseMinutes, multiplier),
    disclaimers: const {TransitDisclaimer.railPassDowngrade},
  );
}

/// Servis enum'unu kullanıcıya gösterilecek düz isme çevirir (i18n anahtarı
/// değil — özel isimler çevrilmez).
String shinkansenServiceLabel(ShinkansenService service) => switch (service) {
      ShinkansenService.nozomi => 'Nozomi',
      ShinkansenService.mizuho => 'Mizuho',
      ShinkansenService.hikari => 'Hikari',
      ShinkansenService.sakura => 'Sakura',
      ShinkansenService.kodama => 'Kodama',
      ShinkansenService.tsubame => 'Tsubame',
      ShinkansenService.otherLine => 'Shinkansen',
    };
