// TypeScript packages/shared/src/itineraryGenerator.ts'in Dart karşılığı.
// Kural tabanlı gün-gün plan üretici (AI gerekmez) + AI yanıtı birleştirme.

import 'dart:math';

import '../core/l10n.dart';
import 'city_places.dart';
import 'destination_profiles.dart';
import 'explore.dart';
import 'japan_suggestions.dart';
import 'route_time_bounds.dart';
import 'trip_factory.dart';
import 'types.dart';

/// Mekanın ilgi alanı puanı — her eşleşme +2.
int _interestScore(PlaceSuggestion p, List<InterestTag> interests) {
  if (interests.isEmpty) return 0;
  final name = p.name.toLowerCase();
  final cat = p.category;
  var score = 0;
  bool has(InterestTag tag) => interests.contains(tag);

  if (has(InterestTag.temples) &&
      (cat == 'culture' ||
          RegExp(r'temple|jingu|inari|todai|sensoji').hasMatch(name))) {
    score += 2;
  }
  if (has(InterestTag.traditional) && cat == 'culture') score += 2;
  if (has(InterestTag.themeParks) &&
      (cat == 'fun' || RegExp(r'disney|usj|universal').hasMatch(name))) {
    score += 2;
  }
  if (has(InterestTag.shopping) && cat == 'shopping') score += 2;
  if (has(InterestTag.food) && cat == 'food') score += 2;
  if (has(InterestTag.photography) &&
      (cat == 'fun' ||
          cat == 'nature' ||
          RegExp(r'sky|crossing|tower|skytree').hasMatch(name))) {
    score += 2;
  }
  if (has(InterestTag.anime) &&
      RegExp(r'akihabara|anime|manga|ghibli|otaku').hasMatch(name)) {
    score += 2;
  }
  if (has(InterestTag.pokemon) && RegExp(r'pokemon|pokémon').hasMatch(name)) {
    score += 2;
  }
  if (has(InterestTag.tech) &&
      RegExp(r'yodobashi|bic camera|akihabara').hasMatch(name)) {
    score += 2;
  }
  if (has(InterestTag.kids) && isKidFriendly(p)) score += 2;
  return score;
}

// Aktivite slotları — yemek saatlerine (13:00 öğle, 19:30 akşam) ve 15 dk
// tamponlarına saygı gösterecek şekilde seçildi. `plan_warnings.dart` bu
// aralıkları doğrular; buradaki değerler üretimde uyarı çıkarmaz.
const _timesRelaxed = ['10:00', '15:30'];
const _timesModerate = ['09:00', '11:00', '15:00', '17:00'];
const _timesIntense = ['09:00', '10:30', '13:30', '16:00', '18:30'];

/// Öğle yemeği için ayrılan sabit slot — hiçbir aktivite slotuyla çakışmaz,
/// 11:00-15:00 pencere içindedir.
const _kLunchTime = '13:00';

/// Bir öğeyi listeye saatine göre doğru kronolojik konumda ekler.
///
/// **Why:** Öğle yemeği eskiden sabit index 1'e ekleniyordu ve "hiçbir
/// aktivite dizisi 13:00'a çakışmaz" varsayımına dayanıyordu. Bu varsayım
/// yanlıştı: moderate tempo saatleri 09:00/11:00/15:00 olduğundan 13:00'lık
/// öğle ikinci sıraya girip listeyi 09:00 → 13:00 → 11:00 → 15:00 sırasına
/// sokuyordu; viewer öğeleri liste sırasında gösterdiği için saatler geriye
/// atlıyor görünüyordu.
void _insertChronologically(List<TimelineItem> items, TimelineItem item) {
  final target = _parseHhmm(item.time);
  if (target == null) {
    items.add(item);
    return;
  }
  for (var i = 0; i < items.length; i++) {
    final other = _parseHhmm(items[i].time);
    if (other != null && other > target) {
      items.insert(i, item);
      return;
    }
  }
  items.add(item);
}

List<String> _timesForPace(Pace pace) {
  if (pace == Pace.relaxed) return _timesRelaxed;
  if (pace == Pace.intense) return _timesIntense;
  return _timesModerate;
}

int _activitiesPerDay(Pace pace) {
  if (pace == Pace.relaxed) return 2;
  if (pace == Pace.intense) return 5;
  return 3;
}

PlaceSuggestion? _placeById(List<PlaceSuggestion> places, String id) {
  for (final p in places) {
    if (p.id == id) return p;
  }
  return null;
}

