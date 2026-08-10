// Bilet açılış pencereleri ve plan üzerindeki tetiklenen uyarıların tespiti.
//
// USJ Express Pass ~2 ay, Tokyo Disney Premier Access / DPA ~2 ay,
// Shinkansen (Smart-EX) 1 ay (30 gün) öncesinden satışa açılır.
// Aynı katalog hem plan taramasında hem Hatırlatmalar ekranındaki sonradan
// ekleme panelinde kullanılır; kabul edilen tarihler yerel bildirime çevrilir.

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
    required this.sourceUrl,
    this.isExactRule = false,
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

  /// Satış zamanının doğrulanacağı resmî kaynak.
  final String sourceUrl;

  /// true: yayımlanmış sabit kural, false: güvenli planlama hedefi.
  final bool isExactRule;

  DateTime saleDateFor(DateTime eventOn) => DateTime(
        eventOn.year,
        eventOn.month,
        eventOn.day,
      ).subtract(Duration(days: opensBeforeDays));
}

const _kUsj = BookingWindow(
  id: 'usj-express',
  title: 'bw.usj.title',
  subtitle: 'bw.usj.subtitle',
  opensBeforeDays: 60,
  icon: '🎢',
  tip: 'bw.usj.tip',
  reminderNoonHour: 9,
  sourceUrl: 'https://www.usj.co.jp/web/en/us/tickets',
);

const _kDisney = BookingWindow(
  id: 'tokyo-disney',
  title: 'bw.disney.title',
  subtitle: 'bw.disney.subtitle',
  opensBeforeDays: 60,
  icon: '🏰',
  tip: 'bw.disney.tip',
  reminderNoonHour: 9,
  sourceUrl:
      'https://faq.tokyodisneyresort.jp/tdr/en/faq_detail.html?body_flg=1&id=21199',
  isExactRule: true,
);

const _kShinkansen = BookingWindow(
  id: 'shinkansen-smartex',
  title: 'bw.shinkansen.title',
  subtitle: 'bw.shinkansen.subtitle',
  opensBeforeDays: 30,
  icon: '🚄',
  tip: 'bw.shinkansen.tip',
  reminderNoonHour: 9,
  sourceUrl: 'https://smart-ex.jp/en/faq/category/detail/?id=459',
  isExactRule: true,
);

const _kTeamLabPlanets = BookingWindow(
  id: 'teamlab-planets',
  title: 'bw.teamlabPlanets.title',
  subtitle: 'bw.teamlabPlanets.subtitle',
  opensBeforeDays: 28,
  icon: '💧',
  tip: 'bw.teamlabPlanets.tip',
  reminderNoonHour: 9,
  sourceUrl: 'https://teamlabplanets.dmm.com/en',
);

const _kTeamLabBorderless = BookingWindow(
  id: 'teamlab-borderless',
  title: 'bw.teamlabBorderless.title',
  subtitle: 'bw.teamlabBorderless.subtitle',
  opensBeforeDays: 28,
  icon: '✨',
  tip: 'bw.teamlabBorderless.tip',
  reminderNoonHour: 9,
  sourceUrl: 'https://www.teamlab.art/e/tokyo/',
);

const _kTeamLabBotanical = BookingWindow(
  id: 'teamlab-botanical',
  title: 'bw.teamlabBotanical.title',
  subtitle: 'bw.teamlabBotanical.subtitle',
  opensBeforeDays: 14,
  icon: '🌿',
  tip: 'bw.teamlabBotanical.tip',
  reminderNoonHour: 9,
  sourceUrl: 'https://www.teamlab.art/e/botanicalgarden/',
);

/// Hatırlatıcı ekranında sunulan hazır seçimler.
const List<BookingWindow> kBookingWindows = [
  _kShinkansen,
  _kDisney,
  _kUsj,
  _kTeamLabPlanets,
  _kTeamLabBorderless,
  _kTeamLabBotanical,
];

BookingWindow? bookingWindowById(String id) {
  for (final window in kBookingWindows) {
    if (window.id == id) return window;
  }
  return null;
}

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
    final opens = w.saleDateFor(eventOn);
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
      if (t.contains('shinkansen') ||
          t.contains('nozomi') ||
          t.contains('sakura')) {
        addIfNeeded(_kShinkansen, ref, item.title);
      }
    }
  }

  // Trip destinations üzerinden Shinkansen: Tokyo↔Kyoto/Osaka geçişi varsa.
  if (!seen.contains(_kShinkansen.id)) {
    final cities =
        trip.preferences.destinations.map((d) => d.city.toLowerCase()).toList();
    final hasTokyo = cities.any((c) => c.contains('tokyo'));
    final hasKansai =
        cities.any((c) => c.contains('kyoto') || c.contains('osaka'));
    if (hasTokyo && hasKansai) {
      final tokyo = trip.preferences.destinations.firstWhere(
          (d) => d.city.toLowerCase().contains('tokyo'),
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
