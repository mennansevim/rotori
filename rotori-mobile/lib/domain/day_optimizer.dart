// TypeScript packages/shared/src/dayOptimizer.ts'in Dart karşılığı.
//
// Bir günü saat + coğrafi açıdan optimize eder:
// 1. Sabit ulaşım/otel kalemleri (transport, hotel) yerinde kalır.
// 2. activity + meal kalemleri lat/lng varsa nearest-neighbor ile sıralanır.
//    İlk nokta: en kuzeydeki (sabah erken için).
// 3. Yemek kalemleri öğle (12:30) ve akşam (19:00) civarına yakınsa orada,
//    değilse sırayı bozmadan yerleştirilir.
// 4. Saat yeniden atanır: activity 1.5 saat, meal 1 saat, transport 0.5 saat.

import 'dart:math';

import 'japan_suggestions.dart' show isTimeLocked;
import 'types.dart';

/// 'HH:mm' → gün başından dakika. Geçersiz/boş → -1.
int timeToMin(String? t) {
  if (t == null || t.isEmpty) return -1;
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t);
  if (m == null) return -1;
  return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}

/// Dakika → 'HH:mm' (00-23 saat, 00-59 dakika ile kırpılır).
String minToTime(int min) {
  final h = min ~/ 60;
  final m = min % 60;
  final hc = h < 0 ? 0 : (h > 23 ? 23 : h);
  final mc = m < 0 ? 0 : (m > 59 ? 59 : m);
  return '${hc.toString().padLeft(2, '0')}:${mc.toString().padLeft(2, '0')}';
}

/// Item'ların GÖRSEL SIRASINI korur, yalnızca saatleri o sıraya göre yeniden
/// dağıtır: mevcut saatler artan sıraya konur ve yukarıdan aşağıya atanır.
/// Sürükle-bırak ile sıra değişince saatlerin de kronolojik kalması için.
/// Saatsiz kalemler olduğu gibi bırakılır.
///
/// TS testleri (packages/shared/src/__tests__/resequenceTimes.test.ts) birebir
/// Dart'ta korunuyor — davranış farkı YOKTUR.
List<TimelineItem> resequenceTimes(List<TimelineItem> items) {
  final sortedTimes = items
      .map((it) => it.time ?? it.scheduledTime)
      .where((t) => timeToMin(t) >= 0)
      .cast<String>()
      .toList()
    ..sort((a, b) => timeToMin(a).compareTo(timeToMin(b)));

  if (sortedTimes.isEmpty) return items;

  var ti = 0;
  return items.map((it) {
    final cur = it.time ?? it.scheduledTime;
    if (timeToMin(cur) < 0) return it; // saatsiz — dokunma
    final t = sortedTimes[ti++];
    if (t == it.time && t == it.scheduledTime) return it;
    return it.copyWith(time: t, scheduledTime: t);
  }).toList();
}

// ---------------------------------------------------------------------------
// optimizeDayItems — geo + anchor + meal-slot mantığı (TS 1:1 portu)
// ---------------------------------------------------------------------------

double _distance(TimelineItem a, TimelineItem b) {
  if (a.lat == null || a.lng == null || b.lat == null || b.lng == null) {
    return double.infinity;
  }
  final dLat = a.lat! - b.lat!;
  final dLng = a.lng! - b.lng!;
  return sqrt(dLat * dLat + dLng * dLng);
}

List<TimelineItem> _nearestNeighborOrder(
  List<TimelineItem> items, [
  int startIdx = 0,
]) {
  if (items.length <= 2) return [...items];
  final remaining = [...items];
  final ordered = <TimelineItem>[remaining.removeAt(startIdx)];
  while (remaining.isNotEmpty) {
    final last = ordered.last;
    var bestIdx = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < remaining.length; i++) {
      final d = _distance(last, remaining[i]);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    ordered.add(remaining.removeAt(bestIdx));
  }
  return ordered;
}

int _durationFor(TimelineItem item) {
  final d = item.durationMin;
  if (d != null && d > 0) return d;
  if (item.kind == TimelineItemKind.meal) return 60;
  if (item.kind == TimelineItemKind.transport) return 30;
  if (item.kind == TimelineItemKind.hotel) return 30;
  return 90;
}

/// Saate göre kararlı (stable) sıralama — saatsizler sona.
/// (JS Array.sort stable'dır; Dart List.sort değildir, indeksle sabitlenir.)
List<TimelineItem> _sortByTimeStable(List<TimelineItem> items) {
  final indexed = items.asMap().entries.toList()
    ..sort((ea, eb) {
      final ta = timeToMin(ea.value.time ?? ea.value.scheduledTime);
      final tb = timeToMin(eb.value.time ?? eb.value.scheduledTime);
      int cmp;
      if (ta < 0 && tb < 0) {
        cmp = 0;
      } else if (ta < 0) {
        cmp = 1;
      } else if (tb < 0) {
        cmp = -1;
      } else {
        cmp = ta - tb;
      }
      return cmp != 0 ? cmp : ea.key - eb.key;
    });
  return indexed.map((e) => e.value).toList();
}

