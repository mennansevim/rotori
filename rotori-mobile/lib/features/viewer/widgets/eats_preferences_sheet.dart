// Beslenme tercihi + öğün bütçesi toplama sheet'i.
//
// **Neden var:** Rotori uyum skoru diyet ve bütçe girdilerine dayanıyor ama
// uygulama bu ikisini HİÇBİR YERDE sormuyordu — `mealBudgetJpyPerPerson`
// hiçbir ekran tarafından yazılmıyordu, `dietaryTags` de yalnızca hiç
// toplanmayan `foodSensitivities`'ten türetiliyordu. Sonuç: skor herkes için
// aynı nötr sayıya çıkıyordu.
//
// Girdileri KULLANILDIKLARI yerde soruyoruz. Plan oluşturmaya da eklendi
// (create/preferences_page.dart) ama asıl dönüşüm burada: kullanıcı skorun
// eksik olduğunu gördüğü anda dolduruyor.

import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/dietary.dart';
import '../../../domain/localized_text.dart';
import '../viewer_theme.dart';

/// Sheet'in döndürdüğü sonuç. Kullanıcı kaydetmeden çıkarsa null döner.
class EatsPreferencesResult {
  const EatsPreferencesResult({
    required this.dietaryTags,
    required this.mealBudgetJpy,
  });

  final List<String> dietaryTags;

  /// Kişi başı öğün bütçesi (JPY). Kullanıcı "belirtmek istemiyorum" derse
  /// null — bu, skorun bütçe bileşenini bilinmez bırakır.
  final int? mealBudgetJpy;
}

/// Kişi başı öğün bütçesi için hazır kademeler (JPY). Rotori Eats fiyat
/// kademeleriyle (¥/¥¥/¥¥¥/¥¥¥¥) hizalı.
const List<int> kMealBudgetPresets = [1500, 3000, 5000, 8000];

Future<EatsPreferencesResult?> showEatsPreferencesSheet({
  required BuildContext context,
  required ViewerPalette palette,
  required AppLang lang,
  required List<String> initialTags,
  required int? initialBudgetJpy,
}) {
  return showModalBottomSheet<EatsPreferencesResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ViewerPaletteScope(
      palette: palette,
      child: _EatsPreferencesSheet(
        palette: palette,
        lang: lang,
        initialTags: initialTags,
        initialBudgetJpy: initialBudgetJpy,
      ),
    ),
  );
}

class _EatsPreferencesSheet extends StatefulWidget {
  const _EatsPreferencesSheet({
    required this.palette,
    required this.lang,
    required this.initialTags,
    required this.initialBudgetJpy,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final List<String> initialTags;
  final int? initialBudgetJpy;

  @override
  State<_EatsPreferencesSheet> createState() => _EatsPreferencesSheetState();
}

class _EatsPreferencesSheetState extends State<_EatsPreferencesSheet> {
  late final Set<String> _tags = widget.initialTags.toSet();
  late int? _budget = widget.initialBudgetJpy;

  ViewerPalette get p => widget.palette;
  AppLang get lang => widget.lang;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final options = dietaryForCountry('JP');
    final maxH = MediaQuery.sizeOf(context).height * 0.9;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(color: p.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                children: [
                  Text(
                    const LText(
                      'Sana göre önerebilmem için',
                      'So I can recommend for you',
                    ).of(lang),
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    const LText(
                      'İkisi de isteğe bağlı. Boş bıraktığın kısım skorda '
                          '"eksik" olarak görünür — uydurma bir puan verilmez.',
                      'Both are optional. Anything you skip shows as "missing" '
                          'in the score — no made-up number is used.',
                    ).of(lang),
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- Beslenme tercihleri ---
                  _sectionTitle(
                    const LText('Beslenme tercihlerin', 'Your dietary needs'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in options)
                        _chip(
                          label: '${option.emoji} ${s.s(option.label)}',
                          active: _tags.contains(option.id),
                          onTap: () => setState(() {
                            _tags.contains(option.id)
                                ? _tags.remove(option.id)
                                : _tags.add(option.id);
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // --- Öğün bütçesi ---
                  _sectionTitle(
                    const LText(
                      'Kişi başı öğün bütçen',
                      'Meal budget per person',
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    const LText(
                      'Bir öğün için ayırdığın üst sınır.',
                      'The ceiling you set for a single meal.',
                    ).of(lang),
                    style: TextStyle(color: p.textMuted, fontSize: 11.5),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip(
                        label: const LText(
                                'Belirtmek istemiyorum', 'Prefer not to say')
                            .of(lang),
                        active: _budget == null,
                        onTap: () => setState(() => _budget = null),
                      ),
                      for (final preset in kMealBudgetPresets)
                        _chip(
                          label: '≤ ¥${_group(preset)}',
                          active: _budget == preset,
                          onTap: () => setState(() => _budget = preset),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: p.card,
                border: Border(top: BorderSide(color: p.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.textSecondary,
                        side: BorderSide(color: p.border),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        const LText('Vazgeç', 'Cancel').of(lang),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(
                        EatsPreferencesResult(
                          dietaryTags: _tags.toList(growable: false),
                          mealBudgetJpy: _budget,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        const LText('Kaydet', 'Save').of(lang),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
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

  Widget _sectionTitle(LText text) => Text(
        text.of(lang),
        style: TextStyle(
          color: p.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      );

  Widget _chip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Material(
      color: active ? p.accent.withValues(alpha: 0.16) : p.elevated,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: active ? p.accent : p.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? p.textPrimary : p.textSecondary,
              fontSize: 12.5,
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
