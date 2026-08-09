// TypeScript packages/shared/src/tripFactory.ts + route.ts +
// destinations/tripDestinations.ts (sync akışı) Dart karşılığı.

import 'dart:math';

import 'destination_profiles.dart';
import 'dietary.dart';
import 'types.dart';

final Random _rand = Random();

/// Basit slug üretici — timestamp base-36.
String _slug() =>
    'yeni-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

/// UUID benzeri (tam RFC4122 değil ama JSON DB'de yeterli).
String _uuid() {
  final r = Random.secure();
  String h(int n) =>
      List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  return '${h(8)}-${h(4)}-${h(4)}-${h(4)}-${h(12)}';
}

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _addDays(DateTime d, int days) => d.add(Duration(days: days));

const _trWeekdays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

/// start..end (dahil) arası her gün için boş DayPlan üretir.
/// React syncTripFromDestinations'ın gün üretimi karşılığı.
List<DayPlan> generateDaysBetween(String startYmd, String endYmd) {
  if (startYmd.isEmpty || endYmd.isEmpty) return [];
  final start = DateTime.tryParse(startYmd);
  final end = DateTime.tryParse(endYmd);
  if (start == null || end == null || end.isBefore(start)) return [];
  final days = <DayPlan>[];
  var cur = start;
  var n = 1;
  while (!cur.isAfter(end) && n <= kMaxTripDays) {
    days.add(DayPlan(
      dayNumber: n,
      date: _ymd(cur),
      weekday: _trWeekdays[cur.weekday - 1],
      theme: '',
      tags: [],
      items: [],
    ));
    cur = _addDays(cur, 1);
    n++;
  }
  return days;
}

/// Destinasyonlara tarih aralığını eşit dağıtır (pure, mutasyon: arrival+departure).
///
/// Toplam gün = daysBetween(start, end) + 1.
/// - slice = max(1, totalDays ÷ destCount)  (tam bölüm)
/// - remainder = totalDays - slice * destCount → son destinasyona eklenir
/// - dest[i].arrivalDate = start + Σ(önceki slice'lar)
/// - dest[i].departureDate = dest[i+1].arrivalDate (son için end)
///
/// Kullanıcı elle tarih düzenlediyse (heuristik: hepsi identik start değil)
/// çağıran taraf bu fonksiyonu skip etmeli. Fonksiyonun kendisi always dağıtır.
List<TripDestination> distributeDates(
  List<TripDestination> sorted,
  String start,
  String end,
) {
  if (sorted.isEmpty || start.isEmpty || end.isEmpty) return sorted;
  final s = DateTime.tryParse(start);
  final e = DateTime.tryParse(end);
  if (s == null || e == null || e.isBefore(s)) return sorted;
  final totalDays = e.difference(s).inDays + 1;
  final count = sorted.length;
  final rawSlice = totalDays ~/ count;
  final slice = rawSlice < 1 ? 1 : rawSlice;
  var remainder = totalDays - slice * count;
  if (remainder < 0) remainder = 0;

  var cursor = 0;
  for (var i = 0; i < count; i++) {
    final isLast = i == count - 1;
    final thisSlice = slice + (isLast ? remainder : 0);
    final arrival = _addDays(s, cursor);
    sorted[i].arrivalDate = _ymd(arrival);
    cursor += thisSlice;
    final depDate = isLast ? e : _addDays(s, cursor);
    sorted[i].departureDate = _ymd(depDate);
  }
  return sorted;
}