List<PlaceSuggestion> _pickPlaces(
  List<PlaceSuggestion> pool,
  int count,
  Set<String> used,
  bool kidMode,
  List<String> mustSee,
  List<InterestTag> interests,
  int maxSteps,
) {
  final mustLower = mustSee.map((m) => m.toLowerCase()).toList();
  final scored = <({PlaceSuggestion p, int score, int idx})>[];
  var idx = 0;
  for (final p in pool) {
    if (used.contains(p.id)) continue;
    var score = 0;
    final nameLower = p.name.toLowerCase();
    if (mustLower.any((m) => nameLower.contains(m) || m.contains(nameLower))) {
      score += 100;
    }
    if (kidMode && isKidFriendly(p)) score += 20;
    if (kidMode && !isKidFriendly(p)) score -= 15;
    score += _interestScore(p, interests);
    // Walking target: kullanıcının üst sınırını aşan yerleri yavaşça aşağı it.
    final steps = p.typicalSteps ?? 10000;
    if (steps > maxSteps) {
      score -= min(15, (steps - maxSteps) ~/ 1000);
    } else if (steps < maxSteps) {
      score += 3;
    }
    scored.add((p: p, score: score, idx: idx++));
  }
  // Puan azalan, eşitlikte orijinal sıra (JS stable sort davranışı).
  scored.sort((a, b) => b.score != a.score ? b.score - a.score : a.idx - b.idx);

  final out = <PlaceSuggestion>[];
  for (final e in scored) {
    if (out.length >= count) break;
    used.add(e.p.id);
    out.add(e.p);
  }
  return out;
}

TimelineItem _makeItem(
  int dayNumber,
  String time,
  PlaceSuggestion place,
  AppLang lang, {
  String? cityId,
}) =>
    TimelineItem(
      id: newItemId(dayNumber),
      time: time,
      scheduledTime: time,
      title: '${place.emoji} ${place.name}',
      description: '${place.city} · ${place.category}',
      tips: place.category == 'culture'
          ? L10n.resolve('gen.tip.cultureEarly', lang)
          : place.category == 'food'
              ? L10n.resolve('gen.tip.foodMeal', lang)
              : null,
      kind: TimelineItemKind.activity,
      cityId: cityId ?? place.city,
    );

TimelineItem _mealItem(int dayNumber, String time, String label,
        {String? cityId}) =>
    TimelineItem(
      id: newItemId(dayNumber),
      time: time,
      scheduledTime: time,
      title: '🍽️ $label',
      kind: TimelineItemKind.meal,
      cityId: cityId,
    );

DayPlan _buildFromTemplate(
  DayPlan day,
  DayTemplate template,
  List<PlaceSuggestion> places,
  Pace pace,
  AppLang lang, {
  String? cityId,
}) {
  final times = _timesForPace(pace);
  final items = <TimelineItem>[];
  var stepSum = 0;

  for (var i = 0; i < template.places.length; i++) {
    final place = _placeById(places, template.places[i]);
    if (place == null) continue;
    final time = i < times.length ? times[i] : times.last;
    items.add(_makeItem(day.dayNumber, time, place, lang, cityId: cityId));
    stepSum += place.typicalSteps ?? 8000;
  }
  if (items.isNotEmpty && times.length > 1) {
    _insertChronologically(
      items,
      _mealItem(
          day.dayNumber, _kLunchTime, L10n.resolve('gen.meal.lunchBreak', lang),
          cityId: cityId),
    );
  }

  if (items.isEmpty && template.id.contains('arrival')) {
    items.add(TimelineItem(
      id: newItemId(day.dayNumber),
      time: '15:00',
      scheduledTime: '15:00',
      title: '🛬 ${L10n.resolve('gen.arrival.checkinTitle', lang)}',
      description: L10n.resolve('gen.arrival.checkinDesc', lang),
      kind: TimelineItemKind.activity,
      cityId: cityId,
    ));
    items.add(TimelineItem(
      id: newItemId(day.dayNumber),
      time: '18:00',
      scheduledTime: '18:00',
      title: '🏪 ${L10n.resolve('gen.arrival.exploreTitle', lang)}',
      description: L10n.resolve('gen.arrival.exploreDesc', lang),
      kind: TimelineItemKind.meal,
      cityId: cityId,
    ));
    stepSum = template.stepsEstimate;
  }

  final tags = template.places
      .map((id) => _placeById(places, id)?.name)
      .whereType<String>()
      .toList();

  final paceLabel = L10n.resolve(
    pace == Pace.relaxed
        ? 'plan.pace.relaxed'
        : pace == Pace.intense
            ? 'plan.pace.intense'
            : 'plan.pace.moderate',
    lang,
  );
  final templateTheme = L10n.resolve(template.theme, lang);
  final templateLabel = L10n.resolve(template.label, lang);
  final highlights = [
    DayHighlight(
      title: templateLabel,
      body: '${template.emoji} $templateTheme — '
          '${L10n.resolve('gen.tempoLabel', lang)}: $paceLabel',
    ),
  ];

  return day.copyWith(
    theme: '${template.emoji} $templateTheme',
    tags: tags.isNotEmpty ? tags : [templateLabel],
    stepsEstimate: template.stepsEstimate != 0
        ? template.stepsEstimate
        : (stepSum != 0 ? stepSum : 10000),
    taxiRecommended:
        (template.stepsEstimate != 0 ? template.stepsEstimate : stepSum) >
            18000,
    items: items,
    highlights: highlights,
  );
}

