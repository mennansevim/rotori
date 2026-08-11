// TypeScript packages/shared/src/cityTransfers.ts'in Dart karşılığı.
// Şehirler arası bilinen transferler + plan içinde şehir geçişi tespiti.

import '../core/l10n.dart';
import 'destination_profiles.dart';
import 'japan_transit_realism.dart';
import 'luggage_logistics.dart';
import 'plan_field_signals.dart';
import 'trip_factory.dart';
import 'types.dart';

class CityTransfer {
  const CityTransfer({
    required this.emoji,
    required this.mode,
    required this.duration,
    required this.fare,
    this.tip,
  });

  final String emoji;

  /// UI başlığı. Özel isimler (ör. "Shinkansen Nozomi") düz metindir;
  /// çevrilebilir mod adları i18n anahtarıdır (ör. "xfer.mode.localTrain").
  /// Gösterirken `L10n.resolve(mode, lang)` ile çözülür — anahtar değilse
  /// metin aynen döner.
  final String mode;

  /// Yaklaşık süre (ör. "2s 30dk")
  final String duration;

  /// Tek yön yaklaşık ücret (ör. "~14,000 ¥")
  final String fare;

  /// Plan içinde gösterilecek kısa ipucu — i18n anahtarı (ör. "xfer.tip.bus").
  /// Gösterirken `L10n.resolve(tip, lang)` ile çözülür.
  final String? tip;
}

/// Shinkansen'in RESMÎ rezervasyon sitesi (JR Central / JR West ortak
/// Smart-EX servisi). Bayi ya da afiliye bağlantısı DEĞİLDİR.
///
/// Tokaido–Sanyo hattını (Tokyo–Nagoya–Kyoto–Osaka–Hiroshima–Hakata) kapsar;
/// uygulamadaki şehir geçişlerinin büyük çoğunluğu bu hat üzerindedir.
const String kShinkansenOfficialUrl = 'https://smart-ex.jp/';

const Map<String, CityTransfer> _transfers = {
  'tokyo|osaka': CityTransfer(
    emoji: '🚄',
    mode: 'Shinkansen Nozomi',
    duration: '2s 30dk',
    fare: '~14,720 ¥',
    tip: 'xfer.tip.tokyoOsaka',
  ),
  'tokyo|kyoto': CityTransfer(
    emoji: '🚄',
    mode: 'Shinkansen Nozomi',
    duration: '2s 15dk',
    fare: '~14,170 ¥',
    tip: 'xfer.tip.tokyoKyoto',
  ),
  'tokyo|hakone': CityTransfer(
    emoji: '🚆',
    mode: 'Odakyu Romance Car',
    duration: '1s 30dk',
    fare: '~2,470 ¥',
    tip: 'xfer.tip.tokyoHakone',
  ),
  'tokyo|nikko': CityTransfer(
    emoji: '🚆',
    mode: 'Tobu Limited Express Spacia',
    duration: '2s',
    fare: '~2,800 ¥',
  ),
  'tokyo|nagoya': CityTransfer(
    emoji: '🚄',
    mode: 'Shinkansen Nozomi',
    duration: '1s 40dk',
    fare: '~11,300 ¥',
  ),
  'osaka|kyoto': CityTransfer(
    emoji: '🚆',
    mode: 'JR Special Rapid',
    duration: '30dk',
    fare: '~580 ¥',
    tip: 'xfer.tip.osakaKyoto',
  ),
  'osaka|nara': CityTransfer(
    emoji: '🚆',
    mode: 'Kintetsu Limited Express',
    duration: '45dk',
    fare: '~1,140 ¥',
  ),
  'osaka|hiroshima': CityTransfer(
    emoji: '🚄',
    mode: 'Shinkansen Sakura/Nozomi',
    duration: '1s 25dk',
    fare: '~10,500 ¥',
  ),
  'kyoto|nara': CityTransfer(
    emoji: '🚆',
    mode: 'JR Nara Line',
    duration: '45dk',
    fare: '~720 ¥',
  ),
  'kyoto|osaka': CityTransfer(
    emoji: '🚆',
    mode: 'JR Special Rapid',
    duration: '30dk',
    fare: '~580 ¥',
  ),
  'nara|kyoto': CityTransfer(
    emoji: '🚆',
    mode: 'JR Nara Line',
    duration: '45dk',
    fare: '~720 ¥',
  ),
  'tokyo|fuji': CityTransfer(
    emoji: '🚌',
    mode: 'Highway Bus Shinjuku → Kawaguchiko',
    duration: '2s 15dk',
    fare: '~2,200 ¥',
  ),
};

