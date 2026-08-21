// Günün adım sayısı — önce telefonun sağlık verisi, olmazsa plan tahmini.
//
// **Neden katman:** "Rota Panoraması" başlığı gerçek adımı göstermek ister,
// ama sağlık verisi her zaman yoktur: kullanıcı izin vermemiş olabilir, gün
// bugün olmayabilir (geçmiş/gelecek gün için cihazda o güne ait sayaç yoktur),
// web/masaüstü önizlemede platform kanalı hiç bulunmaz. Bu yüzden adım tek bir
// yerden, sırayla denenerek çözülür ve UI hangi kaynaktan geldiğini bilir.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Adımın nereden geldiği — UI bunu "cihazdan" rozetiyle göstermek için kullanır.
enum StepSource {
  /// Telefonun sağlık/hareket sayacından okundu.
  device,

  /// Plandaki tahmin (`DayPlan.stepsEstimate`).
  planEstimate,

  /// Mesafeden türetildi (plan tahmini de yoksa).
  derived,
}

class DaySteps {
  const DaySteps({required this.steps, required this.source});

  final int steps;
  final StepSource source;

  bool get isLive => source == StepSource.device;
}

/// Platformun günlük adım sayacı.
///
/// Varsayılan uygulama HİÇBİR ŞEY döndürmez (`null`) — cihaz entegrasyonu
/// (iOS HealthKit / Android Health Connect) eklendiğinde bu provider override
/// edilir ve tüm ekranlar otomatik olarak canlı veriye geçer.
///
/// Sözleşme: verilen gün için cihazdaki adım sayısı, okunamıyorsa `null`.
/// Geçmiş/gelecek günler ve izin verilmemiş durumlar `null` döner.
final deviceStepReaderProvider = Provider<Future<int?> Function(DateTime day)>(
  (ref) => (_) async => null,
);

/// Bir günün adımını çözer: cihaz → plan tahmini → mesafeden türetme.
///
/// [planEstimate] plandaki tahmin, [distanceKm] o günün yürüyüş mesafesi.
Future<DaySteps> resolveDaySteps(
  Ref ref, {
  required DateTime day,
  int? planEstimate,
  double distanceKm = 0,
}) async {
  final read = ref.read(deviceStepReaderProvider);
  final live = await read(day);
  if (live != null && live > 0) {
    return DaySteps(steps: live, source: StepSource.device);
  }
  if (planEstimate != null && planEstimate > 0) {
    return DaySteps(steps: planEstimate, source: StepSource.planEstimate);
  }
  return DaySteps(
    steps: (distanceKm * kStepsPerKm).round(),
    source: StepSource.derived,
  );
}

/// [dayStepsProvider] girdisi — gün + o güne ait plan verisi.
class DayStepsQuery {
  const DayStepsQuery({
    required this.date,
    this.planEstimate,
    this.distanceKm = 0,
  });

  /// ISO gün ("YYYY-MM-DD").
  final String date;
  final int? planEstimate;
  final double distanceKm;

  @override
  bool operator ==(Object other) =>
      other is DayStepsQuery &&
      other.date == date &&
      other.planEstimate == planEstimate &&
      other.distanceKm == distanceKm;

  @override
  int get hashCode => Object.hash(date, planEstimate, distanceKm);
}

/// Bir günün adımı — cihaz okuması asenkron olduğu için Future provider.
final dayStepsProvider =
    FutureProvider.family<DaySteps, DayStepsQuery>((ref, query) async {
  final parsed = DateTime.tryParse(query.date);
  return resolveDaySteps(
    ref,
    day: parsed ?? DateTime.now(),
    planEstimate: query.planEstimate,
    distanceKm: query.distanceKm,
  );
});

/// Ortalama yetişkinde ~1 km yürüyüş ≈ 1370 adım.
const double kStepsPerKm = 1370;

/// Adım başına yakılan yaklaşık kalori (ortalama yetişkin).
///
/// Kilo/boy sormadan verilebilecek kaba bir tahmin; UI bunu "tahmini" olarak
/// sunmalı.
const double kKcalPerStep = 0.04;

/// Adımdan kalori tahmini.
int kcalForSteps(int steps) => (steps * kKcalPerStep).round();
