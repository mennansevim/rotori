// Saf-Dart plan uyarı motoru — bir gün planı içindeki iki tür sorunu tespit
// eder ve UI'ya tüketilebilir uyarı listesi döner:
//
//   1. **Time conflict** — iki aktivite üst üste biner veya aralarında yeterli
//      geçiş süresi yoktur (yemek → 15 dk, diğer → 15 dk).
//   2. **Meal window** — yemek aktivitesi doğal saatinin dışına düşer:
//      • Kahvaltı  06:00 – 11:00
//      • Öğle      11:00 – 15:00
//      • Akşam     18:00 – 22:00  ← kullanıcı kesin sınır olarak istedi
//      Kafe/brunch penceresizdir (esnek).
//
// Bu dosya Flutter/Supabase import ETMEZ — domain katmanı disiplini için.

import 'types.dart';

enum PlanWarningKind { timeConflict, mealOutsideWindow }

class PlanWarning {
  const PlanWarning({
    required this.activityId,
    required this.kind,
    required this.message,
    this.conflictingActivityId,
  });

  final String activityId;
  final PlanWarningKind kind;
  final String message;
  final String? conflictingActivityId;
}

enum _MealKind { breakfast, lunch, dinner, cafe }

class _MealWindow {
  const _MealWindow(this.startMinutes, this.endMinutes, this.label);
  final int startMinutes;
  final int endMinutes;
  final String label;
}

const _kMealGapMinutes = 15;
const _kTransitionMinutes = 15;

const _kMealWindows = <_MealKind, _MealWindow>{
  _MealKind.breakfast:
      _MealWindow(kBreakfastStartMinutes, kBreakfastEndMinutes, 'kahvaltı'),
  _MealKind.lunch:
      _MealWindow(kLunchStartMinutes, kLunchEndMinutes, 'öğle yemeği'),
  _MealKind.dinner:
      _MealWindow(kDinnerStartMinutes, kDinnerEndMinutes, 'akşam yemeği'),
};

// ---------------------------------------------------------------------------
// Öğün pencereleri — DIŞARIYA AÇIK sözleşme
// ---------------------------------------------------------------------------

/// Öğün pencerelerinin TEK doğru kaynağı (dakika cinsinden, [start, end)).
///
/// **Why public:** Rota optimizasyonu kendi öğün saatlerini ayrı ayrı
/// tanımlıyordu (akşam 17:30'dan açık). Sonuç: optimizasyon akşam yemeğini
/// 17:30'a koyuyor, ardından BU dosya aynı öğeyi "normalde 18:00–22:00 arası
/// yenir" diye uyarıyordu — uygulama kendi çıktısını kural ihlali sayıyordu.
/// Optimizasyon artık bu değerleri okuyor; iki modül ayrışamaz.
const int kBreakfastStartMinutes = 6 * 60;
const int kBreakfastEndMinutes = 11 * 60;
const int kLunchStartMinutes = 11 * 60;
const int kLunchEndMinutes = 15 * 60;
const int kDinnerStartMinutes = 18 * 60;
const int kDinnerEndMinutes = 22 * 60;

/// Bir öğenin İZİN VERİLEN öğün penceresi — sınıflandırılamıyorsa (kafe,
/// belirsiz başlık) null.
///
/// Bu pencere ÜST SINIRDIR: optimizasyon daha DAR bir tercih uygulayabilir
/// (ör. öğle yemeğini 11:00 yerine 11:30'dan başlatmak) ama bu pencerenin
/// DIŞINA çıkamaz — çıkarsa [planWarningsFor] kendi çıktımızı uyarı olarak
/// işaretler. Bkz. test/domain/optimizer_rules_test.dart.
({int start, int end})? mealWindowMinutesFor(TimelineItem item) {
  final kind = _classifyMeal(item);
  if (kind == null) return null;
  final window = _kMealWindows[kind];
  if (window == null) return null; // kafe = penceresiz (esnek)
  return (start: window.startMinutes, end: window.endMinutes);
}

/// Bir gün için tespit edilen uyarıları döner. Boş liste = plan temiz.
List<PlanWarning> planWarningsFor(DayPlan day) {
  final warnings = <PlanWarning>[];
  final durations = _effectiveDurations(day);

  // 1) Zaman çakışması — sıraya bağımsız, her iki-item için karşılıklı
  // kontrol. Öncelikle "aynı dakika veya üst üste" durumu; sonra 15dk
  // buffer ihlali.
  for (var i = 0; i < day.items.length; i++) {
    final a = day.items[i];
    final aStart = _startMinutes(a);
    if (aStart == null) continue;
    final aEnd = aStart + (durations[a.id] ?? _duration(a));
    for (var j = i + 1; j < day.items.length; j++) {
      final b = day.items[j];
      final bStart = _startMinutes(b);
      if (bStart == null) continue;
      final bEnd = bStart + (durations[b.id] ?? _duration(b));
      final gap = _requiredGap(a, b);
      // Aralarında en azından `gap` dakika olması bekleniyor.
      final overlap = _overlapMinutes(aStart, aEnd, bStart, bEnd, gap);
      if (overlap > 0) {
        warnings.add(PlanWarning(
          activityId: b.id,
          conflictingActivityId: a.id,
          kind: PlanWarningKind.timeConflict,
          message: '${a.title} ile ${b.title} saatleri çakışıyor '
              '($overlap dk yakınlık).',
        ));
      }
    }
  }

  // 2) Yemek penceresi ihlali.
  for (final item in day.items) {
    final meal = _classifyMeal(item);
    if (meal == null || meal == _MealKind.cafe) continue;
    final start = _startMinutes(item);
    if (start == null) continue;
    final window = _kMealWindows[meal]!;
    if (start < window.startMinutes || start >= window.endMinutes) {
      warnings.add(PlanWarning(
        activityId: item.id,
        kind: PlanWarningKind.mealOutsideWindow,
        message: '${item.title} normalde '
            '${_fmt(window.startMinutes)}–${_fmt(window.endMinutes)} '
            'arası yenir.',
      ));
    }
  }

  return warnings;
}