String _normCity(String city) => city
    .toLowerCase()
    .replaceAll(RegExp(r'\s+\(.*?\)$'), '')
    .replaceAll(RegExp(r'[-_\s]+'), '')
    .trim();

/// İki şehir için bilinen transferi döndür (her iki yön de kabul edilir).
CityTransfer? lookupTransfer(String from, String to) {
  final a = _normCity(from);
  final b = _normCity(to);
  return _transfers['$a|$b'] ?? _transfers['$b|$a'];
}

/// Bir gün için "ana şehir" — önce öğelerdeki cityId, sonra destinasyon.
String? _dayDominantCity(DayPlan day, List<TripDestination> destinations) {
  for (final item in day.items) {
    if (item.cityId != null) return item.cityId;
  }
  return getDestinationForDate(destinations, day.date)?.city;
}

class CityTransitionSuggestion {
  const CityTransitionSuggestion({
    required this.fromDayNumber,
    required this.toDayNumber,
    required this.fromCity,
    required this.toCity,
    required this.transfer,
  });

  final int fromDayNumber;
  final int toDayNumber;
  final String fromCity;
  final String toCity;
  final CityTransfer transfer;
}

/// Plan günleri içinde ardışık şehir geçişlerini ve önerilen transfer biçimini bul.
List<CityTransitionSuggestion> detectCityTransitions(
  List<DayPlan> days,
  List<TripDestination> destinations,
) {
  final out = <CityTransitionSuggestion>[];
  final sorted = [...days]..sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
  String? prevCity;
  int? prevDay;
  for (final day in sorted) {
    final city = _dayDominantCity(day, destinations);
    if (city != null &&
        city.isNotEmpty &&
        prevCity != null &&
        _normCity(city) != _normCity(prevCity)) {
      final transfer = lookupTransfer(prevCity, city);
      if (transfer != null) {
        out.add(CityTransitionSuggestion(
          fromDayNumber: prevDay!,
          toDayNumber: day.dayNumber,
          fromCity: prevCity,
          toCity: city,
          transfer: transfer,
        ));
      }
    }
    if (city != null && city.isNotEmpty) {
      prevCity = city;
      prevDay = day.dayNumber;
    }
  }
  return out;
}

