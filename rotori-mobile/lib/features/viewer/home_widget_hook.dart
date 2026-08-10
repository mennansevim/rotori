// iOS Home Screen widget'ına "Sıradaki Aktivite" verisi gönderir.
//
// Kurulum: docs/IOS_WIDGET_SETUP.md — Xcode Widget Extension target'ı ve
// App Group (`group.com.mennansevim.rotori`) manuel olarak eklenir. Bu Dart tarafı
// bugün derler ve çalışır; native target eksikse `updateWidget` çağrısı
// sessizce başarısız olur (try/catch), akış bozulmaz.
//
// Web derlemesi: kIsWeb gate'i + try/catch — paket web'de no-op olarak
// tanımlıdır, buradaki savunma yalın bir güvenlik ağı.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:home_widget/home_widget.dart';

import '../../domain/types.dart';

// Xcode Widget Extension'daki UserDefaults(suiteName:) ile eşleşen App Group.
// Bu sabiti IOS_WIDGET_SETUP.md dokümanı da referans alır.
const String kRotoriAppGroupId = 'group.com.mennansevim.rotori';
const String kRotoriWidgetName = 'RotoriWidget';

/// Widget'a yazılacak "sıradaki aktivite" verisi — pure hesaplamanın çıktısı.
class NextActivity {
  const NextActivity({
    required this.title,
    required this.city,
    required this.tripTitle,
    required this.daysUntilTripStart,
    this.time,
    this.emoji,
  });

  final String title;
  final String? time;
  final String? emoji;
  final String city;
  final int daysUntilTripStart;
  final String tripTitle;
}

/// Bir gezinin "sıradaki" TimelineItem'ını hesaplar — pure, unit-testable.
///
/// Kural (task tanımından birebir):
///  1) Tüm günlerin tüm item'ları arasında `now`'dan (>=) sonra gelen ilki.
///  2) Bulunamazsa aktif günün ilk item'ı.
///  3) Yine yoksa `null`.
///
/// `daysUntilTripStart` her zaman gelecekteki gezi başlangıcına gün farkıdır;
/// gezi başladıysa 0.
NextActivity? computeNextActivity(Trip trip, DateTime now) {
  final days = [...trip.days]..sort((a, b) => a.date.compareTo(b.date));
  if (days.isEmpty) return null;

  final tripStart = DateTime.tryParse(trip.tripStart);
  final daysUntil = tripStart == null
      ? 0
      : (tripStart.isAfter(now)
          ? tripStart.difference(now).inDays
          : 0);

  // 1) İlk gelecekteki item — tarih + saat birleşiminden DateTime kur.
  DateTime? bestDt;
  TimelineItem? bestItem;
  DayPlan? bestDay;
  for (final day in days) {
    final base = DateTime.tryParse(day.date);
    if (base == null) continue;
    for (final item in day.items) {
      final dt = _combineDateAndTime(base, item.time ?? item.scheduledTime);
      if (!dt.isBefore(now) && (bestDt == null || dt.isBefore(bestDt))) {
        bestDt = dt;
        bestItem = item;
        bestDay = day;
      }
    }
  }

  if (bestItem != null) {
    return NextActivity(
      title: bestItem.title,
      time: bestItem.time ?? bestItem.scheduledTime,
      emoji: _kindEmoji(bestItem.kind),
      city: bestDay?.theme ?? '',
      daysUntilTripStart: daysUntil,
      tripTitle: trip.title,
    );
  }

  // 2) Aktif gün (bugüne eşit → yoksa ilk gelecek → yoksa son)
  final activeIdx = _activeDayIndex(days, now);
  final active = days[activeIdx];
  if (active.items.isNotEmpty) {
    final first = active.items.first;
    return NextActivity(
      title: first.title,
      time: first.time ?? first.scheduledTime,
      emoji: _kindEmoji(first.kind),
      city: active.theme,
      daysUntilTripStart: daysUntil,
      tripTitle: trip.title,
    );
  }

  // 3) Hiçbir gün item taşımıyor.
  return null;
}

/// Aktif gün index'i: bugünle eşleşen, yoksa ilk gelecek, yoksa son.
/// (plan_viewer_screen'deki private `_activeDayIndex` ile aynı kural, ama
/// `now`'ı dışarıdan alır — testler için deterministik.)
int _activeDayIndex(List<DayPlan> daysSorted, DateTime now) {
  if (daysSorted.isEmpty) return 0;
  final today = '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
  final exact = daysSorted.indexWhere((d) => d.date == today);
  if (exact >= 0) return exact;
  final future = daysSorted.indexWhere((d) => d.date.compareTo(today) >= 0);
  return future >= 0 ? future : daysSorted.length - 1;
}

/// "HH:MM" saatini gün tarihiyle birleştirir. Saat eksikse günün başlangıcı
/// (00:00) döner — bu, saatsiz item'ların "gün olarak" gelecekte sayılmasına
/// izin verir.
DateTime _combineDateAndTime(DateTime baseDate, String? hhmm) {
  if (hhmm == null || hhmm.isEmpty) return baseDate;
  final parts = hhmm.split(':');
  if (parts.length < 2) return baseDate;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return baseDate;
  return DateTime(baseDate.year, baseDate.month, baseDate.day, h, m);
}

String? _kindEmoji(TimelineItemKind? k) => switch (k) {
      TimelineItemKind.meal => '🍜',
      TimelineItemKind.transport => '🚄',
      TimelineItemKind.hotel => '🏨',
      TimelineItemKind.activity => '📍',
      _ => null,
    };

/// Widget'a "sıradaki aktivite" verisini iter. Web'de veya native target
/// eksik/başarısızsa sessizce no-op'a düşer (try/catch).
class HomeWidgetHook {
  const HomeWidgetHook._();

  /// Anahtarları Xcode Widget Extension'ı ile eşleşen key'ler; kurulum
  /// dokümanı bu key'leri tekrar listeler:
  /// - nextTitle      : String
  /// - nextTime       : String ("HH:MM" veya boş)
  /// - nextEmoji      : String (emoji veya boş)
  /// - nextCity       : String (gün teması / şehir etiketi)
  /// - tripTitle      : String (gezi başlığı)
  /// - daysUntilStart : String (int'in string'i — UserDefaults'ta String tut)
  static Future<void> pushFromTrip(Trip trip) async {
    if (kIsWeb) return;
    try {
      final next = computeNextActivity(trip, DateTime.now());
      await HomeWidget.setAppGroupId(kRotoriAppGroupId);
      await HomeWidget.saveWidgetData<String>('nextTitle', next?.title ?? '');
      await HomeWidget.saveWidgetData<String>('nextTime', next?.time ?? '');
      await HomeWidget.saveWidgetData<String>('nextEmoji', next?.emoji ?? '');
      await HomeWidget.saveWidgetData<String>('nextCity', next?.city ?? '');
      await HomeWidget.saveWidgetData<String>(
        'tripTitle',
        next?.tripTitle ?? trip.title,
      );
      await HomeWidget.saveWidgetData<String>(
        'daysUntilStart',
        '${next?.daysUntilTripStart ?? 0}',
      );
      await HomeWidget.updateWidget(
        name: kRotoriWidgetName,
        iOSName: kRotoriWidgetName,
      );
    } catch (_) {
      // Native widget target'ı yoksa (veya başka bir platform hatası) — sessiz.
    }
  }
}
