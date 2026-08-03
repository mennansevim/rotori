import '../domain/route_matrix.dart';

enum RouteDayType { weekday, weekend, holiday }

enum RouteTimeBucket {
  earlyMorning,
  morning,
  noon,
  afternoon,
  evening,
  night,
}

class RouteCacheCoordinate {
  const RouteCacheCoordinate(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  RouteCacheCoordinate rounded({int decimalPlaces = 4}) {
    assert(decimalPlaces >= 0 && decimalPlaces <= 6);
    final factor = _powerOfTen(decimalPlaces);
    return RouteCacheCoordinate(
      (latitude * factor).round() / factor,
      (longitude * factor).round() / factor,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RouteCacheCoordinate &&
        latitude == other.latitude &&
        longitude == other.longitude;
  }

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// Anahtar yönlüdür: `from` ve `to` bilerek sıralanmaz veya normalize edilmez.
class RouteMatrixCacheKey {
  RouteMatrixCacheKey({
    required RouteCacheCoordinate from,
    required RouteCacheCoordinate to,
    required this.transportMode,
    required this.dayType,
    required this.timeBucket,
    required this.preferenceProfile,
    required this.provider,
    this.coordinateDecimalPlaces = 4,
  })  : assert(transportMode != ''),
        assert(preferenceProfile != ''),
        assert(provider != ''),
        assert(coordinateDecimalPlaces >= 0 && coordinateDecimalPlaces <= 6),
        from = from.rounded(decimalPlaces: coordinateDecimalPlaces),
        to = to.rounded(decimalPlaces: coordinateDecimalPlaces);

  final RouteCacheCoordinate from;
  final RouteCacheCoordinate to;
  final String transportMode;
  final RouteDayType dayType;
  final RouteTimeBucket timeBucket;
  final String preferenceProfile;
  final String provider;
  final int coordinateDecimalPlaces;

  @override
  bool operator ==(Object other) {
    return other is RouteMatrixCacheKey &&
        from == other.from &&
        to == other.to &&
        transportMode == other.transportMode &&
        dayType == other.dayType &&
        timeBucket == other.timeBucket &&
        preferenceProfile == other.preferenceProfile &&
        provider == other.provider &&
        coordinateDecimalPlaces == other.coordinateDecimalPlaces;
  }

  @override
  int get hashCode => Object.hash(
        from,
        to,
        transportMode,
        dayType,
        timeBucket,
        preferenceProfile,
        provider,
        coordinateDecimalPlaces,
      );
}

class RouteMatrixCacheTtlConfig {
  const RouteMatrixCacheTtlConfig({
    this.walking = const Duration(days: 30),
    this.train = const Duration(days: 7),
    this.metro = const Duration(days: 7),
    this.bus = const Duration(days: 3),
    this.taxi = const Duration(hours: 3),
    this.shinkansen = const Duration(days: 7),
    this.regionalTrain = const Duration(days: 7),
    this.unknown = const Duration(hours: 1),
  });

  final Duration walking;
  final Duration train;
  final Duration metro;
  final Duration bus;
  final Duration taxi;
  final Duration shinkansen;
  final Duration regionalTrain;
  final Duration unknown;

  Duration forTransportMode(String mode) {
    return switch (mode) {
      'walking' => walking,
      'train' => train,
      'metro' => metro,
      'bus' => bus,
      'taxi' => taxi,
      'shinkansen' => shinkansen,
      'regionalTrain' => regionalTrain,
      _ => unknown,
    };
  }
}

enum RouteCacheState { miss, fresh, stale }

class RouteCacheLookup<T> {
  const RouteCacheLookup._({
    required this.state,
    this.value,
    this.storedAt,
    this.expiresAt,
  });

  const RouteCacheLookup.miss() : this._(state: RouteCacheState.miss);

  const RouteCacheLookup.hit({
    required RouteCacheState state,
    required T value,
    required DateTime storedAt,
    required DateTime expiresAt,
  }) : this._(
          state: state,
          value: value,
          storedAt: storedAt,
          expiresAt: expiresAt,
        );

  final RouteCacheState state;
  final T? value;
  final DateTime? storedAt;
  final DateTime? expiresAt;
}

/// İlk sürümde bellek içi deterministik cache. Aynı arayüz daha sonra
/// shared_preferences veya cihaz dosyasıyla uygulanabilir.
class InMemoryRouteMatrixResultCache<T> {
  InMemoryRouteMatrixResultCache({
    this.ttlConfig = const RouteMatrixCacheTtlConfig(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final RouteMatrixCacheTtlConfig ttlConfig;
  final DateTime Function() _clock;
  final Map<RouteMatrixCacheKey, _RouteCacheEntry<T>> _entries = {};

  int get length => _entries.length;

  void put(RouteMatrixCacheKey key, T value) {
    final now = _clock();
    final ttl = ttlConfig.forTransportMode(key.transportMode);
    _entries[key] = _RouteCacheEntry(
      value: value,
      storedAt: now,
      expiresAt: now.add(ttl),
    );
  }

  RouteCacheLookup<T> lookup(
    RouteMatrixCacheKey key, {
    bool allowStale = false,
  }) {
    final entry = _entries[key];
    if (entry == null) return const RouteCacheLookup.miss();
    final isFresh = _clock().isBefore(entry.expiresAt);
    if (!isFresh && !allowStale) return const RouteCacheLookup.miss();
    return RouteCacheLookup.hit(
      state: isFresh ? RouteCacheState.fresh : RouteCacheState.stale,
      value: entry.value,
      storedAt: entry.storedAt,
      expiresAt: entry.expiresAt,
    );
  }

  void remove(RouteMatrixCacheKey key) => _entries.remove(key);

  void clear() => _entries.clear();
}

class _RouteCacheEntry<T> {
  const _RouteCacheEntry({
    required this.value,
    required this.storedAt,
    required this.expiresAt,
  });

  final T value;
  final DateTime storedAt;
  final DateTime expiresAt;
}

/// Backend'in batch/matrix sonucunu tekrar kullanmak için istek düzeyi anahtar.
///
/// Konumlar kimliğe göre sıralanır; listenin geliş sırası aynı matrisi gereksiz
/// yere tekrar sorgulatmaz. Yönlülük matris girdilerinin içinde korunur.
class RouteMatrixRequestCacheKey {
  RouteMatrixRequestCacheKey({
    required List<TripLocation> locations,
    required DateTime day,
    required RoutePreferences preferences,
    required this.provider,
    this.coordinateDecimalPlaces = 4,
    RouteDayType Function(DateTime)? dayTypeResolver,
  })  : assert(provider != ''),
        assert(coordinateDecimalPlaces >= 0 && coordinateDecimalPlaces <= 6),
        dayType = (dayTypeResolver ?? defaultRouteDayTypeResolver).call(day),
        timeBucket = routeTimeBucketFor(day),
        profile = preferences.profile.name,
        maximumWalkingMinutes = preferences.maximumWalkingMinutes,
        partySize = preferences.partySize,
        hasLuggage = preferences.hasLuggage,
        locationFingerprint = _locationFingerprint(
          locations,
          coordinateDecimalPlaces,
        );

  final String provider;
  final int coordinateDecimalPlaces;
  final RouteDayType dayType;
  final RouteTimeBucket timeBucket;
  final String profile;
  final int maximumWalkingMinutes;
  final int partySize;
  final bool hasLuggage;
  final String locationFingerprint;

  @override
  bool operator ==(Object other) {
    return other is RouteMatrixRequestCacheKey &&
        provider == other.provider &&
        coordinateDecimalPlaces == other.coordinateDecimalPlaces &&
        dayType == other.dayType &&
        timeBucket == other.timeBucket &&
        profile == other.profile &&
        maximumWalkingMinutes == other.maximumWalkingMinutes &&
        partySize == other.partySize &&
        hasLuggage == other.hasLuggage &&
        locationFingerprint == other.locationFingerprint;
  }

  @override
  int get hashCode => Object.hash(
        provider,
        coordinateDecimalPlaces,
        dayType,
        timeBucket,
        profile,
        maximumWalkingMinutes,
        partySize,
        hasLuggage,
        locationFingerprint,
      );
}

RouteDayType defaultRouteDayTypeResolver(DateTime day) {
  return day.weekday == DateTime.saturday || day.weekday == DateTime.sunday
      ? RouteDayType.weekend
      : RouteDayType.weekday;
}

RouteTimeBucket routeTimeBucketFor(DateTime dateTime) {
  return switch (dateTime.hour) {
    < 7 => RouteTimeBucket.earlyMorning,
    < 11 => RouteTimeBucket.morning,
    < 14 => RouteTimeBucket.noon,
    < 17 => RouteTimeBucket.afternoon,
    < 21 => RouteTimeBucket.evening,
    _ => RouteTimeBucket.night,
  };
}

abstract interface class RouteMatrixSnapshotCache {
  RouteCacheLookup<RouteMatrix> lookup(
    RouteMatrixRequestCacheKey key, {
    bool allowStale = false,
  });

  void put(RouteMatrixRequestCacheKey key, RouteMatrix matrix);
}

class InMemoryRouteMatrixSnapshotCache implements RouteMatrixSnapshotCache {
  InMemoryRouteMatrixSnapshotCache({
    this.ttl = const Duration(hours: 3),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _clock;
  final Map<RouteMatrixRequestCacheKey, _RouteCacheEntry<RouteMatrix>>
      _entries = {};

  int hitCount = 0;
  int missCount = 0;

  double get hitRatio {
    final total = hitCount + missCount;
    return total == 0 ? 0 : hitCount / total;
  }

  @override
  RouteCacheLookup<RouteMatrix> lookup(
    RouteMatrixRequestCacheKey key, {
    bool allowStale = false,
  }) {
    final entry = _entries[key];
    if (entry == null) {
      missCount++;
      return const RouteCacheLookup.miss();
    }
    final isFresh = _clock().isBefore(entry.expiresAt);
    if (!isFresh && !allowStale) {
      missCount++;
      return const RouteCacheLookup.miss();
    }
    hitCount++;
    return RouteCacheLookup.hit(
      state: isFresh ? RouteCacheState.fresh : RouteCacheState.stale,
      value: entry.value,
      storedAt: entry.storedAt,
      expiresAt: entry.expiresAt,
    );
  }

  @override
  void put(RouteMatrixRequestCacheKey key, RouteMatrix matrix) {
    final now = _clock();
    _entries[key] = _RouteCacheEntry(
      value: matrix,
      storedAt: now,
      expiresAt: now.add(ttl),
    );
  }
}

String _locationFingerprint(
  List<TripLocation> locations,
  int decimalPlaces,
) {
  final sorted = [...locations]..sort((a, b) => a.id.compareTo(b.id));
  return sorted.map((location) {
    final coordinate = RouteCacheCoordinate(
      location.latitude,
      location.longitude,
    ).rounded(decimalPlaces: decimalPlaces);
    return '${location.id}:${coordinate.latitude}:${coordinate.longitude}';
  }).join('|');
}

double _powerOfTen(int exponent) {
  var value = 1.0;
  for (var i = 0; i < exponent; i++) {
    value *= 10;
  }
  return value;
}
