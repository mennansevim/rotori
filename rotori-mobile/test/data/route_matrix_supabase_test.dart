import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/data/route_matrix_remote.dart';
import 'package:rotori/data/route_matrix_supabase.dart';
import 'package:rotori/domain/route_matrix.dart';

void main() {
  test('Supabase rota yanıtını normalize edilmiş matrise dönüştürür', () {
    final matrix = decodeRouteMatrixResponse({
      'version': 'google-routes-v1',
      'entries': [
        {
          'fromLocationId': 'hotel',
          'toLocationId': 'museum',
          'options': [
            {
              'mode': 'train',
              'doorToDoorMinutes': 24,
              'walkingMinutes': 6,
              'waitingMinutes': 4,
              'transferCount': 1,
              'estimatedCostYen': 210,
              'reliabilityScore': .88,
              'isEstimated': false,
              'providerId': 'google-routes',
            },
          ],
        },
      ],
    });

    expect(matrix.version, 'google-routes-v1');
    final option = matrix.entries.single.options.single;
    expect(option.mode, TransportMode.train);
    expect(option.doorToDoorMinutes, 24);
    expect(option.providerId, 'google-routes');
  });

  test('geçersiz ulaşım türünü typed failure olarak reddeder', () {
    expect(
      () => decodeRouteMatrixResponse({
        'version': 'bad',
        'entries': [
          {
            'fromLocationId': 'a',
            'toLocationId': 'b',
            'options': [
              {
                'mode': 'teleport',
                'doorToDoorMinutes': 1,
                'walkingMinutes': 0,
                'waitingMinutes': 0,
                'transferCount': 0,
                'estimatedCostYen': 0,
                'reliabilityScore': 1,
              },
            ],
          },
        ],
      }),
      throwsA(
        isA<RouteMatrixFailure>().having(
          (failure) => failure.kind,
          'kind',
          RouteMatrixFailureKind.invalidResponse,
        ),
      ),
    );
  });
}