/// Gezinin son günü — check-out → havaalanına transfer → uçuş. Saatler
/// [returnTime] verilmişse geriye doğru hesaplanır; havaalanına özel transfer
/// süresi + 2 saat check-in buffer'ı hesaba katılır.
DayPlan _buildDepartureDay(
  DayPlan day,
  String destName,
  String flag,
  AppLang lang, {
  String? returnTime,
  String? airportIata,
}) {
  final flightMin = _parseHhmm(returnTime) ?? (14 * 60);
  final atAirportMin = flightMin - _kAirportPreDepartureBufferMin;
  final transferMin = _hotelTransferMinutes(airportIata);
  final hotelDepartMin = atAirportMin - transferMin;
  final checkOutMin = hotelDepartMin - _kCheckoutBufferMin;
  int safe(int v) => v < 0 ? 0 : v;
  return day.copyWith(
    theme: '$flag ${L10n.resolve('gen.departure.theme', lang)}',
    tags: [L10n.resolve('gen.departure.tag', lang), destName],
    stepsEstimate: 6000,
    items: [
      TimelineItem(
        id: newItemId(day.dayNumber),
        time: _fmtHhmm(safe(checkOutMin)),
        scheduledTime: _fmtHhmm(safe(checkOutMin)),
        title: '🧳 ${L10n.resolve('gen.departure.checkoutTitle', lang)}',
        kind: TimelineItemKind.activity,
        cityId: destName,
        lockType: ActivityLockType.hotel,
        fixedStartTime: _fmtHhmm(safe(checkOutMin)),
        canChangeDay: false,
        canChangeTime: false,
        canReorder: false,
        canDelete: false,
        lockReason: L10n.resolve('viewer.edit.hotelLockReason', lang),
      ),
      TimelineItem(
        id: newItemId(day.dayNumber),
        time: _fmtHhmm(safe(hotelDepartMin)),
        scheduledTime: _fmtHhmm(safe(hotelDepartMin)),
        title: '🚕 ${L10n.resolve('gen.departure.transferTitle', lang)}',
        description: L10n.resolve('gen.departure.transferDesc', lang),
        kind: TimelineItemKind.transport,
        cityId: destName,
      ),
      TimelineItem(
        id: newItemId(day.dayNumber),
        time: _fmtHhmm(safe(atAirportMin)),
        scheduledTime: _fmtHhmm(safe(atAirportMin)),
        title: '🛄 ${L10n.resolve('gen.departure.atAirportTitle', lang)}',
        description: L10n.resolve('gen.departure.atAirportDesc', lang),
        kind: TimelineItemKind.transport,
        cityId: destName,
      ),
      TimelineItem(
        id: newItemId(day.dayNumber),
        time: _fmtHhmm(flightMin),
        scheduledTime: _fmtHhmm(flightMin),
        title: '✈️ ${L10n.resolve('gen.departure.flightTitle', lang)}',
        kind: TimelineItemKind.transport,
        cityId: destName,
        lockType: ActivityLockType.flight,
        fixedStartTime: _fmtHhmm(flightMin),
        canChangeDay: false,
        canChangeTime: false,
        canReorder: false,
        canDelete: false,
        lockReason: L10n.resolve('viewer.edit.flightLockReason', lang),
      ),
    ],
    highlights: [
      DayHighlight(
        title: L10n.resolve('gen.departure.highlightTitle', lang),
        body: L10n.resolve('gen.departure.highlightBody', lang),
      ),
    ],
  );
}

