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
import '../../viewer/widgets/eats_preferences_sheet.dart' show kMealBudgetPresets;
import 'create_plan_widgets.dart';

class PreferencesPage extends StatelessWidget {
  const PreferencesPage({
    super.key,
    required this.palette,
    required this.dietTags,
    required this.mealBudgetJpy,
    required this.onToggleTag,
    required this.onPickBudget,
    required this.generating,
    required this.onGenerate,
  });

  final ViewerPalette palette;
  final List<String> dietTags;
  final int? mealBudgetJpy;
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
                style: TextStyle(color: p.textMuted, fontSize: 11.5, height: 1.4),
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
        style: TextStyle(color: palette.textSecondary, fontSize: 12, height: 1.35),
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

String _group(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
