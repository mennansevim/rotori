/// AI, deterministik rotayı değiştirmez; yalnızca bu sınırlı ve
/// yapılandırılmış sözleşme üzerinden açıklama veya ikinci kontrol üretir.
abstract interface class AiUsagePolicy {
  bool shouldReview(AiReviewContext context);
}

class CostOptimizedAiUsagePolicy implements AiUsagePolicy {
  const CostOptimizedAiUsagePolicy({
    this.minimumConfidence = 0.75,
    this.closeScoreThreshold = 0.03,
  })  : assert(minimumConfidence >= 0 && minimumConfidence <= 1),
        assert(closeScoreThreshold >= 0);

  final double minimumConfidence;
  final double closeScoreThreshold;

  @override
  bool shouldReview(AiReviewContext context) {
    return context.userRequestedExplanation ||
        context.hasAmbiguousPreference ||
        context.hasCriticalWarning ||
        context.hasRouteAnomaly ||
        context.requiresExplanation ||
        context.routeConfidence < minimumConfidence ||
        (context.bestAlternativeScoreGap != null &&
            context.bestAlternativeScoreGap! <= closeScoreThreshold);
  }
}

class AiReviewContext {
  const AiReviewContext({
    required this.planId,
    required this.routeConfidence,
    this.userRequestedExplanation = false,
    this.hasCriticalWarning = false,
    this.hasAmbiguousPreference = false,
    this.hasRouteAnomaly = false,
    this.requiresExplanation = false,
    this.bestAlternativeScoreGap,
    this.callsForPlan = 0,
    this.callsToday = 0,
    this.estimatedInputTokens = 0,
  })  : assert(routeConfidence >= 0 && routeConfidence <= 1),
        assert(bestAlternativeScoreGap == null || bestAlternativeScoreGap >= 0),
        assert(callsForPlan >= 0),
        assert(callsToday >= 0),
        assert(estimatedInputTokens >= 0);

  final String planId;
  final double routeConfidence;
  final bool userRequestedExplanation;
  final bool hasCriticalWarning;
  final bool hasAmbiguousPreference;
  final bool hasRouteAnomaly;
  final bool requiresExplanation;
  final double? bestAlternativeScoreGap;
  final int callsForPlan;
  final int callsToday;
  final int estimatedInputTokens;
}

class AiBudgetPolicy {
  const AiBudgetPolicy({
    this.maximumCallsPerPlan = 2,
    this.maximumCallsPerDay = 8,
    this.maximumInputTokens = 2000,
    this.maximumOutputTokens = 500,
  })  : assert(maximumCallsPerPlan >= 0),
        assert(maximumCallsPerDay >= 0),
        assert(maximumInputTokens >= 0),
        assert(maximumOutputTokens >= 0);

  final int maximumCallsPerPlan;
  final int maximumCallsPerDay;
  final int maximumInputTokens;
  final int maximumOutputTokens;

  bool allows(AiReviewContext context, AiModelConfig modelConfig) {
    return context.callsForPlan < maximumCallsPerPlan &&
        context.callsToday < maximumCallsPerDay &&
        context.estimatedInputTokens <= maximumInputTokens &&
        modelConfig.maxOutputTokens <= maximumOutputTokens;
  }
}

class AiModelConfig {
  const AiModelConfig({
    required this.reviewModel,
    required this.fallbackModel,
    this.maxOutputTokens = 400,
  })  : assert(reviewModel != ''),
        assert(fallbackModel != ''),
        assert(maxOutputTokens > 0);

  final String reviewModel;
  final String fallbackModel;
  final int maxOutputTokens;
}

class AiRouteMetrics {
  const AiRouteMetrics({
    required this.totalTravelMinutes,
    required this.totalWalkingMinutes,
    required this.totalTransfers,
    required this.totalCostYen,
  })  : assert(totalTravelMinutes >= 0),
        assert(totalWalkingMinutes >= 0),
        assert(totalTransfers >= 0),
        assert(totalCostYen >= 0);

  final int totalTravelMinutes;
  final int totalWalkingMinutes;
  final int totalTransfers;
  final int totalCostYen;