DayPlan _buildFromPlaces(
  DayPlan day,
  List<PlaceSuggestion> pool,
  Pace pace,
  Set<String> used,
  bool kidMode,
  List<String> mustSee,
  List<InterestTag> interests,
  int maxSteps,
  String destLabel,
  String flag,
  AppLang lang, {
  String? cityId,
}) {
  final count = _activitiesPerDay(pace);
  final picked =
      _pickPlaces(pool, count, used, kidMode, mustSee, interests, maxSteps);
  final times = _timesForPace(pace);
  final items = <TimelineItem>[];
  var stepSum = 0;

  for (var i = 0; i < picked.length; i++) {
    final time = i < times.length ? times[i] : times.last;
    items.add(_makeItem(day.dayNumber, time, picked[i], lang, cityId: cityId));
    stepSum += picked[i].typicalSteps ?? 8000;
  }

  if (picked.length >= 2 && times.length > 1) {
    _insertChronologically(
      items,
      _mealItem(
          day.dayNumber, _kLunchTime, L10n.resolve('gen.meal.lunchStop', lang),
          cityId: cityId),
    );
  }

  final themePlace = picked.isNotEmpty ? picked.first : null;
  final theme = themePlace != null
      ? '${themePlace.emoji} ${themePlace.city} — ${themePlace.name}'
      : '$flag $destLabel';

  return day.copyWith(
    theme: theme,
    tags: picked.map((p) => p.name).toList(),
    stepsEstimate: stepSum != 0 ? stepSum : 10000,
    taxiRecommended: stepSum > 18000,
    items: items,
    highlights: picked.isNotEmpty
        ? [
            DayHighlight(
              title: L10n.resolve('gen.highlight.featured', lang),
              body: picked.map((p) => p.name).join(' · '),
            ),
          ]
        : <DayHighlight>[],
  );
}

/// Şehir adını normalize eder ("Osaka (Kansai)" → "osaka").
String _normCity(String c) =>
    c.replaceAll(RegExp(r'\s*\(.*\)\s*$'), '').trim().toLowerCase();

/// Şehir adından city_places.dart kaydını (alias'larla) çözer.
CityData? _cityDataForName(String city) {
  final n = _normCity(city);
  for (final c in kCityData) {
    if (c.key == n ||
        c.label.toLowerCase() == n ||
        c.aliases.any((a) => a == n)) {
      return c;
    }
  }
  for (final c in kCityData) {
    if (c.aliases.any((a) => n.contains(a)) || n.contains(c.key)) return c;
  }
  return null;
}

/// Bir şehrin mekan havuzu: profilin popularPlaces'ından O ŞEHRE ait olanlar +
/// city_places.dart'tan zenginleştirme (Kyoto gibi az mekanlı şehirler için
/// şart — aksi halde tüm günler aynı yeri tekrarlardı).
List<PlaceSuggestion> _cityPool(DestinationProfile profile, String city) {
  final n = _normCity(city);
  final pool =
      profile.popularPlaces.where((p) => _normCity(p.city) == n).toList();
  final seen = pool.map((p) => p.name.toLowerCase()).toSet();
  final cd = _cityDataForName(city);
  if (cd != null) {
    for (final cp in cd.places) {
      if (seen.contains(cp.name.toLowerCase())) continue;
      seen.add(cp.name.toLowerCase());
      pool.add(PlaceSuggestion(
        id: cp.id,
        name: cp.name,
        city: cd.label,
        emoji: cp.emoji,
        category: 'culture',
        typicalSteps: 9000,
      ));
    }
  }
  return pool;
}

/// Gezinin ilk günü — şehre özel varış & yerleşme (şablondan bağımsız, böylece
/// başka bir şehre "Tokyo'ya varış" yazılmaz).
/// Japon havaalanından şehir merkezindeki otele ortalama transfer süresi (dk).
/// Kullanıcının seçtiği JP havaalanı IATA'sına göre kaba tahmin.
int _hotelTransferMinutes(String? iata) {
  switch ((iata ?? '').toUpperCase()) {
    case 'HND':
      return 30; // Haneda → merkez Tokyo
    case 'NRT':
      return 60; // Narita → merkez Tokyo (N'EX)
    case 'KIX':
      return 60; // Kansai → merkez Osaka (Haruka)
    case 'ITM':
      return 25; // Itami → merkez Osaka
    case 'FUK':
      return 15; // Fukuoka → merkez
    case 'NGO':
      return 45; // Chubu → merkez Nagoya
    case 'CTS':
      return 45; // Sapporo (Chitose) → merkez
    case 'OKA':
      return 20; // Naha → merkez
    default:
      return 60;
  }
}

/// Immigration + bagaj + SIM aktivasyonu vs. için havaalanı çıkışı buffer'ı.
const int _kAirportExitBufferMin = 75;

/// Uçuş öncesi havaalanında olma buffer'ı (check-in + güvenlik + boarding).
const int _kAirportPreDepartureBufferMin = 120;

/// Otelden ayrılıp havaalanına yola çıkma öncesi buffer (check-out + hazırlık).
const int _kCheckoutBufferMin = 30;

