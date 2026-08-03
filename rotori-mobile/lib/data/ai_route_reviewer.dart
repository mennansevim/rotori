import '../domain/ai_route_review.dart';

abstract interface class AiRouteReviewRepository {
  Future<AiRouteReview> review({
    required AiRouteReviewRequest request,
    required AiModelConfig modelConfig,
  });
}

/// Ağ veya model yapılandırılmadığında güvenli varsayılandır.
///
/// Rota hesaplamaz ve sessizce sahte açıklama üretmez.
class NoopAiRouteReviewRepository implements AiRouteReviewRepository {
  const NoopAiRouteReviewRepository();

  @override
  Future<AiRouteReview> review({
    required AiRouteReviewRequest request,
    required AiModelConfig modelConfig,
  }) {
    throw const AiReviewException(
      AiReviewFailureKind.unavailable,
      'AI inceleme servisi yapılandırılmadı.',
    );
  }
}

class FakeAiRouteReviewRepository implements AiRouteReviewRepository {
  FakeAiRouteReviewRepository({
    required this.response,
    this.error,
  });

  final AiRouteReview response;
  final Object? error;
  int callCount = 0;

  @override
  Future<AiRouteReview> review({
    required AiRouteReviewRequest request,
    required AiModelConfig modelConfig,
  }) async {
    callCount++;
    if (error != null) throw error!;
    return response;
  }
}

enum AiReviewFailureKind {
  unavailable,
  invalidResponse,
  budgetExceeded,
  providerFailure,
}

class AiReviewException implements Exception {
  const AiReviewException(this.kind, this.message);

  final AiReviewFailureKind kind;
  final String message;

  @override
  String toString() => 'AiReviewException($kind): $message';
}

abstract interface class AiRouteReviewCache {
  AiRouteReview? get(AiReviewCacheKey key);
  void put(AiReviewCacheKey key, AiRouteReview review);
}

class InMemoryAiRouteReviewCache implements AiRouteReviewCache {
  InMemoryAiRouteReviewCache({
    this.ttl = const Duration(days: 7),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _clock;
  final Map<AiReviewCacheKey, _CachedAiReview> _entries = {};

  @override
  AiRouteReview? get(AiReviewCacheKey key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (!_clock().isBefore(entry.createdAt.add(ttl))) {
      _entries.remove(key);
      return null;
    }
    return entry.review;
  }

  @override
  void put(AiReviewCacheKey key, AiRouteReview review) {
    _entries[key] = _CachedAiReview(review, _clock());
  }
}

class _CachedAiReview {
  const _CachedAiReview(this.review, this.createdAt);

  final AiRouteReview review;
  final DateTime createdAt;
}

enum AiReviewOutcomeStatus {
  reviewed,
  cacheHit,
  skippedByPolicy,
  skippedByBudget,
  invalidResponse,
  unavailable,
}

/// [route] her sonuçta aynı nesne olarak korunur. AI hatası deterministik
/// optimizasyon sonucunun gösterilmesini veya kaydedilmesini engelleyemez.
class AiReviewedRoute<T> {
  const AiReviewedRoute({
    required this.route,
    required this.status,
    this.review,
    this.failure,
  });

  final T route;
  final AiReviewOutcomeStatus status;
  final AiRouteReview? review;
  final AiReviewException? failure;
}

class RouteReviewCoordinator {
  RouteReviewCoordinator({
    required this.usagePolicy,
    required this.budgetPolicy,
    required this.modelConfig,
    required this.repository,
    AiRouteReviewCache? cache,
  }) : cache = cache ?? InMemoryAiRouteReviewCache();

  final AiUsagePolicy usagePolicy;
  final AiBudgetPolicy budgetPolicy;
  final AiModelConfig modelConfig;
  final AiRouteReviewRepository repository;
  final AiRouteReviewCache cache;

  Future<AiReviewedRoute<T>> reviewIfAllowed<T>({
    required T route,
    required AiReviewContext context,
    required AiRouteReviewRequest request,
  }) async {
    if (!usagePolicy.shouldReview(context)) {
      return AiReviewedRoute(
        route: route,
        status: AiReviewOutcomeStatus.skippedByPolicy,
      );
    }
    if (!budgetPolicy.allows(context, modelConfig)) {
      return AiReviewedRoute(
        route: route,
        status: AiReviewOutcomeStatus.skippedByBudget,
      );
    }
    if (!request.hasValidScope) {
      return AiReviewedRoute(
        route: route,
        status: AiReviewOutcomeStatus.invalidResponse,
        failure: const AiReviewException(
          AiReviewFailureKind.invalidResponse,
          'AI inceleme girdisi eksik.',
        ),
      );
    }

    final key = AiReviewCacheKey.fromRequest(
      request,
      modelConfig.reviewModel,
    );
    final cached = cache.get(key);
    if (cached != null) {
      return AiReviewedRoute(
        route: route,
        review: cached,
        status: AiReviewOutcomeStatus.cacheHit,
      );
    }

    try {
      final review = await repository.review(
        request: request,
        modelConfig: modelConfig,
      );
      if (!review.isWithinScope(request)) {
        return AiReviewedRoute(
          route: route,
          status: AiReviewOutcomeStatus.invalidResponse,
          failure: const AiReviewException(
            AiReviewFailureKind.invalidResponse,
            'AI çıktısı rota girdisinin kapsamı dışında.',
          ),
        );
      }
      cache.put(key, review);
      return AiReviewedRoute(
        route: route,
        review: review,
        status: AiReviewOutcomeStatus.reviewed,
      );
    } catch (error) {
      final failure = error is AiReviewException
          ? error
          : AiReviewException(
              AiReviewFailureKind.providerFailure,
              error.runtimeType.toString(),
            );
      return AiReviewedRoute(
        route: route,
        status: AiReviewOutcomeStatus.unavailable,
        failure: failure,
      );
    }
  }
}
