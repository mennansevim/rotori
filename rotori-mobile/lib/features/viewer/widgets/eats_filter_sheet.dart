// Rotori Eats — detaylı filtre popup'ı.
//
// Tasarım kararı: popup free kullanıcıya da AÇILIR. Premium eksenler kilit
// ikonuyla ve soluk gösterilir; dokununca paywall açılır. Kapalı bir buton
// göstermek yerine değeri göstermek dönüşümü artırır ve kullanıcıyı
// aptal yerine koymaz.
//
// Kilit sınırının tek kaynağı [kFreeFilterDims] / [kFreeSorts]'tur; burada
// ikinci bir liste tutulmaz.

import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/eats.dart';
import '../../../domain/eats_query.dart';
import '../../../domain/localized_text.dart';
import '../viewer_theme.dart';

/// Filtre popup'ını açar. Kullanıcı "Göster"e basarsa güncel sorguyu döner;
/// iptal/kapatmada null.
Future<EatsQuery?> showEatsFilterSheet({
  required BuildContext context,
  required ViewerPalette palette,
  required AppLang lang,
  required EatsQuery initial,
  required EatsContext eatsContext,
  required bool premium,
  required List<EatsPlace> places,
  required bool locationReady,
  required Future<void> Function() onUpsell,
}) {
  return showModalBottomSheet<EatsQuery>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ViewerPaletteScope(
      palette: palette,
      child: _EatsFilterSheet(
        palette: palette,
        lang: lang,
        initial: initial,
        eatsContext: eatsContext,
        premium: premium,
        places: places,
        locationReady: locationReady,
        onUpsell: onUpsell,
      ),
    ),
  );
}