/// HH:MM → toplam dakika (00:00'dan itibaren).
int? _parseHhmm(String? hhmm) {
  if (hhmm == null || hhmm.isEmpty || !hhmm.contains(':')) return null;
  final p = hhmm.split(':');
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// Dakika → HH:MM. 0..23:59 aralığına clamp (aynı gün varsayımı).
String _fmtHhmm(int minutes) {
  final m = minutes.clamp(0, 24 * 60 - 1);
  final h = (m ~/ 60).toString().padLeft(2, '0');
  final mm = (m % 60).toString().padLeft(2, '0');
  return '$h:$mm';
}

/// Gezinin ilk günü — havaalanı → otele transfer → check-in → hafif akşam.
/// Saatler [arrivalTime] verilmişse ona göre kurulur; havaalanına özel
/// transfer süresi (_hotelTransferMinutes) hesaba katılır.
/// [arrivalTime] null ise varsayılan saatler kullanılır (13:00, 15:00, 17:00,
/// 19:30). Çok geç iniş (>20:00) ise yalnız check-in + dinlenme.
DayPlan _buildArrivalDay(
  DayPlan day,
  String city,
  String flag,
  AppLang lang, {
  String? arrivalTime,
  String? airportIata,
}) {
  final landMin = _parseHhmm(arrivalTime) ?? (13 * 60);
  final exitMin = landMin + _kAirportExitBufferMin;
  final transferMin = _hotelTransferMinutes(airportIata);
  final atHotelMin = exitMin + transferMin;
  final checkInMin = atHotelMin + 30;
  final dinnerMin = (checkInMin + 3 * 60)
      .clamp(19 * 60, kRouteEndMinuteOfDay)
      .toInt();
  final isLateArrival = landMin >= 20 * 60;

  return _buildArrivalDayLegacy(day, city, flag, lang, landMin, atHotelMin,
      checkInMin, dinnerMin, isLateArrival);
}

DayPlan _buildArrivalDayLegacy(
  DayPlan day,
  String city,
  String flag,
  AppLang lang,
  int landMin,
  int atHotelMin,
  int checkInMin,
  int dinnerMin,
  bool isLateArrival,
) =>
    day.copyWith(
      theme:
          '🛬 ${L10n.parametrize(L10n.resolve('gen.arrival.cityTheme', lang), {
            'city': city
          })}',
      tags: [city, L10n.resolve('gen.arrival.checkinTitle', lang)],
      stepsEstimate: 4000,
      taxiRecommended: false,
      items: [
        TimelineItem(
          id: newItemId(day.dayNumber),
          time: _fmtHhmm(landMin),
          scheduledTime: _fmtHhmm(landMin),
          title: '🛬 ${L10n.resolve('gen.arrival.airportTitle', lang)}',
          description: L10n.resolve('gen.arrival.airportDesc', lang),
          kind: TimelineItemKind.transport,
          cityId: city,
          lockType: ActivityLockType.flight,
          fixedStartTime: _fmtHhmm(landMin),
          canChangeDay: false,
          canChangeTime: false,
          canReorder: false,
          canDelete: false,
          lockReason: L10n.resolve('viewer.edit.flightLockReason', lang),
        ),
        TimelineItem(
          id: newItemId(day.dayNumber),
          time: _fmtHhmm(landMin + _kAirportExitBufferMin),
          scheduledTime: _fmtHhmm(landMin + _kAirportExitBufferMin),
          title: '🚕 ${L10n.resolve('gen.arrival.transferTitle', lang)}',
          description: L10n.resolve('gen.arrival.transferDesc', lang),
          kind: TimelineItemKind.transport,
          cityId: city,
        ),
        TimelineItem(
          id: newItemId(day.dayNumber),
          time: _fmtHhmm(checkInMin),
          scheduledTime: _fmtHhmm(checkInMin),
          title: '🏨 ${L10n.resolve('gen.arrival.checkinTitle', lang)}',
          description: L10n.resolve('gen.arrival.checkinDesc', lang),
          kind: TimelineItemKind.hotel,
          cityId: city,
          lockType: ActivityLockType.hotel,
          fixedStartTime: _fmtHhmm(checkInMin),
          canChangeDay: false,
          canChangeTime: false,
          canReorder: false,
          canDelete: false,
          lockReason: L10n.resolve('viewer.edit.hotelLockReason', lang),
        ),
        // Çok geç iniş → sadece uyu. Aksi halde hafif akşam yemeği.
        if (!isLateArrival)
          TimelineItem(
            id: newItemId(day.dayNumber),
            time: _fmtHhmm(dinnerMin),
            scheduledTime: _fmtHhmm(dinnerMin),
            title: '🍜 ${L10n.resolve('gen.arrival.lightDinnerTitle', lang)}',
            description: L10n.resolve('gen.arrival.lightDinnerDesc', lang),
            kind: TimelineItemKind.meal,
            cityId: city,
          ),
      ],
      highlights: const [],
    );

