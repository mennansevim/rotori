import 'dart:math' as math;

import '../domain/route_matrix.dart';

const String kOfflineJapanRoutePackVersion = '2026.08.1';
const String kOfflineJapanRouteProviderId = 'rotori-offline-jp';

/// Japonya içi günlük planlamayı çalışma zamanı API çağrısı olmadan besler.
///
/// Bu repository turn-by-turn navigasyon üretmez. Şehir, semt/istasyon,
/// mesafe, gün türü ve zaman bandından kapıdan kapıya tahmini seçenekler kurar;
/// bilinmeyen hat, peron veya yön adı eklemez.
class OfflineJapanRouteMatrixRepository implements RouteMatrixRepository {
  const OfflineJapanRouteMatrixRepository();

  @override
  Future<RouteMatrix> getRouteMatrix({
    required List<TripLocation> locations,
    required DateTime day,
    required RoutePreferences preferences,
  }) async {
    return buildOfflineJapanRouteMatrix(
      locations,
      day: day,
      preferences: preferences,
    );
  }
}

/// Optimizer'ın aynı semte geri dönmeyi cezalandırabilmesi için şehir içi
/// kümeyi cihazdaki aynı rota paketinden çözer.
String offlineJapanRouteClusterId({
  required String? city,
  required double latitude,
  required double longitude,
}) {
  final location = TripLocation(
    id: 'cluster-probe',
    name: '',
    latitude: latitude,
    longitude: longitude,
    city: city,
  );
  final cityKey = _normalizeCity(city);
  var profile = cityKey == null ? null : _profilesByKey[cityKey];
  if (profile == null) {
    for (final candidate in _profiles) {
      if (_distanceTo(candidate.centerLat, candidate.centerLng, location) <=
          candidate.coverageRadiusKm) {
        profile = candidate;
        break;
      }
    }
  }
  profile ??= _genericProfile;
  final zone = profile.nearestZone(location);
  return '${profile.key}:${zone?.id ?? 'outer'}';
}

RouteMatrix buildOfflineJapanRouteMatrix(
  List<TripLocation> locations, {
  required DateTime day,
  RoutePreferences preferences = const RoutePreferences(),
}) {
  final band = _TimeBand.from(day.hour);
  final weekend =
      day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
  final entries = <RouteMatrixEntry>[];

  for (final from in locations) {
    for (final to in locations) {
      if (from.id == to.id) continue;
      entries.add(
        RouteMatrixEntry(
          fromLocationId: from.id,
          toLocationId: to.id,
          options: _optionsFor(
            from,
            to,
            band: band,
            weekend: weekend,
            preferences: preferences,
          ),
        ),
      );
    }
  }

  return RouteMatrix(
    entries: entries,
    version: 'offline-jp-$kOfflineJapanRoutePackVersion-'
        '${weekend ? 'weekend' : 'weekday'}-${band.name}',
  );
}

List<TransportOption> _optionsFor(
  TripLocation from,
  TripLocation to, {
  required _TimeBand band,
  required bool weekend,
  required RoutePreferences preferences,
}) {
  final directKm = _distanceKm(from, to);
  if (directKm <= 0.05) {
    return const [
      TransportOption(
        mode: TransportMode.walking,
        doorToDoorMinutes: 0,
        walkingMinutes: 0,
        waitingMinutes: 0,
        transferCount: 0,
        estimatedCostYen: 0,
        reliabilityScore: 0.96,
        isEstimated: true,
        providerId: kOfflineJapanRouteProviderId,
      ),
    ];
  }

  final profile = _profileFor(from, to);
  final fromZone = profile.nearestZone(from);
  final toZone = profile.nearestZone(to);
  final options = <TransportOption>[];
  final walkingKm = directKm * profile.walkingCircuity;
  final walkingMinutes = math.max(2, (walkingKm / 4.6 * 60).ceil());
  final walkingLimitKm = preferences.maximumWalkingMinutes <= 90
      ? math.min(profile.maximumWalkingKm, 2.2)
      : profile.maximumWalkingKm;

  if (walkingKm <= walkingLimitKm) {
    options.add(
      TransportOption(
        mode: TransportMode.walking,
        doorToDoorMinutes: walkingMinutes,
        walkingMinutes: walkingMinutes,
        waitingMinutes: 0,
        transferCount: 0,
        estimatedCostYen: 0,
        reliabilityScore: profile.isCurated ? 0.82 : 0.62,
        isEstimated: true,
        rideMinutes: 0,
        accessMinutes: walkingMinutes,
        transitWaitMinutes: 0,
        providerId: kOfflineJapanRouteProviderId,
      ),
    );
  }

  final rule = profile.connection(fromZone?.id, toZone?.id);
  options.add(
    rule == null
        ? _transitOption(
            profile,
            directKm,
            fromZone: fromZone,
            toZone: toZone,
            band: band,
            weekend: weekend,
          )
        : rule.option(reversed: rule.fromZoneId != fromZone?.id),
  );
  options.add(
    _taxiOption(
      profile,
      directKm,
      fromZone: fromZone,
      toZone: toZone,
      band: band,
      weekend: weekend,
    ),
  );
  return options;
}

