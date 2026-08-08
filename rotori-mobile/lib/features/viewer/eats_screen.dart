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
              'Damak tadına ve hassasiyetine göre restoranlar. '
              'Fiyatlar yaklaşıktır. Yemek kültürü ve pratik ipuçları için '
              '"Mutlaka Bilmeniz Gerekenler"e göz atın.',
              'Restaurants for your taste and sensitivities. '
              'Prices are approximate. For food culture and practical tips, '
              'check "Must-Know Before You Go".',
            ).of(lang),
            style: TextStyle(color: palette.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 16),
          _EatsSection(palette: palette, lang: lang),
          const SizedBox(height: 16),
          _BudgetQuickCard(palette: palette, lang: lang, table: table),
          const SizedBox(height: 16),
          _DietaryCard(trip: trip, palette: palette, lang: lang),
        ],
      ),
    );
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
class _EatsSection extends StatefulWidget {
  const _EatsSection({required this.palette, required this.lang});

  final ViewerPalette palette;
  final AppLang lang;

  @override
  State<_EatsSection> createState() => _EatsSectionState();
}

class _EatsSectionState extends State<_EatsSection> {
  EatsFilter _filter = EatsFilter.halal;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final lang = widget.lang;
    final all = filterEats(kEatsPlaces, _filter);
    final shown = all.take(kEatsFreeLimit).toList();
    final lockedForFilter = all.length - shown.length;
    final totalLocked =
      kEatsPlaces.length > kEatsFreeLimit ? kEatsPlaces.length - kEatsFreeLimit : 0;

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
              _EatsFreeBadge(palette: palette, lang: lang),
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
          const SizedBox(height: 10),
          _EatsPremiumCard(
            countForFilter: lockedForFilter > 0 ? lockedForFilter : null,
            totalLocked: totalLocked,
            palette: palette,
            lang: lang,
            onTap: () => _showEatsPaywall(context, palette, lang),
          ),
        ],
      ),
    );
  }

  void _showEatsPaywall(
    BuildContext context,
    ViewerPalette palette,
    AppLang lang,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ViewerPaletteScope(
        palette: palette,
        child: _EatsPaywallSheet(palette: palette, lang: lang),
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

/// Free katman etiketi — kullanıcı sınırın “ücretsiz” kısmını net görür.
class _EatsFreeBadge extends StatelessWidget {
  const _EatsFreeBadge({required this.palette, required this.lang});

  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: palette.matcha.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        const LText('Ücretsiz · ilk $kEatsFreeLimit', 'Free · first $kEatsFreeLimit')
            .of(lang),
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Rotori Eats premium rozet/ikonu — kart ve paywall'da tutarlı vitrin dili.
class _EatsPremiumLogo extends StatelessWidget {
  const _EatsPremiumLogo({required this.palette, this.size = 58});

  final ViewerPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  palette.accent,
                  palette.gold,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: palette.accent.withValues(alpha: 0.30),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
          ),
          Container(
            width: size * 0.74,
            height: size * 0.74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.92),
              border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.ramen_dining_rounded,
              size: size * 0.36,
              color: palette.accent,
            ),
          ),
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: size * 0.34,
              height: size * 0.34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.textPrimary,
                border: Border.all(color: palette.card, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.auto_awesome_rounded,
                size: size * 0.17,
                color: palette.gold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Free limitin ötesi için premium upsell kartı — değer önerileri + CTA.
/// Satın alma henüz bağlı değil; CTA paywall önizlemesini açar.
class _EatsPremiumCard extends StatelessWidget {
  const _EatsPremiumCard({
    required this.countForFilter,
    required this.totalLocked,
    required this.palette,
    required this.lang,
    required this.onTap,
  });

  final int? countForFilter;
  final int totalLocked;
  final ViewerPalette palette;
  final AppLang lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = palette.accent;
    final unlockedIntro = lang == AppLang.tr
        ? (countForFilter != null
            ? 'Bu filtrede $countForFilter restoran daha açılır.'
            : 'Tüm şehirlerde $totalLocked restoran daha açılır.')
        : (countForFilter != null
            ? '$countForFilter more restaurants unlock in this filter.'
            : '$totalLocked more restaurants unlock across cities.');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.18),
            palette.gold.withValues(alpha: 0.10),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EatsPremiumLogo(palette: palette),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      const LText('Rotori Eats Pass', 'Rotori Eats Pass').of(lang),
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      unlockedIntro,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _PremiumHintChip(
                text: const LText('📍 Yakınımdakiler', '📍 Near me').of(lang),
                palette: palette,
              ),
              _PremiumHintChip(
                text: const LText('🕒 Şu an açık', '🕒 Open now').of(lang),
                palette: palette,
              ),
              _PremiumHintChip(
                text: const LText('⭐ Rotori skoru', '⭐ Rotori score').of(lang),
                palette: palette,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            const LText(
              'Kısa tanıtım: premium ile filtrelenmiş listeyi genişletir, '
              'kararını hızlandırır ve plana tek dokunuşla ekleme açar.',
              'Quick intro: premium expands your filtered list, speeds up '
              'decisions, and unlocks one-tap add to plan.',
            ).of(lang),
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              icon: const Icon(Icons.lock_open_rounded, size: 17),
              label: Text(
                const LText('Hepsini aç', 'Unlock all').of(lang),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumHintChip extends StatelessWidget {
  const _PremiumHintChip({required this.text, required this.palette});

  final String text;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: palette.card.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Rotori Eats Pass paywall önizlemesi. Satın alma akışı henüz bağlı değil
/// (monetizasyon ayrı çalışma); değer + fiyat modeli gösterilir, birincil
/// aksiyon “yakında” durumundadır.
class _EatsPaywallSheet extends StatelessWidget {
  const _EatsPaywallSheet({required this.palette, required this.lang});

  final ViewerPalette palette;
  final AppLang lang;

  static const _benefits = <({String emoji, LText text})>[
    (emoji: '🔓', text: LText('Tüm restoran listesi (sınırsız)', 'Full restaurant list (unlimited)')),
    (emoji: '📍', text: LText('Yakınımdakiler — konuma göre sıralama', 'Near me — sorted by location')),
    (emoji: '🕒', text: LText('Şu an açık filtresi', 'Open-now filter')),
    (emoji: '⭐', text: LText('Rotori öneri skoru (diyet + bütçe)', 'Rotori recommendation score (diet + budget)')),
    (emoji: '🗓️', text: LText('Plana tek dokunuşla ekle', 'Add to your plan in one tap')),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(color: palette.border),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EatsPremiumLogo(palette: palette, size: 54),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        const LText('Rotori Eats Pass', 'Rotori Eats Pass').of(lang),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        const LText(
                          'Gezi boyunca tüm restoranlar ve “şimdi nereye gitmeliyim?”’in '
                          'cevabı — tek gezi için.',
                          'All restaurants during your trip and the answer to “where '
                          'should I eat now?” — for a single trip.',
                        ).of(lang),
                        style: TextStyle(color: palette.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              const LText('Premium ile açılanlar', 'What unlocks with premium').of(lang),
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            for (final b in _benefits)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.emoji, style: const TextStyle(fontSize: 15)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        b.text.of(lang),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 13.5,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.elevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          const LText('Trip Pass · gezi başına', 'Trip Pass · per trip').of(lang),
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          const LText('Abonelik yok — tek seferlik.', 'No subscription — one-time.').of(lang),
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      const LText('Yakında', 'Soon').of(lang),
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        const LText(
                          'Rotori Eats Pass çok yakında geliyor.',
                          'Rotori Eats Pass is coming very soon.',
                        ).of(lang),
                      ),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  const LText('Beni haberdar et', 'Notify me').of(lang),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  const LText('Kapat', 'Close').of(lang),
                  style: TextStyle(color: palette.textSecondary),
                ),
              ),
            ),
          ],
        ),
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
                'Plan adımında özel bir beslenme tercihi seçmedin. '
                'İstersen Plan > Yemek adımından ekleyebilirsin.',
                'No special dietary preference is selected in the plan. '
                'You can add one from Plan > Food step.',
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
