// Oluşturma akışı 3/3 — "Damak tadın".
//
// **Neden eklendi:** Rotori Eats'in uyum skoru beslenme tercihi ve öğün
// bütçesine dayanıyor ama uygulama bu ikisini hiçbir yerde sormuyordu:
// `mealBudgetJpyPerPerson` hiçbir ekran tarafından yazılmıyor,
// `dietaryTags` de hiç toplanmayan `foodSensitivities`'ten türetiliyordu.
// Sonuç, herkeste aynı çıkan sahte bir "uyum" skoruydu.
//
// Adım İSTEĞE BAĞLI: atlanırsa skor o bileşeni "eksik" gösterir, nötr bir
// puanla doldurmaz. Aynı alanlar Rotori Eats içinden de düzenlenebilir
// (viewer/widgets/eats_preferences_sheet.dart) — tek kaynak trip.preferences.
//
// Durum parent'ta (CreatePlanScreen) tutulur; bu sayfa saf gösterimdir.

import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/dietary.dart';
import '../../viewer/viewer_theme.dart';
import '../../viewer/widgets/eats_preferences_sheet.dart'
    show kMealBudgetPresets;
import 'create_plan_widgets.dart';

class PreferencesPage extends StatelessWidget {
  const PreferencesPage({
    super.key,
    required this.palette,
    required this.dietTags,
    required this.mealBudgetJpy,
    required this.routeSummary,
    required this.dateSummary,
    required this.datesEstimated,
    required this.onEditCities,
    required this.onEditDates,
    required this.onToggleTag,
    required this.onPickBudget,
    required this.generating,
    required this.onGenerate,
  });

  final ViewerPalette palette;
  final List<String> dietTags;
  final int? mealBudgetJpy;
  final String routeSummary;
  final String dateSummary;
  final bool datesEstimated;
  final VoidCallback onEditCities;
  final VoidCallback onEditDates;
  final void Function(String tagId) onToggleTag;
  final void Function(int? jpy) onPickBudget;
  final bool generating;
  final VoidCallback? onGenerate;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = LanguageScope.of(context);
    final options = dietaryForCountry('JP');
    final selected = dietTags.toSet();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            children: [
              _AssumptionSummaryCard(
                palette: p,
                routeSummary: routeSummary,
                dateSummary: dateSummary,
                datesEstimated: datesEstimated,
                onEditCities: onEditCities,
                onEditDates: onEditDates,
              ),
              const SizedBox(height: 24),
              _title(s.s('create.prefs.diet')),
              const SizedBox(height: 3),
              _hint(s.s('create.prefs.dietHint')),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in options)
                    _chip(
                      label: '${option.emoji} ${s.s(option.label)}',
                      active: selected.contains(option.id),
                      onTap: () => onToggleTag(option.id),
                    ),
                ],
              ),
              const SizedBox(height: 26),
              _title(s.s('create.prefs.budget')),
              const SizedBox(height: 3),
              _hint(s.s('create.prefs.budgetHint')),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(
                    label: s.s('create.prefs.budgetSkip'),
                    active: mealBudgetJpy == null,
                    onTap: () => onPickBudget(null),
                  ),
                  for (final preset in kMealBudgetPresets)
                    _chip(
                      label: '≤ ¥${_group(preset)}',
                      active: mealBudgetJpy == preset,
                      onTap: () => onPickBudget(preset),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                s.s('create.prefs.sub'),
                style:
                    TextStyle(color: p.textMuted, fontSize: 11.5, height: 1.4),
              ),
            ],
          ),
        ),
        CreateBottomBar(
          palette: p,
          child: BrandButton(
            palette: p,
            block: true,
            busy: generating,
            label: generating
                ? s.s('create.generating')
                : '✨ ${s.s('create.generate')}',
            onPressed: onGenerate,
          ),
        ),
      ],
    );
  }

  Widget _title(String text) => Text(
        text,
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      );

  Widget _hint(String text) => Text(
        text,
        style:
            TextStyle(color: palette.textSecondary, fontSize: 12, height: 1.35),
      );

  Widget _chip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final p = palette;
    return Material(
      color: active ? p.accent.withValues(alpha: 0.16) : p.card,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: active ? p.accent : p.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? p.textPrimary : p.textSecondary,
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _AssumptionSummaryCard extends StatelessWidget {
  const _AssumptionSummaryCard({
    required this.palette,
    required this.routeSummary,
    required this.dateSummary,
    required this.datesEstimated,
    required this.onEditCities,
    required this.onEditDates,
  });

  final ViewerPalette palette;
  final String routeSummary;
  final String dateSummary;
  final bool datesEstimated;
  final VoidCallback onEditCities;
  final VoidCallback onEditDates;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.accent.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.s('create.assumptions.title'),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            s.s('create.assumptions.help'),
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          _AssumptionRow(
            icon: Icons.route_outlined,
            label: s.s('create.assumptions.route'),
            value: routeSummary,
            actionLabel: s.s('create.assumptions.edit'),
            onEdit: onEditCities,
            palette: palette,
          ),
          _AssumptionRow(
            icon: Icons.calendar_month_outlined,
            label: s.s('create.assumptions.dates'),
            value: dateSummary,
            badge: datesEstimated
                ? s.s('create.assumptions.estimatedBadge')
                : null,
            helper: datesEstimated
                ? s.s('create.assumptions.estimatedReason')
                : null,
            actionLabel: s.s('create.assumptions.edit'),
            onEdit: onEditDates,
            palette: palette,
          ),
          _AssumptionRow(
            icon: Icons.flight_outlined,
            label: s.s('create.assumptions.flight'),
            value: s.s('create.assumptions.draft'),
            palette: palette,
          ),
          _AssumptionRow(
            icon: Icons.hotel_outlined,
            label: s.s('create.assumptions.hotel'),
            value: s.s('create.assumptions.draft'),
            palette: palette,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _AssumptionRow extends StatelessWidget {
  const _AssumptionRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.palette,
    this.badge,
    this.helper,
    this.actionLabel,
    this.onEdit,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final ViewerPalette palette;
  final String? badge;
  final String? helper;
  final String? actionLabel;
  final VoidCallback? onEdit;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: palette.accent),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        badge!,
                        style: TextStyle(
                          color: palette.gold,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (helper != null)
                  Text(
                    helper!,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 10.5,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
          if (onEdit != null)
            TextButton(
              onPressed: onEdit,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 7),
              ),
              child: Text(actionLabel ?? ''),
            ),
        ],
      ),
    );
  }
}

String _group(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