TransportOption _transitOption(
  _CityRouteProfile profile,
  double directKm, {
  required _RouteZone? fromZone,
  required _RouteZone? toZone,
  required _TimeBand band,
  required bool weekend,
}) {
  final sameZone = fromZone != null && fromZone.id == toZone?.id;
  final networkKm = directKm * profile.transitCircuity;
  final access = math.min(
    18,
    profile.accessMinutes +
        (sameZone ? -1 : 0) +
        (fromZone?.accessPenaltyMinutes ?? 0) +
        (toZone?.accessPenaltyMinutes ?? 0),
  );
  final waiting = profile.waitMinutes + (weekend ? 1 : 0);
  final transfers = sameZone
      ? 0
      : directKm < profile.noTransferUpToKm
          ? 0
          : directKm < profile.twoTransfersAfterKm
              ? 1
              : 2;
  final stationBuffer = (fromZone?.stationPenaltyMinutes ?? 0) +
      (toZone?.stationPenaltyMinutes ?? 0) +
      transfers * 4;
  final directionFactor = _directionFactor(
    band,
    fromZone?.isCore ?? false,
    toZone?.isCore ?? false,
  );
  final ride = math.max(
    3,
    (networkKm / profile.transitSpeedKmh * 60 * directionFactor).ceil(),
  );
  final fare = math.max(
    profile.baseTransitFareYen,
    (profile.baseTransitFareYen + networkKm * profile.transitYenPerKm).round(),
  );

  return TransportOption(
    mode: profile.transitMode,
    doorToDoorMinutes: access + waiting + ride + stationBuffer,
    walkingMinutes: access,
    waitingMinutes: waiting,
    transferCount: transfers,
    estimatedCostYen: fare,
    reliabilityScore: profile.isCurated ? 0.78 : 0.58,
    complexityPenalty: stationBuffer / 4,
    isEstimated: true,
    rideMinutes: ride,
    accessMinutes: access,
    transitWaitMinutes: waiting,
    bufferMinutes: stationBuffer,
    providerId: kOfflineJapanRouteProviderId,
  );
}

TransportOption _taxiOption(
  _CityRouteProfile profile,
  double directKm, {
  required _RouteZone? fromZone,
  required _RouteZone? toZone,
  required _TimeBand band,
  required bool weekend,
}) {
  final roadKm = math.max(0.7, directKm * profile.roadCircuity);
  final coreTrip = (fromZone?.isCore ?? false) || (toZone?.isCore ?? false);
  var speed = coreTrip ? profile.taxiCoreSpeedKmh : profile.taxiOuterSpeedKmh;
  if (band == _TimeBand.morning || band == _TimeBand.evening) speed *= 0.82;
  if (weekend && band == _TimeBand.daytime) speed *= 0.9;
  final ride = math.max(3, (roadKm / speed * 60).ceil());
  final waiting = band == _TimeBand.late ? 6 : 4;
  const walking = 1;
  final fare = math.max(
    profile.taxiBaseFareYen,
    (profile.taxiBaseFareYen + roadKm * profile.taxiYenPerKm).round(),
  );

  return TransportOption(
    mode: TransportMode.taxi,
    doorToDoorMinutes: walking + waiting + ride,
    walkingMinutes: walking,
    waitingMinutes: waiting,
    transferCount: 0,
    estimatedCostYen: fare,
    reliabilityScore: 0.64,
    isEstimated: true,
    rideMinutes: ride,
    accessMinutes: walking,
    transitWaitMinutes: waiting,
    fareBasis: FareBasis.perVehicle,
    vehicleCapacity: 4,
    providerId: kOfflineJapanRouteProviderId,
  );
}

double _directionFactor(_TimeBand band, bool fromCore, bool toCore) {
  if (band == _TimeBand.morning && toCore && !fromCore) return 1.08;
  if (band == _TimeBand.evening && fromCore && !toCore) return 1.08;
  if (band == _TimeBand.morning || band == _TimeBand.evening) return 1.03;
  return 1;
}

