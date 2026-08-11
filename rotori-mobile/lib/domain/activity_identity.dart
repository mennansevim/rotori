import 'place_identity_resolver.dart';
import 'route_field_context.dart';
import 'types.dart';

/// Plan içindeki bir aktivite örneğinin (`TimelineItem.id`) katalogdaki mekan
/// kimliğinden (`placeId`) ayrı tutulmasını sağlayan kanonikleştirme katmanı.
///
/// v3'te çözümleme [PlaceIdentityResolver]'a devredildi: Kanji/Kana/Romaji
/// varyantları (清水寺 · きよみずでら · Kiyomizu-dera) tek anahtara iner. Latin
/// girdide çıktı v2 ile birebir aynıdır.
///
/// Katalog kimliği olmayan eski planlarda başlık yalnız kontrollü fallback
/// olarak kullanılır. Ulaşım, öğün ve otel satırları bu sözleşmeye dahil
/// değildir.
String canonicalPlaceIdentity({
  required String title,
  String? placeId,
  String? cityId,
}) =>
    kPlaceIdentityResolver
        .resolve(title: title, placeId: placeId, cityId: cityId)
        .key;

/// Kararlı kanonik hash (`TimelineItem.canonicalPlaceHash` alanına yazılır).
/// Kimlik çözülemezse boş string döner.
String canonicalPlaceHashFor({
  required String title,
  String? placeId,
  String? cityId,
}) =>
    kPlaceIdentityResolver
        .resolve(title: title, placeId: placeId, cityId: cityId)
        .hash;

String canonicalCatalogPlaceIdentity({
  required String city,
  required String id,
  required String name,
}) =>
    canonicalPlaceIdentity(title: name, placeId: id, cityId: city);

/// Bir timeline satırının kanonik kimliği. `canonicalPlaceHash` yazılıysa bile
/// anahtar başlıktan yeniden türetilir — hash yalnız depolama/telemetri
/// içindir, kimlik kararı her zaman kaynak alanlardan verilir.
CanonicalPlaceHash identityOf(TimelineItem item) =>
    kPlaceIdentityResolver.resolve(
      title: item.title,
      placeId: item.placeId,
      cityId: item.cityId,
    );

/// Bir timeline satırının tekrar kuralı. v3 `repeat` nesnesi yoksa katalog
/// ipuçlarından (`inferRepeatRule`) muhafazakâr karar verilir.
RepeatRule repeatRuleOf(TimelineItem item) {
  final signals = item.repeat;
  if (signals != null) {
    if (signals.userExplicitSelection || signals.policy == 'userOverride') {
      return const RepeatRule.userSelected();
    }
    if (signals.policy == 'timeQuota' &&
        signals.recommendedTotalMinutes != null) {
      return RepeatRule.quota(
        signals.recommendedTotalMinutes!,
        maximumConsecutiveDays: signals.maximumConsecutiveDays ?? 2,
      );
    }
    if (signals.isRepeatableZone || signals.policy == 'repeatableZone') {
      return RepeatRule.zone(
        maximumConsecutiveDays: signals.maximumConsecutiveDays ?? 2,
      );
    }
    if (signals.policy == 'hardZero') {
      return const RepeatRule(policy: RepeatPolicy.hardZero);
    }
  }
  return inferRepeatRule(title: item.title, recommendedTotalMinutes: null);
}

class ConsecutiveActivityDuplicate {
  const ConsecutiveActivityDuplicate({
    required this.identity,
    required this.previousDayNumber,
    required this.dayNumber,
    required this.previousTitle,
    required this.title,
    this.policy = 'hardZero',
  });

  final String identity;
  final int previousDayNumber;
  final int dayNumber;
  final String previousTitle;
  final String title;

  /// Hangi politikayla ihlal sayıldığı (`RepeatPolicy.name`).
  final String policy;

  Map<String, dynamic> toJson() => {
        'identity': identity,
        'previousDayNumber': previousDayNumber,
        'dayNumber': dayNumber,
        'previousTitle': previousTitle,
        'title': title,
        'policy': policy,
      };
}