/// Verilen güne, başına şehir-arası transfer öğesi ekle ve o günün diğer
/// aktivitelerinin saatlerini transfere göre yeniden dağıt.
///
/// - Transfer 09:00'da kalkar (sabah yola çıkılır).
/// - Varış saati = kalkış + transfer süresi + 45 dk tampon (süre metninden
///   çözülür; çözülemezse ~3 saat varsayılır).
/// - Günün kalan öğeleri varıştan itibaren ~2 saat arayla yeniden zamanlanır —
///   böylece "önce yolculuk, sonra keşif" akışı ve çakışmasız saatler oluşur.
/// [lang] ile transfer mod adı ve ipucu (i18n anahtarları) o an seçili dile
/// çözülüp öğeye yazılır — böylece plana eklenen metin sabitlenir.
List<DayPlan> insertCityTransfer(
  List<DayPlan> days,
  int dayNumber,
  CityTransitionSuggestion suggestion, {
  AppLang lang = AppLang.tr,
}) {
  return days.map((d) {
    if (d.dayNumber != dayNumber) return d;
    final t = suggestion.transfer;
    const depMin = 9 * 60; // 09:00 kalkış
    final arrMin = (depMin + _transferDurationMin(t.duration) + 45)
        .clamp(depMin + 60, 21 * 60);
    final transfer = TimelineItem(
      id: newItemId(dayNumber),
      isCityTransition: true,
      title:
          '${t.emoji} ${suggestion.fromCity} → ${suggestion.toCity} • ${L10n.resolve(t.mode, lang)}',
      description: '${t.duration} · ${t.fare}',
      tips: t.tip == null ? null : L10n.resolve(t.tip!, lang),
      kind: TimelineItemKind.transport,
      time: _hhmm(depMin),
      scheduledTime: _hhmm(depMin),
      durationMin: _transferDurationMin(t.duration),
      cityId: suggestion.toCity,
    );
    // Kalan aktiviteleri varış sonrası sıralı slotlara dağıt (30 dk'ya yuvarla).
    var slot = ((arrMin + 29) ~/ 30) * 30;
    final retimed = <TimelineItem>[];
    for (final it in d.items) {
      final s = slot.clamp(0, 22 * 60);
      retimed.add(it.copyWith(time: _hhmm(s), scheduledTime: _hhmm(s)));
      slot += 120;
    }
    return d.copyWith(
      items: [transfer, ...retimed],
      cityTransition: CityTransitionPlan(
        fromCity: suggestion.fromCity,
        toCity: suggestion.toCity,
        mode: cityTransitionModeForTransfer(t),
      ),
    );
  }).toList();
}

/// Tespit edilen tüm şehir geçişlerini günlere ekler (idempotent —
/// zaten transfer olan güne yeniden eklemez). planner._generate ve demo
/// aynı pipeline'ı kullanır.
List<DayPlan> applyCityTransitions(
  List<DayPlan> days,
  List<TripDestination> destinations, {
  AppLang lang = AppLang.tr,
}) {
  var out = days;
  for (final s in detectCityTransitions(out, destinations)) {
    final target = out.where((d) => d.dayNumber == s.toDayNumber);
    if (target.isEmpty) continue;
    if (hasExistingTransferTo(target.first, s.toCity)) continue;
    out = insertCityTransfer(out, s.toDayNumber, s, lang: lang);
  }
  return out;
}

/// "2s 15dk" / "2h 15m" / "8+ saat" / "Yaklaşık 2-3 saat" gibi süre metninden
/// dakika çıkarır. Çözülemezse 180 dk (~3 saat) varsayar.
int _transferDurationMin(String d) {
  final l = d.toLowerCase();
  final h = RegExp(r'(\d+)[+\s]*(?:saat|sa|s|hr|h)').firstMatch(l);
  final m = RegExp(r'(\d+)\s*(?:dk|dak|min|m)\b').firstMatch(l);
  final total = (h != null ? int.parse(h.group(1)!) * 60 : 0) +
      (m != null ? int.parse(m.group(1)!) : 0);
  return total > 0 ? total : 180;
}

int cityTransferDurationMinutes(CityTransfer transfer) =>
    _transferDurationMin(transfer.duration);

String cityTransitionModeForTransfer(CityTransfer transfer) {
  final value = transfer.mode.toLowerCase();
  if (value.contains('shinkansen')) return 'shinkansen';
  if (value.contains('bus')) return 'bus';
  if (value.contains('flight') || value.contains('uçak')) return 'flight';
  if (value.contains('taxi') || value.contains('taksi')) return 'taxi';
  return 'train';
}

