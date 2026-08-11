import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/route_matrix.dart';
import 'route_matrix_remote.dart';

class SupabaseRouteMatrixBackendGateway implements RouteMatrixBackendGateway {
  const SupabaseRouteMatrixBackendGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<RouteMatrix> fetchMatrix(RouteMatrixBackendRequest request) async {
    try {
      final response = await _client.functions.invoke(
        'route-matrix',
        body: {
          'day': request.day.toIso8601String(),
          'preferences': {
            'profile': request.preferences.profile.name,
            'partySize': request.preferences.partySize,
            'maximumWalkingMinutes': request.preferences.maximumWalkingMinutes,
          },
          'locations': [
            for (final location in request.locations)
              {
                'id': location.id,
                'name': location.name,
                'latitude': location.latitude,
                'longitude': location.longitude,
              },
          ],
        },
      );
      if (response.status < 200 || response.status >= 300) {
        throw RouteMatrixFailure(
          kind: response.status == 401 || response.status == 403
              ? RouteMatrixFailureKind.unauthorized
              : RouteMatrixFailureKind.providerFailure,
          message: 'Rota servisi ${response.status} durumunu döndürdü.',
          retryable: response.status >= 500,
        );
      }
      return decodeRouteMatrixResponse(response.data);
    } on RouteMatrixFailure {
      rethrow;
    } catch (error) {
      throw RouteMatrixFailure(
        kind: RouteMatrixFailureKind.network,
        message: 'Rota servisine ulaşılamadı: ${error.runtimeType}.',
      );
    }
  }
}

RouteMatrix decodeRouteMatrixResponse(Object? data) {
  try {
    final root = (data as Map).cast<String, dynamic>();
    final rawEntries = root['entries'] as List;
    final entries = rawEntries.map((rawEntry) {
      final entry = (rawEntry as Map).cast<String, dynamic>();
      final rawOptions = entry['options'] as List;
      return RouteMatrixEntry(
        fromLocationId: entry['fromLocationId'] as String,
        toLocationId: entry['toLocationId'] as String,
        options: rawOptions.map((rawOption) {
          final option = (rawOption as Map).cast<String, dynamic>();
          return TransportOption(
            mode: TransportMode.values.byName(option['mode'] as String),
            doorToDoorMinutes: (option['doorToDoorMinutes'] as num).toInt(),
            walkingMinutes: (option['walkingMinutes'] as num).toInt(),
            waitingMinutes: (option['waitingMinutes'] as num).toInt(),
            transferCount: (option['transferCount'] as num).toInt(),
            estimatedCostYen: (option['estimatedCostYen'] as num).toInt(),
            reliabilityScore: (option['reliabilityScore'] as num).toDouble(),
            lineId: option['lineId'] as String?,
            directionId: option['directionId'] as String?,
            complexityPenalty:
                (option['complexityPenalty'] as num?)?.toDouble() ?? 0,
            isEstimated: option['isEstimated'] as bool? ?? false,
            rideMinutes: (option['rideMinutes'] as num?)?.toInt(),
            accessMinutes: (option['accessMinutes'] as num?)?.toInt(),
            transitWaitMinutes: (option['transitWaitMinutes'] as num?)?.toInt(),
            bufferMinutes: (option['bufferMinutes'] as num?)?.toInt() ?? 0,
            fareBasis: FareBasis.values.byName(
              option['fareBasis'] as String? ?? FareBasis.perPerson.name,
            ),
            vehicleCapacity: (option['vehicleCapacity'] as num?)?.toInt() ?? 4,
            providerId: option['providerId'] as String?,
          );
        }).toList(growable: false),
      );
    }).toList(growable: false);
    return RouteMatrix(
      entries: entries,
      version: root['version'] as String,
    );
  } on Object catch (error) {
    throw RouteMatrixFailure(
      kind: RouteMatrixFailureKind.invalidResponse,
      message: 'Rota servisi yanıtı geçersiz: ${error.runtimeType}.',
      retryable: false,
    );
  }
}
