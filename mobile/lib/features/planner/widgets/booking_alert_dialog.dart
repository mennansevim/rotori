// USJ / Disney / Shinkansen bilet açılış hatırlatmaları için popup.
// "Planı yeniden oluştur" sonrasında (plan_step.dart) tetiklenir.
// Her uyarı için kullanıcı "hatırlatma ekle" toggle'ını açabilir; onaylayınca
// remindersProvider'a kaydedilir ve platform destekliyorsa yerel bildirim schedule
// edilir.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n.dart';
import '../../../data/reminders_store.dart';
import '../../../domain/booking_windows.dart';
import '../../notifications/notifications_service.dart';

class BookingAlertsResult {
  const BookingAlertsResult({required this.addedCount});
  final int addedCount;
}

Future<BookingAlertsResult?> showBookingAlertsDialog({
  required BuildContext context,
  required ProviderContainer container,
  required List<BookingAlert> alerts,
  required String tripId,
}) {
  if (alerts.isEmpty) return Future.value(null);
  return showDialog<BookingAlertsResult>(
    context: context,
    builder: (_) => _BookingAlertsSheet(
      alerts: alerts,
      tripId: tripId,
      container: container,
    ),
  );
}

class _BookingAlertsSheet extends StatefulWidget {
  const _BookingAlertsSheet({
    required this.alerts,
    required this.tripId,
    required this.container,
  });
  final List<BookingAlert> alerts;
  final String tripId;
  final ProviderContainer container;

  @override
  State<_BookingAlertsSheet> createState() => _BookingAlertsSheetState();
}

class _BookingAlertsSheetState extends State<_BookingAlertsSheet> {
  late final Map<String, bool> _selected = {
    for (final a in widget.alerts)
      a.window.id: !widget.container
          .read(remindersProvider.notifier)
          .hasFor(a.window.id, tripId: widget.tripId),
  };
  bool _busy = false;

  Future<void> _confirm() async {
    if (_busy) return;
    final s = LanguageScope.of(context);
    setState(() => _busy = true);
    final store = widget.container.read(remindersProvider.notifier);
    final svc = widget.container.read(notificationsServiceProvider);

    var added = 0;
    for (final a in widget.alerts) {
      if (_selected[a.window.id] != true) continue;
      final fireAt = DateTime(
        a.opensOn.year,
        a.opensOn.month,
        a.opensOn.day,
        a.window.reminderNoonHour,
      );
      final reminder = Reminder(
        id: '${a.window.id}-${widget.tripId}',
        windowId: a.window.id,
        title: a.window.title,
        subtitle: s.p('booking.reminderSubtitle',
            {'date': _formatDate(a.eventOn, s.lang)}),
        icon: a.window.icon,
        fireAt: fireAt,
        tip: a.window.tip,
        tripId: widget.tripId,
      );
      await store.add(reminder);
      try {
        await svc.requestPermissionIfNeeded();
        await svc.schedule(reminder);
      } catch (_) {
        // izin reddedilse bile store'a eklenir; kullanıcı ekrandan görür.
      }
      added++;
    }

    if (!mounted) return;
    Navigator.pop(context, BookingAlertsResult(addedCount: added));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = LanguageScope.of(context);
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      title: Row(
        children: [
          const Text('🎟️', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(s.s('booking.title'),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 460),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.s('booking.body'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final a in widget.alerts)
                _AlertTile(
                  alert: a,
                  selected: _selected[a.window.id] ?? false,
                  onChanged: (v) =>
                      setState(() => _selected[a.window.id] = v),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(s.s('booking.notNow')),
        ),
        FilledButton(
          onPressed: _busy ? null : _confirm,
          child: Text(
              _busy ? s.s('booking.adding') : s.s('booking.addReminders')),
        ),
      ],
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.alert,
    required this.selected,
    required this.onChanged,
  });
  final BookingAlert alert;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = LanguageScope.of(context);
    final now = DateTime.now();
    final opens = alert.opensOn;
    final daysUntil = opens.difference(DateTime(now.year, now.month, now.day)).inDays;
    final passed = daysUntil <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(alert.window.icon, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(alert.window.title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(alert.window.subtitle,
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Switch(value: selected, onChanged: passed ? null : onChanged),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _Pill(
                text: s.p('booking.salePill', {
                  'date': _formatDate(alert.opensOn, s.lang),
                  'days': '${alert.window.opensBeforeDays}',
                }),
                color: passed ? Colors.orange : theme.colorScheme.primary,
              ),
              _Pill(
                text: s.p('booking.planDayPill',
                    {'date': _formatDate(alert.eventOn, s.lang)}),
                color: theme.colorScheme.secondary,
              ),
              if (passed)
                _Pill(
                    text: s.s('booking.windowPassed'),
                    color: Colors.deepOrange),
            ],
          ),
          const SizedBox(height: 6),
          Text('💡 ${alert.window.tip}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

String _formatDate(DateTime d, AppLang lang) {
  const tr = [
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
  const en = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  final months = lang == AppLang.en ? en : tr;
  return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
}
