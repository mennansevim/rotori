import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/reminders_store.dart';
import '../../domain/booking_windows.dart';
import '../../domain/localized_text.dart';
import '../notifications/notifications_service.dart';
import '../shared/rotori_premium_sheet.dart';

Future<int?> showReminderComposerSheet(
  BuildContext context, {
  required bool isPremium,
  String? initialWindowId,
}) {
  if (!isPremium) {
    final s = LanguageScope.of(context);
    return showRotoriPremiumSheet<int>(
      context,
      title: s.s('reminders.premiumTitle'),
      body: s.s('reminders.premiumBody'),
      closeLabel: s.s('reminders.premiumClose'),
      sheetKey: const ValueKey('reminder-premium-sheet'),
      closeButtonKey: const ValueKey('reminder-premium-close'),
      benefits: [
        RotoriPremiumBenefit(
          icon: Icons.event_available_rounded,
          text: s.s('reminders.premiumBenefitDates'),
        ),
        RotoriPremiumBenefit(
          icon: Icons.layers_rounded,
          text: s.s('reminders.premiumBenefitMultiple'),
        ),
        RotoriPremiumBenefit(
          icon: Icons.tune_rounded,
          text: s.s('reminders.premiumBenefitCustom'),
        ),
      ],
    );
  }
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReminderComposerSheet(initialWindowId: initialWindowId),
  );
}

class _ReminderComposerSheet extends ConsumerStatefulWidget {
  const _ReminderComposerSheet({this.initialWindowId});

  final String? initialWindowId;

  @override
  ConsumerState<_ReminderComposerSheet> createState() =>
      _ReminderComposerSheetState();
}

