import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/data/ai_route_reviewer.dart';
import 'package:japan_trip/domain/ai_route_review.dart';

void main() {
  const modelConfig = AiModelConfig(
    reviewModel: 'small-structured-model',
    fallbackModel: 'fallback-structured-model',
  );
  const metrics = AiRouteMetrics(
    totalTravelMinutes: 80,
    totalWalkingMinutes: 30,
    totalTransfers: 2,
    totalCostYen: 900,
  );

  AiRouteReviewRequest request() => AiRouteReviewRequest(
        routeActivityIds: const ['shibuya', 'harajuku'],
        metrics: metrics,
        warnings: const [],
        optimizedRouteHash: 'route-hash',
      );

  AiRouteReview review() => AiRouteReview(
        isLogical: true,
        confidence: 0.9,
        summary: 'Aynı bölgedeki duraklar birlikte tutuldu.',
        activityReasons: const [
          AiActivityReason(
            activityId: 'harajuku',
            reason: 'Önceki durakla aynı bölgededir.',
          ),
        ],
        issues: const [],
      );

  RouteReviewCoordinator coordinator(FakeAiRouteReviewRepository repository) {
    return RouteReviewCoordinator(
      usagePolicy: const CostOptimizedAiUsagePolicy(),
      budgetPolicy: const AiBudgetPolicy(),
      modelConfig: modelConfig,
      repository: repository,
    );
  }

  RouteReviewCoordinator automaticCoordinator(
    FakeAiRouteReviewRepository repository,
  ) {
    return RouteReviewCoordinator(
      usagePolicy: const CostOptimizedAiUsagePolicy(
        automaticReviewEnabled: true,
      ),
      budgetPolicy: const AiBudgetPolicy(),
      modelConfig: modelConfig,
      repository: repository,
    );
  }

  test('normal güvenilir rotada gereksiz AI çağrısını engeller', () async {
    final repository = FakeAiRouteReviewRepository(response: review());
    final route = Object();

    final outcome = await coordinator(repository).reviewIfAllowed(
      route: route,
      context: const AiReviewContext(
        planId: 'plan-1',
        routeConfidence: 0.92,
      ),
      request: request(),
    );

    expect(outcome.status, AiReviewOutcomeStatus.skippedByPolicy);
    expect(outcome.route, same(route));
    expect(repository.callCount, 0);
  });

  test('düşük güvenilirlik tek bir AI incelemesine izin verir', () async {
    final repository = FakeAiRouteReviewRepository(response: review());

    final outcome = await automaticCoordinator(repository).reviewIfAllowed(
      route: 'deterministic-route',
      context: const AiReviewContext(
        planId: 'plan-1',
        routeConfidence: 0.6,
      ),
      request: request(),
    );

    expect(outcome.status, AiReviewOutcomeStatus.reviewed);
    expect(outcome.review?.isLogical, isTrue);
    expect(repository.callCount, 1);
  });

  test('aynı rota ve tercih için AI cache kullanılır', () async {
    final repository = FakeAiRouteReviewRepository(response: review());
    final service = automaticCoordinator(repository);
    const context = AiReviewContext(
      planId: 'plan-1',
      routeConfidence: 0.6,
    );

    final first = await service.reviewIfAllowed(
      route: 'route-v1',
      context: context,
      request: request(),
    );
    final second = await service.reviewIfAllowed(
      route: 'route-v1',
      context: context,
      request: request(),
    );

    expect(first.status, AiReviewOutcomeStatus.reviewed);
    expect(second.status, AiReviewOutcomeStatus.cacheHit);
    expect(repository.callCount, 1);
  });

  test('AI hatası deterministik rota akışını bozmaz', () async {
    final repository = FakeAiRouteReviewRepository(
      response: review(),
      error: StateError('provider down'),
    );
    final route = Object();

    final outcome = await automaticCoordinator(repository).reviewIfAllowed(
      route: route,
      context: const AiReviewContext(
        planId: 'plan-1',
        routeConfidence: 0.5,
      ),
      request: request(),
    );

    expect(outcome.status, AiReviewOutcomeStatus.unavailable);
    expect(outcome.route, same(route));
    expect(outcome.review, isNull);
    expect(outcome.failure?.kind, AiReviewFailureKind.providerFailure);
  });

  test('AI bütçesi doluysa repository çağrılmaz', () async {
    final repository = FakeAiRouteReviewRepository(response: review());

    final outcome = await automaticCoordinator(repository).reviewIfAllowed(
      route: 'route',
      context: const AiReviewContext(
        planId: 'plan-1',
        routeConfidence: 0.4,
        callsForPlan: 1,
      ),
      request: request(),
    );

    expect(outcome.status, AiReviewOutcomeStatus.skippedByBudget);
    expect(repository.callCount, 0);
  });

  test('girdide olmayan aktivite üreten çıktı geçersizdir', () async {
    final repository = FakeAiRouteReviewRepository(
      response: AiRouteReview(
        isLogical: false,
        confidence: 0.2,
        summary: 'Kapsam dışı çıktı.',
        activityReasons: const [
          AiActivityReason(
            activityId: 'invented-station',
            reason: 'Girdide yok.',
          ),
        ],
        issues: const [],
      ),
    );

    final outcome = await automaticCoordinator(repository).reviewIfAllowed(
      route: 'route',
      context: const AiReviewContext(
        planId: 'plan-1',
        routeConfidence: 0.4,
      ),
      request: request(),
    );

    expect(outcome.status, AiReviewOutcomeStatus.invalidResponse);
    expect(outcome.review, isNull);
  });

  test('varsayılan politika düşük güvende bile otomatik AI çağırmaz', () async {
    final repository = FakeAiRouteReviewRepository(response: review());

    final outcome = await coordinator(repository).reviewIfAllowed(
      route: 'deterministic-route',
      context: const AiReviewContext(
        planId: 'plan-1',
        routeConfidence: 0.2,
      ),
      request: request(),
    );

    expect(outcome.status, AiReviewOutcomeStatus.skippedByPolicy);
    expect(repository.callCount, 0);
  });
}
