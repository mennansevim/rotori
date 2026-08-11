import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/data/offline_japan_route_matrix.dart';
import 'package:rotori/domain/city_places.dart';
import 'package:rotori/domain/route_matrix.dart';

void main() {
  const shibuya = TripLocation(
    id: 'shibuya',
    name: 'Shibuya Crossing',
    latitude: 35.6595,
    longitude: 139.7005,
    city: 'Tokyo',
  );
  const meiji = TripLocation(
    id: 'meiji',
    name: 'Meiji Jingu',
    latitude: 35.6764,
    longitude: 139.6993,
    city: 'Tokyo',
  );
  const teamLab = TripLocation(
    id: 'teamlab',
    name: 'teamLab Planets',
    latitude: 35.6486,
    longitude: 139.7869,
    city: 'Tokyo',
  );

  test('yakın Tokyo noktalarında yürüyüş gerçek bir adaydır', () {
    final matrix = buildOfflineJapanRouteMatrix(
      const [shibuya, meiji],
      day: DateTime(2026, 8, 11, 8),
    );

    final options = matrix.options(shibuya.id, meiji.id);
    final walking = options.singleWhere(
      (option) => option.mode == TransportMode.walking,
    );

    expect(walking.doorToDoorMinutes, inInclusiveRange(25, 35));
    expect(walking.estimatedCostYen, 0);
    expect(walking.isEstimated, isTrue);
    expect(walking.lineId, isNull);
    expect(walking.directionId, isNull);
  });

  test('optimizer semt kümelerini aynı offline paketten alır', () {
    final shibuyaCluster = offlineJapanRouteClusterId(
      city: shibuya.city,
      latitude: shibuya.latitude,
      longitude: shibuya.longitude,
    );
    final meijiCluster = offlineJapanRouteClusterId(
      city: meiji.city,
      latitude: meiji.latitude,
      longitude: meiji.longitude,
    );
    final bayCluster = offlineJapanRouteClusterId(
      city: teamLab.city,
      latitude: teamLab.latitude,
      longitude: teamLab.longitude,
    );

    expect(shibuyaCluster, 'tokyo:shibuya-harajuku');
    expect(meijiCluster, shibuyaCluster);
    expect(bayCluster, 'tokyo:bay');
  });

  test('Tokyo batı-bay zor bağlantısı küratörlü ve yönlüdür', () {
    final matrix = buildOfflineJapanRouteMatrix(
      const [shibuya, teamLab],
      day: DateTime(2026, 8, 11, 8),
    );

    final outbound = _publicTransport(matrix, shibuya.id, teamLab.id);
    final inbound = _publicTransport(matrix, teamLab.id, shibuya.id);

    expect(outbound.mode, TransportMode.metro);
    expect(outbound.doorToDoorMinutes, 39);
    expect(inbound.doorToDoorMinutes, 41);
    expect(outbound.transferCount, 1);
    expect(outbound.providerId, kOfflineJapanRouteProviderId);
  });

  test('Hiroshima-Miyajima genel mesafe formülüne bırakılmaz', () {
    const center = TripLocation(
      id: 'peace',
      name: 'Barış Anıtı Parkı',
      latitude: 34.3955,
      longitude: 132.4536,
      city: 'Hiroshima',
    );
    const miyajima = TripLocation(
      id: 'miyajima',
      name: 'Itsukushima (Miyajima)',
      latitude: 34.296,
      longitude: 132.3197,
      city: 'Hiroshima',
    );
    final matrix = buildOfflineJapanRouteMatrix(
      const [center, miyajima],
      day: DateTime(2026, 8, 11, 8),
    );

    final outbound = _publicTransport(matrix, center.id, miyajima.id);
    final inbound = _publicTransport(matrix, miyajima.id, center.id);
    expect(outbound.mode, TransportMode.regionalTrain);
    expect(outbound.doorToDoorMinutes, 66);
    expect(inbound.doorToDoorMinutes, 70);
    expect(outbound.walkingMinutes, 16);
  });

  test('sabah merkez yönü ile ters yön aynı süreyi uydurmaz', () {
    const central = TripLocation(
      id: 'central',
      name: 'Ginza',
      latitude: 35.6717,
      longitude: 139.765,
      city: 'Tokyo',
    );
    const bay = TripLocation(
      id: 'odaiba',
      name: 'Odaiba',
      latitude: 35.6276,
      longitude: 139.7763,
      city: 'Tokyo',
    );
    final matrix = buildOfflineJapanRouteMatrix(
      const [central, bay],
      day: DateTime(2026, 8, 11, 8),
    );

    final towardCore = _publicTransport(matrix, bay.id, central.id);
    final awayFromCore = _publicTransport(matrix, central.id, bay.id);
    expect(towardCore.doorToDoorMinutes,
        greaterThanOrEqualTo(awayFromCore.doorToDoorMinutes));
    expect(matrix.version, contains('weekday-morning'));
  });

  test('her ücretli bacakta süre bileşenleri ve araç ücreti tutarlıdır', () {
    final matrix = buildOfflineJapanRouteMatrix(
      const [shibuya, teamLab],
      day: DateTime(2026, 8, 16, 13),
    );

    for (final option in matrix.options(shibuya.id, teamLab.id)) {
      expect(
        option.resolvedAccessMinutes +
            option.resolvedTransitWaitMinutes +
            option.resolvedRideMinutes +
            option.bufferMinutes,
        option.doorToDoorMinutes,
      );
      expect(option.isEstimated, isTrue);
      expect(option.lineId, isNull);
      expect(option.directionId, isNull);
    }
    final taxi = matrix
        .options(shibuya.id, teamLab.id)
        .singleWhere((option) => option.mode == TransportMode.taxi);
    expect(taxi.fareBasis, FareBasis.perVehicle);
    expect(matrix.version, contains('weekend-daytime'));
  });

  test('bilinmeyen Japonya noktası da internetsiz kullanılabilir kalır', () {
    const a = TripLocation(
      id: 'unknown-a',
      name: 'A',
      latitude: 33.59,
      longitude: 130.4,
      city: 'Fukuoka',
    );
    const b = TripLocation(
      id: 'unknown-b',
      name: 'B',
      latitude: 33.61,
      longitude: 130.43,
      city: 'Fukuoka',
    );
    final matrix = buildOfflineJapanRouteMatrix(
      const [a, b],
      day: DateTime(2026, 8, 11, 11),
    );

    expect(matrix.options(a.id, b.id), isNotEmpty);
    expect(
      matrix.options(a.id, b.id).map((option) => option.mode),
      containsAll([TransportMode.train, TransportMode.taxi]),
    );
  });

  test('repository aynı girdide semantik olarak aynı matrisi üretir', () async {
    const repository = OfflineJapanRouteMatrixRepository();
    final first = await repository.getRouteMatrix(
      locations: const [shibuya, teamLab],
      day: DateTime(2026, 8, 11, 8),
      preferences: const RoutePreferences(),
    );
    final second = await repository.getRouteMatrix(
      locations: const [shibuya, teamLab],
      day: DateTime(2026, 8, 11, 8),
      preferences: const RoutePreferences(),
    );

    expect(second.version, first.version);
    expect(
      second.options(shibuya.id, teamLab.id).map(_signature),
      first.options(shibuya.id, teamLab.id).map(_signature),
    );
  });

  test('tüm küratörlü şehirlerde her POI çifti geçerli ve eksiksizdir', () {
    for (final city in kCityData) {
      final locations = [
        for (final place in city.places)
          TripLocation(
            id: place.id,
            name: place.name,
            latitude: place.lat,
            longitude: place.lng,
            city: city.label,
          ),
      ];
      final matrix = buildOfflineJapanRouteMatrix(
        locations,
        day: DateTime(2026, 8, 11, 8),
      );

      expect(
        matrix.entries,
        hasLength(locations.length * (locations.length - 1)),
        reason: '${city.label} yönlü matris eksik',
      );
      for (final entry in matrix.entries) {
        expect(entry.options, isNotEmpty, reason: city.label);
        final coLocated = entry.options.length == 1 &&
            entry.options.single.mode == TransportMode.walking &&
            entry.options.single.doorToDoorMinutes == 0;
        if (!coLocated) {
          expect(
            entry.options.any((option) => option.mode == TransportMode.taxi),
            isTrue,
            reason: '${city.label} taksi alternatifi eksik',
          );
        }
        for (final option in entry.options) {
          expect(option.isValid, isTrue, reason: city.label);
          expect(option.isEstimated, isTrue, reason: city.label);
          expect(option.providerId, kOfflineJapanRouteProviderId);
          expect(option.lineId, isNull);
          expect(option.directionId, isNull);
          expect(
            option.resolvedAccessMinutes +
                option.resolvedTransitWaitMinutes +
                option.resolvedRideMinutes +
                option.bufferMinutes,
            option.doorToDoorMinutes,
            reason: '${city.label} süre bileşenleri tutarsız',
          );
          expect(
            option.doorToDoorMinutes,
            lessThan(240),
            reason: '${city.label} şehir içi süre olağandışı',
          );
        }
      }
    }
  });
}

TransportOption _publicTransport(RouteMatrix matrix, String from, String to) {
  return matrix.options(from, to).firstWhere(
        (option) =>
            option.mode != TransportMode.walking &&
            option.mode != TransportMode.taxi,
      );
}

String _signature(TransportOption option) {
  return '${option.mode.name}:${option.doorToDoorMinutes}:'
      '${option.walkingMinutes}:${option.waitingMinutes}:'
      '${option.transferCount}:${option.estimatedCostYen}';
}
