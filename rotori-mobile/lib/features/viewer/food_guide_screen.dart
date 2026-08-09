import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/google_maps_launcher.dart';
import '../../data/language_store.dart';
import '../../data/unit_cost_table_store.dart';
import '../../domain/cost_estimate.dart';
import '../../domain/dietary.dart';
import '../../domain/eats.dart';
import '../../domain/localized_text.dart';
import '../../domain/types.dart';
import 'budget_screen.dart';
import '../plans/premium_provider.dart';
import 'viewer_theme.dart';

class EatsScreen extends ConsumerWidget {
  const EatsScreen({super.key, required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(viewerPaletteProvider);
    final lang = ref.watch(appLangProvider);
    final table =
        ref.watch(unitCostTableProvider).valueOrNull ?? UnitCostTable.defaults();
    return Theme(
      data: palette.toThemeData(),
      child: ViewerPaletteScope(
        palette: palette,
        child: _EatsView(
          palette: palette,
          lang: lang,
          trip: trip,
          table: table,
        ),
      ),
    );
  }
}

class _EatsView extends StatelessWidget {
  const _EatsView({
    required this.palette,
    required this.lang,
    required this.trip,
    required this.table,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final Trip trip;
  final UnitCostTable table;

  @override
  Widget build(BuildContext context) {
    const sections = _sections;
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          const LText('Rotori Eats', 'Rotori Eats').of(lang),
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        backgroundColor: palette.card,
        foregroundColor: palette.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Text(
            const LText(
              'Damak tadına ve hassasiyetine göre restoranlar; pratik ve '
              'bütçeli yemek için ipuçları. Fiyatlar yaklaşıktır.',
              'Restaurants for your taste and sensitivities, plus tips for '
              'practical, budget-friendly eating. Prices are approximate.',
            ).of(lang),
            style: TextStyle(color: palette.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 16),
          _EatsSection(palette: palette, lang: lang),
          const SizedBox(height: 16),
          _BudgetQuickCard(palette: palette, lang: lang, table: table),
          const SizedBox(height: 16),
          _DietaryCard(trip: trip, palette: palette, lang: lang),
          const SizedBox(height: 16),
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _GuideSectionCard(
              section: sections[i],
              palette: palette,
              lang: lang,
              accent: _accentFor(i, palette),
            ),
          ],
        ],
      ),
    );
  }

  static const _sections = <_GuideSection>[
    _GuideSection(
      emoji: '🍜',
      title: LText('Ne Yenir?', 'What to Eat?'),
      tips: [
        LText(
          'Öğle için ramen/udon/soba, akşam için donburi veya set menü güvenli başlangıçtır.',
          'For lunch, ramen/udon/soba; for dinner, donburi or a set menu is a safe start.',
        ),
        LText(
          'Konbini (7‑Eleven/Lawson/FamilyMart) hızlı ve ekonomik: onigiri + sandviç + içecek kombinasyonu iş görür.',
          'Konbini (7‑Eleven/Lawson/FamilyMart) is fast and affordable: onigiri + sandwich + drink works well.',
        ),
        LText(
          'Yoğun gezi günlerinde 12:00–13:30 arası kuyruk uzar; 11:30 veya 13:45 sonrası daha rahattır.',
          'Queues are longer around 12:00–13:30 on busy days; 11:30 or after 13:45 is usually easier.',
        ),
      ],
    ),
    _GuideSection(
      emoji: '🧒',
      title: LText('Aile ve Çocuk Dostu Plan', 'Family & Kid-Friendly Plan'),
      tips: [
        LText(
          'Çocukla en az bir öğünü konbini/food court tutmak tempoyu ve bütçeyi dengeler.',
          'With kids, making at least one meal konbini/food-court keeps pace and budget balanced.',
        ),
        LText(
          'Baharat hassasiyeti için siparişte “karakute nai” (acı olmasın) notunu kullan.',
          'For spice sensitivity, use “karakute nai” (not spicy) when ordering.',
        ),
        LText(
          'Yüksek yürüyüş gününde küçük atıştırmalık (onigiri, protein bar) taşı; öğün gecikmelerini kurtarır.',
          'Carry small snacks (onigiri, protein bar) on high-walking days; it helps when meals are delayed.',
        ),
      ],
    ),
    _GuideSection(
      emoji: '🕌',
      title: LText('Helal / Vejetaryen İpuçları', 'Halal / Vegetarian Tips'),
      tips: [
        LText(
          'Domuz türevi (pork extract, lard) için içerik sorgula; ramen bazlarında sık geçer.',
          'Ask about pork derivatives (pork extract, lard); they are common in ramen bases.',
        ),
        LText(
          'Balık sosu/dashi, vejetaryen yemeklerde gizli olabilir; “dashi nashi” sorusu kritik.',
          'Fish stock/dashi can be hidden in vegetarian dishes; asking “dashi nashi” is crucial.',
        ),
        LText(
          'İlk günlerde zincir ve etiketli ürünler daha güvenli; sonrasında yerel keşfi artır.',
          'On the first days, chains and clearly labeled products are safer; expand to local spots later.',
        ),
      ],
    ),
    _GuideSection(
      emoji: '🙏',
      title: LText('Sipariş ve Restoran Adabı', 'Ordering & Etiquette'),
      tips: [
        LText(
          'Yürürken yemek yerine dükkan önü/tezgah kenarında bitirmek daha uygundur.',
          'Instead of eating while walking, finishing near the shop counter is more appropriate.',
        ),
        LText(
          'Birçok restoranda su ücretsiz gelir; ekstra içecek siparişi zorunlu değildir.',
          'Many restaurants provide free water; ordering extra drinks is usually not required.',
        ),
        LText(
          'Bahşiş bırakılmaz; hesabı kasada ödersin. Kart geçmiyorsa nakit hazır tut.',
          'No tipping; you typically pay at the cashier. Keep cash ready if cards are not accepted.',
        ),
      ],
    ),
  ];
}

