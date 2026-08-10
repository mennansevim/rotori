import 'itinerary_optimizer.dart';
import 'route_matrix.dart';

enum RouteExecutionLegKind { departure, betweenStops, returnToBase }

enum RouteExecutionDataQuality { reliable, estimated }

/// Optimizer'ın seçtiği bir ulaşım ayağının kullanıcıya gösterilecek saf Dart
/// karşılığıdır. Bu model skor hesaplamaz, sıra veya ulaşım modu seçmez.
class RouteExecutionLeg {
  const RouteExecutionLeg({
    required this.kind,
    required this.fromLocationId,
    required this.fromName,
    required this.toLocationId,
    required this.toName,
    required this.mode,
    required this.departureTime,
    required this.arrivalTime,
    required this.travelDurationMinutes,
    required this.rideMinutes,
    required this.accessMinutes,
    required this.walkingDurationMinutes,
    required this.waitingDurationMinutes,
    required this.transitWaitMinutes,
    required this.scheduleIdleMinutes,
    required this.transferCount,
    required this.costPerPersonYen,
    required this.partyTotalCostYen,
    required this.vehicleCount,
    required this.fareBasis,
    required this.reliabilityScore,
    required this.dataQuality,
    required this.complexityPenalty,
    this.lineId,
    this.directionId,
    this.providerId,
  });

  final RouteExecutionLegKind kind;
  final String fromLocationId;
  final String fromName;
  final String toLocationId;
  final String toName;
  final TransportMode mode;
  final DateTime departureTime;
  final DateTime arrivalTime;
  final int travelDurationMinutes;
  final int rideMinutes;
  final int accessMinutes;
  final int walkingDurationMinutes;
  final int waitingDurationMinutes;
  final int transitWaitMinutes;
  final int scheduleIdleMinutes;
  final int transferCount;
  final int costPerPersonYen;
  final int partyTotalCostYen;
  final int vehicleCount;
  final FareBasis fareBasis;
  final double reliabilityScore;
  final RouteExecutionDataQuality dataQuality;
  final double complexityPenalty;
  final String? lineId;
  final String? directionId;
  final String? providerId;

  bool get isEstimated => dataQuality == RouteExecutionDataQuality.estimated;

  bool get isTrivial =>
      travelDurationMinutes == 0 && fromLocationId == toLocationId;

