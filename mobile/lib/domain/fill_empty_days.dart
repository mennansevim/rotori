// TypeScript packages/shared/src/fillEmptyDays.ts'in Dart karşılığı.
// AI cevabından sonra hâlâ boş kalan günleri destinasyon profilinin
// popularPlaces listesinden rotasyonla doldurur.

import 'dart:math';

import '../core/l10n.dart';
import 'city_places.dart';
import 'destination_profiles.dart';
import 'japan_suggestions.dart' show PlaceCoverage, coverageOfTitle;
import 'trip_factory.dart';
import 'types.dart';

/// Tek bir saat dilimine göre yer önerisi şablonu.
class _SlotTemplate {
  const _SlotTemplate({required this.time, required this.kind, this.mealTag});
  final String time;
  final TimelineItemKind kind;

  /// kind=meal ise yemek tipi — i18n anahtarı (prefix `gen.`), `L10n.resolve`
  /// ile çözülür.
  final String? mealTag;
}

const List<_SlotTemplate> _fillSlots = [
  _SlotTemplate(time: '09:00', kind: TimelineItemKind.activity),
  _SlotTemplate(time: '11:00', kind: TimelineItemKind.activity),
  _SlotTemplate(
      time: '13:00', kind: TimelineItemKind.meal, mealTag: 'gen.meal.lunch'),
  _SlotTemplate(time: '14:30', kind: TimelineItemKind.activity),
  _SlotTemplate(time: '16:30', kind: TimelineItemKind.activity),
  _SlotTemplate(
      time: '19:00', kind: TimelineItemKind.meal, mealTag: 'gen.meal.dinner'),
];

class MealPreset {
  const MealPreset({required this.emoji, required this.name, required this.tip});
  final String emoji;

  /// i18n anahtarı (prefix `gen.`) — `L10n.resolve(name, lang)` ile çözülür.
  final String name;

  /// i18n anahtarı (prefix `gen.`) — `L10n.resolve(tip, lang)` ile çözülür.
  final String tip;
}

const List<MealPreset> kMealPresets = [
  MealPreset(
      emoji: '🍜',
      name: 'gen.meal.ramen',
      tip: 'gen.mealTip.ramen'),
  MealPreset(
      emoji: '🍣',
      name: 'gen.meal.conveyorSushi',
      tip: 'gen.mealTip.conveyorSushi'),
  MealPreset(
      emoji: '🥩',
      name: 'gen.meal.yakitori',
      tip: 'gen.mealTip.yakitori'),
  MealPreset(
      emoji: '🍱',
      name: 'gen.meal.konbiniBento',
      tip: 'gen.mealTip.konbiniBento'),
  MealPreset(
      emoji: '🍛',
      name: 'gen.meal.japaneseCurry',
      tip: 'gen.mealTip.japaneseCurry'),
];

