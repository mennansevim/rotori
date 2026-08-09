// Oluşturma akışı 1/2 — "Japonya'da nereye?"
//
// Durum parent'ta (CreatePlanScreen) tutulur; bu sayfa saf gösterimdir.

import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/city_places.dart';
import '../../viewer/viewer_theme.dart';
import 'create_plan_widgets.dart';

class CitySelectPage extends StatelessWidget {
  const CitySelectPage({
    super.key,
    required this.palette,
    required this.selectedKeys,
    required this.onToggle,
    required this.onContinue,
  });

  final ViewerPalette palette;

  /// Seçim SIRASI anlamlıdır — rota sırası buradan üretilir.
  final List<String> selectedKeys;
  final void Function(String cityKey) onToggle;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.32,
            ),
            itemCount: kCityData.length,
            itemBuilder: (context, i) {
              final c = kCityData[i];
              final idx = selectedKeys.indexOf(c.key);
              return CityTile(
                palette: palette,
                emoji: c.emoji,
                label: c.label,
                placeCountLabel: s.p(
                  'create.cities.placeCount',
                  {'n': '${c.places.length}'},
                ),
                selected: idx >= 0,
                orderIndex: idx + 1,
                onTap: () => onToggle(c.key),
              );
            },
          ),
        ),
        CreateBottomBar(
          palette: palette,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selectedKeys.isEmpty
                      ? s.s('create.cities.selectHint')
                      : s.p('create.cities.selected',
                          {'n': '${selectedKeys.length}'}),
                  style: TextStyle(
                    color: selectedKeys.isEmpty
                        ? palette.textMuted
                        : palette.textSecondary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              BrandButton(
                palette: palette,
                label: s.s('create.continue'),
                onPressed: onContinue,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