  String get stableHashSource => '$totalTravelMinutes|$totalWalkingMinutes|'
      '$totalTransfers|$totalCostYen';
}

class AiRouteReviewRequest {
  AiRouteReviewRequest({
    required List<String> routeActivityIds,
    required this.metrics,
    required List<String> warnings,
    required this.optimizedRouteHash,
    this.userPreference = '',
    this.question = '',
    this.promptVersion = 'route-review-v1',
  })  : routeActivityIds = List.unmodifiable(routeActivityIds),
        warnings = List.unmodifiable(warnings);

  final List<String> routeActivityIds;
  final AiRouteMetrics metrics;
  final List<String> warnings;
  final String userPreference;
  final String question;
  final String optimizedRouteHash;
  final String promptVersion;

  bool get hasValidScope =>
      routeActivityIds.isNotEmpty &&
      optimizedRouteHash.isNotEmpty &&
      promptVersion.isNotEmpty;
}

class AiReviewCacheKey {
  const AiReviewCacheKey({
    required this.optimizedRouteHash,
    required this.metricsHash,
    required this.userPreferenceHash,
    required this.promptVersion,
    required this.model,
  });

  factory AiReviewCacheKey.fromRequest(
    AiRouteReviewRequest request,
    String model,
  ) {
    return AiReviewCacheKey(
      optimizedRouteHash: request.optimizedRouteHash,
      metricsHash: _stableStringHash(request.metrics.stableHashSource),
      userPreferenceHash: _stableStringHash(request.userPreference),
      promptVersion: request.promptVersion,
      model: model,
    );
  }

  final String optimizedRouteHash;
  final String metricsHash;
  final String userPreferenceHash;
  final String promptVersion;
  final String model;

  @override
  bool operator ==(Object other) {
    return other is AiReviewCacheKey &&
        optimizedRouteHash == other.optimizedRouteHash &&
        metricsHash == other.metricsHash &&
        userPreferenceHash == other.userPreferenceHash &&
        promptVersion == other.promptVersion &&
        model == other.model;
  }

  @override
  int get hashCode => Object.hash(
        optimizedRouteHash,
        metricsHash,
        userPreferenceHash,
        promptVersion,
        model,
      );
}

class AiActivityReason {
  const AiActivityReason({
    required this.activityId,
    required this.reason,
  });

  final String activityId;
  final String reason;
}

enum AiReviewIssueSeverity { info, warning, critical }

class AiReviewIssue {
  AiReviewIssue({
    required this.type,
    required this.severity,
    required List<String> activityIds,
    required this.message,
  }) : activityIds = List.unmodifiable(activityIds);

  final String type;
  final AiReviewIssueSeverity severity;
  final List<String> activityIds;
  final String message;
}

class AiRouteReview {
  AiRouteReview({
    required this.isLogical,
    required this.confidence,
    required this.summary,
    required List<AiActivityReason> activityReasons,
    required List<AiReviewIssue> issues,
  })  : assert(confidence >= 0 && confidence <= 1),
        activityReasons = List.unmodifiable(activityReasons),
        issues = List.unmodifiable(issues);

  final bool isLogical;
  final double confidence;
  final String summary;
  final List<AiActivityReason> activityReasons;
  final List<AiReviewIssue> issues;

  /// Şema rota dışı süre/hat/ücret alanları içermez. Buradaki scope kontrolü
  /// ayrıca modelin girdide olmayan aktivitelere referans vermesini engeller.
  bool isWithinScope(AiRouteReviewRequest request) {
    final allowedIds = request.routeActivityIds.toSet();
    return activityReasons.every(
          (reason) =>
              allowedIds.contains(reason.activityId) &&
              reason.reason.trim().isNotEmpty,
        ) &&
        issues.every(
          (issue) =>
              issue.type.trim().isNotEmpty &&
              issue.message.trim().isNotEmpty &&
              issue.activityIds.every(allowedIds.contains),
        );
  }
}

String _stableStringHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash.toRadixString(16);
}
