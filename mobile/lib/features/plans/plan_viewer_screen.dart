// Plan görüntüleyici — zengin, temalı, animasyonlu okuma modu.
// React viewer tasarımının (App.tsx + CountdownBar + DayCard) Flutter portu.
//
// Katmanlar:
//   1) Seçili palet Theme + ViewerPaletteScope + Scaffold(bg=palette.bg).
//   2) Üst durum barı: faz etiketi + geri sayım + bilet çipleri + aksiyonlar.
//   3) Hero: sakura yağmuru + gün/gece pill + gradient başlık + rota zinciri.
//   4) Tema seçici (bottom sheet, 3 tema).
//   5) İstatistik kartları (gece, destinasyon geceleri, bilet, gün).
//   6) Uçuş + otel kartları (temalı).
//   7) Günler: aktif gün vurgulu + genişletilmiş, geçmiş günler soluk;
//      aktif günde "Sıradaki" aktivite işaretlenir; ilk build'de otomatik konum.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n.dart';
import '../../core/supabase_client.dart';
import '../../data/google_maps_launcher.dart';
import '../../data/language_store.dart';
import '../../data/plans_repository.dart';
import '../../data/reminders_store.dart';
import '../../data/weather_service.dart';
import '../../domain/city_palette.dart';
import '../../domain/destination_profiles.dart';
import '../../domain/place_coords.dart';
import '../../domain/types.dart';
import '../auth/auth_repository.dart';
import '../shared/place_detail_sheet.dart';
import '../viewer/budget_screen.dart';
import '../viewer/checklist_screen.dart';
import '../viewer/compass_screen.dart';
import '../viewer/day_map_screen.dart';
import '../viewer/home_widget_hook.dart';
import '../viewer/japanese_phrases_screen.dart';
import '../viewer/must_know_screen.dart';
import '../viewer/pre_departure_checklist_screen.dart';
import '../viewer/reward_map_screen.dart';
import '../viewer/viewer_theme.dart';
import '../viewer/weather_screen.dart';
import 'plan_providers.dart';

// ---------------------------------------------------------------------------
// Tarih yardımcıları — dile göre ay/gün dizisi (intl locale'e bağlı DEĞİL).
// ---------------------------------------------------------------------------

/// "2025-05-13" → "13 Mayıs 2025, Salı" (tr) / "May 13 2025, Tuesday" (en).
/// [weekdayHint] yalnızca TR'de kullanılır (domain verisi Türkçedir); EN'de
/// gün adı tarihten hesaplanır.
String _formatDateLong(String isoDate, AppLang lang, {String? weekdayHint}) {
  final d = DateTime.tryParse(isoDate);
  if (d == null) return isoDate;
  final months = L10n.monthsFor(lang);
  final weekdays = L10n.weekdaysFor(lang);
  final wd = (lang == AppLang.tr && weekdayHint?.isNotEmpty == true)
      ? weekdayHint!
      : weekdays[d.weekday];
  return lang == AppLang.en
      ? '${months[d.month]} ${d.day} ${d.year}, $wd'
      : '${d.day} ${months[d.month]} ${d.year}, $wd';
}

int _daysUntil(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return 0;
  final diff = d.difference(DateTime.now()).inMilliseconds;
  return diff < 0 ? 0 : (diff / 86400000).floor();
}

/// "before" | "during" | "after" — React tripPhase.
String _tripPhase(String start, String end, DateTime now) {
  final s = DateTime.tryParse(start);
  final e = DateTime.tryParse(end);
  if (s == null || e == null) return 'before';
  if (now.isBefore(s)) return 'before';
  if (now.isAfter(e)) return 'after';
  return 'during';
}

/// React getActiveDayIndex — bugün (yerel) YYYY-MM-DD ile eşle, yoksa ilk
/// gelecekteki gün, o da yoksa son gün.
int _activeDayIndex(List<DayPlan> daysSorted) {
  if (daysSorted.isEmpty) return 0;
  final now = DateTime.now();
  final today =
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final exact = daysSorted.indexWhere((d) => d.date == today);
  if (exact >= 0) return exact;
  final future = daysSorted.indexWhere((d) => d.date.compareTo(today) >= 0);
  return future >= 0 ? future : daysSorted.length - 1;
}

