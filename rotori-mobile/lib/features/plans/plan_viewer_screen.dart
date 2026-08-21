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
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';

import '../../core/debug_clock.dart';
import '../../core/debug_tools.dart';
import '../../core/l10n.dart';
import '../../core/rotori_motion.dart';
import '../../core/supabase_client.dart';
import '../../data/language_store.dart';
import '../../data/device_steps.dart';
import '../../data/plans_repository.dart';
import '../../data/reminders_store.dart';
import '../../data/offline_japan_route_matrix.dart';
import '../../data/weather_service.dart';
import '../../domain/city_palette.dart';
import '../../domain/city_hero_assets.dart';
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
import '../../domain/place_image_resolver.dart';
import '../../domain/plan_generation.dart' show tripHasFlightInfo;
import '../../domain/plan_schedule_engine.dart';
import '../../domain/ticketed_activity.dart';
import '../../domain/trip_factory.dart' show newTicketId;
import '../../domain/plan_warnings.dart';
import '../../domain/route_execution.dart';
import '../../domain/route_time_bounds.dart';
import '../../domain/route_matrix.dart';
import '../../data/tts_service.dart';
import '../../domain/travel_tips_data.dart';
import '../../domain/must_see_suggestions.dart';
import '../../domain/trip_forecast.dart';
import '../../domain/types.dart';
import '../../domain/weather_route_order.dart';
import '../auth/auth_repository.dart';
import '../shared/place_detail_sheet.dart';
import '../shared/rotori_premium_sheet.dart';
import '../shared/ticket_support.dart';
import '../tickets/application/ticket_import_coordinator.dart';
import '../tickets/data/ticket_local_media_store.dart';
import '../tickets/domain/ticket_import_models.dart';
import '../tickets/presentation/ticket_add_sheet.dart';
import '../tickets/presentation/ticket_detail_sheet.dart';
import '../tickets/presentation/ticket_import_review_sheet.dart';
import '../tickets/presentation/ticket_wallet_view.dart';
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

typedef TicketImagePicker = Future<XFile?> Function(ImageSource source);
typedef TicketEditCommandExecutor = Future<PlanEditResult> Function(
  PlanEditSession session,
  PlanEditCommand command,
);

final ticketImagePickerProvider = Provider<TicketImagePicker>(
  (_) => (source) => ImagePicker().pickImage(source: source),
);

final ticketEditCommandExecutorProvider = Provider<TicketEditCommandExecutor>(
  (_) => (session, command) => session.execute(command),
);

final ticketImportCoordinatorProvider = Provider<TicketImportCoordinator>(
  (ref) => TicketImportCoordinator(
    mediaStore: ref.watch(ticketLocalMediaStoreProvider),
  ),
);

