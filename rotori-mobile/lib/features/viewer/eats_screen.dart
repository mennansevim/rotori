// Rotori Eats — restoran keşif ekranı.
//
// ## Rakip konumlandırması (neden bu ekran böyle)
//
// Halal Navi / Halal Gourmet Japan → helal aramayı çözer, bütçe ve plan yok.
// Tabelog                          → yerel kaliteyi çözer, diyet filtresi yok.
// Google Maps                      → konum/saati çözer, puanı turist enflasyonlu.
// HappyCow                         → diyeti çözer, Japonya pratiklerini bilmez.
//
// Hiçbiri kullanıcının PLANINI bilmiyor. Rotori biliyor: gezi tarihleri, öğün
// bütçesi, beslenme etiketleri ve (izin verilirse) anlık konum. Bu ekranın tüm
// tasarımı tek bir soruyu cevaplamak üzerine kurulu:
//
//     "Şu an, buradayken, bütçemle, yiyebildiklerimden — nereye gideyim?"
//
// ## Katman kararı
//
//   ÜCRETSİZ  → katalog + diyet/şehir/arama filtresi + puana göre sıralama +
//               ilk [kEatsFreeVisibleLimit] sonuç + tüm güvenlik bilgisi
//               (helal seviyesi, nakit uyarısı, sipariş frazları, harita).
//   PASS      → sınırsız sonuç, Rotori Seçkisi kayıtları, "Şimdi ne yesem?",
//               yakınımda/rotama yakın, mutfak-fiyat-puan-olanak filtreleri,
//               Rotori uyum skoru ve bilenin ipuçları.
//
// Sınır bilinçli olarak "içerik" değil "karar zekası" üzerinden çekildi:
// birinin yiyemeyeceği bir şeyi yemesini engelleyen bilgi paywall'a konmaz.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/google_maps_launcher.dart';
import '../../data/language_store.dart';
import '../../data/plans_repository.dart';
import '../../data/unit_cost_table_store.dart';
import '../../domain/cost_estimate.dart';
import '../../domain/dietary.dart';
import '../../domain/eats.dart';
import '../../domain/eats_query.dart';
import '../../domain/geofence.dart' show LatLng;
import '../../domain/localized_text.dart';
import '../../domain/place_coords.dart';
import '../../domain/types.dart';
import '../plans/premium_provider.dart';
import 'budget_screen.dart';
import 'eats_location.dart';
import 'viewer_theme.dart';
import 'widgets/eats_detail_sheet.dart';
import 'widgets/eats_filter_sheet.dart';
import 'widgets/eats_preferences_sheet.dart';

class EatsScreen extends ConsumerStatefulWidget {
  const EatsScreen({super.key, required this.trip});

  final Trip trip;

  @override
  ConsumerState<EatsScreen> createState() => _EatsScreenState();
}

class _EatsScreenState extends ConsumerState<EatsScreen> {
  late EatsQuery _query = _seedQuery(widget.trip);

  /// "Yakınımda" açıldı mı? Açılana kadar konum provider'ı hiç okunmaz —
  /// kullanıcı istemeden izin diyaloğu çıkmaz.
  bool _nearMe = false;

  /// Konum yerine bugünkü rotanın merkezi kullanılsın mı?
  bool _nearRoute = false;

  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.text = _query.text;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Kullanıcının beslenme tercihlerinden akıllı başlangıç filtresi üretir.
  /// Helal seçmiş biri uygulamayı açtığında ilk ekranda helal listeyi görür —
  /// filtreyi elle kurmak zorunda kalmaz.
  static EatsQuery _seedQuery(Trip trip) {
    final tags = trip.preferences.dietaryTags.toSet();
    if (tags.contains('halal')) {
      return const EatsQuery(minHalal: HalalTrust.muslimFriendly);
    }
    if (tags.contains('vegan')) {
      return const EatsQuery(minVeggie: VeggieLevel.veganMenu);
    }
    if (tags.contains('vegetarian')) {
      return const EatsQuery(minVeggie: VeggieLevel.veggieOption);
    }
    if (tags.contains('no_pork')) {
      return const EatsQuery(minHalal: HalalTrust.porkFreeOption);
    }
    return const EatsQuery();
  }

  // --- Bağlam --------------------------------------------------------------

  /// Japonya yerel saati — "şu an hangi öğün" bunun üzerinden bulunur.
  static DateTime _japanNow() =>
      DateTime.now().toUtc().add(const Duration(hours: 9));

  /// Bugünkü planın durak merkezi (konum izni yokken makul bir başlangıç).
  LatLng? _routeCentroid() {
    final today = _japanNow();
    final iso = '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    DayPlan? day;
    for (final d in widget.trip.days) {
      if (d.date == iso) {
        day = d;
        break;
      }
    }
    day ??= widget.trip.days.isNotEmpty ? widget.trip.days.first : null;
    if (day == null) return null;

    final stops = resolveDayStops(day);
    if (stops.isEmpty) return null;
    var lat = 0.0, lng = 0.0;
    for (final s in stops) {
      lat += s.lat;
      lng += s.lng;
    }
    return LatLng(lat / stops.length, lng / stops.length);
  }

