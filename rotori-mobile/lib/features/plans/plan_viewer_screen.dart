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

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';

import '../../core/debug_tools.dart';
import '../../core/l10n.dart';
import '../../core/supabase_client.dart';
import '../../data/language_store.dart';
import '../../data/plans_repository.dart';
import '../../data/reminders_store.dart';
import '../../data/offline_japan_route_matrix.dart';
import '../../data/weather_service.dart';
import '../../domain/city_palette.dart';
import '../../data/google_maps_launcher.dart';
import '../../domain/city_places.dart';
import '../../domain/city_transfers.dart'
    show
        cityTransitionProjectionMatches,
        kShinkansenOfficialUrl,
        lookupTransfer;
import '../../domain/bug_report.dart';
import '../../domain/day_schedule.dart' as sched;
import '../../domain/destination_profiles.dart';
import '../../domain/itinerary_optimizer.dart';
import '../../domain/japanese_phrases_data.dart';
import '../../domain/localized_text.dart';
import '../../domain/place_coords.dart';
import '../../domain/plan_generation.dart' show tripHasFlightInfo;
import '../../domain/plan_schedule_engine.dart';
import '../../domain/ticketed_activity.dart';
import '../../domain/trip_factory.dart' show newTicketId;
import '../../domain/plan_warnings.dart';
import '../../domain/route_execution.dart';
import '../../domain/route_time_bounds.dart';
import '../../domain/route_matrix.dart';
import '../../data/affiliate_links.dart';
import '../../data/tts_service.dart';
import '../../domain/travel_tips_data.dart';
import '../../domain/must_see_suggestions.dart';
import '../../domain/trip_forecast.dart';
import '../../domain/types.dart';
import '../auth/auth_repository.dart';
import '../shared/place_detail_sheet.dart';
import '../shared/ticket_support.dart';
import '../viewer/budget_screen.dart';
import '../viewer/eats_screen.dart';
import '../viewer/experience_guide_screen.dart';
import '../viewer/home_widget_hook.dart';
import '../viewer/offline_translator_card.dart';
import '../viewer/offline_tile_provider.dart';
import '../viewer/pre_departure_checklist_screen.dart';
import '../viewer/reward_map_screen.dart';
import '../viewer/route_map_sheet.dart';
import '../viewer/viewer_theme.dart';
import '../viewer/weather_screen.dart';
import '../../domain/japan_suggestions.dart' show PlaceSuggestion;
import 'plan_providers.dart';
import 'premium_provider.dart';
import 'plan_edit_session.dart';
import 'plan_optimization_controller.dart';
import 'widgets/must_see_card.dart';

// Viewer sandvich (drawer) bileşen ailesi ayrı bir part dosyasında toplanır.
part 'widgets/plan_viewer_drawer.dart';

// ---------------------------------------------------------------------------
// Tarih yardımcıları — dile göre ay/gün dizisi (intl locale'e bağlı DEĞİL).
// ---------------------------------------------------------------------------

