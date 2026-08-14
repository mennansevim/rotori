import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/data/offline_japan_route_matrix.dart';
import 'package:rotori/data/route_matrix_remote.dart';
import 'package:rotori/domain/plan_generation.dart';
import 'package:rotori/domain/route_execution.dart';
import 'package:rotori/domain/route_matrix.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/plans/initial_trip_route_planner.dart';
import 'package:rotori/features/plans/plan_optimization_controller.dart';

void main() {
  test('ilk plan normal gezi günlerini optimize eder, sabit günleri korur',
      () async {
    final original = buildTripFromCities(
      cityKeys: const ['tokyo'],
      startYmd: '2026-10-01',
      endYmd: '2026-10-07',
    );
    final arrivalIds =
        original.days.first.items.map((item) => item.id).toList();
    final container = ProviderContainer(
      overrides: [
        routeMatrixRepositoryProvider.overrideWithValue(
          const _UnavailableRouteRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final optimized = await optimizeInitialTripRoutes(
      trip: original,
      buildPreview: container
          .read(planOptimizationControllerProvider.notifier)
          .buildInitialPreview,
    );

    expect(
      optimized.days.first.items.map((item) => item.id),
      arrivalIds,
      reason: 'uçuş/otel içeren varış günü değiştirilmemeli',
    );
    expect(
      optimized.days
          .where((day) => day.routeExecutionSnapshot != null)
          .isNotEmpty,
      isTrue,
      reason: 'en az bir normal gezi günü rota snapshotı taşımalı',
    );
    for (final day in optimized.days.where(
      (day) => day.routeExecutionSnapshot != null,
    )) {
      expect(day.items.every((item) => item.lat != null && item.lng != null),
          isTrue);
    }
  });

  test('varsayılan ilk plan bütünüyle offline Japonya paketiyle oluşur',
      () async {
    final original = buildTripFromCities(
      cityKeys: const ['tokyo'],
      startYmd: '2026-10-01',
      endYmd: '2026-10-07',
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final optimized = await optimizeInitialTripRoutes(
      trip: original,
      buildPreview: container
          .read(planOptimizationControllerProvider.notifier)
          .buildInitialPreview,
    );
    final snapshots = optimized.days
        .map((day) => day.routeExecutionSnapshot)
        .whereType<RouteExecutionSnapshot>()
        .toList(growable: false);

    expect(snapshots, isNotEmpty);
    for (final snapshot in snapshots) {
      expect(snapshot.matrixVersion, startsWith('offline-jp-'));
      expect(snapshot.providerIds, [kOfflineJapanRouteProviderId]);
      expect(snapshot.legs, isNotEmpty);
      expect(
        snapshot.legs.every(
          (leg) => leg.providerId == kOfflineJapanRouteProviderId,
        ),
        isTrue,
      );
    }
  });

  test('aday yeniden optimizasyonu yalnız etkilenen günü değiştirir', () async {
    final original = buildTripFromCities(
      cityKeys: const ['tokyo'],
      startYmd: '2026-10-01',
      endYmd: '2026-10-07',
    );
    final target = original.days.firstWhere(
      (day) =>
          day.items.length >= 2 &&
          !day.items.any((item) => item.kind == TimelineItemKind.transport),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final optimized = await optimizeInitialTripRoutes(
      trip: original,
      dayNumbers: {target.dayNumber},
      useInputOrderAsHint: true,
      buildPreview: container
          .read(planOptimizationControllerProvider.notifier)
          .buildInitialPreview,
    );

    expect(
      optimized.days
          .where((day) => day.routeExecutionSnapshot != null)
          .map((day) => day.dayNumber),
      [target.dayNumber],
    );
  });
}

class _UnavailableRouteRepository implements RouteMatrixRepository {
  const _UnavailableRouteRepository();

  @override
  Future<RouteMatrix> getRouteMatrix({
    required List<TripLocation> locations,
    required DateTime day,
    required RoutePreferences preferences,
  }) {
    throw const RouteMatrixFailure(
      kind: RouteMatrixFailureKind.unavailable,
      message: 'test fallback',
      retryable: false,
    );
  }
}