/// Full/half-day coverage'lı bir mekan varsa günü uygun kalıba oturtur.
/// - FULL (Disney, USJ): sadece bu mekan + 13:00 park içi öğle + 20:00 çıkışta
///   akşam yemeği. Diğer aktiviteler kaldırılır. adım ~22k, taksi önerilir.
/// - HALF (teamLab): 10:00 sabah gezisi (varsa) + 12:30 öğle + 14:00 bu mekan.
///   İki aktiviteyle sınırlı; ekstra doldurma yok.
DayPlan _applyCoverage(DayPlan day, AppLang lang) {
  final items = day.items;
  if (items.isEmpty) return day;

  final fullItem = items.firstWhere(
    (it) => coverageOfTitle(it.title) == PlaceCoverage.full,
    orElse: () => TimelineItem(id: '', title: ''),
  );
  if (fullItem.id.isNotEmpty) {
    final f = TimelineItem(
      id: fullItem.id,
      title: fullItem.title,
      description: fullItem.description,
      tips: fullItem.tips,
      kind: fullItem.kind,
      cityId: fullItem.cityId,
      time: '09:00',
      scheduledTime: '09:00',
    );
    return day.copyWith(
      theme: fullItem.title, // ör. "🏰 Tokyo Disneyland"
      tags: [fullItem.title.replaceAll(RegExp(r'^[^\s]+\s*'), '')],
      stepsEstimate: 22000,
      taxiRecommended: true,
      items: [
        f,
        TimelineItem(
          id: newItemId(day.dayNumber),
          time: '13:00',
          scheduledTime: '13:00',
          title: '🍽️ ${L10n.resolve('gen.coverage.parkLunch', lang)}',
          description: L10n.resolve('gen.coverage.parkLunchDesc', lang),
          kind: TimelineItemKind.meal,
          cityId: fullItem.cityId,
        ),
        TimelineItem(
          id: newItemId(day.dayNumber),
          time: '20:00',
          scheduledTime: '20:00',
          title: '🍜 ${L10n.resolve('gen.coverage.postDinner', lang)}',
          description: L10n.resolve('gen.coverage.postDinnerDesc', lang),
          kind: TimelineItemKind.meal,
          cityId: fullItem.cityId,
        ),
      ],
    );
  }

  final halfItem = items.firstWhere(
    (it) => coverageOfTitle(it.title) == PlaceCoverage.half,
    orElse: () => TimelineItem(id: '', title: ''),
  );
  if (halfItem.id.isNotEmpty) {
    // Yarım günü öğleden sonraya al; sabaha hafif bir aktivite (varsa).
    TimelineItem? morning;
    for (final it in items) {
      if (identical(it, halfItem)) continue;
      if (it.kind == TimelineItemKind.activity &&
          coverageOfTitle(it.title) == PlaceCoverage.normal) {
        morning = TimelineItem(
          id: it.id,
          title: it.title,
          description: it.description,
          tips: it.tips,
          kind: it.kind,
          cityId: it.cityId,
          time: '10:00',
          scheduledTime: '10:00',
        );
        break;
      }
    }
    final h = TimelineItem(
      id: halfItem.id,
      title: halfItem.title,
      description: halfItem.description,
      tips: halfItem.tips,
      kind: halfItem.kind,
      cityId: halfItem.cityId,
      time: '14:00',
      scheduledTime: '14:00',
    );
    return day.copyWith(
      theme: halfItem.title,
      tags: [halfItem.title.replaceAll(RegExp(r'^[^\s]+\s*'), '')],
      stepsEstimate: 11000,
      taxiRecommended: false,
      items: [
        if (morning != null)
          morning
        else
          TimelineItem(
            id: newItemId(day.dayNumber),
            time: '10:00',
            scheduledTime: '10:00',
            title: '🚶 ${L10n.resolve('gen.coverage.halfMorning', lang)}',
            description: L10n.resolve('gen.coverage.halfMorningDesc', lang),
            kind: TimelineItemKind.activity,
            cityId: halfItem.cityId,
          ),
        TimelineItem(
          id: newItemId(day.dayNumber),
          time: '12:30',
          scheduledTime: '12:30',
          title: '🍽️ ${L10n.resolve('gen.meal.lunchBreak', lang)}',
          kind: TimelineItemKind.meal,
          cityId: halfItem.cityId,
        ),
        h,
      ],
    );
  }

  return day;
}