Color _accentFor(int index, ViewerPalette palette) {
  switch (index % 5) {
    case 0:
      return palette.sakura;
    case 1:
      return palette.matcha;
    case 2:
      return palette.gold;
    case 3:
      return palette.sky;
    default:
      return palette.accent;
  }
}

class _BudgetQuickCard extends StatelessWidget {
  const _BudgetQuickCard({
    required this.palette,
    required this.lang,
    required this.table,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final UnitCostTable table;

  @override
  Widget build(BuildContext context) {
    final refByKey = {for (final item in table.references) item.key: item.jpy};
    final ramen = refByKey['ramen'] ?? 1100;
    final konbini = refByKey['konbini_meal'] ?? 700;
    final sushi = refByKey['sushi_set'] ?? 2500;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            const LText('Hızlı Bütçe Rehberi', 'Quick Budget Guide').of(lang),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _priceRow('🍜 Ramen', ramen, palette),
          _priceRow('🏪 Konbini öğün', konbini, palette),
          _priceRow('🍣 Suşi seti', sushi, palette),
          const SizedBox(height: 8),
          Text(
            const LText(
              'Yetişkin günlük yemek bandı: yaklaşık ¥3.500 – ¥9.000',
              'Adult daily food band: around ¥3,500 – ¥9,000',
            ).of(lang),
            style: TextStyle(color: palette.textSecondary, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _priceRow(String label, int jpy, ViewerPalette p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: p.textSecondary, fontSize: 13),
            ),
          ),
          Text(
            formatJpy(jpy),
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rotori Eats — küratörlü restoran listesi. Free katman: helal/vejetaryen
/// filtresi + ilk [kEatsFreeLimit] sonuç. Kalanı premium (ayrı çalışma) ile
/// açılacak; şimdilik "yakında" teaser'ı gösterilir.
class _EatsSection extends ConsumerStatefulWidget {
  const _EatsSection({required this.palette, required this.lang});

  final ViewerPalette palette;
  final AppLang lang;

  @override
  ConsumerState<_EatsSection> createState() => _EatsSectionState();
}

class _EatsSectionState extends ConsumerState<_EatsSection> {
  EatsFilter _filter = EatsFilter.halal;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final lang = widget.lang;
    // Premium açıksa liste kısıtlanmaz — tek kaynak: premiumProvider.
    final premium = ref.watch(premiumProvider);
    final all = filterEats(kEatsPlaces, _filter);
    final shown = premium ? all : all.take(kEatsFreeLimit).toList();
    final locked = all.length - shown.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🍽️', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  const LText('Restoranlar', 'Restaurants').of(lang),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            const LText(
              'Damak tadına ve hassasiyetine göre seçilmiş mekanlar.',
              'Places picked for your taste and sensitivities.',
            ).of(lang),
            style: TextStyle(color: palette.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in _filterOptions)
                _EatsFilterChip(
                  label: option.label.of(lang),
                  active: _filter == option.filter,
                  palette: palette,
                  onTap: () => setState(() => _filter = option.filter),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            Text(
              const LText(
                'Bu filtreye uygun mekan bulunamadı.',
                'No place matches this filter.',
              ).of(lang),
              style: TextStyle(color: palette.textSecondary, fontSize: 12.5),
            )
          else
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _EatsCard(place: shown[i], palette: palette, lang: lang),
            ],
          if (locked > 0) ...[
            const SizedBox(height: 8),
            _EatsLockedCard(count: locked, palette: palette, lang: lang),
          ],
        ],
      ),
    );
  }