class _EatsFilterSheet extends StatefulWidget {
  const _EatsFilterSheet({
    required this.palette,
    required this.lang,
    required this.initial,
    required this.eatsContext,
    required this.premium,
    required this.places,
    required this.locationReady,
    required this.onUpsell,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final EatsQuery initial;
  final EatsContext eatsContext;
  final bool premium;
  final List<EatsPlace> places;
  final bool locationReady;
  final Future<void> Function() onUpsell;

  @override
  State<_EatsFilterSheet> createState() => _EatsFilterSheetState();
}

class _EatsFilterSheetState extends State<_EatsFilterSheet> {
  late EatsQuery _draft = widget.initial;
  late final TextEditingController _search =
      TextEditingController(text: widget.initial.text);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  ViewerPalette get p => widget.palette;
  AppLang get lang => widget.lang;

  bool _unlocked(EatsFilterDim dim) =>
      widget.premium || kFreeFilterDims.contains(dim);

  int get _resultCount => runEatsQuery(
        widget.places,
        query: _draft,
        context: widget.eatsContext,
        tier: widget.premium ? EatsTier.premium : EatsTier.free,
      ).length;

  void _lockedTap() {
    Navigator.of(context).pop();
    widget.onUpsell();
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.92;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
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
              _handle(),
              _header(),
              Divider(height: 1, color: p.border),
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  children: [
                    _searchField(),
                    const SizedBox(height: 18),
                    _halalSection(),
                    const SizedBox(height: 18),
                    _veggieSection(),
                    const SizedBox(height: 18),
                    _citySection(),
                    const SizedBox(height: 18),
                    _distanceSection(),
                    const SizedBox(height: 18),
                    _slotSection(),
                    const SizedBox(height: 18),
                    _cuisineSection(),
                    const SizedBox(height: 18),
                    _priceSection(),
                    const SizedBox(height: 18),
                    _ratingSection(),
                    const SizedBox(height: 18),
                    _amenitySection(),
                    const SizedBox(height: 18),
                    _avoidSection(),
                    const SizedBox(height: 18),
                    _sortSection(),
                  ],
                ),
              ),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _handle() => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: p.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      );

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 10, 12),
      child: Row(
        children: [
          Icon(Icons.tune_rounded, size: 19, color: p.textPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              const LText('Detaylı filtre', 'Detailed filter').of(lang),
              style: TextStyle(
                color: p.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _draft = const EatsQuery();
                _search.clear();
              });
            },
            child: Text(
              const LText('Temizle', 'Reset').of(lang),
              style: TextStyle(color: p.textSecondary, fontSize: 13),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded, color: p.textSecondary, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _search,
      onChanged: (v) => setState(() => _draft = _draft.copyWith(text: v)),
      style: TextStyle(color: p.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: const LText(
          'İsim, semt veya yemek ara…',
          'Search name, area or dish…',
        ).of(lang),
        hintStyle: TextStyle(color: p.textMuted, fontSize: 13.5),
        prefixIcon: Icon(Icons.search_rounded, size: 19, color: p.textSecondary),
        filled: true,
        fillColor: p.elevated,
        contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.accent),
        ),
      ),
    );
  }

  // --- Bölümler ------------------------------------------------------------

  Widget _halalSection() => _section(
        dim: EatsFilterDim.halal,
        title: const LText('Helal güveni', 'Halal trust'),
        subtitle: const LText(
          'Japonya\'da "helal" tek bir şey değil — seviyeyi sen seç.',
          'In Japan "halal" is not one thing — pick the level you need.',
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(
              label: const LText('Fark etmez', 'Any').of(lang),
              active: _draft.minHalal == null,
              onTap: () => setState(() => _draft = _draft.copyWith(clearHalal: true)),
            ),
            for (final t in [
              HalalTrust.certified,
              HalalTrust.muslimFriendly,
              HalalTrust.porkFreeOption,
            ])
              _chip(
                label: '${t.emoji} ${t.label.of(lang)}'
                    '${t == HalalTrust.certified ? '' : '+'}',
                active: _draft.minHalal == t,
                onTap: () => setState(() => _draft = _draft.copyWith(minHalal: t)),
              ),
          ],
        ),
      );

  Widget _veggieSection() => _section(
        dim: EatsFilterDim.veggie,
        title: const LText('Vejetaryen / vegan', 'Vegetarian / vegan'),
        subtitle: const LText(
          'Japon çorbalarında balık suyu (dashi) gizlidir; seviyeyi yükselt.',
          'Fish stock (dashi) hides in Japanese broths; raise the level.',
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(
              label: const LText('Fark etmez', 'Any').of(lang),
              active: _draft.minVeggie == null,
              onTap: () => setState(() => _draft = _draft.copyWith(clearVeggie: true)),
            ),
            for (final v in [
              VeggieLevel.veganMenu,
              VeggieLevel.vegetarianMenu,
              VeggieLevel.veggieOption,
            ])
              _chip(
                label: '${v.emoji} ${v.label.of(lang)}',
                active: _draft.minVeggie == v,
                onTap: () => setState(() => _draft = _draft.copyWith(minVeggie: v)),
              ),
          ],
        ),
      );

  Widget _citySection() {
    const cities = ['Tokyo', 'Kyoto', 'Osaka'];
    return _section(
      dim: EatsFilterDim.city,
      title: const LText('Şehir', 'City'),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in cities)
            _chip(
              label: c,
              active: _draft.cities.contains(c),
              onTap: () => setState(() {
                final next = {..._draft.cities};
                next.contains(c) ? next.remove(c) : next.add(c);
                _draft = _draft.copyWith(cities: next);
              }),
            ),
        ],
      ),
    );
  }

  Widget _distanceSection() => _section(
        dim: EatsFilterDim.distance,
        title: const LText('Yakınımda', 'Near me'),
        subtitle: widget.locationReady
            ? const LText(
                'Konumundan uzaklığa göre daralt.',
                'Narrow down by distance from your location.',
              )
            : const LText(
                'Konum kapalı — açtığında mesafe filtresi çalışır.',
                'Location is off — turn it on to use the distance filter.',
              ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(
              label: const LText('Sınırsız', 'Any distance').of(lang),
              active: _draft.maxDistanceKm == null,
              onTap: () =>
                  setState(() => _draft = _draft.copyWith(clearDistance: true)),
            ),
            for (final km in [1.0, 3.0, 10.0])
              _chip(
                label: '≤ ${km.toStringAsFixed(0)} km',
                active: _draft.maxDistanceKm == km,
                onTap: () =>
                    setState(() => _draft = _draft.copyWith(maxDistanceKm: km)),
              ),
          ],
        ),
      );

  Widget _slotSection() => _section(
        dim: EatsFilterDim.slot,
        title: const LText('Servis saati', 'Service time'),
        subtitle: const LText(
          'Tahminidir — tam çalışma saatini haritadan teyit et.',
          'Estimated — confirm exact hours on the map listing.',
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(
              label: const LText('Fark etmez', 'Any').of(lang),
              active: _draft.slot == null,
              onTap: () => setState(() => _draft = _draft.copyWith(clearSlot: true)),
            ),
            for (final s in MealSlot.values)
              _chip(
                label: '${s.emoji} ${s.label.of(lang)}',
                active: _draft.slot == s,
                onTap: () => setState(() => _draft = _draft.copyWith(slot: s)),
              ),
          ],
        ),
      );

  Widget _cuisineSection() => _section(
        dim: EatsFilterDim.cuisine,
        title: const LText('Mutfak', 'Cuisine'),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in EatsCuisine.values)
              _chip(
                label: '${c.emoji} ${c.label.of(lang)}',
                active: _draft.cuisines.contains(c),
                onTap: () => setState(() {
                  final next = {..._draft.cuisines};
                  next.contains(c) ? next.remove(c) : next.add(c);
                  _draft = _draft.copyWith(cuisines: next);
                }),
              ),
          ],
        ),
      );

  Widget _priceSection() => _section(
        dim: EatsFilterDim.price,
        title: const LText('Kişi başı fiyat', 'Price per person'),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in PriceTier.values)
              _chip(
                label: '${t.symbol} · ${t.label.of(lang)}',
                active: _draft.priceTiers.contains(t),
                onTap: () => setState(() {
                  final next = {..._draft.priceTiers};
                  next.contains(t) ? next.remove(t) : next.add(t);
                  _draft = _draft.copyWith(priceTiers: next);
                }),
              ),
          ],
        ),
      );

  Widget _ratingSection() => _section(
        dim: EatsFilterDim.rating,
        title: const LText('En az puan', 'Minimum rating'),
        subtitle: const LText(
          'Google ölçeği. Japonya\'da Tabelog 3.5 zaten üst seviyedir; '
              'buradaki puanlar turist ölçeğidir.',
          'Google scale. In Japan a Tabelog 3.5 is already elite; these '
              'numbers follow the tourist scale.',
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in [0.0, 4.0, 4.3, 4.5])
              _chip(
                label: r == 0
                    ? const LText('Hepsi', 'All').of(lang)
                    : '⭐ ${r.toStringAsFixed(1)}+',
                active: _draft.minRating == r,
                onTap: () => setState(() => _draft = _draft.copyWith(minRating: r)),
              ),
          ],
        ),
      );

  Widget _amenitySection() {
    final positive =
        EatsAmenity.values.where((a) => !a.isCaution).toList(growable: false);
    return _section(
      dim: EatsFilterDim.amenities,
      title: const LText('Şart koştuklarım', 'Must have'),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final a in positive)
            _chip(
              label: '${a.emoji} ${a.label.of(lang)}',
              active: _draft.requiredAmenities.contains(a),
              onTap: () => setState(() {
                final next = {..._draft.requiredAmenities};
                next.contains(a) ? next.remove(a) : next.add(a);
                _draft = _draft.copyWith(requiredAmenities: next);
              }),
            ),
        ],
      ),
    );
  }

  Widget _avoidSection() {
    final caution =
        EatsAmenity.values.where((a) => a.isCaution).toList(growable: false);
    return _section(
      dim: EatsFilterDim.avoid,
      title: const LText('Kaçınmak istediklerim', 'Avoid'),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final a in caution)
            _chip(
              label: '${a.emoji} ${a.label.of(lang)}',
              active: _draft.avoidAmenities.contains(a),
              onTap: () => setState(() {
                final next = {..._draft.avoidAmenities};
                next.contains(a) ? next.remove(a) : next.add(a);
                _draft = _draft.copyWith(avoidAmenities: next);
              }),
            ),
        ],
      ),
    );
  }

  Widget _sortSection() {
    return _sectionShell(
      locked: false,
      title: const LText('Sıralama', 'Sort by'),
      subtitle: null,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in EatsSort.values)
            _chip(
              label: s.label.of(lang),
              active: _draft.sort == s,
              locked: !widget.premium && !s.isFree,
              onTap: () {
                if (!widget.premium && !s.isFree) {
                  _lockedTap();
                  return;
                }
                setState(() => _draft = _draft.copyWith(sort: s));
              },
            ),
        ],
      ),
    );
  }

  // --- Yardımcılar ---------------------------------------------------------

  Widget _section({
    required EatsFilterDim dim,
    required LText title,
    LText? subtitle,
    required Widget child,
  }) {
    return _sectionShell(
      locked: !_unlocked(dim),
      title: title,
      subtitle: subtitle,
      child: child,
    );
  }

  Widget _sectionShell({
    required bool locked,
    required LText title,
    LText? subtitle,
    required Widget child,
  }) {
    final head = Row(
      children: [
        Expanded(
          child: Text(
            title.of(lang),
            style: TextStyle(
              color: locked ? p.textSecondary : p.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (locked) _premiumTag(),
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        head,
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle.of(lang),
            style: TextStyle(color: p.textMuted, fontSize: 11.5, height: 1.35),
          ),
        ],
        const SizedBox(height: 10),
        child,
      ],
    );

    if (!locked) return body;
    return GestureDetector(
      onTap: _lockedTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: 0.45,
        child: IgnorePointer(child: body),
      ),
    );
  }

  Widget _premiumTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, size: 11, color: p.accent),
          const SizedBox(width: 4),
          Text(
            const LText('Pass', 'Pass').of(lang),
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool active,
    required VoidCallback onTap,
    bool locked = false,
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (locked) ...[
                Icon(Icons.lock_rounded, size: 11, color: p.textMuted),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: active ? p.textPrimary : p.textSecondary,
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer() {
    final count = _resultCount;
    final capped = !widget.premium && count > kEatsFreeVisibleLimit;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      decoration: BoxDecoration(
        color: p.card,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (capped)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                lang == AppLang.tr
                    ? '$count sonuçtan ilk $kEatsFreeVisibleLimit tanesi ücretsiz gösterilir.'
                    : 'Showing the first $kEatsFreeVisibleLimit of $count results on the free tier.',
                style: TextStyle(color: p.textMuted, fontSize: 11.5),
                textAlign: TextAlign.center,
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_draft),
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                count == 0
                    ? const LText('Sonuç yok', 'No results').of(lang)
                    : (lang == AppLang.tr
                        ? '$count sonucu göster'
                        : 'Show $count results'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