/// Rota, tempo ve ülke profillerine göre gün-gün plan üretir (AI gerekmez).
/// [lang] üretilen gün temaları, öğün/aktivite başlıkları ve ipuçlarının dilini
/// belirler; içerik seçili dilde trip'e yazılır (sonradan dil değişimi mevcut
/// planı yeniden çevirmez).
List<DayPlan> generateItineraryFromTrip(Trip trip,
    {AppLang lang = AppLang.tr}) {
  final pace = trip.preferences.pace;
  final childCount = trip.preferences.childProfiles.isNotEmpty
      ? trip.preferences.childProfiles.length
      : (trip.preferences.childrenCount ?? 0);
  final kidMode = childCount > 0;
  final mustSee = trip.preferences.mustSee;
  final interests = trip.preferences.interests;
  final maxSteps = trip.preferences.maxStepsPerDay ?? 11000;
  final destinations = [...trip.preferences.destinations]
    ..sort((a, b) => a.order.compareTo(b.order));
  final usedPlaces = <String>{};
  final firstDestId = destinations.isNotEmpty ? destinations.first.id : null;
  final lastDestId = destinations.isNotEmpty ? destinations.last.id : null;

  return trip.days.map((day) {
    final dest = getDestinationForDate(destinations, day.date);
    if (dest == null) return day;

    final profile = getDestinationProfile(dest.countryCode);
    if (profile == null) return day;

    final rawCity = dest.city.isNotEmpty ? dest.city : profile.name;
    final city = rawCity.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
    final flag = profile.flag;

    final segDays = trip.days.where((d) {
      final dd = getDestinationForDate(destinations, d.date);
      return dd?.id == dest.id;
    }).toList();
    final dayIndexInSeg =
        segDays.indexWhere((d) => d.dayNumber == day.dayNumber);
    final isFirstOfSeg = dayIndexInSeg == 0;
    final isLastOfSeg = dayIndexInSeg == segDays.length - 1;
    final isFirstDest = dest.id == firstDestId;
    final isLastDest = dest.id == lastDestId;

    // Gezinin ilk günü → şehre özel varış (yalnızca İLK destinasyonda).
    // Uçuş saatleri (varsa) varış günü akışını belirler.
    if (isFirstOfSeg && isFirstDest) {
      return _buildArrivalDay(
        day,
        city,
        flag,
        lang,
        arrivalTime: trip.preferences.outboundArrivalTime,
        airportIata: dest.airport,
      );
    }
    // Gezinin son günü → dönüş uçuşu (yalnızca SON destinasyonda). Ara
    // şehirlerin son günü normal gündür; şehirler-arası geçiş (Shinkansen)
    // ayrıca eklenir (detectCityTransitions + insertCityTransfer).
    if (isLastOfSeg && isLastDest && trip.days.length > 1) {
      final returnAirport =
          (trip.preferences.returnDepartAirport ?? '').isNotEmpty
          ? trip.preferences.returnDepartAirport
          : dest.airport;
      return _buildDepartureDay(
        day,
        city,
        flag,
        lang,
        returnTime: trip.preferences.returnDepartTime,
        airportIata: returnAirport,
      );
    }

    // Şehre özel içerik — havuz ve şablonlar O şehre filtrelenir; böylece
    // Kyoto gününe Tokyo mekanı gelmez.
    final cityPool = _cityPool(profile, city);
    final cityTemplates = profile.dayTemplates
        .where((t) =>
            _normCity(t.city) == _normCity(city) && !t.id.contains('arrival'))
        .toList();

    // Kullanıcı bu şehirde "gezilecekler" listesinden yer seçtiyse (mustSee),
    // TEMPLATE rotasyonunu atla — _buildFromPlaces mustSee'yi +100 puanla
    // önceliklendirir, diğer günler pool'daki diğer yerlerle otomatik dolar.
    final cityHasMustSee = mustSee.any((m) {
      final ml = m.trim().toLowerCase();
      if (ml.isEmpty) return false;
      return cityPool.any((p) => p.name.toLowerCase() == ml);
    });

    if (cityTemplates.isNotEmpty && !cityHasMustSee) {
      // İlk destinasyonda 0. gün varıştı → şablon sırasını 1 kaydır.
      final seq = isFirstDest ? (dayIndexInSeg - 1) : dayIndexInSeg;
      final idx = (seq < 0 ? 0 : seq) % cityTemplates.length;
      final template = cityTemplates[idx];
      final built =
          _buildFromTemplate(day, template, cityPool, pace, lang, cityId: city);
      usedPlaces.addAll(template.places);
      // Full/half-day mekanları uygun kalıba oturt (Disney/USJ tüm gün,
      // teamLab yarım gün).
      return _applyCoverage(built, lang);
    }

    final built = _buildFromPlaces(
      day,
      cityPool,
      pace,
      usedPlaces,
      kidMode,
      mustSee,
      interests,
      maxSteps,
      city,
      flag,
      lang,
      cityId: city,
    );
    return _applyCoverage(built, lang);
  }).toList();
}

