// TypeScript packages/shared/src/itineraryGenerator.ts'in Dart karşılığı.
// Kural tabanlı gün-gün plan üretici (AI gerekmez) + AI yanıtı birleştirme.

import 'dart:math';

import 'destination_profiles.dart';
import 'explore.dart';
import 'japan_suggestions.dart';
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

const _timesRelaxed = ['10:00', '14:00', '18:00'];
const _timesModerate = ['09:00', '11:30', '14:00', '17:30'];
const _timesIntense = ['08:00', '10:00', '12:00', '14:30', '17:00', '19:00'];

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
    if (mustLower
        .any((m) => nameLower.contains(m) || m.contains(nameLower))) {
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
  scored.sort(
      (a, b) => b.score != a.score ? b.score - a.score : a.idx - b.idx);

  final out = <PlaceSuggestion>[];
  for (final e in scored) {
    if (out.length >= count) break;
    used.add(e.p.id);
    out.add(e.p);
  }
  return out;
}

TimelineItem _makeItem(int dayNumber, String time, PlaceSuggestion place) =>
    TimelineItem(
      id: newItemId(dayNumber),
      time: time,
      scheduledTime: time,
      title: '${place.emoji} ${place.name}',
      description: '${place.city} · ${place.category}',
      tips: place.category == 'culture'
          ? 'Sabah erken gitmek kalabalığı azaltır.'
          : place.category == 'food'
              ? 'Öğle veya akşam için ideal.'
              : null,
      kind: TimelineItemKind.activity,
    );

TimelineItem _mealItem(int dayNumber, String time, String label) =>
    TimelineItem(
      id: newItemId(dayNumber),
      time: time,
      scheduledTime: time,
      title: '🍽️ $label',
      kind: TimelineItemKind.meal,
    );

DayPlan _buildFromTemplate(
  DayPlan day,
  DayTemplate template,
  List<PlaceSuggestion> places,
  Pace pace,
) {
  final times = _timesForPace(pace);
  final items = <TimelineItem>[];
  var stepSum = 0;

  for (var i = 0; i < template.places.length; i++) {
    final place = _placeById(places, template.places[i]);
    if (place == null) continue;
    final time = i < times.length ? times[i] : times.last;
    items.add(_makeItem(day.dayNumber, time, place));
    stepSum += place.typicalSteps ?? 8000;
    if (i == 0 && times.length > 1) {
      items.add(_mealItem(day.dayNumber, times[1], 'Öğle yemeği molası'));
    }
  }

  if (items.isEmpty && template.id.contains('arrival')) {
    items.add(TimelineItem(
      id: newItemId(day.dayNumber),
      time: '15:00',
      scheduledTime: '15:00',
      title: '🛬 Varış & check-in',
      description: 'Otele yerleş, jet lag için hafif tempo.',
      kind: TimelineItemKind.activity,
    ));
    items.add(TimelineItem(
      id: newItemId(day.dayNumber),
      time: '18:00',
      scheduledTime: '18:00',
      title: '🏪 Çevre keşfi & konbini',
      description: 'Yakın çevrede kısa yürüyüş, akşam atıştırmalığı.',
      kind: TimelineItemKind.meal,
    ));
    stepSum = template.stepsEstimate;
  }

  final tags = template.places
      .map((id) => _placeById(places, id)?.name)
      .whereType<String>()
      .toList();

  final paceLabel = pace == Pace.relaxed
      ? 'Rahat'
      : pace == Pace.intense
          ? 'Yoğun'
          : 'Dengeli';
  final highlights = [
    DayHighlight(
      title: template.label,
      body: '${template.emoji} ${template.theme} — tempo: $paceLabel',
    ),
  ];

  return day.copyWith(
    theme: '${template.emoji} ${template.theme}',
    tags: tags.isNotEmpty ? tags : [template.label],
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

DayPlan _buildDepartureDay(DayPlan day, String destName, String flag) =>
    day.copyWith(
      theme: '$flag Ayrılış & havaalanı',
      tags: ['Ayrılış', destName],
      stepsEstimate: 6000,
      items: [
        TimelineItem(
          id: newItemId(day.dayNumber),
          time: '09:00',
          scheduledTime: '09:00',
          title: '🧳 Check-out & valiz',
          kind: TimelineItemKind.activity,
        ),
        TimelineItem(
          id: newItemId(day.dayNumber),
          time: '11:00',
          scheduledTime: '11:00',
          title: '🚕 Havaalanı transferi',
          description: 'Tren veya taksi — uçuş saatine göre erken çık.',
          kind: TimelineItemKind.transport,
        ),
        TimelineItem(
          id: newItemId(day.dayNumber),
          time: '14:00',
          scheduledTime: '14:00',
          title: '✈️ Dönüş uçuşu',
          kind: TimelineItemKind.transport,
        ),
      ],
      highlights: [
        DayHighlight(
          title: 'Ayrılış günü',
          body: 'Havaalanına en az 2–3 saat önce varın.',
        ),
      ],
    );

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
) {
  final count = _activitiesPerDay(pace);
  final picked =
      _pickPlaces(pool, count, used, kidMode, mustSee, interests, maxSteps);
  final times = _timesForPace(pace);
  final items = <TimelineItem>[];
  var stepSum = 0;

  for (var i = 0; i < picked.length; i++) {
    final time = i < times.length ? times[i] : times.last;
    items.add(_makeItem(day.dayNumber, time, picked[i]));
    stepSum += picked[i].typicalSteps ?? 8000;
  }

  if (picked.length >= 2 && times.length > 1) {
    items.insert(1, _mealItem(day.dayNumber, times[1], 'Öğle molası'));
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
              title: 'Öne çıkan',
              body: picked.map((p) => p.name).join(' · '),
            ),
          ]
        : <DayHighlight>[],
  );
}

