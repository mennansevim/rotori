/// Prompt çıktısı `HH:mm` yerel duvar saati; senaryo `date` alanı bunun tarihini
/// verir. Bu yardımcılar tarih+HH:mm'den `DateTime`, DateTime'dan `HH:mm`
/// üretir. Test taraf saatiyle çalışır; zaman dilimi dönüşümü yapılmaz.
library;

int minutesOfDay(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) {
    throw ArgumentError('Beklenen HH:mm: $hhmm');
  }
  final hour = int.parse(parts[0]);
  final minute = int.parse(parts[1]);
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    throw ArgumentError('Geçersiz saat: $hhmm');
  }
  return hour * 60 + minute;
}

String formatHhmm(DateTime time) {
  final hh = time.hour.toString().padLeft(2, '0');
  final mm = time.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

DateTime combineDateAndHhmm(String isoDate, String hhmm) {
  final base = DateTime.parse(isoDate);
  return DateTime(base.year, base.month, base.day)
      .add(Duration(minutes: minutesOfDay(hhmm)));
}