// ---------------------------------------------------------------------------
// AI yanıtı birleştirme (mergeAiItinerary)
// ---------------------------------------------------------------------------

class AiItineraryItem {
  AiItineraryItem({
    this.time,
    required this.title,
    this.description,
    this.tips,
    this.kind,
    this.durationMin,
    this.cost,
    this.costCurrency,
    this.mapUrl,
    this.lat,
    this.lng,
  });

  final String? time;
  final String title;
  final String? description;
  final String? tips;
  final String? kind;
  final int? durationMin;
  final int? cost;
  final String? costCurrency;
  final String? mapUrl;
  final double? lat;
  final double? lng;

  factory AiItineraryItem.fromJson(Map<String, dynamic> j) => AiItineraryItem(
        time: j['time'] as String?,
        title: (j['title'] as String?) ?? '',
        description: j['description'] as String?,
        tips: j['tips'] as String?,
        kind: j['kind'] as String?,
        durationMin: (j['durationMin'] as num?)?.toInt(),
        cost: (j['cost'] as num?)?.toInt(),
        costCurrency: j['costCurrency'] as String?,
        mapUrl: j['mapUrl'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
      );
}

class AiItineraryDay {
  AiItineraryDay({
    required this.dayNumber,
    this.theme,
    this.tags,
    this.stepsEstimate,
    this.highlights,
    this.items,
  });

  final int dayNumber;
  final String? theme;
  final List<String>? tags;
  final int? stepsEstimate;
  final List<DayHighlight>? highlights;
  final List<AiItineraryItem>? items;

  factory AiItineraryDay.fromJson(Map<String, dynamic> j) => AiItineraryDay(
        dayNumber: (j['dayNumber'] as num).toInt(),
        theme: j['theme'] as String?,
        tags: (j['tags'] as List?)?.cast<String>(),
        stepsEstimate: (j['stepsEstimate'] as num?)?.toInt(),
        highlights: (j['highlights'] as List?)
            ?.map((e) => DayHighlight.fromJson((e as Map).cast()))
            .toList(),
        items: (j['items'] as List?)
            ?.map((e) => AiItineraryItem.fromJson((e as Map).cast()))
            .toList(),
      );
}

TimelineItemKind normalizeKind(dynamic raw) {
  if (raw is! String) return TimelineItemKind.activity;
  final k = raw.toLowerCase();
  switch (k) {
    case 'activity':
      return TimelineItemKind.activity;
    case 'transport':
      return TimelineItemKind.transport;
    case 'meal':
      return TimelineItemKind.meal;
    case 'hotel':
      return TimelineItemKind.hotel;
    case 'arrival':
    case 'departure':
    case 'flight':
    case 'train':
    case 'taxi':
    case 'bus':
    case 'walk':
      return TimelineItemKind.transport;
    case 'food':
    case 'restaurant':
    case 'breakfast':
    case 'lunch':
    case 'dinner':
    case 'cafe':
      return TimelineItemKind.meal;
    case 'checkin':
    case 'check-in':
    case 'checkout':
    case 'check-out':
    case 'lodging':
      return TimelineItemKind.hotel;
    default:
      return TimelineItemKind.activity;
  }
}

/// AI yanıtını mevcut gün iskeletine (tarih, weekday) uygular.
List<DayPlan> mergeAiItinerary(
  List<DayPlan> baseDays,
  List<AiItineraryDay> aiDays,
) {
  final byNum = {for (final d in aiDays) d.dayNumber: d};
  return baseDays.map((day) {
    final ai = byNum[day.dayNumber];
    if (ai == null) return day;
    final items = <TimelineItem>[];
    final aiItems = ai.items ?? const <AiItineraryItem>[];
    for (var idx = 0; idx < aiItems.length; idx++) {
      final it = aiItems[idx];
      items.add(TimelineItem(
        id: '${newItemId(day.dayNumber)}-$idx',
        time: it.time,
        scheduledTime: it.time,
        title: it.title,
        description: it.description,
        tips: it.tips,
        kind: normalizeKind(it.kind),
        durationMin: it.durationMin,
        cost: it.cost,
        costCurrency: it.costCurrency,
        mapUrl: it.mapUrl,
        lat: it.lat,
        lng: it.lng,
      ));
    }
    return day.copyWith(
      theme: ai.theme ?? day.theme,
      tags: ai.tags ?? day.tags,
      stepsEstimate: ai.stepsEstimate ?? day.stepsEstimate,
      highlights: ai.highlights ?? day.highlights,
      items: items,
      taxiRecommended: (ai.stepsEstimate ?? day.stepsEstimate ?? 0) > 18000,
    );
  }).toList();
}
