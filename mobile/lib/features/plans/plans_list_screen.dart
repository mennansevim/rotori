import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../data/plans_repository.dart';
import '../../domain/trip_factory.dart';
import '../auth/auth_repository.dart';
import 'plan_providers.dart';

/// Kullanıcının planları — offline-first liste + yeni plan oluşturma.
class PlansListScreen extends ConsumerWidget {
  const PlansListScreen({super.key});

  Future<void> _createNew(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(plansRepositoryProvider);
    if (repo == null) return;
    final trip = createEmptyTrip();
    await repo.save(trip);
    // pullProvider'ı invalidate ki liste yenilensin
    ref.invalidate(plansPullProvider);
    if (context.mounted) {
      context.go('/plans/${trip.id}/edit');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = LanguageScope.of(context);
    final pull = ref.watch(plansPullProvider);
    final plans = ref.watch(localPlansProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            // Küçük mor 旅 rozet — marka izi (avatar-mini).
            const _BrandBadge(),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                s.s('plans.title'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: s.s('plans.refresh'),
            onPressed: () => ref.invalidate(plansPullProvider),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: s.s('plans.signOut'),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: pull.when(
        loading: () => plans.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _PlansList(plans: plans),
        error: (err, _) => _PlansList(plans: plans, offlineHint: '$err'),
        data: (_) =>
            plans.isEmpty ? const _EmptyState() : _PlansList(plans: plans),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createNew(context, ref),
        icon: const Icon(Icons.add),
        label: Text(s.s('plans.newPlan')),
      ),
    );
  }
}

/// AppBar title yanındaki küçük mor 旅 rozet — Rotori marka izi.
class _BrandBadge extends StatelessWidget {
  const _BrandBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C6AEF), Color(0xFFB07CD6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: const Text(
        '旅',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 16,
          height: 1.0,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🗾', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              s.s('plans.emptyTitle'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              s.s('plans.emptyBody'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlansList extends StatelessWidget {
  const _PlansList({required this.plans, this.offlineHint});
  final List<dynamic> plans;
  final String? offlineHint;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: plans.length + (offlineHint != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (offlineHint != null && index == 0) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_off, color: Colors.orange),
              title: Text(s.s('plans.offline')),
              subtitle: Text(
                offlineHint!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }
        final trip = plans[offlineHint != null ? index - 1 : index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Text('🇯🇵')),
            title: Text(trip.title as String),
            subtitle: Text(
              s.p('plans.dateRange', {
                'start': trip.tripStart.toString().substring(0, 10),
                'end': trip.tripEnd.toString().substring(0, 10),
                'n': '${(trip.days as List).length}',
              }),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.visibility),
                  tooltip: s.s('plans.view'),
                  onPressed: () => context.go('/plans/${trip.id}/view'),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: s.s('plans.edit'),
                  onPressed: () => context.go('/plans/${trip.id}/edit'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
