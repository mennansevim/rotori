import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/data/route_matrix_cache.dart';
import 'package:japan_trip/data/route_matrix_remote.dart';
import 'package:japan_trip/data/route_matrix_resolution.dart';
import 'package:japan_trip/domain/route_matrix.dart';

void main() {
  const a = TripLocation(
    id: 'shibuya',
    name: 'Shibuya',
    latitude: 35.6595,
    longitude: 139.7005,
  );
  const b = TripLocation(
    id: 'harajuku',
    name: 'Harajuku',
    latitude: 35.6701,
    longitude: 139.7027,
  );
  final day = DateTime(2026, 7, 30, 9);
  const preferences = RoutePreferences();

  RouteMatrix matrix({String version = 'provider-v1'}) {
    return RouteMatrix(
      version: version,
      entries: [
        RouteMatrixEntry(
          fromLocationId: a.id,
          toLocationId: b.id,
          options: const [
            TransportOption(
              mode: TransportMode.walking,
              doorToDoorMinutes: 22,
              walkingMinutes: 22,
              waitingMinutes: 0,
              transferCount: 0,
              estimatedCostYen: 0,
              reliabilityScore: 0.96,
            ),
          ],
        ),
        RouteMatrixEntry(
          fromLocationId: b.id,
          toLocationId: a.id,
          options: const [
            TransportOption(
              mode: TransportMode.walking,
              doorToDoorMinutes: 31,
              walkingMinutes: 31,
              waitingMinutes: 0,
              transferCount: 0,
              estimatedCostYen: 0,
              reliabilityScore: 0.92,
            ),
          ],
        ),
      ],
    );
  }

  test('remote sınır backend gateway isteğini normalize modele taşır',
      () async {
    final gateway = _FakeGateway(matrix());
    final repository = RemoteRouteMatrixRepository(
      gateway: gateway,
      providerId: 'edge-function',
    );

    final result = await repository.getRouteMatrix(
      locations: const [a, b],
      day: day,
      preferences: preferences,
    );

    expect(gateway.callCount, 1);
    expect(gateway.lastRequest?.locations.map((item) => item.id),
        ['shibuya', 'harajuku']);
    expect(result.version, 'provider-v1');
    expect(result.options(a.id, b.id).single.doorToDoorMinutes, 22);
  });

  test('remote sınır geçersiz yön girdisini reddeder', () async {
    final invalid = RouteMatrix(
      entries: [
        RouteMatrixEntry(
          fromLocationId: 'unknown',
          toLocationId: b.id,
          options: const [
            TransportOption(
              mode: TransportMode.walking,
              doorToDoorMinutes: 1,
              walkingMinutes: 1,
              waitingMinutes: 0,
              transferCount: 0,
              estimatedCostYen: 0,
              reliabilityScore: 1,
            ),
          ],
        ),
      ],
    );
    final repository = RemoteRouteMatrixRepository(
      gateway: _FakeGateway(invalid),
      providerId: 'edge-function',
    );

    expect(
      () => repository.getRouteMatrix(
        locations: const [a, b],
        day: day,
        preferences: preferences,
      ),
      throwsA(
        isA<RouteMatrixFailure>().having(
          (failure) => failure.kind,
          'kind',
          RouteMatrixFailureKind.invalidResponse,
        ),
      ),
    );
  });

  test('resolver ikinci istekte fresh cache kullanır', () async {
    final repository = FakeRouteMatrixRepository(matrix());
    final cache = InMemoryRouteMatrixSnapshotCache();
    final resolver = ResilientRouteMatrixResolver(
      primary: repository,
      primaryProviderId: 'primary',
      cache: cache,
    );

    final first = await resolver.resolve(
      locations: const [a, b],
      day: day,
      preferences: preferences,
    );
    final second = await resolver.resolve(
      locations: const [b, a],
      day: day,
      preferences: preferences,
    );

    expect(first.source, RouteMatrixSource.primaryProvider);
    expect(second.source, RouteMatrixSource.freshCache);
    expect(repository.callCount, 1);
    expect(cache.hitCount, 1);
  });

  test('matrix snapshot TTL sonrası sağlayıcı yeniden çağrılır', () async {
    var now = DateTime.utc(2026, 7, 30, 9);
    final repository = FakeRouteMatrixRepository(matrix());
    final resolver = ResilientRouteMatrixResolver(
      primary: repository,
      primaryProviderId: 'primary',
      cache: InMemoryRouteMatrixSnapshotCache(
        ttl: const Duration(hours: 1),
        clock: () => now,
      ),
    );

    await resolver.resolve(
      locations: const [a, b],
      day: day,
      preferences: preferences,
    );
    now = now.add(const Duration(hours: 1, minutes: 1));
    final result = await resolver.resolve(
      locations: const [a, b],
      day: day,
      preferences: preferences,
    );

    expect(result.source, RouteMatrixSource.primaryProvider);
    expect(repository.callCount, 2);
  });

  test('ana sağlayıcı hata verirse alternatif sağlayıcı kullanılır', () async {
    final fallback = FakeRouteMatrixRepository(
      matrix(version: 'alternative-v1'),
    );
    final resolver = ResilientRouteMatrixResolver(
      primary: const _FailingRepository(),
      primaryProviderId: 'primary',
      alternative: fallback,
      alternativeProviderId: 'alternative',
      cache: InMemoryRouteMatrixSnapshotCache(),
    );

    final result = await resolver.resolve(
      locations: const [a, b],
      day: day,
      preferences: preferences,
    );

    expect(result.source, RouteMatrixSource.alternativeProvider);
    expect(result.matrix?.version, 'alternative-v1');
    expect(result.failures, hasLength(1));
  });

  test('alternatif sağlayıcı sonucu sonraki istekte cache üzerinden kullanılır',
      () async {
    final primary = _CountingFailingRepository();
    final fallback = FakeRouteMatrixRepository(
      matrix(version: 'alternative-v1'),
    );
    final resolver = ResilientRouteMatrixResolver(
      primary: primary,
      primaryProviderId: 'primary',
      alternative: fallback,
      alternativeProviderId: 'alternative',
      cache: InMemoryRouteMatrixSnapshotCache(),
    );

    await resolver.resolve(
      locations: const [a, b],
      day: day,
      preferences: preferences,
    );
    final second = await resolver.resolve(
      locations: const [b, a],
      day: day,
      preferences: preferences,
    );

    expect(second.source, RouteMatrixSource.freshCache);
    expect(primary.callCount, 1);
    expect(fallback.callCount, 1);
  });

  test('tüm sağlayıcılar hata verirse stale cache tahmini işaretlenir',
      () async {
    var now = DateTime.utc(2026, 7, 30, 9);
    final cache = InMemoryRouteMatrixSnapshotCache(
      ttl: const Duration(minutes: 30),
      clock: () => now,
    );
    final cacheKey = RouteMatrixRequestCacheKey(
      locations: const [a, b],
      day: day,
      preferences: preferences,
      provider: 'primary',
    );
    cache.put(cacheKey, matrix());
    now = now.add(const Duration(hours: 1));

    final resolver = ResilientRouteMatrixResolver(
      primary: const _FailingRepository(),
      primaryProviderId: 'primary',
      cache: cache,
    );
    final result = await resolver.resolve(
      locations: const [a, b],
      day: day,
      preferences: preferences,
    );

    expect(result.source, RouteMatrixSource.staleCache);
    expect(result.isEstimated, isTrue);
    expect(
      result.matrix?.options(a.id, b.id).every((option) => option.isEstimated),
      isTrue,
    );
  });

  test('rota ve cache yoksa süre uydurmak yerine optimize edilemez döner',
      () async {
    final resolver = ResilientRouteMatrixResolver(
      primary: const _FailingRepository(),
      primaryProviderId: 'primary',
      cache: InMemoryRouteMatrixSnapshotCache(),
    );

    final result = await resolver.resolve(
      locations: const [a, b],
      day: day,
      preferences: preferences,
    );

    expect(result.source, RouteMatrixSource.unavailable);
    expect(result.matrix, isNull);
    expect(result.coordinatePreFilterOnly, isTrue);
  });

  test('repository adaptörü fallback sonucu mevcut sözleşmeye döndürür',
      () async {
    final fallbackMatrix = matrix(version: 'fallback');
    final repository = ResilientRouteMatrixRepository(
      ResilientRouteMatrixResolver(
        primary: const _FailingRepository(),
        primaryProviderId: 'primary',
        alternative: FakeRouteMatrixRepository(fallbackMatrix),
        alternativeProviderId: 'alternative',
        cache: InMemoryRouteMatrixSnapshotCache(),
      ),
    );

    final result = await repository.getRouteMatrix(
      locations: const [a, b],
      day: day,
      preferences: preferences,
    );

    expect(result.version, 'fallback');
  });
}

class _FakeGateway implements RouteMatrixBackendGateway {
  _FakeGateway(this.matrix);

  final RouteMatrix matrix;
  int callCount = 0;
  RouteMatrixBackendRequest? lastRequest;

  @override
  Future<RouteMatrix> fetchMatrix(RouteMatrixBackendRequest request) async {
    callCount++;
    lastRequest = request;
    return matrix;
  }
}

class _FailingRepository implements RouteMatrixRepository {
  const _FailingRepository();

  @override
  Future<RouteMatrix> getRouteMatrix({
    required List<TripLocation> locations,
    required DateTime day,
    required RoutePreferences preferences,
  }) {
    throw const RouteMatrixFailure(
      kind: RouteMatrixFailureKind.network,
      message: 'offline',
    );
  }
}

class _CountingFailingRepository implements RouteMatrixRepository {
  int callCount = 0;

  @override
  Future<RouteMatrix> getRouteMatrix({
    required List<TripLocation> locations,
    required DateTime day,
    required RoutePreferences preferences,
  }) {
    callCount++;
    throw const RouteMatrixFailure(
      kind: RouteMatrixFailureKind.network,
      message: 'offline',
    );
  }
}