/// Activity id → uyarı seti (aynı item birden çok uyarı taşıyabilir).
Map<String, List<PlanWarning>> warningsByActivity(DayPlan day) {
  final map = <String, List<PlanWarning>>{};
  for (final w in planWarningsFor(day)) {
    map.putIfAbsent(w.activityId, () => []).add(w);
    if (w.conflictingActivityId != null) {
      map.putIfAbsent(w.conflictingActivityId!, () => []).add(w);
    }
  }
  return map;
}

int? _startMinutes(TimelineItem item) {
  final raw = item.fixedStartTime ?? item.time ?? item.scheduledTime;
  return _parseHhmm(raw);
}

int? _parseHhmm(String? value) {
  if (value == null) return null;
  final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final mi = int.parse(m.group(2)!);
  if (h > 23 || mi > 59) return null;
  return h * 60 + mi;
}

int _duration(TimelineItem item) {
  final d = item.durationMin;
  if (d != null && d > 0) return d;
  // Süre yoksa yemek 60, diğer 90 dakika varsay — kaba ama makul.
  return _isMealTitle(item) ? 60 : 90;
}

/// `durationMin` taşımayan aktiviteler için etkin süreyi planın kendi saat
/// aralığından çıkarır.
///
/// **Why:** Sabit 90 dk varsayımı olmayan çakışmalar uyduruyordu. Üretici
/// aktiviteleri ardışık saatlere diziyor ama `durationMin` yazmıyor; bu yüzden
/// 02:00 havaalanı inişi "03:30'a kadar sürüyor" sanılıp 03:15 otele
/// transferiyle çakışıyor görünüyordu. Aynı şekilde dönüş günündeki
/// check-out → transfer → havaalanı zinciri (30 dk aralıklı) sahte çakışma
/// üretiyordu.
///
/// **How to apply:** Süre bilinmiyorsa uydurulmaz — bir sonraki aktiviteye
/// kalan boşluğa sığdırılır. Bilinmeyen süre asla tek başına çakışma
/// doğurmaz. Gerçek çakışmalar hâlâ yakalanır: aynı/örtüşen başlangıç
/// saatlerinde boşluk sıfır veya negatiftir, ayrıca *bildirilmiş*
/// `durationMin` değerleri olduğu gibi kullanılır.
Map<String, int> _effectiveDurations(DayPlan day) {
  final timed = <({TimelineItem item, int start})>[];
  for (final item in day.items) {
    final start = _startMinutes(item);
    if (start != null) timed.add((item: item, start: start));
  }
  timed.sort((a, b) => a.start.compareTo(b.start));

  final result = <String, int>{};
  for (var i = 0; i < timed.length; i++) {
    final current = timed[i];
    final declared = current.item.durationMin;
    if (declared != null && declared > 0) {
      result[current.item.id] = declared;
      continue;
    }
    final fallback = _duration(current.item);
    if (i + 1 >= timed.length) {
      result[current.item.id] = fallback;
      continue;
    }
    final next = timed[i + 1];
    final spacing = next.start - current.start;
    final gap = _requiredGap(current.item, next.item);
    final available = spacing - gap;
    result[current.item.id] = available <= 0 ? 0 : available.clamp(0, fallback);
  }
  return result;
}

int _requiredGap(TimelineItem a, TimelineItem b) {
  final anyMeal = _isMealTitle(a) || _isMealTitle(b);
  return anyMeal ? _kMealGapMinutes : _kTransitionMinutes;
}

int _overlapMinutes(int aStart, int aEnd, int bStart, int bEnd, int gap) {
  // İki aralık arasında istenen en az mesafe = gap.
  // Overlap = max(0, min(aEnd, bEnd) + gap - max(aStart, bStart)).
  final earliestEnd = aEnd < bEnd ? aEnd : bEnd;
  final latestStart = aStart > bStart ? aStart : bStart;
  final diff = (earliestEnd + gap) - latestStart;
  return diff > 0 ? diff : 0;
}

_MealKind? _classifyMeal(TimelineItem item) {
  final title = item.title.toLowerCase();
  bool has(String needle) => title.contains(needle);

  if (has('kahvaltı') || has('breakfast') || has('brunch')) {
    // brunch aslında 10-13 arasında yenir; sadeleştirmek için breakfast
    // penceresine (06-11) katalım — dışına çıkarsa yine uyarır.
    return _MealKind.breakfast;
  }
  if (has('öğle') || has('lunch')) {
    return _MealKind.lunch;
  }
  if (has('akşam') || has('dinner')) {
    return _MealKind.dinner;
  }
  if (has('kafe') || has('cafe') || has('çay')) {
    return _MealKind.cafe;
  }
  // Type meal ama title'da anahtar yok → sınıflandıramadık, pencere kontrolü
  // yapma. (kind == meal olduğu ama başlık farklı gelen özel durumlar.)
  return null;
}

bool _isMealTitle(TimelineItem item) {
  if (item.kind == TimelineItemKind.meal) return true;
  return _classifyMeal(item) != null;
}

String _fmt(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}