  factory RouteExecutionLeg.fromJson(Map<String, dynamic> json) {
    return RouteExecutionLeg(
      kind: RouteExecutionLegKind.values.byName(json['kind'] as String),
      fromLocationId: json['fromLocationId'] as String,
      fromName: json['fromName'] as String,
      toLocationId: json['toLocationId'] as String,
      toName: json['toName'] as String,
      mode: TransportMode.values.byName(json['mode'] as String),
      departureTime: DateTime.parse(json['departureTime'] as String),
      arrivalTime: DateTime.parse(json['arrivalTime'] as String),
      travelDurationMinutes: (json['travelDurationMinutes'] as num).toInt(),
      rideMinutes: (json['rideMinutes'] as num).toInt(),
      accessMinutes: (json['accessMinutes'] as num).toInt(),
      walkingDurationMinutes: (json['walkingDurationMinutes'] as num).toInt(),
      waitingDurationMinutes: (json['waitingDurationMinutes'] as num).toInt(),
      transitWaitMinutes: (json['transitWaitMinutes'] as num).toInt(),
      scheduleIdleMinutes: (json['scheduleIdleMinutes'] as num).toInt(),
      transferCount: (json['transferCount'] as num).toInt(),
      costPerPersonYen: (json['costPerPersonYen'] as num).toInt(),
      partyTotalCostYen: (json['partyTotalCostYen'] as num).toInt(),
      vehicleCount: (json['vehicleCount'] as num).toInt(),
      fareBasis: FareBasis.values.byName(json['fareBasis'] as String),
      reliabilityScore: (json['reliabilityScore'] as num).toDouble(),
      dataQuality: RouteExecutionDataQuality.values
          .byName(json['dataQuality'] as String),
      complexityPenalty: (json['complexityPenalty'] as num).toDouble(),
      lineId: json['lineId'] as String?,
      directionId: json['directionId'] as String?,
      providerId: json['providerId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'fromLocationId': fromLocationId,
        'fromName': fromName,
        'toLocationId': toLocationId,
        'toName': toName,
        'mode': mode.name,
        'departureTime': departureTime.toIso8601String(),
        'arrivalTime': arrivalTime.toIso8601String(),
        'travelDurationMinutes': travelDurationMinutes,
        'rideMinutes': rideMinutes,
        'accessMinutes': accessMinutes,
        'walkingDurationMinutes': walkingDurationMinutes,
        'waitingDurationMinutes': waitingDurationMinutes,
        'transitWaitMinutes': transitWaitMinutes,
        'scheduleIdleMinutes': scheduleIdleMinutes,
        'transferCount': transferCount,
        'costPerPersonYen': costPerPersonYen,
        'partyTotalCostYen': partyTotalCostYen,
        'vehicleCount': vehicleCount,
        'fareBasis': fareBasis.name,
        'reliabilityScore': reliabilityScore,
        'dataQuality': dataQuality.name,
        'complexityPenalty': complexityPenalty,
        if (lineId != null) 'lineId': lineId,
        if (directionId != null) 'directionId': directionId,
        if (providerId != null) 'providerId': providerId,
      };
}

/// Kullanıcının onayladığı günlük rota bilgisinin opsiyonel, versioned
/// snapshot'ıdır. Optimizer'ın doğru kaynağı değildir; aktivite hash'i veya
/// matris sürümü değiştiğinde yeniden hesaplanır.
class RouteExecutionSnapshot {
  const RouteExecutionSnapshot({
    required this.planId,
    required this.dayNumber,
    required this.planVersion,
    required this.activityHash,
    required this.matrixVersion,
    required this.generatedAt,
    required this.profile,
    required this.legs,
    this.schemaVersion = currentSchemaVersion,
    this.providerIds = const [],
  });

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String planId;
  final int dayNumber;
  final int planVersion;
  final String activityHash;
  final String matrixVersion;
  final DateTime generatedAt;
  final RouteOptimizationProfile profile;
  final List<String> providerIds;
  final List<RouteExecutionLeg> legs;

  bool matches({
    required String currentPlanId,
    required int currentDayNumber,
    required String currentActivityHash,
  }) {
    return schemaVersion == currentSchemaVersion &&
        planId == currentPlanId &&
        dayNumber == currentDayNumber &&
        activityHash == currentActivityHash;
  }

  static RouteExecutionSnapshot? tryFromJson(Map<String, dynamic> json) {
    try {
      final version = (json['schemaVersion'] as num?)?.toInt() ?? 0;
      if (version != currentSchemaVersion) return null;
      return RouteExecutionSnapshot(
        schemaVersion: version,
        planId: json['planId'] as String,
        dayNumber: (json['dayNumber'] as num).toInt(),
        planVersion: (json['planVersion'] as num).toInt(),
        activityHash: json['activityHash'] as String,
        matrixVersion: json['matrixVersion'] as String,
        generatedAt: DateTime.parse(json['generatedAt'] as String),
        profile:
            RouteOptimizationProfile.values.byName(json['profile'] as String),
        providerIds: List<String>.from(
          json['providerIds'] as List? ?? const [],
        ),
        legs: (json['legs'] as List? ?? const [])
            .map(
              (leg) => RouteExecutionLeg.fromJson(
                (leg as Map).cast<String, dynamic>(),
              ),
            )
            .toList(growable: false),
      );
    } on Object {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'planId': planId,
        'dayNumber': dayNumber,
        'planVersion': planVersion,
        'activityHash': activityHash,
        'matrixVersion': matrixVersion,
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'profile': profile.name,
        'providerIds': providerIds,
        'legs': legs.map((leg) => leg.toJson()).toList(growable: false),
      };
}

/// Başlangıç/otel ve aktivite adlarını kullanarak optimizer bacaklarını
/// eksiksiz bir saha görünümü listesine dönüştürür.
class RouteExecutionBuilder {
  const RouteExecutionBuilder();

  List<RouteExecutionLeg> build({
    required OptimizationResult result,
    required String startLocationId,
    required String endLocationId,
    required Map<String, String> locationNames,
  }) {
    if (!result.isSuccess) return const [];

    return List.unmodifiable(
      result.legs.map(
        (leg) => RouteExecutionLeg(
          kind: _kindFor(
            leg,
            startLocationId: startLocationId,
            endLocationId: endLocationId,
          ),
          fromLocationId: leg.fromLocationId,
          fromName: locationNames[leg.fromLocationId] ?? leg.fromLocationId,
          toLocationId: leg.toLocationId,
          toName: locationNames[leg.toLocationId] ?? leg.toLocationId,
          mode: leg.mode,
          departureTime: leg.departureTime,
          arrivalTime: leg.arrivalTime,
          travelDurationMinutes: leg.travelDurationMinutes,
          rideMinutes: leg.rideMinutes,
          accessMinutes: leg.accessMinutes,
          walkingDurationMinutes: leg.walkingDurationMinutes,
          waitingDurationMinutes: leg.waitingDurationMinutes,
          transitWaitMinutes: leg.transitWaitMinutes,
          scheduleIdleMinutes: leg.scheduleIdleMinutes,
          transferCount: leg.transferCount,
          costPerPersonYen: leg.costPerPersonYen,
          partyTotalCostYen: leg.partyTotalCostYen,
          vehicleCount: leg.vehicleCount,
          fareBasis: leg.fareBasis,
          reliabilityScore: leg.reliabilityScore,
          dataQuality: leg.isEstimated
              ? RouteExecutionDataQuality.estimated
              : RouteExecutionDataQuality.reliable,
          lineId: leg.lineId,
          directionId: leg.directionId,
          complexityPenalty: leg.complexityPenalty,
          providerId: leg.providerId,
        ),
      ),
    );
  }

  RouteExecutionLegKind _kindFor(
    RouteLeg leg, {
    required String startLocationId,
    required String endLocationId,
  }) {
    if (leg.toLocationId == endLocationId &&
        leg.fromLocationId != startLocationId) {
      return RouteExecutionLegKind.returnToBase;
    }
    if (leg.fromLocationId == startLocationId) {
      return RouteExecutionLegKind.departure;
    }
    return RouteExecutionLegKind.betweenStops;
  }
}