/// 7 günlük boş Trip, tarih bugünden 14 gün sonra başlar.
Trip createEmptyTrip({Trip? overrides}) {
  final now = DateTime.now();
  final start = _addDays(now, 14);
  final end = _addDays(start, 6);
  final startStr = _ymd(start);
  final endStr = _ymd(end);

  return Trip(
    id: _uuid(),
    slug: _slug(),
    title: 'Japonya Turu',
    subtitle: '',
    timezone: 'Asia/Tokyo',
    tripStart: '${startStr}T08:00:00',
    tripEnd: '${endStr}T20:00:00',
    flights: TripFlights(
      outbound: [
        FlightLeg(city: '', airport: '', dateTime: '${startStr}T10:00:00'),
        FlightLeg(city: '', airport: '', dateTime: '${startStr}T18:00:00'),
      ],
      returnLegs: [
        FlightLeg(city: '', airport: '', dateTime: '${endStr}T10:00:00'),
        FlightLeg(city: '', airport: '', dateTime: '${endStr}T20:00:00'),
      ],
    ),
    hotels: [],
    tickets: [],
    preferences: TripPreferences(
      travelDates: TravelDates(start: startStr, end: endStr),
      destinationCountry: 'JP',
      pace: Pace.moderate,
      partySize: 2,
      maxStepsPerDay: kWalkingTargetSteps[WalkingTarget.moderate],
      planMeals: true,
      mealBudgetPerPerson: 2500,
      mealBudgetCurrency: 'JPY',
      walkingTarget: WalkingTarget.moderate,
      transportPreference: TransportPreference.mixed,
      paymentPreference: PaymentPreference.creditAndCash,
    ),
    days: generateDaysBetween(startStr, endStr),
    deadlines: Deadlines(),
  );
}

bool isTransportTicket(String kind) =>
    const ['flight', 'train', 'bus', 'ferry'].contains(kind);

/// Eski verileri yeni alanlarla doldurur. Mevcut alanları korur,
/// eksik olanları varsayılanlarla tamamlar. Strict reject yok — geri uyumlu.
Trip ensureTripPreferences(Trip trip) {
  final p = trip.preferences;
  final walkingTarget = p.walkingTarget ?? WalkingTarget.moderate;
  final sensitivityTags = dietaryTagsFromSensitivities(p.foodSensitivities);
  final mergedDietaryTags = <String>{...p.dietaryTags, ...sensitivityTags};

  p
    ..walkingTarget = walkingTarget
    ..transportPreference = p.transportPreference ?? TransportPreference.mixed
    ..paymentPreference = p.paymentPreference ?? PaymentPreference.creditAndCash
    ..dietaryTags = mergedDietaryTags.toList()
    ..maxStepsPerDay = p.maxStepsPerDay ?? kWalkingTargetSteps[walkingTarget]
    ..childrenCount = p.childProfiles.isNotEmpty
        ? p.childProfiles.length
        : (p.childrenCount ?? 0);
  return trip;
}

String newId(String prefix) =>
    '$prefix-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

String newHotelId() => newId('hotel');

String newTicketId() =>
    'ticket-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

int _itemSeq = 0;

String newItemId(int dayNumber) {
  _itemSeq = (_itemSeq + 1) % 1000000;
  final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final t = ts.substring(ts.length - 4);
  final s = _itemSeq.toRadixString(36);
  final r = List.generate(3, (_) => _rand.nextInt(36).toRadixString(36)).join();
  return 'd$dayNumber-i$t$s$r';
}

const List<String> _activityTimeSlots = [
  '09:30',
  '11:00',
  '13:00',
  '14:30',
  '16:00',
  '17:30',
  '19:00',
];

/// Bu güne yeni bir aktivite için en uygun saat slot'unu seçer.
/// Mevcut item'ların saatlerini dikkate alır; dolu slot'ları atlar.
String _nextTimeSlot(DayPlan day) {
  final used = <String>{};
  for (final it in day.items) {
    final t = it.scheduledTime ?? it.time;
    if (t != null) used.add(t);
  }
  for (final slot in _activityTimeSlots) {
    if (!used.contains(slot)) return slot;
  }
  // Tüm slot'lar dolduysa 30 dakika ekleyerek devam et
  final last = _activityTimeSlots.last;
  final parts = last.split(':');
  final total = int.parse(parts[0]) * 60 +
      int.parse(parts[1]) +
      30 * (day.items.length - _activityTimeSlots.length + 1);
  final hh = min(23, total ~/ 60);
  final mm = total % 60;
  return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
}