@visibleForTesting
Ticket? findExistingTicketForItem(
  Iterable<Ticket> tickets,
  TimelineItem item,
) {
  Ticket? legacyTitleMatch;
  for (final ticket in tickets) {
    if (ticket.linkedActivityId == item.id) return ticket;
    if (ticket.linkedActivityId == null && ticket.label == item.title) {
      legacyTitleMatch ??= ticket;
    }
  }
  return legacyTitleMatch;
}

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
int _activeDayIndex(List<DayPlan> daysSorted, DateTime now) {
  if (daysSorted.isEmpty) return 0;
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

  /// En son otomatik açılan aktif gün index'i. Aktif gün değişince (gün
  /// dönümü veya debug saati) yeni aktif gün kendiliğinden açılır, ama
  /// kullanıcı sonradan elle kapatabilsin diye yalnız değişimde tetiklenir.
  int? _autoExpandedActiveIndex;

  /// Gezi tamamlandığında gezi raporu altında günlere göz atma isteği.
  /// Varsayılan kapalı: rapor gösterildiğinde gün kartları kapanır
  /// ("aşağıdaki gezileri kapat"); kullanıcı isterse geri açabilir.
  bool _tripReportExpanded = false;

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

  /// Aktif tab — 0: Ana Sayfa, 1: Biletler, 2: Japonca, 3: Rehber,
  /// 4: Keşfet.
  int _activeTab = 0;

  /// Harita ağır bir yüzey olduğu için ilk Keşfet dokunuşuna kadar kurulmaz.
  /// Kurulduktan sonra IndexedStack içinde tutulur; böylece sekmeler arasında
  /// geçerken hem harita durumu hem de sabit alt navigasyon korunur.
  bool _exploreInitialized = false;

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
    final initialActiveDay =
        _activeDayIndex(initialDays, ref.read(nowProvider));
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
    // Görüntüleme modunda geçmiş günler gizli → aktif gün zaten en üstte.
    // Kaydırmak yalnızca üstteki hero'yu (ilerleme halkası + sıradaki aktivite)
    // ekrandan iterdi; o yüzden yalnız düzenleme modunda (tüm günler görünürken)
    // aktif güne kaydır.
    if (!_editMode) {
      _autoScrolled = true;
      return;
    }
    // Aktif gün zaten ilk gün ise kaydırma YAPMA: listenin başı zaten görünür
    // ve kaydırmak, gün akışının üstündeki kartları ("✈️ Uçuşunu ekle" gibi)
    // kullanıcı hiç görmeden ekranın dışına iter.
    if (_activeDayIndex(_sortedDays, ref.read(nowProvider)) <= 0) {
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
    // Debug/önizlemede kaydırılabilen "şimdi". Ofset değişince bu build tekrar
    // koşar → aktif gün, sıradaki aktivite ve ilerleme sayacı güncellenir.
    final now = ref.watch(nowProvider);
    final trip = _trip;
    final days = _sortedDays;
    final activeIndex = _activeDayIndex(days, now);
    final activeDay = days.isEmpty ? null : days[activeIndex];
    // Aktif gün değiştiğinde (gün dönümü / debug saati) yeni aktif günü otomatik
    // aç — geçmiş günler gizlendiği için en üstteki gün açık gelmeli. Yalnız
    // görüntüleme modunda ve değişim anında; sonra kullanıcı elle kapatabilir.
    if (!_editMode &&
        days.isNotEmpty &&
        _autoExpandedActiveIndex != activeIndex) {
      _autoExpandedActiveIndex = activeIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _expandedInView.add(activeIndex));
      });
    }
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

    // Gezinin TAMAMI bitti mi (son günün de son aktivitesi geçmiş mi)? Bu
    // durumda gün kartları kapanır, yerine tüm geziyi özetleyen rapor gelir.
    final tripFinished = !_editMode && _isTripFinished(days, activeIndex, now);
    final tripStats = tripFinished ? _buildTripReportStats(trip, days) : null;

    // Ana sayfa (Tab 0) gövdesi. Harita tasarımında sayfa scroll ETMEZ:
    // harita ve "sıradaki aktivite" kartı sabit durur, yalnızca seçili günün
    // rota listesi kendi alanında kayar. Diğer tasarımlar tek akışlı liste.
    final mapNextItem = selectedMapDay == null || _editMode
        ? null
        : _nextActivityForDay(selectedMapDay, now);
    // Geçmiş günleri gizle: görüntüleme modunda aktif günden öncekiler listeden
    // düşer → aktif gün en üste sabitlenir. Düzenleme modunda tüm günler kalır
    // (geçmiş gün de düzenlenebilsin). Harita zaten tek seçili günü gösterir.
    // Gezi tamamlandıysa ("aşağıdaki gezileri kapat"): kullanıcı raporun
    // altındaki anahtarla açana kadar hiçbir gün kartı gösterilmez.
    bool dayVisible(int i) {
      if (template == ViewerTemplateId.mapFocus) return i == selectedMapIndex;
      if (_editMode) return true;
      if (tripFinished) return _tripReportExpanded;
      return i >= activeIndex;
    }

    final dayFlow = <Widget>[
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
          if (dayVisible(i))
            _DayCard(
              key: isMapPresentation
                  ? ValueKey(
                      'viewer-map-route-day-${days[i].dayNumber}',
                    )
                  : i == activeIndex
                      ? _activeDayKey
                      : null,
              day: days[i],
              now: now,
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
              canOptimizeForWeather: _shouldOfferWeatherOptimization(
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
              onOptimizeWeatherRoute: (day, destination, forecast) =>
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
              i < days.length - 1 &&
              dayVisible(i) &&
              dayVisible(i + 1))
            _cityTransitionBetween(days[i], days[i + 1], palette),
        ],
    ];
    final activeDestination = activeDay == null
        ? null
        : getDestinationForDate(_sortedDestinations, activeDay.date);
    final Widget homeTab = isMapPresentation
        ? Column(
            children: [
              if (selectedMapDay != null)
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
              if (mapNextItem != null && selectedMapDay != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: _NextActivityCard(
                    key: const ValueKey('viewer-map-next-activity'),
                    item: mapNextItem,
                    day: selectedMapDay,
                    palette: palette,
                    elevated: true,
                    onOpen: () => _openItem(
                      mapNextItem,
                      getDestinationForDate(
                        _sortedDestinations,
                        selectedMapDay.date,
                      ),
                    ),
                  ),
                ),
              // Harita, gezi bitmiş olsa bile geçmiş günleri gezmek için
              // kullanılabilir kalmalı (tarih şeridi hâlâ orada) — o yüzden
              // günleri kapatmıyoruz, yalnız gerçekten aktif/son günü
              // görüntülerken küçük bir CTA ile tam rapora yönlendiriyoruz.
              if (mapNextItem == null &&
                  tripFinished &&
                  selectedMapIndex == activeIndex &&
                  selectedMapDay != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: _TripCompletionCta(
                    key: const ValueKey('viewer-map-trip-complete-cta'),
                    palette: palette,
                    onTap: () =>
                        _showTripCompletionSheet(trip, tripStats!, palette),
                  ),
                ),
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  children: dayFlow,
                ),
              ),
            ],
          )
        : template == ViewerTemplateId.journeyProgress &&
                !_editMode &&
                activeDay != null
            ? Stack(
                children: [
                  ColoredBox(color: palette.bg),
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: _JourneyHeroImage(
                      day: activeDay,
                      dayNumber: activeIndex + 1,
                      dayCount: days.length,
                      palette: palette,
                    ),
                  ),
                  ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 180, 16, 40),
                    children: [
                      // Gezi bittiyse ("aşağıdaki gezileri kapat"): sıradaki
                      // aktivite/gün-tamamlandı bandı yerine tüm geziyi
                      // özetleyen rapor gelir, gün kartları kapanır.
                      if (tripFinished)
                        _TripCompletionReport(
                          trip: trip,
                          stats: tripStats!,
                          palette: palette,
                          expanded: _tripReportExpanded,
                          onToggleExpanded: () => setState(
                            () => _tripReportExpanded = !_tripReportExpanded,
                          ),
                        )
                      else
                        _JourneyHeroSheet(
                          day: activeDay,
                          now: now,
                          palette: palette,
                          onOpenItem: (item) => _openItem(
                            item,
                            activeDestination,
                          ),
                        ),
                      ...dayFlow,
                    ],
                  ),
                ],
              )
            : ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  // Rota Panoraması: yolculuk düzeninin başlık varyantı — altındaki
                  // gün akışı birebir aynı kalır. Gezi bittiyse ikisinin de
                  // yerini tüm geziyi özetleyen rapor alır (gün kartları kapanır).
                  if (activeDay != null &&
                      !_editMode &&
                      template == ViewerTemplateId.routePanorama &&
                      tripFinished)
                    _TripCompletionReport(
                      trip: trip,
                      stats: tripStats!,
                      palette: palette,
                      expanded: _tripReportExpanded,
                      onToggleExpanded: () => setState(
                        () => _tripReportExpanded = !_tripReportExpanded,
                      ),
                    ),
                  if (activeDay != null &&
                      !_editMode &&
                      template == ViewerTemplateId.routePanorama &&
                      !tripFinished)
                    _RoutePanoramaHero(
                      day: activeDay,
                      now: now,
                      stops: _mapStopsFor(activeDay),
                      legs: _displayRouteLegs(
                        activeDay,
                        getDestinationForDate(
                            _sortedDestinations, activeDay.date),
                      ),
                      cityLabel: getDestinationForDate(
                            _sortedDestinations,
                            activeDay.date,
                          )?.city ??
                          '',
                      palette: palette,
                    ),
                  // Panorama, yolculuk temasının header'ını değiştiren bir
                  // varyant — altındaki "sıradaki aktivite / gün tamamlandı"
                  // bandı (_JourneyHeroSheet) da aynen onunla birlikte gelir.
                  // Bu olmadan, günün/gezinin son aktivitesi geçtiğinde
                  // kullanıcıya hiçbir şey söylenmiyordu.
                  if (activeDay != null &&
                      !_editMode &&
                      template == ViewerTemplateId.routePanorama &&
                      !tripFinished)
                    _JourneyHeroSheet(
                      day: activeDay,
                      now: now,
                      palette: palette,
                      onOpenItem: (item) => _openItem(item, activeDestination),
                    ),
                  ...dayFlow,
                ],
              );

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
              key: const ValueKey('viewer-top-status-bar'),
              trip: trip,
              palette: palette,
              planId: widget.planId,
              editMode: _editMode,
              onToggleEdit: _toggleEditMode,
              onRebuild: _confirmRebuild,
            ),
            if (ref.watch(debugClockBarEnabledProvider))
              _DebugClockBar(palette: palette),
            Expanded(
              child: IndexedStack(
                index: _activeTab,
                children: [
                  // Tab 0 — Ana Sayfa: gün akışı.
                  homeTab,
                  // Tab 1 — Biletler.
                  TicketWalletView(
                    tickets: trip.tickets,
                    palette: palette,
                    now: ref.watch(nowProvider),
                    onAdd: _openTicketAddFlow,
                    onOpen: _openTicketDetails,
                    onOpenMedia: _openTicketMedia,
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
                  // Tab 4 — Keşfet. Parent Scaffold'ın içinde kaldığı için
                  // alt navigasyon route animasyonuna katılmaz.
                  _exploreInitialized
                      ? RewardMapScreen(trip: trip)
                      : const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _ViewerQuickNav(
        palette: palette,
        activeTab: _activeTab,
        ticketCount: _trip.tickets.length,
        onTabChanged: (tab) => setState(() => _activeTab = tab),
        onOpenExplore: _openExplore,
      ),
    );
  }

  /// Bir gün öğesi için yer detay popup'ını açar — bilet arama + ekleme
  /// callback'lerini stateful gövdeden geçirir (persistence burada kalır).
  void _openItem(TimelineItem item, TripDestination? dest) {
    final existing = findExistingTicketForItem(_trip.tickets, item);
    showPlaceDetailSheet(
      context: context,
      item: item,
      city: dest?.city ?? '',
      countryCode: dest?.countryCode,
      existingTicket: existing,
      onAddTicket: _openTicketAddForItem,
    );
  }

  DayPlan? _dayContaining(String activityId) {
    for (final day in _trip.days) {
      if (day.items.any((item) => item.id == activityId)) return day;
    }
    return null;
  }

  TimelineItem? _itemById(String? activityId) {
    if (activityId == null) return null;
    for (final day in _trip.days) {
      for (final item in day.items) {
        if (item.id == activityId) return item;
      }
    }
    return null;
  }

  Future<void> _openTicketAddForItem(TimelineItem item) async {
    if (!mounted) return;
    setState(() => _activeTab = 1);
    await _openTicketAddFlow(linkedItem: item);
  }

  Future<void> _openTicketAddFlow({TimelineItem? linkedItem}) async {
    final source = await showTicketAddSheet(
      context: context,
      palette: ViewerPalette.of(context),
      showPlanOption: linkedItem == null,
    );
    if (source == null || !mounted) return;
    switch (source) {
      case TicketAddSource.gallery:
        await _openTicketImageImport(
          ImageSource.gallery,
          seed: linkedItem == null ? null : _ticketSeedForItem(linkedItem),
          linkedItem: linkedItem,
        );
        return;
      case TicketAddSource.camera:
        await _openTicketImageImport(
          ImageSource.camera,
          seed: linkedItem == null ? null : _ticketSeedForItem(linkedItem),
          linkedItem: linkedItem,
        );
        return;
      case TicketAddSource.manual:
        await _reviewTicket(
          seed: linkedItem == null
              ? Ticket(
                  id: newTicketId(),
                  kind: TicketKind.other.name,
                  label: '',
                  purchased: false,
                )
              : _ticketSeedForItem(linkedItem),
          linkedItem: linkedItem,
        );
        return;
      case TicketAddSource.plan:
        final selection = await _selectPlanTicketSeed();
        if (selection != null && mounted) {
          await _reviewTicket(
            seed: selection.ticket,
            linkedItem: selection.item,
            transitionDayNumber: selection.transitionDayNumber,
          );
        }
        return;
    }
  }

  Ticket _ticketSeedForItem(TimelineItem item) {
    final defaults = ticketedActivityDefaultsForTitle(item.title);
    return Ticket(
      id: newTicketId(),
      kind: TicketKind.attraction.name,
      label: item.title,
      purchased: false,
      visitDate: _dayContaining(item.id)?.date,
      entryTime: item.time ?? item.scheduledTime,
      linkedActivityId: item.id,
      durationMin: item.durationMin ?? defaults.durationMinutes,
      arrivalBufferMin: item.arrivalBufferMin ?? defaults.arrivalBufferMinutes,
      emoji: '🎫',
    );
  }

  Future<bool> _reviewTicket({
    required Ticket seed,
    TicketExtractionResult extraction = const TicketExtractionResult(),
    TicketImportSession? importSession,
    TimelineItem? linkedItem,
    int? transitionDayNumber,
    String? replacedMediaRef,
  }) async {
    final review = await showTicketImportReviewSheet(
      context: context,
      extraction: extraction,
      initialTicket: seed,
      palette: ViewerPalette.of(context),
    );
    if (review == null) {
      await importSession?.cancel();
      return false;
    }

    Future<bool> persist(Ticket ticket) async {
      final command = linkedItem == null
          ? UpsertTicket(
              ticket: ticket,
              transitionDayNumber: transitionDayNumber,
            )
          : AttachTicketToActivity(
              activityId: linkedItem.id,
              ticket: ticket,
            );
      final result = await ref.read(ticketEditCommandExecutorProvider)(
        _editSession,
        command,
      );
      return result.isSuccess;
    }

    final saved = importSession == null
        ? await persist(review.ticket)
        : await importSession.save(
            ticket: review.ticket,
            persist: persist,
            replacedMediaRef: replacedMediaRef,
          );
    if (!saved && mounted) _showTicketSaveFailure();
    return saved;
  }

  Future<bool> _openTicketImageImport(
    ImageSource source, {
    Ticket? seed,
    TimelineItem? linkedItem,
    int? transitionDayNumber,
    String? replacedMediaRef,
  }) async {
    TicketImportSession? session;
    try {
      final picked = await ref.read(ticketImagePickerProvider)(source);
      if (picked == null) return false;
      final initialTicket = seed ??
          Ticket(
            id: newTicketId(),
            kind: TicketKind.other.name,
            label: '',
            purchased: false,
          );
      session = await ref.read(ticketImportCoordinatorProvider).begin(
            planId: _trip.id,
            ticketId: initialTicket.id,
            picked: picked,
          );
      if (session == null) return false;
      if (!mounted) {
        await session.cancel();
        return false;
      }
      return _reviewTicket(
        seed: initialTicket,
        extraction: session.extraction,
        importSession: session,
        linkedItem: linkedItem,
        transitionDayNumber: transitionDayNumber,
        replacedMediaRef: replacedMediaRef,
      );
    } on Object {
      await session?.cancel();
      if (mounted) _showTicketSaveFailure();
      return false;
    }
  }

  Future<void> _openTicketDetails(Ticket ticket) async {
    final mediaRef = ticket.localMediaRef;
    final mediaBytes = mediaRef == null
        ? null
        : await ref.read(ticketLocalMediaStoreProvider).read(mediaRef);
    if (!mounted) return;
    final result = await showTicketDetailSheet(
      context: context,
      ticket: ticket,
      mediaBytes: mediaBytes,
      palette: ViewerPalette.of(context),
    );
    if (result == null || !mounted) return;
    switch (result.action) {
      case TicketDetailAction.save:
        final updated = result.ticket;
        if (updated == null) return;
        final linkedItem = _itemById(updated.linkedActivityId);
        final saved = await ref.read(ticketEditCommandExecutorProvider)(
          _editSession,
          linkedItem == null
              ? UpsertTicket(
                  ticket: updated,
                  transitionDayNumber: updated.linkedTransitionDayNumber,
                )
              : AttachTicketToActivity(
                  activityId: linkedItem.id,
                  ticket: updated,
                ),
        );
        if (!saved.isSuccess && mounted) _showTicketSaveFailure();
        return;
      case TicketDetailAction.replaceMedia:
        final source = await _selectTicketImageSource();
        if (source != null && mounted) {
          await _openTicketImageImport(
            source,
            seed: ticket,
            linkedItem: _itemById(ticket.linkedActivityId),
            transitionDayNumber: ticket.linkedTransitionDayNumber,
            replacedMediaRef: ticket.localMediaRef,
          );
        }
        return;
      case TicketDetailAction.delete:
        await _deleteTicket(ticket);
        return;
    }
  }

  Future<void> _openTicketMedia(Ticket ticket) async {
    final mediaRef = ticket.localMediaRef;
    final bytes = mediaRef == null
        ? null
        : await ref.read(ticketLocalMediaStoreProvider).read(mediaRef);
    if (!mounted) return;
    if (bytes == null) {
      await _openTicketDetails(ticket);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _deleteTicket(Ticket ticket) async {
    final result = await ref.read(ticketEditCommandExecutorProvider)(
      _editSession,
      DeleteTicket(ticketId: ticket.id),
    );
    if (!result.isSuccess) {
      if (mounted) _showTicketSaveFailure();
      return false;
    }
    final mediaRef = ticket.localMediaRef;
    if (mediaRef != null) {
      try {
        await ref.read(ticketLocalMediaStoreProvider).delete(mediaRef);
      } on Object {
        // Plan kaydı başarıyla silindi; sahipsiz medya sonraki cleanup'ta
        // temizlenebilir. Persistence başarısızken bu satıra hiç gelinmez.
      }
    }
    return true;
  }

  Future<ImageSource?> _selectTicketImageSource() {
    final s = LanguageScope.of(context);
    return showModalBottomSheet<ImageSource>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(s.s('ticketAdd.gallery')),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: Text(s.s('ticketAdd.camera')),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  Future<_TicketPlanSelection?> _selectPlanTicketSeed() async {
    final choices = <_TicketPlanSelection>[];
    final linkedActivityIds = _trip.tickets
        .map((ticket) => ticket.linkedActivityId)
        .whereType<String>()
        .toSet();
    for (final day in _sortedDays) {
      for (final item in day.items) {
        if (!requiresTicket(item) || linkedActivityIds.contains(item.id)) {
          continue;
        }
        choices.add(_TicketPlanSelection(
          ticket: _ticketSeedForItem(item),
          item: item,
        ));
      }
      final transition = day.cityTransition;
      if (transition != null && transition.linkedTicketId == null) {
        choices.add(_TicketPlanSelection(
          ticket: Ticket(
            id: newTicketId(),
            kind: _ticketKindForTransitionMode(transition.mode),
            label: '${transition.fromCity} → ${transition.toCity}',
            purchased: false,
            visitDate: day.date,
            emoji: _cityTransitionEmoji(transition.mode),
            linkedTransitionDayNumber: day.dayNumber,
          ),
          transitionDayNumber: day.dayNumber,
        ));
      }
    }
    final s = LanguageScope.of(context);
    return showModalBottomSheet<_TicketPlanSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  s.s('ticketAdd.plan'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Flexible(
                child: choices.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                        child: Text(s.s('ticketAdd.planBody')),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final choice in choices)
                            ListTile(
                              key: ValueKey(
                                'ticket-plan-choice-${choice.ticket.id}',
                              ),
                              leading: Text(choice.ticket.emoji ?? '🎫'),
                              title: Text(choice.ticket.label),
                              subtitle: choice.ticket.visitDate == null
                                  ? null
                                  : Text(choice.ticket.visitDate!),
                              onTap: () => Navigator.pop(sheetContext, choice),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _reviewTransitionTicket({
    Ticket? existing,
    required DayPlan transitionDay,
    required String fromCity,
    required String toCity,
    required String mode,
  }) {
    final seed = existing ??
        Ticket(
          id: newTicketId(),
          kind: _ticketKindForTransitionMode(mode),
          label: '$fromCity → $toCity',
          purchased: false,
          visitDate: transitionDay.date,
          emoji: _cityTransitionEmoji(mode),
          linkedTransitionDayNumber: transitionDay.dayNumber,
        );
    return _reviewTicket(
      seed: seed,
      transitionDayNumber: transitionDay.dayNumber,
    );
  }

  void _showTicketSaveFailure() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          LanguageScope.of(context).s('viewer.ticketEditor.saveFailed'),
        ),
      ),
    );
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
    final activeDay = _activeDayIndex(_sortedDays, ref.read(nowProvider));
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
      useSafeArea: true,
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
      useSafeArea: true,
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
        useSafeArea: true,
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
        final activeIndex = _activeDayIndex(_sortedDays, ref.read(nowProvider));
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
      experienceGuideSlideRoute(
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
    setState(() {
      _exploreInitialized = true;
      _activeTab = 4;
    });
  }

  /// "Haritada gör" — günün rotasını sade (CartoDB) bir zemin üzerinde,
  /// duraklar arasında sırayla çizilen animasyonlu bir çizgiyle gösteren modal
  /// sayfayı açar. Turn-by-turn navigasyon isteyen kullanıcı için sheet'in
  /// içindeki "Yol tarifi" butonu rotayı Google Maps'e taşır — böylece hem
  /// okunur bir rota önizlemesi hem de gerçek navigasyon tek yerde.
  Future<void> _openDayMap(DayPlan day) {
    return showRouteMapSheet(context: context, trip: _trip, day: day);
  }

  /// Günün koordinatlı durakları — harita başlığı ve metrik bandı aynı listeyi
  /// kullanır ki gösterilen mesafe haritadaki rotayla birebir örtüşsün.
  List<ResolvedStop> _mapStopsFor(DayPlan day) {
    final destination = getDestinationForDate(_sortedDestinations, day.date);
    final city = cityDataForKey(destination?.city);
    final fallbackLat = destination?.lat ??
        (city?.places.isNotEmpty == true ? city!.places.first.lat : 36.2048);
    final fallbackLng = destination?.lng ??
        (city?.places.isNotEmpty == true ? city!.places.first.lng : 138.2529);
    return resolveDayStops(
      day,
      cityKey: destination?.city,
      fallbackLat: fallbackLat,
      fallbackLng: fallbackLng,
    );
  }

  /// Tüm gezinin özeti — [_TripCompletionReport] bunu gösterir.
  ///
  /// Cihaz adım sayacı geçmiş günler için sorgulanmıyor (HealthKit/Health
  /// Connect'in geçmişe dönük sorgusu ayrı bir iş; bkz.
  /// `lib/data/device_steps.dart`), o yüzden toplam adım her günün plan
  /// tahmininden ya da mesafeden türetilir — tek günlük karttaki mantığın
  /// aynısı, sadece cihaz katmanı olmadan.
  _TripReportStats _buildTripReportStats(Trip trip, List<DayPlan> days) {
    var places = 0;
    var meals = 0;
    var reservations = 0;
    var totalSteps = 0;
    var totalDistanceKm = 0.0;
    var totalMinutes = 0;
    final cities = <String>[];
    for (final day in days) {
      for (final item in day.items) {
        if (item.kind == TimelineItemKind.activity) places++;
        if (item.kind == TimelineItemKind.meal) meals++;
        if (item.lockType != ActivityLockType.none) reservations++;
      }
      final stops = _mapStopsFor(day);
      final distanceKm = _dayWalkingDistanceKm(stops);
      totalDistanceKm += distanceKm;
      totalSteps += day.stepsEstimate ?? (distanceKm * kStepsPerKm).round();
      totalMinutes += _dayPlannedMinutes(day);
      final dest = getDestinationForDate(_sortedDestinations, day.date);
      final cityLabel = cityDataForKey(dest?.city)?.label ?? dest?.city ?? '';
      if (cityLabel.isNotEmpty && !cities.contains(cityLabel)) {
        cities.add(cityLabel);
      }
    }
    return _TripReportStats(
      dayCount: days.length,
      placesVisited: places,
      mealsCount: meals,
      totalDistanceKm: totalDistanceKm,
      totalSteps: totalSteps,
      totalKcal: kcalForSteps(totalSteps),
      totalMinutes: totalMinutes,
      reservationsCount: reservations,
      cities: cities,
    );
  }

  /// Harita tasarımında gezi bittiğinde tam raporu sheet olarak açar — harita
  /// zaten tarih şeridiyle geziliyor, o yüzden orada günleri kapatıp inline
  /// rapor göstermek yerine isteğe bağlı bir CTA yeterli.
  Future<void> _showTripCompletionSheet(
    Trip trip,
    _TripReportStats stats,
    ViewerPalette palette,
  ) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: palette.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              _TripCompletionReport(
                trip: trip,
                stats: stats,
                palette: palette,
              ),
            ],
          ),
        ),
      ),
    );
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
    final weatherPreferredOrder = weatherAdjustment == null
        ? const <String>[]
        : weatherPreferredActivityOrder(preparedDay.items);
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
      preferredActivityOrder: weatherPreferredOrder,
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
      useSafeArea: true,
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
      useSafeArea: true,
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
                      final saved = await _reviewTransitionTicket(
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

/// Debug/önizleme saat kontrolü — gün/saat ileri-geri alınır, böylece
/// "sıradaki aktivite" ve "ilerlemen" sayacı gerçek zamanı beklemeden denenir.
/// Yalnız [debugClockBarEnabledProvider] `true` iken (önizleme girişi) çizilir;
/// üretim ve widget testlerinde varsayılan `false` olduğu için hiç görünmez.
class _DebugClockBar extends ConsumerWidget {
  const _DebugClockBar({required this.palette});

  final ViewerPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offset = ref.watch(debugClockOffsetProvider);
    final now = ref.watch(nowProvider);
    final s = LanguageScope.of(context);
    final lang = s.lang;
    final months = L10n.monthsFor(lang);
    final weekdays = L10n.weekdaysFor(lang);
    final stamp = '${weekdays[now.weekday]} ${now.day} ${months[now.month]} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    final offsetLabel = offset == Duration.zero
        ? (lang == AppLang.tr ? 'gerçek' : 'live')
        : _formatClockOffset(offset);

    void shift(Duration delta) {
      ref.read(debugClockOffsetProvider.notifier).state = offset + delta;
    }

    return Container(
      key: const ValueKey('viewer-debug-clock-bar'),
      color: const Color(0xFF1B1B2B),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          const Text('🐞', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  stamp,
                  key: const ValueKey('viewer-debug-clock-stamp'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  lang == AppLang.tr
                      ? 'sim saat · $offsetLabel'
                      : 'sim · $offsetLabel',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _DebugClockButton(
            label: '−1g',
            keyValue: 'viewer-debug-clock-day-back',
            onTap: () => shift(const Duration(days: -1)),
          ),
          _DebugClockButton(
            label: '−1s',
            keyValue: 'viewer-debug-clock-hour-back',
            onTap: () => shift(const Duration(hours: -1)),
          ),
          _DebugClockButton(
            label: '+1s',
            keyValue: 'viewer-debug-clock-hour-fwd',
            onTap: () => shift(const Duration(hours: 1)),
          ),
          _DebugClockButton(
            label: '+1g',
            keyValue: 'viewer-debug-clock-day-fwd',
            onTap: () => shift(const Duration(days: 1)),
          ),
          if (offset != Duration.zero)
            _DebugClockButton(
              label: '⟲',
              keyValue: 'viewer-debug-clock-reset',
              onTap: () => ref.read(debugClockOffsetProvider.notifier).state =
                  Duration.zero,
            ),
        ],
      ),
    );
  }
}

