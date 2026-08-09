import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../data/plans_repository.dart';
import '../auth/auth_repository.dart';
import '../viewer/viewer_theme.dart';
import 'plan_providers.dart';

/// Apple sadeliği + Japon seyahat günlüğü hissi veren planlar ana ekranı.
class PlansListScreen extends ConsumerWidget {
  const PlansListScreen({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final s = LanguageScope.of(context);
    final palette = ref.read(viewerPaletteProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.card,
        title: Text(
          s.s('plans.signOutConfirmTitle'),
          style: TextStyle(color: palette.textPrimary),
        ),
        content: Text(
          s.s('plans.signOutConfirmBody'),
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.s('plans.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.s('plans.signOutConfirmAction')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(authRepositoryProvider).signOut();
  }

  /// Boş trip'i ÖNCEDEN kaydetmez — kullanıcı akıştan çıkarsa listede hayalet
  /// plan kalmasın. Kayıt, plan üretildikten sonra CreatePlanScreen'de yapılır.
  /// `push` (go değil): iptal edilirse sistem geri hareketi listeye döner.
  void _createNew(BuildContext context) => context.push('/plans/new');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = LanguageScope.of(context);
    final palette = ref.watch(viewerPaletteProvider);
    final pull = ref.watch(plansPullProvider);
    final plans = ref.watch(localPlansProvider);

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _PlansHeader(
              palette: palette,
              title: s.s('plans.title'),
              onRefresh: () => ref.invalidate(plansPullProvider),
              onSignOut: () => _confirmSignOut(context, ref),
            ),
            Expanded(
              child: pull.when(
                loading: () => plans.isEmpty
                    ? Center(
                        child: CircularProgressIndicator(color: palette.accent))
                    : _PlansList(plans: plans, palette: palette),
                error: (err, _) => _PlansList(
                  plans: plans,
                  palette: palette,
                  offlineHint: '$err',
                ),
                data: (_) => plans.isEmpty
                    ? _EmptyState(palette: palette)
                    : _PlansList(plans: plans, palette: palette),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createNew(context),
        icon: const Icon(Icons.add),
        label: Text(s.s('plans.newPlan')),
        backgroundColor: palette.accent,
        foregroundColor: palette.topBarOnColor,
      ),
    );
  }
}

class _PlansHeader extends StatelessWidget {
  const _PlansHeader({
    required this.palette,
    required this.title,
    required this.onRefresh,
    required this.onSignOut,
  });

  final ViewerPalette palette;
  final String title;
  final VoidCallback onRefresh;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final onColor = palette.topBarOnColor;
    final s = LanguageScope.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: palette.topBar,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: onColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: onColor.withValues(alpha: 0.24)),
            ),
            alignment: Alignment.center,
            child: Text(
              '旅',
              style: TextStyle(
                color: onColor,
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: onColor,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  s.s('plans.headerSubtitle'),
                  style: TextStyle(
                    color: onColor.withValues(alpha: 0.78),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: onColor),
            tooltip: s.s('plans.refresh'),
            onPressed: onRefresh,
          ),
          IconButton(
            icon: Icon(Icons.logout_rounded, color: onColor),
            tooltip: s.s('plans.signOut'),
            onPressed: onSignOut,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette});
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('旅', style: TextStyle(fontSize: 64, color: palette.accent)),
            const SizedBox(height: 16),
            Text(
              s.s('plans.emptyTitle'),
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.s('plans.emptyBody'),
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlansList extends ConsumerWidget {
  const _PlansList({
    required this.plans,
    required this.palette,
    this.offlineHint,
  });

  final List<dynamic> plans;
  final ViewerPalette palette;
  final String? offlineHint;

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    dynamic trip,
  ) async {
    final s = LanguageScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.card,
        title: Text(
          s.s('plans.deleteConfirmTitle'),
          style: TextStyle(color: palette.textPrimary),
        ),
        content: Text(
          s.p('plans.deleteConfirmBody', {'title': trip.title as String}),
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.s('plans.cancel')),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
              backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.s('plans.deleteConfirmAction')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(plansRepositoryProvider);
    if (repo == null) return;
    await repo.delete(trip.id as String);
    ref.invalidate(plansPullProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = LanguageScope.of(context);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
      itemCount: plans.length + (offlineHint != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (offlineHint != null && index == 0) {
          return Card(
            color: palette.card,
            elevation: 0,
            child: ListTile(
              leading: Icon(Icons.cloud_off, color: palette.gold),
              title: Text(s.s('plans.offline'),
                  style: TextStyle(color: palette.textPrimary)),
              subtitle: Text(
                offlineHint!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.textSecondary),
              ),
            ),
          );
        }
        final trip = plans[offlineHint != null ? index - 1 : index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: palette.card,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: palette.border),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            onTap: () => context.go('/plans/${trip.id}/view'),
            leading: CircleAvatar(
              backgroundColor: palette.accent.withValues(alpha: 0.16),
              child: Text('旅', style: TextStyle(color: palette.accent)),
            ),
            title: Text(
              trip.title as String,
              style: TextStyle(
                  color: palette.textPrimary, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              s.p('plans.dateRange', {
                'start': trip.tripStart.toString().substring(0, 10),
                'end': trip.tripEnd.toString().substring(0, 10),
                'n': '${(trip.days as List).length}',
              }),
              style: TextStyle(color: palette.textSecondary),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.edit_outlined, color: palette.textSecondary),
                  tooltip: s.s('plans.edit'),
                  onPressed: () => context.go('/plans/${trip.id}/edit'),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: palette.sunset),
                  tooltip: s.s('plans.delete'),
                  onPressed: () => _confirmDelete(context, ref, trip),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