/// "HH:MM" → günün dakikası; parse edilemezse null.
int? _timeToMinutes(String? t) {
  if (t == null || t.isEmpty) return null;
  final parts = t.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

// ---------------------------------------------------------------------------
// Ekran kökü — tema + palet scope sarmalayıcı.
// ---------------------------------------------------------------------------

class PlanViewerScreen extends ConsumerWidget {
  const PlanViewerScreen({super.key, required this.planId});
  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(viewerPaletteProvider);
    final planAsync = ref.watch(planByIdProvider(planId));

    // Not: Scaffold + drawer artık _ViewerBody içinde kuruluyor — drawer'a
    // trip ve tüm _open* callback'lerine (aksiyon şeridi drawer'a taşındı)
    // erişebilmesi için gerekli.
    return Theme(
      data: palette.toThemeData(),
      child: ViewerPaletteScope(
        palette: palette,
        child: planAsync.when(
          loading: () => Scaffold(
            backgroundColor: palette.bg,
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Scaffold(
            backgroundColor: palette.bg,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  LanguageScope.of(context)
                      .p('viewer.loadFailed', {'err': '$err'}),
                  style: TextStyle(color: palette.textPrimary),
                ),
              ),
            ),
          ),
          data: (trip) => _ViewerBody(trip: trip, planId: planId),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Gövde — durum barı + kaydırılabilir içerik + otomatik konum.
// ---------------------------------------------------------------------------

class _ViewerBody extends ConsumerStatefulWidget {
  const _ViewerBody({required this.trip, required this.planId});
  final Trip trip;
  final String planId;

  @override
  ConsumerState<_ViewerBody> createState() => _ViewerBodyState();
}

class _ViewerBodyState extends ConsumerState<_ViewerBody>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  final _activeDayKey = GlobalKey();
  bool _autoScrolled = false;

  /// Düzenleme modu — üst bardaki ✎ simgesine basılınca aktif olur.
  /// Bu modda: aynı gün içinde sıralama, başka güne taşıma ve kaldırma
  /// aksiyonları her item için görünür. Kayıt her mutasyonda anlık yapılır
  /// (`plansRepositoryProvider.save`).
  bool _editMode = false;

  /// Tarih (YYYY-MM-DD) → o günün hava tahmini (o tarihte hangi destinasyondayız
  /// ise oradan). Open-Meteo'dan bir kez çekilir; hata sessiz.
  Map<String, DayForecast> _forecast = const {};

  List<DayPlan> get _sortedDays =>
      [...widget.trip.days]..sort((a, b) => a.date.compareTo(b.date));

  List<TripDestination> get _sortedDestinations =>
      [...widget.trip.preferences.destinations]
        ..sort((a, b) => a.order.compareTo(b.order));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // İlk frame sonrası: (1) aktif güne oto-kaydır, (2) iOS Home Screen
    // widget'ına "Sıradaki Aktivite" verisini gönder. İki callback bağımsız —
    // sıra önemli değil, hook web'de ve native target yoksa sessizce no-op.
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoScrollToActive());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => HomeWidgetHook.pushFromTrip(widget.trip),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadForecast());
  }

  /// Her destinasyon için Open-Meteo'dan 16 günlük tahmin çek. Bir günün
  /// forecast'i, o tarihte hangi şehre ait olduğuna göre eşleştirilir —
  /// böylece Kyoto gününe Tokyo hava tahmini düşmez. Ağ hatası sessiz.
  Future<void> _loadForecast() async {
    final dests = _sortedDestinations;
    if (dests.isEmpty) return;
    final result = <String, DayForecast>{};
    final seen = <String>{};
    for (final d in dests) {
      final lat = d.lat, lng = d.lng;
      if (lat == null || lng == null) continue;
      final key = '$lat,$lng';
      if (!seen.add(key)) continue;
      try {
        final list = await fetchForecast(lat, lng);
        for (final f in list) {
          final match = getDestinationForDate(dests, f.date);
          if (match?.id == d.id) result[f.date] = f;
        }
      } catch (_) {
        // Ağ hatası — sessizce geç, hava rozeti o gün için gösterilmez.
      }
    }
    if (!mounted || result.isEmpty) return;
    setState(() => _forecast = result);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Uygulama arka plandan öne alındığında widget verisini tazele — kullanıcı
    // dışarıda saatlerce beklemiş olabilir; "sıradaki" değişmiş olabilir.
    if (state == AppLifecycleState.resumed) {
      HomeWidgetHook.pushFromTrip(widget.trip);
    }
  }

  void _autoScrollToActive() {
    if (_autoScrolled || !mounted) return;
    final ctx = _activeDayKey.currentContext;
    if (ctx == null) return;
    _autoScrolled = true;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
      alignment: 0.05, // aktif günü üste yakın konumla
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ViewerPalette.of(context);
    final trip = widget.trip;
    final days = _sortedDays;
    final activeIndex = _activeDayIndex(days);

    // Minimalize edilmiş viewer: sadece üst bar + doğrudan gün akışı. Uçuş
    // özeti, konaklama, metrikler ve tüm aksiyon butonları drawer içinde.
    return Scaffold(
      backgroundColor: palette.bg,
      drawer: _ViewerDrawer(
        palette: palette,
        trip: trip,
        dayCount: days.length,
        onOpenThemePicker: _openThemePicker,
        onOpenMap: _openMap,
        onOpenCompass: _openCompass,
        onOpenBudget: _openBudget,
        onOpenChecklist: _openChecklist,
        onOpenPrep: _openPrep,
        onOpenWeather: _openWeather,
        onOpenPhrases: _openPhrases,
        onOpenMustKnow: _openMustKnow,
        onOpenTripInGoogleMaps: _openTripInGoogleMaps,
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _TopStatusBar(
              trip: trip,
              palette: palette,
              planId: widget.planId,
              editMode: _editMode,
              onToggleEdit: _toggleEditMode,
              onRebuild: _confirmRebuild,
            ),
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  if (days.isEmpty)
                    _EmptyDaysCard(palette: palette)
                  else
                    for (var i = 0; i < days.length; i++)
                      _DayCard(
                        key: i == activeIndex ? _activeDayKey : null,
                        day: days[i],
                        palette: palette,
                        dest: getDestinationForDate(
                          _sortedDestinations,
                          days[i].date,
                        ),
                        bubbleColor: cityColorFor(
                          _sortedDestinations,
                          getDestinationForDate(
                            _sortedDestinations,
                            days[i].date,
                          )?.id,
                        ),
                        forecast: _forecast[days[i].date],
                        isPast: i < activeIndex,
                        isActive: i == activeIndex,
                        editMode: _editMode,
                        allDays: days,
                        onOpenItem: _openItem,
                        onOpenMap: _openDayMap,
                        onMoveWithinDay: _moveWithinDay,
                        onMoveItemToDay: _moveItemToDay,
                        onDeleteItem: _deleteItem,
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bir gün öğesi için yer detay popup'ını açar — bilet arama + ekleme
  /// callback'lerini stateful gövdeden geçirir (persistence burada kalır).
  void _openItem(TimelineItem item, TripDestination? dest) {
    final existing = widget.trip.tickets
        .where((t) => t.label == item.title)
        .cast<Ticket?>()
        .firstWhere((_) => true, orElse: () => null);
    showPlaceDetailSheet(
      context: context,
      item: item,
      city: dest?.city ?? '',
      countryCode: dest?.countryCode,
      existingTicket: existing,
      onAddTicket: (t) {
        widget.trip.tickets.removeWhere((x) => x.label == t.label);
        widget.trip.tickets.add(t);
        ref.read(plansRepositoryProvider)?.save(widget.trip);
        if (mounted) setState(() {});
      },
    );
  }

  // -------------------------------------------------------------------------
  // Edit mode — mutation helpers (her biri anlık kaydeder + UI'yı tazeler).
  // -------------------------------------------------------------------------

  DayPlan? _findDayByDate(String date) {
    for (final d in widget.trip.days) {
      if (d.date == date) return d;
    }
    return null;
  }

  void _persistAndRefresh() {
    ref.read(plansRepositoryProvider)?.save(widget.trip);
    if (mounted) setState(() {});
    HomeWidgetHook.pushFromTrip(widget.trip);
  }

  /// Aynı gün içinde item sırasını değiştirir (yukarı/aşağı).
  void _moveWithinDay(DayPlan day, int oldIdx, int newIdx) {
    if (newIdx < 0 || newIdx >= day.items.length || oldIdx == newIdx) return;
    final item = day.items.removeAt(oldIdx);
    day.items.insert(newIdx, item);
    _persistAndRefresh();
  }

  /// Item'ı başka bir gün planına taşır. Yeni günün sonuna eklenir.
  void _moveItemToDay(DayPlan sourceDay, int itemIdx, DayPlan targetDay) {
    if (identical(sourceDay, targetDay)) return;
    if (itemIdx < 0 || itemIdx >= sourceDay.items.length) return;
    final item = sourceDay.items.removeAt(itemIdx);
    // Hangi günden taşındığını kaydet — kullanıcı geri almak isteyebilir.
    final moved = item.copyWith(movedFromDay: sourceDay.dayNumber);
    targetDay.items.add(moved);
    _persistAndRefresh();
    final s = LanguageScope.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.p('viewer.edit.movedSnack', {
          'title': item.title,
          'day': '${targetDay.dayNumber}',
        })),
      ),
    );
  }

  /// Item'ı plandan kaldırır. Undo ile geri alınabilir (SnackBar action).
  void _deleteItem(DayPlan day, int itemIdx) {
    if (itemIdx < 0 || itemIdx >= day.items.length) return;
    final removed = day.items.removeAt(itemIdx);
    _persistAndRefresh();
    final s = LanguageScope.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.p('viewer.edit.deletedSnack', {'title': removed.title})),
        action: SnackBarAction(
          label: s.s('viewer.edit.undo'),
          onPressed: () {
            // Geri al: aynı index'e yerleştir (varsa) yoksa sona.
            final safeIdx =
                itemIdx > day.items.length ? day.items.length : itemIdx;
            day.items.insert(safeIdx, removed);
            _persistAndRefresh();
          },
        ),
      ),
    );
  }

  void _toggleEditMode() {
    setState(() => _editMode = !_editMode);
  }

  /// "Baştan oluştur" — mevcut plan atılıp planner ekranından yeniden yaratılır.
  /// Onay dialog'u ile korunur (kazara tıklamayı engellemek için).
  Future<void> _confirmRebuild() async {
    final s = LanguageScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.s('viewer.tt.editRebuildConfirmTitle')),
        content: Text(s.s('viewer.tt.editRebuildConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.s('viewer.edit.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.s('viewer.edit.rebuild')),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      context.go('/plans/${widget.planId}/edit');
    }
  }

  void _openMap() {
    final palette = ref.read(viewerPaletteProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: palette.toThemeData(),
          child: ViewerPaletteScope(
            palette: palette,
            child: RewardMapScreen(trip: widget.trip),
          ),
        ),
      ),
    );
  }

  /// Pusula ekranını açar (acil numaralar, otel adresi, Japonca frazlar).
  void _openCompass() {
    final palette = ref.read(viewerPaletteProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: palette.toThemeData(),
          child: ViewerPaletteScope(
            palette: palette,
            child: CompassScreen(trip: widget.trip),
          ),
        ),
      ),
    );
  }

  /// Bütçe & harcama panelini açar (gün/kategori toplamları, JPY→TL çevirici).
  void _openBudget() {
    final palette = ref.read(viewerPaletteProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: palette.toThemeData(),
          child: ViewerPaletteScope(
            palette: palette,
            child: BudgetScreen(trip: widget.trip),
          ),
        ),
      ),
    );
  }

  /// Valiz & Hazırlık listesini açar (Japonya'ya özel, plan bazlı işaretlenir).
  void _openChecklist() {
    final palette = ref.read(viewerPaletteProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: palette.toThemeData(),
          child: ViewerPaletteScope(
            palette: palette,
            child: ChecklistScreen(trip: widget.trip),
          ),
        ),
      ),
    );
  }

  /// Yolculuk öncesi hazırlık ekranını açar (pasaport, Visit Japan Web,
  /// powerbank, eSIM, JR Pass… + kullanıcının kendi maddeleri).
  void _openPrep() {
    final palette = ref.read(viewerPaletteProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: palette.toThemeData(),
          child: ViewerPaletteScope(
            palette: palette,
            child: PreDepartureChecklistScreen(trip: widget.trip),
          ),
        ),
      ),
    );
  }

  /// Hava Durumu ekranını açar (Open-Meteo günlük tahmin, anahtar yok).
  void _openWeather() {
    final palette = ref.read(viewerPaletteProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: palette.toThemeData(),
          child: ViewerPaletteScope(
            palette: palette,
            child: WeatherScreen(trip: widget.trip),
          ),
        ),
      ),
    );
  }

  /// Pratik Japonca kelimeler & cümleler sayfası.
  void _openPhrases() {
    final palette = ref.read(viewerPaletteProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: palette.toThemeData(),
          child: ViewerPaletteScope(
            palette: palette,
            child: JapanesePhrasesScreen(trip: widget.trip),
          ),
        ),
      ),
    );
  }

  /// Tüm planı Google Maps'te aç — her günün ilk konumlu durağı sırayla
  /// bir waypoint olur. Sonuç: gezinin gün-gün kabaca rotası Google Maps
  /// üzerinde açılır (ilk gün origin, son gün destination, aradakiler
  /// waypoints). Detay pinler için day map ekranı kullanılır.
  ///
  /// Sınır: Google Maps `dir` URL'i en fazla 9 waypoint destekler. 11+
  /// günlük gezilerde ilk 9 ara nokta kalır, kullanıcıya SnackBar ile
  /// bildirim verilir.
  Future<void> _openTripInGoogleMaps() async {
    final tripStops = resolveTripStops(widget.trip);
    final sortedDays = [...widget.trip.days]
      ..sort((a, b) => a.date.compareTo(b.date));
    final waypoints = <({double lat, double lng, String? label})>[];
    for (final day in sortedDays) {
      final stops = tripStops[day.dayNumber];
      if (stops == null || stops.isEmpty) continue;
      final first = stops.first;
      waypoints.add(
        (lat: first.lat, lng: first.lng, label: first.item.title),
      );
    }
    final messenger = ScaffoldMessenger.of(context);
    final s = LanguageScope.of(context);
    if (waypoints.isEmpty) {
      // Hiç konumlu durak yok — Japonya merkezini aç, kullanıcı Google
      // Maps'te en azından ülke haritasını görsün.
      final ok = await openGoogleMapsPoint(
        lat: 36.2048,
        lng: 138.2529,
        label: 'Japan',
      );
      if (!mounted) return;
      if (!ok) {
        messenger.showSnackBar(SnackBar(content: Text(s.s('map.openFailed'))));
      }
      return;
    }
    if (waypoints.length == 1) {
      final p = waypoints.first;
      final ok = await openGoogleMapsPoint(
        lat: p.lat,
        lng: p.lng,
        label: p.label,
      );
      if (!mounted) return;
      if (!ok) {
        messenger.showSnackBar(SnackBar(content: Text(s.s('map.openFailed'))));
      }
      return;
    }
    final res = await openGoogleMapsRoute(points: waypoints);
    if (!mounted) return;
    if (!res.launched) {
      messenger.showSnackBar(SnackBar(content: Text(s.s('map.openFailed'))));
    } else if (res.truncated) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.s('map.truncatedWaypoints'))),
      );
    }
  }

  /// "Mutlaka bilmeniz gerekenler" — seyahat tavsiyeleri sayfası.
  void _openMustKnow() {
    final palette = ref.read(viewerPaletteProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: palette.toThemeData(),
          child: ViewerPaletteScope(
            palette: palette,
            child: MustKnowScreen(trip: widget.trip),
          ),
        ),
      ),
    );
  }

  /// Bir günün rota haritasını açar (numaralı pinli OSM haritası).
  void _openDayMap(DayPlan day) {
    final palette = ref.read(viewerPaletteProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: palette.toThemeData(),
          child: ViewerPaletteScope(
            palette: palette,
            child: DayMapScreen(trip: widget.trip, dayNumber: day.dayNumber),
          ),
        ),
      ),
    );
  }

  void _openThemePicker() {
    final palette = ref.read(viewerPaletteProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ThemePickerSheet(current: palette.id),
    );
  }
}

