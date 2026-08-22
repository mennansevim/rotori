// Kullanıcının eklediği bilet açılış hatırlatmalarını listeler.
// Buradan tekli silme + tümünü temizleme yapılabilir.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n.dart';
import '../../data/reminders_store.dart';
import '../notifications/notifications_service.dart';
import '../plans/premium_provider.dart';
import '../viewer/viewer_theme.dart';
import 'reminder_composer_sheet.dart';

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = LanguageScope.of(context);
    final reminders = ref.watch(remindersProvider);
    final isPremium = ref.watch(premiumProvider);
    final palette = ViewerPalette.of(context);
    final sorted = [...reminders]..sort((a, b) => a.fireAt.compareTo(b.fireAt));
    final now = DateTime.now();
    final today = _dateOnly(now);
    final upcoming = sorted
        .where((reminder) => !reminder.fireAt.isBefore(now))
        .toList(growable: false);
    final featured = upcoming.isNotEmpty
        ? upcoming.first
        : (sorted.isEmpty ? null : sorted.last);
    final others = sorted
        .where((reminder) => reminder.id != featured?.id)
        .toList(growable: false);

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (sorted.isNotEmpty)
            IconButton(
              tooltip: s.s('reminders.clearAll'),
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _confirmClear(context, ref),
            ),
        ],
      ),
      body: CustomScrollView(
        key: const ValueKey('reminders-scroll'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            sliver: SliverToBoxAdapter(
              child: _RemindersHeader(
                palette: palette,
                summary: _remindersSummary(
                  context,
                  count: sorted.length,
                  featured: featured,
                  today: today,
                ),
                isPremium: isPremium,
                onAdd: () => _openComposer(context, ref),
              ),
            ),
          ),
          if (featured == null)
            SliverToBoxAdapter(
              child: _EmptyState(
                palette: palette,
                isPremium: isPremium,
                onAdd: () => _openComposer(context, ref),
              ),
            ),
          if (featured != null)
            SliverToBoxAdapter(
              child: _ReminderFeaturedCard(
                reminder: featured,
                palette: palette,
                now: now,
                onRemove: () => _removeReminder(context, ref, featured),
              ),
            ),
          if (others.isNotEmpty)
            SliverToBoxAdapter(
              child: _ReminderList(
                reminders: others,
                palette: palette,
                now: now,
                onRemove: (reminder) => _removeReminder(context, ref, reminder),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }

  Future<void> _openComposer(BuildContext context, WidgetRef ref) async {
    final count = await showReminderComposerSheet(
      context,
      isPremium: ref.read(premiumProvider),
    );
    if (count == null || count == 0 || !context.mounted) return;
    final lang = LanguageScope.of(context).lang;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          lang == AppLang.tr
              ? '$count hatırlatıcı eklendi'
              : '$count reminder${count == 1 ? '' : 's'} added',
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final s = LanguageScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.s('reminders.clearAllTitle')),
        content: Text(s.s('reminders.clearAllBody')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.s('reminders.cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.s('reminders.delete'))),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(notificationsServiceProvider).cancelAll();
    await ref.read(remindersProvider.notifier).clear();
  }

  Future<void> _removeReminder(
    BuildContext context,
    WidgetRef ref,
    Reminder reminder,
  ) async {
    await ref.read(notificationsServiceProvider).cancel(reminder);
    await ref.read(remindersProvider.notifier).remove(reminder.id);
  }
}

class _RemindersHeader extends StatelessWidget {
  const _RemindersHeader({
    required this.palette,
    required this.summary,
    required this.isPremium,
    required this.onAdd,
  });

  final ViewerPalette palette;
  final String? summary;
  final bool isPremium;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final addLabel =
        isPremium ? s.s('reminders.add') : s.s('reminders.premiumCta');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                s.s('reminders.title'),
                key: const ValueKey('reminders-title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 30,
                  height: 1.04,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.58,
                ),
              ),
            ),
            if (isPremium) ...[
              const SizedBox(width: 8),
              const _ProBadge(active: true),
            ],
            const SizedBox(width: 12),
            _AddReminderButton(label: addLabel, onPressed: onAdd),
          ],
        ),
        const SizedBox(height: 6),
        if (summary != null)
          Text(
            summary!,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }
}

