// TypeScript packages/shared/src/fillEmptyDays.ts'in Dart karşılığı.
// AI cevabından sonra hâlâ boş kalan günleri destinasyon profilinin
// popularPlaces listesinden rotasyonla doldurur.

import 'dart:math';

import 'destination_profiles.dart';
import 'trip_factory.dart';
import 'types.dart';

/// Tek bir saat dilimine göre yer önerisi şablonu.
class _SlotTemplate {
  const _SlotTemplate({required this.time, required this.kind, this.mealTag});
  final String time;
  final TimelineItemKind kind;

  /// kind=meal ise yemek tipi (Türkçe etiket).
  final String? mealTag;
}

const List<_SlotTemplate> _fillSlots = [
  _SlotTemplate(time: '09:00', kind: TimelineItemKind.activity),
  _SlotTemplate(time: '11:00', kind: TimelineItemKind.activity),
  _SlotTemplate(
      time: '13:00', kind: TimelineItemKind.meal, mealTag: 'Öğle yemeği'),
  _SlotTemplate(time: '14:30', kind: TimelineItemKind.activity),
  _SlotTemplate(time: '16:30', kind: TimelineItemKind.activity),
  _SlotTemplate(
      time: '19:00', kind: TimelineItemKind.meal, mealTag: 'Akşam yemeği'),
];

class MealPreset {
  const MealPreset({required this.emoji, required this.name, required this.tip});
  final String emoji;
  final String name;
  final String tip;
}

const List<MealPreset> kMealPresets = [
  MealPreset(
      emoji: '🍜',
      name: 'Ramen molası',
      tip: 'Tonkotsu veya shoyu — Ichiran, Ippudo, Afuri gibi zincirlerden biri.'),
  MealPreset(
      emoji: '🍣',
      name: 'Conveyor sushi',
      tip: 'Sushiro / Kura Sushi — uygun fiyatlı, çocuk dostu.'),
  MealPreset(
      emoji: '🥩',
      name: 'Yakitori izakaya',
      tip: 'Tori-kizoku zinciri ya da Omoide Yokocho ara sokakları.'),
  MealPreset(
      emoji: '🍱',
      name: 'Konbini bento',
      tip: 'Family Mart / Lawson — taze onigiri & bento, hızlı seçenek.'),
  MealPreset(
      emoji: '🍛',
      name: 'Japon curry',
      tip: 'CoCo Ichibanya — acılığı + topping seçilebilir.'),
];

/// Şehir adından (örn "Tokyo (Haneda)") sade şehir döndür.
String _cleanCity(String city) =>
    city.replaceAll(RegExp(r'\s*\(.*\)\s*$'), '').trim();

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
) {
  final id = '${newItemId(dayNumber)}-fill-${slot.time.replaceAll(':', '')}';
  if (slot.kind == TimelineItemKind.meal) {
    return TimelineItem(
      id: id,
      title: '${preset.emoji} ${slot.mealTag} — ${preset.name}',
      description: 'Hızlı, yerel bir mola.',
      tips: preset.tip,
      kind: TimelineItemKind.meal,
      time: slot.time,
      scheduledTime: slot.time,
      durationMin: 45,
      cityId: city,
    );
  }
  final name = place?.name ?? 'Mahalle yürüyüşü';
  final emoji = place?.emoji ?? '🚶';
  return TimelineItem(
    id: id,
    title: '$emoji $name',
    description: place != null
        ? '${_cleanCity(city)} bölgesinde popüler durak.'
        : 'Bölgede serbest keşif.',
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
  List<TripDestination> destinations,
) {
  // Şehir bazında popularPlace havuzu + rotasyon indeksleri
  final cityPlaces = <String, List<_FillPlace>>{};
  final cityCursors = <String, int>{};

  for (final dest in destinations) {
    final profile = getDestinationProfile(dest.countryCode);
    if (profile == null) continue;
    final key = _cleanCity(dest.city.isNotEmpty ? dest.city : dest.countryName);
    if (cityPlaces.containsKey(key)) continue;
    cityPlaces[key] = profile.popularPlaces
        .map((p) => _FillPlace(
              name: p.name,
              emoji: p.emoji,
              typicalSteps: p.typicalSteps,
            ))
        .toList();
    cityCursors[key] = 0;
  }

  var mealCursor = 0;

  const minItemsPerDay = 4;

  return days.map((day) {
    if (day.items.length >= minItemsPerDay) return day;
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

    final supplements = <TimelineItem>[];
    var stepsSum = day.stepsEstimate ?? 0;
    final tags = <String>{...day.tags};

    for (final slot in _fillSlots) {
      if (usedTimes.contains(slot.time)) continue;
      // Yemek slot'u: gün içinde aynı kind 2'den az ise ekle
      if (slot.kind == TimelineItemKind.meal &&
          (usedKindCounts['meal'] ?? 0) >= 2) {
        continue;
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
      if (slot.kind == TimelineItemKind.meal) mealCursor++;
      supplements.add(_buildItem(day.dayNumber, slot, cityKey, place, preset));

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
        : '$cityKey keşif günü';

    return day.copyWith(
      theme: theme,
      tags: tags.take(5).toList(),
      stepsEstimate: min(22000, max(day.stepsEstimate ?? 0, stepsSum)),
      items: merged,
    );
  }).toList();
}