// ---------------------------------------------------------------------------
// 2) Üst durum barı.
// ---------------------------------------------------------------------------

class _TopStatusBar extends StatefulWidget {
  const _TopStatusBar({
    required this.trip,
    required this.palette,
    required this.planId,
    required this.editMode,
    required this.onToggleEdit,
    required this.onRebuild,
  });

  final Trip trip;
  final ViewerPalette palette;
  final String planId;

  /// True ise üst bardaki ✎ ikonu ✓ olur ve baştan-oluştur (⟳) ikonu çıkar.
  final bool editMode;
  final VoidCallback onToggleEdit;

  /// Onay dialog'u ile planı planner ekranından baştan oluşturur.
  final VoidCallback onRebuild;

  @override
  State<_TopStatusBar> createState() => _TopStatusBarState();
}

class _TopStatusBarState extends State<_TopStatusBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce == _reduceMotion && (reduce || _pulse.isAnimating)) return;
    _reduceMotion = reduce;
    if (reduce) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String _phaseLabel(LanguageScope s) {
    final trip = widget.trip;
    final hasDates = DateTime.tryParse(trip.tripStart) != null &&
        DateTime.tryParse(trip.tripEnd) != null;
    if (!hasDates) return s.s('viewer.phase.new');
    final now = DateTime.now();
    final phase = _tripPhase(trip.tripStart, trip.tripEnd, now);
    if (phase == 'after') return s.s('viewer.phase.done');
    if (phase == 'during') return s.s('viewer.phase.during');
    final start = DateTime.parse(trip.tripStart);
    final diff = start.difference(now);
    if (diff.isNegative) return s.s('viewer.phase.during');
    final d = diff.inDays;
    final h = diff.inHours % 24;
    return s.p('viewer.phase.countdown', {'d': '$d', 'h': '$h'});
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final onColor = p.topBarOnColor;
    final s = LanguageScope.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: p.topBar,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
        child: Column(
          children: [
            // Üst satır: [☰]  [countdown pill]  [🔔][✏️]
            // Hamburger drawer'ı açar; countdown pill ortada; bell + edit sağda.
            Row(
              children: [
                Builder(
                  builder: (ctx) => _BarIconButton(
                    icon: Icons.menu,
                    color: onColor,
                    tooltip: s.s('drawer.tt.menu'),
                    onTap: () => Scaffold.of(ctx).openDrawer(),
                  ),
                ),
                // Faz etiketi — Expanded ile ortalanır, sığmayınca ellipsis.
                Expanded(
                  child: Center(
                    child: Text(
                      _phaseLabel(s),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: onColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                // Sağa sabit aksiyonlar: bildirim + düzenle (+ edit modunda baştan oluştur).
                _BarBellButton(
                  color: onColor,
                  onTap: () => context.push('/reminders'),
                ),
                if (widget.editMode)
                  _BarIconButton(
                    icon: Icons.refresh,
                    color: onColor,
                    tooltip: s.s('viewer.tt.editRebuild'),
                    onTap: widget.onRebuild,
                  ),
                _BarIconButton(
                  icon: widget.editMode ? Icons.check : Icons.edit_outlined,
                  color: onColor,
                  tooltip: widget.editMode
                      ? s.s('viewer.tt.editDone')
                      : s.s('viewer.tt.edit'),
                  onTap: widget.onToggleEdit,
                ),
              ],
            ),
            // Aksiyon şeridi kaldırıldı — tüm butonlar drawer'a taşındı.
            if (widget.trip.tickets.isNotEmpty) ...[
              const SizedBox(height: 4),
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  itemCount: widget.trip.tickets.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => _TicketChip(
                    ticket: widget.trip.tickets[i],
                    palette: p,
                    pulse: _pulse,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BarIconButton extends StatelessWidget {
  const _BarIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: color, size: 22),
      tooltip: tooltip,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      onPressed: onTap,
    );
  }
}

class _BarBellButton extends ConsumerWidget {
  const _BarBellButton({required this.color, required this.onTap});
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(remindersProvider).length;
    return Tooltip(
      message: LanguageScope.of(context).s('viewer.tt.reminders'),
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(LucideIcons.bell, color: color, size: 22),
              if (count > 0)
                Positioned(
                  right: 6,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE74C3C),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    constraints: const BoxConstraints(minWidth: 16),
                    alignment: Alignment.center,
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
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

class _TicketChip extends StatelessWidget {
  const _TicketChip({
    required this.ticket,
    required this.palette,
    required this.pulse,
  });
  final Ticket ticket;
  final ViewerPalette palette;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final emoji = ticket.emoji ?? '🎫';
    final urgent = !ticket.purchased &&
        ticket.bookingOpens != null &&
        _daysUntil(ticket.bookingOpens!) <= 14;

    final String text;
    Color bg;
    Color fg;
    if (ticket.purchased) {
      text = '$emoji ✓';
      bg = palette.matcha.withValues(alpha: 0.22);
      fg = palette.matcha;
    } else if (urgent) {
      text = '$emoji ${_daysUntil(ticket.bookingOpens!)}g';
      bg = palette.sunset.withValues(alpha: 0.25);
      fg = palette.sunset;
    } else if (ticket.visitDate != null) {
      text = '$emoji ${_daysUntil(ticket.visitDate!)}g';
      bg = palette.topBarOnColor.withValues(alpha: 0.18);
      fg = palette.topBarOnColor;
    } else {
      final short = ticket.label.split(' ').first;
      text = '$emoji ${short.isEmpty ? ticket.label : short}';
      bg = palette.topBarOnColor.withValues(alpha: 0.18);
      fg = palette.topBarOnColor;
    }

    final chip = Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );

    if (!urgent) return chip;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.55, end: 1).animate(pulse),
      child: chip,
    );
  }
}


class _EmptyDaysCard extends StatelessWidget {
  const _EmptyDaysCard({required this.palette});
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        LanguageScope.of(context).s('viewer.emptyDays'),
        textAlign: TextAlign.center,
        style: TextStyle(color: palette.textSecondary),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7) Gün kartı.
// ---------------------------------------------------------------------------

class _DayCard extends StatefulWidget {
  const _DayCard({
    super.key,
    required this.day,
    required this.palette,
    required this.dest,
    required this.bubbleColor,
    this.forecast,
    required this.isPast,
    required this.isActive,
    required this.editMode,
    required this.allDays,
    required this.onOpenItem,
    required this.onOpenMap,
    required this.onMoveWithinDay,
    required this.onMoveItemToDay,
    required this.onDeleteItem,
  });
  final DayPlan day;
  final ViewerPalette palette;
  final TripDestination? dest;
  final Color bubbleColor;
  final DayForecast? forecast;
  final bool isPast;
  final bool isActive;

  /// True ise her item için sıralama/taşıma/kaldırma menüsü çıkar; itemler
  /// tıklandığında normal detay yerine bu menüyü de gösterir.
  final bool editMode;

  /// Başka güne taşıma menüsünü besleyen tüm gün listesi (sıralı).
  final List<DayPlan> allDays;

  final void Function(TimelineItem item, TripDestination? dest) onOpenItem;
  final void Function(DayPlan day) onOpenMap;

  /// Aynı gün içinde item sırasını değiştir (yukarı/aşağı butonu için).
  final void Function(DayPlan day, int oldIdx, int newIdx) onMoveWithinDay;

  /// Item'ı hedef güne taşı.
  final void Function(DayPlan source, int itemIdx, DayPlan target)
      onMoveItemToDay;

  /// Item'ı plandan kaldır (SnackBar ile undo verilir).
  final void Function(DayPlan day, int itemIdx) onDeleteItem;

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.isActive; // aktif gün açık, diğerleri kapalı
  }

  /// Aktif günde, şimdiki dakikaya göre bir sonraki gelecek aktivitenin index'i.
  int? _nextUpcomingIndex() {
    if (!widget.isActive) return null;
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    int? best;
    var bestMin = 1 << 30;
    for (var i = 0; i < widget.day.items.length; i++) {
      final it = widget.day.items[i];
      final m = _timeToMinutes(it.time ?? it.scheduledTime);
      if (m == null) continue;
      if (m >= nowMin && m < bestMin) {
        bestMin = m;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final day = widget.day;
    // Düzenleme modunda tüm günleri zorla aç — kullanıcı kapalı bir gündeki
    // item'ı düzenleyemez, hedef güne taşıma için de görünür olması iyi.
    final expanded = widget.editMode ? true : _expanded;
    final nextIdx = _nextUpcomingIndex();
    final nowMin = DateTime.now().hour * 60 + DateTime.now().minute;

    final card = Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: widget.isActive ? p.cardHover : p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: widget.isActive
              ? p.sakura.withValues(alpha: 0.45)
              : p.border,
          width: widget.isActive ? 1.5 : 1,
        ),
        boxShadow: widget.isActive
            ? [
                BoxShadow(
                  color: p.sakura.withValues(alpha: 0.22),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık satırı (tıklanınca genişlet/daralt).
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.editMode
                ? null
                : () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DayBadge(day: day, palette: p, bubbleColor: widget.bubbleColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                _formatDateLong(
                                  day.date,
                                  LanguageScope.of(context).lang,
                                  weekdayHint: day.weekday,
                                ),
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (widget.forecast != null) ...[
                              const SizedBox(width: 8),
                              _WeatherBadge(
                                forecast: widget.forecast!,
                                palette: p,
                                onTap: () => _showWeatherDialog(
                                    context, widget.forecast!, p),
                              ),
                            ],
                          ],
                        ),
                        if (day.theme.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            day.theme,
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.dest != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 6, top: 2),
                      child: Text(
                        getDestinationProfile(widget.dest!.countryCode)?.flag ??
                            '',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: p.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DayMeta(day: day, palette: p),
                  const SizedBox(height: 4),
                  if (day.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        LanguageScope.of(context).s('viewer.day.noItems'),
                        style: TextStyle(color: p.textMuted),
                      ),
                    )
                  else
                    for (var i = 0; i < day.items.length; i++)
                      widget.editMode
                          ? _EditableTimelineRow(
                              day: day,
                              index: i,
                              palette: p,
                              dest: widget.dest,
                              allDays: widget.allDays,
                              onMoveWithinDay: widget.onMoveWithinDay,
                              onMoveItemToDay: widget.onMoveItemToDay,
                              onDeleteItem: widget.onDeleteItem,
                              onOpen: () =>
                                  widget.onOpenItem(day.items[i], widget.dest),
                            )
                          : _TimelineRow(
                              item: day.items[i],
                              palette: p,
                              dest: widget.dest,
                              isNext: i == nextIdx,
                              isPastItem: widget.isActive &&
                                  _isItemPast(day.items[i], nowMin),
                              isFirst: i == 0,
                              isLast: i == day.items.length - 1,
                              onOpen: () =>
                                  widget.onOpenItem(day.items[i], widget.dest),
                            ),
                  if (day.items.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => widget.onOpenMap(day),
                        icon: Icon(Icons.map_outlined,
                            size: 18, color: p.accent),
                        label: Text(
                          LanguageScope.of(context).s('viewer.day.viewOnMap'),
                          style: TextStyle(
                            color: p.accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );

    if (widget.isPast) {
      return Opacity(opacity: 0.6, child: card);
    }
    return card;
  }

  bool _isItemPast(TimelineItem item, int nowMin) {
    final m = _timeToMinutes(item.time ?? item.scheduledTime);
    if (m == null) return false;
    return m < nowMin;
  }

  /// Küçük hava rozetine dokunulunca detay dialog'u aç — emoji + etiket + yüksek/
  /// düşük/yağış. planner plan_step'teki _showWeatherDialog'un viewer palette
  /// uyarlaması.
  void _showWeatherDialog(
      BuildContext context, DayForecast f, ViewerPalette p) {
    final s = LanguageScope.of(context);
    final info = weatherInfo(f.code);
    final emoji = info.$1;
    final label = s.s(info.$2);
    showDialog<void>(
      context: context,
      barrierColor: p.bg.withValues(alpha: 0.6),
      builder: (_) => Theme(
        data: p.toThemeData(),
        child: AlertDialog(
          backgroundColor: p.card,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: p.border),
          ),
          title: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      f.date,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _wxRow(s.s('wx.high'), '${f.tempMax.round()}°C', p),
              const SizedBox(height: 6),
              _wxRow(s.s('wx.low'), '${f.tempMin.round()}°C', p),
              if (f.precipProb != null) ...[
                const SizedBox(height: 6),
                _wxRow(s.s('wx.precip'), '%${f.precipProb}', p),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                s.s('wx.close'),
                style: TextStyle(
                  color: p.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wxRow(String label, String value, ViewerPalette p) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14, color: p.textSecondary),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: p.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Gün başlığı yanındaki küçük hava rozeti: "☀️ 22°". Tıklanınca detay dialog.
class _WeatherBadge extends StatelessWidget {
  const _WeatherBadge({
    required this.forecast,
    required this.palette,
    required this.onTap,
  });
  final DayForecast forecast;
  final ViewerPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final emoji = weatherInfo(forecast.code).$1;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: palette.elevated,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.border),
          ),
          child: Text(
            '$emoji ${forecast.tempMax.round()}°',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _DayBadge extends StatelessWidget {
  const _DayBadge(
      {required this.day, required this.palette, required this.bubbleColor});
  final DayPlan day;
  final ViewerPalette palette;
  final Color bubbleColor;

  @override
  Widget build(BuildContext context) {
    final lang = LanguageScope.of(context).lang;
    final d = DateTime.tryParse(day.date);
    // EN'de gün adını tarihten hesapla (day.weekday hint'i Türkçe domain verisi).
    final wdShort = (lang == AppLang.tr && day.weekday?.isNotEmpty == true)
        ? day.weekday!
        : (d != null ? L10n.weekdaysFor(lang)[d.weekday] : '');
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${day.dayNumber}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              height: 1,
            ),
          ),
          if (wdShort.isNotEmpty)
            Text(
              wdShort.length > 3 ? wdShort.substring(0, 3) : wdShort,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }
}

class _DayMeta extends StatelessWidget {
  const _DayMeta({required this.day, required this.palette});
  final DayPlan day;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    for (final tag in day.tags) {
      chips.add(_MetaChip(
        text: tag,
        color: palette.accent,
        palette: palette,
      ));
    }
    if (day.stepsEstimate != null) {
      final max = day.stepsEstimateMax;
      final steps = max != null
          ? '👣 ${day.stepsEstimate}–$max'
          : '👣 ${day.stepsEstimate}';
      chips.add(_MetaChip(
        text: steps,
        color: palette.matcha,
        palette: palette,
      ));
    }
    if (day.taxiRecommended == true) {
      chips.add(_MetaChip(
        text: LanguageScope.of(context).s('viewer.day.taxi'),
        color: palette.sunset,
        palette: palette,
      ));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Wrap(spacing: 6, runSpacing: 6, children: chips),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.text,
    required this.color,
    required this.palette,
  });
  final String text;
  final Color color;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

IconData _kindIcon(TimelineItemKind? k) => switch (k) {
      TimelineItemKind.meal => Icons.restaurant,
      TimelineItemKind.transport => Icons.directions_transit,
      TimelineItemKind.hotel => Icons.hotel,
      _ => Icons.place,
    };

// ---------------------------------------------------------------------------
// Düzenleme modunda kullanılan wrapper — mevcut _TimelineRow'u aynen render
// eder ama yanına sıralama/taşıma/kaldırma menüsü ekler. `_TimelineRow`'un
// görsel akışını bozmamak için tıklama davranışı da menüye açık kalır.
// ---------------------------------------------------------------------------
class _EditableTimelineRow extends StatelessWidget {
  const _EditableTimelineRow({
    required this.day,
    required this.index,
    required this.palette,
    required this.dest,
    required this.allDays,
    required this.onMoveWithinDay,
    required this.onMoveItemToDay,
    required this.onDeleteItem,
    required this.onOpen,
  });

  final DayPlan day;
  final int index;
  final ViewerPalette palette;
  final TripDestination? dest;
  final List<DayPlan> allDays;
  final void Function(DayPlan day, int oldIdx, int newIdx) onMoveWithinDay;
  final void Function(DayPlan source, int itemIdx, DayPlan target)
      onMoveItemToDay;
  final void Function(DayPlan day, int itemIdx) onDeleteItem;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = LanguageScope.of(context);
    final isFirst = index == 0;
    final isLast = index == day.items.length - 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _TimelineRow(
            item: day.items[index],
            palette: p,
            dest: dest,
            isNext: false,
            isPastItem: false,
            isFirst: isFirst,
            isLast: isLast,
            onOpen: onOpen,
          ),
        ),
        // Sıralama + taşıma + kaldırma popup menüsü.
        PopupMenuButton<String>(
          tooltip: '',
          icon: Icon(Icons.more_vert, color: p.textMuted, size: 20),
          onSelected: (value) async {
            if (value == 'up') {
              onMoveWithinDay(day, index, index - 1);
            } else if (value == 'down') {
              onMoveWithinDay(day, index, index + 1);
            } else if (value == 'delete') {
              onDeleteItem(day, index);
            } else if (value.startsWith('day:')) {
              final targetIdx = int.parse(value.substring(4));
              onMoveItemToDay(day, index, allDays[targetIdx]);
            }
          },
          itemBuilder: (ctx) => <PopupMenuEntry<String>>[
            PopupMenuItem(
              value: 'up',
              enabled: !isFirst,
              child: Row(children: [
                const Icon(Icons.arrow_upward, size: 18),
                const SizedBox(width: 10),
                Text(s.s('viewer.edit.moveUp')),
              ]),
            ),
            PopupMenuItem(
              value: 'down',
              enabled: !isLast,
              child: Row(children: [
                const Icon(Icons.arrow_downward, size: 18),
                const SizedBox(width: 10),
                Text(s.s('viewer.edit.moveDown')),
              ]),
            ),
            if (allDays.length > 1) ...[
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  s.s('viewer.edit.moveToDayTitle'),
                  style: TextStyle(color: p.textMuted, fontSize: 12),
                ),
              ),
              for (var di = 0; di < allDays.length; di++)
                if (!identical(allDays[di], day))
                  PopupMenuItem<String>(
                    value: 'day:$di',
                    child: Row(children: [
                      const Icon(Icons.calendar_today, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Gün ${allDays[di].dayNumber} · '
                          '${allDays[di].date}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                  ),
            ],
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'delete',
              child: Row(children: [
                Icon(Icons.delete_outline,
                    size: 18, color: Colors.red.shade400),
                const SizedBox(width: 10),
                Text(
                  s.s('viewer.edit.deleteItem'),
                  style: TextStyle(color: Colors.red.shade400),
                ),
              ]),
            ),
          ],
        ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.item,
    required this.palette,
    required this.dest,
    required this.isNext,
    required this.isPastItem,
    required this.isFirst,
    required this.isLast,
    required this.onOpen,
  });
  final TimelineItem item;
  final ViewerPalette palette;
  final TripDestination? dest;
  final bool isNext;
  final bool isPastItem;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final time = item.time ?? item.scheduledTime ?? '--:--';
    final timeStyle = TextStyle(
      color: isPastItem ? p.textMuted : p.fuji,
      fontWeight: FontWeight.w700,
      fontSize: 13,
    );

    // Şehir-arası geçiş (Shinkansen vb.) → normal aktiviteden ayrı, gradyanlı bant.
    final isTransition =
        item.kind == TimelineItemKind.transport && item.title.contains('→');
    final Widget content = isTransition
        ? _transitionBand(context)
        : InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isNext
              ? p.accent.withValues(alpha: 0.10)
              : (isPastItem ? p.textMuted.withValues(alpha: 0.05) : null),
          border: isNext
              ? Border.all(color: p.accent.withValues(alpha: 0.55), width: 1.5)
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 62,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(time, style: timeStyle),
                    if (isPastItem) ...[
                      const SizedBox(width: 3),
                      Icon(Icons.check_rounded,
                          size: 13, color: p.textMuted),
                    ],
                  ],
                ),
              ),
            ),
            Icon(_kindIcon(item.kind), size: 16, color: p.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isNext) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: p.accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            LanguageScope.of(context).s('viewer.item.next'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (item.description != null &&
                      item.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        item.description!,
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (item.cost != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: p.gold.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${item.cost}${item.costCurrency != null ? ' ${item.costCurrency}' : ''}',
                          style: TextStyle(
                            color: p.gold,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: p.textMuted),
          ],
        ),
      ),
    );

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TimelineRail(
              palette: p,
              isFirst: isFirst,
              isLast: isLast,
              isPast: isPastItem,
              isNext: isNext,
            ),
            const SizedBox(width: 8),
            Expanded(child: content),
          ],
        ),
      ),
    );

    if (isPastItem && !isNext) {
      return Opacity(opacity: 0.6, child: row);
    }
    return row;
  }

  /// Şehir-arası geçiş bandı — timeline içinde belirgin, gradyanlı "yolculuk"
  /// kartı. Normal aktivite satırlarından net biçimde ayrışır.
  Widget _transitionBand(BuildContext context) {
    final p = palette;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: p.gradientNight,
          ),
          boxShadow: [
            BoxShadow(
              color: p.fuji.withValues(alpha: 0.30),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 46,
              child: Text(
                item.time ?? item.scheduledTime ?? '',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.25,
                    ),
                  ),
                  if (item.description != null && item.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        item.description!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (item.tips != null && item.tips!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        '💡 ${item.tips}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.chevron_right, size: 16, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

/// Timeline'ın solundaki dikey akış rayı: node + üst/alt bağlantı çizgileri.
/// - Geçmiş item → dolu koyu node + tam çizgi
/// - Aktif "Sıradaki" → pulse'lı halka + gradient node
/// - Gelecek → içi boş halka
class _TimelineRail extends StatefulWidget {
  const _TimelineRail({
    required this.palette,
    required this.isFirst,
    required this.isLast,
    required this.isPast,
    required this.isNext,
  });
  final ViewerPalette palette;
  final bool isFirst;
  final bool isLast;
  final bool isPast;
  final bool isNext;

  @override
  State<_TimelineRail> createState() => _TimelineRailState();
}

class _TimelineRailState extends State<_TimelineRail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce == _reduceMotion && (reduce || _pulse.isAnimating)) return;
    _reduceMotion = reduce;
    if (reduce) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animate = widget.isNext ? _pulse : const AlwaysStoppedAnimation(0.0);
    return SizedBox(
      width: 22,
      child: AnimatedBuilder(
        animation: animate,
        builder: (_, __) => CustomPaint(
          painter: _TimelineRailPainter(
            palette: widget.palette,
            isFirst: widget.isFirst,
            isLast: widget.isLast,
            isPast: widget.isPast,
            isNext: widget.isNext,
            pulseT: animate.value,
          ),
        ),
      ),
    );
  }
}

