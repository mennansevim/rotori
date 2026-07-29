// Gün planı saat/sıralama mantığı — saf (UI'dan bağımsız) fonksiyonlar.
// plan_viewer_screen düzenleme modu bunları kullanır; test edilebilir olsun
// diye ayrı tutulur.

import 'types.dart';

/// "HH:mm" → dakika (0..1439). Geçersizse null.
int? timeToMinutes(String? t) {
  if (t == null || t.isEmpty) return null;
  final parts = t.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// Dakika (0..1439) → "HH:mm".
String minutesToTime(int mins) {
  final m = mins.clamp(0, 24 * 60 - 1);
  final h = m ~/ 60;
  final mm = m % 60;
  return '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
}

/// Bir item'ın hem `time` hem `scheduledTime` alanına yazar.
void _setItemTime(TimelineItem it, int mins) {
  final t = minutesToTime(mins);
  it.time = t;
  it.scheduledTime = t;
}

/// Bir günün item saatlerini mevcut sıraya göre makul aralıklarla yeniden
/// yazar (SÜRÜKLE-BIRAK sonrası kullanılır). İlk item'ın saati (yoksa 09:00)
/// çıpa alınır; her durak, süresine (durationMin) göre + 15 dk geçiş payıyla
/// bir sonrakine aktarılır ve 15 dk'ya yuvarlanır.
///
/// Listeyi yerinde günceller ve geri döndürür.
List<TimelineItem> redistributeDayTimes(List<TimelineItem> items) {
  if (items.isEmpty) return items;
  var cursor =
      timeToMinutes(items.first.time ?? items.first.scheduledTime) ?? 9 * 60;
  for (final it in items) {
    _setItemTime(it, cursor);
    final dur = (it.durationMin ?? 90).clamp(30, 240);
    var gap = dur + 15; // aktivite + kısa geçiş payı
    gap = ((gap + 14) ~/ 15) * 15; // 15 dk'ya yuvarla
    cursor += gap;
    if (cursor >= 24 * 60) cursor = 24 * 60 - 1;
  }
  return items;
}

/// Kullanıcı [index]'teki durağın saatini elle [newMinutes] yaptı.
/// SADECE o durağın saati değişir (kullanıcı iradesine saygı) ve liste saate
/// göre STABLE biçimde yeniden sıralanır. Diğer durakların saatleri KORUNUR.
///
/// Listeyi yerinde günceller ve geri döndürür.
List<TimelineItem> applyManualTimeEdit(
  List<TimelineItem> items,
  int index,
  int newMinutes,
) {
  if (index < 0 || index >= items.length) return items;
  _setItemTime(items[index], newMinutes);
  _stableSortByTime(items);
  return items;
}

/// Yeni bir durağı saatine göre doğru konuma ekler (STABLE). Diğer saatler
/// korunur. Listeyi yerinde günceller ve geri döndürür.
List<TimelineItem> insertItemSorted(
  List<TimelineItem> items,
  TimelineItem item,
) {
  items.add(item);
  _stableSortByTime(items);
  return items;
}

/// Saate göre stable sıralama (eşit saatlerde mevcut sıra korunur).
void _stableSortByTime(List<TimelineItem> items) {
  final indexed = [
    for (var i = 0; i < items.length; i++) (i, items[i]),
  ];
  indexed.sort((a, b) {
    final ma = timeToMinutes(a.$2.time ?? a.$2.scheduledTime) ?? 0;
    final mb = timeToMinutes(b.$2.time ?? b.$2.scheduledTime) ?? 0;
    if (ma != mb) return ma.compareTo(mb);
    return a.$1.compareTo(b.$1); // stable: orijinal index
  });
  final sorted = [for (final e in indexed) e.$2];
  items
    ..clear()
    ..addAll(sorted);
}
