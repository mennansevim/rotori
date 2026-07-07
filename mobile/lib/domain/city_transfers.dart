// TypeScript packages/shared/src/cityTransfers.ts'in Dart karşılığı.
// Şehirler arası bilinen transferler + plan içinde şehir geçişi tespiti.

import 'destination_profiles.dart';
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

  /// UI başlığı (ör. "Shinkansen Nozomi")
  final String mode;

  /// Yaklaşık süre (ör. "2s 30dk")
  final String duration;

  /// Tek yön yaklaşık ücret (ör. "~14,000 ¥")
  final String fare;

  /// Plan içinde gösterilecek kısa ipucu
  final String? tip;
}

const Map<String, CityTransfer> _transfers = {
  'tokyo|osaka': CityTransfer(
    emoji: '🚄',
    mode: 'Shinkansen Nozomi',
    duration: '2s 30dk',
    fare: '~14,720 ¥',
    tip: 'IC kart yerine gişe/Smart-EX. JR Pass kullanılmaz Nozomi için.',
  ),
  'tokyo|kyoto': CityTransfer(
    emoji: '🚄',
    mode: 'Shinkansen Nozomi',
    duration: '2s 15dk',
    fare: '~14,170 ¥',
    tip:
        'Sabah erken Nozomi sefer aralıkları sık, oturma kolaylığı için ayırtılabilir.',
  ),
  'tokyo|hakone': CityTransfer(
    emoji: '🚆',
    mode: 'Odakyu Romance Car',
    duration: '1s 30dk',
    fare: '~2,470 ¥',
    tip: 'Hakone Free Pass al, gün boyu dağ ulaşımı dahil.',
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
    tip: 'IC kart (Suica/Icoca) ile bin, ek bilet gerekmez.',
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

/// Verilen güne, başına şehir-arası transfer öğesi ekle.
List<DayPlan> insertCityTransfer(
  List<DayPlan> days,
  int dayNumber,
  CityTransitionSuggestion suggestion,
) {
  return days.map((d) {
    if (d.dayNumber != dayNumber) return d;
    final t = suggestion.transfer;
    final item = TimelineItem(
      id: newItemId(dayNumber),
      title:
          '${t.emoji} ${suggestion.fromCity} → ${suggestion.toCity} • ${t.mode}',
      description: '${t.duration} · ${t.fare}',
      tips: t.tip,
      kind: TimelineItemKind.transport,
      time: '08:30',
      scheduledTime: '08:30',
      cityId: suggestion.toCity,
    );
    return d.copyWith(items: [item, ...d.items]);
  }).toList();
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