/// Basit "mekan ekle" girdi kaydı.
class PlaceToAdd {
  const PlaceToAdd({required this.name, this.emoji, this.steps, this.city});
  final String name;
  final String? emoji;
  final int? steps;
  final String? city;
}

List<DayPlan> addPlaceToDay(
  List<DayPlan> days,
  int dayNumber,
  PlaceToAdd place,
) {
  return days.map((d) {
    if (d.dayNumber != dayNumber) return d;
    final time = _nextTimeSlot(d);
    final item = TimelineItem(
      id: newItemId(dayNumber),
      title: '${place.emoji ?? '📍'} ${place.name}',
      kind: TimelineItemKind.activity,
      time: time,
      scheduledTime: time,
      cityId: place.city,
    );
    final tags =
        d.tags.contains(place.name) ? d.tags : [...d.tags, place.name];
    return d.copyWith(
      tags: tags,
      theme: d.theme == 'Gün $dayNumber' ? place.name : d.theme,
      stepsEstimate: (d.stepsEstimate ?? 0) + (place.steps ?? 3000),
      items: [...d.items, item],
    );
  }).toList();
}

/// Belirli bir destinasyona ait günler arasından,
/// yeni bir aktivite için en uygun olanı seçer.
/// Sıralama: en az aktivite sayısı → en düşük adım tahmini → en erken gün.
int? pickBestDayForDestination(
  List<DayPlan> days,
  List<int> destinationDayNumbers,
) {
  if (destinationDayNumbers.isEmpty) return null;
  final candidates = days
      .where((d) => destinationDayNumbers.contains(d.dayNumber))
      .toList()
    ..sort((a, b) {
      int actCount(DayPlan d) => d.items
          .where(
              (it) => it.kind == TimelineItemKind.activity || it.kind == null)
          .length;
      final aAct = actCount(a);
      final bAct = actCount(b);
      if (aAct != bAct) return aAct - bAct;
      final aSteps = a.stepsEstimate ?? 0;
      final bSteps = b.stepsEstimate ?? 0;
      if (aSteps != bSteps) return aSteps - bSteps;
      return a.dayNumber - b.dayNumber;
    });
  return candidates.isNotEmpty ? candidates.first.dayNumber : null;
}

/// applyDayTemplate girdi şablonu (tema + mekan listesi).
class DayTemplateInput {
  const DayTemplateInput({
    required this.theme,
    required this.emoji,
    required this.places,
    required this.stepsEstimate,
  });
  final String theme;
  final String emoji;
  final List<PlaceToAdd> places;
  final int stepsEstimate;
}

List<DayPlan> applyDayTemplate(
  List<DayPlan> days,
  int dayNumber,
  DayTemplateInput template,
) {
  var next = days
      .map((d) => d.dayNumber == dayNumber
          ? d.copyWith(
              theme: '${template.emoji} ${template.theme}',
              stepsEstimate: template.stepsEstimate,
              taxiRecommended: template.stepsEstimate > 18000,
            )
          : d)
      .toList();
  for (final p in template.places) {
    next = addPlaceToDay(next, dayNumber, p);
  }
  return next;
}

// ---------------------------------------------------------------------------
// Destinasyon senkronizasyonu (TS: destinations/tripDestinations.ts + route.ts)
// ---------------------------------------------------------------------------

int _destSeq = 0;

/// Destinasyon id'si — ÇAKIŞMASIZ olmak zorunda.
///
/// Eski hâli yalnızca `millisecondsSinceEpoch` kullanıyordu; bir döngüde
/// arka arkaya üretilen destinasyonlar AYNI id'yi alıyordu. Bu, id'ye anahtar
/// olarak güvenen her yeri (gün→şehir kapsama sayımı, _cityColor, dedup)
/// sessizce bozuyordu. newItemId ile aynı desen: zaman + sıra + rastgele.
String newDestinationId() {
  _destSeq = (_destSeq + 1) % 1000000;
  final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final r = List.generate(3, (_) => _rand.nextInt(36).toRadixString(36)).join();
  return 'dest-$ts-${_destSeq.toRadixString(36)}$r';
}