/// Bir günün item'larını saat ve coğrafi sıraya göre yeniden düzenler.
/// Mevcut item id'lerini korur — sadece time/scheduledTime günceller.
List<TimelineItem> optimizeDayItems(List<TimelineItem> items) {
  if (items.length <= 1) return items;

  // Sabit kalemler — kendi saatlerini tutar, yeniden dizilmez:
  //  • transport / hotel (uçuş, check-in vb.)
  //  • SAATLİ GİRİŞ aktiviteleri (teamLab, Disneyland, USJ) ve kullanıcının
  //    elle kilitlediği öğeler. Bunların bileti belirli bir saate kesilir;
  //    hava durumuna göre yeniden dizerken oynatmak bileti geçersiz kılar.
  final anchors = <TimelineItem>[];
  final flexible = <TimelineItem>[];
  for (final it in items) {
    if (it.kind == TimelineItemKind.transport ||
        it.kind == TimelineItemKind.hotel ||
        isTimeLocked(it)) {
      anchors.add(it);
    } else {
      flexible.add(it);
    }
  }

  // Flexible'ları coğrafi olarak sırala (lat/lng varsa).
  final haveCoords =
      flexible.where((f) => f.lat != null && f.lng != null).length;
  List<TimelineItem> ordered;
  if (haveCoords >= 2 && haveCoords == flexible.length) {
    // En kuzeydeki noktadan başla (sabah erken, daha iyi tempo).
    var startIdx = 0;
    var maxLat = double.negativeInfinity;
    for (var i = 0; i < flexible.length; i++) {
      final lat = flexible[i].lat;
      if (lat != null && lat > maxLat) {
        maxLat = lat;
        startIdx = i;
      }
    }
    ordered = _nearestNeighborOrder(flexible, startIdx);
  } else {
    // Koordinat yoksa mevcut zaman sırasını koru.
    ordered = _sortByTimeStable(flexible);
  }

  // Anchor'ları saate göre sırala; kendi saatlerinde tut.
  // Strateji: anchor'lar zaman çizelgesine eklenir, flexible'lar aralara dolar.
  final anchorsSorted = _sortByTimeStable(anchors);

  // Akıllı zaman dağıtımı:
  // Sabah 09:00 başla. Anchor'ın kendi saati varsa onu kullan, sonraki flexible
  // o saatten sonra yerleştir.
  final out = <TimelineItem>[];
  var cursorMin = 9 * 60; // 09:00 default
  var anchorIdx = 0;

  // En erken anchor 09:00'dan önceyse oradan başla (örn. 06:00 uçuş).
  final firstAnchorMin = anchorsSorted.isNotEmpty
      ? timeToMin(anchorsSorted[0].time ?? anchorsSorted[0].scheduledTime)
      : -1;
  if (firstAnchorMin >= 0 && firstAnchorMin < cursorMin) {
    cursorMin = firstAnchorMin;
  }

  final flexQueue = [...ordered];
  var lastMealMin = -1;

  while (flexQueue.isNotEmpty || anchorIdx < anchorsSorted.length) {
    final anchor =
        anchorIdx < anchorsSorted.length ? anchorsSorted[anchorIdx] : null;
    final anchorMin =
        anchor != null ? timeToMin(anchor.time ?? anchor.scheduledTime) : -1;

    if (anchor != null && anchorMin >= 0 && anchorMin <= cursorMin) {
      // Anchor sırası geldi — kendi saatini kullan.
      out.add(anchor.copyWith(
        time: minToTime(anchorMin),
        scheduledTime: minToTime(anchorMin),
      ));
      cursorMin = anchorMin + _durationFor(anchor);
      anchorIdx++;
      continue;
    }

    if (flexQueue.isEmpty) {
      // Sadece geleceğe ait anchor kaldı — onu da ekle.
      if (anchor != null) {
        final t = minToTime(anchorMin >= 0 ? anchorMin : cursorMin);
        out.add(anchor.copyWith(time: t, scheduledTime: t));
        cursorMin =
            (anchorMin >= 0 ? anchorMin : cursorMin) + _durationFor(anchor);
        anchorIdx++;
      }
      continue;
    }

    // Sıradaki flexible'ı yerleştir.
    var next = flexQueue.removeAt(0);

    // Yemek slot tercihi: öğle (12:00-13:30) ve akşam (18:30-20:00).
    if (next.kind == TimelineItemKind.meal) {
      final lunchOk = lastMealMin < 0 && cursorMin >= 11 * 60 + 30;
      final dinnerOk = lastMealMin > 0 && cursorMin >= 17 * 60 + 30;
      if (!lunchOk && !dinnerOk && cursorMin < 11 * 60 + 30) {
        // Çok erken — flexible'ları yeniden sırala ki meal sonra gelsin.
        final swap =
            flexQueue.indexWhere((f) => f.kind != TimelineItemKind.meal);
        if (swap >= 0) {
          flexQueue.insert(0, next);
          next = flexQueue.removeAt(swap + 1);
        }
      }
    }

    // Anchor'a çok yakınsa anchor'ı önce ekle.
    if (anchor != null &&
        anchorMin >= 0 &&
        cursorMin + _durationFor(next) > anchorMin) {
      out.add(anchor.copyWith(
        time: minToTime(anchorMin),
        scheduledTime: minToTime(anchorMin),
      ));
      cursorMin = anchorMin + _durationFor(anchor);
      anchorIdx++;
      flexQueue.insert(0, next);
      continue;
    }

    out.add(next.copyWith(
      time: minToTime(cursorMin),
      scheduledTime: minToTime(cursorMin),
    ));
    if (next.kind == TimelineItemKind.meal) lastMealMin = cursorMin;
    cursorMin += _durationFor(next) + 30; // 30 dk geçiş

    // Öğle aralığına ulaştıysak yemek zorla.
    if (cursorMin >= 12 * 60 + 30 && lastMealMin < 0) {
      final mealIdx =
          flexQueue.indexWhere((f) => f.kind == TimelineItemKind.meal);
      if (mealIdx > 0) {
        flexQueue.insert(0, flexQueue.removeAt(mealIdx));
      }
    }
  }

  return out;
}

DayPlan optimizeDay(DayPlan day) =>
    day.copyWith(items: optimizeDayItems(day.items));
