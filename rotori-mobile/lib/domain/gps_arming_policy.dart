/// GPS devreye girme politikası — pil ile "otomatik" hissi arasındaki takas.
///
/// Sorun: Keşfet ekranında elle basılan bir "İzlemeyi başlat" butonu kimsenin
/// basmadığı bir buton. Sürekli akış açmak ise pili yer.
///
/// Çözüm, Rotori'nin sahip olduğu ama genel amaçlı uygulamaların sahip olmadığı
/// bilgiyi kullanmak: **kullanıcının nerede ve ne zaman olacağını plan zaten
/// biliyor.** O yüzden GPS'i açmaya değil, çoğu zaman *açmamaya* karar veririz.
///
/// Merdiven:
///
/// | Kademe     | Koşul                                          | Maliyet |
/// |------------|------------------------------------------------|---------|
/// | `off`      | gezi penceresi dışı / izin yok / hedef yok     | sıfır   |
/// | `oneShot`  | konum bilinmiyor ya da tüm hedefler uzak       | ~sıfır  |
/// | `balanced` | hedefe yakın **ve** planlı saate yakın         | orta    |
/// | `precise`  | hedefin hemen dibinde (damga anı)              | yüksek  |
///
/// Kritik nokta: `balanced`'a geçmek için **iki koşul birlikte** gerekir.
/// Otelde saat 23:00'te Asakusa'ya 8 km uzaktayken GPS hiç açılmaz.
///
/// Katman **saf**tır: `Geolocator`, `DateTime.now()` ve ağ yok. Zaman ve konum
/// enjekte edilir; testler determinist olur.
library;

import 'dart:math' as math;

import 'geofence.dart' show LatLng, distanceMeters;

/// GPS örnekleme yoğunluğu kademesi.
enum GpsArmingTier {
  /// Hiç konum alınmaz.
  off,

  /// Tek seferlik kaba konum (ekran açılışı). Akış başlatılmaz.
  oneShot,

  /// Orta doğrulukta akış — hedefe yaklaşılıyor.
  balanced,

  /// En yüksek doğruluk — keşif/damga anı.
  precise,
}

/// Kararın **neden** verildiği. Log ve UI'daki dürüst durum çipi için.
enum GpsArmingReason {
  outsideTripWindow,
  permissionMissing,
  noTargets,
  allTargetsDiscovered,

  /// Henüz konum bilinmiyor — karar vermek için bir kaba fix gerekiyor.
  noFixYet,

  /// Elde bir fix var ama çok eski; yenilemek gerekiyor.
  staleFix,

  /// Tüm hedefler yaklaşma yarıçapının dışında.
  farFromAllTargets,

  /// Hedef yakın ama planlı saat penceresi kapalı.
  outsideTimeWindow,

  /// Hedefe yaklaşılıyor — akış açılır.
  approachingTarget,

  /// Hedefin içinde/dibinde — en yüksek doğruluk.
  atTarget,

  /// Yaklaşık konum yetkisiyle hedefe yaklaşıldı ama damga için kesin konum
  /// gerekiyor. UI, Apple'ın geçici tam doğruluk akışını **bu anda** açmalı.
  reducedAccuracyBlocked,
}

/// iOS 14+ / Android 12+ konum doğruluk yetkisi.
///
/// Kullanıcı "Yaklaşık Konum"u seçebilir. Apple bunu kasten kolaylaştırdı;
/// uygulama buna **saygı göstermek** ve yine de çalışmak zorunda. Kesin konumu
/// ancak gerçekten gerektiği anda, `requestTemporaryFullAccuracyAuthorization`
/// ile geçici olarak istemek Apple'ın önerdiği yoldur.
enum LocationAccuracyAuthorization {
  /// Tam doğruluk — metre mertebesi.
  precise,

  /// Yaklaşık konum — iOS'ta ~1–20 km. Şehir bağlamı için yeter, damga için
  /// yetmez.
  reduced,
}

/// Bilinen son konum.
class GeoFix {
  const GeoFix({
    required this.lat,
    required this.lng,
    required this.timestamp,
    this.accuracyMeters = 50,
  });

  final double lat;
  final double lng;
  final DateTime timestamp;
  final double accuracyMeters;
}

