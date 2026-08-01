import 'dart:math' as math;

import '../domain/route_matrix.dart';
import 'route_matrix_cache.dart';
import 'route_matrix_remote.dart';

enum RouteMatrixSource {
  freshCache,
  primaryProvider,
  alternativeProvider,
  staleCache,
  unavailable,
}

class RouteMatrixResolution {
  RouteMatrixResolution({
    required this.source,
    required List<RouteMatrixFailure> failures,
    this.matrix,
    this.isEstimated = false,
    this.coordinatePreFilterOnly = false,
  }) : failures = List.unmodifiable(failures);

  final RouteMatrix? matrix;
  final RouteMatrixSource source;
  final bool isEstimated;

  /// `true` ise koordinatlar yalnızca aday elemek için kullanılabilir;
  /// bunlardan ulaşım süresi üretilemez.
  final bool coordinatePreFilterOnly;
  final List<RouteMatrixFailure> failures;

  bool get hasUsableMatrix => matrix != null;
}

/// Fallback sırası: fresh cache → ana backend → alternatif backend →
/// stale cache → optimize edilemez. Koordinat mesafesi hiçbir aşamada gerçek
/// ulaşım süresine çevrilmez.
class ResilientRouteMatrixResolver {
  const ResilientRouteMatrixResolver({
    required this.primary,
    required this.primaryProviderId,
    required this.cache,
    this.alternative,
    this.alternativeProviderId,
    this.dayTypeResolver = defaultRouteDayTypeResolver,
  })  : assert(primaryProviderId != ''),
        assert(
          (alternative == null && alternativeProviderId == null) ||
              (alternative != null &&
                  alternativeProviderId != null &&
                  alternativeProviderId != ''),
        );

  final RouteMatrixRepository primary;
  final String primaryProviderId;
  final RouteMatrixRepository? alternative;
  final String? alternativeProviderId;
  final RouteMatrixSnapshotCache cache;
  final RouteDayType Function(DateTime) dayTypeResolver;

  Future<RouteMatrixResolution> resolve({
    required List<TripLocation> locations,
    required DateTime day,
    required RoutePreferences preferences,
  }) async {
    final primaryKey = _key(
      provider: primaryProviderId,
      locations: locations,
      day: day,
      preferences: preferences,
    );
    final fresh = cache.lookup(primaryKey);
    if (fresh.state == RouteCacheState.fresh && fresh.value != null) {
      return RouteMatrixResolution(
        matrix: fresh.value,
        source: RouteMatrixSource.freshCache,
        failures: const [],
      );
    }

    final fallbackProvider = alternativeProviderId;
    final fallbackKey = fallbackProvider == null
        ? null
        : _key(
            provider: fallbackProvider,
            locations: locations,
            day: day,
            preferences: preferences,
          );
    if (fallbackKey != null) {
      final fallbackFresh = cache.lookup(fallbackKey);
      if (fallbackFresh.state == RouteCacheState.fresh &&
          fallbackFresh.value != null) {
        return RouteMatrixResolution(
          matrix: fallbackFresh.value,
          source: RouteMatrixSource.freshCache,
          failures: const [],
        );
      }
    }

    final failures = <RouteMatrixFailure>[];
    final primaryMatrix = await _tryRepository(
      primary,
      locations,
      day,
      preferences,
      failures,
    );
    if (primaryMatrix != null) {
      cache.put(primaryKey, primaryMatrix);
      return RouteMatrixResolution(
        matrix: primaryMatrix,
        source: RouteMatrixSource.primaryProvider,
        failures: failures,
      );
    }

    final fallbackRepository = alternative;
    if (fallbackRepository != null && fallbackKey != null) {
      final fallbackMatrix = await _tryRepository(
        fallbackRepository,
        locations,
        day,
        preferences,
        failures,
      );
      if (fallbackMatrix != null) {
        cache.put(fallbackKey, fallbackMatrix);
        return RouteMatrixResolution(
          matrix: fallbackMatrix,
          source: RouteMatrixSource.alternativeProvider,
          failures: failures,
        );
      }
    }

    final stale = cache.lookup(primaryKey, allowStale: true);
    if (stale.state == RouteCacheState.stale && stale.value != null) {
      return RouteMatrixResolution(
        matrix: _markEstimated(stale.value!),
        source: RouteMatrixSource.staleCache,
        failures: failures,
        isEstimated: true,
      );
    }
    if (fallbackKey != null) {
      final fallbackStale = cache.lookup(fallbackKey, allowStale: true);
      if (fallbackStale.state == RouteCacheState.stale &&
          fallbackStale.value != null) {
        return RouteMatrixResolution(
          matrix: _markEstimated(fallbackStale.value!),
          source: RouteMatrixSource.staleCache,
          failures: failures,
          isEstimated: true,
        );
      }
    }

    return RouteMatrixResolution(
      source: RouteMatrixSource.unavailable,
      failures: failures,
      coordinatePreFilterOnly: true,
    );
  }

  RouteMatrixRequestCacheKey _key({
    required String provider,
    required List<TripLocation> locations,
    required DateTime day,
    required RoutePreferences preferences,
  }) {
    return RouteMatrixRequestCacheKey(
      locations: locations,
      day: day,
      preferences: preferences,
      provider: provider,
      dayTypeResolver: dayTypeResolver,
    );
  }
}

