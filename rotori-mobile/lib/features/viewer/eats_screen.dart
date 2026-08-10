// Rotori Eats — Japon yemekleri rehberi.
//
// ## Neden restoran listesi değil
//
// Önceki sürüm 27 küratörlü restorandan oluşuyordu: adres, puan, helal
// sertifikası. Üç sorunu vardı. (1) Veri bayatlıyordu — mekan kapanır, fiyat
// kayar, sertifika iptal olur. (2) Doğrulanabilir değildi; canlı bir kaynağa
// bağlanmak ise Google Places şartlarınca yasak (içerik cache'lenemez) ve
// uygulamanın çevrimdışı çalışma gereğiyle çelişiyordu. (3) 27 kayıt ürün
// değildi.
//
// Yemek bilgisi bu üç sorunun hiçbirini taşımıyor: tonkotsu rameninin domuz
// suyu bazlı olduğu değişmez, dashi'nin balık suyu olduğu değişmez, sesli
// erişte çekmenin ayıp olmadığı değişmez.
//
// Ve daha faydalı: **neyi yiyebileceğini bilen gezgin her yerde yiyebilir.**
// Helal bir kullanıcıya 27 mekan adı vermek onu o 27 mekana hapsediyordu;
// "ramen bazları genelde domuzdur ama tori paitan tavuktur, şunu sormalısın"
// demek Japonya'nın tamamını açıyor.
//
// Ekran tamamen ÜCRETSİZ. Diyet bilgisi bir paywall'ın arkasına konmaz.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/language_store.dart';
import '../../data/plans_repository.dart';
import '../../domain/dietary.dart';
import '../../domain/japanese_dishes.dart';
import '../../domain/japanese_dishes_data.dart';
import '../../domain/localized_text.dart';
import '../../domain/types.dart';
import 'viewer_theme.dart';
import 'widgets/eats_preferences_sheet.dart';

class EatsScreen extends ConsumerStatefulWidget {
  const EatsScreen({super.key, required this.trip});

  final Trip trip;

  @override
  ConsumerState<EatsScreen> createState() => _EatsScreenState();
}

class _EatsScreenState extends ConsumerState<EatsScreen> {
  DishCategory? _category;
  String _search = '';

  /// Açıkken diyetine uymayan yemekler listeden çıkar. Varsayılan KAPALI:
  /// "yiyemediğini bilmek" de bir bilgi — okonomiyaki'nin neden uygun
  /// olmadığını görmek, listede hiç görmemekten iyidir.
  bool _onlyEdible = false;

  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Set<String> get _diet => widget.trip.preferences.dietaryTags.toSet();

  List<JapaneseDish> get _results {
    final needle = _search.trim().toLowerCase();
    final diet = _diet;
    return kJapaneseDishes.where((d) {
      if (_category != null && d.category != _category) return false;
      if (needle.isNotEmpty) {
        final hay = [
          d.name,
          d.nameJa,
          d.romaji,
          d.summary.tr,
          d.summary.en,
          ...d.variants.map((v) => v.name),
        ].join(' ').toLowerCase();
        if (!hay.contains(needle)) return false;
      }
      if (_onlyEdible && diet.isNotEmpty) {
        final a = assessDish(d, diet: diet);
        if (a.verdict == DishVerdict.avoid) {
          // Uygun bir alt türü varsa yemek yine de listede kalsın.
          return safeVariantFor(d, diet) != null;
        }
      }
      return true;
    }).toList(growable: false);
  }

  Future<void> _openPreferences(ViewerPalette palette, AppLang lang) async {
    final prefs = widget.trip.preferences;
    final result = await showEatsPreferencesSheet(
      context: context,
      palette: palette,
      lang: lang,
      initialTags: prefs.dietaryTags,
      initialBudgetJpy: prefs.mealBudgetJpyPerPerson,
    );
    if (result == null || !mounted) return;

    setState(() {
      prefs
        ..dietaryTags = result.dietaryTags
        ..mealBudgetJpyPerPerson = result.mealBudgetJpy;
    });

    // Kalıcılaştırma en iyi çabadır ve asla seçimi geri almaz. Provider'ın
    // kendisi Supabase'e uzandığı için (önizlemede başlatılmamış olabilir)
    // okuma da yazma da aynı try içinde.
    try {
      await ref.read(plansRepositoryProvider)?.save(widget.trip);
    } catch (_) {
      // Oturum içi seçim geçerli kalır.
    }
  }

