// Kullanıcının eklediği bilet açılış hatırlatmalarını listeler.
// Buradan tekli silme + tümünü temizleme yapılabilir.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/reminders_store.dart';
import '../notifications/notifications_service.dart';

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(remindersProvider);
    final sorted = [...reminders]..sort((a, b) => a.fireAt.compareTo(b.fireAt));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Hatırlatmalar'),
        actions: [
          if (sorted.isNotEmpty)
            IconButton(
              tooltip: 'Tümünü temizle',
              icon: const Icon(LucideIcons.trash2),
              onPressed: () => _confirmClear(context, ref),
            ),
        ],
      ),
      body: sorted.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _ReminderTile(reminder: sorted[i]),
            ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tümünü sil'),
        content: const Text(
            'Tüm hatırlatmalar silinsin mi? Bildirim planlamaları da iptal edilir.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(notificationsServiceProvider).cancelAll();
    await ref.read(remindersProvider.notifier).clear();
  }
}

class _ReminderTile extends ConsumerWidget {
  const _ReminderTile({required this.reminder});
  final Reminder reminder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final diff = reminder.fireAt.difference(now);
    final passed = diff.isNegative;
    final label = passed
        ? 'Bugün / geçti'
        : diff.inDays >= 1
            ? '${diff.inDays} gün sonra'
            : '${diff.inHours} saat sonra';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(reminder.icon, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reminder.title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(reminder.subtitle, style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _Pill(
                      icon: LucideIcons.calendarClock,
                      text: _formatDate(reminder.fireAt),
                      color: passed ? Colors.deepOrange : theme.colorScheme.primary,
                    ),
                    _Pill(
                      icon: LucideIcons.timer,
                      text: label,
                      color: theme.colorScheme.secondary,
                    ),
                  ],
                ),
                if (reminder.tip.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('💡 ${reminder.tip}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Sil',
            icon: const Icon(LucideIcons.x),
            onPressed: () async {
              await ref.read(notificationsServiceProvider).cancel(reminder);
              await ref.read(remindersProvider.notifier).remove(reminder.id);
            },
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.bellOff,
                size: 42, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text('Henüz hatırlatma yok',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Planına USJ, Tokyo Disney veya Shinkansen eklediğinde '
              '"Planı yeniden oluştur" adımında sana bilet açılış '
              'tarihi için hatırlatma teklif edeceğim.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime d) {
  const months = [
    'Oca',
    'Şub',
    'Mar',
    'Nis',
    'May',
    'Haz',
    'Tem',
    'Ağu',
    'Eyl',
    'Eki',
    'Kas',
    'Ara'
  ];
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year} · $hh:$mm';
}
