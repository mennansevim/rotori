// TypeScript packages/shared/src/dayOptimizer.ts'in Dart karşılığı.
//
// MVP kapsamı:
//   - timeToMin / minToTime yardımcıları
//   - resequenceTimes: sürükle-bırak sonrası GÖRSEL sırayı korur, mevcut
//     saatleri kronolojik yeniden dağıtır. TS testi birebir Dart'ta korunur.
//
// TODO(Faz 3b): optimizeDayItems (geo + anchor + meal-slot mantığı) portu.

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
