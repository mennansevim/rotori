import '../domain/route_matrix.dart';

class RouteMatrixBackendRequest {
  RouteMatrixBackendRequest({
    required List<TripLocation> locations,
    required this.day,
    required this.preferences,
  }) : locations = List.unmodifiable(locations);

  final List<TripLocation> locations;
  final DateTime day;
  final RoutePreferences preferences;
}

/// HTTP/Supabase taşıyıcısının uygulayacağı backend sınırı.
///
/// Bu arayüz API anahtarı kabul etmez. Harita sağlayıcısı kimlik bilgileri
/// yalnızca backend veya Edge Function çalışma ortamında tutulur.
abstract interface class RouteMatrixBackendGateway {
  Future<RouteMatrix> fetchMatrix(RouteMatrixBackendRequest request);
}

class UnavailableRouteMatrixBackendGateway
    implements RouteMatrixBackendGateway {
  const UnavailableRouteMatrixBackendGateway();

  @override
  Future<RouteMatrix> fetchMatrix(RouteMatrixBackendRequest request) {
    throw const RouteMatrixFailure(
      kind: RouteMatrixFailureKind.unavailable,
      message: 'Rota backend taşıyıcısı yapılandırılmadı.',
      retryable: false,
    );
  }
}

class RemoteRouteMatrixRepository implements RouteMatrixRepository {
  const RemoteRouteMatrixRepository({
    required this.gateway,
    required this.providerId,
  }) : assert(providerId != '');

  final RouteMatrixBackendGateway gateway;
  final String providerId;

  @override
  Future<RouteMatrix> getRouteMatrix({
    required List<TripLocation> locations,
    required DateTime day,
    required RoutePreferences preferences,
  }) async {
    if (locations.isEmpty) {
      return RouteMatrix(entries: const [], version: 'empty');
    }

    try {
      final matrix = await gateway.fetchMatrix(
        RouteMatrixBackendRequest(
          locations: locations,
          day: day,
          preferences: preferences,
        ),
      );
      _validateMatrix(matrix, locations);
      return matrix;
    } on RouteMatrixFailure {
      rethrow;
    } catch (error) {
      throw RouteMatrixFailure(
        kind: RouteMatrixFailureKind.providerFailure,
        message: 'Rota backend çağrısı başarısız: ${error.runtimeType}.',
      );
    }
  }
}

enum RouteMatrixFailureKind {
  network,
  timeout,
  unauthorized,
  rateLimited,
  invalidResponse,
  noRoute,
  unavailable,
  providerFailure,
}

class RouteMatrixFailure implements Exception {
  const RouteMatrixFailure({
    required this.kind,
    required this.message,
    this.retryable = true,
  });

  final RouteMatrixFailureKind kind;
  final String message;
  final bool retryable;

  @override
  String toString() => 'RouteMatrixFailure($kind): $message';
}

void _validateMatrix(RouteMatrix matrix, List<TripLocation> locations) {
  if (locations.length > 1 && matrix.entries.isEmpty) {
    throw const RouteMatrixFailure(
      kind: RouteMatrixFailureKind.noRoute,
      message: 'Backend kullanılabilir bir rota matrisi döndürmedi.',
      retryable: false,
    );
  }
  final allowedIds = locations.map((location) => location.id).toSet();
  final directions = <String>{};
  for (final entry in matrix.entries) {
    final direction = '${entry.fromLocationId}\u0000${entry.toLocationId}';
    final isValid = entry.fromLocationId != entry.toLocationId &&
        allowedIds.contains(entry.fromLocationId) &&
        allowedIds.contains(entry.toLocationId) &&
        entry.options.isNotEmpty &&
        entry.options.every((option) => option.isValid) &&
        directions.add(direction);
    if (!isValid) {
      throw const RouteMatrixFailure(
        kind: RouteMatrixFailureKind.invalidResponse,
        message: 'Backend geçersiz veya yinelenen rota matrisi döndürdü.',
        retryable: false,
      );
    }
  }
}