class _AddReminderButton extends StatelessWidget {
  const _AddReminderButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = ViewerPalette.of(context);
    return Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      child: SizedBox.square(
        key: const ValueKey('add-reminder'),
        dimension: 44,
        child: Material(
          color: palette.accent.withValues(alpha: .10),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            excludeFromSemantics: true,
            customBorder: const CircleBorder(),
            splashFactory: NoSplash.splashFactory,
            overlayColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.pressed)
                  ? palette.accent.withValues(alpha: .17)
                  : null,
            ),
            child: Icon(
              Icons.add_rounded,
              size: 23,
              color: palette.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReminderFeaturedCard extends StatelessWidget {
  const _ReminderFeaturedCard({
    required this.reminder,
    required this.palette,
    required this.now,
    required this.onRemove,
  });

  final Reminder reminder;
  final ViewerPalette palette;
  final DateTime now;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final status = _statusFor(context, reminder, now);
    final colors = [palette.accentStrong, palette.sky];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: .16),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _StatusChip(
                        status: status,
                        foreground: Colors.white,
                        background: Colors.white.withValues(alpha: .16),
                      ),
                    ),
                    _ReminderDeleteButton(
                      reminder: reminder,
                      foreground: Colors.white,
                      background: Colors.white.withValues(alpha: .15),
                      onPressed: onRemove,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  reminder.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.45,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  reminder.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .84),
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                _ReminderDateTime(
                  reminder: reminder,
                  foreground: Colors.white.withValues(alpha: .94),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReminderList extends StatelessWidget {
  const _ReminderList({
    required this.reminders,
    required this.palette,
    required this.now,
    required this.onRemove,
  });

  final List<Reminder> reminders;
  final ViewerPalette palette;
  final DateTime now;
  final ValueChanged<Reminder> onRemove;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.s('reminders.other'),
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: .12,
            ),
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < reminders.length; index++) ...[
            _ReminderTile(
              reminder: reminders[index],
              palette: palette,
              now: now,
              onRemove: () => onRemove(reminders[index]),
            ),
            if (index != reminders.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.reminder,
    required this.palette,
    required this.now,
    required this.onRemove,
  });

  final Reminder reminder;
  final ViewerPalette palette;
  final DateTime now;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final status = _statusFor(context, reminder, now);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: status.tone.withValues(alpha: .24)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 10, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: status.tone.withValues(alpha: .10),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                _reminderIcon(reminder.windowId),
                size: 19,
                color: status.tone,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reminder.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 16,
                      height: 1.18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _StatusLine(status: status, palette: palette),
                  const SizedBox(height: 7),
                  _ReminderDateTime(
                    reminder: reminder,
                    foreground: palette.textSecondary,
                  ),
                ],
              ),
            ),
            _ReminderDeleteButton(
              reminder: reminder,
              foreground: palette.textSecondary,
              background: palette.bg,
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.status,
    required this.foreground,
    required this.background,
  });

  final _ReminderStatus status;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(status.icon, size: 15, color: foreground),
              const SizedBox(width: 6),
              Text(
                status.label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status, required this.palette});

  final _ReminderStatus status;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(status.icon, size: 16, color: status.tone),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              status.detail,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
}

class _ReminderDateTime extends StatelessWidget {
  const _ReminderDateTime({
    required this.reminder,
    required this.foreground,
  });

  final Reminder reminder;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 12,
        runSpacing: 7,
        children: [
          _InlineFact(
            icon: Icons.calendar_today_rounded,
            value: _formatDate(reminder.fireAt, LanguageScope.of(context)),
            color: foreground,
          ),
        ],
      );
}

class _InlineFact extends StatelessWidget {
  const _InlineFact({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}

class _ReminderDeleteButton extends StatelessWidget {
  const _ReminderDeleteButton({
    required this.reminder,
    required this.foreground,
    required this.background,
    required this.onPressed,
  });

  final Reminder reminder;
  final Color foreground;
  final Color background;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final label = s.p('reminders.remove', {'name': reminder.title});
    return Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      child: SizedBox.square(
        key: ValueKey('reminder-remove-${reminder.id}'),
        dimension: 44,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            excludeFromSemantics: true,
            customBorder: const CircleBorder(),
            splashFactory: NoSplash.splashFactory,
            overlayColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.pressed)
                  ? foreground.withValues(alpha: .16)
                  : null,
            ),
            child: Icon(
              Icons.delete_outline_rounded,
              size: 19,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.palette,
    required this.isPremium,
    required this.onAdd,
  });

