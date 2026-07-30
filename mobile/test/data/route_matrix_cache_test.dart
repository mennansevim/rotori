import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/data/route_matrix_cache.dart';

void main() {
  RouteMatrixCacheKey key({
    RouteCacheCoordinate from = const RouteCacheCoordinate(35.65951, 139.70054),
    RouteCacheCoordinate to = const RouteCacheCoordinate(35.67011, 139.70269),
    String mode = 'walking',
  }) {
    return RouteMatrixCacheKey(
      from: from,
      to: to,
      transportMode: mode,
      dayType: RouteDayType.weekday,
      timeBucket: RouteTimeBucket.morning,
      preferenceProfile: 'balanced',
      provider: 'backend-v1',
    );
  }

  test('aynı istek ve yakın koordinat cache hit üretir', () {
    final cache = InMemoryRouteMatrixResultCache<String>();
    cache.put(key(), 'shibuya-to-harajuku');

    final lookup = cache.lookup(
      key(
        from: const RouteCacheCoordinate(35.659509, 139.700541),
        to: const RouteCacheCoordinate(35.670109, 139.702688),
      ),
    );

    expect(lookup.state, RouteCacheState.fresh);
    expect(lookup.value, 'shibuya-to-harajuku');
  });

  test('TTL dolduğunda fresh miss, izin verilirse stale hit döner', () {
    var now = DateTime.utc(2026, 7, 30, 9);
    final cache = InMemoryRouteMatrixResultCache<String>(
      ttlConfig: const RouteMatrixCacheTtlConfig(
        taxi: Duration(hours: 2),
      ),
      clock: () => now,
    );
    final taxiKey = key(mode: 'taxi');
    cache.put(taxiKey, 'taxi-estimate');

    now = now.add(const Duration(hours: 2, minutes: 1));

    expect(cache.lookup(taxiKey).state, RouteCacheState.miss);
    final stale = cache.lookup(taxiKey, allowStale: true);
    expect(stale.state, RouteCacheState.stale);
    expect(stale.value, 'taxi-estimate');
  });

  test('A→B ile B→A farklı cache anahtarıdır', () {
    const a = RouteCacheCoordinate(35.6595, 139.7005);
    const b = RouteCacheCoordinate(35.6701, 139.7027);
    final cache = InMemoryRouteMatrixResultCache<int>();

    cache
      ..put(key(from: a, to: b), 22)
      ..put(key(from: b, to: a), 31);

    expect(cache.lookup(key(from: a, to: b)).value, 22);
    expect(cache.lookup(key(from: b, to: a)).value, 31);
    expect(key(from: a, to: b), isNot(key(from: b, to: a)));
  });

  test('varsayılan TTL ulaşım türüne göre maliyeti dengeler', () {
    const config = RouteMatrixCacheTtlConfig();

    expect(config.forTransportMode('walking'), const Duration(days: 30));
    expect(config.forTransportMode('train'), const Duration(days: 7));
    expect(config.forTransportMode('bus'), const Duration(days: 3));
    expect(config.forTransportMode('taxi'), const Duration(hours: 3));
  });
}