/// Rota, tempo ve ülke profillerine göre gün-gün plan üretir (AI gerekmez).
List<DayPlan> generateItineraryFromTrip(Trip trip) {
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

  return trip.days.map((day) {
    final dest = getDestinationForDate(destinations, day.date);
    if (dest == null) return day;

    final profile = getDestinationProfile(dest.countryCode);
    if (profile == null) return day;

    final segDays = trip.days.where((d) {
      final dd = getDestinationForDate(destinations, d.date);
      return dd?.id == dest.id;
    }).toList();
    final dayIndexInSeg =
        segDays.indexWhere((d) => d.dayNumber == day.dayNumber);
    final isFirst = dayIndexInSeg == 0;
    final isLast = dayIndexInSeg == segDays.length - 1;
    final flag = profile.flag;

    if (isLast && segDays.length > 1) {
      return _buildDepartureDay(
        day,
        dest.city.isNotEmpty ? dest.city : profile.name,
        flag,
      );
    }

    final templates = profile.dayTemplates;
    if (isFirst) {
      DayTemplate? arrival;
      for (final t in templates) {
        if (t.id.contains('arrival')) {
          arrival = t;
          break;
        }
      }
      arrival ??= templates.isNotEmpty ? templates.first : null;
      if (arrival != null) {
        return _buildFromTemplate(day, arrival, profile.popularPlaces, pace);
      }
    }

    final middleTemplates =
        templates.where((t) => !t.id.contains('arrival')).toList();
    if (middleTemplates.isNotEmpty) {
      final idx = max(0, dayIndexInSeg - 1) % middleTemplates.length;
      final template = middleTemplates[idx];
      final built =
          _buildFromTemplate(day, template, profile.popularPlaces, pace);
      usedPlaces.addAll(template.places);
      return built;
    }

    return _buildFromPlaces(
      day,
      profile.popularPlaces,
      pace,
      usedPlaces,
      kidMode,
      mustSee,
      interests,
      maxSteps,
      dest.city.isNotEmpty ? dest.city : profile.name,
      flag,
    );
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