/// "1. Gün Cuma" (tr) / "Day 1 Friday" (en). Rozet zaten tarihi gösterdiğinden
/// başlık satırı gün sırası + tam hafta gününü verir.
String _formatDayTitle(String isoDate, int dayNumber, AppLang lang,
    {String? weekdayHint}) {
  final d = DateTime.tryParse(isoDate);
  final weekdays = L10n.weekdaysFor(lang);
  // Tarih varsa kaydedilmiş kısa/eskimiş weekday alanını kullanma; örneğin
  // "Per" yerine her zaman "Perşembe" göster.
  final wd = d != null
      ? weekdays[d.weekday]
      : (weekdayHint?.isNotEmpty == true ? weekdayHint! : '');
  return lang == AppLang.en
      ? 'Day $dayNumber${wd.isNotEmpty ? ' $wd' : ''}'
      : '$dayNumber. Gün${wd.isNotEmpty ? ' $wd' : ''}';
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

/// Dakika (0..1439) → "HH:mm".
String _minutesToTime(int mins) {
  final m = mins.clamp(0, 24 * 60 - 1);
  final h = m ~/ 60;
  final mm = m % 60;
  return '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
}

class _WeatherRouteAdjustment {
  const _WeatherRouteAdjustment({
    required this.profile,
    required this.hintKey,
    this.maximumWalkingMinutes,
  });

  final RouteOptimizationProfile profile;
  final int? maximumWalkingMinutes;
  final String hintKey;
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
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scrollController = ScrollController();
  final _activeDayKey = GlobalKey();
  bool _autoScrolled = false;

  /// Global drag durumu — null = boşta, "itemId" = o item sürükleniyor.
  /// Tüm drop-slot'lar dinleyip drag aktif olduğunda kendini büyütür; böylece
  /// Apple-vari "diğer aktiviteler kayarak yer açar" hissi verilir.
  final ValueNotifier<String?> _dragActiveNotifier =
      ValueNotifier<String?>(null);

  /// Akordiyon davranışı moda göre değişir:
  /// - **View modu (varsayılan aktif gün açık):** ilk açılışta yalnız aktif
  ///   gün açıktır. Kullanıcı okumak istediği güne dokununca o gün
  ///   `_expandedInView` içinde aç/kapa yapılır.
  /// - **Edit modu (varsayılan açık):** ✎ butonuna basınca bütün günler açılır
  ///   (drag/drop için ideal). Kullanıcı bir günü kapatmak isterse
  ///   `_collapsedInEdit`'e girer.
  /// Mod değişiminde her set ilgili mod için resetlenir.
  final Set<int> _expandedInView = <int>{};
  final Set<int> _collapsedInEdit = <int>{};

  /// Düzenleme modu — üst bardaki ✎ simgesine basılınca aktif olur.
  /// Bu modda: aynı gün içinde sıralama, başka güne taşıma ve kaldırma
  /// aksiyonları her item için görünür. Kayıt her mutasyonda anlık yapılır
  /// (`plansRepositoryProvider.save`).
  bool _editMode = false;

  /// Aktif tab — 0: Ana Sayfa, 1: Biletler, 2: Japonca, 3: Rehber.
  int _activeTab = 0;

  /// "✈️ Uçuşunu ekle" kartı ✕ ile kapatıldı mı (bu oturumda) — SharedPreferences
  /// ile kalıcı, planId'ye özel (bkz. initState _loadFlightCardDismissed).
  bool _flightCardDismissed = false;
  bool _mustSeeCardDismissed = false;
  int _flightDrawerExpansionRequest = 0;

  /// Harita tasarımında kullanıcı tarafından seçilen tek gün. `null` iken
  /// takvimdeki gerçek aktif gün kullanılır. Bu yalnızca sunum durumudur;
  /// planın günlerini veya rota verisini değiştirmez.
  int? _selectedMapDayNumber;

  late final PlanEditSession _editSession;
  PlanEditState? _editState;
  Timer? _undoSnackTimer;
  int _planVersion = 0;
  bool _transitionRepairScheduled = false;

  Trip get _trip => _editState?.trip ?? _editSession.current;

  /// Tarih (YYYY-MM-DD) → o günün hava tahmini (o tarihte hangi destinasyondayız
  /// ise oradan). Open-Meteo'dan bir kez çekilir; hata sessiz.
  Map<String, DayForecast> _forecast = const {};

  List<DayPlan> get _sortedDays =>
      [..._trip.days]..sort((a, b) => a.dayNumber.compareTo(b.dayNumber));

  List<TripDestination> get _sortedDestinations => [
        ..._trip.preferences.destinations
      ]..sort((a, b) => a.order.compareTo(b.order));

  @override
  void initState() {
    super.initState();
    final initialDays = [...widget.trip.days]
      ..sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
    final initialActiveDay = _activeDayIndex(initialDays);
    if (initialDays.isNotEmpty && initialActiveDay >= 0) {
      _expandedInView.add(initialActiveDay);
    }
    _editSession = PlanEditSession(
      initialTrip: widget.trip,
      persist: (trip) async {
        try {
          await ref.read(plansRepositoryProvider)?.save(trip);
        } on StateError {
          // Auth-less preview ve widget testinde repository bilinçli yoktur.
        }
      },
      onChanged: (state) {
        if (!mounted) return;
        setState(() {
          _editState = state;
          _planVersion += 1;
        });
        HomeWidgetHook.pushFromTrip(state.trip);
      },
    );
    WidgetsBinding.instance.addObserver(this);
    // İlk frame sonrası: (1) aktif güne oto-kaydır, (2) iOS Home Screen
    // widget'ına "Sıradaki Aktivite" verisini gönder. İki callback bağımsız —
    // sıra önemli değil, hook web'de ve native target yoksa sessizce no-op.
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoScrollToActive());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => HomeWidgetHook.pushFromTrip(_trip),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadForecast());
    _loadFlightCardDismissed();
    _loadMustSeeCardDismissed();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_transitionRepairScheduled) return;
    _transitionRepairScheduled = true;
    final lang = LanguageScope.of(context).lang;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _repairLegacyCityTransitionProjections(lang),
    );
  }

  Future<void> _repairLegacyCityTransitionProjections(AppLang lang) async {
    for (final day in [..._editSession.current.days]) {
      final transition = day.cityTransition;
      if (transition == null ||
          cityTransitionProjectionMatches(day, lang) ||
          !mounted) {
        continue;
      }
      await _editSession.execute(UpdateCityTransition(
        toDayNumber: day.dayNumber,
        fromCity: transition.fromCity,
        toCity: transition.toCity,
        mode: transition.mode,
        lang: lang,
      ));
    }
  }

  String get _flightCardPrefsKey =>
      'viewer:flightCardDismissed:${widget.planId}';

  String get _mustSeeCardPrefsKey =>
      'viewer:mustSeeCardDismissed:${widget.planId}';

  Future<void> _loadFlightCardDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getBool(_flightCardPrefsKey) ?? false;
      if (mounted && dismissed) setState(() => _flightCardDismissed = true);
    } catch (_) {
      // Depolama erişilemezse kart görünmeye devam eder — sorun değil.
    }
  }

  Future<void> _loadMustSeeCardDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getBool(_mustSeeCardPrefsKey) ?? false;
      if (mounted && dismissed) setState(() => _mustSeeCardDismissed = true);
    } catch (_) {
      // Depolama erişilemezse kart görünmeye devam eder — sorun değil.
    }
  }

  Future<void> _openFlightDetails({bool closeDrawer = false}) async {
    if (closeDrawer) Navigator.of(context).pop();
    final updatedTrip = await context.push<Trip>(
      '/plans/${widget.planId}/flights',
    );
    if (!mounted || updatedTrip == null) return;

    _editSession.replaceFromRemote(updatedTrip);
    setState(() {
      _editState = PlanEditState(trip: updatedTrip);
      _flightCardDismissed = true;
      _flightDrawerExpansionRequest += 1;
    });
    HomeWidgetHook.pushFromTrip(updatedTrip);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scaffoldKey.currentState?.openDrawer();
    });
  }

  /// "Bunları da gör" seçimini plana uygular ve kaydeder.
  ///
  /// Yeniden ÜRETİM yok: [addHighlightsToPlan] mevcut öğelere dokunmadan
  /// boşluklara ekler, böylece kullanıcının elle yaptığı düzenlemeler kalır.
  Future<HighlightPlacement> _applyMustSee(
    Trip trip,
    List<PlaceSuggestion> picks,
  ) async {
    final s = LanguageScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = addHighlightsToPlan(trip, picks);

    final repo = ref.read(plansRepositoryProvider);
    if (repo != null) {
      try {
        await repo.saveLocal(trip);
        unawaited(repo.save(trip).catchError((_) => null));
      } catch (_) {
        // Kaydedilemezse bile ekranda görünür; bir sonraki kayıtta senkronlanır.
      }
    }
    ref.read(draftTripProvider.notifier).state = trip;
    if (mounted) setState(() {});

    final added = result.placed.length;
    final missed = result.unplaced.length;
    messenger.showSnackBar(SnackBar(
      content: Text(
        added == 0
            ? s.s('viewer.mustSee.none')
            : missed == 0
                ? s.p('viewer.mustSee.added', {'n': '$added'})
                : s.p(
                    'viewer.mustSee.partial', {'n': '$added', 'm': '$missed'}),
      ),
    ));
    return result;
  }

  /// Her destinasyon için Open-Meteo'dan tahmin çek ve gün↔şehir eşleştirmesini
  /// paylaşılan [buildRouteForecast]'e yaptır — hava ekranı da aynı fonksiyonu
  /// kullanır, böylece gün rozeti ile liste birbirinden sapamaz.
  /// Ağ hatası sessizdir; o destinasyonun günleri rozetsiz kalır.
  Future<void> _loadForecast() async {
    final dests = _sortedDestinations;
    if (dests.isEmpty) return;
    final byDestination = <String, List<DayForecast>>{};
    for (final d in distinctForecastDestinations(dests)) {
      try {
        byDestination[d.id] = await fetchForecast(d.lat!, d.lng!);
      } catch (_) {
        // Ağ hatası — sessizce geç, hava rozeti o gün için gösterilmez.
      }
    }
    if (!mounted || byDestination.isEmpty) return;
    final result = routeForecastByDate(buildRouteForecast(
      days: _trip.days,
      destinations: dests,
      forecastsByDestinationId: byDestination,
    ));
    if (result.isEmpty) return;
    setState(() => _forecast = result);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Uygulama arka plandan öne alındığında widget verisini tazele — kullanıcı
    // dışarıda saatlerce beklemiş olabilir; "sıradaki" değişmiş olabilir.
    if (state == AppLifecycleState.resumed) {
      HomeWidgetHook.pushFromTrip(_trip);
    }
  }

  void _autoScrollToActive() {
    if (_autoScrolled || !mounted) return;
    // Aktif gün zaten ilk gün ise kaydırma YAPMA: listenin başı zaten görünür
    // ve kaydırmak, gün akışının üstündeki kartları ("✈️ Uçuşunu ekle" gibi)
    // kullanıcı hiç görmeden ekranın dışına iter.
    if (_activeDayIndex(_sortedDays) <= 0) {
      _autoScrolled = true;
      return;
    }
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
    _undoSnackTimer?.cancel();
    _editSession.dispose();
    _scrollController.dispose();
    _dragActiveNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ViewerPalette.of(context);
    final template = ref.watch(viewerTemplateProvider);
    final trip = _trip;
    final days = _sortedDays;
    final activeIndex = _activeDayIndex(days);
    final activeDay = days.isEmpty ? null : days[activeIndex];
    final requestedMapIndex = days.indexWhere(
      (candidate) => candidate.dayNumber == _selectedMapDayNumber,
    );
    final selectedMapIndex = days.isEmpty
        ? -1
        : requestedMapIndex >= 0
            ? requestedMapIndex
            : activeIndex;
    final selectedMapDay = selectedMapIndex < 0 ? null : days[selectedMapIndex];
    final isMapPresentation = template == ViewerTemplateId.mapFocus;

    // Minimalize edilmiş viewer: sadece üst bar + doğrudan gün akışı. Uçuş
    // özeti, konaklama, metrikler ve tüm aksiyon butonları drawer içinde.
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: palette.bg,
      drawer: _ViewerDrawer(
        palette: palette,
        trip: trip,
        dayCount: days.length,
        flightExpansionRequest: _flightDrawerExpansionRequest,
        onOpenFlights: () => _openFlightDetails(closeDrawer: true),
        onOpenThemePicker: _openThemePicker,
        onOpenBudget: _openBudget,
        onOpenPrep: _openPrep,
        onOpenWeather: _openWeather,
        onOpenFoodGuide: _openEats,
        onOpenExperienceGuide: _openExperienceGuide,
        onReportBug: () => _openBugReport(trip),
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
              child: IndexedStack(
                index: _activeTab,
                children: [
                  // Tab 0 — Ana Sayfa: gün akışı.
                  ListView(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      isMapPresentation ? 0 : 16,
                      isMapPresentation ? 0 : 12,
                      isMapPresentation ? 0 : 16,
                      40,
                    ),
                    children: [
                      if (activeDay != null &&
                          !_editMode &&
                          template == ViewerTemplateId.journeyProgress)
                        _JourneyProgressHero(
                          day: activeDay,
                          palette: palette,
                          onOpenItem: (item) => _openItem(
                            item,
                            getDestinationForDate(
                              _sortedDestinations,
                              activeDay.date,
                            ),
                          ),
                        ),
                      if (selectedMapDay != null &&
                          template == ViewerTemplateId.mapFocus)
                        _MapFocusHero(
                          trip: trip,
                          day: selectedMapDay,
                          days: days,
                          palette: palette,
                          onSelectDay: (candidate) {
                            final index = days.indexWhere(
                              (d) => d.dayNumber == candidate.dayNumber,
                            );
                            if (index < 0) return;
                            setState(() {
                              _selectedMapDayNumber = candidate.dayNumber;
                              _expandedInView
                                ..clear()
                                ..add(index);
                            });
                          },
                          onOpenMap: _openDayMap,
                        ),
                      if (template != ViewerTemplateId.mapFocus &&
                          !tripHasFlightInfo(trip) &&
                          !_flightCardDismissed)
                        _AddFlightCard(
                          palette: palette,
                          onOpen: _openFlightDetails,
                          onDismiss: () {
                            setState(() => _flightCardDismissed = true);
                            SharedPreferences.getInstance().then(
                              (p) => p.setBool(_flightCardPrefsKey, true),
                            );
                          },
                        ),
                      if (template != ViewerTemplateId.mapFocus &&
                          !_mustSeeCardDismissed &&
                          days.isNotEmpty)
                        MustSeeCard(
                          palette: palette,
                          trip: trip,
                          onAdd: (picks) => _applyMustSee(trip, picks),
                          onDismiss: () {
                            setState(() => _mustSeeCardDismissed = true);
                            SharedPreferences.getInstance().then(
                              (p) => p.setBool(_mustSeeCardPrefsKey, true),
                            );
                          },
                        ),
                      if (days.isEmpty)
                        _EmptyDaysCard(palette: palette)
                      else
                        for (var i = 0; i < days.length; i++) ...[
                          if (template != ViewerTemplateId.mapFocus ||
                              i == selectedMapIndex)
                            _DayCard(
                              key: isMapPresentation
                                  ? ValueKey(
                                      'viewer-map-route-day-${days[i].dayNumber}',
                                    )
                                  : i == activeIndex
                                      ? _activeDayKey
                                      : null,
                              day: days[i],
                              palette: palette,
                              template: template,
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
                              // Hava CTA'sı yalnız gerçekten gerekliyse ve
                              // tahmin kesinleşmiş pencerede ise yanar.
                              canOptimizeForWeather:
                                  _shouldOfferWeatherOptimization(
                                days[i],
                                _forecast[days[i].date],
                              ),
                              isPast: i < activeIndex,
                              isActive: template == ViewerTemplateId.mapFocus
                                  ? i == selectedMapIndex
                                  : i == activeIndex,
                              expanded: template == ViewerTemplateId.mapFocus
                                  ? i == selectedMapIndex
                                  : _editMode
                                      ? !_collapsedInEdit.contains(i)
                                      : _expandedInView.contains(i),
                              onToggleExpand: () => setState(() {
                                if (_editMode) {
                                  if (!_collapsedInEdit.remove(i)) {
                                    _collapsedInEdit.add(i);
                                  }
                                } else {
                                  if (!_expandedInView.remove(i)) {
                                    _expandedInView.add(i);
                                  }
                                }
                              }),
                              editMode: _editMode,
                              allDays: days,
                              onOpenItem: _openItem,
                              onOpenMap: _openDayMap,
                              isPremium: ref.watch(premiumProvider),
                              onOptimizeRoute: () => _openRouteOptimization(
                                days[i],
                                getDestinationForDate(
                                  _sortedDestinations,
                                  days[i].date,
                                ),
                              ),
                              onOptimizeWeatherRoute:
                                  (day, destination, forecast) =>
                                      _openRouteOptimization(
                                day,
                                destination,
                                forecast: forecast,
                                useWeatherAdjustment: true,
                              ),
                              onDropItem: _dropActivity,
                              onDeleteItem: _deleteItem,
                              onEditItemTime: _editItemTime,
                              onToggleItemLock: _toggleItemLock,
                              onAddItem: _addItemToDay,
                              onEditDay: _editDay,
                              onMoveDay: _moveDay,
                              onDragUpdate: _autoScrollDuringDrag,
                              dragActive: _dragActiveNotifier,
                            ),
                          if (template != ViewerTemplateId.mapFocus &&
                              i < days.length - 1)
                            _cityTransitionBetween(
                                days[i], days[i + 1], palette),
                        ],
                    ],
                  ),
                  // Tab 1 — Biletler.
                  _TabTicketsView(
                    trip: trip,
                    palette: palette,
                    onAddTicket: () => _openTicketEditor(),
                    onEditTicket: (ticket) =>
                        _openTicketEditor(existing: ticket),
                  ),
                  // Tab 2 — Japonca.
                  _TabPhrasesView(
                    palette: palette,
                    lang: ref.watch(appLangProvider),
                    isPremium: ref.watch(premiumProvider),
                  ),
                  // Tab 3 — Rehber.
                  _TabMustKnowView(
                    palette: palette,
                    lang: ref.watch(appLangProvider),
                    trip: trip,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _ViewerQuickNav(
        palette: palette,
        activeTab: _activeTab,
        onTabChanged: (tab) => setState(() => _activeTab = tab),
        onOpenExplore: _openExplore,
      ),
    );
  }

  /// Bir gün öğesi için yer detay popup'ını açar — bilet arama + ekleme
  /// callback'lerini stateful gövdeden geçirir (persistence burada kalır).
  void _openItem(TimelineItem item, TripDestination? dest) {
    final existing = _trip.tickets
        .where((t) => t.linkedActivityId == item.id || t.label == item.title)
        .cast<Ticket?>()
        .firstWhere((_) => true, orElse: () => null);
    showPlaceDetailSheet(
      context: context,
      item: item,
      city: dest?.city ?? '',
      countryCode: dest?.countryCode,
      existingTicket: existing,
      onAddTicket: (ticket) async {
        final defaults = ticketedActivityDefaultsForTitle(item.title);
        final enriched = Ticket.fromJson({
          ...ticket.toJson(),
          'linkedActivityId': item.id,
          'visitDate': ticket.visitDate ?? _dayContaining(item.id)?.date,
          'entryTime': ticket.entryTime ?? item.time ?? item.scheduledTime,
          'durationMin': ticket.durationMin ??
              item.durationMin ??
              defaults.durationMinutes,
          'arrivalBufferMin': ticket.arrivalBufferMin ??
              item.arrivalBufferMin ??
              defaults.arrivalBufferMinutes,
        });
        return _applyEdit(
          AttachTicketToActivity(activityId: item.id, ticket: enriched),
          successMessage:
              LanguageScope.of(context).s('viewer.edit.ticketAttachedSnack'),
        );
      },
    );
  }

  DayPlan? _dayContaining(String activityId) {
    for (final day in _trip.days) {
      if (day.items.any((item) => item.id == activityId)) return day;
    }
    return null;
  }

  Future<bool> _openTicketEditor({
    Ticket? existing,
    DayPlan? transitionDay,
    String? fromCity,
    String? toCity,
    String? mode,
  }) async {
    final s = LanguageScope.of(context);
    final palette = ViewerPalette.of(context);
    final isTransition = transitionDay != null;
    final draft = await showDialog<_TicketEditorDraft>(
      context: context,
      builder: (_) => _TicketEditorDialog(
        palette: palette,
        title: existing == null
            ? s.s('viewer.ticketEditor.addTitle')
            : s.s('viewer.ticketEditor.editTitle'),
        labelText: s.s('viewer.ticketEditor.label'),
        urlText: s.s('viewer.ticketEditor.url'),
        purchasedText: s.s('viewer.ticketEditor.purchased'),
        cancelText: s.s('routeOptimization.cancel'),
        saveText: s.s('viewer.ticketEditor.save'),
        initialLabel: existing?.label ??
            (isTransition ? '${fromCity ?? ''} → ${toCity ?? ''}' : ''),
        initialUrl: existing?.url ?? '',
        initialPurchased: existing?.purchased ?? false,
      ),
    );
    if (draft == null || !mounted) return false;

    final ticketMode = mode ?? transitionDay?.cityTransition?.mode;
    final ticket = Ticket(
      id: existing?.id ??
          'ticket-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      kind: existing?.kind ?? _ticketKindForTransitionMode(ticketMode),
      label: draft.label,
      purchased: draft.purchased,
      visitDate: existing?.visitDate ?? transitionDay?.date,
      bookingOpens: existing?.bookingOpens,
      url: draft.url.isEmpty ? null : draft.url,
      emoji: existing?.emoji ?? _cityTransitionEmoji(ticketMode ?? 'train'),
      imageDataUrl: existing?.imageDataUrl,
      scannedText: existing?.scannedText,
      linkedTransitionDayNumber:
          existing?.linkedTransitionDayNumber ?? transitionDay?.dayNumber,
      linkedActivityId: existing?.linkedActivityId,
      entryTime: existing?.entryTime,
      durationMin: existing?.durationMin,
      arrivalBufferMin: existing?.arrivalBufferMin,
    );
    final result = await _editSession.execute(
      UpsertTicket(
        ticket: ticket,
        transitionDayNumber: transitionDay?.dayNumber,
      ),
    );
    if (!result.isSuccess && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.s('viewer.ticketEditor.saveFailed'))),
      );
    }
    return result.isSuccess;
  }

  Future<void> _openBugReport(Trip trip) async {
    final s = LanguageScope.of(context);
    final palette = ViewerPalette.of(context);
    final messageController = TextEditingController();
    final emailController = TextEditingController(
      text: ref.read(currentUserProvider)?.email ?? '',
    );
    var category = BugReportCategory.planning;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: palette.card,
          title: Text(
            s.s('bugReport.title'),
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s.s('bugReport.body'),
                  style: TextStyle(color: palette.textSecondary),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<BugReportCategory>(
                  initialValue: category,
                  decoration: InputDecoration(
                    labelText: s.s('bugReport.category'),
                  ),
                  items: [
                    for (final value in BugReportCategory.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(s.s('bugReport.category.${value.name}')),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => category = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: messageController,
                  maxLines: 5,
                  maxLength: 4000,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: s.s('bugReport.message'),
                    hintText: s.s('bugReport.messageHint'),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: s.s('bugReport.emailOptional'),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  s.s('bugReport.privacy'),
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('viewer-top-status-bar'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(s.s('common.cancel')),
            ),
            FilledButton(
              onPressed: messageController.text.trim().length < 3
                  ? null
                  : () => Navigator.of(dialogContext).pop(true),
              child: Text(s.s('bugReport.send')),
            ),
          ],
        ),
      ),
    );
    final message = messageController.text.trim();
    final email = emailController.text.trim();
    messageController.dispose();
    emailController.dispose();
    if (submitted != true || message.length < 3 || !mounted) return;

    final lang = ref.read(appLangProvider);
    final activeDay = _activeDayIndex(_sortedDays);
    final report = BugReport(
      message: message,
      category: category,
      planId: widget.planId,
      contactEmail: email.isEmpty ? null : email,
      context: BugReport.contextForTrip(
        trip: trip,
        planId: widget.planId,
        appVersion: '1.0.0+1',
        platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
        locale: lang.code,
        activeDay: activeDay >= 0 && activeDay < _sortedDays.length
            ? _sortedDays[activeDay].dayNumber
            : null,
      ),
    );
    try {
      final repo = ref.read(plansRepositoryProvider);
      if (repo == null) throw StateError('bug-report requires a session');
      await repo.submitBugReport(report);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.s('bugReport.success'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.s('bugReport.error'))),
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // Edit mode — mutation helpers (her biri anlık kaydeder + UI'yı tazeler).
  // -------------------------------------------------------------------------

  Future<bool> _applyEdit(
    PlanEditCommand command, {
    String? successMessage,
  }) async {
    final result = await _editSession.execute(command);
    if (!mounted) return result.isSuccess;
    final s = LanguageScope.of(context);
    if (!result.isSuccess) {
      final failure = result.failure!;
      final first = _findActivity(failure.conflictingActivityId)?.title;
      final second = _findActivity(failure.activityId)?.title;
      final message =
          failure.overlapMinutes != null && first != null && second != null
              ? s.p('viewer.edit.conflict', {
                  'first': first,
                  'second': second,
                  'minutes': '${failure.overlapMinutes}',
                })
              : failure.code == PlanEditFailureCode.lockedActivity
                  ? s.s('viewer.edit.locked')
                  : _editState?.saveFailed == true
                      ? s.s('viewer.edit.saveFailed')
                      : s.s('viewer.edit.invalidChange');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      await HapticFeedback.mediumImpact();
      return false;
    }
    if (!mounted) return true;
    final messenger = ScaffoldMessenger.of(context);
    _undoSnackTimer?.cancel();
    messenger.removeCurrentSnackBar();
    Timer? expiryTimer;
    final controller = messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text(successMessage ?? s.s('viewer.edit.saved')),
        action: SnackBarAction(
          label: s.s('viewer.edit.undo'),
          onPressed: () async {
            _undoSnackTimer?.cancel();
            _undoSnackTimer = null;
            await _editSession.undo();
          },
        ),
      ),
    );
    expiryTimer = Timer(const Duration(seconds: 5), () {
      controller.close();
      if (identical(_undoSnackTimer, expiryTimer)) {
        _undoSnackTimer = null;
      }
    });
    _undoSnackTimer = expiryTimer;
    unawaited(HapticFeedback.lightImpact());
    return true;
  }

  TimelineItem? _findActivity(String? id) {
    if (id == null) return null;
    for (final day in _trip.days) {
      for (final item in day.items) {
        if (item.id == id) return item;
      }
    }
    return null;
  }

  /// Drag sırasında ekran kenarına yaklaşınca çok yumuşak kaydırma (Apple
  /// standardı). Yalnızca son 56 px'te tetiklenir; hız kenara ne kadar
  /// yakınsan o kadar büyür (max 6 px/frame). Kullanıcı ortada gezinirken
  /// hiçbir hareket olmaz.
  void _autoScrollDuringDrag(DragUpdateDetails details) {
    if (!_scrollController.hasClients) return;
    final height = MediaQuery.sizeOf(context).height;
    const edge = 56.0;
    const maxDelta = 6.0;
    final dy = details.globalPosition.dy;
    double delta = 0;
    if (dy < edge) {
      final t = ((edge - dy) / edge).clamp(0.0, 1.0);
      delta = -maxDelta * t;
    } else if (dy > height - edge) {
      final t = ((dy - (height - edge)) / edge).clamp(0.0, 1.0);
      delta = maxDelta * t;
    }
    if (delta.abs() < 0.5) return;
    final position = _scrollController.position;
    final target = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _scrollController.jumpTo(target);
  }

  /// Aynı gün içinde item sırasını değiştirir. Popup menü kaldırıldıktan sonra
  /// UI'dan çağrılmıyor — drag-drop `_dropActivity` üzerinden geçiyor. Domain
  /// sözleşmesi tutulsun diye korunuyor.
  // ignore: unused_element
  void _moveWithinDay(DayPlan day, int oldIdx, int newIdx) {
    if (newIdx < 0 || newIdx >= day.items.length || oldIdx == newIdx) return;
    final item = day.items[oldIdx];
    _applyEdit(MoveActivityWithinDay(
      dayNumber: day.dayNumber,
      activityId: item.id,
      targetIndex: newIdx,
    ));
  }

  /// Bir aktivitenin gün + saat değişimini tek bottom-sheet üzerinden yönetir.
  ///
  /// - Item bileti girilmişse (Trip.tickets.label eşleşiyorsa) önce
  ///   "biletli aktiviteyi düzenlemek üzeresin" uyarısı gösterilir; kullanıcı
  ///   iptal ederse hiçbir şey değişmez.
  /// - Aynı gün + yeni saat → `applyManualTimeEdit` (diğer saatler korunur).
  /// - Farklı gün seçilirse item hedef güne "insertItemSorted" ile eklenir;
  ///   kullanıcı saati elle değiştirmediyse hedef güne uygun otomatik saat
  ///   önerilir (son durak + 90 dk, boşsa 09:00).
  /// Kullanıcı kilidini aç/kapa.
  ///
  /// Kilitli durak rota yeniden kurulurken/optimize edilirken gününü ve
  /// saatini korur — kullanıcı bileti almış olabilir. Sistem kilitleri
  /// (uçuş, otel, saatli giriş) buradan değiştirilemez.
  Future<void> _toggleItemLock(DayPlan day, TimelineItem item) async {
    final s = LanguageScope.of(context);
    if (!item.canUserToggleLock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.s('viewer.edit.pinSystemLocked'))),
      );
      return;
    }
    final shouldLock = !item.isUserPinned;
    await _applyEdit(
      SetActivityUserLock(
        dayNumber: day.dayNumber,
        activityId: item.id,
        locked: shouldLock,
        reason: s.s('viewer.edit.pinReason'),
      ),
      successMessage:
          shouldLock ? s.s('viewer.edit.pinned') : s.s('viewer.edit.unpinned'),
    );
  }

  Future<void> _editItemTime(DayPlan day, int index) async {
    if (index < 0 || index >= day.items.length) return;
    final it = day.items[index];
    final palette = ref.read(viewerPaletteProvider);
    final s = LanguageScope.of(context);

    // Bilet uyarısı — kullanıcı bileti girdiği bir aktiviteyi düzenliyorsa
    // slot uyumu için onay iste.
    if (it.isFixed || !it.canChangeTime) {
      await _applyEdit(UpdateActivityTime(
        dayNumber: day.dayNumber,
        activityId: it.id,
        startMinutes: _timeToMinutes(it.time ?? it.scheduledTime) ?? 9 * 60,
      ));
      return;
    }
    final hasTicketRecord = _trip.tickets.any((t) => t.label == it.title);
    if (hasTicketRecord || requiresTicket(it)) {
      if (hasTicketRecord) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(s.s('viewer.edit.ticketConfirmTitle')),
            content: Text(s.p('viewer.edit.ticketConfirmBody', {
              'title': it.title,
            })),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(s.s('viewer.edit.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(s.s('viewer.edit.ticketConfirmContinue')),
              ),
            ],
          ),
        );
        if (ok != true) return;
      }
    }

    if (!mounted) return;
    final result = await showModalBottomSheet<_EditItemResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditItemDayTimeSheet(
        palette: palette,
        trip: _trip,
        item: it,
        currentDay: day,
        allDays: _trip.days,
      ),
    );
    if (result == null) return;

    final targetDay = result.targetDay;
    final newMin = result.timeMinutes;
    if (identical(targetDay, day)) {
      await _applyEdit(UpdateActivitySchedule(
        dayNumber: day.dayNumber,
        activityId: it.id,
        startMinutes: newMin,
        durationMinutes: result.durationMinutes,
      ));
    } else {
      final moved = await _applyEdit(MoveActivityToDay(
        sourceDayNumber: day.dayNumber,
        activityId: it.id,
        targetDayNumber: targetDay.dayNumber,
        startMinutes: newMin,
        durationMinutes: result.durationMinutes,
      ));
      if (!moved) return;
    }
  }

  /// Bir güne yeni durak ekler — şehir bazlı autocomplete + saat girişli sheet.
  Future<void> _addItemToDay(DayPlan day, TripDestination? dest) async {
    // Varsayılan saat: son durağın saati + 90 dk, yoksa 09:00.
    int defaultMin = 9 * 60;
    if (day.items.isNotEmpty) {
      final last =
          _timeToMinutes(day.items.last.time ?? day.items.last.scheduledTime);
      if (last != null) defaultMin = (last + 90).clamp(0, 24 * 60 - 1);
    }
    final result = await showModalBottomSheet<_AddPlaceResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddPlaceSheet(
        palette: ref.read(viewerPaletteProvider),
        city: _cityDataForDest(dest),
        cityLabel: dest?.city ?? '',
        defaultTime: _minutesToTime(defaultMin),
      ),
    );
    if (result == null) return;
    final item = TimelineItem(
      id: 'u-${DateTime.now().microsecondsSinceEpoch}',
      title: result.title,
      time: result.time,
      scheduledTime: result.time,
      kind: result.kind,
      lat: result.lat,
      lng: result.lng,
      durationMin: result.durationMin,
      arrivalBufferMin: result.hasTicket ? result.arrivalBufferMin : null,
    );
    if (!mounted) return;
    final s = LanguageScope.of(context);
    final addedMessage = result.hasTicket
        ? s.s('viewer.edit.ticketAddedSnack')
        : s.p('viewer.edit.addedSnack', {'title': item.title});
    final command = result.hasTicket
        ? AddTicketedActivity(
            dayNumber: day.dayNumber,
            activity: item,
            ticket: Ticket(
              id: newTicketId(),
              kind: TicketKind.attraction.name,
              label: item.title,
              purchased: true,
              visitDate: day.date,
              entryTime: result.time,
              durationMin: result.durationMin,
              arrivalBufferMin: result.arrivalBufferMin,
              linkedActivityId: item.id,
              emoji: '🎫',
            ),
          )
        : AddActivity(dayNumber: day.dayNumber, activity: item);
    final added = await _applyEdit(
      command,
      successMessage: addedMessage,
    );
    if (!added) return;
    if (result.hasTicket && ref.read(premiumProvider) && mounted) {
      final updatedDay = _trip.days.firstWhere(
        (candidate) => candidate.dayNumber == day.dayNumber,
      );
      if (updatedDay.items.length >= 2) {
        await _openRouteOptimization(updatedDay, dest);
      }
    }
  }

  /// Bir destinasyonun şehrini küratörlü [CityData]'ya eşler (autocomplete için).
  CityData? _cityDataForDest(TripDestination? dest) {
    if (dest == null) return null;
    final city = dest.city.toLowerCase();
    for (final c in kCityData) {
      if (c.aliases.any((a) => city.contains(a))) return c;
    }
    return null;
  }

  /// Menüden gün seçildikten sonra kullanılan uygun-saat sunumu. Popup menü
  /// kaldırıldıktan sonra çağrılmıyor; drag-drop `_dropActivity` üzerinden
  /// yürüyor. Domain sözleşmesi korunuyor.
  // ignore: unused_element
  void _moveItemToDay(DayPlan sourceDay, int itemIdx, DayPlan targetDay) {
    if (identical(sourceDay, targetDay)) return;
    if (itemIdx < 0 || itemIdx >= sourceDay.items.length) return;
    final item = sourceDay.items[itemIdx];
    () async {
      final result = await showModalBottomSheet<_EditItemResult>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _EditItemDayTimeSheet(
          palette: ref.read(viewerPaletteProvider),
          trip: _trip,
          item: item,
          currentDay: sourceDay,
          allDays: _trip.days,
          initialTargetDay: targetDay,
        ),
      );
      if (result == null || !mounted) return;
      final s = LanguageScope.of(context);
      final command = result.targetDay.dayNumber == sourceDay.dayNumber
          ? UpdateActivitySchedule(
              dayNumber: sourceDay.dayNumber,
              activityId: item.id,
              startMinutes: result.timeMinutes,
              durationMinutes: result.durationMinutes,
            )
          : MoveActivityToDay(
              sourceDayNumber: sourceDay.dayNumber,
              activityId: item.id,
              targetDayNumber: result.targetDay.dayNumber,
              startMinutes: result.timeMinutes,
              durationMinutes: result.durationMinutes,
            );
      await _applyEdit(
        command,
        successMessage: s.p('viewer.edit.movedSnack', {
          'title': item.title,
          'day': '${result.targetDay.dayNumber}',
        }),
      );
    }();
  }

  /// Drag/drop taşımasını modal açmadan, bırakılan satır aralığına uygular.
  /// Saat komşu aktivitelerin uygun boşluğunun ortasına yerleştirilir; yeterli
  /// boşluk yoksa yalnızca çakışan sonraki aktiviteler ileri kaydırılır.
  Future<void> _dropActivity(
    DayPlan sourceSnapshot,
    String itemId,
    DayPlan targetSnapshot,
    int rawTargetIndex,
  ) async {
    final sourceDay = _trip.days.firstWhere(
      (day) => day.dayNumber == sourceSnapshot.dayNumber,
      orElse: () => sourceSnapshot,
    );
    final targetDay = _trip.days.firstWhere(
      (day) => day.dayNumber == targetSnapshot.dayNumber,
      orElse: () => targetSnapshot,
    );
    final sourceIndex = sourceDay.items.indexWhere((item) => item.id == itemId);
    if (sourceIndex < 0) return;
    final sameDay = sourceDay.dayNumber == targetDay.dayNumber;
    var targetIndex = rawTargetIndex;
    if (sameDay && targetIndex > sourceIndex) targetIndex -= 1;
    final maxIndex =
        sameDay ? (targetDay.items.length - 1) : targetDay.items.length;
    targetIndex = targetIndex.clamp(0, maxIndex < 0 ? 0 : maxIndex);
    if (sameDay && targetIndex == sourceIndex) return;

    const engine = PlanScheduleEngine();
    final startMinutes = engine.suggestedStartMinutesForInsertion(
      _trip,
      sourceDayNumber: sourceDay.dayNumber,
      activityId: itemId,
      targetDayNumber: targetDay.dayNumber,
      targetIndex: targetIndex,
    );
    final item = sourceDay.items[sourceIndex];
    final command = sameDay
        ? MoveActivityWithinDay(
            dayNumber: sourceDay.dayNumber,
            activityId: itemId,
            targetIndex: targetIndex,
            startMinutes: startMinutes,
            preserveExistingTimes: true,
          )
        : MoveActivityToDay(
            sourceDayNumber: sourceDay.dayNumber,
            activityId: itemId,
            targetDayNumber: targetDay.dayNumber,
            targetIndex: targetIndex,
            startMinutes: startMinutes,
            durationMinutes: item.durationMin,
            preserveExistingTimes: true,
          );
    final s = LanguageScope.of(context);
    final moved = await _applyEdit(
      command,
      successMessage: s.p('viewer.edit.droppedSnack', {
        'title': item.title,
        'day': '${targetDay.dayNumber}',
        'time': _minutesToTime(startMinutes),
      }),
    );
    if (!moved || !mounted) return;
    final expandedIndex =
        _sortedDays.indexWhere((day) => day.dayNumber == targetDay.dayNumber);
    if (expandedIndex >= 0) {
      setState(() {
        // Drag/menü ile hedef güne bir aktivite bırakıldığında o gün otomatik
        // açılsın — hangi moddaysak ilgili sette güncelle.
        if (_editMode) {
          _collapsedInEdit.remove(expandedIndex);
        } else {
          _expandedInView.add(expandedIndex);
        }
      });
    }
  }

  /// Item'ı plandan kaldırır. Undo ile geri alınabilir (SnackBar action).
  void _deleteItem(DayPlan day, int itemIdx) {
    if (itemIdx < 0 || itemIdx >= day.items.length) return;
    final removed = day.items[itemIdx];
    final s = LanguageScope.of(context);
    _applyEdit(
      DeleteActivity(dayNumber: day.dayNumber, activityId: removed.id),
      successMessage: s.p('viewer.edit.deletedSnack', {'title': removed.title}),
    );
  }

  Future<void> _editDay(DayPlan day) async {
    final s = LanguageScope.of(context);
    final titleController = TextEditingController(text: day.theme);
    var selectedDate = DateTime.tryParse(day.date) ?? DateTime.now();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(s.s('viewer.edit.editDay')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: s.s('viewer.edit.dayTitle'),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.s('viewer.edit.dayDate')),
                subtitle: Text(
                  '${selectedDate.year.toString().padLeft(4, '0')}-'
                  '${selectedDate.month.toString().padLeft(2, '0')}-'
                  '${selectedDate.day.toString().padLeft(2, '0')}',
                ),
                trailing: const Icon(Icons.calendar_month_outlined),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(s.s('viewer.edit.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(s.s('viewer.edit.save')),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await _applyEdit(UpdateDayDetails(
        dayNumber: day.dayNumber,
        title: titleController.text,
        date: '${selectedDate.year.toString().padLeft(4, '0')}-'
            '${selectedDate.month.toString().padLeft(2, '0')}-'
            '${selectedDate.day.toString().padLeft(2, '0')}',
      ));
    }
    titleController.dispose();
  }

  void _moveDay(DayPlan day, int offset) {
    final days = _sortedDays;
    final oldIndex =
        days.indexWhere((candidate) => candidate.dayNumber == day.dayNumber);
    final newIndex = oldIndex + offset;
    if (oldIndex < 0 || newIndex < 0 || newIndex >= days.length) return;
    _applyEdit(ReorderDays(oldIndex: oldIndex, newIndex: newIndex));
  }

  void _toggleEditMode() {
    setState(() {
      _editMode = !_editMode;
      // Mod değişince kullanıcı toggle'ları resetlenir; her mod kendi
      // varsayılanına döner. View: aktif gün açık, edit: hepsi açık.
      _expandedInView.clear();
      _collapsedInEdit.clear();
      if (!_editMode) {
        final activeIndex = _activeDayIndex(_sortedDays);
        if (activeIndex >= 0) {
          _expandedInView.add(activeIndex);
        }
      }
    });
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

  /// Bütçe & harcama panelini açar (gün/kategori toplamları, JPY→TL çevirici).
  void _openBudget() {
    final palette = ref.read(viewerPaletteProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: palette.toThemeData(),
          child: ViewerPaletteScope(
            palette: palette,
            child: BudgetScreen(trip: _trip),
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
            child: PreDepartureChecklistScreen(trip: _trip),
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
            child: WeatherScreen(trip: _trip),
          ),
        ),
      ),
    );
  }

  /// Rotori Eats — restoranlar (helal/vejetaryen filtre), bütçe ve diyet.
  void _openEats() {
    final palette = ref.read(viewerPaletteProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: palette.toThemeData(),
          child: ViewerPaletteScope(
            palette: palette,
            child: EatsScreen(trip: _trip),
          ),
        ),
      ),
    );
  }

  /// İlk kez gidenler için USJ, Tokyo Disney ve teamLab bilet/gün rehberi.
  Future<void> _openExperienceGuide() async {
    final palette = ref.read(viewerPaletteProvider);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: palette.toThemeData(),
          child: ViewerPaletteScope(
            palette: palette,
            // Trip geçilir ki detayda "Plana ekle" çalışsın; dönüşte plan
            // değişmiş olabilir, o yüzden setState ile tazeleniyor.
            child: ExperienceGuideScreen(trip: _trip),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Planın şehirlerini, yakın yerleri ve kazanılan keşifleri haritada açar.
  void _openExplore() {
    final palette = ref.read(viewerPaletteProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: palette.toThemeData(),
          child: ViewerPaletteScope(
            palette: palette,
            child: RewardMapScreen(trip: _trip),
          ),
        ),
      ),
    );
  }

  /// "Haritada gör" — günün rotasını sade (CartoDB) bir zemin üzerinde,
  /// duraklar arasında sırayla çizilen animasyonlu bir çizgiyle gösteren modal
  /// sayfayı açar. Turn-by-turn navigasyon isteyen kullanıcı için sheet'in
  /// içindeki "Yol tarifi" butonu rotayı Google Maps'e taşır — böylece hem
  /// okunur bir rota önizlemesi hem de gerçek navigasyon tek yerde.
  Future<void> _openDayMap(DayPlan day) {
    return showRouteMapSheet(context: context, trip: _trip, day: day);
  }

  /// Tüm günlerin rotasını sırayla optimize et. Her uygun gün için mevcut
  /// per-day bottom sheet'ini açar; kullanıcı Uygula ya da Kapat der. Sheet
  /// kapandıktan sonra bir sonraki güne geçer. İki'den az durağı olan günler
  /// sessizce atlanır.
  Future<void> _openRouteOptimization(
    DayPlan day,
    TripDestination? destination, {
    DayForecast? forecast,
    bool useWeatherAdjustment = false,
  }) async {
    final s = LanguageScope.of(context);
    if (day.items.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.s('routeOptimization.needTwoStops'))),
      );
      return;
    }

    final cityData = cityDataForKey(destination?.city);
    final centerLat = destination?.lat ??
        (cityData?.places.isNotEmpty == true
            ? cityData!.places.first.lat
            : null);
    final centerLng = destination?.lng ??
        (cityData?.places.isNotEmpty == true
            ? cityData!.places.first.lng
            : null);
    if (centerLat == null || centerLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.s('routeOptimization.missingLocation'))),
      );
      return;
    }

    final preparedTrip = Trip.fromJson(_trip.toJson());
    final preparedDay = preparedTrip.days.firstWhere(
      (candidate) => candidate.dayNumber == day.dayNumber,
    );
    for (final item in preparedDay.items) {
      if (item.lat != null && item.lng != null) continue;
      final coordinate = resolvePlaceCoords(
        item.title,
        cityKey: destination?.city,
      );
      if (coordinate == null) {
        // “Öğle molası”, “serbest zaman” gibi esnek plan öğeleri gerçek bir
        // mekan değildir. Bunlar sabit aktivite olmadığı sürece optimizasyonu
        // kesmemeli; şehir merkezini güvenli yaklaşık durak olarak kullanıp
        // saat/sıra hesabına dahil edilmelidir. Sabit aktivitenin zamanı,
        // kilidi ve diğer özellikleri burada değiştirilmez.
        item
          ..lat = centerLat
          ..lng = centerLng;
        continue;
      }
      item
        ..lat = coordinate.lat
        ..lng = coordinate.lng;
    }

    final date = DateTime.tryParse(day.date);
    if (date == null) return;
    final weatherAdjustment =
        useWeatherAdjustment ? _weatherRouteAdjustmentFor(forecast) : null;
    final base = TripLocation(
      id: 'day-${day.dayNumber}-base',
      name: destination?.city ?? s.s('routeOptimization.dayBase'),
      latitude: centerLat,
      longitude: centerLng,
      city: destination?.city,
      clusterId: destination?.city,
    );
    final input = DayOptimizationInput(
      trip: preparedTrip,
      dayNumber: day.dayNumber,
      planVersion: _planVersion,
      constraints: DayRouteConstraints(
        startLocation: base,
        endLocation: base,
        availableStartTime:
            DateTime(date.year, date.month, date.day, kRouteStartHour),
        availableEndTime:
            DateTime(date.year, date.month, date.day, kRouteEndHour),
      ),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RouteOptimizationSheet(
        input: input,
        palette: ViewerPalette.of(context),
        initialProfile: weatherAdjustment?.profile,
        weatherHintText:
            weatherAdjustment == null ? null : s.s(weatherAdjustment.hintKey),
        weatherMaximumWalkingMinutes: weatherAdjustment?.maximumWalkingMinutes,
        onPersist: (optimized) async {
          try {
            await ref.read(plansRepositoryProvider)?.save(optimized);
          } on StateError {
            // Auth-less preview ve widget testinde repository bilinçli yoktur.
          }
          _editSession.replaceFromRemote(optimized);
          HomeWidgetHook.pushFromTrip(optimized);
        },
      ),
    );
  }

  void _openThemePicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const FractionallySizedBox(
        heightFactor: 0.82,
        child: _ThemePickerSheet(),
      ),
    );
  }

  /// İki günün destinasyonu farklıysa günler arasına yerleştirilen küçük
  /// "şehirler arası geçiş" ayracı. Kart yığınında ulaşım günü olduğunu
  /// belirsizce vurgular; ulaşım kartını değiştirmez.
  /// Bu transfer raylı mı? Yalnız raylı bacaklarda Shinkansen rezervasyon
  /// bağlantısı gösterilir — uçak/otobüs bacağında yanıltıcı olurdu.
  static bool _isRailTransfer(String? mode) {
    if (mode == null || mode.isEmpty) return false;
    final m = mode.toLowerCase();
    return m.contains('shinkansen') ||
        m.contains('jr ') ||
        m.contains('express') ||
        m.contains('train') ||
        m.contains('line');
  }

  Widget _cityTransitionBetween(
      DayPlan fromDay, DayPlan toDay, ViewerPalette p) {
    final fromDest = getDestinationForDate(_sortedDestinations, fromDay.date);
    final toDest = getDestinationForDate(_sortedDestinations, toDay.date);
    if (fromDest == null || toDest == null) return const SizedBox.shrink();
    if (fromDest.id == toDest.id) return const SizedBox.shrink();
    final fromCity =
        fromDest.city.isNotEmpty ? fromDest.city : fromDest.countryName;
    final toCity = toDest.city.isNotEmpty ? toDest.city : toDest.countryName;
    final s = LanguageScope.of(context);
    final label = s.p('viewer.cityTransition', {
      'from': fromCity,
      'to': toCity,
    });
    // Rozet + bağlantı GERÇEK transfer moduna göre seçilir. Eskiden her
    // şehir geçişinde sabit "JR Pass" rozeti ve bir bayi linki vardı; uçakla
    // gidilen bacaklarda (ör. Tokyo → Sapporo) bu yanlış bilgiydi.
    final transfer = lookupTransfer(fromCity, toCity);
    final selectedMode = toDay.cityTransition?.mode ??
        (_isRailTransfer(transfer?.mode) ? 'shinkansen' : 'train');
    final rail = selectedMode == 'shinkansen';
    final modeLabel = s.s('viewer.transition.mode.$selectedMode');

    // Dikey ritim: üstteki gün kartı zaten 12px alt boşluk bırakıyor, bu
    // yüzden buranın üstü 0. Eskiden simetrik 8px vardı ve pill üstteki
    // karttan 20px (12+8), alttakinden 8px uzakta duruyordu — göz bunu
    // "alttaki güne ait bir etiket" gibi okuyordu.
    //
    // Yatay: çizgiler gün kartlarıyla aynı hizada başlar (eski 4px inset
    // kartların kenarından içeride kalıyordu).
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: p.border)),
          const SizedBox(width: 10),
          // Dekorasyon `Material`'da, InkWell'in DIŞINDA değil.
          //
          // **Why:** Eskiden çerçeveli Container'ın 12px iç boşluğu InkWell'in
          // DIŞINDA kalıyordu; pill'in kenarına dokunmak hiçbir şey yapmıyor,
          // ripple de kapsülü doldurmuyordu. Tek kapsül = tek dokunma hedefi.
          Semantics(
            button: true,
            label: '$label · $modeLabel',
            child: Material(
              color: p.accent.withValues(alpha: .10),
              shape: StadiumBorder(
                side: BorderSide(color: p.accent.withValues(alpha: .35)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey(
                  'city-transition-$fromCity-$toCity-$selectedMode',
                ),
                onTap: () => _openCityTransitionPicker(
                  fromDay: fromDay,
                  toDay: toDay,
                  fromCity: fromCity,
                  toCity: toCity,
                  palette: p,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 34),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Tek gap değeri: 6. Eskiden 4/6/5/3/0 karışıktı ve
                        // chevron kendinden önceki ikona sıfır boşlukla
                        // yapışıyordu.
                        Text(
                          _cityTransitionEmoji(selectedMode),
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            color: p.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          modeLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: p.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (rail) ...[
                          const SizedBox(width: 6),
                          // Rozet artık palete bağlı. Eskiden 0xFFFFD700 /
                          // 0xFFD4A017 sabitleriydi; koyu temada zeminle
                          // çakışıyordu.
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: p.gold.withValues(alpha: .18),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              s.s('viewer.transition.official'),
                              style: TextStyle(
                                fontSize: 9.5,
                                color: Color.lerp(p.gold, p.textPrimary, .3),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                        // `open_in_new` kaldırıldı: dışarı açılacağını
                        // söylüyordu ama pill'in tek aksiyonu mod seçiciyi
                        // AÇMAK. Resmî bilet bağlantısı seçicinin içinde.
                        const SizedBox(width: 6),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 16,
                          color: p.accent.withValues(alpha: .75),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: p.border)),
        ],
      ),
    );
  }

  Future<void> _openCityTransitionPicker({
    required DayPlan fromDay,
    required DayPlan toDay,
    required String fromCity,
    required String toCity,
    required ViewerPalette palette,
  }) async {
    final s = LanguageScope.of(context);
    var selectedMode = toDay.cityTransition?.mode ??
        (_isRailTransfer(lookupTransfer(fromCity, toCity)?.mode)
            ? 'shinkansen'
            : 'train');
    final linkedTicketId = toDay.cityTransition?.linkedTicketId;
    final existingTicket = linkedTicketId == null
        ? null
        : _trip.tickets
            .where((ticket) => ticket.id == linkedTicketId)
            .cast<Ticket?>()
            .firstWhere((ticket) => ticket != null, orElse: () => null);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: Material(
            color: palette.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.textMuted.withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.p('viewer.transition.pickerTitle', {
                            'from': fromCity,
                            'to': toCity,
                          }),
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: s.s('wx.close'),
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Text(
                    s.s('viewer.transition.pickerHelp'),
                    style:
                        TextStyle(color: palette.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  for (final mode in const [
                    'shinkansen',
                    'train',
                    'bus',
                    'taxi',
                    'flight',
                  ])
                    ListTile(
                      key: ValueKey(
                        'city-transition-mode-$mode-${selectedMode == mode}',
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Text(
                        _cityTransitionEmoji(mode),
                        style: const TextStyle(fontSize: 21),
                      ),
                      title: Text(s.s('viewer.transition.mode.$mode')),
                      trailing: selectedMode == mode
                          ? Icon(Icons.check_circle_rounded,
                              color: palette.accent)
                          : const Icon(Icons.circle_outlined),
                      onTap: () async {
                        if (mode == selectedMode) return;
                        final result = await _editSession.execute(
                          UpdateCityTransition(
                            toDayNumber: toDay.dayNumber,
                            fromCity: fromCity,
                            toCity: toCity,
                            mode: mode,
                            lang: s.lang,
                          ),
                        );
                        if (result.isSuccess && sheetContext.mounted) {
                          setSheetState(() => selectedMode = mode);
                        }
                      },
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('city-transition-ticket-action'),
                    onPressed: () async {
                      final saved = await _openTicketEditor(
                        existing: existingTicket,
                        transitionDay: _editSession.current.days.firstWhere(
                          (day) => day.dayNumber == toDay.dayNumber,
                        ),
                        fromCity: fromCity,
                        toCity: toCity,
                        mode: selectedMode,
                      );
                      if (saved && sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                      }
                    },
                    icon: Icon(existingTicket == null
                        ? Icons.add_rounded
                        : Icons.edit_outlined),
                    label: Text(existingTicket == null
                        ? s.s('viewer.transition.addTicket')
                        : s.s('viewer.transition.editTicket')),
                  ),
                  if (selectedMode == 'shinkansen')
                    TextButton.icon(
                      onPressed: () async {
                        final uri = Uri.tryParse(kShinkansenOfficialUrl);
                        if (uri == null) return;
                        try {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } on Object {
                          // Harici uygulama açılamazsa plan ve sheet korunur.
                        }
                      },
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: Text(s.s('viewer.transition.openOfficial')),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _cityTransitionEmoji(String mode) => switch (mode) {
        'shinkansen' => '🚄',
        'bus' => '🚌',
        'taxi' => '🚕',
        'flight' => '✈️',
        _ => '🚆',
      };

  static String _ticketKindForTransitionMode(String? mode) => switch (mode) {
        'bus' => 'bus',
        'flight' => 'flight',
        'shinkansen' || 'train' => 'train',
        _ => 'other',
      };

  _WeatherRouteAdjustment? _weatherRouteAdjustmentFor(DayForecast? forecast) {
    if (forecast == null) return null;
    final code = forecast.code;
    final precip = forecast.precipProb ?? 0;
    final isStorm = (code >= 95 && code <= 99) || code == 77;
    final isHeavyRain = (code >= 80 && code <= 82) ||
        (code >= 51 && code <= 67) ||
        precip >= 65;
    final isSnow = code >= 71 && code <= 76;

    if (isStorm || isSnow) {
      return const _WeatherRouteAdjustment(
        profile: RouteOptimizationProfile.leastWalking,
        maximumWalkingMinutes: 45,
        hintKey: 'routeOptimization.weather.storm',
      );
    }
    if (isHeavyRain) {
      return const _WeatherRouteAdjustment(
        profile: RouteOptimizationProfile.leastWalking,
        maximumWalkingMinutes: 65,
        hintKey: 'routeOptimization.weather.rain',
      );
    }
    if (forecast.tempMax >= 34 || forecast.tempMin <= 2) {
      return const _WeatherRouteAdjustment(
        profile: RouteOptimizationProfile.leastWalking,
        maximumWalkingMinutes: 75,
        hintKey: 'routeOptimization.weather.extremeTemp',
      );
    }

    // Hava rotayı değiştirmeyi gerektirmiyor → **öneri yok**.
    //
    // Eskiden burada `balanced` + "clear" ipucu dönüyordu; bu null olmadığı
    // için "Havaya göre optimize et" CTA'sı sorunsuz bir günde de yanıyordu.
    // Zaten düzgün olan bir planı optimize etmeye çağırmak kullanıcının
    // güvenini tüketir.
    return null;
  }

  /// Bu gün için hava temelli optimizasyon **teklif edilmeli mi?**
  ///
  /// İki kapı birlikte geçilmeli:
  /// 1. Hava gerçekten bir değişiklik gerektiriyor (fırtına/yoğun yağış/aşırı
  ///    sıcaklık) — [_weatherRouteAdjustmentFor] null değil.
  /// 2. Tarih tahminin kesinleştiği pencerede ([kForecastActionableHorizonDays]).
  ///    16 gün sonrasının kodu için rota bozmak, tahmin tutmayınca kullanıcıyı
  ///    boşa uğraştırır.
  bool _shouldOfferWeatherOptimization(DayPlan day, DayForecast? forecast) {
    if (_weatherRouteAdjustmentFor(forecast) == null) return false;
    return isForecastActionable(dateIso: day.date, today: DateTime.now());
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

  String _dateLabel() {
    String short(String value) {
      final date = DateTime.tryParse(value);
      if (date == null) return '';
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
    }

    final start = short(widget.trip.tripStart);
    final end = short(widget.trip.tripEnd);
    if (start.isEmpty && end.isEmpty) return '';
    if (start == end || end.isEmpty) return start;
    return '$start — $end';
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
                // Apple tarzı merkez başlık: plan adı + kısa tarih/faz bilgisi.
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.trip.title.trim().isEmpty
                              ? s.s('drawer.brand')
                              : widget.trip.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: onColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (_dateLabel().isNotEmpty) _dateLabel(),
                            _phaseLabel(s),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: onColor.withValues(alpha: 0.78),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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
              Icon(Icons.notifications_none_outlined, color: color, size: 22),
              if (count > 0)
                Positioned(
                  right: 6,
                  top: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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

/// iOS tarzı persistent tab bar — yazı + emoji bazlı, net ve anlaşılır.
class _ViewerQuickNav extends StatelessWidget {
  const _ViewerQuickNav({
    required this.palette,
    required this.activeTab,
    required this.onTabChanged,
    required this.onOpenExplore,
  });

  final ViewerPalette palette;
  final int activeTab;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onOpenExplore;

  @override
  Widget build(BuildContext context) {
    final activeColor = palette.accent;
    final inactiveColor = palette.textSecondary;

    final tabs = <({String emoji, String label})>[
      (emoji: '🏠', label: 'Ana Sayfa'),
      (emoji: '🎫', label: 'Biletler'),
      (emoji: '🇯🇵', label: 'Japonca'),
      (emoji: '📖', label: 'Rehber'),
      (
        emoji: '🗺️',
        label: LanguageScope.of(context).s('viewer.quick.explore')
      ),
    ];

    return Material(
      color: palette.card.withValues(alpha: 0.98),
      child: SafeArea(
        top: false,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: palette.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      if (i == tabs.length - 1) {
                        onOpenExplore();
                      } else {
                        onTabChanged(i);
                      }
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(tabs[i].emoji,
                            style:
                                TextStyle(fontSize: activeTab == i ? 22 : 20)),
                        const SizedBox(height: 2),
                        Text(
                          tabs[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: activeTab == i ? activeColor : inactiveColor,
                            fontSize: 11,
                            fontWeight: activeTab == i
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ],
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
// Tab içerik widget'ları — persistent tab bar ile kullanım için
// Scaffold/AppBar'sız, sadece içerik.
// ---------------------------------------------------------------------------

/// Tab 1 — Biletler: kullanıcının girdiği biletleri listeler.
class _TicketEditorDraft {
  const _TicketEditorDraft({
    required this.label,
    required this.url,
    required this.purchased,
  });

  final String label;
  final String url;
  final bool purchased;
}

class _TicketEditorDialog extends StatefulWidget {
  const _TicketEditorDialog({
    required this.palette,
    required this.title,
    required this.labelText,
    required this.urlText,
    required this.purchasedText,
    required this.cancelText,
    required this.saveText,
    required this.initialLabel,
    required this.initialUrl,
    required this.initialPurchased,
  });

  final ViewerPalette palette;
  final String title;
  final String labelText;
  final String urlText;
  final String purchasedText;
  final String cancelText;
  final String saveText;
  final String initialLabel;
  final String initialUrl;
  final bool initialPurchased;

  @override
  State<_TicketEditorDialog> createState() => _TicketEditorDialogState();
}

class _TicketEditorDialogState extends State<_TicketEditorDialog> {
  late final TextEditingController _labelController;
  late final TextEditingController _urlController;
  late bool _purchased;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.initialLabel);
    _urlController = TextEditingController(text: widget.initialUrl);
    _purchased = widget.initialPurchased;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _save() {
    final label = _labelController.text.trim();
    if (label.isEmpty) return;
    Navigator.pop(
      context,
      _TicketEditorDraft(
        label: label,
        url: _urlController.text.trim(),
        purchased: _purchased,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.palette.card,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _labelController,
            autofocus: true,
            decoration: InputDecoration(labelText: widget.labelText),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: widget.urlText),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(widget.purchasedText),
            value: _purchased,
            onChanged: (value) => setState(() => _purchased = value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelText),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(widget.saveText),
        ),
      ],
    );
  }
}

class _TabTicketsView extends StatelessWidget {
  const _TabTicketsView({
    required this.trip,
    required this.palette,
    required this.onAddTicket,
    required this.onEditTicket,
  });
  final Trip trip;
  final ViewerPalette palette;
  final VoidCallback onAddTicket;
  final ValueChanged<Ticket> onEditTicket;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final p = palette;
    if (trip.tickets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.confirmation_num_outlined, size: 48, color: p.textMuted),
            const SizedBox(height: 12),
            Text(
              s.s('viewer.quick.noTickets'),
              style: TextStyle(color: p.textSecondary, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              s.s('viewer.quick.noTicketsHelp'),
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textMuted, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const ValueKey('add-first-ticket'),
              onPressed: onAddTicket,
              icon: const Icon(Icons.add_rounded),
              label: Text(s.s('viewer.quick.addTicket')),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        for (final ticket in trip.tickets)
          InkWell(
            onTap: () => onEditTicket(ticket),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (ticket.kind == 'train' ? p.fuji : p.sakura)
                          .withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      ticket.kind == 'train'
                          ? Icons.train_outlined
                          : Icons.confirmation_num_outlined,
                      color: ticket.kind == 'train' ? p.fuji : p.sakura,
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ticket.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.textPrimary,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(
                            ticket.visitDate ??
                                (ticket.purchased
                                    ? s.s('viewer.quick.ticketPurchased')
                                    : s.s('viewer.quick.ticketPending')),
                            style: TextStyle(
                                color: p.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  Icon(
                    ticket.purchased
                        ? Icons.check_circle_outline
                        : Icons.schedule_outlined,
                    color: ticket.purchased ? p.matcha : p.gold,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Tab 2 — Japonca: pratik kelimeler & cümleler (AppBar'sız, tab içi).
class _TabPhrasesView extends StatefulWidget {
  const _TabPhrasesView({
    required this.palette,
    required this.lang,
    required this.isPremium,
  });
  final ViewerPalette palette;
  final AppLang lang;
  final bool isPremium;
  @override
  State<_TabPhrasesView> createState() => _TabPhrasesViewState();
}

class _TabPhrasesViewState extends State<_TabPhrasesView> {
  int _activeCat = 0;

  void _speak(String text) {
    try {
      TtsService.instance.speakJa(text);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final lang = widget.lang;
    final category = kJapanesePhraseCategories[_activeCat];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Text(const LText('Japonca', 'Japanese').of(lang),
            style: TextStyle(
                color: p.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        OfflineTranslatorCard(
          palette: p,
          lang: lang,
          isPremium: widget.isPremium,
        ),
        const SizedBox(height: 20),
        Text(
          const LText('Hazır ifadeler', 'Ready-to-use phrases').of(lang),
          style: TextStyle(
            color: p.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        // Kategori sekmeleri — emoji yerine anlamlı ikon + kısa metin
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kJapanesePhraseCategories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final cat = kJapanesePhraseCategories[i];
              final active = i == _activeCat;
              return Material(
                color: active ? p.accent.withValues(alpha: 0.14) : p.elevated,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => setState(() => _activeCat = i),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: active ? p.accent : p.border),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(cat.emoji, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 5),
                      Text(cat.title.of(lang),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: active ? p.accent : p.textSecondary)),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        // Cümleler
        for (final phrase in category.phrases)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.border),
            ),
            child: InkWell(
              onTap: () => _speak(phrase.jp),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(phrase.meaning.of(lang),
                              style: TextStyle(
                                  color: p.textSecondary, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(phrase.jp,
                              style: TextStyle(
                                  color: p.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700)),
                          if (phrase.romaji != null &&
                              phrase.romaji!.isNotEmpty)
                            Text(phrase.romaji!,
                                style: TextStyle(
                                    color: p.textMuted,
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.volume_up_rounded,
                          size: 20, color: p.accent),
                      onPressed: () => _speak(phrase.jp),
                      tooltip: const LText('Sesli dinle', 'Listen').of(lang),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Rehber sekmesi.
///
/// **Yeniden düzenlendi.** Eskiden 13 bölümün TÜM maddeleri açık haldeydi:
/// yüzlerce satırlık tek bir duvar. Kullanıcı aradığını bulmak için
/// kaydırmak zorundaydı ve en altta duran "seyahat öncesi hallet" kartını
/// (zamana duyarlı, aksiyon gerektiren tek şey) çoğu kimse hiç görmüyordu.
///
/// Yeni düzen:
///  1. Aksiyon gerektiren "seyahat öncesi hallet" EN ÜSTTE,
///  2. Arama kutusu — 13 bölümde gezinmek yerine yazıp bul,
///  3. Bölümler KAPALI başlar, dokununca açılır (madde sayısı görünür).
///
/// Maddeler geziye göre süzülür: çocuksuz planda çocuk maddeleri gösterilmez.
class _TabMustKnowView extends StatefulWidget {
  const _TabMustKnowView({
    required this.palette,
    required this.lang,
    required this.trip,
  });
  final ViewerPalette palette;
  final AppLang lang;
  final Trip trip;

  @override
  State<_TabMustKnowView> createState() => _TabMustKnowViewState();
}

class _TabMustKnowViewState extends State<_TabMustKnowView> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _hasKids {
    final prefs = widget.trip.preferences;
    if ((prefs.childrenCount ?? 0) > 0) return true;
    return prefs.interests.contains(InterestTag.kids);
  }

  bool _tipVisible(MustKnowTip tip) =>
      tip.audience == MustKnowAudience.all || _hasKids;

  bool _sectionMatchesQuery(MustKnowSection section, String q) {
    final title = section.title.of(widget.lang).toLowerCase();
    if (title.contains(q)) return true;
    return section.tips.any((tip) {
      if (!_tipVisible(tip)) return false;
      return tip.text.of(widget.lang).toLowerCase().contains(q);
    });
  }

  List<int> _matchingSectionIndices(String q) {
    if (q.isEmpty)
      return List<int>.generate(kMustKnowSections.length, (i) => i);
    final matches = <int>[];
    for (var i = 0; i < kMustKnowSections.length; i++) {
      if (_sectionMatchesQuery(kMustKnowSections[i], q)) {
        matches.add(i);
      }
    }
    return matches;
  }

  List<MustKnowTip> _tipsOf(MustKnowSection section, {String? query}) {
    final q = (query ?? _query).trim().toLowerCase();
    return section.tips.where((tip) {
      if (!_tipVisible(tip)) return false;
      if (q.isEmpty) return true;
      final title = section.title.of(widget.lang).toLowerCase();
      return tip.text.of(widget.lang).toLowerCase().contains(q) ||
          title.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final lang = widget.lang;
    final s = LanguageScope.of(context);
    final q = _query.trim().toLowerCase();
    final visibleIndices = _matchingSectionIndices(q);
    final detailIndex = _selectedSectionIndex;
    final visibleSections = visibleIndices
        .map(
          (index) => (
            index: index,
            section: kMustKnowSections[index],
            tips: _tipsOf(kMustKnowSections[index], query: _query),
          ),
        )
        .toList(growable: false);

    return AnimatedSwitcher(
      duration:
          RotoriMotion.duration(context, const Duration(milliseconds: 220)),
      switchInCurve: RotoriMotion.curve(context),
      switchOutCurve: RotoriMotion.curve(context),
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: RotoriMotion.curve(context),
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.02, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: detailIndex == null
          ? _GuideListView(
              key: ValueKey('guide-list-$q'),
              palette: p,
              lang: lang,
              searchCtrl: _searchCtrl,
              query: _query,
              hasResults: q.isEmpty || visibleSections.isNotEmpty,
              visibleSections: visibleSections,
              onQueryChanged: _updateQuery,
              onClearSearch: _clearSearch,
              onOpenSection: _openSection,
            )
          : _GuideDetailView(
              key: ValueKey('guide-detail-$detailIndex-$q'),
              palette: p,
              lang: lang,
              section: kMustKnowSections[detailIndex],
              tips: _tipsOf(kMustKnowSections[detailIndex], query: _query),
              onBackToAllTopics: () =>
                  setState(() => _selectedSectionIndex = null),
            ),
    );
  }
}

class _GuideListView extends StatelessWidget {
  const _GuideListView({
    super.key,
    required this.palette,
    required this.lang,
    required this.searchCtrl,
    required this.query,
    required this.hasResults,
    required this.visibleSections,
    required this.onQueryChanged,
    required this.onClearSearch,
    required this.onOpenSection,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final TextEditingController searchCtrl;
  final String query;
  final bool hasResults;
  final List<({int index, MustKnowSection section, List<MustKnowTip> tips})>
      visibleSections;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<int> onOpenSection;

  List<int> get _quickAccessIndices {
    int findByTrTitle(String title) => kMustKnowSections.indexWhere(
          (section) => section.title.tr == title,
        );
    return [
      findByTrTitle('Acil Durum ve Güvenlik'),
      findByTrTitle('Suica Kartı Nasıl Alınır?'),
      findByTrTitle('Para ve Ödeme'),
      findByTrTitle('Ulaşım ve İnternet'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = LanguageScope.of(context);
    final q = query.trim();
    final searching = q.isNotEmpty;
    final quickAccessIndices = _quickAccessIndices;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Text(
          key: const ValueKey('guide-title'),
          const LText('Rehber', 'Guide').of(lang),
          style: TextStyle(
            color: p.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          const LText(
            'Japonya yolculuğunda işine yarayacak pratik notlar ve kısa '
                'uyarılar.',
            'Practical notes and quick warnings for your Japan trip.',
          ).of(lang),
          style: TextStyle(color: p.textSecondary, fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('viewer-guide-search'),
          controller: searchCtrl,
          onChanged: onQueryChanged,
          style: TextStyle(color: p.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: s.s('viewer.guide.search'),
            hintStyle: TextStyle(color: p.textMuted, fontSize: 14),
            prefixIcon:
                Icon(Icons.search_rounded, size: 20, color: p.textMuted),
            suffixIcon: searching
                ? IconButton(
                    icon:
                        Icon(Icons.close_rounded, size: 18, color: p.textMuted),
                    onPressed: onClearSearch,
                  )
                : null,
            filled: true,
            fillColor: p.card,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: p.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: p.accent),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (visibleQuickAccessIndices.isNotEmpty) ...[
          Text(
            key: const ValueKey('guide-quick-access-heading'),
            const LText('Hızlı erişim', 'Quick access').of(lang),
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final index in visibleQuickAccessIndices)
                    SizedBox(
                      width: cardWidth,
                      child: _GuideQuickAccessCard(
                        key: ValueKey('guide-quick-$index'),
                        palette: p,
                        lang: lang,
                        section: kMustKnowSections[index],
                        label: switch (index) {
                          6 => const LText('Acil Durum', 'Emergency'),
                          2 => const LText('Suica', 'Suica'),
                          1 => const LText('Para', 'Money'),
                          3 => const LText('İnternet', 'Internet'),
                          _ => const LText('Konu', 'Topic'),
                        },
                        onTap: () => onOpenSection(index),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
        ],
        Text(
          key: const ValueKey('guide-all-topics-heading'),
          const LText('Tüm konular', 'All topics').of(lang),
          style: TextStyle(
            color: p.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        if (!hasResults)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              s.s('viewer.guide.noResult'),
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textSecondary, fontSize: 14),
            ),
          )
        else
          _GuideTopicGroup(
            palette: p,
            lang: lang,
            sections: visibleSections,
            onOpenSection: onOpenSection,
          ),
      ],
    );
  }
}

class _GuideDetailView extends StatelessWidget {
  const _GuideDetailView({
    super.key,
    required this.palette,
    required this.lang,
    required this.section,
    required this.tips,
    required this.onBackToAllTopics,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final MustKnowSection section;
  final List<MustKnowTip> tips;
  final VoidCallback onBackToAllTopics;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return ListView(
      key: const ValueKey('viewer-guide-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        TextButton.icon(
          key: const ValueKey('guide-back-all'),
          onPressed: onBackToAllTopics,
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: Text(
            const LText('Tüm konular', 'All topics').of(lang),
            style: TextStyle(
              color: p.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: p.accent,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: p.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  section.emoji,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.title.of(lang),
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lang == AppLang.tr
                          ? '${tips.length} madde'
                          : '${tips.length} tips',
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: p.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < tips.length; i++) ...[
                if (i > 0) Divider(height: 1, color: p.border),
                _GuideTipRow(
                  tip: tips[i],
                  palette: p,
                  lang: lang,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _PreDepartureCard(palette: p, lang: lang),
      ],
    );
  }
}

class _GuideQuickAccessCard extends StatelessWidget {
  const _GuideQuickAccessCard({
    super.key,
    required this.palette,
    required this.lang,
    required this.section,
    required this.label,
    required this.onTap,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final MustKnowSection section;
  final LText label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Semantics(
      button: true,
      label: '${label.of(lang)} · ${section.title.of(lang)}',
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      section.emoji,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label.of(lang),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          section.title.of(lang),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideTopicGroup extends StatelessWidget {
  const _GuideTopicGroup({
    required this.palette,
    required this.lang,
    required this.sections,
    required this.onOpenSection,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final List<({int index, MustKnowSection section, List<MustKnowTip> tips})>
      sections;
  final ValueChanged<int> onOpenSection;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.border),
            _GuideTopicRow(
              index: sections[i].index,
              palette: p,
              lang: lang,
              section: sections[i].section,
              tips: sections[i].tips,
              onTap: () => onOpenSection(sections[i].index),
            ),
          ],
        ],
      ),
    );
  }
}

class _GuideTopicRow extends StatelessWidget {
  const _GuideTopicRow({
    required this.index,
    required this.palette,
    required this.lang,
    required this.section,
    required this.tips,
    required this.onTap,
  });

  final int index;
  final ViewerPalette palette;
  final AppLang lang;
  final MustKnowSection section;
  final List<MustKnowTip> tips;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Semantics(
      button: true,
      label: '${section.title.of(lang)} · ${tips.length}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('guide-topic-$index'),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(section.emoji,
                        style: const TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      section.title.of(lang),
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${tips.length}',
                      style: TextStyle(
                        color: p.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
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

/// "Seyahat öncesi hallet" — zamana duyarlı afiliye kartları.
///
/// Sekmenin altında ikincil ve kapalı bir yardımcı satır olarak kalır.
class _PreDepartureCard extends StatefulWidget {
  const _PreDepartureCard({required this.palette, required this.lang});
  final ViewerPalette palette;
  final AppLang lang;

  @override
  State<_PreDepartureCard> createState() => _PreDepartureCardState();
}

class _PreDepartureCardState extends State<_PreDepartureCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final lang = widget.lang;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => setState(() => _expanded = !_expanded),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child:
                              const Text('📦', style: TextStyle(fontSize: 18)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                const LText(
                                  'Seyahat öncesi hallet',
                                  'Book before you go',
                                ).of(lang),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                const LText(
                                  'Bunları şimdiden ayırt, yerin garanti olsun.',
                                  'Book now, secure your spot.',
                                ).of(lang),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${kPreDepartureAffiliates.length}',
                            style: TextStyle(
                              color: p.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 22,
                            color: p.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                children: [
                  for (final link in kPreDepartureAffiliates)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _AffiliateCard(link: link, palette: p, lang: lang),
                    ),
                ],
              ),
            ),
        ],
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
    final visibleQuickAccessIndices = searching
        ? quickAccessIndices
            .where(
              (index) => visibleSections.any((entry) => entry.index == index),
            )
            .toList(growable: false)
        : quickAccessIndices;
      text = '$emoji ${_daysUntil(ticket.visitDate!)}g';
      bg = palette.topBarOnColor.withValues(alpha: 0.18);
      key: const ValueKey('viewer-guide-scroll'),
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

/// "✈️ Uçuşunu ekle" — plan uçuşsuz üretildiyse gün akışının ÜSTÜNDE görünen
/// opsiyonel kart. Drawer'a değil buraya konur: kullanıcı planı ilk açtığı
/// anda görsün, drawer'da keşfedilmeden kaybolmasın.
class _AddFlightCard extends StatelessWidget {
  const _AddFlightCard({
    required this.palette,
    required this.onOpen,
    required this.onDismiss,
  });
  final ViewerPalette palette;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.flight_takeoff_rounded,
                      color: palette.accent, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.s('viewer.addFlight.title'),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.s('viewer.addFlight.body'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: palette.textMuted),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: palette.textMuted, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: onDismiss,
                ),
              ],
            ),
          ),
        ),
      ),
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

class _RouteOptimizationSheet extends ConsumerStatefulWidget {
  const _RouteOptimizationSheet({
    required this.input,
    required this.palette,
    required this.onPersist,
    this.initialProfile,
    this.weatherHintText,
    this.weatherMaximumWalkingMinutes,
  });

  final DayOptimizationInput input;
  final ViewerPalette palette;
  final OptimizedPlanPersist onPersist;
  final RouteOptimizationProfile? initialProfile;
  final String? weatherHintText;
  final int? weatherMaximumWalkingMinutes;

  @override
  ConsumerState<_RouteOptimizationSheet> createState() =>
      _RouteOptimizationSheetState();
}

class _RouteOptimizationSheetState
    extends ConsumerState<_RouteOptimizationSheet> {
  late RouteOptimizationProfile _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.initialProfile ?? RouteOptimizationProfile.balanced;
    WidgetsBinding.instance.addPostFrameCallback((_) => _optimize());
  }

  Future<void> _optimize() {
    return ref.read(planOptimizationControllerProvider.notifier).optimizeDay(
          DayOptimizationInput(
            trip: widget.input.trip,
            dayNumber: widget.input.dayNumber,
            planVersion: widget.input.planVersion,
            constraints: widget.input.constraints,
            preferences: RoutePreferences(

              profile: _profile,
              maximumWalkingMinutes: widget.weatherMaximumWalkingMinutes ??
                  widget.input.preferences.maximumWalkingMinutes,
              partySize: widget.input.preferences.partySize,
              hasLuggage: widget.input.preferences.hasLuggage,
              luggageState: widget.input.preferences.effectiveLuggageState,
            ),
          ),
        );
  }

  @override
  int? _selectedSectionIndex;
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final p = widget.palette;
    final state = ref.watch(planOptimizationControllerProvider);
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .88,
        ),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: p.border),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.textMuted.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(4),
                  ),
  void _openSection(int index) {
    setState(() => _selectedSectionIndex = index);
  }

  void _clearSearch() {
    setState(() {
      _searchCtrl.clear();
      _query = '';
      _selectedSectionIndex = null;
    });
  }

  void _updateQuery(String value) {
    final q = value.trim().toLowerCase();
    final matches = _matchingSectionIndices(q);
    setState(() {
      _query = value;
      if (q.isEmpty) {
        _selectedSectionIndex = null;
      } else if (matches.length == 1) {
        _selectedSectionIndex = matches.single;
      } else {
        _selectedSectionIndex = null;
      }
    });
  }

                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      s.s('routeOptimization.title'),
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
      key: const ValueKey('viewer-guide-scroll'),
                    tooltip: s.s('wx.close'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (widget.weatherHintText != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: p.sky.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.sky.withValues(alpha: .45)),
                  ),
                  child: Row(
                    children: [
                      const Text('🌦️', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.weatherHintText!,
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
              ],
              const SizedBox(height: 6),
              Text(
                s.s('routeOptimization.subtitle'),
                style: TextStyle(color: p.textSecondary, height: 1.35),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final profile in RouteOptimizationProfile.values)
                    ChoiceChip(
                      label: Text(_profileLabel(s, profile)),
                      selected: _profile == profile,
                      onSelected: state.isLoading
                          ? null
                          : (selected) {
                              if (!selected || profile == _profile) return;
                              setState(() => _profile = profile);
                              _optimize();
                            },
                    ),
                ],
              ),
              const SizedBox(height: 18),
              state.when(
                loading: () => _OptimizationLoading(palette: p),
                error: (error, _) => _OptimizationError(
                  palette: p,
                  message: _optimizationErrorMessage(s, error),
                  onRetry: _optimize,
                ),
                data: (preview) {
                  if (preview == null) {
                    return _OptimizationLoading(palette: p);
                  }
                  return _OptimizationComparison(
                    preview: preview,
                    palette: p,
                    onCancel: () {
                      ref
                          .read(planOptimizationControllerProvider.notifier)
                          .discard();
                      Navigator.pop(context);
                    },
                    onConfirm: () async {
        const SizedBox(height: 16),
        _PreDepartureCard(palette: p, lang: lang),
                      final saved = await ref
                          .read(planOptimizationControllerProvider.notifier)
                          .confirm(widget.onPersist);
                      if (saved && context.mounted) Navigator.pop(context);
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptimizationLoading extends StatelessWidget {
  const _OptimizationLoading({required this.palette});
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          children: [
            CircularProgressIndicator(color: palette.accent),
            const SizedBox(height: 14),
            Text(
              LanguageScope.of(context).s('routeOptimization.loading'),
              style: TextStyle(color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptimizationError extends StatelessWidget {
  const _OptimizationError({
    required this.palette,
    required this.message,
    required this.onRetry,
  });
  final ViewerPalette palette;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.sakura.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.sakura.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: TextStyle(color: palette.textPrimary)),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(s.s('routeOptimization.retry')),
          ),
        ],
      ),
    );
  }
}

class _OptimizationComparison extends StatelessWidget {
  const _OptimizationComparison({
    required this.preview,
    required this.palette,
    required this.onCancel,
    required this.onConfirm,
  });
  final PlanOptimizationPreview preview;
  final ViewerPalette palette;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _RouteMetricCard(
                title: s.s('routeOptimization.before'),
                summary: preview.before,
                palette: palette,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward, color: palette.accent),
            ),
            Expanded(
              child: _RouteMetricCard(
                title: s.s('routeOptimization.after'),
                summary: preview.after,
                palette: palette,
                highlighted: true,
              ),
            ),
          ],
        ),
        if (preview.result.optimizationChanges.isNotEmpty) ...[
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded, color: p.textMuted),
          const SizedBox(height: 16),
          Text(
            s.s('routeOptimization.changes'),
          ),
        ),
      ),
    );
  }
}

class _GuideTipRow extends StatelessWidget {
  const _GuideTipRow({
    required this.tip,
    required this.palette,
    required this.lang,
  });

  final MustKnowTip tip;
  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tip.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tip.text.of(lang),
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
          ),
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final change in preview.result.optimizationChanges.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $change',
                style: TextStyle(color: palette.textSecondary),
              ),
            ),
        ],
        if (preview.executionLegs.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            s.s('routeOptimization.legs.title'),
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            s.s('routeOptimization.legs.subtitle'),
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < preview.executionLegs.length; i++) ...[
            _RouteExecutionLegCard(
              key: ValueKey('route-execution-leg-$i'),
              leg: preview.executionLegs[i],
              palette: palette,
            ),
            if (i != preview.executionLegs.length - 1)
              const SizedBox(height: 8),
          ],
        ],
        const SizedBox(height: 20),
            key: const ValueKey('guide-predeparture'),
        // Kazanç yoksa "Uygula" HİÇ çizilmez.
        //
        // **Why pasif buton değil, yokluk:** Gri bir "Uygula" kullanıcıyı
        // "neden basamıyorum" diye uğraştırır. Burada basılacak bir şey yok;
        // doğru cevap butonu değil, açıklamayı göstermek.
        if (!preview.improvesRoute)
          Container(
            key: const ValueKey('route-optimization-no-gain'),
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.elevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 18, color: palette.matcha),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.s('routeOptimization.noGain.title'),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  s.s('routeOptimization.noGain.body'),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  child: Text(s.s('routeOptimization.cancel')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('confirm-route-optimization'),
                  onPressed: onConfirm,
                  child: Text(s.s('routeOptimization.apply')),
                ),
              ),
            ],
          ),
        if (!preview.improvesRoute) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const ValueKey('route-optimization-close'),
              onPressed: onCancel,
              child: Text(s.s('common.done')),
            ),
          ),
        ],
      ],
    );
  }
}

class _RouteExecutionLegCard extends StatelessWidget {
  const _RouteExecutionLegCard({
    super.key,
    required this.leg,
    required this.palette,
    this.compact = false,
  });

  final RouteExecutionLeg leg;
  final ViewerPalette palette;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final estimated = leg.isEstimated;
    final accent = palette.accent;
    final line = !estimated && leg.lineId?.trim().isNotEmpty == true
        ? leg.lineId!.trim()
        : null;
    final direction = !estimated && leg.directionId?.trim().isNotEmpty == true
        ? leg.directionId!.trim()
        : null;
    final semanticsLabel = s.p('routeOptimization.legs.semantics', {
      'from': leg.fromName,
      'to': leg.toName,
      'mode': _routeModeLabel(s, leg.mode),
      'minutes': '${leg.travelDurationMinutes}',
    });

    if (compact) {
      return Semantics(
        container: true,
        label: semanticsLabel,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: Row(
            children: [
              Icon(_routeModeIcon(leg.mode), color: accent, size: 16),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${leg.fromName}  →  ${leg.toName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_routeModeLabel(s, leg.mode)} · '
                '${leg.travelDurationMinutes} ${s.s('routeOptimization.minute')}',
                maxLines: 1,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: semanticsLabel,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.borderStrong),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_routeModeIcon(leg.mode), color: accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _routeLegKindLabel(s, leg.kind),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${leg.fromName}  →  ${leg.toName}',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${_clock(leg.departureTime)}–${_clock(leg.arrivalTime)}  ·  '
              '${leg.travelDurationMinutes} ${s.s('routeOptimization.minute')}',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (line != null || direction != null) ...[
              const SizedBox(height: 6),
              Text(
                [
                  if (line != null)
                    s.p('routeOptimization.legs.line', {'line': line}),
                  if (direction != null)
                    s.p('routeOptimization.legs.direction', {
                      'direction': direction,
                    }),
                ].join('  ·  '),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 9),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _RouteLegFact(
                  icon: _routeModeIcon(leg.mode),
                  label: _routeModeLabel(s, leg.mode),
                  palette: palette,
                ),
                if (leg.walkingDurationMinutes > 0)
                  _RouteLegFact(
                    icon: Icons.directions_walk_rounded,
                    label: s.p('routeOptimization.legs.walk', {
                      'minutes': '${leg.walkingDurationMinutes}',
                    }),
                    palette: palette,
                  ),
                if (leg.transitWaitMinutes > 0)
                  _RouteLegFact(
                    icon: Icons.schedule_rounded,
                    label: s.p('routeOptimization.legs.wait', {
                      'minutes': '${leg.transitWaitMinutes}',
                    }),
                    palette: palette,
                  ),
                if (leg.transferCount > 0)
                  _RouteLegFact(
                    icon: Icons.multiple_stop_rounded,
                    label: s.p('routeOptimization.legs.transfer', {
                      'count': '${leg.transferCount}',
                    }),
                    palette: palette,
                  ),
                if (leg.partyTotalCostYen > 0)
                  _RouteLegFact(
                    icon: Icons.payments_outlined,
                    label: '¥${leg.partyTotalCostYen}',
                    palette: palette,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _clock(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

List<RouteExecutionLeg> _displayRouteLegs(
  DayPlan day,
  TripDestination? destination,
) {
  final saved = day.routeExecutionSnapshot?.legs;
  if (saved != null && saved.isNotEmpty) return saved;
  return _estimatedTimelineLegs(day, destination);
}

List<RouteExecutionLeg> _estimatedTimelineLegs(
  DayPlan day,
  TripDestination? destination,
) {
  if (day.items.isEmpty) return const [];
  final date = DateTime.tryParse(day.date);
  if (date == null) return const [];

  final cityData = cityDataForKey(destination?.city);
  final centerLat = destination?.lat ??
      (cityData?.places.isNotEmpty == true ? cityData!.places.first.lat : null);
  final centerLng = destination?.lng ??
      (cityData?.places.isNotEmpty == true ? cityData!.places.first.lng : null);
  if (centerLat == null || centerLng == null) return const [];

  final base = TripLocation(
    id: 'day-${day.dayNumber}-base',
    name: destination?.city ?? 'Gün başlangıcı',
    latitude: centerLat,
    longitude: centerLng,
    city: destination?.city,
    clusterId: destination?.city,
  );
  final stops = <({TripLocation location, TimelineItem? item})>[
    (location: base, item: null),
  ];
  for (final item in day.items) {
    if (item.kind == TimelineItemKind.transport) continue;
    final location = _timelineLocation(item, destination: destination);
    if (location == null) continue;
    stops.add((location: location, item: item));
  }
  stops.add((location: base, item: null));
  final matrix = buildOfflineJapanRouteMatrix(
    stops.map((stop) => stop.location).toSet().toList(growable: false),
    day: DateTime(date.year, date.month, date.day, kRouteStartHour),
  );
  final legs = <RouteExecutionLeg>[];

  for (var index = 0; index < stops.length - 1; index++) {
    final from = stops[index];
    final to = stops[index + 1];

    final options = matrix.options(from.location.id, to.location.id);
    if (options.isEmpty) continue;
    TransportOption? comfortableWalk;
    for (final candidate in options) {
      if (candidate.mode == TransportMode.walking &&
          candidate.doorToDoorMinutes <= 35) {
        comfortableWalk = candidate;
        break;
      }
    }
    final option = comfortableWalk ??
        options.reduce(
          (best, candidate) =>
              _displayOptionScore(candidate) < _displayOptionScore(best)
                  ? candidate
                  : best,
        );
    if (option.doorToDoorMinutes <= 0) continue;

    final travel = Duration(minutes: option.doorToDoorMinutes);
    final fromStart = _timelineStart(date, from.item);
    final toStart = _timelineStart(date, to.item);
    late final DateTime departure;
    late final DateTime arrival;
    if (toStart != null) {
      arrival = toStart;
      departure = arrival.subtract(travel);
    } else if (fromStart != null && from.item != null) {
      departure = fromStart.add(
        Duration(minutes: _timelineDurationMinutes(from.item!)),
      );
      arrival = departure.add(travel);
    } else {
      departure = DateTime(
        date.year,
        date.month,
        date.day,
        kRouteStartHour,
      ).add(Duration(minutes: index * 30));
      arrival = departure.add(travel);
    }

    final cost = option.costForParty(1);
    legs.add(
      RouteExecutionLeg(
        kind: from.item == null
            ? RouteExecutionLegKind.departure
            : to.item == null
                ? RouteExecutionLegKind.returnToBase
                : RouteExecutionLegKind.betweenStops,
        fromLocationId: from.location.id,
        fromName: from.location.name,
        toLocationId: to.location.id,
        toName: to.location.name,
        mode: option.mode,
        departureTime: departure,
        arrivalTime: arrival,
        travelDurationMinutes: option.doorToDoorMinutes,
        rideMinutes: option.resolvedRideMinutes,
        accessMinutes: option.resolvedAccessMinutes,
        walkingDurationMinutes: option.walkingMinutes,
        waitingDurationMinutes: option.waitingMinutes,
        transitWaitMinutes: option.resolvedTransitWaitMinutes,
        scheduleIdleMinutes: 0,
        transferCount: option.transferCount,
        costPerPersonYen: cost.costPerPersonYen,
        partyTotalCostYen: cost.partyTotalCostYen,
        vehicleCount: cost.vehicleCount,
        fareBasis: cost.fareBasis,
        reliabilityScore: option.reliabilityScore,
        dataQuality: RouteExecutionDataQuality.estimated,
        complexityPenalty: option.complexityPenalty,
        providerId: option.providerId ?? matrix.version,
      ),
    );
  }
  return List.unmodifiable(legs);
}

double _displayOptionScore(TransportOption option) {
  return option.doorToDoorMinutes +
      option.walkingMinutes * 0.35 +
      option.transferCount * 8 +
      option.estimatedCostYen / 180;
}

TripLocation? _timelineLocation(
  TimelineItem item, {
  required TripDestination? destination,
}) {
  final coordinate = item.lat != null && item.lng != null
      ? (lat: item.lat!, lng: item.lng!)
      : resolvePlaceCoords(item.title, cityKey: destination?.city);
  // Konumu bilinmeyen mola/özel başlığı şehir merkezindeymiş gibi varsaymak,
  // iki gerçek durak arasında sahte kısa yürüyüşler üretir. Bu öğe timeline'da
  // görünmeye devam eder; yalnız rota matrisinde düğüm olmaz.
  if (coordinate == null) return null;
  return TripLocation(
    id: item.id,
    name: item.title,
    latitude: coordinate.lat,
    longitude: coordinate.lng,
    city: item.cityId ?? destination?.city,
    clusterId: item.cityId ?? destination?.city,
  );
}

DateTime? _timelineStart(DateTime day, TimelineItem? item) {
  if (item == null) return null;
  final minutes = _timeToMinutes(item.time ?? item.scheduledTime);
  if (minutes == null) return null;
  return DateTime(day.year, day.month, day.day).add(Duration(minutes: minutes));
}

int _timelineDurationMinutes(TimelineItem item) {
  final duration = item.durationMin;
  if (duration != null && duration > 0) return duration;
  return switch (item.kind) {
    TimelineItemKind.meal => 60,
    TimelineItemKind.transport || TimelineItemKind.hotel => 30,
    _ => 90,
  };
}

class _RouteLegFact extends StatelessWidget {
  const _RouteLegFact({
    required this.icon,
    required this.label,
    required this.palette,
  });

  final IconData icon;
  final String label;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: palette.bg.withValues(alpha: .58),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: palette.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String _routeLegKindLabel(LanguageScope s, RouteExecutionLegKind kind) {
  return switch (kind) {
    RouteExecutionLegKind.departure => s.s('routeOptimization.legs.departure'),
    RouteExecutionLegKind.betweenStops =>
      s.s('routeOptimization.legs.betweenStops'),
    RouteExecutionLegKind.returnToBase =>
      s.s('routeOptimization.legs.returnToBase'),
  };
}

String _routeModeLabel(LanguageScope s, TransportMode mode) {
  return s.s('routeOptimization.mode.${mode.name}');
}

IconData _routeModeIcon(TransportMode mode) {
  return switch (mode) {
    TransportMode.walking => Icons.directions_walk_rounded,
    TransportMode.train || TransportMode.regionalTrain => Icons.train_rounded,
    TransportMode.metro => Icons.subway_rounded,
    TransportMode.bus => Icons.directions_bus_rounded,
    TransportMode.taxi => Icons.local_taxi_rounded,
    TransportMode.shinkansen => Icons.train_rounded,
  };
}

class _RouteMetricCard extends StatelessWidget {
  const _RouteMetricCard({
    required this.title,
    required this.summary,
    required this.palette,
    this.highlighted = false,
  });
  final String title;
  final RouteSummary summary;
  final ViewerPalette palette;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: highlighted
            ? palette.accent.withValues(alpha: .12)
            : palette.bg.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted
              ? palette.accent.withValues(alpha: .45)
              : palette.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: highlighted ? palette.accent : palette.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          _metric(s.s('routeOptimization.travel'),
              '${summary.totalTravelMinutes} ${s.s('routeOptimization.minute')}'),
          _metric(s.s('routeOptimization.walking'),
              '${summary.totalWalkingMinutes} ${s.s('routeOptimization.minute')}'),
          _metric(s.s('routeOptimization.transfers'),
              '${summary.totalTransferCount}'),
          _metric(s.s('routeOptimization.cost'),
              '¥${summary.estimatedTransportCostYen}'),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$label: $value',
        style: TextStyle(color: palette.textPrimary, fontSize: 12),
      ),
    );
  }
}

String _profileLabel(LanguageScope s, RouteOptimizationProfile profile) {
  return switch (profile) {
    RouteOptimizationProfile.balanced =>
      s.s('routeOptimization.profile.balanced'),
    RouteOptimizationProfile.fastest =>
      s.s('routeOptimization.profile.fastest'),
    RouteOptimizationProfile.leastWalking =>
      s.s('routeOptimization.profile.leastWalking'),
    RouteOptimizationProfile.cheapest =>
      s.s('routeOptimization.profile.cheapest'),
  };
}

String _optimizationErrorMessage(LanguageScope s, Object error) {
  if (error is PlanOptimizationException) {
    final failure = error.failure;
    if (failure == null) return s.s('routeOptimization.unavailable');
    return switch (failure.code) {
      OptimizationFailureCode.noFeasibleRoute =>
        s.s('routeOptimization.noFeasible'),
      OptimizationFailureCode.fixedTimeConflict ||
      OptimizationFailureCode.protectedActivityInfeasible =>
        s.s('routeOptimization.fixedConflict'),
      OptimizationFailureCode.routeDataMissing =>
        s.s('routeOptimization.routeDataMissing'),
      OptimizationFailureCode.duplicateActivityId ||
      OptimizationFailureCode.fixedActivityMissingTime ||
      OptimizationFailureCode.invalidRequest =>
        s.s('routeOptimization.dataIssue'),
    };
  }
  if (error is StateError) {
    return s.s('routeOptimization.missingLocation');
  }
  return s.s('routeOptimization.unavailable');
}

class _ActivityDragData {
  const _ActivityDragData({
    required this.sourceDay,
    required this.itemIndex,
    required this.itemId,
  });

  final DayPlan sourceDay;
  final int itemIndex;
  final String itemId;
}

/// Aktivite kartlarının arasındaki gerçek bırakma alanı. Sürükleme yokken
/// ince bir boşluk olarak kalır; aday üzerine geldiğinde belirginleşir.
class _ActivityDropSlot extends StatelessWidget {
  const _ActivityDropSlot({
    super.key,
    required this.palette,
    required this.targetIndex,
    required this.onAccept,
    required this.dragActive,
  });

  final ViewerPalette palette;
  final int targetIndex;
  final ValueChanged<_ActivityDragData> onAccept;

  /// null iken slot ince bir ayraç; drag başladığında hafif büyür (diğer
  /// aktiviteler yer açar), hover geldiğinde tamamen açılır.
  final ValueNotifier<String?> dragActive;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_ActivityDragData>(
      onWillAcceptWithDetails: (_) {
        HapticFeedback.selectionClick();
        return true;
      },
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidates, rejected) {
        final hovered = candidates.isNotEmpty;
        return ValueListenableBuilder<String?>(
          valueListenable: dragActive,
          builder: (context, activeId, _) {
            final dragging = activeId != null;
            // İdle: 6px görünmez; drag aktif: 22px belirgin ayrıcı; hover: 44px vurgu.
            final double h = hovered ? 44 : (dragging ? 22 : 6);
            return Semantics(
              label: 'Aktiviteyi $targetIndex. sıraya bırak',
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                height: h,
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: hovered
                      ? palette.accent.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: hovered
                      ? Border.all(
                          color: palette.accent.withValues(alpha: 0.75),
                          width: 1.5,
                        )
                      : null,
                ),
                child: hovered
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded,
                              size: 18, color: palette.accent),
                          const SizedBox(width: 6),
                          Text(
                            'Buraya bırak',
                            style: TextStyle(
                              color: palette.accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      )
                    : dragging
                        ? Center(
                            child: Container(
                              height: 2,
                              decoration: BoxDecoration(
                                color: palette.accent.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
              ),
            );
          },
        );
      },
    );
  }
}

/// Saat rozeti — uyarı varsa turuncu amber görünür + üzerinde küçük uyarı
/// ikonu ve tooltip. Tıklanınca ilgili düzenleme akışı açılır.
class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.time,
    required this.palette,
    required this.editable,
    required this.warnings,
    required this.onTap,
  });

  final String time;
  final ViewerPalette palette;
  final bool editable;
  final List<PlanWarning> warnings;
  final VoidCallback? onTap;

  static const Color _amber = Color(0xFFFF9F0A);

  @override
  Widget build(BuildContext context) {
    final hasWarning = warnings.isNotEmpty;
    final Color base = hasWarning ? _amber : palette.accent;
    final chip = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: base.withValues(alpha: hasWarning ? 0.7 : 0.35),
            width: hasWarning ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              time,
              style: TextStyle(
                color: base,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: -0.2,
              ),
            ),
            Icon(
              hasWarning
                  ? Icons.warning_amber_rounded
                  : (editable ? Icons.edit : Icons.lock),
              size: hasWarning ? 12 : 10,
              color: hasWarning
                  ? _amber
                  : (editable ? palette.accent : palette.textMuted),
            ),
          ],
        ),
      ),
    );
    if (!hasWarning) return chip;
    return Tooltip(
      message: warnings.map((w) => '• ${w.message}').join('\n'),
      preferBelow: false,
      child: chip,
    );
  }
}

/// Edit modunda üst status bar'ın hemen altına yerleşen aksiyon şeridi.
/// Şu anda tek eylem: "Tüm rotayı yeniden optimize et". İleride toplu
/// dönüşümler (bütçe yeniden dağıt, günleri sıralamayı sıfırla, vs.) buraya
/// eklenebilir.
/// Gün başlığında görünen küçük amber banner. Bir günde en az 1 uyarı varsa
/// çıkar; view modunda "Düzenleyerek çöz" ipucu verir, edit modunda "Zamanları
/// gözden geçir" der. Sadece bilgi — tıklama yok (aksiyon satır seviyesinde
/// saat rozetinde).
class _DayWarningBanner extends StatelessWidget {
  const _DayWarningBanner({
    required this.palette,
    required this.count,
    required this.editMode,
  });

  final ViewerPalette palette;
  final int count;
  final bool editMode;

  static const Color _amber = Color(0xFFFF9F0A);

  @override
  Widget build(BuildContext context) {
    final label = editMode
        ? '$count uyarı — turuncu saat rozetlerine dokunup düzelt'
        : '$count uyarı var — düzenle modundan çöz';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _amber.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: _amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _amber,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Swipe-to-delete (iOS Mail tarzı) için kırmızı arka plan.
class _SwipeDeleteBg extends StatelessWidget {
  const _SwipeDeleteBg({required this.palette});
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: const Color(0xFFE53935),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text(
              'Sil',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _dayButton(IconData icon, String label, Color color, VoidCallback onTap,
    {String? badge, Key? key}) {
  final labelWidget = badge != null
      ? Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
              child: Text(label,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 12))),
          const SizedBox(width: 4),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.4))),
              child: Text(badge,
                  style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800))),
        ])
      : Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 12));
  return TextButton.icon(
    key: key,
    onPressed: onTap,
    icon: Icon(icon, size: 16, color: color),
    style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    label: labelWidget,
  );
}

/// Rota optimizasyonu premium bilgilendirme sheet'i.
void _showOptimizePaywall(BuildContext context, ViewerPalette p) {
  final s = LanguageScope.of(context);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: p.border),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: p.textMuted.withValues(alpha: .45),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: p.gold.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_rounded, size: 28, color: p.gold),
            ),
            const SizedBox(height: 14),
            Text(
              s.s('routeOptimization.premium.title'),
              style: TextStyle(
                color: p.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.s('routeOptimization.premium.body'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  s.s('wx.close'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _JourneyProgressHero extends StatelessWidget {
  const _JourneyProgressHero({
    required this.day,
    required this.palette,
    required this.onOpenItem,
  });

  final DayPlan day;
  final ViewerPalette palette;
  final ValueChanged<TimelineItem> onOpenItem;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final now = DateTime.now();
    final date = DateTime.tryParse(day.date);
    final today = DateTime(now.year, now.month, now.day);
    final planDate =
        date == null ? null : DateTime(date.year, date.month, date.day);
    final completed = <TimelineItem>{};
    for (final item in day.items) {
      final minutes = _timeToMinutes(item.time ?? item.scheduledTime);
      final isDone = planDate != null &&
          (planDate.isBefore(today) ||
              (planDate == today &&
                  minutes != null &&
                  minutes < now.hour * 60 + now.minute));
      if (isDone) completed.add(item);
    }
    final total = day.items.length;
    final done = completed.length;
    TimelineItem? next;
    for (final item in day.items) {
      if (!completed.contains(item)) {
        next = item;
        break;
      }
    }

    return Container(
      key: const ValueKey('viewer-template-journey-hero'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 205,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    key: const ValueKey('viewer-journey-japan-line-art'),
                    painter: _JapanJourneyLineArtPainter(palette: palette),
                  ),
                ),
                SizedBox(
                  width: 138,
                  height: 138,
                  child: CustomPaint(
                    key: const ValueKey('viewer-journey-segmented-progress'),
                    painter: _SegmentedJourneyProgressPainter(
                      done: done,
                      total: total,
                      palette: palette,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          s.lang == AppLang.tr ? 'İLERLEMEN' : 'PROGRESS',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$done/$total',
                          style: TextStyle(
                            color: palette.accent,
                            fontSize: 31,
                            fontWeight: FontWeight.w900,
                            height: 1,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          s.lang == AppLang.tr ? 'tamamlandı' : 'completed',
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (next != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Material(
                color: palette.accent,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => onOpenItem(next!),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                    child: Row(
                      children: [
                        Container(
                          width: 64,
                          height: 70,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const Icon(
                            Icons.flight_land_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF655B),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      s.s('viewer.template.next').toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      _formatDayTitle(
                                        day.date,
                                        day.dayNumber,
                                        s.lang,
                                        weekdayHint: day.weekday,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${next.time ?? next.scheduledTime ?? ''}  ${next.title}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  height: 1.08,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const CircleAvatar(
                          radius: 19,
                          backgroundColor: Colors.white,
                          child:
                              Icon(Icons.chevron_right, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.matcha.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: palette.matcha),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.s('viewer.template.dayComplete'),
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
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

class _SegmentedJourneyProgressPainter extends CustomPainter {
  const _SegmentedJourneyProgressPainter({
    required this.done,
    required this.total,
    required this.palette,
  });

  final int done;
  final int total;
  final ViewerPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: size.width * 0.43);
    const gap = 0.075;
    const sweep = math.pi / 2 - gap * 2;
    final activeSegments = total == 0 ? 0 : ((done / total) * 4).ceil();
    final segmentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.butt;

    for (var index = 0; index < 4; index++) {
      segmentPaint.color = index < activeSegments
          ? palette.accent
          : Color.alphaBlend(
              palette.textSecondary.withValues(alpha: 0.10),
              palette.card,
            );
      final start = -math.pi / 2 + index * math.pi / 2 + gap;
      canvas.drawArc(rect, start, sweep, false, segmentPaint);

      final angle = start + sweep / 2;
      final labelCenter = center +
          Offset(math.cos(angle), math.sin(angle)) * (size.width * 0.43);
      final label = TextPainter(
        text: TextSpan(
          text: '${index + 1}',
          style: TextStyle(
            color:
                index < activeSegments ? Colors.white : palette.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        labelCenter - Offset(label.width / 2, label.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentedJourneyProgressPainter oldDelegate) =>
      oldDelegate.done != done ||
      oldDelegate.total != total ||
      oldDelegate.palette != palette;
}

class _JapanJourneyLineArtPainter extends CustomPainter {
  const _JapanJourneyLineArtPainter({required this.palette});

  final ViewerPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final blue = Paint()
      ..color = palette.accent.withValues(alpha: 0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final coral = Paint()
      ..color = const Color(0xFFFF5F60).withValues(alpha: 0.86)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final baselineY = size.height * 0.88;

    final tower = Path()
      ..moveTo(size.width * 0.07, baselineY)
      ..lineTo(size.width * 0.10, size.height * 0.22)
      ..lineTo(size.width * 0.13, baselineY)
      ..moveTo(size.width * 0.083, size.height * 0.62)
      ..lineTo(size.width * 0.117, size.height * 0.62)
      ..moveTo(size.width * 0.078, size.height * 0.72)
      ..lineTo(size.width * 0.122, size.height * 0.72)
      ..moveTo(size.width * 0.10, size.height * 0.22)
      ..lineTo(size.width * 0.10, size.height * 0.15);
    canvas.drawPath(tower, blue);

    final plane = Path()
      ..moveTo(size.width * 0.18, size.height * 0.39)
      ..lineTo(size.width * 0.31, size.height * 0.31)
      ..lineTo(size.width * 0.33, size.height * 0.34)
      ..lineTo(size.width * 0.24, size.height * 0.42)
      ..lineTo(size.width * 0.20, size.height * 0.51)
      ..lineTo(size.width * 0.18, size.height * 0.50)
      ..lineTo(size.width * 0.20, size.height * 0.43)
      ..close();
    canvas.drawPath(plane, blue);

    canvas.drawCircle(
      Offset(size.width * 0.79, size.height * 0.43),
      size.height * 0.105,
      Paint()..color = const Color(0xFFFF5F60),
    );
    final mountain = Path()
      ..moveTo(size.width * 0.64, baselineY)
      ..lineTo(size.width * 0.79, size.height * 0.50)
      ..lineTo(size.width * 0.92, baselineY)
      ..moveTo(size.width * 0.745, size.height * 0.62)
      ..lineTo(size.width * 0.79, size.height * 0.50)
      ..lineTo(size.width * 0.83, size.height * 0.62)
      ..lineTo(size.width * 0.805, size.height * 0.59)
      ..lineTo(size.width * 0.785, size.height * 0.63)
      ..lineTo(size.width * 0.77, size.height * 0.59)
      ..close();
    canvas.drawPath(mountain, blue);

    final pagodaX = size.width * 0.93;
    for (var index = 0; index < 3; index++) {
      final y = baselineY - index * 15;
      canvas.drawLine(
        Offset(pagodaX - 18 + index * 3, y),
        Offset(pagodaX + 18 - index * 3, y),
        blue,
      );
      canvas.drawLine(
        Offset(pagodaX - 14 + index * 3, y - 4),
        Offset(pagodaX + 14 - index * 3, y - 4),
        blue,
      );
    }
    canvas.drawLine(
      Offset(pagodaX, baselineY - 49),
      Offset(pagodaX, baselineY),
      blue,
    );

    final branch = Path()
      ..moveTo(size.width, size.height * 0.12)
      ..quadraticBezierTo(
        size.width * 0.94,
        size.height * 0.18,
        size.width * 0.90,
        size.height * 0.30,
      );
    canvas.drawPath(branch, blue);
    for (final point in [
      Offset(size.width * 0.94, size.height * 0.18),
      Offset(size.width * 0.90, size.height * 0.27),
      Offset(size.width * 0.97, size.height * 0.13),
    ]) {
      canvas.drawCircle(point, 4.2, coral);
      canvas.drawCircle(point, 1.2, coral);
    }

    canvas.drawLine(
      Offset(size.width * 0.03, baselineY),
      Offset(size.width * 0.36, baselineY),
      blue,
    );
    canvas.drawLine(
      Offset(size.width * 0.63, baselineY),
      Offset(size.width * 0.97, baselineY),
      blue,
    );
  }

  @override
  bool shouldRepaint(covariant _JapanJourneyLineArtPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

class _MapFocusHero extends StatelessWidget {
  const _MapFocusHero({
    required this.trip,
    required this.day,
    required this.days,
    required this.palette,
    required this.onSelectDay,
    required this.onOpenMap,
  });

  final Trip trip;
  final DayPlan day;
  final List<DayPlan> days;
  final ViewerPalette palette;
  final ValueChanged<DayPlan> onSelectDay;
  final ValueChanged<DayPlan> onOpenMap;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final destinations = [...trip.preferences.destinations]
      ..sort((a, b) => a.order.compareTo(b.order));
    final destination = getDestinationForDate(destinations, day.date);
    final city = cityDataForKey(destination?.city);
    final fallbackLat = destination?.lat ??
        (city?.places.isNotEmpty == true ? city!.places.first.lat : 36.2048);
    final fallbackLng = destination?.lng ??
        (city?.places.isNotEmpty == true ? city!.places.first.lng : 138.2529);
    final stops = resolveDayStops(
      day,
      cityKey: destination?.city,
      fallbackLat: fallbackLat,
      fallbackLng: fallbackLng,
    );
    final points = [for (final stop in stops) LatLng(stop.lat, stop.lng)];
    final options = points.length >= 2
        ? MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(points),
              padding: const EdgeInsets.fromLTRB(70, 62, 70, 130),
            ),
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
          )
        : MapOptions(
            initialCenter: points.isEmpty
                ? LatLng(fallbackLat, fallbackLng)
                : points.first,
            initialZoom: points.isEmpty ? 11 : 14,
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
          );

    return Container(
      key: const ValueKey('viewer-template-map-hero'),
      height: 390,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(24),
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: FlutterMap(
                key: ValueKey('viewer-map-${day.date}'),
                options: options,
                children: [
                  TileLayer(
                    urlTemplate: kRotoriTileUrlTemplate,
                    userAgentPackageName: 'com.mennansevim.rotori',
                    maxZoom: 19,
                    tileProvider: RotoriTileProvider.shared,
                  ),
                  if (points.length >= 2)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: points,
                          color: Colors.white.withValues(alpha: 0.88),
                          strokeWidth: 5.5,
                        ),
                        Polyline(
                          points: points,
                          color: const Color(0xFF1687E8),
                          strokeWidth: 3,
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      for (final stop in stops)
                        Marker(
                          point: LatLng(stop.lat, stop.lng),
                          width: 140,
                          height: 88,
                          child: _MapTemplateMarker(
                            stop: stop,
                            palette: palette,
                          ),
                        ),
                    ],
                  ),
                  RichAttributionWidget(
                    showFlutterMapAttribution: false,
                    attributions: [
                      TextSourceAttribution(
                        s.s('map.osmAttribution'),
                        onTap: () async {
                          await launchUrl(
                            Uri.parse(kOpenStreetMapCopyrightUrl),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 102,
            child: Material(
              color: Colors.transparent,
              child: InkWell(onTap: () => onOpenMap(day)),
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            child: Material(
              color: palette.card.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(999),
              elevation: 2,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onOpenMap(day),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.layers_outlined,
                          color: palette.textPrimary, size: 18),
                      const SizedBox(width: 7),
                      Text(
                        LanguageScope.of(context)
                            .s('viewer.template.map.layers'),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 86,
            child: Material(
              color: palette.card.withValues(alpha: 0.97),
              shape: const CircleBorder(),
              elevation: 4,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onOpenMap(day),
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: Icon(
                    Icons.my_location_rounded,
                    color: palette.textPrimary,
                    size: 25,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: SizedBox(
              height: 68,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final separatorWidth = days.length > 5 ? 4.0 : 6.0;
                  final chipWidth = days.isEmpty
                      ? constraints.maxWidth
                      : (constraints.maxWidth -
                              separatorWidth * (days.length - 1)) /
                          days.length;
                  return ListView.separated(
                    key: const ValueKey('viewer-map-day-strip'),
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: days.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(width: separatorWidth),
                    itemBuilder: (context, index) {
                      final candidate = days[index];
                      final selected = candidate.dayNumber == day.dayNumber;
                      final parsed = DateTime.tryParse(candidate.date);
                      final lang = LanguageScope.of(context).lang;
                      final month = parsed == null
                          ? ''
                          : L10n.monthsFor(lang)[parsed.month];
                      final shortMonth =
                          month.length > 3 ? month.substring(0, 3) : month;
                      final weekday = parsed == null
                          ? ''
                          : L10n.weekdaysFor(lang)[parsed.weekday];
                      final shortWeekday = weekday.length > 3
                          ? weekday.substring(0, 3)
                          : weekday;
                      const chipTints = [
                        Color(0xFF368BFF),
                        Color(0xFFFFB52E),
                        Color(0xFFFF668C),
                        Color(0xFF8B6CFF),
                        Color(0xFF35B979),
                        Color(0xFF24AFC0),
                        Color(0xFFFF7A59),
                      ];
                      final tint = chipTints[index % chipTints.length];
                      final chipColor = Color.alphaBlend(
                        tint.withValues(alpha: selected ? 0.20 : 0.10),
                        palette.card,
                      );
                      return Material(
                        color: chipColor.withValues(alpha: 0.98),
                        borderRadius: BorderRadius.circular(14),
                        elevation: selected ? 3 : 1,
                        child: InkWell(
                          key: ValueKey(
                            'viewer-map-day-${candidate.dayNumber}',
                          ),
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => onSelectDay(candidate),
                          child: Container(
                            width: chipWidth,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? palette.accent
                                    : tint.withValues(alpha: 0.42),
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  parsed == null
                                      ? '${candidate.dayNumber}'
                                      : '${parsed.day}',
                                  style: TextStyle(
                                    color: selected
                                        ? palette.accent
                                        : palette.textPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    height: 1,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  shortMonth,
                                  style: TextStyle(
                                    color: selected
                                        ? palette.accent
                                        : palette.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  shortWeekday,
                                  style: TextStyle(
                                    color: palette.textSecondary,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapTemplateMarker extends StatelessWidget {
  const _MapTemplateMarker({required this.stop, required this.palette});

  final ResolvedStop stop;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 30,
          child: SizedBox(
            width: 28,
            height: 28,
            child: _MapTemplatePin(
              order: stop.order,
              palette: palette,
            ),
          ),
        ),
        Positioned(
          top: stop.order.isOdd ? 0 : 62,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 136),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(7),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              stop.item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF172033),
                fontSize: 9.2,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MapTemplatePin extends StatelessWidget {
  const _MapTemplatePin({required this.order, required this.palette});

  final int order;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.sakura,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$order',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DayCard extends StatefulWidget {
  const _DayCard({
    super.key,
    required this.day,
    required this.palette,
    required this.template,
    required this.dest,
    required this.bubbleColor,
    this.forecast,
    this.canOptimizeForWeather = false,
    required this.isPast,
    required this.isActive,
    required this.expanded,
    required this.onToggleExpand,
    required this.editMode,
    required this.allDays,
    required this.onOpenItem,
    required this.onOpenMap,
    required this.isPremium,
    required this.onOptimizeRoute,
    required this.onOptimizeWeatherRoute,
    required this.onDropItem,
    required this.onDeleteItem,
    required this.onEditItemTime,
    required this.onToggleItemLock,
    required this.onAddItem,
    required this.onEditDay,
    required this.onMoveDay,
    required this.onDragUpdate,
    required this.dragActive,
  });
  final DayPlan day;
  final ViewerPalette palette;
  final ViewerTemplateId template;
  final TripDestination? dest;
  final Color bubbleColor;
  final DayForecast? forecast;

  /// Hava temelli optimizasyon bu gün için anlamlı mı? `false` iken CTA hiç
  /// çizilmez — düzgün bir planı "optimize et" diye çağırmak güveni tüketir.
  final bool canOptimizeForWeather;
  final bool isPast;
  final bool isActive;

  /// Akordiyon: bu gün açık mı? (parent tek-açık mantığını yönetir).
  final bool expanded;

  /// Başlığa tıklanınca aç/kapa (parent state'i günceller).
  final VoidCallback onToggleExpand;

  /// True ise her item için sıralama/taşıma/kaldırma menüsü çıkar; itemler
  /// tıklandığında normal detay yerine bu menüyü de gösterir.
  final bool editMode;

  /// Başka güne taşıma menüsünü besleyen tüm gün listesi (sıralı).
  final List<DayPlan> allDays;

  final void Function(TimelineItem item, TripDestination? dest) onOpenItem;
  final void Function(DayPlan day) onOpenMap;

  /// Kullanıcı premium mü? Rota optimizasyonu buna göre çalışır ya da
  /// paywall gösterir. Tek kaynak: premiumProvider.
  final bool isPremium;

  /// Premium'da gerçek rota optimizasyonunu açar.
  final VoidCallback onOptimizeRoute;
  final void Function(
    DayPlan day,
    TripDestination? destination,
    DayForecast? forecast,
  ) onOptimizeWeatherRoute;

  /// Item'ı bırakılan kesin satır aralığına taşır.
  final void Function(
    DayPlan source,
    String itemId,
    DayPlan target,
    int targetIndex,
  ) onDropItem;

  /// Item'ı plandan kaldır (SnackBar ile undo verilir).
  final void Function(DayPlan day, int itemIdx) onDeleteItem;

  /// Bir durağın saatini düzenle (time picker) → gün yeniden saatlenir.
  final void Function(DayPlan day, int itemIdx) onEditItemTime;

  /// Kullanıcı kilidini aç/kapa (bileti alınmış durakları korumak için).
  final void Function(DayPlan day, TimelineItem item) onToggleItemLock;

  /// Bu güne yeni durak ekle (autocomplete + saat sheet).
  final void Function(DayPlan day, TripDestination? dest) onAddItem;
  final void Function(DayPlan day) onEditDay;
  final void Function(DayPlan day, int offset) onMoveDay;
  final ValueChanged<DragUpdateDetails> onDragUpdate;

  /// Global drag state — herhangi bir aktivite sürüklenirken doldurulur.
  /// Drop-slot'lar dinleyip "diğerleri yer açıyor" görünümü verir.
  final ValueNotifier<String?> dragActive;

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  Timer? _springLoadTimer;
  bool _isDropTarget = false;

  @override
  void dispose() {
    _springLoadTimer?.cancel();
    super.dispose();
  }

  void _startSpringLoad() {
    if (_springLoadTimer != null || widget.expanded) return;
    _springLoadTimer = Timer(const Duration(milliseconds: 550), () {
      _springLoadTimer = null;
      if (mounted && _isDropTarget && !widget.expanded) {
        widget.onToggleExpand();
      }
    });
  }

  void _clearDropTarget() {
    _springLoadTimer?.cancel();
    _springLoadTimer = null;
    if (_isDropTarget && mounted) setState(() => _isDropTarget = false);
  }

  /// Aktif günde, şimdiki dakikaya göre bir sonraki gelecek aktivitenin index'i.
  int? _nextUpcomingIndex(DateTime now) {
    if (!widget.isActive) return null;
    final dayDate = DateTime.tryParse(widget.day.date);
    if (dayDate == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    final planDate = DateTime(dayDate.year, dayDate.month, dayDate.day);
    if (planDate.isBefore(today)) return null;
    final threshold = planDate.isAfter(today) ? -1 : now.hour * 60 + now.minute;
    int? best;
    var bestMin = 1 << 30;
    for (var i = 0; i < widget.day.items.length; i++) {
      final it = widget.day.items[i];
      final m = _timeToMinutes(it.time ?? it.scheduledTime);
      if (m == null) continue;
      if (m >= threshold && m < bestMin) {
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
    final compact = widget.template == ViewerTemplateId.mapFocus;
    final cardRadius = compact ? 22.0 : 18.0;
    // Akordiyon: parent tek-açık mantığını yönetir. Düzenleme modunda tüm
    // günler zorla açık (kullanıcı kapalı gündeki item'ı düzenleyemez).
    final expanded = widget.expanded;
    final dayIndex = widget.allDays
        .indexWhere((candidate) => candidate.dayNumber == day.dayNumber);
    final now = DateTime.now();
    final nextIdx = _nextUpcomingIndex(now);
    // Uyarıları hesapla (saf-Dart, hızlı) — satırlar bunları saat rozetinde
    // gösterir, gün başlığı ise özet banner çıkarır.
    final warningsMap = warningsByActivity(day);
    final totalWarnings =
        warningsMap.values.fold<int>(0, (acc, list) => acc + list.length);
    final routeLegs = _displayRouteLegs(day, widget.dest);

    final card = Container(
      margin: EdgeInsets.only(bottom: compact ? 6 : 12),
      decoration: BoxDecoration(
        color: compact ? p.card : (widget.isActive ? p.cardHover : p.card),
        borderRadius: BorderRadius.circular(cardRadius),
        border: Border.all(
          color: widget.isActive && !compact
              ? p.sakura.withValues(alpha: 0.45)
              : p.border,
          width: widget.isActive && !compact ? 1.5 : 1,
        ),
        boxShadow: widget.isActive && !compact
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
            borderRadius: BorderRadius.circular(cardRadius),
            onTap: widget.onToggleExpand,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 14,
                vertical: compact ? 9 : 14,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DayBadge(
                    day: day,
                    palette: p,
                    bubbleColor: widget.bubbleColor,
                    compact: compact,
                  ),
                  SizedBox(width: compact ? 10 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                _formatDayTitle(
                                  day.date,
                                  day.dayNumber,
                                  LanguageScope.of(context).lang,
                                  weekdayHint: day.weekday,
                                ),
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: compact ? 14.5 : 15,
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
                  if (widget.editMode)
                    PopupMenuButton<String>(
                      tooltip:
                          LanguageScope.of(context).s('viewer.edit.editDay'),
                      icon: Icon(Icons.more_horiz, color: p.textMuted),
                      onSelected: (value) {
                        if (value == 'edit') widget.onEditDay(day);
                        if (value == 'up') widget.onMoveDay(day, -1);
                        if (value == 'down') widget.onMoveDay(day, 1);
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(LanguageScope.of(context)
                              .s('viewer.edit.editDay')),
                        ),
                        if (dayIndex > 0)
                          PopupMenuItem(
                            value: 'up',
                            child: Text(LanguageScope.of(context)
                                .s('viewer.edit.moveUp')),
                          ),
                        if (dayIndex >= 0 &&
                            dayIndex < widget.allDays.length - 1)
                          PopupMenuItem(
                            value: 'down',
                            child: Text(LanguageScope.of(context)
                                .s('viewer.edit.moveDown')),
                          ),
                      ],
                    ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.expand_more,
                      color: p.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            clipBehavior: Clip.hardEdge,
            child: !expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 10 : 14,
                      0,
                      compact ? 10 : 14,
                      compact ? 10 : 14,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DayMeta(day: day, palette: p),
                        const SizedBox(height: 4),
                        if (totalWarnings > 0) ...[
                          _DayWarningBanner(
                            palette: p,
                            count: totalWarnings,
                            editMode: widget.editMode,
                          ),
                          const SizedBox(height: 6),
                        ],
                        if (widget.editMode) ...[
                          // Düzenleme: sürükle-bırak sıralama + sol ok butonları +
                          // saate dokunarak düzenleme. Boşsa doğrudan ekleme çubuğu.
                          if (day.items.isEmpty)
                            _ActivityDropSlot(
                              key: ValueKey('drop-day-${day.dayNumber}-slot-0'),
                              palette: p,
                              targetIndex: 0,
                              dragActive: widget.dragActive,
                              onAccept: (data) => widget.onDropItem(
                                data.sourceDay,
                                data.itemId,
                                day,
                                0,
                              ),
                            )
                          else
                            Column(
                              children: [
                                for (var i = 0; i < day.items.length; i++) ...[
                                  _ActivityDropSlot(
                                    key: ValueKey(
                                        'drop-day-${day.dayNumber}-slot-$i'),
                                    palette: p,
                                    targetIndex: i,
                                    dragActive: widget.dragActive,
                                    onAccept: (data) => widget.onDropItem(
                                      data.sourceDay,
                                      data.itemId,
                                      day,
                                      i,
                                    ),
                                  ),
                                  Builder(
                                    builder: (context) {
                                      final item = day.items[i];
                                      final row = _EditableTimelineRow(
                                        day: day,
                                        index: i,
                                        palette: p,
                                        dest: widget.dest,
                                        allDays: widget.allDays,
                                        warnings:
                                            warningsMap[item.id] ?? const [],
                                        onEditTime: () =>
                                            widget.onEditItemTime(day, i),
                                        onOpen: () => widget.onOpenItem(
                                            item, widget.dest),
                                        onToggleLock: () =>
                                            widget.onToggleItemLock(day, item),
                                      );
                                      final canDelete =
                                          item.canDelete && !item.isFixed;
                                      // Swipe-to-delete (Apple standardı): sola
                                      // sürükleyince silinir. Yalnızca silinebilir
                                      // ve sabit olmayan aktivitelerde aktif.
                                      Widget dismissible = canDelete
                                          ? Dismissible(
                                              key: ValueKey(
                                                  'dismiss-${item.id}'),
                                              direction:
                                                  DismissDirection.endToStart,
                                              dismissThresholds: const {
                                                DismissDirection.endToStart:
                                                    0.4,
                                              },
                                              background:
                                                  const SizedBox.shrink(),
                                              secondaryBackground:
                                                  _SwipeDeleteBg(palette: p),
                                              onDismissed: (_) {
                                                HapticFeedback.mediumImpact();
                                                widget.onDeleteItem(day, i);
                                              },
                                              child: row,
                                            )
                                          : row;
                                      if (item.isFixed || !item.canChangeDay) {
                                        return dismissible;
                                      }
                                      return Semantics(
                                        label: LanguageScope.of(context)
                                            .s('viewer.edit.dragHint'),
                                        button: true,
                                        child: LongPressDraggable<
                                            _ActivityDragData>(
                                          key: ValueKey('draggable-${item.id}'),
                                          data: _ActivityDragData(
                                            sourceDay: day,
                                            itemIndex: i,
                                            itemId: item.id,
                                          ),
                                          maxSimultaneousDrags: 1,
                                          onDragStarted: () {
                                            HapticFeedback.mediumImpact();
                                            widget.dragActive.value = item.id;
                                          },
                                          onDragUpdate: widget.onDragUpdate,
                                          onDragEnd: (_) {
                                            HapticFeedback.lightImpact();
                                            widget.dragActive.value = null;
                                          },
                                          onDraggableCanceled: (_, __) =>
                                              widget.dragActive.value = null,
                                          onDragCompleted: () =>
                                              widget.dragActive.value = null,
                                          feedback: Material(
                                            color: Colors.transparent,
                                            child: SizedBox(
                                              width: MediaQuery.sizeOf(context)
                                                      .width -
                                                  56,
                                              child: Transform.scale(
                                                scale: 1.03,
                                                child: row,
                                              ),
                                            ),
                                          ),
                                          childWhenDragging: Opacity(
                                            opacity: 0.2,
                                            child: row,
                                          ),
                                          child: dismissible,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                                _ActivityDropSlot(
                                  key: ValueKey(
                                      'drop-day-${day.dayNumber}-slot-${day.items.length}'),
                                  palette: p,
                                  targetIndex: day.items.length,
                                  dragActive: widget.dragActive,
                                  onAccept: (data) => widget.onDropItem(
                                    data.sourceDay,
                                    data.itemId,
                                    day,
                                    day.items.length,
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 6),
                          _AddPlaceBar(
                            palette: p,
                            onTap: () => widget.onAddItem(day, widget.dest),
                          ),
                        ] else ...[
                          if (day.items.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                LanguageScope.of(context)
                                    .s('viewer.day.noItems'),
                                style: TextStyle(color: p.textMuted),
                              ),
                            )
                          else
                            for (var i = 0; i < day.items.length; i++) ...[
                              // Geliş bacağı ayrı bir satır değil, durağın alt
                              // başlığıdır: "Dotonbori / Yürüyerek · 18 dk".
                              _TimelineRow(
                                item: day.items[i],
                                inboundLeg: _inboundLegFor(
                                  routeLegs,
                                  day.items[i].id,
                                ),
                                palette: p,
                                dest: widget.dest,
                                isNext: i == nextIdx,
                                isPastItem: widget.isActive &&
                                    _isItemPast(day, day.items[i], now),
                                isFirst: i == 0,
                                isLast: i == day.items.length - 1,
                                warnings:
                                    warningsMap[day.items[i].id] ?? const [],
                                onOpen: () => widget.onOpenItem(
                                    day.items[i], widget.dest),
                              ),
                            ],
                          for (final leg in routeLegs.where((leg) =>
                              !leg.isTrivial &&
                              leg.kind == RouteExecutionLegKind.returnToBase))
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 3, 0, 5),
                              child: _RouteExecutionLegCard(
                                key: ValueKey(
                                  'saved-route-return-${day.dayNumber}-${leg.fromLocationId}',
                                ),
                                leg: leg,
                                palette: p,
                                compact: true,
                              ),
                            ),
                          if (day.items.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(children: [
                              Expanded(
                                  child: _dayButton(
                                      Icons.map_outlined,
                                      LanguageScope.of(context)
                                          .s('viewer.day.viewOnMap'),
                                      p.accent,
                                      () => widget.onOpenMap(day))),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _dayButton(
                                  widget.isPremium
                                      ? Icons.auto_awesome
                                      : Icons.lock_outlined,
                                  LanguageScope.of(context)
                                      .s('routeOptimization.action'),
                                  widget.isPremium ? p.accent : p.textMuted,
                                  widget.isPremium
                                      ? widget.onOptimizeRoute
                                      : () => _showOptimizePaywall(context, p),
                                  badge: widget.isPremium ? null : 'Premium',
                                  key: ValueKey(
                                      'optimize-route-${day.dayNumber}'),
                                ),
                              ),
                            ]),
                          ],
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );

    // Geçmiş günler pasif renklerle solutulmuyor — plan sonrası da net okunsun,
    // ilk günün gri görünmesi ortadan kalksın. "Aktif gün" vurgusu accent
    // seçicilerle (isNext, aktif index) zaten yeterli.
    if (!widget.editMode) return card;
    return DragTarget<_ActivityDragData>(
      onWillAcceptWithDetails: (details) {
        final accepts = details.data.sourceDay.dayNumber != day.dayNumber;
        if (accepts && !_isDropTarget) {
          setState(() => _isDropTarget = true);
          _startSpringLoad();
          HapticFeedback.selectionClick();
        }
        return accepts;
      },
      onLeave: (_) => _clearDropTarget(),
      onAcceptWithDetails: (details) {
        _clearDropTarget();
        final data = details.data;
        widget.onDropItem(
          data.sourceDay,
          data.itemId,
          day,
          day.items.length,
        );
      },
      builder: (context, candidates, rejected) => AnimatedScale(
        scale: _isDropTarget ? 1.01 : 1,
        duration: const Duration(milliseconds: 160),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 14 : 20),
            border:
                _isDropTarget ? Border.all(color: p.accent, width: 2) : null,
          ),
          child: card,
        ),
      ),
    );
  }

  bool _isItemPast(DayPlan day, TimelineItem item, DateTime now) {
    final dayDate = DateTime.tryParse(day.date);
    if (dayDate == null) return false;
    final today = DateTime(now.year, now.month, now.day);
    final planDate = DateTime(dayDate.year, dayDate.month, dayDate.day);
    if (planDate.isAfter(today)) return false;
    if (planDate.isBefore(today)) return true;
    final m = _timeToMinutes(item.time ?? item.scheduledTime);
    if (m == null) return false;
    return m < now.hour * 60 + now.minute;
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
              IconButton(
                tooltip: s.s('wx.close'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
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
            if (widget.canOptimizeForWeather)
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onOptimizeWeatherRoute(
                    widget.day,
                    widget.dest,
                    widget.forecast,
                  );
                },
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: Text(s.s('routeOptimization.weatherAction')),
              ),
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
  const _DayBadge({
    required this.day,
    required this.palette,
    required this.bubbleColor,
    required this.compact,
  });
  final DayPlan day;
  final ViewerPalette palette;
  final Color bubbleColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final lang = LanguageScope.of(context).lang;
    final d = DateTime.tryParse(day.date);
    // Rozet: büyük = ayın günü (ör. 25), küçük = kısa ay adı (ör. Ara).
    final dayOfMonth = d != null ? '${d.day}' : '${day.dayNumber}';
    final monthFull = d != null ? L10n.monthsFor(lang)[d.month] : '';
    final monthShort =
        monthFull.length > 3 ? monthFull.substring(0, 3) : monthFull;
    return Container(
      width: compact ? 46 : 54,
      height: compact ? 46 : 54,
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(compact ? 11 : 14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            dayOfMonth,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 18 : 20,
              height: 1,
            ),
          ),
          if (monthShort.isNotEmpty)
            Text(
              monthShort,
              style: TextStyle(
                color: Colors.white70,
                fontSize: compact ? 9 : 10,
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
    // Tek satır: alta sarkmasın, taşarsa yatay kaydırılır (Apple tarzı chip şeridi).
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: SizedBox(
        height: 28,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: chips.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) => Align(
            alignment: Alignment.centerLeft,
            child: chips[i],
          ),
        ),
      ),
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
    required this.onEditTime,
    required this.onOpen,
    required this.onToggleLock,
    this.warnings = const [],
  });

  final DayPlan day;
  final int index;
  final ViewerPalette palette;
  final TripDestination? dest;
  final List<DayPlan> allDays;
  final VoidCallback onEditTime;
  final VoidCallback onOpen;

  /// Kullanıcı kilidini aç/kapa. Sistem kilitli duraklarda çağrılmaz.
  final VoidCallback onToggleLock;

  /// Bu satırın plan uyarıları (zaman çakışması / yemek penceresi ihlali).
  /// Boş liste → normal görünüm. Doluysa saat rozeti turuncuya döner ve
  /// üstünde uyarı ikonu belirir.
  final List<PlanWarning> warnings;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = LanguageScope.of(context);
    final item = day.items[index];
    final time = item.time ?? item.scheduledTime ?? '--:--';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: p.elevated.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.border),
        ),
        padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Sol tutamaç: yalnızca 3 çizgi (drag_handle). Ok yok — Apple standardı,
            // basılı tut → sürükle. Sabit satırda kilit rozeti.
            SizedBox(
              width: 22,
              child: Center(
                child: (item.canReorder && !item.isFixed)
                    ? Semantics(
                        label: s.s('viewer.edit.dragHint'),
                        button: true,
                        child: Icon(
                          Icons.drag_handle_rounded,
                          size: 20,
                          color: p.textMuted,
                        ),
                      )
                    // Kullanıcı kilidi dokunulabilir ve accent renkte: sistem
                    // kilidinden (gri, sabit) hem görsel hem davranışça ayrı.
                    : Semantics(
                        label: item.isUserPinned
                            ? s.s('viewer.edit.unpin')
                            : item.lockReason ?? s.s('viewer.edit.fixedReason'),
                        button: item.isUserPinned,
                        child: IconButton(
                          key: ValueKey('unpin-${item.id}'),
                          onPressed: item.isUserPinned ? onToggleLock : null,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 22,
                            minHeight: 32,
                          ),
                          tooltip: item.isUserPinned
                              ? s.s('viewer.edit.unpin')
                              : s.s('viewer.edit.pinSystemLocked'),
                          icon: Icon(
                            Icons.lock_rounded,
                            size: item.isUserPinned ? 17 : 15,
                            color: item.isUserPinned ? p.accent : p.textMuted,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 4),
            // Saat rozeti — dokununca time picker. Uyarı varsa turuncu
            // (Apple system amber #FF9F0A) + üstünde uyarı ikonu; tooltip
            // uyarının nedenini gösterir.
            _TimeChip(
              time: time,
              palette: p,
              editable: item.canChangeTime && !item.isFixed,
              warnings: warnings,
              onTap: item.canChangeTime && !item.isFixed ? onEditTime : null,
            ),
            const SizedBox(width: 10),
            // Başlık + açıklama — tıklanınca detay.
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onOpen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    if (item.description != null &&
                        item.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          item.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: p.textSecondary, fontSize: 11.5),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // 3-nokta menü kaldırıldı (Apple standardı):
            // • Silme  → sola swipe (Dismissible)
            // • Taşıma → basılı tut + günler arası sürükle-bırak
            // • Detay  → satıra tıkla
            // • Kilit  → açık kilit rozetine dokun
            //
            // Kilitli durakta rozet zaten solda (dokunulabilir) duruyor;
            // burada yalnız HENÜZ kilitlenmemiş duraklar için "kilitle"
            // aksiyonu gösterilir.
            if (item.canUserToggleLock && !item.isFixed)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Semantics(
                  label: s.s('viewer.edit.pin'),
                  button: true,
                  child: IconButton(
                    key: ValueKey('pin-${item.id}'),
                    onPressed: onToggleLock,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 32,
                    ),
                    tooltip: s.s('viewer.edit.pin'),
                    icon: Icon(
                      Icons.lock_open_rounded,
                      size: 15,
                      color: p.textMuted,
                    ),
                  ),
                ),
              )
            else if (item.isFixed && !item.isUserPinned)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Semantics(
                  label: item.lockReason ?? s.s('viewer.edit.fixedReason'),
                  child: Icon(
                    Icons.lock_rounded,
                    size: 14,
                    color: p.textMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Küçük, dokunması kolay ok butonu (edit modu sıralama okları).
// ignore: unused_element
class _MiniIconBtn extends StatelessWidget {
  const _MiniIconBtn({
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: enabled ? onTap : null,
      radius: 16,
      child: Icon(
        icon,
        size: 20,
        color: enabled ? color : color.withValues(alpha: 0.25),
      ),
    );
  }
}

/// Düzenleme modunda her günün altında beliren "durak ekle" çubuğu.
class _AddPlaceBar extends StatelessWidget {
  const _AddPlaceBar({required this.palette, required this.onTap});
  final ViewerPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: DottedBorderBox(
            color: p.accent.withValues(alpha: 0.55),
            radius: 14,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, size: 18, color: p.accent),
                  const SizedBox(width: 8),
                  Text(
                    LanguageScope.of(context).s('viewer.edit.addPlace'),
                    style: TextStyle(
                      color: p.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kesikli çerçeveli kutu (ekle çubuğu için). Basit CustomPaint.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({
    super.key,
    required this.child,
    required this.color,
    this.radius = 12,
  });
  final Widget child;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: color, radius: radius),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final next = dist + dash;
        canvas.drawPath(
          metric.extractPath(dist, next.clamp(0, metric.length)),
          paint,
        );
        dist = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

/// "Durak ekle" sheet sonucu.
class _AddPlaceResult {
  const _AddPlaceResult({
    required this.title,
    required this.time,
    required this.kind,
    required this.durationMin,
    required this.hasTicket,
    required this.arrivalBufferMin,
    this.lat,
    this.lng,
  });
  final String title;
  final String time;
  final TimelineItemKind kind;
  final int durationMin;
  final bool hasTicket;
  final int arrivalBufferMin;
  final double? lat;
  final double? lng;
}

class _EditItemResult {
  const _EditItemResult({
    required this.targetDay,
    required this.timeMinutes,
    required this.durationMinutes,
  });
  final DayPlan targetDay;
  final int timeMinutes;
  final int durationMinutes;
}

/// Aktivitenin gün + saatini birlikte düzenleyen bottom-sheet. Kullanıcı gün
/// değiştirmezse saat aynı gün içinde uygulanır; gün değiştirdiği anda saat
/// otomatik olarak hedef günün son aktivitesi + 90 dk'ya kayar — kullanıcı
/// isterse saati elle tekrar seçebilir.
class _EditItemDayTimeSheet extends StatefulWidget {
  const _EditItemDayTimeSheet({
    required this.palette,
    required this.trip,
    required this.item,
    required this.currentDay,
    required this.allDays,
    this.initialTargetDay,
  });

  final ViewerPalette palette;
  final Trip trip;
  final TimelineItem item;
  final DayPlan currentDay;
  final List<DayPlan> allDays;
  final DayPlan? initialTargetDay;

  @override
  State<_EditItemDayTimeSheet> createState() => _EditItemDayTimeSheetState();
}

class _EditItemDayTimeSheetState extends State<_EditItemDayTimeSheet> {
  static const _engine = PlanScheduleEngine();
  static const _firstSlot = kRouteStartMinuteOfDay;
  static const _lastSlot = kRouteEndMinuteOfDay;
  late DayPlan _targetDay;
  late int _timeMinutes;
  late int _durationMinutes;
  late List<int> _availableSlots;

  @override
  void initState() {
    super.initState();
    _targetDay = widget.initialTargetDay ?? widget.currentDay;
    _timeMinutes =
        sched.timeToMinutes(widget.item.time ?? widget.item.scheduledTime) ??
            9 * 60;
    _durationMinutes = widget.item.durationMin ?? 60;
    _refreshAvailableSlots(_timeMinutes);
  }

  void _refreshAvailableSlots(int wanted) {
    _availableSlots = _engine.availableStartMinutes(
      widget.trip,
      sourceDayNumber: widget.currentDay.dayNumber,
      activityId: widget.item.id,
      targetDayNumber: _targetDay.dayNumber,
      durationMinutes: _durationMinutes,
      firstMinute: _firstSlot,
      lastMinute: _lastSlot,
    );
    final nearest = _nearestAvailable(wanted, _availableSlots);
    if (nearest != null) _timeMinutes = nearest;
  }

  int? _nearestAvailable(int wanted, List<int> slots) {
    if (slots.isEmpty) return null;
    var nearest = slots.first;
    var distance = (nearest - wanted).abs();
    for (final slot in slots.skip(1)) {
      final candidateDistance = (slot - wanted).abs();
      // Eşit uzaklıkta ileri slotu seç: kullanıcının mevcut plan akışını
      // geriye çekmek yerine günün devamına eklemek daha öngörülebilir.
      if (candidateDistance <= distance) {
        nearest = slot;
        distance = candidateDistance;
      }
    }
    return nearest;
  }

  void _pickDay(DayPlan d) {
    if (identical(d, _targetDay)) return;
    setState(() {
      _targetDay = d;
      _refreshAvailableSlots(_timeMinutes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final p = widget.palette;
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final available = _availableSlots.toSet();
    final hasAvailableSlot = available.isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.textMuted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                s.s('viewer.edit.editSheetTitle'),
                style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.item.title,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              Text(
                s.s('viewer.edit.dayLabel'),
                style: TextStyle(
                  color: p.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final d in widget.allDays)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _EditDayChip(
                          label: s.p(
                              'viewer.edit.dayShort', {'n': '${d.dayNumber}'}),
                          date: d.date,
                          active: identical(d, _targetDay),
                          palette: p,
                          onTap: () => _pickDay(d),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                s.s('viewer.edit.timeLabel'),
                style: TextStyle(
                  color: p.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                hasAvailableSlot
                    ? s.s('viewer.edit.availableTimeHint')
                    : s.s('viewer.edit.noAvailableTime'),
                style: TextStyle(
                  color: hasAvailableSlot ? p.textMuted : p.sunset,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 174,
                child: GridView.builder(
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.15,
                  ),
                  itemCount: ((_lastSlot - _firstSlot) ~/ 15) + 1,
                  itemBuilder: (context, index) {
                    final minute = _firstSlot + index * 15;
                    final enabled = available.contains(minute);
                    final selected = enabled && minute == _timeMinutes;
                    final label = _minutesToTime(minute);
                    return Semantics(
                      label: label,
                      enabled: enabled,
                      selected: selected,
                      button: true,
                      child: InkWell(
                        key: ValueKey('time-slot-$minute'),
                        onTap: enabled
                            ? () => setState(() => _timeMinutes = minute)
                            : null,
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? p.accent
                                : enabled
                                    ? p.accent.withValues(alpha: 0.10)
                                    : p.elevated.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? p.accent
                                  : enabled
                                      ? p.accent.withValues(alpha: 0.28)
                                      : p.border.withValues(alpha: 0.55),
                            ),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : enabled
                                      ? p.accent
                                      : p.textMuted.withValues(alpha: 0.52),
                              fontWeight:
                                  selected ? FontWeight.w800 : FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text(
                s.s('viewer.edit.durationLabel'),
                style: TextStyle(
                  color: p.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _durationMinutes,
                dropdownColor: p.card,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.timelapse_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: [
                  for (final minutes in const [30, 45, 60, 90, 120, 180, 240])
                    DropdownMenuItem(
                      value: minutes,
                      child: Text(s.p('viewer.edit.durationMinutes', {
                        'minutes': '$minutes',
                      })),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _durationMinutes = value;
                      _refreshAvailableSlots(_timeMinutes);
                    });
                  }
                },
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.textPrimary,
                        side: BorderSide(color: p.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(s.s('viewer.edit.cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: available.contains(_timeMinutes)
                          ? () => Navigator.pop(
                                context,
                                _EditItemResult(
                                  targetDay: _targetDay,
                                  timeMinutes: _timeMinutes,
                                  durationMinutes: _durationMinutes,
                                ),
                              )
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(s.s('viewer.edit.save')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditDayChip extends StatelessWidget {
  const _EditDayChip({
    required this.label,
    required this.date,
    required this.active,
    required this.palette,
    required this.onTap,
  });
  final String label;
  final String date;
  final bool active;
  final ViewerPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:
              active ? palette.accent : palette.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? palette.accent
                : palette.accent.withValues(alpha: 0.30),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : palette.accent,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Şehir bazlı autocomplete + saat girişli durak ekleme sheet'i.
class _AddPlaceSheet extends StatefulWidget {
  const _AddPlaceSheet({
    required this.palette,
    required this.city,
    required this.cityLabel,
    required this.defaultTime,
  });
  final ViewerPalette palette;
  final CityData? city;
  final String cityLabel;
  final String defaultTime;

  @override
  State<_AddPlaceSheet> createState() => _AddPlaceSheetState();
}

class _AddPlaceSheetState extends State<_AddPlaceSheet> {
  final _controller = TextEditingController();
  late String _time = widget.defaultTime;
  CityPlace? _selected;
  bool _hasTicket = false;
  int _durationMin = 90;
  int _arrivalBufferMin = 30;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<CityPlace> get _suggestions {
    final q = _controller.text.trim().toLowerCase();
    final all = widget.city?.places ?? const <CityPlace>[];
    if (q.isEmpty) return all;
    return all
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.category.tr.toLowerCase().contains(q) ||
            p.category.en.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _pickTime() async {
    final cur = _timeToMinutes(_time) ?? 9 * 60;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
      builder: (ctx, child) => Theme(
        data: widget.palette.toThemeData(),
        child: MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _time = _minutesToTime(picked.hour * 60 + picked.minute));
  }

  void _applyTicketDefaults(String title) {
    final defaults = ticketedActivityDefaultsForTitle(title);
    _durationMin = defaults.durationMinutes;
    _arrivalBufferMin = defaults.arrivalBufferMinutes;
    if (defaults.fullDay) _time = '09:00';
  }

  String _durationLabel(LanguageScope s, int minutes) {
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours == 0) return s.p('plan.durMin', {'n': '$minutes'});
    if (remainder == 0) return s.p('plan.durHour', {'n': '$hours'});
    return s.p('plan.durHourMin', {'h': '$hours', 'm': '$remainder'});
  }

  void _submit() {
    final q = _controller.text.trim();
    if (_selected == null && q.isEmpty) return;
    final result = _selected != null
        ? _AddPlaceResult(
            title: _selected!.name,
            time: _time,
            kind: _kindForCategory(_selected!.category.en),
            durationMin: _durationMin,
            hasTicket: _hasTicket,
            arrivalBufferMin: _arrivalBufferMin,
            lat: _selected!.lat,
            lng: _selected!.lng,
          )
        : _AddPlaceResult(
            title: q,
            time: _time,
            kind: TimelineItemKind.activity,
            durationMin: _durationMin,
            hasTicket: _hasTicket,
            arrivalBufferMin: _arrivalBufferMin,
          );
    Navigator.of(context).pop(result);
  }

  TimelineItemKind _kindForCategory(String catEn) {
    final c = catEn.toLowerCase();
    if (c.contains('food')) return TimelineItemKind.meal;
    return TimelineItemKind.activity;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final s = LanguageScope.of(context);
    final lang = s.lang;
    final suggestions = _suggestions;
    final q = _controller.text.trim();

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: p.border),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: p.textMuted.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        s.s('viewer.edit.addSheetTitle'),
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      if (widget.cityLabel.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${widget.city?.emoji ?? '📍'} ${widget.cityLabel}',
                            style: TextStyle(
                              color: p.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Arama alanı.
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    onChanged: (value) => setState(() {
                      _selected = null;
                      if (_hasTicket) _applyTicketDefaults(value);
                    }),
                    style: TextStyle(color: p.textPrimary),
                    decoration: InputDecoration(
                      hintText: s.s('viewer.edit.searchPlace'),
                      hintStyle: TextStyle(color: p.textMuted),
                      prefixIcon: Icon(Icons.search, color: p.textMuted),
                      filled: true,
                      fillColor: p.elevated,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: p.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: p.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: p.accent),
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 10),
                  // Öneri listesi (yükseklik sınırlı).
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: suggestions.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              q.isEmpty
                                  ? s.s('viewer.edit.searchPlace')
                                  : s.s('viewer.edit.noResults'),
                              style:
                                  TextStyle(color: p.textMuted, fontSize: 13),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: suggestions.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: p.border.withValues(alpha: 0.5),
                            ),
                            itemBuilder: (_, i) {
                              final place = suggestions[i];
                              final sel = identical(_selected, place);
                              return ListTile(
                                dense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                leading: Text(place.emoji,
                                    style: const TextStyle(fontSize: 20)),
                                title: Text(
                                  place.name,
                                  style: TextStyle(
                                    color: p.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Text(
                                  place.category.of(lang),
                                  style: TextStyle(
                                      color: p.textSecondary, fontSize: 12),
                                ),
                                trailing: sel
                                    ? Icon(Icons.check_circle,
                                        color: p.accent, size: 20)
                                    : null,
                                onTap: () {
                                  setState(() {
                                    _selected = place;
                                    _controller.text = place.name;
                                    if (_hasTicket) {
                                      _applyTicketDefaults(place.name);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.transparent,
                    child: SwitchListTile.adaptive(
                      key: const ValueKey('add-place-has-ticket'),
                      value: _hasTicket,
                      contentPadding: EdgeInsets.zero,
                      activeTrackColor: p.accent.withValues(alpha: .45),
                      activeThumbColor: p.accent,
                      title: Text(
                        s.s('viewer.edit.hasTicket'),
                        style: TextStyle(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        s.s('viewer.edit.hasTicketHint'),
                        style: TextStyle(color: p.textSecondary, fontSize: 12),
                      ),
                      onChanged: (value) => setState(() {
                        _hasTicket = value;
                        if (value) {
                          _applyTicketDefaults(
                            _selected?.name ?? _controller.text.trim(),
                          );
                        } else {
                          _durationMin = 90;
                        }
                      }),
                    ),
                  ),
                  if (_hasTicket) ...[
                    const SizedBox(height: 8),
                    Text(
                      s.s('viewer.edit.ticketDuration'),
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      key: const ValueKey('ticket-duration-options'),
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final minutes in const [90, 120, 180, 240, 720])
                          ChoiceChip(
                            label: Text(_durationLabel(s, minutes)),
                            selected: _durationMin == minutes,
                            onSelected: (_) =>
                                setState(() => _durationMin = minutes),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      key: const ValueKey('ticket-fixed-summary'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: p.accent.withValues(alpha: .25)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_clock_outlined,
                              size: 18, color: p.accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.p('viewer.edit.ticketFixedSummary', {
                                'time': _time,
                                'buffer': '$_arrivalBufferMin',
                              }),
                              style: TextStyle(
                                color: p.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Saat + Ekle.
                  Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _pickTime,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: p.elevated,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: p.border),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.schedule, size: 18, color: p.accent),
                              const SizedBox(width: 8),
                              Text(
                                _time,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: (_selected != null || q.isNotEmpty)
                              ? _submit
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: p.accent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            _hasTicket
                                ? s.s('viewer.edit.addTicketed')
                                : q.isNotEmpty && _selected == null
                                    ? s.p('viewer.edit.customPlace', {'q': q})
                                    : s.s('viewer.edit.add'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bir durağa **gelinen** bacağı bulur.
///
/// Bacak artık kendi satırında değil, varış durağının alt başlığında gösterilir;
/// bu yüzden eşleşme `toLocationId` üzerindendir. Süresi sıfır olan (aynı nokta)
/// bacaklar kullanıcıya bilgi taşımaz, atlanır.
RouteExecutionLeg? _inboundLegFor(
  List<RouteExecutionLeg> legs,
  String itemId,
) {
  for (final leg in legs) {
    if (!leg.isTrivial && leg.toLocationId == itemId) return leg;
  }
  return null;
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
    this.inboundLeg,
    this.warnings = const [],
  });
  final TimelineItem item;
  final ViewerPalette palette;
  final TripDestination? dest;
  final bool isNext;
  final bool isPastItem;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onOpen;

  /// Bu durağa gelinen ulaşım bacağı. Alt başlıkta rozet olarak gösterilir.
  final RouteExecutionLeg? inboundLeg;

  final List<PlanWarning> warnings;

  static const Color _amber = Color(0xFFFF9F0A);

  /// "🚶 Yürüyerek · 18 dk" rozeti. Durağın kimliğini bastırmaması için
  /// başlıktan küçük ve accent tonundadır.
  Widget _transitBadge(BuildContext context, RouteExecutionLeg leg) {
    final s = LanguageScope.of(context);
    final p = palette;
    final muted = isPastItem;
    final color = muted ? p.textMuted : p.accent;
    final label = '${_routeModeLabel(s, leg.mode)} · '
        '${leg.travelDurationMinutes} ${s.s('routeOptimization.minute')}';
    return Semantics(
      key: ValueKey('timeline-transit-badge-${item.id}'),
      label: s.p('routeOptimization.legs.semantics', {
        'from': leg.fromName,
        'to': leg.toName,
        'mode': _routeModeLabel(s, leg.mode),
        'minutes': '${leg.travelDurationMinutes}',
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_routeModeIcon(leg.mode), size: 12, color: color),
            const SizedBox(width: 4),
            // Flexible şart: Row'un flex'siz çocuğu maxWidth:infinity ile
            // ölçülür, ellipsis hiç devreye girmez ve Row rozeti taşırır.
            // Container clip yapmadığı için taşan metin ("… dk") komşu
            // açıklamanın üstüne basılıyordu.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final time = item.time ?? item.scheduledTime ?? '--:--';
    final hasWarning = warnings.isNotEmpty;
    final timeStyle = TextStyle(
      color: hasWarning ? _amber : (isPastItem ? p.textMuted : p.fuji),
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
                    ? Border.all(
                        color: p.accent.withValues(alpha: 0.55), width: 1.5)
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
                          if (hasWarning) ...[
                            const SizedBox(width: 4),
                            Tooltip(
                              message: warnings
                                  .map((w) => '• ${w.message}')
                                  .join('\n'),
                              preferBelow: false,
                              child: const Icon(
                                Icons.warning_amber_rounded,
                                size: 14,
                                color: _amber,
                              ),
                            ),
                          ] else if (isPastItem) ...[
                            const SizedBox(width: 3),
                            Icon(Icons.check_rounded,
                                size: 13, color: p.textMuted),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                                  LanguageScope.of(context)
                                      .s('viewer.item.next'),
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
                        // Alt başlık: önce ulaşım rozeti, sonra açıklama.
                        //
                        // **Why Wrap:** İki `Flexible` genişliği yarı yarıya
                        // bölüyordu — rozet kendi içeriğinden dar kalıp taşıyor,
                        // açıklama da erken kırpılıyordu. Wrap ile rozet kendi
                        // boyunda durur; açıklama aynı satıra sığmıyorsa alt
                        // satıra iner, üst üste binmez.
                        if (inboundLeg != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 3,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _transitBadge(context, inboundLeg!),
                                if (item.description?.isNotEmpty == true)
                                  Text(
                                    item.description!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: p.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          )
                        else if (item.description != null &&
                            item.description!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              item.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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
// 4) Görünüm seçici: düzen + renk teması + dil.
// ---------------------------------------------------------------------------

/// ViewerThemeId → l10n anahtarı (tema adı, dile göre çözülür).
String _themeLabelKey(ViewerThemeId id) => switch (id) {
      ViewerThemeId.japanDark => 'theme.japanDark',
      ViewerThemeId.appleLight => 'theme.appleLight',
      ViewerThemeId.sakuraSoft => 'theme.sakuraSoft',
    };

String _templateLabelKey(ViewerTemplateId id) => switch (id) {
      ViewerTemplateId.journeyProgress => 'viewer.template.journeyProgress',
      ViewerTemplateId.mapFocus => 'viewer.template.mapFocus',
    };

String _templateDescriptionKey(ViewerTemplateId id) => switch (id) {
      ViewerTemplateId.journeyProgress =>
        'viewer.template.journeyProgress.description',
      ViewerTemplateId.mapFocus => 'viewer.template.mapFocus.description',
    };

class _ThemePickerSheet extends ConsumerWidget {
  const _ThemePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(viewerThemeProvider);
    final currentTemplate = ref.watch(viewerTemplateProvider);
    final palette = ViewerPalette.forId(current);
    final s = LanguageScope.of(context);
    final lang = ref.watch(appLangProvider);
    return Theme(
      data: palette.toThemeData(),
      child: Material(
        color: palette.card,
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.s('viewer.appearance.title'),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  s.s('viewer.template.title'),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                for (final id in ViewerTemplateId.values)
                  _TemplateOption(
                    id: id,
                    palette: palette,
                    selected: id == currentTemplate,
                    onTap: () =>
                        ref.read(viewerTemplateProvider.notifier).set(id),
                  ),
                const SizedBox(height: 14),
                Divider(color: palette.border),
                const SizedBox(height: 14),
                Text(
                  s.s('viewer.theme.title'),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                for (final id in ViewerThemeId.values)
                  _ThemeOption(
                    id: id,
                    selected: id == current,
                    onTap: () => ref.read(viewerThemeProvider.notifier).set(id),
                  ),
                const SizedBox(height: 16),
                // Dil / Language seçici — appLangProvider'ı ayarlar (kalıcı).
                Text(
                  s.s('lang.title'),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
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
        ),
      ),
    );
  }
}

class _TemplateOption extends StatelessWidget {
  const _TemplateOption({
    required this.id,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final ViewerTemplateId id;
  final ViewerPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final mapFocused = id == ViewerTemplateId.mapFocus;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: ValueKey('viewer-template-${id.storageKey}'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? palette.accent.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: palette.elevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.border),
                ),
                child: Icon(
                  mapFocused ? Icons.map_outlined : Icons.route_outlined,
                  color: palette.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.s(_templateLabelKey(id)),
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.s(_templateDescriptionKey(id)),
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: palette.accent, size: 20),
            ],
          ),
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
                : Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.12),
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

/// Rehber ve checklist'te kullanılan affiliate kartı.
class _AffiliateCard extends StatelessWidget {
  const _AffiliateCard(
      {required this.link, required this.palette, required this.lang});
  final AffiliateLink link;
  final ViewerPalette palette;
  final AppLang lang;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(link.url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(LanguageScope.of(context).s('map.openFailed'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Material(
      color: p.bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.border)),
          child: Row(children: [
            Text(link.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(link.label.of(lang),
                      style: TextStyle(
                          color: p.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 1),
                  Text(link.description.of(lang),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.textSecondary, fontSize: 11, height: 1.3)),
                ])),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999)),
              child: Text(link.cta.of(lang),
                  style: TextStyle(
                      color: p.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}