  final ViewerPalette palette;
  final bool isPremium;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 48, 28, 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: .09),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                isPremium ? LucideIcons.bellOff : Icons.lock_rounded,
                size: 30,
                color: palette.accent,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isPremium
                ? s.s('reminders.emptyTitle')
                : s.s('reminders.premiumTitle'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 22,
              height: 1.15,
              fontWeight: FontWeight.w700,
              letterSpacing: -.3,
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              isPremium
                  ? s.s('reminders.emptyBody')
                  : s.s('reminders.premiumBody'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 15,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: FilledButton.icon(
              key: const ValueKey('add-first-reminder'),
              onPressed: onAdd,
              icon: Icon(
                isPremium ? Icons.add_rounded : Icons.lock_rounded,
              ),
              label: Text(
                isPremium ? s.s('reminders.add') : s.s('reminders.premiumCta'),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 44),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProBadge extends StatelessWidget {
  const _ProBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = ViewerPalette.of(context);
    final s = LanguageScope.of(context);
    final color = active ? palette.gold : palette.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.workspace_premium_rounded : Icons.lock_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            s.s('reminders.premiumBadge'),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: .5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderStatus {
  const _ReminderStatus({
    required this.label,
    required this.detail,
    required this.icon,
    required this.tone,
  });

  final String label;
  final String detail;
  final IconData icon;
  final Color tone;
}

_ReminderStatus _statusFor(
  BuildContext context,
  Reminder reminder,
  DateTime now,
) {
  final s = LanguageScope.of(context);
  final palette = ViewerPalette.of(context);
  final difference = reminder.fireAt.difference(now);
  if (difference.isNegative) {
    return _ReminderStatus(
      label: s.s('reminders.status.passed'),
      detail: s.s('reminders.status.passed'),
      icon: Icons.history_rounded,
      tone: palette.textMuted,
    );
  }
  final dayDifference =
      _dateOnly(reminder.fireAt).difference(_dateOnly(now)).inDays;
  if (dayDifference == 0) {
    return _ReminderStatus(
      label: s.s('reminders.status.today'),
      detail: s.p('reminders.inHours', {'n': '${difference.inHours}'}),
      icon: Icons.today_rounded,
      tone: palette.sunset,
    );
  }
  return _ReminderStatus(
    label: s.s('reminders.status.upcoming'),
    detail: s.p('reminders.inDays', {'n': '$dayDifference'}),
    icon: Icons.notifications_active_rounded,
    tone: palette.accent,
  );
}

String? _remindersSummary(
  BuildContext context, {
  required int count,
  required Reminder? featured,
  required DateTime today,
}) {
  if (count == 0) return null;
  final s = LanguageScope.of(context);
  final parts = <String>[
    s.p(
      count == 1
          ? 'reminders.summary.count.singular'
          : 'reminders.summary.count.plural',
      {'count': '$count'},
    ),
  ];
  if (featured != null) {
    final dayDifference = _dateOnly(featured.fireAt).difference(today).inDays;
    final next = dayDifference < 0
        ? s.s('reminders.summary.next.none')
        : dayDifference == 0
            ? s.s('reminders.summary.next.today')
            : dayDifference == 1
                ? s.s('reminders.summary.next.tomorrow')
                : s.p(
                    'reminders.summary.next.days',
                    {'count': '$dayDifference'},
                  );
    parts.add(next);
  }
  return parts.join(s.s('reminders.summary.separator'));
}

IconData _reminderIcon(String windowId) {
  if (windowId == 'shinkansen-smartex') return Icons.train_rounded;
  if (windowId == 'tokyo-disney') return Icons.castle_rounded;
  if (windowId == 'usj-express') return Icons.attractions_rounded;
  if (windowId.startsWith('teamlab-')) return Icons.auto_awesome_rounded;
  return Icons.notifications_rounded;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _formatDate(DateTime d, LanguageScope s) {
  final month = s.s('reminders.mon.${d.month}');
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.day.toString().padLeft(2, '0')} $month ${d.year} · $hh:$mm';
}