TimelineItem cityTransitionTimelineItem({
  required String id,
  required String fromCity,
  required String toCity,
  required String mode,
  required String time,
  required AppLang lang,
}) {
  final suggestion = suggestionForMode(
    mode,
    fromCity,
    toCity,
    0,
    0,
  );
  final transfer = suggestion.transfer;
  return TimelineItem(
    id: id,
    isCityTransition: true,
    title:
        '${transfer.emoji} $fromCity → $toCity • ${L10n.resolve(transfer.mode, lang)}',
    description: '${transfer.duration} · ${transfer.fare}',
    tips: transfer.tip == null ? null : L10n.resolve(transfer.tip!, lang),
    kind: TimelineItemKind.transport,
    time: time,
    scheduledTime: time,
    durationMin: cityTransferDurationMinutes(transfer),
    cityId: toCity,
  );
}

bool matchesCityTransitionItem(
  TimelineItem item, {
  required String fromCity,
  required String toCity,
}) {
  if (item.isCityTransition) return true;
  if (item.kind != TimelineItemKind.transport || !item.title.contains('→')) {
    return false;
  }
  final title = _normCity(item.title);
  return title.contains(_normCity(fromCity)) &&
      title.contains(_normCity(toCity));
}

bool cityTransitionProjectionMatches(DayPlan day, AppLang lang) {
  final transition = day.cityTransition;
  if (transition == null) return true;
  final projected = day.items
      .where((item) => matchesCityTransitionItem(
            item,
            fromCity: transition.fromCity,
            toCity: transition.toCity,
          ))
      .toList(growable: false);
  if (projected.length != 1 || !projected.single.isCityTransition) {
    return false;
  }
  final expected = suggestionForMode(
    transition.mode,
    transition.fromCity,
    transition.toCity,
    0,
    day.dayNumber,
  ).transfer;
  final item = projected.single;
  return item.title.contains(L10n.resolve(expected.mode, lang)) &&
      item.durationMin == cityTransferDurationMinutes(expected) &&
      item.description == '${expected.duration} · ${expected.fare}';
}

