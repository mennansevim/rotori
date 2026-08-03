import 'itinerary_optimizer.dart';

enum RouteValidationIssueCode {
  unsuccessfulResult,
  duplicateActivityId,
  scheduledAndDropped,
  protectedActivityDropped,
  unaccountedActivity,
  timelineOverlap,
  outsideOpeningWindow,
  fixedTimeMismatch,
  routeLegMissing,
  routeLegMismatch,
  returnLegMissing,
  returnAfterDayEnd,
  metricMismatch,
}

class RouteValidationIssue {
  const RouteValidationIssue({
    required this.code,
    required this.message,
    this.activityId,
    this.fromLocationId,
    this.toLocationId,
  });

  final RouteValidationIssueCode code;
  final String message;
  final String? activityId;
  final String? fromLocationId;
  final String? toLocationId;
}

/// Optimizer'dan bağımsız hard-constraint kapısı.
///
/// Bir sonuç bu doğrulamayı geçmeden önizlemeye veya persistence katmanına
/// taşınmamalıdır. Validator skor/kalite yorumu yapmaz; yalnız doğruluğu ölçer.
class RouteOptimizationValidator {
  const RouteOptimizationValidator();

  List<RouteValidationIssue> validate(
    OptimizationRequest request,
    OptimizationResult result,
  ) {
    final issues = <RouteValidationIssue>[];
    if (!result.isSuccess || result.metrics == null) {
      return const [
        RouteValidationIssue(
          code: RouteValidationIssueCode.unsuccessfulResult,
          message: 'Başarısız optimizer sonucu uygulanamaz.',
        ),
      ];
    }

    final requestedById = <String, OptimizationActivity>{};
    for (final activity in request.activities) {
      if (requestedById.containsKey(activity.id)) {
        issues.add(RouteValidationIssue(
          code: RouteValidationIssueCode.duplicateActivityId,
          message: 'İstek aynı aktivite kimliğini birden fazla içeriyor.',
          activityId: activity.id,
        ));
      }
      requestedById[activity.id] = activity;
    }

    final scheduledIds = <String>{};
    DateTime? previousEnd;
    for (final scheduled in result.activities) {
      final activity = scheduled.activity;
      if (!scheduledIds.add(activity.id)) {
        issues.add(RouteValidationIssue(
          code: RouteValidationIssueCode.duplicateActivityId,
          message: 'Aktivite schedule içinde ikinci kez yer alıyor.',
          activityId: activity.id,
        ));
      }
      if (previousEnd != null && scheduled.startTime.isBefore(previousEnd)) {
        issues.add(RouteValidationIssue(
          code: RouteValidationIssueCode.timelineOverlap,
          message: 'Aktivite zamanları kronolojik ve çakışmasız değil.',
          activityId: activity.id,
        ));
      }
      previousEnd = scheduled.endTime;

      if ((activity.openingTime != null &&
              scheduled.startTime.isBefore(activity.openingTime!)) ||
          (activity.closingTime != null &&
              scheduled.endTime.isAfter(activity.closingTime!))) {
        issues.add(RouteValidationIssue(
          code: RouteValidationIssueCode.outsideOpeningWindow,
          message: 'Aktivite çalışma saatinin dışında planlandı.',
          activityId: activity.id,
        ));
      }
      if ((activity.fixedStartTime != null &&
              scheduled.startTime != activity.fixedStartTime) ||
          (activity.fixedEndTime != null &&
              scheduled.endTime != activity.fixedEndTime)) {
        issues.add(RouteValidationIssue(
          code: RouteValidationIssueCode.fixedTimeMismatch,
          message: 'Sabit aktivite tanımlanan saatinde değil.',
          activityId: activity.id,
        ));
      }

      _validateLeg(request, scheduled.inboundLeg, issues);
    }

    final droppedIds = <String>{};
    for (final id in result.droppedActivityIds) {
      if (!droppedIds.add(id)) {
        issues.add(RouteValidationIssue(
          code: RouteValidationIssueCode.duplicateActivityId,
          message: 'Aktivite dropping listesinde ikinci kez yer alıyor.',
          activityId: id,
        ));
      }
      if (scheduledIds.contains(id)) {
        issues.add(RouteValidationIssue(
          code: RouteValidationIssueCode.scheduledAndDropped,
          message: 'Aktivite hem schedule hem dropping listesinde.',
          activityId: id,
        ));
      }
      final requested = requestedById[id];
      if (requested != null &&
          (requested.hasFixedSchedule ||
              requested.priority == ActivityPriority.mustDo)) {
        issues.add(RouteValidationIssue(
          code: RouteValidationIssueCode.protectedActivityDropped,
          message: 'Must-do veya sabit aktivite düşürülemez.',
          activityId: id,
        ));
      }
    }
    for (final id in requestedById.keys) {
      if (!scheduledIds.contains(id) && !droppedIds.contains(id)) {
        issues.add(RouteValidationIssue(
          code: RouteValidationIssueCode.unaccountedActivity,
          message: 'İstenen aktivite sonuçta açıklanmadı.',
          activityId: id,
        ));
      }
    }

    final expectedLegCount = result.activities.length + 1;
    if (result.legs.length < expectedLegCount) {
      issues.add(const RouteValidationIssue(
        code: RouteValidationIssueCode.returnLegMissing,
        message: 'Gün sonu dönüş bacağı eksik.',
      ));
    } else {
      final returnLeg = result.legs.last;
      _validateLeg(request, returnLeg, issues);
      if (returnLeg.toLocationId != request.constraints.endLocation.id) {
        issues.add(RouteValidationIssue(
          code: RouteValidationIssueCode.returnLegMissing,
          message: 'Son bacak günün bitiş lokasyonuna dönmüyor.',
          fromLocationId: returnLeg.fromLocationId,
          toLocationId: returnLeg.toLocationId,
        ));
      }
      if (returnLeg.arrivalTime.isAfter(
        request.constraints.availableEndTime,
      )) {
        issues.add(const RouteValidationIssue(
          code: RouteValidationIssueCode.returnAfterDayEnd,
          message: 'Otele dönüş gün sonunu aşıyor.',
        ));
      }
    }

    final metrics = result.metrics!;
    final travel = result.legs.fold<int>(
      0,
      (sum, leg) => sum + leg.travelDurationMinutes,
    );
    final walking = result.legs.fold<int>(
      0,
      (sum, leg) => sum + leg.walkingDurationMinutes,
    );
    final waiting = result.legs.fold<int>(
      0,
      (sum, leg) => sum + leg.waitingDurationMinutes,
    );
    final transfers = result.legs.fold<int>(
      0,
      (sum, leg) => sum + leg.transferCount,
    );
    final cost = result.legs.fold<int>(
      0,
      (sum, leg) => sum + leg.estimatedCostYen,
    );
    if (travel != metrics.totalTravelMinutes ||
        walking != metrics.totalWalkingMinutes ||
        waiting != metrics.totalWaitingMinutes ||
        transfers != metrics.totalTransferCount ||
        cost != metrics.estimatedTransportCostYen) {
      issues.add(const RouteValidationIssue(
        code: RouteValidationIssueCode.metricMismatch,
        message: 'Timeline toplamları aggregate metriklerle eşleşmiyor.',
      ));
    }
    return List.unmodifiable(issues);
  }

  void _validateLeg(
    OptimizationRequest request,
    RouteLeg leg,
    List<RouteValidationIssue> issues,
  ) {
    final options = request.routeMatrix.options(
      leg.fromLocationId,
      leg.toLocationId,
    );
    if (options.isEmpty) {
      issues.add(RouteValidationIssue(
        code: RouteValidationIssueCode.routeLegMissing,
        message: 'Transit bacağı yönlü matriste bulunamadı.',
        fromLocationId: leg.fromLocationId,
        toLocationId: leg.toLocationId,
      ));
      return;
    }
    final matches = options.any((option) =>
        option.mode == leg.mode &&
        option.doorToDoorMinutes == leg.travelDurationMinutes &&
        option.walkingMinutes == leg.walkingDurationMinutes &&
        option.transferCount == leg.transferCount &&
        option.estimatedCostYen == leg.estimatedCostYen);
    if (!matches) {
      issues.add(RouteValidationIssue(
        code: RouteValidationIssueCode.routeLegMismatch,
        message: 'Transit bacağı matris seçeneğiyle eşleşmiyor.',
        fromLocationId: leg.fromLocationId,
        toLocationId: leg.toLocationId,
      ));
    }
  }
}