DestinationFoodPrefs defaultFoodPrefsForDestination(TripDestination dest) {
  final profile = getDestinationProfile(dest.countryCode);
  return DestinationFoodPrefs(
    destinationId: dest.id,
    dietaryTags: [],
    foodLikes: [],
    foodDislikes: [],
    mealBudgetPerPerson: profile?.code == 'JP'
        ? 2500
        : profile?.code == 'KR'
            ? 15000
            : 50,
    mealBudgetCurrency: profile?.defaultCurrency ?? 'EUR',
  );
}

String buildTripTitleFromDestinations(
  String originCity,
  List<TripDestination> destinations,
) {
  final sorted = [...destinations]..sort((a, b) => a.order.compareTo(b.order));
  final allJapan =
      sorted.isNotEmpty && sorted.every((d) => d.countryCode == 'JP');
  if (allJapan) return 'Japonya Turu';
  final stops = sorted
      .map((d) => d.city.isNotEmpty ? d.city : d.countryName)
      .where((s) => s.isNotEmpty)
      .toList();
  if (originCity.isEmpty && stops.isEmpty) return 'Japonya Turu';
  if (stops.isEmpty) return originCity;
  if (originCity.isEmpty) return stops.join(' → ');
  return '$originCity → ${stops.join(' → ')} → $originCity';
}

/// Kalkış → duraklar → eve dönüş uçuş zinciri. (TS: route.ts → buildRouteLegs)
List<FlightLeg> buildRouteLegs(
  String originCity,
  String originAirport,
  List<TripDestination> destinations,
  String travelStart,
  String travelEnd,
) {
  final sorted = [...destinations]..sort((a, b) => a.order.compareTo(b.order));
  if (originCity.trim().isEmpty && sorted.isEmpty) return [];

  final legs = <FlightLeg>[
    FlightLeg(
      city: originCity,
      airport: originAirport,
      dateTime: '${travelStart}T10:00:00',
    ),
  ];

  for (final dest in sorted) {
    if (dest.city.trim().isEmpty && dest.countryName.trim().isEmpty) continue;
    legs.add(FlightLeg(
      city: dest.city.isNotEmpty ? dest.city : dest.countryName,
      airport: dest.airport ?? '',
      dateTime: '${dest.arrivalDate}T14:00:00',
    ));
  }

  if (originCity.trim().isNotEmpty &&
      sorted.any(
          (d) => d.city.trim().isNotEmpty || d.countryName.trim().isNotEmpty)) {
    legs.add(FlightLeg(
      city: originCity,
      airport: originAirport,
      dateTime: '${travelEnd}T20:00:00',
    ));
  }

  return legs;
}

const List<String> _flagPrefixes = [
  '🇯🇵', '🇰🇷', '🇹🇼', '🇬🇧', '🇫🇷', '🇮🇹', '🇩🇪', '🇪🇸', '🇺🇸', '🇹🇷', //
];

