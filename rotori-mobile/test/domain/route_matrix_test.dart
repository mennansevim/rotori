import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/data/route_matrix_resolution.dart';
import 'package:rotori/domain/route_matrix.dart';

void main() {
  const a = TripLocation(
    id: 'a',
    name: 'A',
    latitude: 35,
    longitude: 139,
  );
  const b = TripLocation(
    id: 'b',
    name: 'B',
    latitude: 35.1,
    longitude: 139.1,
  );

  test('rota matrisi A → B ve B → A yönlerini ayrı tutar', () {
    final matrix = RouteMatrix(
      version: 'test-v1',
      entries: [
        RouteMatrixEntry(
          fromLocationId: 'a',
          toLocationId: 'b',
          options: [_walking(12)],
        ),
        RouteMatrixEntry(
          fromLocationId: 'b',
          toLocationId: 'a',
          options: [_walking(27)],
        ),
      ],
    );

    expect(matrix.options('a', 'b').single.doorToDoorMinutes, 12);
    expect(matrix.options('b', 'a').single.doorToDoorMinutes, 27);
    expect(matrix.version, 'test-v1');
  });

  test('aynı konum geçişi dış veri gerektirmeden sıfır dakika döner', () {
    final matrix = RouteMatrix(entries: const []);

    final option = matrix.options('a', 'a').single;

    expect(option.mode, TransportMode.walking);
    expect(option.doorToDoorMinutes, 0);
    expect(option.estimatedCostYen, 0);
  });

  test('fake repository deterministik matrisi ve çağrı bilgisini korur',
      () async {
    final matrix = RouteMatrix(entries: const [], version: 'fake');
    final repository = FakeRouteMatrixRepository(matrix);
    final day = DateTime(2026, 9, 4);
    const preferences = RoutePreferences(
      profile: RouteOptimizationProfile.cheapest,
    );

    final result = await repository.getRouteMatrix(
      locations: const [a, b],
      day: day,
      preferences: preferences,
    );

    expect(identical(result, matrix), isTrue);
    expect(repository.callCount, 1);
    expect(repository.lastRequestedLocationIds, ['a', 'b']);
    expect(repository.lastRequestedDay, day);
    expect(repository.lastRequestedPreferences?.profile,
        RouteOptimizationProfile.cheapest);
  });

  test('koordinat fallback matrisi tüm yönleri tahmini olarak üretir', () {
    final matrix = buildCoordinateFallbackMatrix(const [a, b]);

    expect(matrix.version, 'coordinate-estimate-v1');
    expect(matrix.options('a', 'b'), hasLength(1));
    expect(matrix.options('b', 'a'), hasLength(1));
    expect(matrix.options('a', 'b').single.isEstimated, isTrue);
    expect(matrix.options('a', 'b').single.isValid, isTrue);
    expect(matrix.options('a', 'b').single.doorToDoorMinutes, greaterThan(0));
  });

  test('6 kişilik taksi iki araç, toplu taşıma kişi başı ücretlenir', () {
    const taxi = TransportOption(
      mode: TransportMode.taxi,
      doorToDoorMinutes: 20,
      walkingMinutes: 1,
      waitingMinutes: 3,
      transferCount: 0,
      estimatedCostYen: 2400,
      reliabilityScore: .9,
      fareBasis: FareBasis.perVehicle,
      vehicleCapacity: 4,
    );
    const train = TransportOption(
      mode: TransportMode.train,
      doorToDoorMinutes: 30,
      walkingMinutes: 5,
      waitingMinutes: 4,
      transferCount: 0,
      estimatedCostYen: 300,
      reliabilityScore: .95,
      fareBasis: FareBasis.perPerson,
    );

    final taxiCost = taxi.costForParty(6);
    final trainCost = train.costForParty(6);
    expect(taxiCost.vehicleCount, 2);
    expect(taxiCost.partyTotalCostYen, 4800);
    expect(taxiCost.costPerPersonYen, 800);
    expect(trainCost.vehicleCount, 0);
    expect(trainCost.partyTotalCostYen, 1800);
  });

  test('door-to-door süre bileşenleri açıkça çözümlenir', () {
    const option = TransportOption(
      mode: TransportMode.metro,
      doorToDoorMinutes: 24,
      walkingMinutes: 7,
      waitingMinutes: 4,
      transferCount: 0,
      estimatedCostYen: 220,
      reliabilityScore: .95,
      rideMinutes: 13,
      accessMinutes: 7,
      transitWaitMinutes: 4,
    );

    expect(
      option.resolvedRideMinutes +
          option.resolvedAccessMinutes +
          option.resolvedTransitWaitMinutes +
          option.bufferMinutes,
      option.doorToDoorMinutes,
    );
  });
}

TransportOption _walking(int minutes) => TransportOption(
      mode: TransportMode.walking,
      doorToDoorMinutes: minutes,
      walkingMinutes: minutes,
      waitingMinutes: 0,
      transferCount: 0,
      estimatedCostYen: 0,
      reliabilityScore: 1,
    );