/// Mevcut Riverpod/controller sözleşmesine resolver'ı adaptör olarak bağlar.
///
/// Cache ve fallback tükendiyse eksik süre uydurmak yerine typed failure
/// fırlatır; controller mevcut error durumunu gösterebilir.
class ResilientRouteMatrixRepository implements RouteMatrixRepository {
  const ResilientRouteMatrixRepository(this.resolver);

  final ResilientRouteMatrixResolver resolver;

  @override
  Future<RouteMatrix> getRouteMatrix({
    required List<TripLocation> locations,
    required DateTime day,
    required RoutePreferences preferences,
  }) async {
    final result = await resolver.resolve(
      locations: locations,
      day: day,
      preferences: preferences,
    );
    final matrix = result.matrix;
    if (matrix != null) return matrix;
    throw RouteMatrixFailure(
      kind: RouteMatrixFailureKind.unavailable,
      message: 'Rota verisi cache veya sağlayıcılardan alınamadı.',
      retryable: result.failures.any((failure) => failure.retryable),
    );
  }
}

/// Backend ulaşılamadığında optimizasyonun tamamen kilitlenmesini önleyen,
/// koordinat tabanlı ve deterministik son çare matrisi.
///
/// Bu bir harita sağlayıcısı sonucu değildir. Süreler özellikle
/// `isEstimated=true` ile işaretlenir; gerçek veri geldiğinde controller bunu
/// otomatik olarak tercih eder. Yine de optimizasyon motorunun sıralama,
/// zaman çakışması ve sabit aktivite kurallarını çalıştırabilmesi için her
/// yönü kapsayan güvenli bir maliyet sağlar.
RouteMatrix buildCoordinateFallbackMatrix(List<TripLocation> locations) {
  final entries = <RouteMatrixEntry>[];
  for (final from in locations) {
    for (final to in locations) {
      if (from.id == to.id) continue;
      final kilometres = _distanceKm(from, to);
      final isShortWalk = kilometres <= 0.8;
      final travelMinutes = isShortWalk
          ? math.max(3, (kilometres * 14).ceil())
          : math.max(8, (kilometres * 4.2).ceil() + 8);
      final walkingMinutes = isShortWalk
          ? travelMinutes
          : math.min(25, math.max(5, (kilometres * 1.4).ceil()));
      entries.add(
        RouteMatrixEntry(
          fromLocationId: from.id,
          toLocationId: to.id,
          options: [
            TransportOption(
              mode: isShortWalk ? TransportMode.walking : TransportMode.train,
              doorToDoorMinutes: travelMinutes,
              walkingMinutes: walkingMinutes,
              waitingMinutes: isShortWalk ? 0 : 5,
              transferCount: isShortWalk ? 0 : 1,
              estimatedCostYen: isShortWalk ? 0 : 180,
              reliabilityScore: 0.35,
              isEstimated: true,
            ),
          ],
        ),
      );
    }
  }
  return RouteMatrix(
    entries: entries,
    version: 'coordinate-estimate-v1',
  );
}

double _distanceKm(TripLocation from, TripLocation to) {
  const earthRadiusKm = 6371.0;
  final latitudeDelta = _radians(to.latitude - from.latitude);
  final longitudeDelta = _radians(to.longitude - from.longitude);
  final fromLatitude = _radians(from.latitude);
  final toLatitude = _radians(to.latitude);
  final haversine = math.pow(math.sin(latitudeDelta / 2), 2) +
      math.cos(fromLatitude) *
          math.cos(toLatitude) *
          math.pow(math.sin(longitudeDelta / 2), 2);
  final arc = 2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  return earthRadiusKm * arc;
}

double _radians(double degrees) => degrees * math.pi / 180;

Future<RouteMatrix?> _tryRepository(
  RouteMatrixRepository repository,
  List<TripLocation> locations,
  DateTime day,
  RoutePreferences preferences,
  List<RouteMatrixFailure> failures,
) async {
  try {
    return await repository.getRouteMatrix(
      locations: locations,
      day: day,
      preferences: preferences,
    );
  } catch (error) {
    failures.add(
      error is RouteMatrixFailure
          ? error
          : RouteMatrixFailure(
              kind: RouteMatrixFailureKind.providerFailure,
              message: 'Rota sağlayıcısı başarısız: ${error.runtimeType}.',
            ),
    );
    return null;
  }
}

RouteMatrix _markEstimated(RouteMatrix matrix) {
  return RouteMatrix(
    version: matrix.version,
    entries: matrix.entries.map(
      (entry) {
        return RouteMatrixEntry(
          fromLocationId: entry.fromLocationId,
          toLocationId: entry.toLocationId,
          options: entry.options.map(
            (option) {
              return TransportOption(
                mode: option.mode,
                doorToDoorMinutes: option.doorToDoorMinutes,
                walkingMinutes: option.walkingMinutes,
                waitingMinutes: option.waitingMinutes,
                transferCount: option.transferCount,
                estimatedCostYen: option.estimatedCostYen,
                reliabilityScore: option.reliabilityScore,
                lineId: option.lineId,
                directionId: option.directionId,
                complexityPenalty: option.complexityPenalty,
                isEstimated: true,
              );
            },
          ).toList(),
        );
      },
    ).toList(),
  );
}
