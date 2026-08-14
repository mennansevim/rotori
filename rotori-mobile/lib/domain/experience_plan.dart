// Bir deneyim rehberini plana yerleştirme.
//
// **Why ayrı bir yol:** `must_see_suggestions.dart`'taki `addHighlightsToPlan`
// yerleri 09:00–20:00 penceresindeki BOŞLUKLARA koyuyor. Bu deneyimlerin
// üçü (USJ, Disneyland, DisneySea) 10–13 saat sürüyor — hiçbir boşluğa
// sığmazlar, motor hepsini "yerleştirilemedi" diye geri çevirirdi.
//
// Bu yüzden model farklı: deneyim bir aktivite DEĞİL, günün kendisidir.
// Kullanıcı bir gün seçer, o gün deneyime ayrılır.

import 'destination_profiles.dart' show getDestinationForDate;
import 'experience_guides.dart';
import 'types.dart';

/// Deneyim yerleştirilebilecek bir gün.
class ExperienceDayOption {
  const ExperienceDayOption({
    required this.day,
    required this.city,
    required this.replaceableCount,
    required this.lockedCount,
  });

  final DayPlan day;

  /// Günün şehri (destinasyondan çözülür).
  final String city;

  /// Devralma sırasında SİLİNECEK durak sayısı.
  final int replaceableCount;

  /// Korunacak kilitli durak sayısı (uçuş, otel check-in, kullanıcı kilidi).
  final int lockedCount;
}

/// Bu deneyimin yerleştirilebileceği günler.
///
/// Yalnızca şehri eşleşen günler döner. Eşleşme gevşek: rehberin şehri
/// "Toyosu, Tokyo" gibi bir semt+şehir olabilir, günün şehri ise "Tokyo".
/// İlk ve son gün hariç tutulur — onlar uçuşa bağlı (bkz.
/// `must_see_suggestions.dart` aynı kuralı uygular).
List<ExperienceDayOption> experienceDayOptions(
  Trip trip,
  ExperienceGuide guide,
) {
  final dests = [...trip.preferences.destinations]
    ..sort((a, b) => a.order.compareTo(b.order));
  final guideCity = guide.city.toLowerCase();

  final out = <ExperienceDayOption>[];
  for (final day in trip.days) {
    if (day.dayNumber == 1 || day.dayNumber == trip.days.length) continue;
    final city = getDestinationForDate(dests, day.date)?.city ?? '';
    if (city.isEmpty) continue;
    if (!guideCity.contains(city.toLowerCase())) continue;

    var locked = 0;
    var replaceable = 0;
    for (final item in day.items) {
      if (item.isFixed) {
        locked++;
      } else {
        replaceable++;
      }
    }
    out.add(ExperienceDayOption(
      day: day,
      city: city,
      replaceableCount: replaceable,
      lockedCount: locked,
    ));
  }
  return out;
}

/// `'10–12 saat'` → 600. Ayrıştırılamazsa null.
///
/// Katalog insan için yazılmış serbest metin tutuyor; yapısal bir süre alanı
/// yok. İlk sayıyı (alt sınır) ve birimi okuyoruz — "2,5 saat" gibi ondalık
/// da desteklenir. Alt sınırı almak bilinçli: günü olduğundan uzun
/// göstermektense kısa göstermek daha güvenli.
int? parseExperienceMinutes(String text) {
  final match = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(text);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!.replaceAll(',', '.'));
  if (value == null || value <= 0) return null;

  final lower = text.toLowerCase();
  final isHours = lower.contains('saat') || lower.contains('hour');
  final minutes = isHours ? value * 60 : value;
  if (minutes < 15 || minutes > 16 * 60) return null;
  return minutes.round();
}

/// Devralma sonucu.
class ExperienceDayResult {
  const ExperienceDayResult({
    required this.dayNumber,
    required this.removed,
    required this.keptLocked,
  });

  final int dayNumber;

  /// Silinen durak sayısı.
  final int removed;

  /// Korunan kilitli durak sayısı.
  final int keptLocked;
}

/// [dayNumber] gününü [guide] deneyimine ayırır.
///
/// Kilitli duraklar KORUNUR — kullanıcı bileti almış olabilir, uçuş/otel
/// saatleri plan verisinden geliyor olabilir. Geri kalanlar silinir ve
/// yerlerine tek bir tam-gün aktivitesi yazılır.
///
/// Deneyim ayrıca `preferences.mustSee`'ye eklenir: plan ileride yeniden
/// üretilirse üretici bunu öne alır.
ExperienceDayResult? applyExperienceToDay({
  required Trip trip,
  required ExperienceGuide guide,
  required int dayNumber,
  required String title,
  required String description,
  required String durationText,
  String startTime = '09:00',
}) {
  final index = trip.days.indexWhere((d) => d.dayNumber == dayNumber);
  if (index < 0) return null;
  final day = trip.days[index];

  final locked = day.items.where((i) => i.isFixed).toList(growable: false);
  final removed = day.items.length - locked.length;

  final activity = TimelineItem(
    id: 'experience-${guide.id}-$dayNumber',
    title: title,
    description: description,
    time: startTime,
    scheduledTime: startTime,
    durationMin: parseExperienceMinutes(durationText),
    kind: TimelineItemKind.activity,
  );

  // Kilitli duraklar saatleriyle kalır; deneyim onların arasına değil,
  // listenin başına yazılır ve gün sıralaması saate göre düzelir.
  final items = [...locked, activity]..sort((a, b) {
      final ta = _minutes(a.time ?? a.scheduledTime) ?? 0;
      final tb = _minutes(b.time ?? b.scheduledTime) ?? 0;
      return ta.compareTo(tb);
    });

  day
    ..items = items
    ..theme = title;

  if (!trip.preferences.mustSee.contains(guide.title)) {
    trip.preferences.mustSee.add(guide.title);
  }

  return ExperienceDayResult(
    dayNumber: dayNumber,
    removed: removed,
    keptLocked: locked.length,
  );
}

int? _minutes(String? hhmm) {
  if (hhmm == null) return null;
  final parts = hhmm.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}