class _TimelineRailPainter extends CustomPainter {
  _TimelineRailPainter({
    required this.palette,
    required this.isFirst,
    required this.isLast,
    required this.isPast,
    required this.isNext,
    required this.pulseT,
  });
  final ViewerPalette palette;
  final bool isFirst;
  final bool isLast;
  final bool isPast;
  final bool isNext;
  final double pulseT;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    // Node dikey merkez: ilk satırın time metniyle hizalanacak şekilde 20px'ten.
    final cy = 20.0.clamp(0.0, size.height - 1);

    final lineColor = isPast
        ? palette.accent.withValues(alpha: 0.45)
        : palette.textMuted.withValues(alpha: 0.35);

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Üst çizgi (isFirst değilse)
    if (!isFirst) {
      canvas.drawLine(Offset(cx, 0), Offset(cx, cy - 8), linePaint);
    }
    // Alt çizgi (isLast değilse)
    if (!isLast) {
      final downColor = (isPast || isNext)
          ? palette.accent.withValues(alpha: 0.45)
          : palette.textMuted.withValues(alpha: 0.35);
      canvas.drawLine(
        Offset(cx, cy + 8),
        Offset(cx, size.height),
        Paint()
          ..color = downColor
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Node
    if (isNext) {
      // Pulse dış halka
      final pulseR = 8 + pulseT * 6;
      final pulseAlpha = (1 - pulseT) * 0.45;
      canvas.drawCircle(
        Offset(cx, cy),
        pulseR,
        Paint()..color = palette.accent.withValues(alpha: pulseAlpha),
      );
      // Dolu iç daire
      canvas.drawCircle(
        Offset(cx, cy),
        6,
        Paint()..color = palette.accent,
      );
      // İç beyaz nokta
      canvas.drawCircle(
        Offset(cx, cy),
        2.4,
        Paint()..color = Colors.white,
      );
    } else if (isPast) {
      canvas.drawCircle(
        Offset(cx, cy),
        5,
        Paint()..color = palette.accent.withValues(alpha: 0.7),
      );
    } else {
      // Gelecek: içi boş halka
      canvas.drawCircle(
        Offset(cx, cy),
        5,
        Paint()..color = palette.textMuted.withValues(alpha: 0.20),
      );
      canvas.drawCircle(
        Offset(cx, cy),
        5,
        Paint()
          ..color = palette.textMuted.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineRailPainter old) =>
      old.pulseT != pulseT ||
      old.isPast != isPast ||
      old.isNext != isNext ||
      old.isFirst != isFirst ||
      old.isLast != isLast;
}

// ---------------------------------------------------------------------------
// 4) Tema seçici.
// ---------------------------------------------------------------------------

/// ViewerThemeId → l10n anahtarı (tema adı, dile göre çözülür).
String _themeLabelKey(ViewerThemeId id) => switch (id) {
      ViewerThemeId.japanDark => 'theme.japanDark',
      ViewerThemeId.appleLight => 'theme.appleLight',
      ViewerThemeId.sakuraSoft => 'theme.sakuraSoft',
    };

class _ThemePickerSheet extends ConsumerWidget {
  const _ThemePickerSheet({required this.current});
  final ViewerThemeId current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ViewerPalette.forId(current);
    final s = LanguageScope.of(context);
    final lang = ref.watch(appLangProvider);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.s('viewer.theme.title'),
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            for (final id in ViewerThemeId.values)
              _ThemeOption(
                id: id,
                selected: id == current,
                onTap: () {
                  ref.read(viewerThemeProvider.notifier).set(id);
                  Navigator.of(context).pop();
                },
              ),
            const SizedBox(height: 16),
            // Dil / Language seçici — appLangProvider'ı ayarlar (kalıcı).
            Text(
              s.s('lang.title'),
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final l in AppLang.values) ...[
                  Expanded(
                    child: _LangOption(
                      lang: l,
                      palette: palette,
                      selected: l == lang,
                      onTap: () =>
                          ref.read(appLangProvider.notifier).set(l),
                    ),
                  ),
                  if (l != AppLang.values.last) const SizedBox(width: 10),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dil seçici tekli seçenek (TR / EN).
class _LangOption extends StatelessWidget {
  const _LangOption({
    required this.lang,
    required this.palette,
    required this.selected,
    required this.onTap,
  });
  final AppLang lang;
  final ViewerPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? palette.accent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? palette.accent : palette.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              lang.label,
              style: TextStyle(
                color: selected ? palette.accent : palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle, color: palette.accent, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.id,
    required this.selected,
    required this.onTap,
  });
  final ViewerThemeId id;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ViewerPalette.forId(id);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? palette.accent
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            _Swatch(palette: palette),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                LanguageScope.of(context).s(_themeLabelKey(id)),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: palette.accent, size: 20),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette});
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.borderStrong),
      ),
      child: Center(
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: palette.gradientSakura),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 9) Sandvich (drawer) — kullanıcı bilgisi + uçuş özet + otel özet + metrikler
//    + tüm aksiyon butonları + nav kısayolları + çıkış. Viewer minimalize
//    edildiğinde bu drawer, top bar'daki aksiyon şeridinin ve hero'nun yerini
//    aldı: asıl "iş" (günler) hemen görünsün diye.
// ---------------------------------------------------------------------------