  Future<void> _openDish(
    ViewerPalette palette,
    AppLang lang,
    JapaneseDish dish,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ViewerPaletteScope(
        palette: palette,
        child: _DishDetailSheet(
          dish: dish,
          diet: _diet,
          palette: palette,
          lang: lang,
          onEditDiet: () => _openPreferences(palette, lang),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(viewerPaletteProvider);
    final lang = ref.watch(appLangProvider);
    final diet = _diet;
    final results = _results;

    return Theme(
      data: palette.toThemeData(),
      child: ViewerPaletteScope(
        palette: palette,
        child: Scaffold(
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
          body: Column(
            children: [
              _SearchBar(
                palette: palette,
                lang: lang,
                controller: _searchController,
                onChanged: (v) => setState(() => _search = v),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  children: [
                    _DietBanner(
                      palette: palette,
                      lang: lang,
                      diet: diet,
                      onTap: () => _openPreferences(palette, lang),
                    ),
                    const SizedBox(height: 14),
                    _CategoryRow(
                      palette: palette,
                      lang: lang,
                      selected: _category,
                      onSelect: (c) => setState(() => _category = c),
                    ),
                    if (diet.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _EdibleToggle(
                        palette: palette,
                        lang: lang,
                        value: _onlyEdible,
                        onChanged: (v) => setState(() => _onlyEdible = v),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      lang == AppLang.tr
                          ? '${results.length} yemek'
                          : '${results.length} dishes',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (results.isEmpty)
                      _EmptyState(
                        palette: palette,
                        lang: lang,
                        onReset: () => setState(() {
                          _category = null;
                          _search = '';
                          _onlyEdible = false;
                          _searchController.clear();
                        }),
                      )
                    else
                      for (var i = 0; i < results.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _DishCard(
                          dish: results[i],
                          diet: diet,
                          palette: palette,
                          lang: lang,
                          onTap: () => _openDish(palette, lang, results[i]),
                        ),
                      ],
                    const SizedBox(height: 20),
                    _MenuWordsCard(palette: palette, lang: lang),
                    const SizedBox(height: 14),
                    _SourceNote(palette: palette, lang: lang),
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

// ---------------------------------------------------------------------------
// Üst çubuk ve filtreler
// ---------------------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.palette,
    required this.lang,
    required this.controller,
    required this.onChanged,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: p.card,
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: SizedBox(
        height: 42,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: TextStyle(color: p.textPrimary, fontSize: 13.5),
          decoration: InputDecoration(
            isDense: true,
            hintText: const LText(
              'Ramen, suşi, takoyaki…',
              'Ramen, sushi, takoyaki…',
            ).of(lang),
            hintStyle: TextStyle(color: p.textMuted, fontSize: 13),
            prefixIcon:
                Icon(Icons.search_rounded, size: 18, color: p.textSecondary),
            filled: true,
            fillColor: p.elevated,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide(color: p.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide(color: p.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide(color: p.accent),
            ),
          ),
        ),
      ),
    );
  }
}

/// Diyet durumu — girilmemişse çağrı, girilmişse özet.
class _DietBanner extends StatelessWidget {
  const _DietBanner({
    required this.palette,
    required this.lang,
    required this.diet,
    required this.onTap,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final Set<String> diet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = LanguageScope.of(context);
    final set = diet;
    final labels = dietaryForCountry('JP')
        .where((o) => set.contains(o.id))
        .map((o) => '${o.emoji} ${s.s(o.label)}')
        .toList(growable: false);
    final empty = labels.isEmpty;

    return Material(
      color: empty ? p.gold.withValues(alpha: 0.12) : p.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: empty ? p.gold.withValues(alpha: 0.45) : p.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                empty ? Icons.tune_rounded : Icons.verified_user_outlined,
                size: 19,
                color: empty ? p.gold : p.matcha,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      empty
                          ? const LText(
                              'Neyi yiyebilirsin?',
                              'What can you eat?',
                            ).of(lang)
                          : const LText(
                              'Sana göre işaretleniyor',
                              'Marked for your diet',
                            ).of(lang),
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      empty
                          ? const LText(
                              'Beslenme tercihini gir; her yemekte '
                                  '"yiyebilirsin / sor / uygun değil" rozetini '
                                  've gerekçesini göster.',
                              'Set your dietary needs and every dish gets a '
                                  '"safe / ask / avoid" badge with the reason.',
                            ).of(lang)
                          : labels.join(' · '),
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, size: 20, color: p.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.palette,
    required this.lang,
    required this.selected,
    required this.onSelect,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final DishCategory? selected;
  final ValueChanged<DishCategory?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(
          label: const LText('Hepsi', 'All').of(lang),
          active: selected == null,
          onTap: () => onSelect(null),
        ),
        for (final c in DishCategory.values)
          _chip(
            label: '${c.emoji} ${c.label.of(lang)}',
            active: selected == c,
            onTap: () => onSelect(c),
          ),
      ],
    );
  }

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

class _EdibleToggle extends StatelessWidget {
  const _EdibleToggle({
    required this.palette,
    required this.lang,
    required this.value,
    required this.onChanged,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Row(
      children: [
        Expanded(
          child: Text(
            const LText(
              'Sadece yiyebileceklerimi göster',
              'Show only what I can eat',
            ).of(lang),
            style: TextStyle(color: p.textSecondary, fontSize: 12.5),
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: p.accent,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Yemek kartı
// ---------------------------------------------------------------------------

class _DishCard extends StatelessWidget {
  const _DishCard({
    required this.dish,
    required this.diet,
    required this.palette,
    required this.lang,
    required this.onTap,
  });

  final JapaneseDish dish;
  final Set<String> diet;
  final ViewerPalette palette;
  final AppLang lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final a = assessDish(dish, diet: diet);
    final alt = a.verdict == DishVerdict.avoid
        ? safeVariantFor(dish, diet)
        : null;

    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dish.emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dish.name,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${dish.nameJa} · ${dish.romaji}',
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (a.verdict != DishVerdict.unknown)
                    _VerdictBadge(verdict: a.verdict, palette: p, lang: lang),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                dish.summary.of(lang),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
              if (alt != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: p.matcha.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    lang == AppLang.tr
                        ? '💡 Ama "${alt.name}" türünü yiyebilirsin'
                        : '💡 But you can have the "${alt.name}" version',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 9),
              // Kategori etiketi dar ekranda uzayabiliyor ("Pirinç kaseleri");
              // Flexible + ellipsis olmadan 390px'te satır taşıyor.
              Row(
                children: [
                  Text(
                    dish.priceBand,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${dish.category.emoji} ${dish.category.label.of(lang)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.textMuted, fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: p.textMuted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerdictBadge extends StatelessWidget {
  const _VerdictBadge({
    required this.verdict,
    required this.palette,
    required this.lang,
  });

  final DishVerdict verdict;
  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final tone = switch (verdict) {
      DishVerdict.safe => p.matcha,
      DishVerdict.ask => p.gold,
      DishVerdict.avoid => p.sunset,
      DishVerdict.unknown => p.textMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.45)),
      ),
      child: Text(
        '${verdict.emoji} ${verdict.label.of(lang)}',
        style: TextStyle(
          color: p.textPrimary,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.palette,
    required this.lang,
    required this.onReset,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          const Text('🍱', style: TextStyle(fontSize: 30)),
          const SizedBox(height: 8),
          Text(
            const LText('Bu filtreyle yemek yok.', 'No dish matches this filter.')
                .of(lang),
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onReset,
            style: OutlinedButton.styleFrom(
              foregroundColor: p.textPrimary,
              side: BorderSide(color: p.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              const LText('Filtreleri temizle', 'Clear filters').of(lang),
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Menüde tanınacak kelimeler
// ---------------------------------------------------------------------------

class _MenuWordsCard extends StatelessWidget {
  const _MenuWordsCard({required this.palette, required this.lang});

  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            const LText(
              'Menüde tanıman gereken kelimeler',
              'Words to recognise on a menu',
            ).of(lang),
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            const LText(
              'Bunları tanıyorsan Japonya\'nın her yerinde kendini '
                  'koruyabilirsin — hiçbir restoran listesi bu kadar '
                  'taşınabilir değil.',
              'Recognise these and you can look after yourself anywhere in '
                  'Japan — no restaurant list travels this well.',
            ).of(lang),
            style: TextStyle(color: p.textSecondary, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 12),
          for (final w in kMenuWordsToKnow)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      w.ja,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          w.meaning.of(lang),
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                        Text(
                          w.romaji,
                          style: TextStyle(color: p.textMuted, fontSize: 11),
                        ),
                      ],
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

class _SourceNote extends StatelessWidget {
  const _SourceNote({required this.palette, required this.lang});

  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    return Text(
      const LText(
        'Bu rehber yemekleri anlatır, mekan önermez — böylece bilgi '
            'bayatlamaz ve çevrimdışı çalışır. Malzemeler tipik tarife göredir; '
            'her mutfak farklıdır, hassasiyetin varsa sipariş öncesi sor.',
        'This guide explains dishes rather than recommending venues — so the '
            'information does not go stale and works offline. Ingredients '
            'reflect the typical recipe; every kitchen differs, so ask before '
            'ordering if you are sensitive.',
      ).of(lang),
      style: TextStyle(color: palette.textMuted, fontSize: 11, height: 1.4),
    );
  }
}

// ---------------------------------------------------------------------------
// Yemek detayı
// ---------------------------------------------------------------------------

class _DishDetailSheet extends StatefulWidget {
  const _DishDetailSheet({
    required this.dish,
    required this.diet,
    required this.palette,
    required this.lang,
    required this.onEditDiet,
  });

  final JapaneseDish dish;
  final Set<String> diet;
  final ViewerPalette palette;
  final AppLang lang;
  final Future<void> Function() onEditDiet;

  @override
  State<_DishDetailSheet> createState() => _DishDetailSheetState();
}

class _DishDetailSheetState extends State<_DishDetailSheet> {
  DishVariant? _variant;

  ViewerPalette get p => widget.palette;
  AppLang get lang => widget.lang;
  JapaneseDish get dish => widget.dish;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.92;
    final assessment =
        assessDish(dish, diet: widget.diet, variant: _variant);
    final ingredients = dish.effectiveIngredients(_variant);

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
              padding: const EdgeInsets.only(top: 10, bottom: 6),
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
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                children: [
                  _header(),
                  const SizedBox(height: 14),
                  _verdictCard(assessment),
                  if (dish.variants.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _variantPicker(),
                  ],
                  const SizedBox(height: 16),
                  _section(
                    const LText('Nedir', 'What it is'),
                    dish.summary.of(lang),
                  ),
                  const SizedBox(height: 16),
                  _ingredientsBlock(ingredients),
                  const SizedBox(height: 16),
                  _section(
                    const LText('Nasıl yenir', 'How to eat it'),
                    dish.howToEat.of(lang),
                  ),
                  if (dish.watchOut != null) ...[
                    const SizedBox(height: 16),
                    _warnBlock(dish.watchOut!.of(lang)),
                  ],
                  if (dish.orderTip != null) ...[
                    const SizedBox(height: 16),
                    _section(
                      const LText('Sipariş verirken', 'When ordering'),
                      dish.orderTip!.of(lang),
                    ),
                  ],
                  if (dish.whereToFind != null) ...[
                    const SizedBox(height: 16),
                    _section(
                      const LText('Nerede bulunur', 'Where to find it'),
                      dish.whereToFind!.of(lang),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _showRow(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(dish.emoji, style: const TextStyle(fontSize: 32)),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dish.name,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${dish.nameJa} · ${dish.romaji}',
                style: TextStyle(color: p.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 4),
              Text(
                '${dish.priceBand} · ${dish.category.emoji} ${dish.category.label.of(lang)}',
                style: TextStyle(color: p.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _verdictCard(DishAssessment a) {
    if (a.verdict == DishVerdict.unknown) {
      return Material(
        color: p.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () {
            Navigator.of(context).pop();
            widget.onEditDiet();
          },
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: p.gold.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, size: 18, color: p.gold),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    const LText(
                      'Beslenme tercihini gir, bu yemeği yiyip '
                          'yiyemeyeceğini söyleyeyim.',
                      'Set your dietary needs and I\'ll tell you whether you '
                          'can eat this.',
                    ).of(lang),
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 19, color: p.textMuted),
              ],
            ),
          ),
        ),
      );
    }

    final tone = switch (a.verdict) {
      DishVerdict.safe => p.matcha,
      DishVerdict.ask => p.gold,
      DishVerdict.avoid => p.sunset,
      DishVerdict.unknown => p.textMuted,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: tone.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${a.verdict.emoji} ${a.verdict.label.of(lang)}',
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          for (final r in a.reasons)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                r.of(lang),
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _variantPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          const LText('Türleri', 'Varieties').of(lang),
          style: TextStyle(
            color: p.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          const LText(
            'Tür seç — değerlendirme ona göre değişir.',
            'Pick a variety — the verdict updates for it.',
          ).of(lang),
          style: TextStyle(color: p.textMuted, fontSize: 11.5),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _variantChip(
              label: const LText('Genel', 'General').of(lang),
              active: _variant == null,
              onTap: () => setState(() => _variant = null),
            ),
            for (final v in dish.variants)
              _variantChip(
                label: v.name,
                active: _variant == v,
                onTap: () => setState(() => _variant = v),
              ),
          ],
        ),
        if (_variant != null) ...[
          const SizedBox(height: 9),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: p.elevated,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: p.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_variant!.name} · ${_variant!.nameJa}',
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _variant!.note.of(lang),
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _variantChip({
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

  Widget _ingredientsBlock(Map<DishIngredient, IngredientChance> ing) {
    if (ing.isEmpty) return const SizedBox.shrink();
    // "her zaman" önce, "bazen" sonra — kesin bilgi üstte dursun.
    final entries = ing.entries.toList()
      ..sort((a, b) => a.value.index.compareTo(b.value.index));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          const LText('İçinde ne var', 'What is in it').of(lang),
          style: TextStyle(
            color: p.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 9),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.key.emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${e.key.label.of(lang)} — ${e.value.label.of(lang)}',
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        e.key.japaneseLabel,
                        style: TextStyle(color: p.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _section(LText title, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.of(lang),
          style: TextStyle(
            color: p.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          body,
          style: TextStyle(color: p.textSecondary, fontSize: 13, height: 1.45),
        ),
      ],
    );
  }

  Widget _warnBlock(String body) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.sunset.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.sunset.withValues(alpha: 0.38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  const LText('Dikkat', 'Watch out').of(lang),
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Japonca adı personele göstermek/kopyalamak için.
  Widget _showRow() {
    return Material(
      color: p.elevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Clipboard.setData(ClipboardData(text: dish.nameJa));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(const LText('Kopyalandı', 'Copied').of(lang)),
              duration: const Duration(seconds: 1),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dish.nameJa,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      const LText(
                        'Personele göstermek için dokun, kopyalansın',
                        'Tap to copy and show it to the staff',
                      ).of(lang),
                      style: TextStyle(color: p.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.copy_rounded, size: 16, color: p.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