/// Politikanın değerlendirdiği hedef (keşif noktası).
class GpsTarget {
  const GpsTarget({
    required this.id,
    required this.lat,
    required this.lng,
    this.radiusMeters = 150,
    this.scheduledAt,
    this.isDiscovered = false,
  });

  final String id;
  final double lat;
  final double lng;
  final double radiusMeters;

  /// Planda bu hedefin başlangıç saati. `null` ise zaman kapısı uygulanmaz —
  /// saati bilinmeyen bir hedefi saat yüzünden ıskalamak istemeyiz.
  final DateTime? scheduledAt;

  /// Zaten keşfedilmiş hedef için GPS açmanın anlamı yok.
  final bool isDiscovered;
}

class GpsArmingDecision {
  const GpsArmingDecision({
    required this.tier,
    required this.reason,
    this.nearestTargetId,
    this.nearestTargetMeters,
    this.recheckAfter,
    this.needsTemporaryFullAccuracy = false,
  });

  final GpsArmingTier tier;
  final GpsArmingReason reason;

  final String? nearestTargetId;
  final double? nearestTargetMeters;

  /// Bir sonraki değerlendirme için önerilen bekleme. `oneShot` kademesinde
  /// mesafeye göre uzar: 8 km uzaktaysak 2 dakikada bir bakmak anlamsızdır.
  final Duration? recheckAfter;

  /// `true` ise UI, Apple'ın geçici tam doğruluk iznini istemeli. Bunu ancak
  /// kullanıcı fiilen bir keşif noktasının yakınındayken sormak, hem review
  /// hem kabul oranı açısından doğru olan.
  final bool needsTemporaryFullAccuracy;

  bool get isStreaming =>
      tier == GpsArmingTier.balanced || tier == GpsArmingTier.precise;

  bool get needsFix =>
      reason == GpsArmingReason.noFixYet || reason == GpsArmingReason.staleFix;

  @override
  String toString() =>
      'GpsArmingDecision(${tier.name}, ${reason.name}'
      '${nearestTargetMeters == null ? '' : ', ${nearestTargetMeters!.round()}m'})';
}

class GpsArmingPolicy {
  const GpsArmingPolicy({
    this.approachRadiusMeters = 1500,
    this.preciseRadiusMeters = 300,
    this.scheduleWindow = const Duration(minutes: 45),
    this.fixStalenessLimit = const Duration(minutes: 20),
    this.minimumRecheck = const Duration(minutes: 5),
    this.maximumRecheck = const Duration(minutes: 30),
    this.walkingSpeedKmh = 4.6,
  });

  /// Bu yarıçapın içinde akış açılır (zaman kapısı da açıksa).
  final double approachRadiusMeters;

  /// Bu yarıçapın içinde en yüksek doğruluğa çıkılır.
  final double preciseRadiusMeters;

  /// Planlı saatin etrafındaki tolerans (±). Kullanıcı programın önünde ya da
  /// arkasında olabilir; pencere bunu massetmeli.
  final Duration scheduleWindow;

  /// Bundan eski bir fix karar vermek için güvenilmez.
  final Duration fixStalenessLimit;

  final Duration minimumRecheck;
  final Duration maximumRecheck;

  /// Yürüme hızı — uzaktaki hedefe varış süresi tahmini için.
  final double walkingSpeedKmh;

