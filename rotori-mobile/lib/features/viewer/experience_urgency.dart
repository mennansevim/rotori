// Deneyim rehberlerini BİLET ACİLİYETİNE göre kovalara ayırır.
//
// **Why kategori değil aciliyet:** "Tema parkı / dijital sanat" ayrımı
// kullanıcının sorusunu cevaplamıyor. Asıl soru "şimdi ne yapmam lazım" —
// USJ Express Pass'i 60 gün önce almak gerekiyor, teamLab Botanical'ı iki
// hafta kala almak yetiyor. Liste bu sıraya girince kendisi bir yapılacaklar
// listesi hâline geliyor.
//
// **Why serbest metin değil:** `ExperienceGuide.bookingWindow` insan için
// yazılmış bir cümle ("45–60 gün önce kontrol et"). Ondan sayı ayıklamak
// dile bağımlı ve kırılgan olurdu. `BookingWindow.opensBeforeDays` zaten
// yapısal veri — eşleme `reminderWindowId` üzerinden yapılır.

import '../../domain/booking_windows.dart';
import '../../domain/experience_guides.dart';

enum ExperienceUrgency {
  /// 45 gün ve üzeri — geziden çok önce, plan bunun etrafında kurulur.
  early,

  /// 21–44 gün — birkaç hafta önce.
  weeks,

  /// 21 günden az — son haftalarda almak yeterli.
  late_,
}

/// Rehberin bilet penceresinin kaç gün önce açıldığı.
///
/// Eşleşen `BookingWindow` yoksa null — bu durumda rehber en az acil kovaya
/// düşer, çünkü elimizde onu öne çekecek bir kanıt yok.
int? experienceLeadDays(ExperienceGuide guide) {
  final id = guide.reminderWindowId;
  if (id == null) return null;
  return bookingWindowById(id)?.opensBeforeDays;
}

ExperienceUrgency experienceUrgency(ExperienceGuide guide) {
  final days = experienceLeadDays(guide);
  if (days == null) return ExperienceUrgency.late_;
  if (days >= 45) return ExperienceUrgency.early;
  if (days >= 21) return ExperienceUrgency.weeks;
  return ExperienceUrgency.late_;
}

/// Rehberleri aciliyete göre gruplar; kovalar en acilden başlar.
///
/// Kova içinde sıralama: önce uzun lead time (aynı kovada 60 gün, 45'ten
/// önce gelir), sonra başlık — böylece liste her açılışta aynı sırada.
/// Boş kovalar döndürülmez.
List<({ExperienceUrgency urgency, List<ExperienceGuide> guides})>
    groupExperiencesByUrgency([
  List<ExperienceGuide> guides = kExperienceGuides,
]) {
  final buckets = <ExperienceUrgency, List<ExperienceGuide>>{};
  for (final guide in guides) {
    buckets.putIfAbsent(experienceUrgency(guide), () => []).add(guide);
  }

  final out = <({ExperienceUrgency urgency, List<ExperienceGuide> guides})>[];
  for (final urgency in ExperienceUrgency.values) {
    final group = buckets[urgency];
    if (group == null || group.isEmpty) continue;
    group.sort((a, b) {
      final byDays = (experienceLeadDays(b) ?? 0)
          .compareTo(experienceLeadDays(a) ?? 0);
      if (byDays != 0) return byDays;
      return a.title.compareTo(b.title);
    });
    out.add((urgency: urgency, guides: group));
  }
  return out;
}
