// TypeScript packages/shared/src/rules.ts'in Dart karşılığı.
// Yayın öncesi uyarı kuralları + gün-arası taşıma.

import '../core/l10n.dart';
import 'types.dart';

enum TripWarningSeverity { info, warn, urgent }

class TripWarning {
  const TripWarning({
    required this.id,
    required this.severity,
    required this.messageKey,
    this.messageParams,
    this.dayNumber,
    this.step,
  });

  final String id;
  final TripWarningSeverity severity;

  /// i18n anahtarı ('rules.*'). Görüntülemede LanguageScope ile çözülür.
  final String messageKey;

  /// {placeholder} değerleri (varsa) — çözüm anında doldurulur.
  final Map<String, String>? messageParams;

  final int? dayNumber;

  /// Yayın adımındaki "adıma dön" butonu için hedef step id.
  /// 'journey' | 'explore' | 'title' | 'hotels' | 'food' | 'plan' | 'calendar'
  final String? step;

  /// Geriye dönük uyumluluk: anahtarı varsayılan dilde (TR) çözer.
  /// UI i18n için messageKey/messageParams'ı LanguageScope ile kullanmalı.
  String get message => L10n.parametrize(
        L10n.resolve(messageKey, AppLang.tr),
        messageParams ?? const <String, String>{},
      );
}

/// 15000 → "15.000" (tr-TR binlik ayırıcı, TS toLocaleString karşılığı).
String _trNumber(int n) => n.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );

TripWarning? checkStepsOverLimit(DayPlan day, int? maxSteps) {
  if (maxSteps == null || maxSteps == 0) return null;
  final estimate = day.stepsEstimateMax ?? day.stepsEstimate;
  if (estimate != null && estimate > maxSteps) {
    return TripWarning(
      id: 'steps-${day.dayNumber}',
      severity: TripWarningSeverity.warn,
      messageKey: 'rules.stepsOverLimit',
      messageParams: {
        'day': '${day.dayNumber}',
        'estimate': _trNumber(estimate),
        'limit': _trNumber(maxSteps),
      },
      dayNumber: day.dayNumber,
      step: 'plan',
    );
  }
  return null;
}

List<TripWarning> checkUnassignedMustSee(Trip trip) {
  final assigned = <String>{
    for (final d in trip.days)
      for (final i in d.items) ...[
        i.title,
        if (i.description != null) i.description!,
      ],
  };
  final text = assigned.join(' ').toLowerCase();
  return trip.preferences.mustSee
      .where((place) => !text.contains(place.toLowerCase()))
      .map((place) => TripWarning(
            id: 'mustsee-$place',
            severity: TripWarningSeverity.info,
            messageKey: 'rules.mustSeeUnassigned',
            messageParams: {'place': place},
            step: 'plan',
          ))
      .toList();
}

TripWarning? checkShinkansenDeadline(String? deadline, {DateTime? now}) {
  if (deadline == null || deadline.isEmpty) return null;
  final d = DateTime.tryParse(deadline);
  if (d == null) return null;
  final diff = d.difference(now ?? DateTime.now()).inMilliseconds;
  final days = (diff / 86400000).floor();
  if (days <= 0) {
    return const TripWarning(
      id: 'shinkansen-urgent',
      severity: TripWarningSeverity.urgent,
      messageKey: 'rules.shinkansenUrgent',
    );
  }
  if (days <= 30) {
    return TripWarning(
      id: 'shinkansen-soon',
      severity: TripWarningSeverity.warn,
      messageKey: 'rules.shinkansenSoon',
      messageParams: {'days': '$days'},
    );
  }
  return null;
}

TripWarning? checkHotelsIncomplete(Trip trip) {
  final dests = trip.preferences.destinations;
  if (dests.isEmpty) return null;
  final hotels = trip.hotels;
  if (hotels.isEmpty) {
    return const TripWarning(
      id: 'hotels-missing',
      severity: TripWarningSeverity.warn,
      messageKey: 'rules.hotelsMissing',
      step: 'hotels',
    );
  }
  final incomplete = hotels
      .where((h) =>
          h.city.trim().isEmpty ||
          h.name.trim().isEmpty ||
          h.address.trim().isEmpty)
      .length;
  if (incomplete > 0) {
    return TripWarning(
      id: 'hotels-incomplete',
      severity: TripWarningSeverity.warn,
      messageKey: 'rules.hotelsIncomplete',
      messageParams: {'count': '$incomplete'},
      step: 'hotels',
    );
  }
  return null;
}

TripWarning? checkEmptyPlan(Trip trip) {
  if (trip.days.isEmpty) return null;
  final allEmpty = trip.days.every((d) => d.items.isEmpty);
  if (allEmpty) {
    return const TripWarning(
      id: 'plan-empty',
      severity: TripWarningSeverity.warn,
      messageKey: 'rules.planEmpty',
      step: 'plan',
    );
  }
  return null;
}

TripWarning? checkMissingTitle(Trip trip) {
  final t = trip.title.trim();
  if (t.isEmpty || t == 'Yeni seyahat' || t == 'Japonya Turu') {
    return const TripWarning(
      id: 'title-default',
      severity: TripWarningSeverity.info,
      messageKey: 'rules.titleDefault',
      step: 'title',
    );
  }
  return null;
}

List<TripWarning> collectTripWarnings(Trip trip) {
  final warnings = <TripWarning>[];

  final hotel = checkHotelsIncomplete(trip);
  if (hotel != null) warnings.add(hotel);
  final empty = checkEmptyPlan(trip);
  if (empty != null) warnings.add(empty);
  final title = checkMissingTitle(trip);
  if (title != null) warnings.add(title);

  warnings.addAll(checkUnassignedMustSee(trip));
  final sh = checkShinkansenDeadline(trip.deadlines?.shinkansenBooking);
  if (sh != null) warnings.add(sh);

  return warnings;
}

bool suggestTaxiForDay(DayPlan day, TripPreferences prefs) {
  final est = day.stepsEstimateMax ?? day.stepsEstimate ?? 0;
  final max = prefs.maxStepsPerDay ?? 14000;
  return est > max || day.taxiRecommended == true;
}

/// Bir öğeyi bir günden diğerine taşır; movedFromDay ile kaynağı işaretler.
/// Kaynak/hedef bulunamazsa veya öğe yoksa orijinal listeyi döndürür.
List<DayPlan> moveItemBetweenDays(
  List<DayPlan> days,
  String itemId,
  int fromDayNumber,
  int toDayNumber,
) {
  if (fromDayNumber == toDayNumber) return days;

  final next = days.map((d) => d.copyWith(items: [...d.items])).toList();

  DayPlan? from;
  DayPlan? to;
  for (final d in next) {
    if (d.dayNumber == fromDayNumber) from = d;
    if (d.dayNumber == toDayNumber) to = d;
  }
  if (from == null || to == null) return days;

  final idx = from.items.indexWhere((i) => i.id == itemId);
  if (idx < 0) return days;

  final item = from.items.removeAt(idx);
  to.items.add(item.copyWith(movedFromDay: fromDayNumber));

  return next;
}
