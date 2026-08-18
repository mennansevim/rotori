import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../data/plans_repository.dart';
import '../../domain/city_hero_assets.dart';
import '../../domain/types.dart';
import '../auth/auth_repository.dart';
import '../viewer/viewer_theme.dart';
import 'plan_providers.dart';

/// Plan kartında rotadaki şehirleri sabit sırada, ülke adıyla birlikte gösterir.
String planDestinationLine(Trip trip) {
  final destinations = [...trip.preferences.destinations]
    ..sort((a, b) => a.order.compareTo(b.order));
  final cities = <String>[];
  for (final destination in destinations) {
    final city = destination.city.trim();
    if (city.isNotEmpty && !cities.contains(city)) cities.add(city);
  }
  final country = destinations
      .map((destination) => destination.countryName.trim())
      .firstWhere((name) => name.isNotEmpty, orElse: () => '');
  if (cities.isEmpty) return country;
  return country.isEmpty ? cities.join(', ') : '${cities.join(', ')}, $country';
}

/// Kartın altındaki destinasyon rozetinin TR/EN metni.
String planDestinationCount(Trip trip, AppLang lang) {
  final cities = trip.preferences.destinations
      .map((destination) => destination.city.trim())
      .where((city) => city.isNotEmpty)
      .toSet()
      .length;
  return L10n.parametrize(
    L10n.resolve('plans.destinations', lang),
    {'n': '$cities'},
  );
}

/// Referans kartındaki kısa, okunabilir tarih aralığını üretir.
String planDateRange(Trip trip, AppLang lang) {
  final start = DateTime.tryParse(trip.tripStart);
  final end = DateTime.tryParse(trip.tripEnd);
  if (start == null || end == null) {
    return '${trip.tripStart} → ${trip.tripEnd}';
  }

  final months = L10n.monthsShortFor(lang);
  final startMonth = months[start.month];
  final endMonth = months[end.month];
  final sameMonth = start.year == end.year && start.month == end.month;

  if (lang == AppLang.tr) {
    if (sameMonth) return '${start.day}–${end.day} $startMonth ${end.year}';
    return '${start.day} $startMonth–${end.day} $endMonth ${end.year}';
  }
  if (sameMonth) return '$startMonth ${start.day}–${end.day}, ${end.year}';
  return '$startMonth ${start.day}–$endMonth ${end.day}, ${end.year}';
}

int planDayCount(Trip trip) {
  if (trip.days.isNotEmpty) return trip.days.length;
  final start = DateTime.tryParse(trip.tripStart);
  final end = DateTime.tryParse(trip.tripEnd);
  if (start == null || end == null) return 0;
  return end.difference(start).inDays + 1;
}

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

  final List<Trip> plans;
  final ViewerPalette palette;
  final String? offlineHint;

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Trip trip,
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
          s.p('plans.deleteConfirmBody', {'title': trip.title}),
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
    await repo.delete(trip.id);
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
        return _PlanCard(
          trip: trip,
          palette: palette,
          lang: s.lang,
          onTap: () => context.go('/plans/${trip.id}/view'),
          onEdit: () => context.go('/plans/${trip.id}/edit'),
          onDelete: () => _confirmDelete(context, ref, trip),
        );
      },
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.trip,
    required this.palette,
    required this.lang,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final Trip trip;
  final ViewerPalette palette;
  final AppLang lang;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final destinations = [...trip.preferences.destinations]
      ..sort((a, b) => a.order.compareTo(b.order));
    final firstCity = destinations.isEmpty ? null : destinations.first.city;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.textPrimary.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 178,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      cityHeroAssetFor(firstCity),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ColoredBox(
                        color: palette.accent.withValues(alpha: 0.18),
                        child: Icon(
                          Icons.landscape_outlined,
                          size: 46,
                          color: palette.accent,
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.26),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.08),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: PopupMenuButton<String>(
                        tooltip: s.s('plans.edit'),
                        icon: const Icon(Icons.more_horiz_rounded),
                        iconColor: Colors.white,
                        color: palette.card,
                        onSelected: (value) {
                          if (value == 'edit') onEdit();
                          if (value == 'delete') onDelete();
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.edit_outlined),
                              title: Text(s.s('plans.edit')),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.delete_outline,
                                  color: palette.sunset),
                              title: Text(s.s('plans.delete')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 24,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      planDestinationLine(trip),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 17,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Icon(Icons.calendar_month_outlined,
                            size: 24, color: palette.textSecondary),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            planDateRange(trip, lang),
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _PlanPill(
                          label: s.p('plans.days', {
                            'n': '${planDayCount(trip)}',
                          }),
                          color: palette.accent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _PlanPill(
                          icon: Icons.location_on_outlined,
                          label: planDestinationCount(trip, lang),
                          color: palette.textSecondary,
                        ),
                        const Spacer(),
                        CircleAvatar(
                          radius: 22,
                          backgroundColor:
                              palette.accent.withValues(alpha: 0.16),
                          child: Icon(Icons.route_rounded,
                              color: palette.accent, size: 22),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanPill extends StatelessWidget {
  const _PlanPill({this.icon, required this.label, required this.color});

  final IconData? icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