  GpsArmingDecision evaluate({
    required DateTime now,
    required bool isWithinTripWindow,
    required bool hasPermission,
    required List<GpsTarget> targets,
    GeoFix? lastFix,
    LocationAccuracyAuthorization accuracy =
        LocationAccuracyAuthorization.precise,
  }) {
    // --- Kapılar: bunlar geçilmezse GPS'e hiç dokunulmaz ------------------
    if (!hasPermission) {
      return const GpsArmingDecision(
        tier: GpsArmingTier.off,
        reason: GpsArmingReason.permissionMissing,
      );
    }
    if (!isWithinTripWindow) {
      return const GpsArmingDecision(
        tier: GpsArmingTier.off,
        reason: GpsArmingReason.outsideTripWindow,
      );
    }
    if (targets.isEmpty) {
      return const GpsArmingDecision(
        tier: GpsArmingTier.off,
        reason: GpsArmingReason.noTargets,
      );
    }

    final pending = targets.where((t) => !t.isDiscovered).toList();
    if (pending.isEmpty) {
      return const GpsArmingDecision(
        tier: GpsArmingTier.off,
        reason: GpsArmingReason.allTargetsDiscovered,
      );
    }

    // --- Konum bilinmiyorsa tek atış yeterli ------------------------------
    if (lastFix == null) {
      return const GpsArmingDecision(
        tier: GpsArmingTier.oneShot,
        reason: GpsArmingReason.noFixYet,
      );
    }
    if (now.difference(lastFix.timestamp).abs() > fixStalenessLimit) {
      return const GpsArmingDecision(
        tier: GpsArmingTier.oneShot,
        reason: GpsArmingReason.staleFix,
      );
    }

    // --- Mesafe + zaman kapısı --------------------------------------------
    GpsTarget? nearest;
    var nearestMeters = double.infinity;
    GpsTarget? bestArmable;
    var bestArmableMeters = double.infinity;

    for (final target in pending) {
      final meters = distanceMeters(
        LatLng(lastFix.lat, lastFix.lng),
        LatLng(target.lat, target.lng),
      );
      if (meters < nearestMeters) {
        nearestMeters = meters;
        nearest = target;
      }
      final withinApproach =
          meters <= math.max(approachRadiusMeters, target.radiusMeters);
      if (withinApproach &&
          _isTimeWindowOpen(now: now, scheduledAt: target.scheduledAt) &&
          meters < bestArmableMeters) {
        bestArmableMeters = meters;
        bestArmable = target;
      }
    }

    if (bestArmable != null) {
      // Yaklaşık konum yetkisiyle 300 m'lik damga kararı verilemez: iOS'ta
      // reduced accuracy ~1–20 km. Uydurma bir "geldin" demektense Apple'ın
      // geçici tam doğruluk akışını tetiklemesi için UI'a haber veririz.
      if (accuracy == LocationAccuracyAuthorization.reduced) {
        return GpsArmingDecision(
          tier: GpsArmingTier.oneShot,
          reason: GpsArmingReason.reducedAccuracyBlocked,
          nearestTargetId: bestArmable.id,
          nearestTargetMeters: bestArmableMeters,
          needsTemporaryFullAccuracy: true,
        );
      }

      // Fix'in kendi hata payı karar yarıçapından büyükse "hedefteyim"
      // diyemeyiz; bir kademe aşağıda kalıp daha iyi bir örnek bekleriz.
      final threshold = math.max(preciseRadiusMeters, bestArmable.radiusMeters);
      final atTarget = bestArmableMeters <= threshold &&
          lastFix.accuracyMeters <= threshold;
      return GpsArmingDecision(
        tier: atTarget ? GpsArmingTier.precise : GpsArmingTier.balanced,
        reason: atTarget
            ? GpsArmingReason.atTarget
            : GpsArmingReason.approachingTarget,
        nearestTargetId: bestArmable.id,
        nearestTargetMeters: bestArmableMeters,
      );
    }

    // Yakın hedef var ama saati gelmemiş → akış açma, tembel tekrar bak.
    final nearIsClose = nearestMeters <= approachRadiusMeters;
    return GpsArmingDecision(
      tier: GpsArmingTier.oneShot,
      reason: nearIsClose
          ? GpsArmingReason.outsideTimeWindow
          : GpsArmingReason.farFromAllTargets,
      nearestTargetId: nearest?.id,
      nearestTargetMeters: nearestMeters,
      recheckAfter: _recheckFor(nearestMeters),
    );
  }

  bool _isTimeWindowOpen({
    required DateTime now,
    required DateTime? scheduledAt,
  }) {
    // Saati bilinmeyen hedefi zaman yüzünden ıskalamayız.
    if (scheduledAt == null) return true;
    return now.difference(scheduledAt).abs() <= scheduleWindow;
  }

  /// Mesafeye göre tembel tekrar-bakma aralığı: hedefe yürüyerek varış
  /// süresinin yarısı, [minimumRecheck]–[maximumRecheck] arasına kırpılır.
  Duration _recheckFor(double meters) {
    if (!meters.isFinite) return maximumRecheck;
    final hours = (meters / 1000) / walkingSpeedKmh;
    final half = Duration(minutes: (hours * 60 / 2).round());
    if (half < minimumRecheck) return minimumRecheck;
    if (half > maximumRecheck) return maximumRecheck;
    return half;
  }
}