_CityRouteProfile _profileFor(TripLocation from, TripLocation to) {
  final fromCity = _normalizeCity(from.city);
  final toCity = _normalizeCity(to.city);
  if (fromCity != null && (toCity == null || fromCity == toCity)) {
    final named = _profilesByKey[fromCity];
    if (named != null) return named;
  }
  if (toCity != null && fromCity == null) {
    final named = _profilesByKey[toCity];
    if (named != null) return named;
  }

  _CityRouteProfile? best;
  var bestDistance = double.infinity;
  for (final profile in _profiles) {
    final fromDistance =
        _distanceTo(profile.centerLat, profile.centerLng, from);
    final toDistance = _distanceTo(profile.centerLat, profile.centerLng, to);
    if (fromDistance > profile.coverageRadiusKm ||
        toDistance > profile.coverageRadiusKm) {
      continue;
    }
    final combined = fromDistance + toDistance;
    if (combined < bestDistance) {
      best = profile;
      bestDistance = combined;
    }
  }
  return best ?? _genericProfile;
}

String? _normalizeCity(String? value) {
  final city = value?.trim().toLowerCase();
  if (city == null || city.isEmpty) return null;
  if (city.contains('tokyo') || city.contains('tokio')) return 'tokyo';
  if (city.contains('kyoto') || city.contains('kioto')) return 'kyoto';
  if (city.contains('osaka')) return 'osaka';
  if (city.contains('hiroshima') || city.contains('miyajima')) {
    return 'hiroshima';
  }
  for (final key in _profilesByKey.keys) {
    if (city.contains(key)) return key;
  }
  return city;
}

enum _TimeBand {
  morning,
  daytime,
  evening,
  late;

  static _TimeBand from(int hour) {
    if (hour >= 7 && hour < 10) return morning;
    if (hour >= 10 && hour < 16) return daytime;
    if (hour >= 16 && hour < 20) return evening;
    return late;
  }
}

class _CityRouteProfile {
  const _CityRouteProfile({
    required this.key,
    required this.centerLat,
    required this.centerLng,
    required this.coverageRadiusKm,
    required this.transitMode,
    required this.walkingCircuity,
    required this.roadCircuity,
    required this.transitCircuity,
    required this.transitSpeedKmh,
    required this.accessMinutes,
    required this.waitMinutes,
    required this.maximumWalkingKm,
    required this.noTransferUpToKm,
    required this.twoTransfersAfterKm,
    required this.baseTransitFareYen,
    required this.transitYenPerKm,
    required this.taxiCoreSpeedKmh,
    required this.taxiOuterSpeedKmh,
    required this.taxiBaseFareYen,
    required this.taxiYenPerKm,
    this.isCurated = false,
    this.zones = const [],
    this.connections = const [],
  });

  final String key;
  final double centerLat;
  final double centerLng;
  final double coverageRadiusKm;
  final TransportMode transitMode;
  final double walkingCircuity;
  final double roadCircuity;
  final double transitCircuity;
  final double transitSpeedKmh;
  final int accessMinutes;
  final int waitMinutes;
  final double maximumWalkingKm;
  final double noTransferUpToKm;
  final double twoTransfersAfterKm;
  final int baseTransitFareYen;
  final double transitYenPerKm;
  final double taxiCoreSpeedKmh;
  final double taxiOuterSpeedKmh;
  final int taxiBaseFareYen;
  final double taxiYenPerKm;
  final bool isCurated;
  final List<_RouteZone> zones;
  final List<_ConnectionRule> connections;

  _RouteZone? nearestZone(TripLocation location) {
    _RouteZone? best;
    var bestDistance = double.infinity;
    for (final zone in zones) {
      final distance = _distanceTo(zone.lat, zone.lng, location);
      if (distance <= zone.radiusKm && distance < bestDistance) {
        best = zone;
        bestDistance = distance;
      }
    }
    return best;
  }

  _ConnectionRule? connection(String? fromZoneId, String? toZoneId) {
    if (fromZoneId == null || toZoneId == null) return null;
    for (final rule in connections) {
      if (rule.matches(fromZoneId, toZoneId)) return rule;
    }
    return null;
  }
}

class _RouteZone {
  const _RouteZone({
    required this.id,
    required this.lat,
    required this.lng,
    required this.radiusKm,
    this.isCore = false,
    this.accessPenaltyMinutes = 0,
    this.stationPenaltyMinutes = 0,
  });