  static const _filterOptions = <({EatsFilter filter, LText label})>[
    (filter: EatsFilter.halal, label: LText('🕌 Helal', '🕌 Halal')),
    (filter: EatsFilter.vegetarian, label: LText('🥗 Vejetaryen', '🥗 Vegetarian')),
    (filter: EatsFilter.all, label: LText('Hepsi', 'All')),
  ];
}

class _EatsFilterChip extends StatelessWidget {
  const _EatsFilterChip({
    required this.label,
    required this.active,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool active;
  final ViewerPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? palette.accent.withValues(alpha: 0.16) : palette.elevated,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? palette.accent : palette.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? palette.textPrimary : palette.textSecondary,
              fontSize: 12.5,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _EatsCard extends StatelessWidget {
  const _EatsCard({
    required this.place,
    required this.palette,
    required this.lang,
  });

  final EatsPlace place;
  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.elevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(place.categoryEmoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${place.category.of(lang)} · ${place.city} · ${place.area}',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  Icon(Icons.star_rounded, size: 15, color: palette.gold),
                  const SizedBox(width: 2),
                  Text(
                    place.rating.toStringAsFixed(1),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            place.description.of(lang),
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (place.halal)
                _EatsBadge(
                  text: const LText('🕌 Helal', '🕌 Halal').of(lang),
                  palette: palette,
                ),
              if (place.halal) const SizedBox(width: 6),
              if (place.vegetarianFriendly)
                _EatsBadge(
                  text: const LText('🥗 Vejetaryen', '🥗 Vegetarian').of(lang),
                  palette: palette,
                ),
              const Spacer(),
              Text(
                place.priceBand,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => openGoogleMapsSearch(place.mapsQuery),
              icon: const Icon(Icons.map_outlined, size: 16),
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.textPrimary,
                side: BorderSide(color: palette.border),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              label: Text(
                const LText('Haritada aç', 'Open in Maps').of(lang),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EatsBadge extends StatelessWidget {
  const _EatsBadge({required this.text, required this.palette});

  final String text;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: palette.matcha.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Free limitin ötesindeki sonuçlar için "yakında" teaser'ı. Premium gate
/// ayrı bir çalışmada bağlanacak (bkz. monetizasyon tartışması).
class _EatsLockedCard extends StatelessWidget {
  const _EatsLockedCard({
    required this.count,
    required this.palette,
    required this.lang,
  });

  final int count;
  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: palette.border,
          style: BorderStyle.solid,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 18, color: palette.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              LText(
                'Bu filtrede $count restoran daha var · yakında',
                '$count more restaurants in this filter · coming soon',
              ).of(lang),
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DietaryCard extends StatelessWidget {
  const _DietaryCard({
    required this.trip,
    required this.palette,
    required this.lang,
  });

  final Trip trip;
  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final tagSet = trip.preferences.dietaryTags.toSet();
    final options = dietaryForCountry('JP')
        .where((option) => tagSet.contains(option.id))
        .toList(growable: false);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            const LText('Aktif Beslenme Tercihlerin', 'Your Active Dietary Preferences')
                .of(lang),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (options.isEmpty)
            Text(
              const LText(
                'Özel bir beslenme tercihi seçili değil — liste tüm '
                'mekanları gösteriyor. Yukarıdaki helal / vejetaryen '
                'filtresiyle daraltabilirsin.',
                'No dietary preference is set — the list shows every place. '
                'Use the halal / vegetarian filter above to narrow it down.',
              ).of(lang),
              style: TextStyle(color: palette.textSecondary, fontSize: 12.5),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in options)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: palette.elevated,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: palette.border),
                    ),
                    child: Text(
                      '${option.emoji} ${s.s(option.label)}',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _GuideSection {
  const _GuideSection({
    required this.emoji,
    required this.title,
    required this.tips,
  });

  final String emoji;
  final LText title;
  final List<LText> tips;
}

class _GuideSectionCard extends StatelessWidget {
  const _GuideSectionCard({
    required this.section,
    required this.palette,
    required this.lang,
    required this.accent,
  });

  final _GuideSection section;
  final ViewerPalette palette;
  final AppLang lang;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(section.emoji, style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.title.of(lang),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final tip in section.tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: accent, fontSize: 16)),
                  Expanded(
                    child: Text(
                      tip.of(lang),
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
