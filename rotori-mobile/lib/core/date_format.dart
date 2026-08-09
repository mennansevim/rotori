// Tarih biçimlendiricileri — UI'dan bağımsız, saf fonksiyonlar.
//
// Kaynak: features/planner/steps/welcome_step.dart (wizard sökülürken buraya
// taşındı; testleri test/core/date_format_test.dart altında sürüyor).

import 'l10n.dart' show AppLang;

/// YYYY-MM-DD.
String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// "23 Ağu Paz" — TR kısa tarih.
String formatTrShortDate(DateTime d) =>
    '${d.day} ${_trShortMonths[d.month]} ${_trShortWeekdays[d.weekday]}';

/// "23 Aug Sun" — EN kısa tarih.
String formatEnShortDate(DateTime d) =>
    '${_enShortWeekdays[d.weekday]} ${d.day} ${_enShortMonths[d.month]}';

/// Dile göre kısa tarih. [ymd] ayrıştırılamazsa olduğu gibi döner —
/// boş girdide boş string.
String formatShortDate(String ymd, AppLang lang) {
  final d = DateTime.tryParse(ymd);
  if (d == null) return ymd;
  return lang == AppLang.en ? formatEnShortDate(d) : formatTrShortDate(d);
}

/// Google Flights derin bağlantısı.
String googleFlightsUrl({
  required String from,
  required String toIata,
  required DateTime start,
  required DateTime end,
}) {
  final q = 'Flights from $from to $toIata on ${isoDate(start)} '
      'through ${isoDate(end)}';
  return 'https://www.google.com/travel/flights?q=${Uri.encodeComponent(q)}';
}

const _trShortMonths = [
  '', 'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
  'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
];

const _trShortWeekdays = [
  '', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz',
];

const _enShortMonths = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _enShortWeekdays = [
  '', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
];