  final String id;
  final double lat;
  final double lng;
  final double radiusKm;
  final bool isCore;
  final int accessPenaltyMinutes;
  final int stationPenaltyMinutes;
}

class _ConnectionRule {
  const _ConnectionRule({
    required this.fromZoneId,
    required this.toZoneId,
    required this.mode,
    required this.minutes,
    required this.walkingMinutes,
    required this.waitingMinutes,
    required this.transferCount,
    required this.costYen,
    this.reverseDeltaMinutes = 0,
  });

  final String fromZoneId;
  final String toZoneId;
  final TransportMode mode;
  final int minutes;
  final int walkingMinutes;
  final int waitingMinutes;
  final int transferCount;
  final int costYen;
  final int reverseDeltaMinutes;
  bool matches(String from, String to) {
    return (fromZoneId == from && toZoneId == to) ||
        (fromZoneId == to && toZoneId == from);
  }

  TransportOption option({required bool reversed}) {
    final total = minutes + (reversed ? reverseDeltaMinutes : 0);
    const buffer = 5;
    final ride = math.max(0, total - walkingMinutes - waitingMinutes - buffer);
    return TransportOption(
      mode: mode,
      doorToDoorMinutes: total,
      walkingMinutes: walkingMinutes,
      waitingMinutes: waitingMinutes,
      transferCount: transferCount,
      estimatedCostYen: costYen,
      reliabilityScore: 0.84,
      complexityPenalty: transferCount * 1.5,
      isEstimated: true,
      rideMinutes: ride,
      accessMinutes: walkingMinutes,
      transitWaitMinutes: waitingMinutes,
      bufferMinutes: buffer,
      providerId: kOfflineJapanRouteProviderId,
    );
  }
}

const _genericProfile = _CityRouteProfile(
  key: 'generic-japan',
  centerLat: 36.2,
  centerLng: 138.25,
  coverageRadiusKm: 999,
  transitMode: TransportMode.train,
  walkingCircuity: 1.32,
  roadCircuity: 1.28,
  transitCircuity: 1.22,
  transitSpeedKmh: 24,
  accessMinutes: 10,
  waitMinutes: 7,
  maximumWalkingKm: 3.2,
  noTransferUpToKm: 3.5,
  twoTransfersAfterKm: 16,
  baseTransitFareYen: 200,
  transitYenPerKm: 34,
  taxiCoreSpeedKmh: 21,
  taxiOuterSpeedKmh: 28,
  taxiBaseFareYen: 600,
  taxiYenPerKm: 360,
);