class _ViewerDrawer extends ConsumerWidget {
  const _ViewerDrawer({
    required this.palette,
    required this.trip,
    required this.dayCount,
    required this.onOpenThemePicker,
    required this.onOpenMap,
    required this.onOpenCompass,
    required this.onOpenBudget,
    required this.onOpenChecklist,
    required this.onOpenPrep,
    required this.onOpenWeather,
    required this.onOpenPhrases,
    required this.onOpenMustKnow,
    required this.onOpenTripInGoogleMaps,
  });
  final ViewerPalette palette;
  final Trip trip;
  final int dayCount;
  final VoidCallback onOpenThemePicker;
  final VoidCallback onOpenMap;
  final VoidCallback onOpenCompass;
  final VoidCallback onOpenBudget;
  final VoidCallback onOpenChecklist;
  final VoidCallback onOpenPrep;
  final VoidCallback onOpenWeather;
  final VoidCallback onOpenPhrases;
  final VoidCallback onOpenMustKnow;
  final VoidCallback onOpenTripInGoogleMaps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = palette;
    final s = LanguageScope.of(context);
    String? email;
    try {
      email = ref.watch(currentUserProvider)?.email;
    } catch (_) {
      email = null;
    }
    final isGuest = email == null || email.isEmpty;
    final role =
        isGuest ? s.s('drawer.role.guest') : s.s('drawer.role.traveler');
    final avatarInitial =
        isGuest ? '?' : email.trim().substring(0, 1).toUpperCase();

