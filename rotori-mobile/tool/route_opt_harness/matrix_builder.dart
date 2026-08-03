import 'dart:math';

import 'package:japan_trip/domain/route_matrix.dart';

/// Bir günün lokasyon kümesi için sentetik ama gerçekçi bir yönlü RouteMatrix
/// üretir. Üretim optimizer'ı koordinattan süre türetmez; burada SADECE test
/// verisi üretmek için haversine mesafeden makul walking/metro/train/taxi
/// seçenekleri kuruyoruz. Matris tam bağlantılıdır (her yönlü çift).
class MatrixBuilder {
  const MatrixBuilder();

  static const version = 'harness-directional-v2';

  static const double _walkKmh = 4.6;
  static const double _transitEffectiveKmh = 21;
  static const double _taxiKmh = 24;

  RouteMatrix build(
    List<TripLocation> locations, {
    DateTime? departureTime,
  }) {
    final entries = <RouteMatrixEntry>[];
    for (final from in locations) {
      for (final to in locations) {
        if (from.id == to.id) continue;
        final options = _optionsFor(from, to, departureTime);
        if (options.isEmpty) continue;
        entries.add(RouteMatrixEntry(
          fromLocationId: from.id,
          toLocationId: to.id,
          options: options,
        ));
      }
    }
    return RouteMatrix(entries: entries, version: version);
  }

  List<TransportOption> _optionsFor(
    TripLocation from,
    TripLocation to,
    DateTime? departureTime,
  ) {
    final km =
        _haversineKm(from.latitude, from.longitude, to.latitude, to.longitude);
    final sameCluster =
        from.clusterId != null && from.clusterId == to.clusterId;
    final options = <TransportOption>[];
    final hour = departureTime?.hour ?? 12;
    final peakPenalty =
        (hour >= 7 && hour < 10) || (hour >= 17 && hour < 20) ? 3 : 0;
    final directionBias = from.id.compareTo(to.id) < 0 ? 1 : 3;

    // Aynı koordinat / 50 m altı: yapay yürüyüş üretme (baseline'da otel
    // kahvaltısı için 3 dk'lık sahte leg oluşuyordu). Sıfır süreli leg.
    if (km <= 0.05) {
      options.add(const TransportOption(
        mode: TransportMode.walking,
        doorToDoorMinutes: 0,
        walkingMinutes: 0,
        waitingMinutes: 0,
        transferCount: 0,
        estimatedCostYen: 0,
        reliabilityScore: 1,
        isEstimated: true,
        providerId: 'harness-synthetic',
      ));
      return options;
    }

    // Yürüyüş: yalnızca yeterince yakınsa (~2.2 km altı).
    if (km <= 2.2) {
      final walkMin = max(3, (km / _walkKmh * 60).round());
      options.add(TransportOption(
        mode: TransportMode.walking,
        doorToDoorMinutes: walkMin,
        walkingMinutes: walkMin,
        waitingMinutes: 0,
        transferCount: 0,
        estimatedCostYen: 0,
        reliabilityScore: 1,
        rideMinutes: 0,
        accessMinutes: walkMin,
        transitWaitMinutes: 0,
        isEstimated: true,
        providerId: 'harness-synthetic',
      ));
    }

    // Metro/tren: kısa yürüyüşle erişilir, çok kısa mesafede anlamsız.
    if (km >= 0.7) {
      final access = 4 + (km > 6 ? 3 : 0) + directionBias;
      final ride = (km / _transitEffectiveKmh * 60).round() + peakPenalty;
      final transfers = sameCluster ? 0 : (km > 8 ? 2 : (km > 3.5 ? 1 : 0));
      final waiting = 3 + transfers * 3;
      final total = access + ride + waiting;
      final isMetro = km < 9;
      final baseFare = isMetro ? 180 : 220;
      final cost = baseFare + (km * 12).round() + transfers * 60;
      // Büyük istasyon / çok aktarmalı güzergâh karmaşıklık cezası alır.
      final complexity = transfers >= 2 ? 6.0 : (transfers == 1 ? 2.0 : 0.0);
      options.add(TransportOption(
        mode: isMetro ? TransportMode.metro : TransportMode.train,
        doorToDoorMinutes: total,
        walkingMinutes: access,
        waitingMinutes: waiting,
        transferCount: transfers,
        estimatedCostYen: cost,
        reliabilityScore: transfers >= 2 ? 0.9 : 0.95,
        lineId: '${from.clusterId}->${to.clusterId}',
        directionId: from.id.compareTo(to.id) < 0 ? 'outbound' : 'inbound',
        complexityPenalty: complexity,
        rideMinutes: ride,
        accessMinutes: access,
        transitWaitMinutes: waiting,
        fareBasis: FareBasis.perPerson,
        isEstimated: true,
        providerId: 'harness-synthetic',
      ));
    }

    // Taksi: orta-uzun mesafede hızlı ama pahalı bir alternatif.
    if (km >= 1.5 && km <= 18) {
      final rideMin = max(6, (km / _taxiKmh * 60).round() + 4);
      final cost = 500 + (km * 340).round();
      options.add(TransportOption(
        mode: TransportMode.taxi,
        doorToDoorMinutes: rideMin,
        walkingMinutes: 1,
        waitingMinutes: 3,
        transferCount: 0,
        estimatedCostYen: cost,
        reliabilityScore: 0.9,
        rideMinutes: rideMin - 4,
        accessMinutes: 1,
        transitWaitMinutes: 3,
        fareBasis: FareBasis.perVehicle,
        vehicleCapacity: 4,
        isEstimated: true,
        providerId: 'harness-synthetic',
      ));
    }

    // Emniyet: hiç seçenek yoksa (çok kısa ve <0.7) minik yürüyüş.
    if (options.isEmpty) {
      final walkMin = max(2, (km / _walkKmh * 60).round());
      options.add(TransportOption(
        mode: TransportMode.walking,
        doorToDoorMinutes: walkMin,
        walkingMinutes: walkMin,
        waitingMinutes: 0,
        transferCount: 0,
        estimatedCostYen: 0,
        reliabilityScore: 1,
        rideMinutes: 0,
        accessMinutes: walkMin,
        transitWaitMinutes: 0,
        isEstimated: true,
        providerId: 'harness-synthetic',
      ));
    }
    return options;
  }

  static double _haversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180;
}