/// "HH:mm" → dakika (0..1439). Geçersizse null.
int? _hhmmToMin(String? t) {
  if (t == null || t.isEmpty) return null;
  final parts = t.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// Şehir adından (örn "Tokyo (Haneda)") sade şehir döndür.
String _cleanCity(String city) =>
    city.replaceAll(RegExp(r'\s*\(.*\)\s*$'), '').trim();

/// Şehir adından city_places.dart kaydını (alias'larla) çözer — havuz
/// zenginleştirmesi için.
CityData? _fillCityData(String city) {
  final n = _cleanCity(city).toLowerCase();
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

class _FillPlace {
  const _FillPlace({required this.name, this.emoji, this.typicalSteps});
  final String name;
  final String? emoji;
  final int? typicalSteps;
}

/// Bir gün için TimelineItem üret — şablon + popularPlace eşle.
TimelineItem _buildItem(
  int dayNumber,
  _SlotTemplate slot,
  String city,
  _FillPlace? place,
  MealPreset preset,
  AppLang lang,
) {
  final id = '${newItemId(dayNumber)}-fill-${slot.time.replaceAll(':', '')}';
  if (slot.kind == TimelineItemKind.meal) {
    return TimelineItem(
      id: id,
      title: '${preset.emoji} ${L10n.resolve(slot.mealTag!, lang)} — '
          '${L10n.resolve(preset.name, lang)}',
      description: L10n.resolve('gen.fill.mealDesc', lang),
      tips: L10n.resolve(preset.tip, lang),
      kind: TimelineItemKind.meal,
      time: slot.time,
      scheduledTime: slot.time,
      durationMin: 45,
      cityId: city,
    );
  }
  final name = place?.name ?? L10n.resolve('gen.fill.neighborhoodWalk', lang);
  final emoji = place?.emoji ?? '🚶';
  return TimelineItem(
    id: id,
    title: '$emoji $name',
    description: place != null
        ? L10n.parametrize(L10n.resolve('gen.fill.popularStop', lang),
            {'city': _cleanCity(city)})
        : L10n.resolve('gen.fill.freeExplore', lang),
    kind: TimelineItemKind.activity,
    time: slot.time,
    scheduledTime: slot.time,
    durationMin: 90,
    mapUrl: place != null
        ? 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('${place.name} ${_cleanCity(city)}')}'
        : null,
    cityId: city,
  );
}

/// AI cevabından sonra hâlâ items.length === 0 olan günleri doldur.
/// Destinasyon profilinin popularPlaces listesinden rotasyonla seçer.
List<DayPlan> fillEmptyDays(
  List<DayPlan> days,
  List<TripDestination> destinations, {
  AppLang lang = AppLang.tr,
}) {
  // Şehir bazında popularPlace havuzu + rotasyon indeksleri
  final cityPlaces = <String, List<_FillPlace>>{};
  final cityCursors = <String, int>{};

  for (final dest in destinations) {
    final profile = getDestinationProfile(dest.countryCode);
    if (profile == null) continue;
    final cityName = dest.city.isNotEmpty ? dest.city : dest.countryName;
    final key = _cleanCity(cityName);
    if (cityPlaces.containsKey(key)) continue;
    final keyLower = key.toLowerCase();
    final list = <_FillPlace>[];
    final seen = <String>{};
    // 1) Profil popularPlaces'ından YALNIZCA bu şehre ait olanlar.
    for (final p in profile.popularPlaces) {
      if (_cleanCity(p.city).toLowerCase() != keyLower) continue;
      if (!seen.add(p.name.toLowerCase())) continue;
      list.add(_FillPlace(
          name: p.name, emoji: p.emoji, typicalSteps: p.typicalSteps));
    }
    // 2) city_places.dart'tan zenginleştir (Kyoto gibi az mekanlı şehirlerde
    //    günler aynı yeri tekrarlamasın diye şart).
    final cd = _fillCityData(cityName);
    if (cd != null) {
      for (final cp in cd.places) {
        if (!seen.add(cp.name.toLowerCase())) continue;
        list.add(_FillPlace(name: cp.name, emoji: cp.emoji, typicalSteps: 9000));
      }
    }
    cityPlaces[key] = list;
    cityCursors[key] = 0;
  }

  var mealCursor = 0;

  const minItemsPerDay = 4;

  return days.map((day) {
    if (day.items.length >= minItemsPerDay) return day;
    // Full/half-day mekan (Disney, USJ, teamLab) günü kaplar — ekstra doldurma
    // yok, kalıbı bozulmasın.
    final anyCovered = day.items.any(
        (it) => coverageOfTitle(it.title) != PlaceCoverage.normal);
    if (anyCovered) return day;
    final dest = getDestinationForDate(destinations, day.date);
    final destCity = dest == null
        ? ''
        : (dest.city.isNotEmpty ? dest.city : dest.countryName);
    final cityKey = _cleanCity(destCity);
    final pool = cityPlaces[cityKey] ?? const <_FillPlace>[];
    var cursor = cityCursors[cityKey] ?? 0;

    // Hangi saat dilimlerinde zaten item var?
    final usedTimes = <String>{
      for (final it in day.items)
        if (it.time != null && it.time!.isNotEmpty) it.time!,
    };
    final usedKindCounts = <String, int>{};
    for (final it in day.items) {
      final k = it.kind?.name ?? 'activity';
      usedKindCounts[k] = (usedKindCounts[k] ?? 0) + 1;
    }
    // Gün içinde zaten planlanmış yemeklerin saatleri (dakika). Yeni bir yemek
    // eklemeden önce bunlara yakınlık kontrol edilir — böylece 11:30'daki öğle
    // yemeğinin üstüne 13:00'e ikinci bir öğle yemeği eklenmez.
    final existingMealMins = <int>[
      for (final it in day.items)
        if (it.kind == TimelineItemKind.meal)
          if (_hhmmToMin(it.time ?? it.scheduledTime) case final int m) m,
    ];

    final supplements = <TimelineItem>[];
    var stepsSum = day.stepsEstimate ?? 0;
    final tags = <String>{...day.tags};

    for (final slot in _fillSlots) {
      if (usedTimes.contains(slot.time)) continue;
      // Yemek slot'u: (a) günde en fazla 2 yemek, (b) bu slot'un saatine
      // ±2.5 saat içinde zaten bir yemek varsa ekleme (üst üste öğün olmasın).
      if (slot.kind == TimelineItemKind.meal) {
        if ((usedKindCounts['meal'] ?? 0) >= 2) continue;
        final slotMin = _hhmmToMin(slot.time);
        if (slotMin != null &&
            existingMealMins.any((m) => (m - slotMin).abs() < 150)) {
          continue;
        }
      }
      // Activity slot'u: havuz yoksa atla
      _FillPlace? place;
      if (slot.kind == TimelineItemKind.activity) {
        if (pool.isEmpty) continue;
        // Aynı yer zaten varsa cursor'ı ilerlet
        var attempts = 0;
        while (attempts < pool.length) {
          final candidate = pool[cursor % pool.length];
          final inDay =
              day.items.any((it) => it.title.contains(candidate.name));
          final inSupp =
              supplements.any((it) => it.title.contains(candidate.name));
          if (!inDay && !inSupp) {
            place = candidate;
            break;
          }
          cursor++;
          attempts++;
        }
        if (place == null) continue;
        cursor++;
        stepsSum += place.typicalSteps ?? 3000;
        tags.add(place.name);
      }
      final preset = kMealPresets[mealCursor % kMealPresets.length];
      if (slot.kind == TimelineItemKind.meal) {
        mealCursor++;
        // Bu döngüde eklenen yemeği de kaydet ki bir sonraki yemek slot'u
        // buna yakınsa atlansın (aynı gün iki öğle olmasın).
        final m = _hhmmToMin(slot.time);
        if (m != null) existingMealMins.add(m);
      }
      supplements
          .add(_buildItem(day.dayNumber, slot, cityKey, place, preset, lang));

      // Yeterince eklediysek dur
      if (day.items.length + supplements.length >= minItemsPerDay + 1) break;
    }

    cityCursors[cityKey] = cursor;

    if (supplements.isEmpty) return day;

    final merged = [...day.items, ...supplements]..sort(
        (a, b) => (a.time ?? '99:99').compareTo(b.time ?? '99:99'),
      );

    final theme = day.theme.isNotEmpty &&
            !day.theme.startsWith('Gün ') &&
            !day.theme.contains(' — Gün ')
        ? day.theme
        : L10n.parametrize(
            L10n.resolve('gen.fill.exploreDay', lang), {'city': cityKey});

    return day.copyWith(
      theme: theme,
      tags: tags.take(5).toList(),
      stepsEstimate: min(22000, max(day.stepsEstimate ?? 0, stepsSum)),
      items: merged,
    );
  }).toList();
}