    final actions = <_DrawerActionSpec>[
      _DrawerActionSpec(
          icon: Icons.map_outlined,
          label: s.s('viewer.tt.map'),
          onTap: onOpenMap),
      _DrawerActionSpec(
          icon: Icons.explore_outlined,
          label: s.s('viewer.tt.compass'),
          onTap: onOpenCompass),
      _DrawerActionSpec(
          icon: Icons.wb_sunny_outlined,
          label: s.s('viewer.tt.weather'),
          onTap: onOpenWeather),
      _DrawerActionSpec(
          icon: Icons.account_balance_wallet_outlined,
          label: s.s('viewer.tt.budget'),
          onTap: onOpenBudget),
      _DrawerActionSpec(
          icon: Icons.luggage_outlined,
          label: s.s('viewer.tt.checklist'),
          onTap: onOpenChecklist),
      _DrawerActionSpec(
          icon: Icons.checklist,
          label: s.s('viewer.tt.prep'),
          onTap: onOpenPrep),
      _DrawerActionSpec(
          icon: Icons.translate,
          label: s.s('viewer.tt.phrases'),
          onTap: onOpenPhrases),
      _DrawerActionSpec(
          icon: Icons.info_outline,
          label: s.s('viewer.tt.mustKnow'),
          onTap: onOpenMustKnow),
      _DrawerActionSpec(
          icon: Icons.palette_outlined,
          label: s.s('viewer.tt.theme'),
          onTap: onOpenThemePicker),
      // Tüm rotayı Google Maps'te aç — günlerden ilk konumlu duraklarını
      // sırayla waypoint yapıp Google Maps `dir` URL'i ile açar. Kompakt
      // rota özeti (max ~9 gün); günlerin detay pinleri day map ekranında.
      _DrawerActionSpec(
          icon: Icons.travel_explore,
          label: s.s('map.openInGoogleMaps'),
          onTap: onOpenTripInGoogleMaps),
    ];

