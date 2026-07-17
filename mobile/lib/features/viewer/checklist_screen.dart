// Valiz & Hazırlık — Japonya'ya özel, kategorilere ayrılmış hazırlık listesi.
// Maddelere dokununca işaretlenir; işaretli durum plan (trip) bazında kalıcıdır.
// Kullanıcı kendi maddesini ekleyebilir, özel maddeyi silebilir, tüm listeyi
// sıfırlayabilir.
//
// Viewer paletine uyumlu (Theme + ViewerPaletteScope), Türkçe UI. Ağ YOK.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/checklist_store.dart';
import '../../domain/packing_data.dart';
import '../../domain/types.dart';
import 'viewer_theme.dart';

class ChecklistScreen extends ConsumerWidget {
  const ChecklistScreen({super.key, required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(viewerPaletteProvider);
    return Theme(
      data: palette.toThemeData(),
      child: ViewerPaletteScope(
        palette: palette,
        child: _ChecklistView(trip: trip),
      ),
    );
  }
}

/// Kategori grupları: (kategori adı, o kategorinin maddeleri).
typedef CategoryGroups = List<MapEntry<String, List<ChecklistItem>>>;

/// Kategori adı → (şablon + özel) maddeler, ilk görülme sırasını koruyarak.
CategoryGroups _groupByCategory(ChecklistState st) {
  final map = <String, List<ChecklistItem>>{};
  for (final item in [...kJapanChecklist, ...st.customItems]) {
    map.putIfAbsent(item.category, () => <ChecklistItem>[]).add(item);
  }
  return map.entries.toList();
}

class _ChecklistView extends ConsumerWidget {
  const _ChecklistView({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ViewerPalette.of(context);
    final state = ref.watch(checklistProvider(trip.id));
    final notifier = ref.read(checklistProvider(trip.id).notifier);

    final groups = _groupByCategory(state);
    final allIds = <String>{
      for (final i in kJapanChecklist) i.id,
      for (final i in state.customItems) i.id,
    };
    final total = allIds.length;
    final done = state.checkedIds.where(allIds.contains).length;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          '🎒 Valiz & Hazırlık',
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
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: palette.textPrimary),
            color: palette.card,
            onSelected: (v) {
              if (v == 'reset') _confirmReset(context, palette, notifier);
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                value: 'reset',
                child: Text(
                  'Sıfırla',
                  style: TextStyle(color: palette.textPrimary),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _ProgressCard(done: done, total: total, palette: palette),
          const SizedBox(height: 16),
          for (final group in groups) ...[
            _CategoryHeader(title: group.key, palette: palette),
            for (final item in group.value)
              _ChecklistRow(
                item: item,
                checked: state.checkedIds.contains(item.id),
                isCustom:
                    state.customItems.any((c) => c.id == item.id),
                palette: palette,
                onToggle: () => notifier.toggle(item.id),
                onDelete: () => notifier.removeCustom(item.id),
              ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          _AddButton(
            palette: palette,
            onTap: () => _addCustom(context, palette, notifier, groups),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset(
    BuildContext context,
    ViewerPalette palette,
    ChecklistNotifier notifier,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: palette.toThemeData(),
        child: AlertDialog(
          backgroundColor: palette.card,
          title: Text(
            'Listeyi sıfırla?',
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            'Tüm işaretler ve eklediğin özel maddeler silinecek.',
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: palette.sunset),
              child: const Text('Sıfırla'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await notifier.reset();
  }

  Future<void> _addCustom(
    BuildContext context,
    ViewerPalette palette,
    ChecklistNotifier notifier,
    CategoryGroups groups,
  ) async {
    // Kategori seçenekleri: şablon kategorileri (ilk görülme sırasıyla) + Diğer.
    final categories = <String>[
      for (final g in groups) g.key,
    ];
    if (!categories.contains('Diğer')) categories.add('Diğer');

    final labelController = TextEditingController();
    var selectedCategory = categories.first;

    final result = await showDialog<_CustomEntry>(
      context: context,
      builder: (ctx) {
        return Theme(
          data: palette.toThemeData(),
          child: StatefulBuilder(
            builder: (ctx, setState) => AlertDialog(
              backgroundColor: palette.card,
              title: Text(
                'Kendi maddeni ekle',
                style: TextStyle(color: palette.textPrimary),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kategori',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButton<String>(
                    value: selectedCategory,
                    isExpanded: true,
                    dropdownColor: palette.card,
                    style: TextStyle(color: palette.textPrimary),
                    items: [
                      for (final c in categories)
                        DropdownMenuItem<String>(
                          value: c,
                          child: Text(
                            c,
                            style: TextStyle(color: palette.textPrimary),
                          ),
                        ),
                    ],
                    onChanged: (v) =>
                        setState(() => selectedCategory = v ?? selectedCategory),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: labelController,
                    autofocus: true,
                    style: TextStyle(color: palette.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Madde',
                      labelStyle: TextStyle(color: palette.textSecondary),
                      border: const OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: palette.border),
                      ),
                    ),
                    onSubmitted: (_) => Navigator.of(ctx).pop(
                      _CustomEntry(selectedCategory, labelController.text),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('İptal'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(
                    _CustomEntry(selectedCategory, labelController.text),
                  ),
                  style: FilledButton.styleFrom(backgroundColor: palette.accent),
                  child: const Text('Ekle'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result != null && result.label.trim().isNotEmpty) {
      await notifier.addCustom(result.category, result.label);
    }
  }
}

class _CustomEntry {
  const _CustomEntry(this.category, this.label);
  final String category;
  final String label;
}

// ---------------------------------------------------------------------------
// İlerleme kartı.
// ---------------------------------------------------------------------------

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.done,
    required this.total,
    required this.palette,
  });

  final int done;
  final int total;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final fraction = total > 0 ? done / total : 0.0;
    final allDone = total > 0 && done == total;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.matcha.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  allDone ? '✅ Her şey hazır!' : 'Hazırlık durumu',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                '$done / $total hazır',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Container(
                      height: 10,
                      width: double.infinity,
                      color: palette.elevated,
                    ),
                    Container(
                      height: 10,
                      width: constraints.maxWidth * fraction.clamp(0.0, 1.0),
                      color: palette.matcha,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kategori başlığı.
// ---------------------------------------------------------------------------

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.title, required this.palette});

  final String title;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: palette.accent,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Madde satırı — dokununca işaretlenir; özel maddede silme afordansı.
// ---------------------------------------------------------------------------

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.item,
    required this.checked,
    required this.isCustom,
    required this.palette,
    required this.onToggle,
    required this.onDelete,
  });

  final ChecklistItem item;
  final bool checked;
  final bool isCustom;
  final ViewerPalette palette;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
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
                Icon(
                  checked
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: checked ? palette.matcha : palette.textMuted,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                color: checked
                                    ? palette.textMuted
                                    : palette.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                decoration: checked
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: palette.textMuted,
                              ),
                            ),
                          ),
                          if (isCustom) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: palette.accent.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'özel',
                                style: TextStyle(
                                  color: palette.accent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (item.note != null && item.note!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.note!,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 12,
                            height: 1.3,
                            decoration: checked
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: palette.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isCustom)
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: palette.textMuted,
                      size: 20,
                    ),
                    tooltip: 'Sil',
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
// "+ Kendi maddeni ekle" butonu.
// ---------------------------------------------------------------------------

class _AddButton extends StatelessWidget {
  const _AddButton({required this.palette, required this.onTap});

  final ViewerPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(Icons.add, color: palette.accent, size: 18),
        label: Text(
          'Kendi maddeni ekle',
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
}