const _profiles = <_CityRouteProfile>[
  _CityRouteProfile(
    key: 'tokyo',
    centerLat: 35.6812,
    centerLng: 139.7671,
    coverageRadiusKm: 32,
    transitMode: TransportMode.metro,
    walkingCircuity: 1.22,
    roadCircuity: 1.3,
    transitCircuity: 1.18,
    transitSpeedKmh: 31,
    accessMinutes: 9,
    waitMinutes: 4,
    maximumWalkingKm: 4,
    noTransferUpToKm: 4.2,
    twoTransfersAfterKm: 14,
    baseTransitFareYen: 180,
    transitYenPerKm: 26,
    taxiCoreSpeedKmh: 19,
    taxiOuterSpeedKmh: 27,
    taxiBaseFareYen: 500,
    taxiYenPerKm: 390,
    isCurated: true,
    zones: [
      _RouteZone(
          id: 'shibuya-harajuku',
          lat: 35.667,
          lng: 139.7000,
          radiusKm: 2.5,
          isCore: true,
          stationPenaltyMinutes: 5),
      _RouteZone(
          id: 'shinjuku',
          lat: 35.6896,
          lng: 139.7006,
          radiusKm: 2.4,
          isCore: true,
          stationPenaltyMinutes: 7),
      _RouteZone(
          id: 'central',
          lat: 35.6768,
          lng: 139.7635,
          radiusKm: 3.2,
          isCore: true,
          stationPenaltyMinutes: 5),
      _RouteZone(
          id: 'asakusa-ueno',
          lat: 35.714,
          lng: 139.786,
          radiusKm: 3.2,
          stationPenaltyMinutes: 3),
      _RouteZone(
          id: 'bay',
          lat: 35.638,
          lng: 139.781,
          radiusKm: 4.4,
          accessPenaltyMinutes: 2,
          stationPenaltyMinutes: 3),
      _RouteZone(
          id: 'disney',
          lat: 35.630,
          lng: 139.883,
          radiusKm: 3.2,
          accessPenaltyMinutes: 3,
          stationPenaltyMinutes: 5),
    ],
    connections: [
      _ConnectionRule(
          fromZoneId: 'shibuya-harajuku',
          toZoneId: 'bay',
          mode: TransportMode.metro,
          minutes: 39,
          walkingMinutes: 11,
          waitingMinutes: 5,
          transferCount: 1,
          costYen: 470,
          reverseDeltaMinutes: 2),
      _ConnectionRule(
          fromZoneId: 'shinjuku',
          toZoneId: 'asakusa-ueno',
          mode: TransportMode.metro,
          minutes: 36,
          walkingMinutes: 10,
          waitingMinutes: 4,
          transferCount: 1,
          costYen: 310,
          reverseDeltaMinutes: 2),
      _ConnectionRule(
          fromZoneId: 'asakusa-ueno',
          toZoneId: 'bay',
          mode: TransportMode.metro,
          minutes: 42,
          walkingMinutes: 12,
          waitingMinutes: 5,
          transferCount: 1,
          costYen: 440),
      _ConnectionRule(
          fromZoneId: 'shibuya-harajuku',
          toZoneId: 'disney',
          mode: TransportMode.metro,
          minutes: 52,
          walkingMinutes: 12,
          waitingMinutes: 5,
          transferCount: 1,
          costYen: 520,
          reverseDeltaMinutes: -2),
      _ConnectionRule(
          fromZoneId: 'central',
          toZoneId: 'disney',
          mode: TransportMode.regionalTrain,
          minutes: 42,
          walkingMinutes: 10,
          waitingMinutes: 5,
          transferCount: 1,
          costYen: 410,
          reverseDeltaMinutes: -2),
    ],
  ),
  _CityRouteProfile(
    key: 'kyoto',
    centerLat: 35.0116,
    centerLng: 135.7681,
    coverageRadiusKm: 22,
    transitMode: TransportMode.bus,
    walkingCircuity: 1.25,
    roadCircuity: 1.22,
    transitCircuity: 1.2,
    transitSpeedKmh: 18,
    accessMinutes: 7,
    waitMinutes: 7,
    maximumWalkingKm: 3.6,
    noTransferUpToKm: 4,
    twoTransfersAfterKm: 12,
    baseTransitFareYen: 230,
    transitYenPerKm: 30,
    taxiCoreSpeedKmh: 18,
    taxiOuterSpeedKmh: 25,
    taxiBaseFareYen: 500,
    taxiYenPerKm: 370,
    isCurated: true,
    zones: [
      _RouteZone(
          id: 'central',
          lat: 35.005,
          lng: 135.765,
          radiusKm: 2.3,
          isCore: true,
          stationPenaltyMinutes: 3),
      _RouteZone(
          id: 'east',
          lat: 35.005,
          lng: 135.787,
          radiusKm: 3.1,
          accessPenaltyMinutes: 1),
      _RouteZone(
          id: 'south',
          lat: 34.972,
          lng: 135.774,
          radiusKm: 2.8,
          stationPenaltyMinutes: 2),
      _RouteZone(id: 'north', lat: 35.0394, lng: 135.7292, radiusKm: 3),
      _RouteZone(
          id: 'arashiyama',
          lat: 35.017,
          lng: 135.6716,
          radiusKm: 3,
          accessPenaltyMinutes: 2,
          stationPenaltyMinutes: 2),
    ],
    connections: [
      _ConnectionRule(
          fromZoneId: 'arashiyama',
          toZoneId: 'south',
          mode: TransportMode.regionalTrain,
          minutes: 56,
          walkingMinutes: 13,
          waitingMinutes: 7,
          transferCount: 1,
          costYen: 520,
          reverseDeltaMinutes: 2),
      _ConnectionRule(
          fromZoneId: 'north',
          toZoneId: 'south',
          mode: TransportMode.bus,
          minutes: 52,
          walkingMinutes: 10,
          waitingMinutes: 8,
          transferCount: 1,
          costYen: 460),
    ],
  ),
  _CityRouteProfile(
    key: 'osaka',
    centerLat: 34.6937,
    centerLng: 135.5023,
    coverageRadiusKm: 25,
    transitMode: TransportMode.metro,
    walkingCircuity: 1.2,
    roadCircuity: 1.25,
    transitCircuity: 1.16,
    transitSpeedKmh: 30,
    accessMinutes: 8,
    waitMinutes: 4,
    maximumWalkingKm: 4,
    noTransferUpToKm: 4.5,
    twoTransfersAfterKm: 14,
    baseTransitFareYen: 190,
    transitYenPerKm: 27,
    taxiCoreSpeedKmh: 20,
    taxiOuterSpeedKmh: 28,
    taxiBaseFareYen: 500,
    taxiYenPerKm: 360,
    isCurated: true,
    zones: [
      _RouteZone(
          id: 'namba',
          lat: 34.665,
          lng: 135.503,
          radiusKm: 2.4,
          isCore: true,
          stationPenaltyMinutes: 4),
      _RouteZone(
          id: 'umeda',
          lat: 34.7025,
          lng: 135.4959,
          radiusKm: 2.7,
          isCore: true,
          stationPenaltyMinutes: 7),
      _RouteZone(id: 'castle', lat: 34.6873, lng: 135.5259, radiusKm: 2.2),
      _RouteZone(
          id: 'tennoji',
          lat: 34.646,
          lng: 135.513,
          radiusKm: 2.8,
          stationPenaltyMinutes: 3),
      _RouteZone(
          id: 'usj',
          lat: 34.6654,
          lng: 135.4323,
          radiusKm: 3.2,
          accessPenaltyMinutes: 2,
          stationPenaltyMinutes: 3),
    ],
    connections: [
      _ConnectionRule(
          fromZoneId: 'namba',
          toZoneId: 'usj',
          mode: TransportMode.train,
          minutes: 31,
          walkingMinutes: 9,
          waitingMinutes: 5,
          transferCount: 1,
          costYen: 370,
          reverseDeltaMinutes: 2),
      _ConnectionRule(
          fromZoneId: 'umeda',
          toZoneId: 'usj',
          mode: TransportMode.train,
          minutes: 25,
          walkingMinutes: 8,
          waitingMinutes: 5,
          transferCount: 1,
          costYen: 330),
    ],
  ),
  _CityRouteProfile(
    key: 'hiroshima',
    centerLat: 34.397,
    centerLng: 132.475,
    coverageRadiusKm: 30,
    transitMode: TransportMode.bus,
    walkingCircuity: 1.18,
    roadCircuity: 1.2,
    transitCircuity: 1.18,
    transitSpeedKmh: 20,
    accessMinutes: 7,
    waitMinutes: 6,
    maximumWalkingKm: 4,
    noTransferUpToKm: 4.5,
    twoTransfersAfterKm: 16,
    baseTransitFareYen: 220,
    transitYenPerKm: 28,
    taxiCoreSpeedKmh: 22,
    taxiOuterSpeedKmh: 30,
    taxiBaseFareYen: 580,
    taxiYenPerKm: 350,
    isCurated: true,
    zones: [
      _RouteZone(
          id: 'center', lat: 34.397, lng: 132.456, radiusKm: 3, isCore: true),
      _RouteZone(
          id: 'station',
          lat: 34.3975,
          lng: 132.4754,
          radiusKm: 2.2,
          stationPenaltyMinutes: 4),
      _RouteZone(
          id: 'miyajima',
          lat: 34.296,
          lng: 132.3197,
          radiusKm: 5,
          accessPenaltyMinutes: 3,
          stationPenaltyMinutes: 4),
    ],
    connections: [
      _ConnectionRule(
          fromZoneId: 'center',
          toZoneId: 'miyajima',
          mode: TransportMode.regionalTrain,
          minutes: 66,
          walkingMinutes: 16,
          waitingMinutes: 8,
          transferCount: 1,
          costYen: 620,
          reverseDeltaMinutes: 4),
      _ConnectionRule(
          fromZoneId: 'station',
          toZoneId: 'miyajima',
          mode: TransportMode.regionalTrain,
          minutes: 58,
          walkingMinutes: 14,
          waitingMinutes: 8,
          transferCount: 1,
          costYen: 600,
          reverseDeltaMinutes: 4),
    ],
  ),
  _CityRouteProfile(
      key: 'nara',
      centerLat: 34.6851,
      centerLng: 135.843,
      coverageRadiusKm: 12,
      transitMode: TransportMode.bus,
      walkingCircuity: 1.18,
      roadCircuity: 1.2,
      transitCircuity: 1.16,
      transitSpeedKmh: 18,
      accessMinutes: 7,
      waitMinutes: 7,
      maximumWalkingKm: 4.5,
      noTransferUpToKm: 4,
      twoTransfersAfterKm: 12,
      baseTransitFareYen: 220,
      transitYenPerKm: 25,
      taxiCoreSpeedKmh: 22,
      taxiOuterSpeedKmh: 28,
      taxiBaseFareYen: 600,
      taxiYenPerKm: 350),
  _CityRouteProfile(
      key: 'sapporo',
      centerLat: 43.0618,
      centerLng: 141.3545,
      coverageRadiusKm: 20,
      transitMode: TransportMode.metro,
      walkingCircuity: 1.2,
      roadCircuity: 1.22,
      transitCircuity: 1.15,
      transitSpeedKmh: 28,
      accessMinutes: 8,
      waitMinutes: 5,
      maximumWalkingKm: 4,
      noTransferUpToKm: 4.5,
      twoTransfersAfterKm: 14,
      baseTransitFareYen: 210,
      transitYenPerKm: 28,
      taxiCoreSpeedKmh: 21,
      taxiOuterSpeedKmh: 29,
      taxiBaseFareYen: 670,
      taxiYenPerKm: 360),
  _CityRouteProfile(
      key: 'kanazawa',
      centerLat: 36.561,
      centerLng: 136.656,
      coverageRadiusKm: 14,
      transitMode: TransportMode.bus,
      walkingCircuity: 1.2,
      roadCircuity: 1.2,
      transitCircuity: 1.16,
      transitSpeedKmh: 17,
      accessMinutes: 7,
      waitMinutes: 7,
      maximumWalkingKm: 4.2,
      noTransferUpToKm: 4,
      twoTransfersAfterKm: 11,
      baseTransitFareYen: 210,
      transitYenPerKm: 25,
      taxiCoreSpeedKmh: 22,
      taxiOuterSpeedKmh: 28,
      taxiBaseFareYen: 600,
      taxiYenPerKm: 350),
  _CityRouteProfile(
      key: 'yokohama',
      centerLat: 35.4548,
      centerLng: 139.6317,
      coverageRadiusKm: 20,
      transitMode: TransportMode.train,
      walkingCircuity: 1.2,
      roadCircuity: 1.25,
      transitCircuity: 1.16,
      transitSpeedKmh: 29,
      accessMinutes: 8,
      waitMinutes: 5,
      maximumWalkingKm: 4,
      noTransferUpToKm: 4.5,
      twoTransfersAfterKm: 14,
      baseTransitFareYen: 180,
      transitYenPerKm: 28,
      taxiCoreSpeedKmh: 21,
      taxiOuterSpeedKmh: 29,
      taxiBaseFareYen: 500,
      taxiYenPerKm: 380),
  _CityRouteProfile(
      key: 'hakone',
      centerLat: 35.232,
      centerLng: 139.027,
      coverageRadiusKm: 20,
      transitMode: TransportMode.regionalTrain,
      walkingCircuity: 1.3,
      roadCircuity: 1.28,
      transitCircuity: 1.3,
      transitSpeedKmh: 16,
      accessMinutes: 9,
      waitMinutes: 9,
      maximumWalkingKm: 3,
      noTransferUpToKm: 3,
      twoTransfersAfterKm: 10,
      baseTransitFareYen: 300,
      transitYenPerKm: 55,
      taxiCoreSpeedKmh: 24,
      taxiOuterSpeedKmh: 31,
      taxiBaseFareYen: 700,
      taxiYenPerKm: 430),
  _CityRouteProfile(
      key: 'kamakura',
      centerLat: 35.319,
      centerLng: 139.55,
      coverageRadiusKm: 18,
      transitMode: TransportMode.regionalTrain,
      walkingCircuity: 1.22,
      roadCircuity: 1.25,
      transitCircuity: 1.18,
      transitSpeedKmh: 22,
      accessMinutes: 8,
      waitMinutes: 7,
      maximumWalkingKm: 4,
      noTransferUpToKm: 4,
      twoTransfersAfterKm: 13,
      baseTransitFareYen: 200,
      transitYenPerKm: 30,
      taxiCoreSpeedKmh: 20,
      taxiOuterSpeedKmh: 27,
      taxiBaseFareYen: 600,
      taxiYenPerKm: 390),
  _CityRouteProfile(
      key: 'fuji',
      centerLat: 35.5,
      centerLng: 138.77,
      coverageRadiusKm: 32,
      transitMode: TransportMode.bus,
      walkingCircuity: 1.3,
      roadCircuity: 1.3,
      transitCircuity: 1.35,
      transitSpeedKmh: 20,
      accessMinutes: 10,
      waitMinutes: 10,
      maximumWalkingKm: 3,
      noTransferUpToKm: 4,
      twoTransfersAfterKm: 16,
      baseTransitFareYen: 300,
      transitYenPerKm: 45,
      taxiCoreSpeedKmh: 25,
      taxiOuterSpeedKmh: 34,
      taxiBaseFareYen: 700,
      taxiYenPerKm: 440),
  _CityRouteProfile(
      key: 'nikko',
      centerLat: 36.75,
      centerLng: 139.57,
      coverageRadiusKm: 28,
      transitMode: TransportMode.bus,
      walkingCircuity: 1.28,
      roadCircuity: 1.3,
      transitCircuity: 1.3,
      transitSpeedKmh: 19,
      accessMinutes: 9,
      waitMinutes: 9,
      maximumWalkingKm: 3.2,
      noTransferUpToKm: 4,
      twoTransfersAfterKm: 14,
      baseTransitFareYen: 250,
      transitYenPerKm: 40,
      taxiCoreSpeedKmh: 24,
      taxiOuterSpeedKmh: 32,
      taxiBaseFareYen: 700,
      taxiYenPerKm: 420),
  _CityRouteProfile(
      key: 'nagoya',
      centerLat: 35.1709,
      centerLng: 136.8815,
      coverageRadiusKm: 28,
      transitMode: TransportMode.metro,
      walkingCircuity: 1.2,
      roadCircuity: 1.24,
      transitCircuity: 1.16,
      transitSpeedKmh: 29,
      accessMinutes: 8,
      waitMinutes: 5,
      maximumWalkingKm: 4,
      noTransferUpToKm: 4.5,
      twoTransfersAfterKm: 15,
      baseTransitFareYen: 210,
      transitYenPerKm: 27,
      taxiCoreSpeedKmh: 21,
      taxiOuterSpeedKmh: 29,
      taxiBaseFareYen: 500,
      taxiYenPerKm: 370),
  _CityRouteProfile(
      key: 'kobe',
      centerLat: 34.6901,
      centerLng: 135.1955,
      coverageRadiusKm: 22,
      transitMode: TransportMode.train,
      walkingCircuity: 1.22,
      roadCircuity: 1.25,
      transitCircuity: 1.18,
      transitSpeedKmh: 27,
      accessMinutes: 8,
      waitMinutes: 5,
      maximumWalkingKm: 4,
      noTransferUpToKm: 4.2,
      twoTransfersAfterKm: 14,
      baseTransitFareYen: 180,
      transitYenPerKm: 28,
      taxiCoreSpeedKmh: 20,
      taxiOuterSpeedKmh: 28,
      taxiBaseFareYen: 600,
      taxiYenPerKm: 370),
  _CityRouteProfile(
      key: 'himeji',
      centerLat: 34.827,
      centerLng: 134.69,
      coverageRadiusKm: 14,
      transitMode: TransportMode.bus,
      walkingCircuity: 1.2,
      roadCircuity: 1.2,
      transitCircuity: 1.16,
      transitSpeedKmh: 18,
      accessMinutes: 7,
      waitMinutes: 7,
      maximumWalkingKm: 4,
      noTransferUpToKm: 4,
      twoTransfersAfterKm: 12,
      baseTransitFareYen: 210,
      transitYenPerKm: 25,
      taxiCoreSpeedKmh: 22,
      taxiOuterSpeedKmh: 29,
      taxiBaseFareYen: 650,
      taxiYenPerKm: 350),
];

final Map<String, _CityRouteProfile> _profilesByKey = {
  for (final profile in _profiles) profile.key: profile,
};

double _distanceTo(double latitude, double longitude, TripLocation to) {
  return _haversineKm(latitude, longitude, to.latitude, to.longitude);
}

double _distanceKm(TripLocation from, TripLocation to) {
  return _haversineKm(
    from.latitude,
    from.longitude,
    to.latitude,
    to.longitude,
  );
}

double _haversineKm(
  double fromLatitude,
  double fromLongitude,
  double toLatitude,
  double toLongitude,
) {
  const earthRadiusKm = 6371.0;
  final latitudeDelta = _radians(toLatitude - fromLatitude);
  final longitudeDelta = _radians(toLongitude - fromLongitude);
  final fromLat = _radians(fromLatitude);
  final toLat = _radians(toLatitude);
  final haversine = math.pow(math.sin(latitudeDelta / 2), 2) +
      math.cos(fromLat) *
          math.cos(toLat) *
          math.pow(math.sin(longitudeDelta / 2), 2);
  final arc = 2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  return earthRadiusKm * arc;
}

double _radians(double degrees) => degrees * math.pi / 180;