    return Drawer(
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                children: [
                  _DrawerBrandMark(palette: p),
                  const SizedBox(width: 12),
                  Text(
                    s.s('drawer.brand'),
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DrawerFlightsMini(trip: trip, palette: p),
                    const SizedBox(height: 10),
                    _DrawerHotelsMini(trip: trip, palette: p),
                    const SizedBox(height: 10),
                    _DrawerMetricsMini(
                        trip: trip, palette: p, dayCount: dayCount),
                    const SizedBox(height: 14),
                    _DrawerActionGrid(actions: actions, palette: p),
                  ],
                ),
              ),
            ),
            Divider(color: p.border, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: p.gradientSakura,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      avatarInitial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isGuest ? role : email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!isGuest) ...[
                          const SizedBox(height: 2),
                          Text(
                            role,
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _DrawerNavTile(
              palette: p,
              icon: Icons.list_alt_rounded,
              label: s.s('drawer.nav.plans'),
              onTap: () {
                Navigator.of(context).pop();
                context.go('/plans');
              },
            ),
            _DrawerNavTile(
              palette: p,
              icon: Icons.notifications_none_rounded,
              label: s.s('drawer.nav.reminders'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/reminders');
              },
            ),
            _DrawerNavTile(
              palette: p,
              icon: Icons.logout_rounded,
              label: s.s('drawer.signout'),
              destructive: true,
              onTap: () async {
                Navigator.of(context).pop();
                try {
                  await ref.read(authRepositoryProvider).signOut();
                } catch (_) {
                  // Preview / Supabase yok — sessizce yut.
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Drawer'ın 32x32 mor rozeti + 旅 karakteri.
class _DrawerBrandMark extends StatelessWidget {
  const _DrawerBrandMark({required this.palette});
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [palette.accent, palette.fuji],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: const Text(
        '旅',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 18,
          height: 1.0,
        ),
      ),
    );
  }
}

/// Drawer nav satırı — hafif hover, destructive için kırmızımsı ton.
class _DrawerNavTile extends StatelessWidget {
  const _DrawerNavTile({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
  final ViewerPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final Color color = destructive ? p.sunset : p.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight:
                          destructive ? FontWeight.w600 : FontWeight.w500,
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

/// Kompakt uçuş özeti — drawer içi. Gidiş/Dönüş yönlerini tek satırda
/// IATA + saat olarak gösterir.
class _DrawerFlightsMini extends StatelessWidget {
  const _DrawerFlightsMini({required this.trip, required this.palette});
  final Trip trip;
  final ViewerPalette palette;

  static String _iata(FlightLeg l) {
    final ap = l.airport.trim();
    if (ap.isNotEmpty) return ap.toUpperCase();
    final c = l.city.trim();
    if (c.isEmpty) return '—';
    return c.length > 4 ? c.substring(0, 4).toUpperCase() : c.toUpperCase();
  }

  static String _time(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _row({
    required BuildContext context,
    required String label,
    required List<FlightLeg> legs,
  }) {
    if (legs.isEmpty) return const SizedBox.shrink();
    final p = palette;
    final from = legs.first;
    final to = legs.last;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration:
                BoxDecoration(color: p.sakura, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Text(
                  _iata(from),
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _time(from.dateTime),
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Icon(Icons.arrow_forward, size: 10, color: p.sakura),
                Text(
                  _iata(to),
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _time(to.dateTime),
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outbound = trip.flights.outbound;
    final ret = trip.flights.returnLegs;
    if (outbound.isEmpty && ret.isEmpty) return const SizedBox.shrink();
    final p = palette;
    final s = LanguageScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.elevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flight_takeoff, size: 14, color: p.sakura),
              const SizedBox(width: 6),
              Text(
                s.s('viewer.flights'),
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _row(context: context, label: s.s('viewer.flights.outbound'), legs: outbound),
          _row(context: context, label: s.s('viewer.flights.return'), legs: ret),
        ],
      ),
    );
  }
}

/// Drawer içi kompakt konaklama listesi (ilk 3 + "+N daha").
class _DrawerHotelsMini extends StatelessWidget {
  const _DrawerHotelsMini({required this.trip, required this.palette});
  final Trip trip;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    if (trip.hotels.isEmpty) return const SizedBox.shrink();
    final p = palette;
    final s = LanguageScope.of(context);
    final visible = trip.hotels.take(3).toList();
    final extra = trip.hotels.length - visible.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.elevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hotel_outlined, size: 14, color: p.gold),
              const SizedBox(width: 6),
              Text(
                s.s('viewer.hotels'),
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final h in visible)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      h.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (extra > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 12),
              child: Text(
                s.p('viewer.hotels.more', {'n': '$extra'}),
                style: TextStyle(
                  color: p.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Drawer içi 3'lü metrik satırı — gece · şehir · gün.
class _DrawerMetricsMini extends StatelessWidget {
  const _DrawerMetricsMini({
    required this.trip,
    required this.palette,
    required this.dayCount,
  });
  final Trip trip;
  final ViewerPalette palette;
  final int dayCount;

  int get _hotelNights {
    var n = 0;
    for (final h in trip.hotels) {
      final ci = DateTime.tryParse(h.checkIn);
      final co = DateTime.tryParse(h.checkOut);
      if (ci != null && co != null) {
        n += co.difference(ci).inDays.clamp(0, 60);
      }
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = LanguageScope.of(context);
    final nights = _hotelNights;
    final cityCount = trip.preferences.destinations.length;
    final items = <(IconData, String, String)>[
      (Icons.nights_stay_outlined, '$nights', s.s('viewer.metric.nights')),
      (Icons.pin_drop_outlined, '$cityCount', s.s('viewer.metric.cities')),
      (Icons.calendar_month_outlined, '$dayCount', s.s('viewer.metric.days')),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: p.elevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.border),
              ),
              child: Column(
                children: [
                  Icon(items[i].$1, size: 16, color: p.accent),
                  const SizedBox(height: 4),
                  Text(
                    items[i].$2,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[i].$3,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (i < items.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _DrawerActionSpec {
  const _DrawerActionSpec({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Drawer içi aksiyon grid — 4 kolon; her hücre ikon + kısa etiket.
class _DrawerActionGrid extends StatelessWidget {
  const _DrawerActionGrid({required this.actions, required this.palette});
  final List<_DrawerActionSpec> actions;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return LayoutBuilder(
      builder: (_, c) {
        const cols = 4;
        const spacing = 8.0;
        final w = (c.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final a in actions)
              SizedBox(
                width: w,
                height: w,
                child: Material(
                  color: p.elevated,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.of(context).pop();
                      a.onTap();
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(a.icon, size: 22, color: p.accent),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            a.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
