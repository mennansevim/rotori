// Yolculuk öncesi hazırlık listesi — ayrı ekran.
//
// Viewer aksiyon şeridindeki `Icons.checklist` butonundan açılır. Countdown +
// progress + preset & custom maddeler + "kendi maddeni ekle" + görünme eşiği
// ayarı. ViewerPalette'a uyumlu.
//
// Persistence: PreDepartureChecklistRepository (SharedPreferences + varsa
// Supabase). Kullanıcı login değilse yalnızca yerel çalışır.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/pre_departure_checklist_repository.dart';
import '../../domain/pre_departure_checklist.dart';
import '../../domain/types.dart';
import 'viewer_theme.dart';

class PreDepartureChecklistScreen extends ConsumerWidget {
  const PreDepartureChecklistScreen({super.key, required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(viewerPaletteProvider);
    return Theme(
      data: palette.toThemeData(),
      child: ViewerPaletteScope(
        palette: palette,
        child: _PrepView(trip: trip),
      ),
    );
  }
}

class _PrepView extends ConsumerWidget {
  const _PrepView({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ViewerPalette.of(context);
    final s = LanguageScope.of(context);
    final state = ref.watch(preDepartureChecklistProvider(trip.id));
    final notifier = ref.read(preDepartureChecklistProvider(trip.id).notifier);

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          s.s('prep.title'),
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        backgroundColor: palette.card,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: s.s('prep.settings.title'),
            icon: Icon(Icons.tune, color: palette.textPrimary),
            onPressed: () => _openSettings(context, state, notifier, palette),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _CountdownCard(trip: trip, state: state, palette: palette),
          const SizedBox(height: 16),
          for (final item in state.items)
            _PrepRow(
              item: item,
              palette: palette,
              onToggle: () => notifier.toggle(item.id),
              onDelete:
                  item.custom ? () => notifier.removeCustom(item.id) : null,
            ),
          const SizedBox(height: 24),
          _AddCustomTile(
            palette: palette,
            onSubmit: (label, emoji) => notifier.addCustom(label, emoji: emoji),
          ),
        ],
      ),
    );
  }

  Future<void> _openSettings(
    BuildContext context,
    PreDepartureChecklist state,
    PreDepartureChecklistNotifier notifier,
    ViewerPalette palette,
  ) async {
    final s = LanguageScope.of(context);
    var current = state.daysBefore.toDouble();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Theme(
        data: palette.toThemeData(),
        child: StatefulBuilder(
          builder: (ctx, setState) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              20 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 4,
                  width: 40,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Text(
                  s.s('prep.settings.daysBefore'),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.p('prep.settings.daysBeforeValue',
                      {'n': '${current.toInt()}'}),
                  style: TextStyle(
                    color: palette.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Slider(
                  min: 1,
                  max: 30,
                  divisions: 29,
                  value: current.clamp(1, 30),
                  activeColor: palette.accent,
                  inactiveColor: palette.border,
                  onChanged: (v) => setState(() => current = v),
                  onChangeEnd: (v) => notifier.setDaysBefore(v.toInt()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Countdown + progress kartı
// ---------------------------------------------------------------------------

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({
    required this.trip,
    required this.state,
    required this.palette,
  });

  final Trip trip;
  final PreDepartureChecklist state;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final days = PreDepartureChecklist.daysUntil(trip.tripStart);
    final countdown = (days == null || days == 0)
        ? s.s('prep.countdown.started')
        : s.p('prep.countdown.before', {'n': '$days'});
    final progressText = state.allDone
        ? s.s('prep.allReady')
        : s.p('prep.status', {
            'done': '${state.doneCount}',
            'total': '${state.totalCount}',
          });
    final fraction = state.totalCount == 0
        ? 0.0
        : (state.doneCount / state.totalCount).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: state.allDone
              ? palette.matcha.withValues(alpha: 0.6)
              : palette.accent.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            countdown,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            progressText,
            style: TextStyle(
              color: state.allDone ? palette.matcha : palette.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Container(
                    height: 10,
                    width: double.infinity,
                    color: palette.elevated,
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    height: 10,
                    width: constraints.maxWidth * fraction,
                    color: state.allDone ? palette.matcha : palette.accent,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Madde satırı
// ---------------------------------------------------------------------------

class _PrepRow extends StatelessWidget {
  const _PrepRow({
    required this.item,
    required this.palette,
    required this.onToggle,
    this.onDelete,
  });

  final PrepItem item;
  final ViewerPalette palette;
  final VoidCallback onToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final lang = s.lang;
    // Preset maddelerde metinler i18n sözlüğünden çözülür; custom'larda
    // storage'daki düz metin (labelTr/En) kullanılır.
    final title = item.custom
        ? (lang == AppLang.en
            ? (item.labelEn ?? item.labelTr ?? '')
            : (item.labelTr ?? item.labelEn ?? ''))
        : s.s('prep.item.${item.id}.title');
    final desc = item.custom
        ? (lang == AppLang.en ? item.descEn : item.descTr)
        : () {
            final resolved = s.s('prep.item.${item.id}.desc');
            // Sözlükte yoksa anahtar geri döner → boş göster.
            return resolved == 'prep.item.${item.id}.desc' ? null : resolved;
          }();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: palette.elevated,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.emoji.isEmpty ? '📌' : item.emoji,
                  style: const TextStyle(fontSize: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          color: item.checked
                              ? palette.textMuted
                              : palette.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          decoration: item.checked
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          decorationColor: palette.textMuted,
                        ),
                        child: Text(title),
                      ),
                      if (desc != null && desc.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          desc,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 12,
                            height: 1.3,
                            decoration: item.checked
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: palette.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  item.checked
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: item.checked ? palette.matcha : palette.textMuted,
                  size: 24,
                ),
                if (onDelete != null)
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: palette.textMuted,
                      size: 20,
                    ),
                    tooltip: LanguageScope.of(context).s('common.delete'),
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: onDelete,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "+ Kendi maddeni ekle" — inline text input
// ---------------------------------------------------------------------------

class _AddCustomTile extends StatefulWidget {
  const _AddCustomTile({required this.palette, required this.onSubmit});

  final ViewerPalette palette;
  final void Function(String label, String emoji) onSubmit;

  @override
  State<_AddCustomTile> createState() => _AddCustomTileState();
}

class _AddCustomTileState extends State<_AddCustomTile> {
  final _labelController = TextEditingController();
  final _emojiController = TextEditingController();
  bool _expanded = false;

  @override
  void dispose() {
    _labelController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _labelController.text.trim();
    if (label.isEmpty) return;
    final emoji = _emojiController.text.trim();
    widget.onSubmit(label, emoji.isEmpty ? '📌' : emoji);
    _labelController.clear();
    _emojiController.clear();
    setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final s = LanguageScope.of(context);
    if (!_expanded) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => setState(() => _expanded = true),
          icon: Icon(Icons.add, color: palette.accent, size: 18),
          label: Text(
            s.s('prep.addCustom'),
            style: TextStyle(
              color: palette.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: palette.accent.withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _emojiController,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.textPrimary, fontSize: 18),
                  decoration: InputDecoration(
                    hintText: '📌',
                    hintStyle: TextStyle(color: palette.textMuted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    labelText: s.s('prep.addCustom.emoji'),
                    labelStyle: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: palette.border),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _labelController,
                  autofocus: true,
                  style: TextStyle(color: palette.textPrimary),
                  decoration: InputDecoration(
                    hintText: s.s('prep.addCustom.hint'),
                    hintStyle: TextStyle(color: palette.textMuted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: palette.border),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  _labelController.clear();
                  _emojiController.clear();
                  setState(() => _expanded = false);
                },
                child: Text(s.s('common.cancel')),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(backgroundColor: palette.accent),
                child: Text(s.s('common.add')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