String _hhmm(int min) {
  final h = (min ~/ 60).clamp(0, 23);
  final m = min % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Ulaşım modu kimliği (picker sonucu). API stringleri sabit — enum yerine
/// String kullanıyoruz ki UI serialize/kompare basit kalsın.
const List<String> kTransportModes = [
  'shinkansen',
  'train',
  'bus',
  'taxi',
  'flight',
  'car',
];

/// Verilen ulaşım modu için jenerik bir `CityTransfer` üretir.
/// (Bilinen çift olmasa da picker'dan seçilen bir moda geçmek için kullanılır.)
CityTransfer transferForMode(String mode) {
  switch (mode) {
    case 'train':
      return const CityTransfer(
        emoji: '🚆',
        mode: 'xfer.mode.localTrain',
        duration: 'Değişken',
        fare: 'Ucuz',
        tip: 'xfer.tip.train',
      );
    case 'bus':
      return const CityTransfer(
        emoji: '🚌',
        mode: 'xfer.mode.overnightBus',
        duration: '8+ saat',
        fare: 'Ekonomik',
        tip: 'xfer.tip.bus',
      );
    case 'taxi':
      return const CityTransfer(
        emoji: '🚕',
        mode: 'viewer.transition.mode.taxi',
        duration: 'Değişken',
        fare: 'Mesafe ve trafiğe göre',
        tip: 'xfer.tip.car',
      );
    case 'flight':
      return const CityTransfer(
        emoji: '✈️',
        mode: 'viewer.transition.mode.flight',
        duration: 'Seçilen sefere göre',
        fare: 'Havayoluna göre',
      );
    case 'car':
      return const CityTransfer(
        emoji: '🚗',
        mode: 'xfer.mode.rentalCar',
        duration: 'Değişken',
        fare: 'Yakıt + kira',
        tip: 'xfer.tip.car',
      );
    case 'shinkansen':
    default:
      return const CityTransfer(
        emoji: '🚄',
        mode: 'Shinkansen Nozomi',
        duration: 'Yaklaşık 2-3 saat',
        fare: '~10-15,000 ¥',
        tip: 'xfer.tip.shinkansen',
      );
  }
}

/// Seçilen mode + şehir/gün bilgileriyle yeni bir `CityTransitionSuggestion` üretir.
CityTransitionSuggestion suggestionForMode(
  String mode,
  String fromCity,
  String toCity,
  int fromDayNumber,
  int toDayNumber,
) {
  // Shinkansen için bilinen çift varsa (Tokyo→Osaka gibi) gerçek süre/ücreti
  // koru — sadece tip'i mode ile hizala.
  if (mode == 'shinkansen' || mode == 'train') {
    final known = lookupTransfer(fromCity, toCity);
    final knownMode =
        known == null ? null : cityTransitionModeForTransfer(known);
    if (known != null && knownMode == mode) {
      return CityTransitionSuggestion(
        fromDayNumber: fromDayNumber,
        toDayNumber: toDayNumber,
        fromCity: fromCity,
        toCity: toCity,
        transfer: known,
      );
    }
  }
  if (mode == 'bus') {
    final known = lookupTransfer(fromCity, toCity);
    if (known != null) {
      final railMinutes = cityTransferDurationMinutes(known);
      // Bilinen şehir çiftinde tek ve bağlamdan kopuk "8+ saat" varsayımı
      // kullanma. Raylı referansı yalnız muhafazakâr bir şehirlerarası otobüs
      // tahmininin tabanı yap; bu kesin sefer süresi değildir.
      final busMinutes = (railMinutes * 2.5).round().clamp(60, 480);
      return CityTransitionSuggestion(
        fromDayNumber: fromDayNumber,
        toDayNumber: toDayNumber,
        fromCity: fromCity,
        toCity: toCity,
        transfer: CityTransfer(
          emoji: '🚌',
          mode: 'xfer.mode.regionalBus',
          duration: '~$busMinutes min',
          fare: 'Operatöre göre',
          tip: 'xfer.tip.regionalBus',
        ),
      );
    }
  }
  return CityTransitionSuggestion(
    fromDayNumber: fromDayNumber,
    toDayNumber: toDayNumber,
    fromCity: fromCity,
    toCity: toCity,
    transfer: transferForMode(mode),
  );
}

/// Aynı transferin bu güne zaten eklendiğini kontrol et.
bool hasExistingTransferTo(DayPlan day, String toCity) {
  final norm = _normCity(toCity);
  return day.items.any(
    (it) =>
        it.kind == TimelineItemKind.transport &&
        it.title.toLowerCase().contains('→') &&
        it.title.toLowerCase().contains(norm),
  );
}

// ---------------------------------------------------------------------------
// v3 — Bilet tipi (JR Pass) ve bagaj lojistiği farkındalığı
// ---------------------------------------------------------------------------

/// `DayPlan.cityTransition.railPass` alanını enum'a çözer. Bilinmeyen/boş
/// değer `RailPassType.none` döner — pass kısıtı yalnız açıkça beyan
/// edildiğinde uygulanır.
RailPassType railPassFromJsonValue(String? value) {
  switch ((value ?? '').trim()) {
    case 'nationalJrPass':
      return RailPassType.nationalJrPass;
    case 'regionalJrPass':
      return RailPassType.regionalJrPass;
    case 'nonJrPass':
      return RailPassType.nonJrPass;
    default:
      return RailPassType.none;
  }
}

/// Bir şehir çifti + mod için, kullanıcının bileti dikkate alınarak
/// düzeltilmiş transfer.
///
/// JR Pass sahibi Nozomi/Mizuho'ya binemez; bu durumda mod adı Hikari/Sakura
/// olarak yeniden yazılır ve süre [RailPassPolicy] çarpanıyla uzatılır.
/// Böylece geçiş satırı, gün başlığı ve rozet **aynı** kaynaktan türer.
CityTransitionSuggestion suggestionForModeWithPass(
  String mode,
  String fromCity,
  String toCity,
  int fromDayNumber,
  int toDayNumber, {
  RailPassType railPass = RailPassType.none,
  RailPassPolicy policy = const RailPassPolicy(),
  bool passCoversThisLeg = true,
}) {
  final base =
      suggestionForMode(mode, fromCity, toCity, fromDayNumber, toDayNumber);
  final transfer = base.transfer;
  final adjustment = adjustCityTransferForPass(
    modeLabel: transfer.mode,
    baseMinutes: cityTransferDurationMinutes(transfer),
    railPass: railPass,
    policy: policy,
    passCoversThisLeg: passCoversThisLeg,
  );
  if (!adjustment.isServiceChanged) return base;

  final replacement = adjustment.effectiveService!;
  return CityTransitionSuggestion(
    fromDayNumber: fromDayNumber,
    toDayNumber: toDayNumber,
    fromCity: fromCity,
    toCity: toCity,
    transfer: CityTransfer(
      emoji: transfer.emoji,
      mode: 'Shinkansen ${shinkansenServiceLabel(replacement)}',
      duration: _formatMinutes(adjustment.adjustedMinutes),
      fare: transfer.fare,
      tip: transfer.tip,
    ),
  );
}

/// Picker'a sunulacak tüm mod seçeneklerini üretir.
///
/// Seçenek listesi **motor tarafından** üretilir; UI yalnız gösterir ve seçer.
/// `isBlockedByPass` işaretli seçenek kullanıcıya gösterilir ama seçilemez —
/// "pass'im var ama neden Nozomi yok?" sorusunu sessiz bırakmamak için.
List<CityTransitionOption> cityTransitionOptionsFor({
  required String fromCity,
  required String toCity,
  RailPassType railPass = RailPassType.none,
  RailPassPolicy policy = const RailPassPolicy(),
  int departureMinutes = 9 * 60,
  TrafficRiskPolicy trafficPolicy = const TrafficRiskPolicy(),
  AppLang lang = AppLang.tr,
}) {
  final known = lookupTransfer(fromCity, toCity);
  final recommendedMode =
      known == null ? 'shinkansen' : cityTransitionModeForTransfer(known);

  final options = <CityTransitionOption>[];
  for (final mode in kTransportModes) {
    final suggestion = suggestionForMode(mode, fromCity, toCity, 0, 0);
    final transfer = suggestion.transfer;
    final baseMinutes = cityTransferDurationMinutes(transfer);
    final service = shinkansenServiceFromText(transfer.mode);

    final adjustment = adjustCityTransferForPass(
      modeLabel: transfer.mode,
      baseMinutes: baseMinutes,
      railPass: railPass,
      policy: policy,
    );

    var minutes = adjustment.adjustedMinutes;
    final disclaimers = {...adjustment.disclaimers};

    // Karayolu modlarında trafik belirsizliği çarpanı ve UI uyarısı.
    final isRoadMode = mode == 'bus' || mode == 'taxi' || mode == 'car';
    if (isRoadMode) {
      final departure =
          DateTime(2000, 1, 1).add(Duration(minutes: departureMinutes));
      final multiplier = trafficPolicy.isPeak(departure)
          ? trafficPolicy.peakMultiplier
          : trafficPolicy.offPeakMultiplier;
      minutes = (minutes * multiplier).ceil();
      disclaimers.add(TransitDisclaimer.trafficRisk);
    }

    // JR Pass + Nozomi/Mizuho: seçenek gösterilir, seçilemez.
    final blocked = !policy.allowNozomiWithSurcharge &&
        railPass.coversJrLines &&
        service != null &&
        kJrPassExcludedServices.contains(service) &&
        mode == 'shinkansen';

    options.add(CityTransitionOption(
      mode: mode,
      durationMinutes: minutes,
      serviceLabel: adjustment.effectiveService == null
          ? null
          : shinkansenServiceLabel(adjustment.effectiveService!),
      fareLabel: transfer.fare,
      isRecommended: mode == recommendedMode,
      isPassCovered: railPass.coversJrLines &&
          (mode == 'train' || (mode == 'shinkansen' && !blocked)),
      isBlockedByPass: blocked,
      hasTrafficRiskDisclaimer:
          disclaimers.contains(TransitDisclaimer.trafficRisk),
      disclaimers:
          List.unmodifiable(disclaimers.map((d) => d.name).toList()..sort()),
      emoji: transfer.emoji,
    ));
  }
  return List.unmodifiable(options);
}

/// Geçiş günü için bagaj planını çözer.
///
/// Uzun mesafe + büyük bagaj → Yamato (ertesi gün varış, o gün bagaj tamponu
/// **yok**). Erken varış → coin locker veya otele erken bırakma. Check-in
/// penceresi açıksa doğrudan otele.
LuggagePlan resolveTransitionLuggagePlan({
  required int transitionMinutes,
  required int arrivalMinutes,
  LuggageSize size = LuggageSize.none,
  int bagCount = 0,
  int nightsAtDestination = 1,
  int? originDepartureMinutes,
  bool hasHotelChange = true,
  LuggagePolicy policy = const LuggagePolicy(),
  LuggageHandlingStrategy? userForcedStrategy,
}) {
  final base = DateTime(2000, 1, 1);
  return LuggageStrategyResolver(policy: policy).resolve(LuggageContext(
    size: size,
    bagCount: bagCount,
    arrivalAtDestination: base.add(Duration(minutes: arrivalMinutes)),
    intercityTransferMinutes: transitionMinutes,
    nightsAtDestination: nightsAtDestination,
    originHotelDepartureTime: originDepartureMinutes == null
        ? null
        : base.add(Duration(minutes: originDepartureMinutes)),
    hasHotelChange: hasHotelChange,
    userForcedStrategy: userForcedStrategy,
  ));
}

/// Bagaj adımını timeline satırına çevirir.
///
/// `bypassesStationLuggageBuffer` (Yamato / bagajsız) durumunda **satır
/// üretilmez** — rotaya sahada var olmayan bir adım eklenmez.
TimelineItem? luggageHandlingTimelineItem({
  required int dayNumber,
  required LuggagePlan plan,
  required int atMinutes,
  required String cityId,
  AppLang lang = AppLang.tr,
}) {
  if (plan.bypassesStationLuggageBuffer || plan.arrivalHandlingMinutes <= 0) {
    return null;
  }
  final (emoji, titleKey, tipKey) = switch (plan.strategy) {
    LuggageHandlingStrategy.coinLocker => (
        '🔐',
        'luggage.step.coinLocker',
        'luggage.tip.coinLocker',
      ),
    LuggageHandlingStrategy.hotelEarlyDrop => (
        '🧳',
        'luggage.step.hotelEarlyDrop',
        'luggage.tip.hotelEarlyDrop',
      ),
    _ => ('🏨', 'luggage.step.hotelCheckIn', 'luggage.tip.hotelCheckIn'),
  };
  return TimelineItem(
    id: newItemId(dayNumber),
    title: '$emoji ${L10n.resolve(titleKey, lang)}',
    tips: L10n.resolve(tipKey, lang),
    kind: TimelineItemKind.hotel,
    time: _hhmm(atMinutes),
    scheduledTime: _hhmm(atMinutes),
    durationMin: plan.arrivalHandlingMinutes,
    cityId: cityId,
  );
}

/// Dakikayı `"2s 15dk"` biçimine çevirir — `_transferDurationMin` bu formatı
/// kayıpsız geri okur.
String _formatMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours <= 0) return '${rest}dk';
  if (rest == 0) return '${hours}s';
  return '${hours}s ${rest}dk';
}