class _ReminderComposerSheetState
    extends ConsumerState<_ReminderComposerSheet> {
  final Set<String> _selected = {};
  final Map<String, DateTime> _eventDates = {};

  /// "Ziyaret tarihleri" bölümüne kaydırmak için.
  final GlobalKey _datesSectionKey = GlobalKey();
  final TextEditingController _customTitle = TextEditingController();
  bool _customEnabled = false;
  DateTime? _customDate;
  TimeOfDay _customTime = const TimeOfDay(hour: 9, minute: 0);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (bookingWindowById(widget.initialWindowId ?? '') != null) {
      _selected.add(widget.initialWindowId!);
    }
  }

  @override
  void dispose() {
    _customTitle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = LanguageScope.of(context).lang;
    final selectedWindows = kBookingWindows
        .where((window) => _selected.contains(window.id))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: .9,
      minChildSize: .62,
      maxChildSize: .96,
      expand: false,
      builder: (context, controller) => Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 10, 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.tertiary,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.notifications_active_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          const LText('Rotori hatırlatıcısı', 'Rotori reminder')
                              .of(lang),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.4,
                          ),
                        ),
                        Text(
                          const LText(
                            'Birden fazla seçebilir, sonra tarihlerini ayrı ayrı belirleyebilirsin.',
                            'Select several, then set each visit date separately.',
                          ).of(lang),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 130),
                children: [
                  _InfoBanner(lang: lang),
                  const SizedBox(height: 20),
                  _ComposerTitle(
                    title: const LText('Hazır seçimler', 'Ready-made choices')
                        .of(lang),
                    subtitle: const LText(
                      'Satış tarihi ziyaret gününden otomatik hesaplanır.',
                      'The sale date is calculated from your visit date.',
                    ).of(lang),
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = (constraints.maxWidth - 10) / 2;
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (var i = 0; i < kBookingWindows.length; i++)
                            SizedBox(
                              width: width,
                              child: _PresetCard(
                                window: kBookingWindows[i],
                                lang: lang,
                                selected:
                                    _selected.contains(kBookingWindows[i].id),
                                onTap: () => setState(() {
                                  final id = kBookingWindows[i].id;
                                  if (!_selected.add(id)) {
                                    _selected.remove(id);
                                    _eventDates.remove(id);
                                  }
                                }),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  if (selectedWindows.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _ComposerTitle(
                      key: _datesSectionKey,
                      title: const LText('Ziyaret tarihleri', 'Visit dates')
                          .of(lang),
                      subtitle: const LText(
                        'Her seçim için gideceğin günü belirt.',
                        'Choose the day you will use each selection.',
                      ).of(lang),
                    ),
                    const SizedBox(height: 10),
                    for (final window in selectedWindows) ...[
                      _SelectedDateTile(
                        window: window,
                        date: _eventDates[window.id],
                        lang: lang,
                        onTap: () => _pickEventDate(window),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                  const SizedBox(height: 14),
                  _CustomReminderCard(
                    enabled: _customEnabled,
                    titleController: _customTitle,
                    date: _customDate,
                    time: _customTime,
                    lang: lang,
                    onToggle: (value) => setState(() => _customEnabled = value),
                    onTitleChanged: (_) => setState(() {}),
                    onPickDate: _pickCustomDate,
                    onPickTime: _pickCustomTime,
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                12 + MediaQuery.paddingOf(context).bottom,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pasif butonun NEDENİ.
                  //
                  // **Why:** Bir hazır seçim işaretlendiğinde buton yine pasif
                  // kalıyordu, çünkü `_canSave` her seçim için ziyaret tarihi
                  // şart koşuyor. Tarih alanı ise altı kartlık ızgaranın
                  // ALTINDA, kaydırmadan görünmüyor. Kullanıcı için buton
                  // sebepsiz bozuk görünüyordu. Satır eksiği söylüyor ve
                  // dokununca ilgili bölüme kaydırıyor.
                  if (_missingDateCount > 0) ...[
                    _BlockedHint(
                      text: lang == AppLang.tr
                          ? '$_missingDateCount seçim için ziyaret tarihi gerekiyor'
                          : '$_missingDateCount selection(s) need a visit date',
                      actionLabel:
                          const LText('Tarihi seç', 'Pick the date').of(lang),
                      onTap: _scrollToDates,
                    ),
                    const SizedBox(height: 10),
                  ] else if (!_canSave) ...[
                    _BlockedHint(
                      text: const LText(
                        'Bir hazır seçim işaretle ya da kendi hatırlatıcını ekle',
                        'Pick a ready-made choice or add your own reminder',
                      ).of(lang),
                    ),
                    const SizedBox(height: 10),
                  ],
                  FilledButton.icon(
                    key: const ValueKey('save-reminders'),
                    onPressed: _canSave && !_saving ? _save : null,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.notifications_active_rounded),
                    label: Text(
                      _saving
                          ? const LText('Ekleniyor…', 'Adding…').of(lang)
                          : const LText(
                              'Seçilen hatırlatıcıları ekle',
                              'Add selected reminders',
                            ).of(lang),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Seçili ama ziyaret tarihi girilmemiş hazır seçim sayısı.
  int get _missingDateCount =>
      _selected.where((id) => !_eventDates.containsKey(id)).length;

  void _scrollToDates() {
    final ctx = _datesSectionKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: .1,
    );
  }

  bool get _canSave {
    if (_selected.any((id) => !_eventDates.containsKey(id))) return false;
    final hasPreset = _selected.isNotEmpty;
    final hasCustom = _customEnabled &&
        _customTitle.text.trim().isNotEmpty &&
        _customDate != null;
    return hasPreset || hasCustom;
  }

  Future<void> _pickEventDate(BookingWindow window) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final firstDate = today.add(Duration(days: window.opensBeforeDays + 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDates[window.id] ?? firstDate,
      firstDate: firstDate,
      lastDate: DateTime(today.year + 4, 12, 31),
      helpText: LanguageScope.of(context).lang == AppLang.tr
          ? '${L10n.resolve(window.title, AppLang.tr)} ziyaret tarihi'
          : '${L10n.resolve(window.title, AppLang.en)} visit date',
    );
    if (picked != null && mounted) {
      setState(() => _eventDates[window.id] = picked);
    }
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDate ?? now.add(const Duration(days: 1)),
      firstDate: DateUtils.dateOnly(now),
      lastDate: DateTime(now.year + 4, 12, 31),
    );
    if (picked != null && mounted) setState(() => _customDate = picked);
  }

  Future<void> _pickCustomTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _customTime,
    );
    if (picked != null && mounted) setState(() => _customTime = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final lang = LanguageScope.of(context).lang;
    final notifications = ref.read(notificationsServiceProvider);
    await notifications.requestPermissionIfNeeded();
    var added = 0;

    for (final id in _selected) {
      final window = bookingWindowById(id)!;
      final eventDate = _eventDates[id]!;
      final saleDate = window.saleDateFor(eventDate);
      final reminder = Reminder(
        id: 'preset-$id-${eventDate.millisecondsSinceEpoch}',
        windowId: id,
        title: L10n.resolve(window.title, lang),
        subtitle: lang == AppLang.tr
            ? 'Ziyaret: ${_shortDate(eventDate, lang)} · ${window.opensBeforeDays} gün önce'
            : 'Visit: ${_shortDate(eventDate, lang)} · ${window.opensBeforeDays} days ahead',
        icon: window.icon,
        fireAt: DateTime(
          saleDate.year,
          saleDate.month,
          saleDate.day,
          window.reminderNoonHour,
        ),
        tip: L10n.resolve(window.tip, lang),
        tripId: null,
      );
      await ref.read(remindersProvider.notifier).add(reminder);
      await notifications.schedule(reminder);
      added++;
    }

    if (_customEnabled && _customDate != null) {
      final date = _customDate!;
      final reminder = Reminder(
        id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
        windowId: 'custom-${DateTime.now().microsecondsSinceEpoch}',
        title: _customTitle.text.trim(),
        subtitle: lang == AppLang.tr
            ? 'Özel Rotori hatırlatıcısı'
            : 'Custom Rotori reminder',
        icon: '🔔',
        fireAt: DateTime(
          date.year,
          date.month,
          date.day,
          _customTime.hour,
          _customTime.minute,
        ),
        tip: '',
        tripId: null,
      );
      await ref.read(remindersProvider.notifier).add(reminder);
      await notifications.schedule(reminder);
      added++;
    }

    if (mounted) Navigator.pop(context, added);
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.lang});
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: theme.colorScheme.primary.withValues(alpha: .2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              const LText(
                'Hazır seçimlerde bildirim, hesaplanan satış gününün sabahı 09:00’da cihaz saatine göre gelir. Satın almadan önce resmî takvimi yeniden kontrol et.',
                'Ready-made alerts fire at 09:00 device time on the calculated sale day. Recheck the official schedule before purchase.',
              ).of(lang),
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pasif CTA'nın nedenini söyleyen satır. Verildiyse dokunulabilir ve eksik
/// alana kaydırır — "buton çalışmıyor" hissini "şu eksik" bilgisine çevirir.
class _BlockedHint extends StatelessWidget {
  const _BlockedHint({
    required this.text,
    this.actionLabel,
    this.onTap,
  });

  final String text;
  final String? actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Row(
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
        ),
        if (actionLabel != null) ...[
          const SizedBox(width: 8),
          Text(
            actionLabel!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: '$text. $actionLabel',
      child: InkWell(
        key: const ValueKey('reminder-blocked-hint'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: row,
        ),
      ),
    );
  }
}

class _ComposerTitle extends StatelessWidget {
  const _ComposerTitle({
    super.key,
    required this.title,
    required this.subtitle,
  });
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(subtitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.window,
    required this.lang,
    required this.selected,
    required this.onTap,
  });

  final BookingWindow window;
  final AppLang lang;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const gold = Color(0xFFFFD166);
    final accent = _presetAccent(window.id);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('reminder-preset-${window.id}'),
        onTap: onTap,
        child: Ink(
          height: 174,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _presetGradient(window.id),
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? gold : Colors.white.withValues(alpha: .3),
              width: selected ? 2.2 : 1,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -28,
                top: -34,
                child: Icon(
                  _presetIcon(window.id),
                  size: 128,
                  color: accent.withValues(alpha: .08),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 74,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black38],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: accent.withValues(alpha: .42),
                            ),
                          ),
                          child: Icon(
                            _presetIcon(window.id),
                            size: 28,
                            color: accent,
                          ),
                        ),
                        const Spacer(),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 27,
                          height: 27,
                          decoration: BoxDecoration(
                            color: selected
                                ? gold
                                : Colors.black.withValues(alpha: .28),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? gold
                                  : Colors.white.withValues(alpha: .74),
                              width: 1.8,
                            ),
                          ),
                          child: selected
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Color(0xFF211A47),
                                  size: 18,
                                )
                              : null,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      L10n.resolve(window.title, lang),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        height: 1.12,
                        shadows: const [
                          Shadow(color: Colors.black54, blurRadius: 8),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          Icons.notifications_active_rounded,
                          size: 14,
                          color: selected ? gold : accent,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            lang == AppLang.tr
                                ? '${window.opensBeforeDays} gün önce'
                                : '${window.opensBeforeDays} days ahead',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: selected ? gold : accent,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
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

class _SelectedDateTile extends StatelessWidget {
  const _SelectedDateTile({
    required this.window,
    required this.date,
    required this.lang,
    required this.onTap,
  });

  final BookingWindow window;
  final DateTime? date;
  final AppLang lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saleDate = date == null ? null : window.saleDateFor(date!);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _presetIcon(window.id),
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.resolve(window.title, lang),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      saleDate == null
                          ? const LText(
                              'Ziyaret tarihini seç',
                              'Choose visit date',
                            ).of(lang)
                          : lang == AppLang.tr
                              ? 'Hatırlatma: ${_shortDate(saleDate, lang)} · 09:00 cihaz saati'
                              : 'Reminder: ${_shortDate(saleDate, lang)} · 09:00 device time',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: saleDate == null
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.calendar_month_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomReminderCard extends StatelessWidget {
  const _CustomReminderCard({
    required this.enabled,
    required this.titleController,
    required this.date,
    required this.time,
    required this.lang,
    required this.onToggle,
    required this.onTitleChanged,
    required this.onPickDate,
    required this.onPickTime,
  });

  final bool enabled;
  final TextEditingController titleController;
  final DateTime? date;
  final TimeOfDay time;
  final AppLang lang;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onTitleChanged;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: enabled
            ? theme.colorScheme.tertiaryContainer.withValues(alpha: .42)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  const LText(
                    'Özel hatırlatıcı ekle',
                    'Add a custom reminder',
                  ).of(lang),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Switch(
                key: const ValueKey('custom-reminder-toggle'),
                value: enabled,
                onChanged: onToggle,
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('custom-reminder-title'),
              controller: titleController,
              onChanged: onTitleChanged,
              decoration: InputDecoration(
                labelText: const LText(
                  'Neyi hatırlatayım?',
                  'What should I remind you about?',
                ).of(lang),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('custom-reminder-date'),
                    onPressed: onPickDate,
                    icon: const Icon(Icons.calendar_today_rounded, size: 17),
                    label: Text(date == null
                        ? const LText('Tarih', 'Date').of(lang)
                        : _shortDate(date!, lang)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPickTime,
                    icon: const Icon(Icons.schedule_rounded, size: 17),
                    label: Text(
                      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _shortDate(DateTime date, AppLang lang) {
  final month = L10n.monthsFor(lang)[date.month].substring(0, 3);
  return '${date.day} $month ${date.year}';
}

List<Color> _presetGradient(String id) {
  if (id == 'shinkansen-smartex') {
    return const [Color(0xFF24385F), Color(0xFF17233E)];
  }
  if (id == 'tokyo-disney') {
    return const [Color(0xFF524464), Color(0xFF2E293F)];
  }
  if (id == 'usj-express') {
    return const [Color(0xFF5A3E49), Color(0xFF302938)];
  }
  if (id == 'teamlab-planets') {
    return const [Color(0xFF24545E), Color(0xFF1B3442)];
  }
  if (id == 'teamlab-borderless') {
    return const [Color(0xFF4B405E), Color(0xFF2D2B45)];
  }
  return const [Color(0xFF315847), Color(0xFF1E382E)];
}

Color _presetAccent(String id) {
  if (id == 'shinkansen-smartex') return const Color(0xFFAEC9FF);
  if (id == 'tokyo-disney') return const Color(0xFFD9C2F1);
  if (id == 'usj-express') return const Color(0xFFFFC1CB);
  if (id == 'teamlab-planets') return const Color(0xFF9ADFE9);
  if (id == 'teamlab-borderless') return const Color(0xFFD4C4F5);
  return const Color(0xFFA8DDB9);
}

IconData _presetIcon(String id) {
  if (id == 'shinkansen-smartex') return Icons.train_rounded;
  if (id == 'tokyo-disney') return Icons.castle_rounded;
  if (id == 'usj-express') return Icons.attractions_rounded;
  if (id == 'teamlab-planets') return Icons.water_drop_rounded;
  if (id == 'teamlab-borderless') return Icons.all_inclusive_rounded;
  return Icons.local_florist_rounded;
}