/// Ardışık günlerde aynı kanonik mekanı bulan saf kalite kapısı.
///
/// Intent-aware: `repeatableZone`, `timeQuota` (kota dolmamışsa) ve
/// `userOverride` politikaları ihlal sayılmaz.
List<ConsecutiveActivityDuplicate> findConsecutiveActivityDuplicates(
  List<DayPlan> days,
) {
  const evaluator = RepeatPolicyEvaluator();
  final sorted = [...days]..sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
  final duplicates = <ConsecutiveActivityDuplicate>[];
  var previous = const <String, _VisitTrace>{};
  int? previousDayNumber;

  for (final day in sorted) {
    final current = <String, _VisitTrace>{};
    for (final item in day.items) {
      if (item.kind != TimelineItemKind.activity) continue;
      final identity = identityOf(item);
      if (identity.isEmpty) continue;

      final rule = repeatRuleOf(item);
      final earlier = previous[identity.key];
      current.putIfAbsent(
        identity.key,
        () => _VisitTrace(
          item: item,
          minutes: (earlier?.minutes ?? 0) + (item.durationMin ?? 0),
          consecutiveDays: (earlier?.consecutiveDays ?? 0) + 1,
        ),
      );

      if (earlier == null || previousDayNumber == null) continue;
      final verdict = evaluator.evaluate(
        rule: rule,
        observation: RepeatObservation(
          identityKey: identity.key,
          previousDayNumber: previousDayNumber,
          minutesSpentSoFar: earlier.minutes,
          consecutiveDayCount: earlier.consecutiveDays,
        ),
      );
      if (verdict.isAllowed) continue;
      duplicates.add(ConsecutiveActivityDuplicate(
        identity: identity.key,
        previousDayNumber: previousDayNumber,
        dayNumber: day.dayNumber,
        previousTitle: earlier.item.title,
        title: item.title,
        policy: rule.policy.name,
      ));
    }
    previous = current;
    previousDayNumber = day.dayNumber;
  }
  return duplicates;
}

/// Üretici katalog verisinde yeni bir alias kaçağı olsa bile aynı mekanı iki
/// ardışık güne bırakmayan deterministik son güvenlik ağı.
///
/// Tekrar politikası izin veriyorsa satır **korunur** — bu, "hard-zero"
/// kuralının bölgeler ve çok günlük biletler için gevşetilmesidir.
List<DayPlan> removeConsecutiveActivityDuplicates(List<DayPlan> days) {
  const evaluator = RepeatPolicyEvaluator();
  final sorted = [...days]..sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
  final output = <DayPlan>[];
  var previous = <String, _VisitTrace>{};
  int? previousDayNumber;

  for (final day in sorted) {
    final current = <String, _VisitTrace>{};
    var changed = false;
    final items = <TimelineItem>[];

    for (final item in day.items) {
      if (item.kind != TimelineItemKind.activity) {
        items.add(item);
        continue;
      }
      final identity = identityOf(item);
      if (identity.isEmpty) {
        items.add(item);
        continue;
      }

      final earlier = previous[identity.key];
      if (earlier != null && previousDayNumber != null) {
        final verdict = evaluator.evaluate(
          rule: repeatRuleOf(item),
          observation: RepeatObservation(
            identityKey: identity.key,
            previousDayNumber: previousDayNumber,
            minutesSpentSoFar: earlier.minutes,
            consecutiveDayCount: earlier.consecutiveDays,
          ),
        );
        if (!verdict.isAllowed) {
          changed = true;
          continue;
        }
      }

      current.putIfAbsent(
        identity.key,
        () => _VisitTrace(
          item: item,
          minutes: (earlier?.minutes ?? 0) + (item.durationMin ?? 0),
          consecutiveDays: (earlier?.consecutiveDays ?? 0) + 1,
        ),
      );
      items.add(item);
    }

    if (!changed) {
      output.add(day);
    } else {
      TimelineItem? firstActivity;
      String? cityId;
      for (final item in items) {
        cityId ??= item.cityId;
        if (item.kind == TimelineItemKind.activity) {
          firstActivity = item;
          break;
        }
      }
      output.add(day.copyWith(
        theme: firstActivity?.title ?? cityId ?? day.theme,
        tags: firstActivity == null ? const [] : [firstActivity.title],
        items: items,
      ));
    }
    previous = current;
    previousDayNumber = day.dayNumber;
  }
  return output;
}

/// Bir mekanın ardışık günlerdeki ziyaret izi — zaman kotası hesabı için
/// süre ve ardışık gün sayısı taşınır.
class _VisitTrace {
  const _VisitTrace({
    required this.item,
    required this.minutes,
    required this.consecutiveDays,
  });

  final TimelineItem item;
  final int minutes;
  final int consecutiveDays;
}
