import 'route_execution.dart';
import 'types.dart';

/// Rota üretim analitiğinde saklanan JSON sözleşmesi.
///
/// Tam [Trip.toJson] bilinçli olarak gönderilmez: uçuş, otel, bilet, serbest
/// not, harita URL'si ve iletişim bilgileri ölçüm için gerekli değildir.
/// Buradaki snapshot rota sırası ve optimizer kalitesini incelemeye yeterlidir.
class RouteAnalyticsSnapshot {
  const RouteAnalyticsSnapshot._();

  static const int schemaVersion = 1;

  static Map<String, dynamic> request({
    required List<String> cityKeys,
    required String startYmd,
    required String endYmd,
    required bool datesEstimated,
    required Map<String, int> dayOverrides,
    required List<String> dietaryTags,
    required int? mealBudgetJpyPerPerson,
    required String language,
  }) =>
      {
        'schemaVersion': schemaVersion,
        'cityKeys': List<String>.from(cityKeys),
        'startYmd': startYmd,
        'endYmd': endYmd,
        'datesEstimated': datesEstimated,
        'dayOverrides': Map<String, int>.from(dayOverrides),
        // Beslenme etiketlerinin kendisi sağlık/inanç çıkarımına yol
        // açabileceğinden yalnız sayısı tutulur.
        'dietaryTagCount': dietaryTags.length,
        'hasMealBudget': mealBudgetJpyPerPerson != null,
        'language': language,
      };

  static Map<String, dynamic> route(Trip trip) => {
        'schemaVersion': schemaVersion,
        'planId': trip.id,
        'timezone': trip.timezone,
        'tripStart': trip.tripStart,
        'tripEnd': trip.tripEnd,
        'preferences': {
          'pace': trip.preferences.pace.name,
          'datesEstimated': trip.preferences.datesEstimated,
          'dietaryTagCount': trip.preferences.dietaryTags.length,
          'hasMealBudget': trip.preferences.mealBudgetJpyPerPerson != null,
          'walkingTarget': trip.preferences.walkingTarget?.name,
          'transportPreference': trip.preferences.transportPreference?.name,
          'destinations': trip.preferences.destinations
              .map(
                (destination) => {
                  'id': destination.id,
                  'countryCode': destination.countryCode,
                  'city': destination.city,
                  'arrivalDate': destination.arrivalDate,
                  'departureDate': destination.departureDate,
                  'order': destination.order,
                },
              )
              .toList(growable: false),
        },
        'days': trip.days
            .map(
              (day) => {
                'dayNumber': day.dayNumber,
                'date': day.date,
                'theme': day.theme,
                'tags': List<String>.from(day.tags),
                'stepsEstimate': day.stepsEstimate,
                'stepsEstimateMax': day.stepsEstimateMax,
                'taxiRecommended': day.taxiRecommended,
                'items': day.items
                    .map(
                      (item) => {
                        'id': item.id,
                        'title': item.title,
                        'time': item.time,
                        'scheduledTime': item.scheduledTime,
                        'kind': item.kind?.name,
                        'lat': item.lat,
                        'lng': item.lng,
                        'durationMin': item.durationMin,
                        'arrivalBufferMin': item.arrivalBufferMin,
                        'cost': item.cost,
                        'costCurrency': item.costCurrency,
                        'cityId': item.cityId,
                        'lockType': item.lockType.name,
                        'fixedStartTime': item.fixedStartTime,
                        'fixedEndTime': item.fixedEndTime,
                        'openingTime': item.openingTime,
                        'closingTime': item.closingTime,
                      },
                    )
                    .toList(growable: false),
                if (day.routeExecutionSnapshot != null)
                  'routeExecution': _routeExecution(
                    day.routeExecutionSnapshot!,
                  ),
                if (day.cityTransition != null)
                  'cityTransition': {
                    'fromCity': day.cityTransition!.fromCity,
                    'toCity': day.cityTransition!.toCity,
                    'mode': day.cityTransition!.mode,
                  },
              },
            )
            .toList(growable: false),
      };

  static Map<String, dynamic> metrics(
    Trip trip, {
    required int elapsedMs,
  }) {
    final legs = trip.days
        .expand(
          (day) =>
              day.routeExecutionSnapshot?.legs ?? const <RouteExecutionLeg>[],
        )
        .toList(growable: false);
    final activities = trip.days.fold<int>(
      0,
      (total, day) => total + day.items.length,
    );
    final travelMinutes = legs.fold<int>(
      0,
      (total, leg) => total + leg.travelDurationMinutes,
    );

    return {
      'schemaVersion': schemaVersion,
      'elapsedMs': elapsedMs,
      'dayCount': trip.days.length,
      'activityCount': activities,
      'routeLegCount': legs.length,
      'estimatedLegCount':
          legs.where((leg) => leg.dataQuality.name == 'estimated').length,
      'totalTravelMinutes': travelMinutes,
    };
  }

  static Map<String, dynamic> _routeExecution(
    RouteExecutionSnapshot snapshot,
  ) =>
      {
        'schemaVersion': snapshot.schemaVersion,
        'dayNumber': snapshot.dayNumber,
        'planVersion': snapshot.planVersion,
        'matrixVersion': snapshot.matrixVersion,
        'profile': snapshot.profile.name,
        'providerIds': List<String>.from(snapshot.providerIds),
        'legs': snapshot.legs
            .map(
              (leg) => {
                'kind': leg.kind.name,
                'mode': leg.mode.name,
                'departureTime': leg.departureTime.toIso8601String(),
                'arrivalTime': leg.arrivalTime.toIso8601String(),
                'travelDurationMinutes': leg.travelDurationMinutes,
                'rideMinutes': leg.rideMinutes,
                'accessMinutes': leg.accessMinutes,
                'walkingDurationMinutes': leg.walkingDurationMinutes,
                'waitingDurationMinutes': leg.waitingDurationMinutes,
                'transitWaitMinutes': leg.transitWaitMinutes,
                'scheduleIdleMinutes': leg.scheduleIdleMinutes,
                'transferCount': leg.transferCount,
                'costPerPersonYen': leg.costPerPersonYen,
                'partyTotalCostYen': leg.partyTotalCostYen,
                'vehicleCount': leg.vehicleCount,
                'fareBasis': leg.fareBasis.name,
                'reliabilityScore': leg.reliabilityScore,
                'dataQuality': leg.dataQuality.name,
                'complexityPenalty': leg.complexityPenalty,
                if (leg.lineId != null) 'lineId': leg.lineId,
                if (leg.directionId != null) 'directionId': leg.directionId,
                if (leg.providerId != null) 'providerId': leg.providerId,
              },
            )
            .toList(growable: false),
      };
}