/// [_DebugClockBar] içindeki tek tık hedefi. Kompakt, koyu bar için özel.
class _DebugClockButton extends StatelessWidget {
  const _DebugClockButton({
    required this.label,
    required this.keyValue,
    required this.onTap,
  });

  final String label;
  final String keyValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: ValueKey(keyValue),
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Debug saat ofsetini "+2g 3s" gibi kısa okunur metne çevirir.
String _formatClockOffset(Duration offset) {
  final negative = offset.isNegative;
  final abs = offset.abs();
  final days = abs.inDays;
  final hours = abs.inHours % 24;
  final minutes = abs.inMinutes % 60;
  final parts = <String>[];
  if (days > 0) parts.add('${days}g');
  if (hours > 0) parts.add('${hours}s');
  if (minutes > 0) parts.add('${minutes}d');
  if (parts.isEmpty) parts.add('0d');
  return '${negative ? '−' : '+'}${parts.join(' ')}';
}

class _TopStatusBar extends StatefulWidget {
  const _TopStatusBar({
    super.key,
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

class _TopStatusBarState extends State<_TopStatusBar> {
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
            // Aksiyon şeridi ve bilet çipleri kaldırıldı — bilet sayısı artık
            // alt navigasyondaki "Biletler" sekmesinde sakin bir rozet olarak
            // gösteriliyor (bkz. _ViewerQuickNav).
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

/// Viewer'ın sabit alt navigasyonu — tek ikon sistemi ve erişilebilir label'lar.
class _ViewerQuickNav extends StatelessWidget {
  const _ViewerQuickNav({
    required this.palette,
    required this.activeTab,
    required this.onTabChanged,
    required this.onOpenExplore,
    this.ticketCount = 0,
  });

  final ViewerPalette palette;
  final int activeTab;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onOpenExplore;

  /// "Biletler" sekmesinin ikonunda gösterilecek sakin sayı rozeti.
  final int ticketCount;

  @override
  Widget build(BuildContext context) {
    final activeColor = palette.accent;
    final inactiveColor = palette.textSecondary;
    final s = LanguageScope.of(context);

    final tabs = <({IconData icon, String label})>[
      (icon: Icons.home_outlined, label: s.s('viewer.quick.home')),
      (
        icon: Icons.confirmation_num_outlined,
        label: s.s('viewer.quick.tickets')
      ),
      (icon: Icons.translate_outlined, label: s.s('viewer.quick.japanese')),
      (icon: Icons.menu_book_outlined, label: s.s('viewer.quick.guide')),
      (icon: Icons.map_outlined, label: s.s('viewer.quick.explore')),
    ];

    return Material(
      key: const ValueKey('viewer-quick-nav'),
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
                  child: Semantics(
                    button: true,
                    selected: i == activeTab,
                    label: tabs[i].label,
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
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                tabs[i].icon,
                                size: activeTab == i ? 22 : 20,
                                color: activeTab == i
                                    ? activeColor
                                    : inactiveColor,
                              ),
                              if (i == 1 && ticketCount > 0)
                                Positioned(
                                  right: -6,
                                  top: -4,
                                  child: _TicketCountBadge(
                                    count: ticketCount,
                                    palette: palette,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tabs[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color:
                                  activeTab == i ? activeColor : inactiveColor,
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
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Biletler" sekmesindeki sayı rozeti — bilinçli olarak nötr/sakin: uyarı
/// rengi (kırmızı) kullanmaz, sadece adet bilgisini taşır.
class _TicketCountBadge extends StatelessWidget {
  const _TicketCountBadge({required this.count, required this.palette});

  final int count;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final label = count > 9 ? '9+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: palette.textSecondary.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.card, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: palette.card,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab içerik widget'ları — persistent tab bar ile kullanım için
// Scaffold/AppBar'sız, sadece içerik.
// ---------------------------------------------------------------------------

class _TicketPlanSelection {
  const _TicketPlanSelection({
    required this.ticket,
    this.item,
    this.transitionDayNumber,
  });

  final Ticket ticket;
  final TimelineItem? item;
  final int? transitionDayNumber;
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
/// Büyük başlık, hızlı erişim kartları, tek grup konu listesi ve sekme içi
/// detay görünümü — hepsi aynı tab içinde kalır.
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
  int? _selectedSectionIndex;

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
    if (q.isEmpty) {
      return List<int>.generate(kMustKnowSections.length, (i) => i);
    }
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

  void _openSection(int index) {
    setState(() => _selectedSectionIndex = index);
  }

  void _closeSection() {
    setState(() => _selectedSectionIndex = null);
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
    final nextSectionIndex = q.isEmpty
        ? null
        : matches.length == 1
            ? matches.single
            : null;
    setState(() {
      _query = value;
      _selectedSectionIndex = nextSectionIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final lang = widget.lang;
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

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return ClipRect(
      child: AnimatedSwitcher(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final isList = child.key == const ValueKey('guide-list');
          return SlideTransition(
            position: Tween<Offset>(
              begin: isList ? const Offset(-1, 0) : const Offset(1, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
        child: detailIndex == null
            ? _GuideListView(
                key: const ValueKey('guide-list'),
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
                key: ValueKey('guide-detail-$detailIndex'),
                palette: p,
                lang: lang,
                section: kMustKnowSections[detailIndex],
                tips: _tipsOf(kMustKnowSections[detailIndex], query: _query),
                onBackToAllTopics: _closeSection,
              ),
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
    final visibleQuickAccessIndices = searching
        ? quickAccessIndices
            .where(
              (index) => visibleSections.any((entry) => entry.index == index),
            )
            .toList(growable: false)
        : quickAccessIndices;

    return ListView(
      key: const ValueKey('viewer-guide-scroll'),
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
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded, color: p.textMuted),
                ],
              ),
            ),
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
        ],
      ),
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
            preferredActivityOrder: widget.input.preferredActivityOrder,
          ),
        );
  }

  @override
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
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: RouteOptimizationProfile.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final profile = RouteOptimizationProfile.values[index];
                    return ChoiceChip(
                      label: Text(_profileLabel(s, profile)),
                      selected: _profile == profile,
                      onSelected: state.isLoading
                          ? null
                          : (selected) {
                              if (!selected || profile == _profile) return;
                              setState(() => _profile = profile);
                              _optimize();
                            },
                    );
                  },
                ),
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
    final after = preview.after;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const ValueKey('route-optimization-recommended'),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: palette.accent.withValues(alpha: .35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: palette.accent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.route_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      s.s('routeOptimization.recommended'),
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.check_circle_rounded,
                    color: palette.matcha,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 18,
                runSpacing: 12,
                children: [
                  _CompactRouteMetric(
                    icon: Icons.schedule_rounded,
                    label: s.s('routeOptimization.travel'),
                    value:
                        '${after.totalTravelMinutes} ${s.s('routeOptimization.minute')}',
                    palette: palette,
                  ),
                  _CompactRouteMetric(
                    icon: Icons.directions_walk_rounded,
                    label: s.s('routeOptimization.walking'),
                    value:
                        '${after.totalWalkingMinutes} ${s.s('routeOptimization.minute')}',
                    palette: palette,
                  ),
                  _CompactRouteMetric(
                    icon: Icons.multiple_stop_rounded,
                    label: s.s('routeOptimization.transfers'),
                    value: '${after.totalTransferCount}',
                    palette: palette,
                  ),
                  _CompactRouteMetric(
                    icon: Icons.payments_outlined,
                    label: s.s('routeOptimization.cost'),
                    value: '¥${after.estimatedTransportCostYen}',
                    palette: palette,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (preview.result.optimizationChanges.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            s.s('routeOptimization.changes'),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: palette.bg.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              children: [
                for (final change in preview.result.optimizationChanges.take(3))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: palette.accent,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            change,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 13,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (preview.executionLegs.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            s.s('routeOptimization.legs.title'),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            s.s('routeOptimization.legs.subtitle'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: palette.bg.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < preview.executionLegs.length; i++) ...[
                  _RouteExecutionLegCard(
                    key: ValueKey('route-execution-leg-$i'),
                    leg: preview.executionLegs[i],
                    palette: palette,
                    compact: true,
                  ),
                  if (i != preview.executionLegs.length - 1)
                    Divider(height: 1, color: palette.border),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
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

class _CompactRouteMetric extends StatelessWidget {
  const _CompactRouteMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.palette,
  });

  final IconData icon;
  final String label;
  final String value;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: palette.accent, size: 16),
        const SizedBox(width: 5),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(_routeModeIcon(leg.mode), color: accent, size: 17),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '${leg.fromName}  →  ${leg.toName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _routeModeLabel(s, leg.mode),
                        style: TextStyle(
                          color: accent,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${leg.travelDurationMinutes} ${s.s('routeOptimization.minute')}',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (line != null || direction != null)
                Padding(
                  padding: const EdgeInsets.only(left: 24, top: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      [
                        if (line != null)
                          s.p('routeOptimization.legs.line', {'line': line}),
                        if (direction != null)
                          s.p('routeOptimization.legs.direction', {
                            'direction': direction,
                          }),
                      ].join('  ·  '),
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

/// Verilen günün "sıradaki" aktivitesi.
///
/// Geçmiş gün → null (yapılacak bir şey kalmadı), gelecek gün → günün ilk
/// aktivitesi, bugün → saati henüz gelmemiş ilk aktivite. Saatsiz aktivite
/// hiçbir zaman "geçmiş" sayılmaz, sırası geldiğinde kart onu gösterir.
TimelineItem? _nextActivityForDay(DayPlan day, DateTime now) {
  if (day.items.isEmpty) return null;
  final date = DateTime.tryParse(day.date);
  if (date == null) return day.items.first;
  final today = DateTime(now.year, now.month, now.day);
  final planDate = DateTime(date.year, date.month, date.day);
  if (planDate.isBefore(today)) return null;
  if (planDate.isAfter(today)) return day.items.first;
  final minutesNow = now.hour * 60 + now.minute;
  for (final item in day.items) {
    final minutes = _timeToMinutes(item.time ?? item.scheduledTime);
    if (minutes == null || minutes >= minutesNow) return item;
  }
  return null;
}

/// Gezinin TAMAMI bitti mi — son gün, o günün de son aktivitesi geçmiş mi?
///
/// **Neden ayrı bir kontrol:** "Bugünün planı tamamlandı" bandı her gün
/// bitiminde çıkar (ör. 3. günün sonu), ama gezinin kendisi bitmiş sayılmaz —
/// yarın hâlâ gidilecek günler var. Bu, yalnız listedeki SON günün de
/// tamamlandığı anı yakalar; o anda "gün tamamlandı" yerine tüm geziyi
/// özetleyen rapor gösterilir.
bool _isTripFinished(List<DayPlan> daysSorted, int activeIndex, DateTime now) {
  if (daysSorted.isEmpty) return false;
  if (activeIndex != daysSorted.length - 1) return false;
  return _nextActivityForDay(daysSorted[activeIndex], now) == null;
}

/// Sıradaki aktivite kartının sol ikonu — aktivitenin türünü yansıtır.
IconData _nextActivityIcon(TimelineItem item) {
  if (item.lockType == ActivityLockType.flight) {
    return Icons.flight_land_rounded;
  }
  return switch (item.kind) {
    TimelineItemKind.transport => Icons.directions_transit_rounded,
    TimelineItemKind.meal => Icons.restaurant_rounded,
    TimelineItemKind.hotel => Icons.hotel_rounded,
    _ => Icons.place_rounded,
  };
}

/// "SIRADAKI" kartı — accent zeminli, tam genişlikte, tek dokunuşla aktiviteyi
/// açan vurgu bloğu. Hem yolculuk hem harita tasarımı aynı kartı kullanır.
class _NextActivityCard extends StatelessWidget {
  const _NextActivityCard({
    super.key,
    required this.item,
    required this.day,
    required this.palette,
    required this.onOpen,
    this.elevated = false,
  });

  final TimelineItem item;
  final DayPlan day;
  final ViewerPalette palette;
  final VoidCallback onOpen;

  /// Harita tasarımında kart haritanın altında tek başına durur; gölge onu
  /// zeminden ayırır. Yolculuk kartının içindeyken gölgeye gerek yok.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final time = item.time ?? item.scheduledTime ?? '';
    return Material(
      color: palette.accent,
      borderRadius: BorderRadius.circular(18),
      elevation: elevated ? 4 : 0,
      shadowColor: palette.accent.withValues(alpha: 0.32),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _nextActivityIcon(item),
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF655B),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            s.s('viewer.template.next').toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
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
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      time.isEmpty ? item.title : '$time  ${item.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const CircleAvatar(
                radius: 17,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.chevron_right,
                  color: Colors.black87,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Harita tasarımında, aktif/son gün tamamlanınca "sıradaki aktivite"
/// kartının yerini alan kompakt çağrı — dokununca tam rapor bottom sheet
/// olarak açılır. Harita kendisi kapanmaz (geçmiş günleri gezmeye devam
/// edilebilir), yalnız bu tek CTA rapora yönlendirir.
class _TripCompletionCta extends StatelessWidget {
  const _TripCompletionCta({
    super.key,
    required this.palette,
    required this.onTap,
  });

  final ViewerPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Material(
      color: palette.matcha,
      borderRadius: BorderRadius.circular(20),
      elevation: 6,
      shadowColor: palette.matcha.withValues(alpha: 0.55),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: Colors.white,
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  s.s('viewer.report.cta'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const CircleAvatar(
                radius: 17,
                backgroundColor: Colors.white,
                child: Icon(Icons.chevron_right, color: Colors.black87),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Rota Panoraması" başlığı — günün eforunu tek bakışta veren pano.
///
/// Yolculuk tasarımının başlık varyantı: altındaki gün akışı birebir aynıdır,
/// yalnız bu blok değişir. Solda adım halkası, sağda mesafe/kalori/süre,
/// altta durak · ilerleme · kalan · rezervasyon.
class _RoutePanoramaHero extends ConsumerWidget {
  const _RoutePanoramaHero({
    required this.day,
    required this.now,
    required this.stops,
    required this.legs,
    required this.cityLabel,
    required this.palette,
  });

  final DayPlan day;
  final DateTime now;
  final List<ResolvedStop> stops;
  final List<RouteExecutionLeg> legs;
  final String cityLabel;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = LanguageScope.of(context);
    final p = palette;
    final distanceKm = _dayWalkingDistanceKm(stops);

    // Adım: cihazdan gelen canlı veri varsa o, yoksa plan tahmini, o da yoksa
    // mesafeden türetilen sayı. Kalori DAİMA gösterilen adımdan hesaplanır ki
    // ikisi birbirini tutsun.
    final stepsAsync = ref.watch(
      dayStepsProvider(
        DayStepsQuery(
          date: day.date,
          planEstimate: day.stepsEstimate,
          distanceKm: distanceKm,
        ),
      ),
    );
    // Cihaz okuması asenkron; beklerken "0" göstermek yerine plandan gelen
    // (senkron) değeri çiziyoruz — canlı veri gelince yerini alır.
    final fallbackSteps =
        day.stepsEstimate ?? (distanceKm * kStepsPerKm).round();
    final steps = stepsAsync.valueOrNull;
    final stepCount = steps?.steps ?? fallbackSteps;
    final kcal = kcalForSteps(stepCount);

    // Süre: gerçek rota bacakları varsa onların toplamı, yoksa ilk ve son
    // aktivite saati arasındaki fark.
    final travelMinutes = legs.isNotEmpty
        ? legs.fold<int>(0, (acc, l) => acc + l.travelDurationMinutes)
        : _dayPlannedMinutes(day);

    // İlerleme: günün kaç durağı geride kaldı.
    final total = day.items.length;
    final done = _completedStopCount(day, now);
    final progress = total == 0 ? 0.0 : done / total;
    final remainingKm = _remainingDistanceKm(stops, done);
    final reservations =
        day.items.where((it) => it.lockType != ActivityLockType.none).length;

    final isCompact = MediaQuery.sizeOf(context).width < 370;
    final horizontalPadding = isCompact ? 14.0 : 16.0;
    final ringSize = isCompact ? 118.0 : 132.0;
    final contentGap = isCompact ? 10.0 : 14.0;
    final backgroundCity = cityLabel.isEmpty ? day.theme : cityLabel;

    return Container(
      key: const ValueKey('viewer-template-panorama-hero'),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.border),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: MediaQuery.highContrastOf(context) ? 0.04 : 0.126,
                child: Image.asset(
                  cityHeroAssetFor(backgroundCity),
                  key: const ValueKey('viewer-panorama-city-background'),
                  alignment: Alignment.center,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey('viewer-panorama-contrast-overlay'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: .16),
                      Colors.black.withValues(alpha: .05),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              14,
              horizontalPadding,
              14,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_formatDayTitle(day.date, day.dayNumber, s.lang, weekdayHint: day.weekday)}'
                  '${cityLabel.isEmpty ? '' : ' · $cityLabel'}',
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  s.s('viewer.template.routePanorama'),
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    SizedBox(
                      width: ringSize,
                      height: ringSize,
                      child: CustomPaint(
                        key: const ValueKey('viewer-panorama-step-ring'),
                        painter:
                            _StepRingPainter(progress: progress, palette: p),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _groupThousands(stepCount),
                                key: const ValueKey('viewer-panorama-steps'),
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontSize: isCompact ? 24 : 27,
                                  fontWeight: FontWeight.w900,
                                  height: 1,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                s.s('viewer.metrics.steps'),
                                style: TextStyle(
                                  color: p.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (steps?.isLive == true) ...[
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: p.matcha.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    s.s('viewer.metrics.live'),
                                    style: TextStyle(
                                      color: p.matcha,
                                      fontSize: 8,
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
                    SizedBox(width: contentGap),
                    Expanded(
                      child: Column(
                        children: [
                          _PanoramaMetricRow(
                            icon: Icons.route_rounded,
                            tint: p.fuji,
                            value: '${_oneDecimal(distanceKm)} km',
                            label: s.s('viewer.metrics.distance'),
                            palette: p,
                          ),
                          const SizedBox(height: 10),
                          _PanoramaMetricRow(
                            icon: Icons.local_fire_department_rounded,
                            tint: p.sunset,
                            value: '$kcal kcal',
                            label: s.s('viewer.metrics.caloriesLabel'),
                            palette: p,
                          ),
                          const SizedBox(height: 10),
                          _PanoramaMetricRow(
                            icon: Icons.schedule_rounded,
                            tint: p.matcha,
                            value:
                                '$travelMinutes ${s.s('routeOptimization.minute')}',
                            label: s.s('viewer.metrics.duration'),
                            palette: p,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(color: p.border, height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _PanoramaFootCell(
                      icon: Icons.place_rounded,
                      value: '$total',
                      label: s.s('viewer.metrics.stops'),
                      palette: p,
                    ),
                    _PanoramaFootCell(
                      icon: Icons.donut_large_rounded,
                      value: '%${(progress * 100).round()}',
                      label: s.s('viewer.metrics.progress'),
                      palette: p,
                    ),
                    _PanoramaFootCell(
                      icon: Icons.directions_walk_rounded,
                      value: '${_oneDecimal(remainingKm)} km',
                      label: s.s('viewer.metrics.remaining'),
                      palette: p,
                    ),
                    _PanoramaFootCell(
                      icon: Icons.confirmation_number_rounded,
                      value: '$reservations',
                      label: s.s('viewer.metrics.reservations'),
                      palette: p,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Binlik ayraçlı sayı — "12400" → "12.400".
String _groupThousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return '${value < 0 ? '-' : ''}$buffer';
}

String _oneDecimal(double value) =>
    value.toStringAsFixed(1).replaceAll('.', ',');

/// Günün ilk ve son saatli aktivitesi arasındaki dakika farkı.
int _dayPlannedMinutes(DayPlan day) {
  final minutes = <int>[];
  for (final item in day.items) {
    final m = _timeToMinutes(item.time ?? item.scheduledTime);
    if (m != null) minutes.add(m);
  }
  if (minutes.length < 2) return 0;
  minutes.sort();
  return minutes.last - minutes.first;
}

/// Saati geçmiş (tamamlanmış sayılan) durak adedi.
int _completedStopCount(DayPlan day, DateTime now) {
  final date = DateTime.tryParse(day.date);
  if (date == null) return 0;
  final today = DateTime(now.year, now.month, now.day);
  final planDate = DateTime(date.year, date.month, date.day);
  if (planDate.isAfter(today)) return 0;
  if (planDate.isBefore(today)) return day.items.length;
  final minutesNow = now.hour * 60 + now.minute;
  var done = 0;
  for (final item in day.items) {
    final m = _timeToMinutes(item.time ?? item.scheduledTime);
    if (m != null && m < minutesNow) done++;
  }
  return done;
}

/// Tamamlanan duraklardan sonra kalan yürüyüş mesafesi.
double _remainingDistanceKm(List<ResolvedStop> stops, int done) {
  if (stops.length < 2) return 0;
  final from = done.clamp(0, stops.length - 1);
  return _dayWalkingDistanceKm(stops.sublist(from));
}

/// Panoramadaki sağ sütun satırı: renkli ikon + değer + etiket.
class _PanoramaMetricRow extends StatelessWidget {
  const _PanoramaMetricRow({
    required this.icon,
    required this.tint,
    required this.value,
    required this.label,
    required this.palette,
  });

  final IconData icon;
  final Color tint;
  final String value;
  final String label;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 17),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Panoramanın alt şeridindeki tek hücre.
class _PanoramaFootCell extends StatelessWidget {
  const _PanoramaFootCell({
    required this.icon,
    required this.value,
    required this.label,
    required this.palette,
  });

  final IconData icon;
  final String value;
  final String label;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: palette.bg,
              shape: BoxShape.circle,
              border: Border.all(color: palette.border),
            ),
            child: Icon(icon, color: palette.textSecondary, size: 17),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bir gezinin tamamına ait özet sayılar — [_TripCompletionReport]'un girdisi.
///
/// `[_ViewerBodyState._buildTripReportStats]` tarafından, gezinin tüm
/// günlerinden tek seferde hesaplanır.
class _TripReportStats {
  const _TripReportStats({
    required this.dayCount,
    required this.placesVisited,
    required this.mealsCount,
    required this.totalDistanceKm,
    required this.totalSteps,
    required this.totalKcal,
    required this.totalMinutes,
    required this.reservationsCount,
    required this.cities,
  });

  final int dayCount;

  /// `TimelineItemKind.activity` türündeki durak sayısı — gezip görülen yerler
  /// (transfer/check-in gibi lojistik adımlar dışarıda).
  final int placesVisited;
  final int mealsCount;
  final double totalDistanceKm;
  final int totalSteps;
  final int totalKcal;
  final int totalMinutes;
  final int reservationsCount;

  /// Ziyaret edilen şehirler, gezideki sırayla, tekrarsız.
  final List<String> cities;
}

/// Gezi tamamen bittiğinde gösterilen detaylı rapor.
///
/// Tek satırlık "Bugünün planı tamamlandı" bandının yerini alır — o banner
/// yalnız GÜNÜN bittiğini söylüyordu, GEZİNİN kendisinin bittiğini değil.
/// Bu widget [_ViewerBodyState._isTripFinished] `true` olduğunda, hem
/// Yolculuk hem Rota Panoraması tasarımlarında günlük kartların YERİNE
/// geçer; harita tasarımında ise bir CTA'dan bottom sheet olarak açılır.
class _TripCompletionReport extends StatelessWidget {
  const _TripCompletionReport({
    required this.trip,
    required this.stats,
    required this.palette,
    this.expanded,
    this.onToggleExpanded,
  });

  final Trip trip;
  final _TripReportStats stats;
  final ViewerPalette palette;

  /// `null` → günlere dönüş satırı hiç gösterilmez (bottom sheet'te harita
  /// zaten tarih şeridiyle geziliyor, ayrı bir "günleri göster" gerekmez).
  final bool? expanded;
  final VoidCallback? onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final p = palette;
    final stepsLabel = _groupThousands(stats.totalSteps);
    final distanceLabel = '${_oneDecimal(stats.totalDistanceKm)} km';

    return Container(
      key: const ValueKey('viewer-trip-completion-report'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: p.matcha.withValues(alpha: 0.35),
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: p.matcha.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.emoji_events_rounded,
                  color: p.matcha,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.s('viewer.report.title'),
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${trip.title} · ${stats.dayCount} ${s.s('viewer.report.days')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: p.bg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                _MetricCell(
                  value: stepsLabel,
                  label: s.s('viewer.metrics.steps'),
                  color: p.accent,
                  palette: p,
                ),
                _MetricDivider(palette: p),
                _MetricCell(
                  value: distanceLabel,
                  label: s.s('viewer.metrics.distance'),
                  color: p.matcha,
                  palette: p,
                ),
                _MetricDivider(palette: p),
                _MetricCell(
                  value: '${stats.totalKcal}',
                  label: s.s('viewer.metrics.calories'),
                  color: const Color(0xFFFF655B),
                  palette: p,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _PanoramaFootCell(
                icon: Icons.place_rounded,
                value: '${stats.placesVisited}',
                label: s.s('viewer.report.places'),
                palette: p,
              ),
              _PanoramaFootCell(
                icon: Icons.restaurant_rounded,
                value: '${stats.mealsCount}',
                label: s.s('viewer.report.meals'),
                palette: p,
              ),
              _PanoramaFootCell(
                icon: Icons.location_city_rounded,
                value: '${stats.cities.length}',
                label: s.s('viewer.report.cities'),
                palette: p,
              ),
              _PanoramaFootCell(
                icon: Icons.confirmation_number_rounded,
                value: '${stats.reservationsCount}',
                label: s.s('viewer.metrics.reservations'),
                palette: p,
              ),
            ],
          ),
          if (stats.cities.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final city in stats.cities)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: p.sky.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      city,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (onToggleExpanded != null) ...[
            const SizedBox(height: 10),
            Divider(color: p.border, height: 1),
            const SizedBox(height: 4),
            InkWell(
              key: const ValueKey('viewer-trip-report-toggle-days'),
              onTap: onToggleExpanded,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      expanded == true
                          ? s.s('viewer.report.hideDays')
                          : s.s('viewer.report.showDays'),
                      style: TextStyle(
                        color: p.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      expanded == true
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: p.accent,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Adım halkası — tek parça yay, günün ilerlemesi kadar dolar.
class _StepRingPainter extends CustomPainter {
  const _StepRingPainter({required this.progress, required this.palette});

  final double progress;
  final ViewerPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: size.width * 0.42);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..color = Color.alphaBlend(
        palette.textSecondary.withValues(alpha: 0.12),
        palette.card,
      );
    canvas.drawArc(rect, 0, math.pi * 2, false, track);

    final sweep = (math.pi * 2) * progress.clamp(0.0, 1.0);
    if (sweep <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [palette.matcha, palette.sky, palette.accent],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc);
  }

  @override
  bool shouldRepaint(covariant _StepRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.palette != palette;
}

class _JourneyHeroImage extends StatelessWidget {
  const _JourneyHeroImage({
    required this.day,
    required this.dayNumber,
    required this.dayCount,
    required this.palette,
  });

  final DayPlan day;
  final int dayNumber;
  final int dayCount;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final total = dayCount < 1 ? 1 : dayCount;
    final done = dayNumber.clamp(0, total);

    return Container(
      key: const ValueKey('viewer-template-journey-hero'),
      height: 205,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/journey-progress-hero.webp',
              key: const ValueKey('viewer-journey-progress-background'),
              fit: BoxFit.cover,
              alignment: Alignment.center,
              opacity: const AlwaysStoppedAnimation(1.0),
            ),
          ),
          Positioned.fill(
            child: ColoredBox(
              color: palette.card.withValues(alpha: 0.72),
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
    );
  }
}

class _JourneyHeroSheet extends StatelessWidget {
  const _JourneyHeroSheet({
    required this.day,
    required this.now,
    required this.palette,
    required this.onOpenItem,
  });

  final DayPlan day;
  final DateTime now;
  final ViewerPalette palette;
  final ValueChanged<TimelineItem> onOpenItem;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final next = _nextActivityForDay(day, now);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: next != null
          ? _NextActivityCard(
              key: const ValueKey('viewer-journey-next-activity'),
              item: next,
              day: day,
              palette: palette,
              onOpen: () => onOpenItem(next),
            )
          : Container(
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
    // Dilim sayısı = gezinin toplam gün sayısı. Halka tüm 360°'ye bu kadar
    // eşit parçaya bölünür; 4 gün de olsa 16 gün de olsa grafik uyum sağlar.
    final segments = total < 1 ? 1 : total;
    final activeSegments = done.clamp(0, segments);
    // Çok günlü gezilerde dilimler inceldiği için boşluğu ve kalınlığı ölçekle:
    // aksi halde 16 dilimde çizgiler birbirine değer, boşluk kaybolurdu.
    final step = (2 * math.pi) / segments;
    final gap = math.min(0.14, step * 0.28);
    final sweep = step - gap;
    final strokeWidth = segments <= 6
        ? 22.0
        : segments <= 10
            ? 16.0
            : segments <= 16
                ? 11.0
                : 7.0;
    // Dilim numaraları yalnız az günde okunur; kalabalıkta merkez sayaç yeter.
    final showLabels = segments <= 8;
    final segmentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    for (var index = 0; index < segments; index++) {
      segmentPaint.color = index < activeSegments
          ? palette.accent
          : Color.alphaBlend(
              palette.textSecondary.withValues(alpha: 0.10),
              palette.card,
            );
      final start = -math.pi / 2 + index * step + gap / 2;
      canvas.drawArc(rect, start, sweep, false, segmentPaint);

      if (!showLabels) continue;
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

    // Harita tasarımı tek ekrana sığar: önceki kompozisyona göre yaklaşık %10
    // daha kısa tutulur. Okunabilirlik için 241 dp altına düşmez; 270 dp üstüne
    // çıkmayarak sıradaki aktivite ve gün rotasına daha fazla alan bırakır.
    // Alt sınır, Katmanlar pili ile sadeleştirilmiş tarih şeridinin birbirine
    // girmeden ortalanabildiği en düşük yüksekliktir.
    final screenHeight = MediaQuery.sizeOf(context).height;
    final heroHeight = math.min(270.0, math.max(241.0, screenHeight * 0.288));

    // "Rotaya sığdır" padding'i hero yüksekliğine göre ölçeklenir.
    //
    // **Neden:** Sabit (62 üst / 130 alt) padding, hero kısaldığında toplamda
    // yüksekliğin neredeyse tamamını yiyordu; geriye kalan alan sığdırmaya
    // yetmeyince rota ekran dışına taşıyordu. Padding'i yüksekliğe oranlayıp
    // dikeyde en fazla ~%45'ini kullanmasına izin veriyoruz.
    final vInset = (heroHeight * 0.09).clamp(14.0, 32.0);
    final bottomInset = (heroHeight * 0.30).clamp(72.0, 102.0);
    final options = points.length >= 2
        ? MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(points),
              padding: EdgeInsets.fromLTRB(40, vInset, 40, bottomInset),
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
      height: heroHeight,
      margin: const EdgeInsets.only(bottom: 10),
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
                    // Etiketsiz zemin: başlıkta Japonca yer adları yerine
                    // rotanın kendisi okunur.
                    urlTemplate: kRotoriPlainTileUrlTemplate,
                    subdomains: kRotoriPlainTileSubdomains,
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
                      // Etiketsiz zemin CARTO'dan geliyor — atıf zorunlu.
                      TextSourceAttribution(
                        'CARTO',
                        onTap: () async {
                          await launchUrl(
                            Uri.parse(kCartoAttributionUrl),
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
            bottom: 92,
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
            bottom: 76,
            child: Material(
              color: palette.card.withValues(alpha: 0.97),
              shape: const CircleBorder(),
              elevation: 4,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onOpenMap(day),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: Icon(
                    Icons.my_location_rounded,
                    color: palette.textPrimary,
                    size: 23,
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
              height: 62,
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
                      final chipColor = Color.alphaBlend(
                        palette.accent.withValues(
                          alpha: selected ? 0.15 : 0.025,
                        ),
                        palette.card,
                      );
                      return Material(
                        color: chipColor.withValues(alpha: 0.98),
                        borderRadius: BorderRadius.circular(12),
                        elevation: selected ? 2 : 0,
                        child: InkWell(
                          key: ValueKey(
                            'viewer-map-day-${candidate.dayNumber}',
                          ),
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => onSelectDay(candidate),
                          child: Container(
                            width: chipWidth,
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color:
                                    selected ? palette.accent : palette.border,
                                width: selected ? 1.5 : 1,
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
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    height: 1,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  shortMonth,
                                  style: TextStyle(
                                    color: selected
                                        ? palette.accent
                                        : palette.textSecondary,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  shortWeekday,
                                  style: TextStyle(
                                    color: palette.textSecondary,
                                    fontSize: 8.5,
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

/// Günün duraklarından yürüme mesafesi (km).
///
/// Duraklar arası kuş uçuşu mesafenin toplamı; gerçek yol her zaman biraz daha
/// uzun olduğu için 1.25 katsayısıyla düzeltilir (şehir içi ızgara yürüyüşü).
double _dayWalkingDistanceKm(List<ResolvedStop> stops) {
  if (stops.length < 2) return 0;
  const earthRadiusKm = 6371.0;
  double toRad(double d) => d * math.pi / 180;
  var total = 0.0;
  for (var i = 0; i < stops.length - 1; i++) {
    final a = stops[i];
    final b = stops[i + 1];
    final dLat = toRad(b.lat - a.lat);
    final dLng = toRad(b.lng - a.lng);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(toRad(a.lat)) *
            math.cos(toRad(b.lat)) *
            math.pow(math.sin(dLng / 2), 2);
    total += 2 * earthRadiusKm * math.asin(math.sqrt(h));
  }
  return total * 1.25;
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.value,
    required this.label,
    required this.color,
    required this.palette,
  });

  final String value;
  final String label;
  final Color color;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 19,
              fontWeight: FontWeight.w900,
              height: 1.1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider({required this.palette});

  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 26, color: palette.border);
  }
}

const double _kMapTemplatePhotoMarkerMinZoom = 15;

class _MapTemplateMarker extends StatelessWidget {
  const _MapTemplateMarker({required this.stop, required this.palette});

  final ResolvedStop stop;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final zoom = MapCamera.maybeOf(context)?.zoom ?? 0;
    final imageUrl = _mapTemplateImageUrl(stop);
    final showPhoto =
        imageUrl != null && zoom >= _kMapTemplatePhotoMarkerMinZoom;
    return Stack(
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 30,
          child: SizedBox(
            width: 28,
            height: 28,
            child: showPhoto
                ? _MapTemplatePhotoPin(
                    order: stop.order,
                    imageUrl: imageUrl,
                    palette: palette,
                  )
                : _MapTemplatePin(order: stop.order, palette: palette),
          ),
        ),
        if (!showPhoto)
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

String? _mapTemplateImageUrl(ResolvedStop stop) {
  final resolver = PlaceImageResolver.instance;
  final direct = resolver.peekCurated(stop.item.title);
  if (direct != null && direct.isNotEmpty) return direct.first;
  final place = stop.place;
  if (place == null) return null;
  final matched = resolver.peekCurated(place.name);
  return matched == null || matched.isEmpty ? null : matched.first;
}

class _MapTemplatePhotoPin extends StatelessWidget {
  const _MapTemplatePhotoPin({
    required this.order,
    required this.imageUrl,
    required this.palette,
  });

  final int order;
  final String imageUrl;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Durak $order',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -10,
            top: -10,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: palette.card,
                  border: Border.all(color: Colors.white, width: 2.5),
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x45000000),
                      blurRadius: 7,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  cacheWidth: 128,
                  cacheHeight: 128,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (_, __, ___) => _MapTemplatePin(
                    order: order,
                    palette: palette,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: -12,
            top: -12,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: palette.accent, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                '$order',
                style: TextStyle(
                  color: palette.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 9.5,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
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
    required this.now,
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

  /// Uygulamanın "şimdi"si (debug ofsetli olabilir) — "sıradaki" rozetini ve
  /// geçmiş/gelecek aktivite işaretlerini bu belirler.
  final DateTime now;
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
    final now = widget.now;
    final nextIdx = _nextUpcomingIndex(now);
    // Uyarıları hesapla (saf-Dart, hızlı) — satırlar bunları saat rozetinde
    // gösterir, gün başlığı ise özet banner çıkarır.
    final warningsMap = warningsByActivity(day);
    final totalWarnings =
        warningsMap.values.fold<int>(0, (acc, list) => acc + list.length);
    final routeLegs = _displayRouteLegs(day, widget.dest);

    final card = Container(
      key: widget.isActive && !compact
          ? ValueKey('viewer-day-card-${day.dayNumber}')
          : null,
      margin: EdgeInsets.only(bottom: compact ? 6 : 12),
      decoration: BoxDecoration(
        color: compact ? p.card : (widget.isActive ? p.cardHover : p.card),
        borderRadius: BorderRadius.circular(cardRadius),
        border: Border.all(color: p.border),
        boxShadow: widget.isActive && !compact
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .07),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Başlık satırı (tıklanınca genişlet/daralt).
              InkWell(
                borderRadius: BorderRadius.circular(cardRadius),
                onTap: widget.onToggleExpand,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 10 : 14,
                    vertical: compact ? 9 : 16,
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
                          tooltip: LanguageScope.of(context)
                              .s('viewer.edit.editDay'),
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
                        duration: RotoriMotion.duration(
                            context, const Duration(milliseconds: 220)),
                        curve: RotoriMotion.curve(context),
                        child: Icon(
                          Icons.expand_more,
                          color: p.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              RotoriAnimatedSize(
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
                          compact ? 10 : 16,
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
                                  key: ValueKey(
                                      'drop-day-${day.dayNumber}-slot-0'),
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
                                    for (var i = 0;
                                        i < day.items.length;
                                        i++) ...[
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
                                            warnings: warningsMap[item.id] ??
                                                const [],
                                            onEditTime: () =>
                                                widget.onEditItemTime(day, i),
                                            onOpen: () => widget.onOpenItem(
                                                item, widget.dest),
                                            onToggleLock: () => widget
                                                .onToggleItemLock(day, item),
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
                                                  direction: DismissDirection
                                                      .endToStart,
                                                  dismissThresholds: const {
                                                    DismissDirection.endToStart:
                                                        0.4,
                                                  },
                                                  background:
                                                      const SizedBox.shrink(),
                                                  secondaryBackground:
                                                      _SwipeDeleteBg(
                                                          palette: p),
                                                  onDismissed: (_) {
                                                    HapticFeedback
                                                        .mediumImpact();
                                                    widget.onDeleteItem(day, i);
                                                  },
                                                  child: row,
                                                )
                                              : row;
                                          if (item.isFixed ||
                                              !item.canChangeDay) {
                                            return dismissible;
                                          }
                                          return Semantics(
                                            label: LanguageScope.of(context)
                                                .s('viewer.edit.dragHint'),
                                            button: true,
                                            child: LongPressDraggable<
                                                _ActivityDragData>(
                                              key: ValueKey(
                                                  'draggable-${item.id}'),
                                              data: _ActivityDragData(
                                                sourceDay: day,
                                                itemIndex: i,
                                                itemId: item.id,
                                              ),
                                              maxSimultaneousDrags: 1,
                                              onDragStarted: () {
                                                HapticFeedback.mediumImpact();
                                                widget.dragActive.value =
                                                    item.id;
                                              },
                                              onDragUpdate: widget.onDragUpdate,
                                              onDragEnd: (_) {
                                                HapticFeedback.lightImpact();
                                                widget.dragActive.value = null;
                                              },
                                              onDraggableCanceled: (_, __) =>
                                                  widget.dragActive.value =
                                                      null,
                                              onDragCompleted: () => widget
                                                  .dragActive.value = null,
                                              feedback: Material(
                                                color: Colors.transparent,
                                                child: SizedBox(
                                                  width:
                                                      MediaQuery.sizeOf(context)
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
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
                                    warnings: warningsMap[day.items[i].id] ??
                                        const [],
                                    onOpen: () => widget.onOpenItem(
                                        day.items[i], widget.dest),
                                  ),
                                ],
                              for (final leg in routeLegs.where((leg) =>
                                  !leg.isTrivial &&
                                  leg.kind ==
                                      RouteExecutionLegKind.returnToBase))
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(8, 3, 0, 5),
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
                                      Icons.cloud_outlined,
                                      LanguageScope.of(context)
                                          .s('routeOptimization.weatherAction'),
                                      p.accent,
                                      () => widget.onOptimizeWeatherRoute(
                                        day,
                                        widget.dest,
                                        widget.forecast,
                                      ),
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
          if (widget.isActive && !compact)
            Positioned(
              key: const ValueKey('viewer-day-card-active-accent'),
              left: 0,
              top: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: p.sakura,
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(cardRadius),
                  ),
                ),
                child: const SizedBox(width: 3),
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
    final reduceMotion = RotoriMotion.reduce(context);
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
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 140),
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
      ViewerTemplateId.routePanorama => 'viewer.template.routePanorama',
    };

String _templateDescriptionKey(ViewerTemplateId id) => switch (id) {
      ViewerTemplateId.journeyProgress =>
        'viewer.template.journeyProgress.description',
      ViewerTemplateId.mapFocus => 'viewer.template.mapFocus.description',
      ViewerTemplateId.routePanorama =>
        'viewer.template.routePanorama.description',
    };

void _showTemplatePremiumSheet(BuildContext context) {
  final s = LanguageScope.of(context);
  showRotoriPremiumSheet<void>(
    context,
    title: s.s('viewer.template.premium.title'),
    body: s.s('viewer.template.premium.body'),
    closeLabel: s.s('viewer.template.premium.close'),
    closeButtonKey: const ValueKey('viewer-template-premium-close'),
    benefits: [
      RotoriPremiumBenefit(
        icon: Icons.route_rounded,
        text: s.s('viewer.template.premium.journey'),
      ),
      RotoriPremiumBenefit(
        icon: Icons.map_outlined,
        text: s.s('viewer.template.premium.map'),
      ),
    ],
  );
}

class _ThemePickerSheet extends ConsumerWidget {
  const _ThemePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(viewerThemeProvider);
    final currentTemplate = ref.watch(viewerTemplateProvider);
    final isPremium = ref.watch(premiumProvider);
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
          child: SizedBox(
            height: math.min(MediaQuery.sizeOf(context).height * .90, 760.0),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Column(
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
                        SizedBox(
                          height: 184,
                          child: ListView.separated(
                            key: const ValueKey(
                                'viewer-template-horizontal-list'),
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(right: 20),
                            physics: const BouncingScrollPhysics(),
                            itemCount: ViewerTemplateId.values.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final id = [
                                ViewerTemplateId.routePanorama,
                                ViewerTemplateId.journeyProgress,
                                ViewerTemplateId.mapFocus,
                              ][index];
                              final locked = !isPremium &&
                                  id != ViewerTemplateId.routePanorama;
                              return _TemplateOption(
                                id: id,
                                palette: palette,
                                selected: id == currentTemplate,
                                locked: locked,
                                onTap: locked
                                    ? () => _showTemplatePremiumSheet(context)
                                    : () => ref
                                        .read(viewerTemplateProvider.notifier)
                                        .set(id),
                              );
                            },
                          ),
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
                            onTap: () =>
                                ref.read(viewerThemeProvider.notifier).set(id),
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
                        for (final l in AppLang.values)
                          _LangOption(
                            lang: l,
                            palette: palette,
                            selected: l == lang,
                            onTap: () =>
                                ref.read(appLangProvider.notifier).set(l),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                      key: const ValueKey('viewer-appearance-done'),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        s.s('common.done'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
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

class _TemplateOption extends StatelessWidget {
  const _TemplateOption({
    required this.id,
    required this.palette,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final ViewerTemplateId id;
  final ViewerPalette palette;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final cardWidth = math.min(
      272.0,
      math.max(232.0, MediaQuery.sizeOf(context).width - 64),
    );
    return Semantics(
      selected: selected,
      button: true,
      label: '${s.s(_templateLabelKey(id))}${locked ? ', Premium' : ''}',
      child: InkWell(
        key: ValueKey('viewer-template-${id.storageKey}'),
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: cardWidth,
          decoration: BoxDecoration(
            color: selected
                ? palette.accent.withValues(alpha: 0.08)
                : palette.elevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
              width: selected ? 2.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TemplatePreview(
                      id: id,
                      palette: palette,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.s(_templateLabelKey(id)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      s.s(_templateDescriptionKey(id)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              if (locked)
                Positioned(
                  key: ValueKey('viewer-template-lock-${id.storageKey}'),
                  top: 18,
                  right: 18,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.textPrimary.withValues(alpha: .86),
                      shape: BoxShape.circle,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(7),
                      child: Icon(
                        Icons.lock_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              if (selected)
                Positioned(
                  key: ValueKey('viewer-template-selected-${id.storageKey}'),
                  top: 18,
                  right: 18,
                  child: Icon(
                    Icons.check_circle,
                    color: palette.accent,
                    size: 25,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplatePreview extends StatelessWidget {
  const _TemplatePreview({required this.id, required this.palette});

  final ViewerTemplateId id;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ColoredBox(
          color: palette.bg,
          child: switch (id) {
            ViewerTemplateId.journeyProgress => Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/journey-progress-hero.webp',
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    opacity: const AlwaysStoppedAnimation(.30),
                  ),
                  ColoredBox(color: palette.card.withValues(alpha: .56)),
                  Center(
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: CustomPaint(
                        painter: _TemplatePreviewRingPainter(palette: palette),
                        child: Center(
                          child: Text(
                            '3/7',
                            style: TextStyle(
                              color: palette.accent,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ViewerTemplateId.mapFocus => CustomPaint(
                painter: _TemplateMapPreviewPainter(palette: palette),
              ),
            ViewerTemplateId.routePanorama => CustomPaint(
                painter: _TemplatePanoramaPreviewPainter(palette: palette),
              ),
          },
        ),
      ),
    );
  }
}

class _TemplatePreviewRingPainter extends CustomPainter {
  const _TemplatePreviewRingPainter({required this.palette});

  final ViewerPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width * .39,
    );
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = palette.textMuted.withValues(alpha: .18);
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 8
      ..color = palette.accent;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 1.55, false, progress);
  }

  @override
  bool shouldRepaint(covariant _TemplatePreviewRingPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

class _TemplateMapPreviewPainter extends CustomPainter {
  const _TemplateMapPreviewPainter({required this.palette});

  final ViewerPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = palette.textMuted.withValues(alpha: .10)
      ..strokeWidth = 1;
    for (var x = 12.0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x - 12, size.height), grid);
    }
    for (var y = 12.0; y < size.height; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 8), grid);
    }
    final route = Paint()
      ..color = palette.accent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * .15, size.height * .72)
      ..lineTo(size.width * .42, size.height * .35)
      ..lineTo(size.width * .74, size.height * .58)
      ..lineTo(size.width * .87, size.height * .23);
    canvas.drawPath(path, route);
    for (final point in [
      Offset(size.width * .15, size.height * .72),
      Offset(size.width * .42, size.height * .35),
      Offset(size.width * .74, size.height * .58),
      Offset(size.width * .87, size.height * .23),
    ]) {
      canvas.drawCircle(point, 8, Paint()..color = palette.sakura);
      canvas.drawCircle(point, 4, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _TemplateMapPreviewPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

class _TemplatePanoramaPreviewPainter extends CustomPainter {
  const _TemplatePanoramaPreviewPainter({required this.palette});

  final ViewerPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .31, size.height * .5);
    final rect = Rect.fromCircle(center: center, radius: 31);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..color = palette.accent.withValues(alpha: .18);
    canvas.drawArc(rect, 0, math.pi * 2, false, ring);
    final active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = palette.accent;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 1.45, false, active);
    for (var i = 0; i < 3; i++) {
      final y = size.height * (.28 + i * .23);
      final color = [palette.fuji, palette.sunset, palette.matcha][i];
      canvas.drawCircle(
        Offset(size.width * .64, y),
        9,
        Paint()..color = color.withValues(alpha: .92),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * .72, y - 5, size.width * .20, 10),
          const Radius.circular(5),
        ),
        Paint()..color = palette.textPrimary.withValues(alpha: .15),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TemplatePanoramaPreviewPainter oldDelegate) =>
      oldDelegate.palette != palette;
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
      key: ValueKey('viewer-language-option-${lang.code}'),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.borderStrong),
              ),
              alignment: Alignment.center,
              child: Text(
                lang.code.toUpperCase(),
                style: TextStyle(
                  color: palette.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                lang.label,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (selected) ...[
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
      key: ValueKey('viewer-theme-option-${id.storageKey}'),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
            const SizedBox(width: 10),
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
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.borderStrong),
      ),
      child: Center(
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: palette.gradientSakura),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