  EatsContext _buildContext(LatLng? origin) {
    final prefs = widget.trip.preferences;
    return EatsContext(
      origin: origin,
      dietTags: prefs.dietaryTags.toSet(),
      mealBudgetJpy: prefs.mealBudgetJpyPerPerson,
      nowSlot: MealSlotX.forHour(_japanNow().hour),
      partyHasKids: (prefs.childrenCount ?? 0) > 0,
    );
  }

  // --- Aksiyonlar ----------------------------------------------------------

  Future<void> _openFilters(
    ViewerPalette palette,
    AppLang lang,
    EatsContext ctx,
    bool premium,
  ) async {
    final next = await showEatsFilterSheet(
      context: context,
      palette: palette,
      lang: lang,
      initial: _query,
      eatsContext: ctx,
      premium: premium,
      places: kEatsPlaces,
      locationReady: ctx.origin != null,
      onUpsell: () => _openPaywall(palette, lang),
    );
    if (next != null && mounted) {
      setState(() {
        _query = next;
        _searchController.text = next.text;
      });
    }
  }

  Future<void> _openPaywall(ViewerPalette palette, AppLang lang) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ViewerPaletteScope(
        palette: palette,
        child: _EatsPaywallSheet(palette: palette, lang: lang),
      ),
    );
  }

  Future<void> _openDetail(
    ViewerPalette palette,
    AppLang lang,
    EatsResult result,
    EatsContext ctx,
    bool premium,
  ) {
    return showEatsDetailSheet(
      context: context,
      palette: palette,
      lang: lang,
      result: result,
      eatsContext: ctx,
      premium: premium,
      onUpsell: () => _openPaywall(palette, lang),
      onEditPreferences: () => _openPreferences(palette, lang),
    );
  }

  /// Beslenme tercihi + öğün bütçesi toplama. Sonuç doğrudan
  /// `trip.preferences`'a yazılır ve kalıcılaştırılır; skor bir sonraki
  /// karede gerçek girdilerle hesaplanır.
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
      // Yeni diyet tercihi filtreyi de tazelesin — kullanıcı helal seçtiyse
      // listenin hemen helale daralmasını bekler.
      _query = _seedQuery(widget.trip).copyWith(text: _query.text);
    });

    // Kalıcılaştırma en iyi çabadır ve ASLA seçimi geri almaz.
    //
    // plansRepositoryProvider'ın kendisi Supabase'e uzanır; önizlemede ve
    // testlerde `Supabase.instance` başlatılmadığı için provider okuması bile
    // fırlatabiliyor. Bu yüzden okuma da yazma da aynı try içinde.
    try {
      await ref.read(plansRepositoryProvider)?.save(widget.trip);
    } catch (_) {
      // Kalıcı yazılamasa da oturum içi seçim geçerli kalır; save() içindeki
      // saveLocal zaten denendiyse sunucu push'u syncDirty ile telafi edilir.
    }
  }

  Future<void> _openNowPicks(
    ViewerPalette palette,
    AppLang lang,
    EatsContext ctx,
  ) {
    final picks = pickEatsNow(kEatsPlaces, context: ctx, base: _query);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ViewerPaletteScope(
        palette: palette,
        child: _NowPicksSheet(
          palette: palette,
          lang: lang,
          picks: picks,
          slot: ctx.nowSlot ?? MealSlot.lunch,
          onPick: (r) {
            Navigator.of(sheetContext).pop();
            _openDetail(palette, lang, r, ctx, true);
          },
        ),
      ),
    );
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(viewerPaletteProvider);
    final lang = ref.watch(appLangProvider);
    final premium = ref.watch(premiumProvider);
    final table =
        ref.watch(unitCostTableProvider).valueOrNull ?? UnitCostTable.defaults();

    // Konum yalnızca kullanıcı "Yakınımda"yı açtığında istenir.
    LatLng? origin;
    var locationPending = false;
    var locationDenied = false;
    if (_nearMe && premium) {
      final async = ref.watch(eatsOriginProvider);
      locationPending = async.isLoading;
      final value = async.valueOrNull;
      if (value != null) {
        origin = value.point;
        locationDenied = value.state != EatsLocationState.ok;
      }
    } else if (_nearRoute && premium) {
      origin = _routeCentroid();
    }

    final ctx = _buildContext(origin);
    final tier = premium ? EatsTier.premium : EatsTier.free;
    final all = runEatsQuery(
      kEatsPlaces,
      query: _query,
      context: ctx,
      tier: tier,
    );
    final visible =
        premium ? all : all.take(kEatsFreeVisibleLimit).toList(growable: false);
    final hiddenByTier = all.length - visible.length;
    final curatedLocked =
        premium ? 0 : kEatsPlaces.where((p) => p.premiumOnly).length;

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
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: _TierBadge(
                    palette: palette,
                    lang: lang,
                    premium: premium,
                    onTap: premium ? null : () => _openPaywall(palette, lang),
                  ),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              _SearchBar(
                palette: palette,
                lang: lang,
                controller: _searchController,
                activeCount: _query.activeCount,
                onChanged: (v) =>
                    setState(() => _query = _query.copyWith(text: v)),
                onFilter: () => _openFilters(palette, lang, ctx, premium),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  children: [
                    _NowCard(
                      palette: palette,
                      lang: lang,
                      premium: premium,
                      slot: ctx.nowSlot ?? MealSlot.lunch,
                      onTap: premium
                          ? () => _openNowPicks(palette, lang, ctx)
                          : () => _openPaywall(palette, lang),
                    ),
                    // Diyet/bütçe hiç girilmemişse skorlar kişiselleştirilemez.
                    // Bunu sessizce nötr puanla kapatmak yerine söylüyoruz.
                    if (ctx.dietTags.isEmpty || (ctx.mealBudgetJpy ?? 0) <= 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _PersonalizePrompt(
                          palette: palette,
                          lang: lang,
                          missingDiet: ctx.dietTags.isEmpty,
                          missingBudget: (ctx.mealBudgetJpy ?? 0) <= 0,
                          onTap: () => _openPreferences(palette, lang),
                        ),
                      ),
                    const SizedBox(height: 12),
                    _ProximityRow(
                      palette: palette,
                      lang: lang,
                      premium: premium,
                      nearMe: _nearMe,
                      nearRoute: _nearRoute,
                      pending: locationPending,
                      denied: locationDenied,
                      onNearMe: () {
                        if (!premium) {
                          _openPaywall(palette, lang);
                          return;
                        }
                        setState(() {
                          _nearMe = !_nearMe;
                          if (_nearMe) _nearRoute = false;
                        });
                      },
                      onNearRoute: () {
                        if (!premium) {
                          _openPaywall(palette, lang);
                          return;
                        }
                        setState(() {
                          _nearRoute = !_nearRoute;
                          if (_nearRoute) _nearMe = false;
                        });
                      },
                    ),
                    if (_query.activeCount > 0) ...[
                      const SizedBox(height: 12),
                      _ActiveFilterRow(
                        palette: palette,
                        lang: lang,
                        query: _query,
                        onClear: () => setState(() {
                          _query = const EatsQuery();
                          _searchController.clear();
                        }),
                        onOpen: () => _openFilters(palette, lang, ctx, premium),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _ResultHeader(
                      palette: palette,
                      lang: lang,
                      total: all.length,
                      shown: visible.length,
                      sort: _query.sort,
                    ),
                    const SizedBox(height: 10),
                    if (visible.isEmpty)
                      _EmptyState(
                        palette: palette,
                        lang: lang,
                        onReset: () => setState(() {
                          _query = const EatsQuery();
                          _searchController.clear();
                        }),
                      )
                    else
                      for (var i = 0; i < visible.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _EatsResultCard(
                          result: visible[i],
                          palette: palette,
                          lang: lang,
                          premium: premium,
                          showScore: premium,
                          onTap: () => _openDetail(
                            palette,
                            lang,
                            visible[i],
                            ctx,
                            premium,
                          ),
                        ),
                      ],
                    if (!premium) ...[
                      const SizedBox(height: 14),
                      _EatsPremiumCard(
                        hiddenByTier: hiddenByTier,
                        curatedLocked: curatedLocked,
                        palette: palette,
                        lang: lang,
                        onTap: () => _openPaywall(palette, lang),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _BudgetQuickCard(
                      palette: palette,
                      lang: lang,
                      table: table,
                      mealBudget: widget.trip.preferences.mealBudgetJpyPerPerson,
                    ),
                    const SizedBox(height: 12),
                    _DietaryCard(
                      trip: widget.trip,
                      palette: palette,
                      lang: lang,
                      onEdit: () => _openPreferences(palette, lang),
                    ),
                    const SizedBox(height: 14),
                    _DataNote(palette: palette, lang: lang),
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
// Üst arama + filtre çubuğu
// ---------------------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.palette,
    required this.lang,
    required this.controller,
    required this.activeCount,
    required this.onChanged,
    required this.onFilter,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final TextEditingController controller;
  final int activeCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: p.card,
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: TextStyle(color: p.textPrimary, fontSize: 13.5),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: const LText(
                    'Ramen, Asakusa, vegan…',
                    'Ramen, Asakusa, vegan…',
                  ).of(lang),
                  hintStyle: TextStyle(color: p.textMuted, fontSize: 13),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: p.textSecondary,
                  ),
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
          ),
          const SizedBox(width: 8),
          Material(
            color: activeCount > 0 ? p.accent : p.elevated,
            borderRadius: BorderRadius.circular(11),
            child: InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: onFilter,
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: activeCount > 0 ? p.accent : p.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 17,
                      color: activeCount > 0 ? Colors.white : p.textPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      const LText('Filtre', 'Filter').of(lang),
                      style: TextStyle(
                        color: activeCount > 0 ? Colors.white : p.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (activeCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 18,
                        height: 18,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$activeCount',
                          style: TextStyle(
                            color: p.accent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "Şimdi ne yesem?" kartı — premium çekirdek
// ---------------------------------------------------------------------------

class _NowCard extends StatelessWidget {
  const _NowCard({
    required this.palette,
    required this.lang,
    required this.premium,
    required this.slot,
    required this.onTap,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final bool premium;
  final MealSlot slot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: p.brandGradient,
            ),
            boxShadow: [
              BoxShadow(
                color: p.accent.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Text(slot.emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            const LText(
                              'Şimdi ne yesem?',
                              'What should I eat now?',
                            ).of(lang),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!premium) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.lock_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      lang == AppLang.tr
                          ? 'Konumun, saatin (${slot.label.tr.toLowerCase()}), '
                              'bütçen ve diyetin birlikte — 3 net öneri.'
                          : 'Your location, the time (${slot.label.en.toLowerCase()}), '
                              'your budget and diet together — 3 clear picks.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 20,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Yakınlık satırı
// ---------------------------------------------------------------------------

class _ProximityRow extends StatelessWidget {
  const _ProximityRow({
    required this.palette,
    required this.lang,
    required this.premium,
    required this.nearMe,
    required this.nearRoute,
    required this.pending,
    required this.denied,
    required this.onNearMe,
    required this.onNearRoute,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final bool premium;
  final bool nearMe;
  final bool nearRoute;
  final bool pending;
  final bool denied;
  final VoidCallback onNearMe;
  final VoidCallback onNearRoute;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _toggle(
                emoji: '📍',
                label: const LText('Yakınımda', 'Near me').of(lang),
                active: nearMe,
                locked: !premium,
                busy: pending,
                onTap: onNearMe,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _toggle(
                emoji: '🗺️',
                label: const LText('Rotama yakın', 'Near my route').of(lang),
                active: nearRoute,
                locked: !premium,
                busy: false,
                onTap: onNearRoute,
              ),
            ),
          ],
        ),
        if (nearMe && denied)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              const LText(
                'Konum alınamadı — cihaz ayarlarından izni aç, sonra tekrar dene.',
                'Could not get your location — enable permission in settings and retry.',
              ).of(lang),
              style: TextStyle(color: p.sunset, fontSize: 11.5),
            ),
          ),
      ],
    );
  }

  Widget _toggle({
    required String emoji,
    required String label,
    required bool active,
    required bool locked,
    required bool busy,
    required VoidCallback onTap,
  }) {
    final p = palette;
    return Material(
      color: active ? p.accent.withValues(alpha: 0.16) : p.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? p.accent : p.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(p.accent),
                  ),
                )
              else
                Text(emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? p.textPrimary : p.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (locked) ...[
                const SizedBox(width: 5),
                Icon(Icons.lock_rounded, size: 12, color: p.textMuted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Aktif filtre özeti
// ---------------------------------------------------------------------------

class _ActiveFilterRow extends StatelessWidget {
  const _ActiveFilterRow({
    required this.palette,
    required this.lang,
    required this.query,
    required this.onClear,
    required this.onOpen,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final EatsQuery query;
  final VoidCallback onClear;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final labels = <String>[
      if (query.text.trim().isNotEmpty) '"${query.text.trim()}"',
      if (query.minHalal != null)
        '${query.minHalal!.emoji} ${query.minHalal!.label.of(lang)}',
      if (query.minVeggie != null)
        '${query.minVeggie!.emoji} ${query.minVeggie!.label.of(lang)}',
      ...query.cities,
      ...query.cuisines.map((c) => '${c.emoji} ${c.label.of(lang)}'),
      ...query.priceTiers.map((t) => t.symbol),
      if (query.minRating > 0) '⭐ ${query.minRating.toStringAsFixed(1)}+',
      if (query.slot != null)
        '${query.slot!.emoji} ${query.slot!.label.of(lang)}',
      if (query.maxDistanceKm != null)
        '≤ ${query.maxDistanceKm!.toStringAsFixed(0)} km',
      ...query.requiredAmenities.map((a) => '${a.emoji} ${a.label.of(lang)}'),
      ...query.avoidAmenities.map(
        (a) => '${lang == AppLang.tr ? "yok" : "no"}: ${a.label.of(lang)}',
      ),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final l in labels)
                GestureDetector(
                  onTap: onOpen,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: p.accent.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      l,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onClear,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              const LText('Temizle', 'Reset').of(lang),
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({
    required this.palette,
    required this.lang,
    required this.total,
    required this.shown,
    required this.sort,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final int total;
  final int shown;
  final EatsSort sort;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final text = shown < total
        ? (lang == AppLang.tr
            ? '$total sonuçtan $shown tanesi'
            : '$shown of $total results')
        : (lang == AppLang.tr ? '$total sonuç' : '$total results');
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Icon(Icons.sort_rounded, size: 14, color: p.textMuted),
        const SizedBox(width: 4),
        Text(
          sort.label.of(lang),
          style: TextStyle(color: p.textSecondary, fontSize: 12),
        ),
      ],
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
            const LText(
              'Bu kriterlere uyan mekan yok.',
              'No place matches these criteria.',
            ).of(lang),
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            const LText(
              'Bir iki filtreyi gevşetmeyi dene — özellikle mesafe ve fiyat.',
              'Try relaxing a filter or two — distance and price especially.',
            ).of(lang),
            style: TextStyle(color: p.textSecondary, fontSize: 12.5),
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
// Sonuç kartı
// ---------------------------------------------------------------------------

class _EatsResultCard extends StatelessWidget {
  const _EatsResultCard({
    required this.result,
    required this.palette,
    required this.lang,
    required this.premium,
    required this.showScore,
    required this.onTap,
  });

  final EatsResult result;
  final ViewerPalette palette;
  final AppLang lang;
  final bool premium;
  final bool showScore;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final place = result.place;
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
                  Text(place.categoryEmoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                place.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (place.premiumOnly) ...[
                              const SizedBox(width: 6),
                              _miniTag(
                                '✦ ${const LText('Seçki', 'Curated').of(lang)}',
                                p.gold,
                                p,
                              ),
                            ],
                          ],
                        ),
                        Text(
                          '${place.category.of(lang)} · ${place.city} · ${place.area}',
                          style: TextStyle(color: p.textSecondary, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.star_rounded, size: 15, color: p.gold),
                          const SizedBox(width: 2),
                          Text(
                            place.rating.toStringAsFixed(1),
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      if (showScore) ...[
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${result.score}',
                            style: TextStyle(
                              color: p.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (place.halal != HalalTrust.none)
                    _badge(
                      '${place.halal.emoji} ${place.halal.label.of(lang)}',
                      place.halal == HalalTrust.certified ? p.matcha : p.sky,
                      p,
                    ),
                  if (place.veggie != VeggieLevel.none)
                    _badge(
                      '${place.veggie.emoji} ${place.veggie.label.of(lang)}',
                      p.matcha,
                      p,
                    ),
                  for (final a in place.amenities.where((a) => a.isCaution))
                    _badge('${a.emoji} ${a.label.of(lang)}', p.sunset, p),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                '👉 ${place.signature.of(lang)}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Text(
                    place.priceBand,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    place.priceTier.symbol,
                    style: TextStyle(color: p.textMuted, fontSize: 11.5),
                  ),
                  if (result.distanceKm != null && premium) ...[
                    const SizedBox(width: 10),
                    Icon(
                      Icons.directions_walk_rounded,
                      size: 13,
                      color: p.textSecondary,
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        '${result.distanceKm!.toStringAsFixed(1)} km · '
                        '${result.walkMinutes} ${lang == AppLang.tr ? "dk" : "min"}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.textSecondary, fontSize: 11.5),
                      ),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => openGoogleMapsPoint(
                      lat: place.lat,
                      lng: place.lng,
                      label: place.name,
                    ),
                    icon: Icon(Icons.map_outlined, size: 18, color: p.accent),
                    tooltip: const LText('Haritada aç', 'Open in Maps').of(lang),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _badge(String text, Color tone, ViewerPalette p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.38)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: p.textPrimary,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static Widget _miniTag(String text, Color tone, ViewerPalette p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: p.textPrimary,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "Şimdi ne yesem?" sonuç sheet'i
// ---------------------------------------------------------------------------

class _NowPicksSheet extends StatelessWidget {
  const _NowPicksSheet({
    required this.palette,
    required this.lang,
    required this.picks,
    required this.slot,
    required this.onPick,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final List<EatsResult> picks;
  final MealSlot slot;
  final ValueChanged<EatsResult> onPick;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border.all(color: p.border),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: p.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '${slot.emoji} ${const LText('Şimdi buraya git', 'Go here now').of(lang)}',
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            const LText(
              'Diyetin, bütçen, saatin ve konumun birlikte değerlendirildi.',
              'Your diet, budget, time of day and location were weighed together.',
            ).of(lang),
            style: TextStyle(color: p.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          if (picks.isEmpty)
            Text(
              const LText(
                'Şu anki filtrelerle öneri çıkmadı — filtreleri gevşet.',
                'No pick with the current filters — try relaxing them.',
              ).of(lang),
              style: TextStyle(color: p.textSecondary, fontSize: 13),
            )
          else
            for (var i = 0; i < picks.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _pickRow(i + 1, picks[i]),
            ],
        ],
      ),
    );
  }

  Widget _pickRow(int rank, EatsResult r) {
    final p = palette;
    return Material(
      color: p.elevated,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => onPick(r),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: rank == 1 ? p.accent.withValues(alpha: 0.6) : p.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rank == 1 ? p.accent : p.border,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: rank == 1 ? Colors.white : p.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r.place.categoryEmoji} ${r.place.name}',
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${r.place.area} · ${r.place.priceBand}'
                      '${r.distanceKm != null ? ' · ${r.distanceKm!.toStringAsFixed(1)} km' : ''}',
                      style: TextStyle(color: p.textSecondary, fontSize: 11.5),
                    ),
                    if (r.reasons.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      for (final reason in r.reasons)
                        Text(
                          '· ${reason.of(lang)}',
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '${r.score}',
                  style: TextStyle(
                    color: p.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
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
// Katman rozeti + premium kart + paywall
// ---------------------------------------------------------------------------

class _TierBadge extends StatelessWidget {
  const _TierBadge({
    required this.palette,
    required this.lang,
    required this.premium,
    this.onTap,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final bool premium;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          gradient: premium ? LinearGradient(colors: [p.accent, p.gold]) : null,
          color: premium ? null : p.elevated,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: premium ? Colors.transparent : p.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              premium ? Icons.auto_awesome_rounded : Icons.lock_open_rounded,
              size: 12,
              color: premium ? Colors.white : p.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              premium
                  ? const LText('Pass aktif', 'Pass active').of(lang)
                  : const LText('Ücretsiz', 'Free').of(lang),
              style: TextStyle(
                color: premium ? Colors.white : p.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rotori Eats premium rozet/ikonu — kart ve paywall'da tutarlı vitrin dili.
class _EatsPremiumLogo extends StatelessWidget {
  const _EatsPremiumLogo({required this.palette});

  final ViewerPalette palette;

  static const double size = 54;

  @override
  Widget build(BuildContext context) {
    final p = palette;
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
                colors: [p.accent, p.gold],
              ),
              boxShadow: [
                BoxShadow(
                  color: p.accent.withValues(alpha: 0.30),
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
              color: p.accent,
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
                color: p.textPrimary,
                border: Border.all(color: p.card, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.auto_awesome_rounded,
                size: size * 0.17,
                color: p.gold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Free limitin ötesi için premium upsell kartı.
class _EatsPremiumCard extends StatelessWidget {
  const _EatsPremiumCard({
    required this.hiddenByTier,
    required this.curatedLocked,
    required this.palette,
    required this.lang,
    required this.onTap,
  });

  /// Bu sorguda ücretsiz katman yüzünden gizlenen sonuç sayısı.
  final int hiddenByTier;

  /// Yalnızca premium'da görünen "Rotori Seçkisi" kayıt sayısı.
  final int curatedLocked;

  final ViewerPalette palette;
  final AppLang lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final accent = p.accent;
    final intro = lang == AppLang.tr
        ? (hiddenByTier > 0
            ? 'Bu aramada $hiddenByTier sonuç daha, artı $curatedLocked Rotori '
                'Seçkisi mekan açılır.'
            : '$curatedLocked Rotori Seçkisi mekan ve tüm karar araçları açılır.')
        : (hiddenByTier > 0
            ? '$hiddenByTier more results plus $curatedLocked curated places unlock.'
            : '$curatedLocked curated places and every decision tool unlock.');

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
            p.gold.withValues(alpha: 0.10),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EatsPremiumLogo(palette: p),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      const LText('Rotori Eats Pass', 'Rotori Eats Pass').of(lang),
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      intro,
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
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in const [
                LText('🍽️ Şimdi ne yesem?', '🍽️ What to eat now'),
                LText('📍 Yakınımda', '📍 Near me'),
                LText('🎛️ 11 filtre ekseni', '🎛️ 11 filter axes'),
                LText('⭐ Rotori skoru', '⭐ Rotori score'),
              ])
                _PremiumHintChip(text: t.of(lang), palette: p),
            ],
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
    final p = palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: p.card.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: p.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: p.textPrimary,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Rotori Eats Pass paywall önizlemesi. Satın alma akışı henüz bağlı değil
/// (monetizasyon ayrı çalışma); değer + fiyat modeli gösterilir.
///
/// Buradaki her madde bugün ÇALIŞAN bir özelliktir — "yakında" vaadi verilmez.
class _EatsPaywallSheet extends StatelessWidget {
  const _EatsPaywallSheet({required this.palette, required this.lang});

  final ViewerPalette palette;
  final AppLang lang;

  static const _benefits = <({String emoji, LText title, LText body})>[
    (
      emoji: '🍽️',
      title: LText('Şimdi ne yesem?', 'What should I eat now?'),
      body: LText(
        'Konum + saat + bütçe + diyet tek dokunuşta 3 net öneriye dönüşür.',
        'Location + time + budget + diet become 3 clear picks in one tap.',
      ),
    ),
    (
      emoji: '📍',
      title: LText('Yakınımda ve rotama yakın', 'Near me and near my route'),
      body: LText(
        'Mesafe, yürüme dakikası ve bugünkü planının merkezine göre sıralama.',
        'Distance, walking minutes and sorting around today\'s plan.',
      ),
    ),
    (
      emoji: '🎛️',
      title: LText('11 eksenli detaylı filtre', '11-axis detailed filter'),
      body: LText(
        'Mutfak, fiyat kademesi, puan, servis saati, kart geçer, kuyruksuz, '
            'namaz alanı, alkolsüz mekan…',
        'Cuisine, price tier, rating, service time, cards accepted, no queue, '
            'prayer space, alcohol-free…',
      ),
    ),
    (
      emoji: '⭐',
      title: LText('Rotori uyum skoru', 'Rotori match score'),
      body: LText(
        'Her mekan için diyet / puan / bütçe / mesafe kırılımı — neden o mekan?',
        'Diet / rating / budget / distance breakdown for every place — why this one?',
      ),
    ),
    (
      emoji: '✦',
      title: LText('Rotori Seçkisi', 'Rotori curated picks'),
      body: LText(
        'Turist listelerinde olmayan küratörlü mekanlar ve bilenin ipuçları.',
        'Curated places off the tourist lists, plus insider tips.',
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.92;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Container(
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: p.border),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _EatsPremiumLogo(palette: p),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            const LText('Rotori Eats Pass', 'Rotori Eats Pass')
                                .of(lang),
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            const LText(
                              'Japonya\'da hiçbir uygulama senin planını, bütçeni '
                                  've diyetini aynı anda bilmiyor. Bu, o farkın adı.',
                              'No app in Japan knows your plan, your budget and '
                                  'your diet at the same time. This is that difference.',
                            ).of(lang),
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: 12.5,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  const LText('Premium ile açılanlar', 'What unlocks with premium')
                      .of(lang),
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                for (final b in _benefits)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.emoji, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                b.title.of(lang),
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                b.body.of(lang),
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
                    ),
                  ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.elevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        const LText(
                          'Ücretsiz katmanda ne var?',
                          'What stays free?',
                        ).of(lang),
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        lang == AppLang.tr
                            ? 'Katalog, helal/vejetaryen ve şehir filtresi, arama, '
                                'her aramada ilk $kEatsFreeVisibleLimit sonuç, '
                                'harita — ve güvenlik bilgisinin tamamı: helal '
                                'seviyesi açıklaması, nakit uyarısı ve sipariş '
                                'frazları hiçbir zaman kilitlenmez.'
                            : 'The catalogue, halal/vegetarian and city filters, '
                                'search, the first $kEatsFreeVisibleLimit results '
                                'per search, maps — and all safety information: '
                                'halal level explainers, cash-only warnings and '
                                'ordering phrases are never locked.',
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.elevated,
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
                              const LText(
                                'Trip Pass · gezi başına',
                                'Trip Pass · per trip',
                              ).of(lang),
                              style: TextStyle(
                                color: p.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              const LText(
                                'Abonelik yok — tek seferlik.',
                                'No subscription — one-time.',
                              ).of(lang),
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: p.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          const LText('Yakında', 'Soon').of(lang),
                          style: TextStyle(
                            color: p.textPrimary,
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
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.of(context).pop();
                      messenger.showSnackBar(
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
                      backgroundColor: p.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      const LText('Beni haberdar et', 'Notify me').of(lang),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      const LText('Kapat', 'Close').of(lang),
                      style: TextStyle(color: p.textSecondary),
                    ),
                  ),
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
// Alt bilgi kartları
// ---------------------------------------------------------------------------

class _BudgetQuickCard extends StatelessWidget {
  const _BudgetQuickCard({
    required this.palette,
    required this.lang,
    required this.table,
    required this.mealBudget,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final UnitCostTable table;
  final int? mealBudget;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final refByKey = {for (final item in table.references) item.key: item.jpy};
    final ramen = refByKey['ramen'] ?? 1100;
    final konbini = refByKey['konbini_meal'] ?? 700;
    final sushi = refByKey['sushi_set'] ?? 2500;

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
            const LText('Hızlı Bütçe Rehberi', 'Quick Budget Guide').of(lang),
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _priceRow('🍜 Ramen', ramen, p),
          _priceRow(
            lang == AppLang.tr ? '🏪 Konbini öğün' : '🏪 Konbini meal',
            konbini,
            p,
          ),
          _priceRow(
            lang == AppLang.tr ? '🍣 Suşi seti' : '🍣 Sushi set',
            sushi,
            p,
          ),
          const SizedBox(height: 8),
          Text(
            mealBudget != null && mealBudget! > 0
                ? (lang == AppLang.tr
                    ? 'Senin öğün bütçen: kişi başı ${formatJpy(mealBudget!)} — '
                        'liste bu bandı göz önüne alarak puanlanıyor.'
                    : 'Your meal budget: ${formatJpy(mealBudget!)} per person — '
                        'the list is scored against this band.')
                : const LText(
                    'Yetişkin günlük yemek bandı: yaklaşık ¥3.500 – ¥9.000',
                    'Adult daily food band: around ¥3,500 – ¥9,000',
                  ).of(lang),
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 12.5,
              height: 1.35,
            ),
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

/// Skorun kişiselleştirilemediğini söyleyen ve girdi toplayan çağrı.
///
/// Uygulama beslenme tercihini ve öğün bütçesini hiç sormuyordu; skor bu
/// yüzden herkeste aynı nötr sayıyı üretiyordu. Bunu gizlemek yerine
/// kullanıcıya söyleyip doldurma yolunu veriyoruz.
class _PersonalizePrompt extends StatelessWidget {
  const _PersonalizePrompt({
    required this.palette,
    required this.lang,
    required this.missingDiet,
    required this.missingBudget,
    required this.onTap,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final bool missingDiet;
  final bool missingBudget;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final what = <String>[
      if (missingDiet)
        const LText('beslenme tercihin', 'your dietary needs').of(lang),
      if (missingBudget)
        const LText('öğün bütçen', 'your meal budget').of(lang),
    ].join(lang == AppLang.tr ? ' ve ' : ' and ');

    return Material(
      color: p.gold.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.gold.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, size: 19, color: p.gold),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      const LText(
                        'Öneriler henüz sana göre değil',
                        'Recommendations are not yours yet',
                      ).of(lang),
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lang == AppLang.tr
                          ? '$what bilinmiyor. Gir, sıralama ve skor sana göre çalışsın.'
                          : 'I don\'t know $what. Set them and the ranking becomes yours.',
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

class _DietaryCard extends StatelessWidget {
  const _DietaryCard({
    required this.trip,
    required this.palette,
    required this.lang,
    required this.onEdit,
  });

  final Trip trip;
  final ViewerPalette palette;
  final AppLang lang;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = LanguageScope.of(context);
    final tagSet = trip.preferences.dietaryTags.toSet();
    final options = dietaryForCountry('JP')
        .where((option) => tagSet.contains(option.id))
        .toList(growable: false);
    final budget = trip.preferences.mealBudgetJpyPerPerson;

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
          Row(
            children: [
              Expanded(
                child: Text(
                  const LText(
                    'Aktif Beslenme Tercihlerin',
                    'Your Active Dietary Preferences',
                  ).of(lang),
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  const LText('Düzenle', 'Edit').of(lang),
                  style: TextStyle(
                    color: p.accent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (options.isEmpty)
            Text(
              const LText(
                'Özel bir beslenme tercihi seçili değil — liste tüm mekanları '
                'gösteriyor ve skor bu bileşeni "eksik" sayıyor. "Düzenle" ile '
                'tercihini gir.',
                'No dietary preference is set — the list shows every place and '
                'the score counts this input as missing. Tap "Edit" to set it.',
              ).of(lang),
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 12.5,
                height: 1.35,
              ),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in options)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: p.elevated,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: p.border),
                    ),
                    child: Text(
                      '${option.emoji} ${s.s(option.label)}',
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              budget != null && budget > 0
                  ? (lang == AppLang.tr
                      ? 'Bu tercihler ve ${formatJpy(budget)} öğün bütçen '
                          'filtreyi ve Rotori uyum skorunu besliyor.'
                      : 'These preferences and your ${formatJpy(budget)} meal '
                          'budget drive the filter and the Rotori score.')
                  : const LText(
                      'Bu tercihler skoru besliyor. Öğün bütçen henüz girilmedi '
                          '— o bileşen "eksik" sayılıyor.',
                      'These preferences drive the score. Your meal budget is '
                          'not set yet — that input counts as missing.',
                    ).of(lang),
              style: TextStyle(color: p.textMuted, fontSize: 11.5, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _DataNote extends StatelessWidget {
  const _DataNote({required this.palette, required this.lang});

  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Text(
      lang == AppLang.tr
          ? 'Bu liste küratörlüdür ve tamamen çevrimdışı çalışır — Google '
              'Places ya da başka bir canlı kaynaktan ÇEKİLMEZ. Kayıtlar '
              'kamuya açık kaynaklardan elle derlendi ($kEatsDataVerifiedOn); '
              'puanlar Google ölçeğine yakın yaklaşık değerlerdir (Japonya\'da '
              'Tabelog 3.5 zaten üst seviyedir). Sertifika, menü, fiyat ve '
              'çalışma saatleri değişmiş olabilir — mekanda teyit et.'
          : 'This list is curated and works fully offline — it is NOT pulled '
              'from Google Places or any live source. Entries were compiled by '
              'hand from public sources ($kEatsDataVerifiedOn); ratings '
              'approximate the Google scale (in Japan a Tabelog 3.5 is already '
              'elite). Certification, menus, prices and hours may have changed '
              '— confirm at the venue.',
      style: TextStyle(color: p.textMuted, fontSize: 11, height: 1.4),
    );
  }
}