/// Destinasyon listesi + tarih aralığından Trip'i yeniden kurar.
/// Mevcut günlerin item/theme/highlight içeriği dayNumber'a göre korunur —
/// kullanıcı bir paket yükledikten sonra uçuş tarihlerini değiştirdiğinde
/// küratörlü içerik kaybolmasın; sadece tarih+weekday yeni aralığa kayar.
Trip syncTripFromDestinations(
  Trip trip, {
  required String originCity,
  String? originAirport,
  double? originLat,
  double? originLng,
  required List<TripDestination> destinations,
  required List<DestinationFoodPrefs> destinationFood,
  required String travelStart,
  required String travelEnd,
}) {
  final sorted = [...destinations]..sort((a, b) => a.order.compareTo(b.order));
  final first = sorted.isNotEmpty ? sorted.first : null;
  final last = sorted.isNotEmpty ? sorted.last : null;

  final previousByDayNumber = {
    for (final d in trip.days) d.dayNumber: d,
  };

  final days = generateDaysBetween(travelStart, travelEnd).map((day) {
    final dest = getDestinationForDate(sorted, day.date);
    final previous = previousByDayNumber[day.dayNumber];
    final defaultTheme = 'Gün ${day.dayNumber}';
    final baseTags = (previous != null && previous.tags.isNotEmpty)
        ? previous.tags
        : day.tags;
    final prevTheme = previous?.theme ?? '';
    final baseTheme = (prevTheme.isNotEmpty && prevTheme != defaultTheme)
        ? prevTheme
        : day.theme;

    day
      ..items = previous?.items ?? day.items
      ..stepsEstimate = previous?.stepsEstimate ?? day.stepsEstimate
      ..stepsEstimateMax = previous?.stepsEstimateMax
      ..taxiRecommended = previous?.taxiRecommended
      ..routeMapsUrl = previous?.routeMapsUrl
      ..highlights = previous?.highlights ?? day.highlights
      ..tags = dest != null
          ? [
              '${getDestinationProfile(dest.countryCode)?.flag ?? ''} ${dest.countryName}'
                  .trim(),
              ...baseTags
                  .where((t) => !_flagPrefixes.any((f) => t.startsWith(f))),
            ]
          : baseTags
      ..theme = (dest != null &&
              (baseTheme.isEmpty || baseTheme == defaultTheme))
          ? '${dest.city.isNotEmpty ? dest.city : dest.countryName} — Gün ${day.dayNumber}'
          : baseTheme;
    return day;
  }).toList();

  final title = buildTripTitleFromDestinations(originCity, sorted);

  final resolvedOriginAirport = originAirport ??
      (trip.flights.outbound.isNotEmpty
          ? trip.flights.outbound.first.airport
          : '');
  final legs = buildRouteLegs(
    originCity,
    resolvedOriginAirport,
    sorted,
    travelStart,
    travelEnd,
  );

  final outbound = legs.length >= 2
      ? [legs[0], legs[1]]
      : legs.isNotEmpty
          ? [legs[0]]
          : <FlightLeg>[];
  final returnLegs = legs.length >= 2
      ? [legs[legs.length - 2], legs[legs.length - 1]]
      : <FlightLeg>[];

  final countryCodes = <String>{
    for (final d in sorted)
      if (d.countryCode.isNotEmpty) d.countryCode,
  }.toList();

  final prefs = trip.preferences
    ..originCity = originCity
    ..originAirport = resolvedOriginAirport.isNotEmpty
        ? resolvedOriginAirport
        : trip.preferences.originAirport
    ..originLat = originLat ?? trip.preferences.originLat
    ..originLng = originLng ?? trip.preferences.originLng
    ..destinationCity = last?.city ?? first?.city ?? ''
    ..destinationCountry = countryCodes.length == 1
        ? countryCodes.first
        : countryCodes.join(',')
    ..destinations = sorted
    ..destinationFood = destinationFood
    ..travelDates = TravelDates(start: travelStart, end: travelEnd);

  return Trip(
    id: trip.id,
    slug: trip.slug,
    title: trip.title == 'Yeni seyahat' ||
            trip.title == 'Japonya Turu' ||
            trip.title.contains('→')
        ? title
        : trip.title,
    subtitle: trip.subtitle,
    timezone:
        getDestinationProfile(first?.countryCode ?? '')?.timezone ??
            trip.timezone,
    tripStart: '${travelStart}T08:00:00',
    tripEnd: '${travelEnd}T20:00:00',
    flights: TripFlights(legs: legs, outbound: outbound, returnLegs: returnLegs),
    hotels: trip.hotels,
    tickets: trip.tickets,
    preferences: prefs,
    days: days,
    deadlines: trip.deadlines,
  );
}
