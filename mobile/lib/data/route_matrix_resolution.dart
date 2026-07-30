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
