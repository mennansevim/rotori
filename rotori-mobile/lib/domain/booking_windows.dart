// Bilet açılış pencereleri ve plan üzerindeki tetiklenen uyarıların tespiti.
//
// USJ Express Pass ~2 ay, Tokyo Disney Premier Access / DPA ~2 ay,
// Shinkansen (Smart-EX) 1 ay (30 gün) öncesinden satışa açılır.
// Bu bilgi kullanıcıya "Planı yeniden oluştur" sonrasında popup ile duyurulur;
// kabul ederse ilgili tarih için yerel bildirim kurulur.

import 'types.dart';

/// Bir bilet/park için açılış penceresi tanımı.
class BookingWindow {
  const BookingWindow({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.opensBeforeDays,
    required this.icon,
    required this.tip,
    required this.reminderNoonHour,
  });

  final String id;

  /// Popup başlığı — i18n anahtarı (örn. 'bw.usj.title').
  final String title;

  /// Kısa açıklama — i18n anahtarı (örn. 'bw.usj.subtitle').
  final String subtitle;

  /// Bilet satışa kaç gün önce açılıyor (yaklaşık).
  final int opensBeforeDays;

  /// Popup ve reminder ekranındaki emoji/kısa etiket.
  final String icon;

  /// Kullanıcıya faydalı ipucu — i18n anahtarı (örn. 'bw.usj.tip').
  final String tip;

  /// Bildirimin gün içinde tetikleneceği saat (24h). 09:00 default.
  final int reminderNoonHour;
}

const _kUsj = BookingWindow(
  id: 'usj-express',
  title: 'bw.usj.title',
  subtitle: 'bw.usj.subtitle',
  opensBeforeDays: 60,
  icon: '🎢',
  tip: 'bw.usj.tip',
  reminderNoonHour: 9,
);

const _kDisney = BookingWindow(
  id: 'tokyo-disney',
  title: 'bw.disney.title',
  subtitle: 'bw.disney.subtitle',
  opensBeforeDays: 60,
  icon: '🏰',
  tip: 'bw.disney.tip',
  reminderNoonHour: 9,
);

const _kShinkansen = BookingWindow(
  id: 'shinkansen-smartex',
  title: 'bw.shinkansen.title',
  subtitle: 'bw.shinkansen.subtitle',
  opensBeforeDays: 30,
  icon: '🚄',
  tip: 'bw.shinkansen.tip',
  reminderNoonHour: 9,
);

/// Tespit edilen uyarı — hangi pencere, hangi gerçek tarihte açılıyor.
class BookingAlert {
  const BookingAlert({
    required this.window,
    required this.opensOn,
    required this.eventOn,
    required this.reason,
  });

  final BookingWindow window;

  /// Biletin satışa açıldığı gün (YYYY-MM-DD).
  final DateTime opensOn;

  /// Trip'te ilgili etkinliğin gerçekleşeceği gün.
  final DateTime eventOn;

  /// Neden tetiklendiğini kullanıcıya gösteren kısa etiket (planda karşılaşılan başlık).
  final String reason;
}

/// Trip'i tarayıp aktif uyarıları döndürür. Bugünden önce açılmış (yani süresi
/// geçmiş) pencereleri de dahil eder — kullanıcı uyarısı ayrı gösterir.
List<BookingAlert> detectBookingAlerts(Trip trip, {DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());
  final out = <BookingAlert>[];
  final seen = <String>{};

  DateTime? parseDay(String s) {
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  void addIfNeeded(BookingWindow w, DateTime eventOn, String reason) {
    if (seen.contains(w.id)) return;
    seen.add(w.id);
    final opens = eventOn.subtract(Duration(days: w.opensBeforeDays));
    // Etkinlik geçmişte kaldıysa uyarma.
    if (eventOn.isBefore(today)) return;
    out.add(BookingAlert(
      window: w,
      opensOn: _dateOnly(opens),
      eventOn: _dateOnly(eventOn),
      reason: reason,
    ));
  }

  // Trip günlerini gez, item title/city üzerinden anahtar kelime ara.
  for (final day in trip.days) {
    final dayDate = parseDay(day.date);
    for (final item in day.items) {
      final t = item.title.toLowerCase();
      final ref = dayDate ?? _dayIndexToDate(trip, day.dayNumber) ?? today;

      if (t.contains('universal studios') || t.contains('usj')) {
        addIfNeeded(_kUsj, ref, item.title);
      }
      if (t.contains('disney')) {
        addIfNeeded(_kDisney, ref, item.title);
      }
      if (t.contains('shinkansen') || t.contains('nozomi') || t.contains('sakura')) {
        addIfNeeded(_kShinkansen, ref, item.title);
      }
    }
  }

  // Trip destinations üzerinden Shinkansen: Tokyo↔Kyoto/Osaka geçişi varsa.
  if (!seen.contains(_kShinkansen.id)) {
    final cities = trip.preferences.destinations
        .map((d) => d.city.toLowerCase())
        .toList();
    final hasTokyo = cities.any((c) => c.contains('tokyo'));
    final hasKansai = cities.any((c) => c.contains('kyoto') || c.contains('osaka'));
    if (hasTokyo && hasKansai) {
      final tokyo = trip.preferences.destinations
          .firstWhere((d) => d.city.toLowerCase().contains('tokyo'),
              orElse: () => trip.preferences.destinations.first);
      final ref = parseDay(tokyo.departureDate) ??
          parseDay(trip.preferences.travelDates.start) ??
          today;
      addIfNeeded(_kShinkansen, ref, 'bw.reason.tokyoKansai');
    }
  }

  return out;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime? _dayIndexToDate(Trip trip, int dayNumber) {
  final start = trip.preferences.travelDates.start;
  if (start.isEmpty) return null;
  try {
    return DateTime.parse(start).add(Duration(days: dayNumber - 1));
  } catch (_) {
    return null;
  }
}
