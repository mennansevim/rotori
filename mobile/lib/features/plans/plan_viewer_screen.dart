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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../core/supabase_client.dart';
import '../../data/google_maps_launcher.dart';
import '../../data/language_store.dart';
import '../../data/plans_repository.dart';
import '../../data/reminders_store.dart';
import '../../data/weather_service.dart';
import '../../domain/city_palette.dart';
import '../../domain/city_places.dart';
import '../../domain/day_schedule.dart' as sched;
import '../../domain/destination_profiles.dart';
import '../../domain/itinerary_optimizer.dart';
import '../../domain/place_coords.dart';
import '../../domain/place_image_resolver.dart';
import '../../domain/plan_schedule_engine.dart';
import '../../domain/plan_warnings.dart';
import '../../domain/route_matrix.dart';
import '../../domain/types.dart';
import '../auth/auth_repository.dart';
import '../shared/place_detail_sheet.dart';
import '../shared/ticket_support.dart';
import '../viewer/budget_screen.dart';
import '../viewer/checklist_screen.dart';
import '../viewer/compass_screen.dart';
import '../viewer/home_widget_hook.dart';
import '../viewer/japanese_phrases_screen.dart';
import '../viewer/must_know_screen.dart';
import '../viewer/pre_departure_checklist_screen.dart';
import '../viewer/reward_map_screen.dart';
import '../viewer/viewer_theme.dart';
import '../viewer/weather_screen.dart';
import 'plan_providers.dart';
import 'plan_edit_session.dart';
import 'plan_optimization_controller.dart';

// ---------------------------------------------------------------------------
// Tarih yardımcıları — dile göre ay/gün dizisi (intl locale'e bağlı DEĞİL).
// ---------------------------------------------------------------------------

/// "1. Gün Cuma" (tr) / "Day 1 Friday" (en). Rozet zaten tarihi gösterdiğinden
/// başlık satırı gün sırası + hafta gününü verir.
String _formatDayTitle(String isoDate, int dayNumber, AppLang lang,
    {String? weekdayHint}) {
  final d = DateTime.tryParse(isoDate);
  final weekdays = L10n.weekdaysFor(lang);
  final wd = (lang == AppLang.tr && weekdayHint?.isNotEmpty == true)
      ? weekdayHint!
      : (d != null ? weekdays[d.weekday] : '');
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

  /// Global drag durumu — null = boşta, "itemId" = o item sürükleniyor.
  /// Tüm drop-slot'lar dinleyip drag aktif olduğunda kendini büyütür; böylece
  /// Apple-vari "diğer aktiviteler kayarak yer açar" hissi verilir.
  final ValueNotifier<String?> _dragActiveNotifier = ValueNotifier<String?>(null);

  /// Akordiyon davranışı moda göre değişir:
  /// - **View modu (varsayılan kapalı):** ilk açılışta bütün günler kapalı.
  ///   Kullanıcı okumak istediği güne dokununca o gün `_expandedInView`'a
  ///   girer ve açılır.
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
  late final PlanEditSession _editSession;
  PlanEditState? _editState;
  Timer? _undoSnackTimer;
  int _planVersion = 0;

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
      HomeWidgetHook.pushFromTrip(_trip);
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
    _undoSnackTimer?.cancel();
    _editSession.dispose();
    _scrollController.dispose();
    _dragActiveNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ViewerPalette.of(context);
    final trip = _trip;
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
            // Edit modu üst bar'ı — planı bütün olarak dönüştüren toplu
            // aksiyonlar burada durur. Şimdilik: "Tüm rotayı yeniden optimize et".
            if (_editMode)
              _EditToolbar(
                palette: palette,
                onOptimizeAll: () => _optimizeAllRoutes(days),
              ),
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  if (days.isEmpty)
                    _EmptyDaysCard(palette: palette)
                  else
                    for (var i = 0; i < days.length; i++) ...[
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
                        expanded: _editMode
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
                        onOptimizeRoute: () => _openRouteOptimization(
                          days[i],
                          getDestinationForDate(
                            _sortedDestinations,
                            days[i].date,
                          ),
                        ),
                        onDropItem: _dropActivity,
                        onDeleteItem: _deleteItem,
                        onEditItemTime: _editItemTime,
                        onAddItem: _addItemToDay,
                        onEditDay: _editDay,
                        onMoveDay: _moveDay,
                        onDragUpdate: _autoScrollDuringDrag,
                        dragActive: _dragActiveNotifier,
                      ),
                      if (i < days.length - 1)
                        _cityTransitionBetween(days[i], days[i + 1], palette),
                    ],
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
    final existing = _trip.tickets
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
        _trip.tickets.removeWhere((x) => x.label == t.label);
        _trip.tickets.add(t);
        ref.read(plansRepositoryProvider)?.save(_trip);
        if (mounted) setState(() {});
      },
    );
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
      durationMin: 90,
    );
    if (!mounted) return;
    final addedMessage = LanguageScope.of(context)
        .p('viewer.edit.addedSnack', {'title': item.title});
    final added = await _applyEdit(
      AddActivity(dayNumber: day.dayNumber, activity: item),
      successMessage: addedMessage,
    );
    if (!added) return;
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
      // varsayılanına döner. View: hepsi kapalı, edit: hepsi açık.
      _expandedInView.clear();
      _collapsedInEdit.clear();
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

  void _openMap() {
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

  /// Pusula ekranını açar (acil numaralar, otel adresi, Japonca frazlar).
  void _openCompass() {
    final palette = ref.read(viewerPaletteProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: palette.toThemeData(),
          child: ViewerPaletteScope(
            palette: palette,
            child: CompassScreen(trip: _trip),
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
            child: BudgetScreen(trip: _trip),
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
            child: ChecklistScreen(trip: _trip),
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

  /// Pratik Japonca kelimeler & cümleler sayfası.
  void _openPhrases() {
    final palette = ref.read(viewerPaletteProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: palette.toThemeData(),
          child: ViewerPaletteScope(
            palette: palette,
            child: JapanesePhrasesScreen(trip: _trip),
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
    final tripStops = resolveTripStops(_trip);
    final sortedDays = [..._trip.days]
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
            child: MustKnowScreen(trip: _trip),
          ),
        ),
      ),
    );
  }

  /// Günün duraklarını doğrudan Google Maps ile aç — cihazda Google Maps app
  /// yüklüyse rota + turn-by-turn yönlendirme (transit); yoksa Google Maps
  /// web'de aynı rota. İç OSM haritası artık ana giriş noktası değil (kullanıcı
  /// mesajı: "haritada gör kısmında gerçekten problem var. Google navigation
  /// kullan burada").
  Future<void> _openDayMap(DayPlan day) async {
    final messenger = ScaffoldMessenger.of(context);
    final s = LanguageScope.of(context);
    final dest = getDestinationForDate(_sortedDestinations, day.date);
    final cityData = cityDataForKey(dest?.city);
    final centerLat = cityData?.places.isNotEmpty == true
        ? cityData!.places.first.lat
        : (dest?.lat ?? 35.6762);
    final centerLng = cityData?.places.isNotEmpty == true
        ? cityData!.places.first.lng
        : (dest?.lng ?? 139.6503);
    final stops = resolveDayStops(
      day,
      cityKey: dest?.city,
      fallbackLat: centerLat,
      fallbackLng: centerLng,
    );
    if (stops.length >= 2) {
      final res = await openGoogleMapsRoute(
        points: [
          for (final st in stops)
            (lat: st.lat, lng: st.lng, label: st.item.title),
        ],
      );
      if (!mounted) return;
      if (!res.launched) {
        messenger.showSnackBar(SnackBar(content: Text(s.s('map.openFailed'))));
      } else if (res.truncated) {
        messenger.showSnackBar(
          SnackBar(content: Text(s.s('map.truncatedWaypoints'))),
        );
      }
      return;
    }
    if (stops.length == 1) {
      final st = stops.first;
      final ok = await openGoogleMapsPoint(
        lat: st.lat,
        lng: st.lng,
        label: st.item.title,
      );
      if (!mounted) return;
      if (!ok) {
        messenger.showSnackBar(SnackBar(content: Text(s.s('map.openFailed'))));
      }
      return;
    }
    // Duraksız gün — şehir merkezini aç.
    final ok = await openGoogleMapsPoint(
      lat: centerLat,
      lng: centerLng,
      label: dest?.city,
    );
    if (!mounted) return;
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(s.s('map.openFailed'))));
    }
  }

  /// Tüm günlerin rotasını sırayla optimize et. Her uygun gün için mevcut
  /// per-day bottom sheet'ini açar; kullanıcı Uygula ya da Kapat der. Sheet
  /// kapandıktan sonra bir sonraki güne geçer. İki'den az durağı olan günler
  /// sessizce atlanır.
  Future<void> _optimizeAllRoutes(List<DayPlan> days) async {
    final s = LanguageScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final eligible = days.where((d) => d.items.length >= 2).toList();
    if (eligible.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.s('routeOptimization.needTwoStops'))),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tüm rotayı optimize et'),
        content: Text(
          '${eligible.length} gün için rota optimizasyonu sırayla açılacak. '
          'Her günde tercih ettiğin profili seçip uygulayabilirsin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Başla'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    for (final day in eligible) {
      if (!mounted) return;
      final destination = getDestinationForDate(_sortedDestinations, day.date);
      await _openRouteOptimization(day, destination);
    }
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('${eligible.length} gün için tamamlandı.')),
    );
  }

  Future<void> _openRouteOptimization(
    DayPlan day,
    TripDestination? destination,
  ) async {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              s.p('routeOptimization.stopLocationMissing', {
                'name': item.title,
              }),
            ),
          ),
        );
        return;
      }
      item
        ..lat = coordinate.lat
        ..lng = coordinate.lng;
    }

    final date = DateTime.tryParse(day.date);
    if (date == null) return;
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
        availableStartTime: DateTime(date.year, date.month, date.day, 6),
        availableEndTime: DateTime(date.year, date.month, date.day, 23),
      ),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RouteOptimizationSheet(
        input: input,
        palette: ViewerPalette.of(context),
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

  /// İki günün destinasyonu farklıysa günler arasına yerleştirilen küçük
  /// "şehirler arası geçiş" ayracı. Kart yığınında ulaşım günü olduğunu
  /// belirsizce vurgular; ulaşım kartını değiştirmez.
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: p.textMuted.withValues(alpha: 0.35),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: p.accent.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🚄', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: p.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: p.textMuted.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
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

class _RouteOptimizationSheet extends ConsumerStatefulWidget {
  const _RouteOptimizationSheet({
    required this.input,
    required this.palette,
    required this.onPersist,
  });

  final DayOptimizationInput input;
  final ViewerPalette palette;
  final OptimizedPlanPersist onPersist;

  @override
  ConsumerState<_RouteOptimizationSheet> createState() =>
      _RouteOptimizationSheetState();
}

class _RouteOptimizationSheetState
    extends ConsumerState<_RouteOptimizationSheet> {
  RouteOptimizationProfile _profile = RouteOptimizationProfile.balanced;

  @override
  void initState() {
    super.initState();
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
              maximumWalkingMinutes:
                  widget.input.preferences.maximumWalkingMinutes,
              partySize: widget.input.preferences.partySize,
              hasLuggage: widget.input.preferences.hasLuggage,
            ),
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
              Text(
                s.s('routeOptimization.title'),
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
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
          const SizedBox(height: 16),
          Text(
            s.s('routeOptimization.changes'),
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
        const SizedBox(height: 20),
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
      ],
    );
  }
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
      padding: const EdgeInsets.all(12),
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
                                color:
                                    palette.accent.withValues(alpha: 0.35),
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
class _EditToolbar extends StatelessWidget {
  const _EditToolbar({required this.palette, required this.onOptimizeAll});

  final ViewerPalette palette;
  final VoidCallback onOptimizeAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border(
          bottom: BorderSide(
            color: palette.border.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
      ),
      child: SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _EditToolbarChip(
              palette: palette,
              icon: Icons.route_outlined,
              label: 'Tüm rotayı yeniden optimize et',
              tint: palette.sakura,
              onTap: onOptimizeAll,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditToolbarChip extends StatelessWidget {
  const _EditToolbarChip({
    required this.palette,
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  final ViewerPalette palette;
  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tint.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: tint),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: tint,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
            Icon(Icons.delete_outline_rounded,
                color: Colors.white, size: 22),
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
    required this.expanded,
    required this.onToggleExpand,
    required this.editMode,
    required this.allDays,
    required this.onOpenItem,
    required this.onOpenMap,
    required this.onOptimizeRoute,
    required this.onDropItem,
    required this.onDeleteItem,
    required this.onEditItemTime,
    required this.onAddItem,
    required this.onEditDay,
    required this.onMoveDay,
    required this.onDragUpdate,
    required this.dragActive,
  });
  final DayPlan day;
  final ViewerPalette palette;
  final TripDestination? dest;
  final Color bubbleColor;
  final DayForecast? forecast;
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
  final VoidCallback onOptimizeRoute;

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
    final totalWarnings = warningsMap.values
        .fold<int>(0, (acc, list) => acc + list.length);

    final card = Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: widget.isActive ? p.cardHover : p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: widget.isActive ? p.sakura.withValues(alpha: 0.45) : p.border,
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
            onTap: widget.onToggleExpand,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DayBadge(
                      day: day, palette: p, bubbleColor: widget.bubbleColor),
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
                                _formatDayTitle(
                                  day.date,
                                  day.dayNumber,
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
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
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
                                                DismissDirection.endToStart: 0.4,
                                              },
                                              background: const SizedBox
                                                  .shrink(),
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
                            for (var i = 0; i < day.items.length; i++)
                              _TimelineRow(
                                item: day.items[i],
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
                          if (day.items.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                TextButton.icon(
                                  onPressed: () => widget.onOpenMap(day),
                                  icon: Icon(Icons.map_outlined,
                                      size: 18, color: p.accent),
                                  label: Text(
                                    LanguageScope.of(context)
                                        .s('viewer.day.viewOnMap'),
                                    style: TextStyle(
                                      color: p.accent,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  key: ValueKey(
                                      'optimize-route-${day.dayNumber}'),
                                  onPressed: widget.onOptimizeRoute,
                                  icon: Icon(Icons.route_outlined,
                                      size: 18, color: p.sakura),
                                  label: Text(
                                    LanguageScope.of(context)
                                        .s('routeOptimization.action'),
                                    style: TextStyle(
                                      color: p.sakura,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
            borderRadius: BorderRadius.circular(20),
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
    // Rozet: büyük = ayın günü (ör. 25), küçük = kısa ay adı (ör. Ara).
    final dayOfMonth = d != null ? '${d.day}' : '${day.dayNumber}';
    final monthFull = d != null ? L10n.monthsFor(lang)[d.month] : '';
    final monthShort =
        monthFull.length > 3 ? monthFull.substring(0, 3) : monthFull;
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
            dayOfMonth,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              height: 1,
            ),
          ),
          if (monthShort.isNotEmpty)
            Text(
              monthShort,
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
    required this.onEditTime,
    required this.onOpen,
    this.warnings = const [],
  });

  final DayPlan day;
  final int index;
  final ViewerPalette palette;
  final TripDestination? dest;
  final List<DayPlan> allDays;
  final VoidCallback onEditTime;
  final VoidCallback onOpen;

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
                    : Semantics(
                        label: item.lockReason ??
                            s.s('viewer.edit.fixedReason'),
                        child: Icon(
                          Icons.lock_rounded,
                          size: 15,
                          color: p.textMuted,
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
            const SizedBox(width: 8),
            _ItemThumb(item: item, dest: dest, palette: p, size: 40),
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
            // Sabit satırlarda küçük kilit rozeti tutulmuş.
            if (item.isFixed)
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

/// Timeline durağı için küçük yuvarlatılmış görsel. `PlaceImageResolver` ile
/// çözülür (küratörlü → Wikipedia). Görsel yoksa tür ikonuna düşer.
class _ItemThumb extends StatefulWidget {
  const _ItemThumb({
    required this.item,
    required this.dest,
    required this.palette,
    this.size = 40,
  });
  final TimelineItem item;
  final TripDestination? dest;
  final ViewerPalette palette;
  final double size;

  @override
  State<_ItemThumb> createState() => _ItemThumbState();
}

class _ItemThumbState extends State<_ItemThumb> {
  String? _url;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _ItemThumb old) {
    super.didUpdateWidget(old);
    if (old.item.title != widget.item.title) {
      _done = false;
      _url = null;
      _resolve();
    }
  }

  bool get _eligible {
    final k = widget.item.kind;
    // Şehirler-arası geçiş bandının kendi tasarımı var; thumb gösterme.
    if (k == TimelineItemKind.transport && widget.item.title.contains('→')) {
      return false;
    }
    return true;
  }

  Future<void> _resolve() async {
    if (!_eligible) {
      setState(() => _done = true);
      return;
    }
    final urls = await PlaceImageResolver.instance
        .resolve(widget.item.title, city: widget.dest?.city);
    if (!mounted) return;
    setState(() {
      _url = urls.isNotEmpty ? urls.first : null;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final size = widget.size;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: p.elevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      alignment: Alignment.center,
      child: Icon(_kindIcon(widget.item.kind), size: 18, color: p.textMuted),
    );
    if (!_done || _url == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        _url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        loadingBuilder: (_, child, prog) => prog == null ? child : fallback,
        errorBuilder: (_, __, ___) => fallback,
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
    this.lat,
    this.lng,
  });
  final String title;
  final String time;
  final TimelineItemKind kind;
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
  static const _firstSlot = 8 * 60;
  static const _lastSlot = 22 * 60;
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

  void _submit() {
    final q = _controller.text.trim();
    if (_selected == null && q.isEmpty) return;
    final result = _selected != null
        ? _AddPlaceResult(
            title: _selected!.name,
            time: _time,
            kind: _kindForCategory(_selected!.category.en),
            lat: _selected!.lat,
            lng: _selected!.lng,
          )
        : _AddPlaceResult(
            title: q,
            time: _time,
            kind: TimelineItemKind.activity,
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
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: p.border),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
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
                onChanged: (_) => setState(() => _selected = null),
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
                          style: TextStyle(color: p.textMuted, fontSize: 13),
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
                              });
                            },
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
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
                      onPressed:
                          (_selected != null || q.isNotEmpty) ? _submit : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        q.isNotEmpty && _selected == null
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
  final List<PlanWarning> warnings;

  static const Color _amber = Color(0xFFFF9F0A);

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final time = item.time ?? item.scheduledTime ?? '--:--';
    final hasWarning = warnings.isNotEmpty;
    final timeStyle = TextStyle(
      color: hasWarning
          ? _amber
          : (isPastItem ? p.textMuted : p.fuji),
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
                  _ItemThumb(item: item, dest: dest, palette: p),
                  const SizedBox(width: 10),
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
                        if (item.description != null &&
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
                      onTap: () => ref.read(appLangProvider.notifier).set(l),
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

// ---------------------------------------------------------------------------
// 9) Sandvich (drawer) — kullanıcı bilgisi + uçuş özet + otel özet + metrikler
//    + tüm aksiyon butonları + nav kısayolları + çıkış. Viewer minimalize
//    edildiğinde bu drawer, top bar'daki aksiyon şeridinin ve hero'nun yerini
//    aldı: asıl "iş" (günler) hemen görünsün diye.
// ---------------------------------------------------------------------------

/// İki adımlı hesap silme onay akışı — Apple 5.1.1(v).
///
/// 1. AlertDialog: "Hesabı silmek istiyor musun?" + net destructive uyarı
/// 2. Onay verilirse `authRepository.deleteAccount()` çağrılır (RPC + signOut)
/// 3. Sonuç SnackBar ile bildirilir; router auth ekranına yönlendirir
Future<void> _confirmAndDeleteAccount(
  BuildContext context,
  WidgetRef ref,
) async {
  final s = LanguageScope.of(context);
  final palette = ViewerPalette.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: palette.card,
      title: Text(
        s.s('account.delete.title'),
        style:
            TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700),
      ),
      content: Text(
        s.s('account.delete.body'),
        style: TextStyle(color: palette.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(s.s('account.delete.cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(foregroundColor: palette.sunset),
          child: Text(s.s('account.delete.confirm')),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(authRepositoryProvider).deleteAccount();
    messenger.showSnackBar(
      SnackBar(content: Text(s.s('account.delete.success'))),
    );
  } catch (_) {
    messenger.showSnackBar(
      SnackBar(content: Text(s.s('account.delete.error'))),
    );
  }
}

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

    // KEŞFET — geziyi keşfetmek için 4 çekirdek araç.
    final discoverActions = <_DrawerActionSpec>[
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
    ];
    // ARAÇLAR — hazırlık + referans (valiz, hazırlık, sözlük, bilmen gerekenler).
    final toolActions = <_DrawerActionSpec>[
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
    ];

    return Drawer(
      width: (MediaQuery.sizeOf(context).width * 0.9)
          .clamp(320.0, 400.0)
          .toDouble(),
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DrawerHero(palette: p),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DrawerFlightsMini(trip: trip, palette: p),
                  const SizedBox(height: 10),
                  _DrawerHotelsMini(trip: trip, palette: p),
                  const SizedBox(height: 14),
                  _DrawerMetricsMini(
                      trip: trip, palette: p, dayCount: dayCount),
                  const SizedBox(height: 18),
                  _DrawerSectionLabel(
                    label: s.s('drawer.section.discover'),
                    palette: p,
                  ),
                  const SizedBox(height: 10),
                  _DrawerActionGrid(actions: discoverActions, palette: p),
                  const SizedBox(height: 18),
                  _DrawerSectionLabel(
                    label: s.s('drawer.section.tools'),
                    palette: p,
                  ),
                  const SizedBox(height: 10),
                  _DrawerActionList(actions: toolActions, palette: p),
                  const SizedBox(height: 18),
                  _DrawerProfileCard(
                    palette: p,
                    avatarInitial: avatarInitial,
                    title: isGuest ? role : email,
                    subtitle: isGuest ? null : role,
                  ),
                  const SizedBox(height: 8),
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
                    icon: Icons.palette_outlined,
                    label: s.s('viewer.tt.theme'),
                    onTap: () {
                      Navigator.of(context).pop();
                      onOpenThemePicker();
                    },
                  ),
                  _DrawerNavTile(
                    palette: p,
                    icon: Icons.travel_explore,
                    label: s.s('map.openInGoogleMaps'),
                    onTap: () {
                      Navigator.of(context).pop();
                      onOpenTripInGoogleMaps();
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Divider(color: p.border, height: 1),
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
                  // Apple App Store Guideline 5.1.1(v): kayıt varsa silme
                  // akışı da olmak zorunda.
                  _DrawerNavTile(
                    palette: p,
                    icon: Icons.delete_forever_rounded,
                    label: s.s('drawer.deleteAccount'),
                    destructive: true,
                    onTap: () async {
                      Navigator.of(context).pop();
                      await _confirmAndDeleteAccount(context, ref);
                    },
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

class _DrawerProfileCard extends StatelessWidget {
  const _DrawerProfileCard({
    required this.palette,
    required this.avatarInitial,
    required this.title,
    this.subtitle,
  });

  final ViewerPalette palette;
  final String avatarInitial;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.elevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
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
                fontSize: 17,
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
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
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
          Icon(Icons.chevron_right_rounded, color: p.textMuted),
        ],
      ),
    );
  }
}

/// Drawer'ın 32x32 mor rozeti + 旅 karakteri.
class _DrawerBrandMark extends StatelessWidget {
  const _DrawerBrandMark({required this.palette, this.size = 32});
  final ViewerPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [palette.accent, palette.fuji],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child: Text(
        '旅',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.56,
          height: 1.0,
        ),
      ),
    );
  }
}

/// Drawer'ın üst kısmındaki "hero" bandı — dawn gradient arka plan üzerinde
/// 旅 rozet + "Rotori" başlığı, sağ tarafta stilize edilmiş Fuji dağı silüeti
/// ve batan kırmızı güneş. Fuji siluetini yerel çizimle üretiyoruz (harici
/// asset yok) — dosya boyutu artmasın ve tema paletiyle uyum sürsün diye.
class _DrawerHero extends StatelessWidget {
  const _DrawerHero({required this.palette});
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 160,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Dawn / dusk gradient — deep purple → coral → soft peach.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF2A1F4A),
                    p.fuji.withValues(alpha: 0.85),
                    const Color(0xFFEE7F6A),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
            // Fuji silueti + kırmızı güneş (sağ tarafta).
            const Positioned.fill(
              child: CustomPaint(painter: _FujiPainter()),
            ),
            // Alt kenar — drawer body'sine yumuşak geçiş.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 24,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      p.card.withValues(alpha: 0.0),
                      p.card.withValues(alpha: 0.9),
                    ],
                  ),
                ),
              ),
            ),
            // Rozet + marka + kapatma butonu.
            Positioned(
              left: 20,
              right: 12,
              top: 20,
              child: Row(
                children: [
                  _DrawerBrandMark(palette: p, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      LanguageScope.of(context).s('drawer.brand'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stilize Fuji + batan güneş — hero arka planında dekoratif katman.
class _FujiPainter extends CustomPainter {
  const _FujiPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Kırmızı batan güneş — sağ üst.
    final sunCenter = Offset(w * 0.75, h * 0.28);
    final sunRadius = h * 0.13;
    canvas.drawCircle(
      sunCenter,
      sunRadius + 4,
      Paint()..color = const Color(0x33FFB4A2),
    );
    canvas.drawCircle(
      sunCenter,
      sunRadius,
      Paint()..color = const Color(0xFFE45B4B),
    );

    // Uzak dağ — açık siluet.
    final farMountain = Path()
      ..moveTo(0, h)
      ..lineTo(w * 0.15, h * 0.72)
      ..lineTo(w * 0.35, h * 0.85)
      ..lineTo(w * 0.55, h * 0.65)
      ..lineTo(w * 0.7, h * 0.8)
      ..lineTo(w, h * 0.7)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(
      farMountain,
      Paint()..color = const Color(0x552A1F4A),
    );

    // Fuji ana silüeti — sağa yakın, klasik konik.
    final fujiPeak = Offset(w * 0.62, h * 0.42);
    final fuji = Path()
      ..moveTo(w * 0.28, h)
      ..lineTo(w * 0.5, h * 0.62)
      ..lineTo(fujiPeak.dx - 12, h * 0.52)
      ..lineTo(fujiPeak.dx, fujiPeak.dy)
      ..lineTo(fujiPeak.dx + 12, h * 0.52)
      ..lineTo(w * 0.78, h * 0.62)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(
      fuji,
      Paint()..color = const Color(0xCC1B1233),
    );

    // Karla kaplı zirve — üstte küçük beyaz cap.
    final cap = Path()
      ..moveTo(fujiPeak.dx - 12, h * 0.52)
      ..quadraticBezierTo(
        fujiPeak.dx - 6,
        h * 0.58,
        fujiPeak.dx - 8,
        h * 0.6,
      )
      ..lineTo(fujiPeak.dx, h * 0.56)
      ..lineTo(fujiPeak.dx + 8, h * 0.6)
      ..quadraticBezierTo(
        fujiPeak.dx + 6,
        h * 0.58,
        fujiPeak.dx + 12,
        h * 0.52,
      )
      ..lineTo(fujiPeak.dx, fujiPeak.dy)
      ..close();
    canvas.drawPath(
      cap,
      Paint()..color = const Color(0xE6FFFFFF),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Küçük harfli bölüm başlığı — "KEŞFET", "ARAÇLAR" gibi drawer içi ayraçlar.
class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel({required this.label, required this.palette});
  final String label;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: TextStyle(
          color: palette.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
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
class _DrawerFlightsMini extends StatefulWidget {
  const _DrawerFlightsMini({required this.trip, required this.palette});
  final Trip trip;
  final ViewerPalette palette;

  @override
  State<_DrawerFlightsMini> createState() => _DrawerFlightsMiniState();
}

class _DrawerFlightsMiniState extends State<_DrawerFlightsMini> {
  bool _expanded = false;

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

  static String _dateShort(String iso, AppLang lang) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    const trMonths = [
      '',
      'Oca',
      'Şub',
      'Mar',
      'Nis',
      'May',
      'Haz',
      'Tem',
      'Ağu',
      'Eyl',
      'Eki',
      'Kas',
      'Ara',
    ];
    const enMonths = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final m = lang == AppLang.en ? enMonths[d.month] : trMonths[d.month];
    return '${d.day} $m ${d.year}';
  }

  /// Aynı gün olmayan varış — "+1" göstermek için.
  int _dayOffset(String depIso, String arrIso) {
    final dep = DateTime.tryParse(depIso);
    final arr = DateTime.tryParse(arrIso);
    if (dep == null || arr == null) return 0;
    final depDate = DateTime(dep.year, dep.month, dep.day);
    final arrDate = DateTime(arr.year, arr.month, arr.day);
    return arrDate.difference(depDate).inDays;
  }

  Widget _legCard({
    required BuildContext context,
    required String tripLabel,
    required List<FlightLeg> legs,
  }) {
    final p = widget.palette;
    final s = LanguageScope.of(context);
    if (legs.isEmpty) return const SizedBox.shrink();
    final from = legs.first;
    final to = legs.last;
    final offset = _dayOffset(from.dateTime, to.dateTime);
    final hopsCount = legs.length - 1; // aktarma sayısı
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  tripLabel,
                  style: TextStyle(
                    color: p.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '·',
                  style: TextStyle(color: p.textMuted, fontSize: 11),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _dateShort(from.dateTime, s.lang),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _time(from.dateTime),
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        from.city.isNotEmpty
                            ? '${from.city} (${_iata(from)})'
                            : _iata(from),
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.flight, size: 18, color: p.sakura),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _time(to.dateTime),
                              style: TextStyle(
                                color: p.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                            if (offset > 0)
                              Padding(
                                padding: const EdgeInsets.only(left: 2, top: 2),
                                child: Text(
                                  '+$offset',
                                  style: TextStyle(
                                    color: p.sakura,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        to.city.isNotEmpty
                            ? '${to.city} (${_iata(to)})'
                            : _iata(to),
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (hopsCount > 0) ...[
              const SizedBox(height: 6),
              Text(
                s.p(
                  hopsCount == 1
                      ? 'drawer.flights.stops'
                      : 'drawer.flights.stops.plural',
                  {'n': '$hopsCount'},
                ),
                style: TextStyle(
                  color: p.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outbound = widget.trip.flights.outbound;
    final ret = widget.trip.flights.returnLegs;
    final tripsCount = (outbound.isNotEmpty ? 1 : 0) + (ret.isNotEmpty ? 1 : 0);
    final p = widget.palette;
    final s = LanguageScope.of(context);
    return _DrawerCollapsible(
      palette: p,
      expanded: _expanded,
      onToggle: () => setState(() => _expanded = !_expanded),
      icon: Icons.flight_takeoff,
      iconColor: p.sakura,
      title: s.s('viewer.flights').replaceAll('✈️ ', ''),
      badge: tripsCount == 0
          ? s.s('drawer.flights.empty')
          : s.p('drawer.flights.count', {'n': '$tripsCount'}),
      child: tripsCount == 0
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (outbound.isNotEmpty)
                    _legCard(
                      context: context,
                      tripLabel: 'Gezi 1',
                      legs: outbound,
                    ),
                  if (ret.isNotEmpty)
                    _legCard(
                      context: context,
                      tripLabel: outbound.isNotEmpty ? 'Gezi 2' : 'Gezi 1',
                      legs: ret,
                    ),
                ],
              ),
            ),
    );
  }
}

/// Drawer içi konaklama bölümü — default kapalı, "N otel" badge; açıldığında
/// her otel kartı (ad + şehir + check-in/out tarih aralığı).
class _DrawerHotelsMini extends StatefulWidget {
  const _DrawerHotelsMini({required this.trip, required this.palette});
  final Trip trip;
  final ViewerPalette palette;

  @override
  State<_DrawerHotelsMini> createState() => _DrawerHotelsMiniState();
}

class _DrawerHotelsMiniState extends State<_DrawerHotelsMini> {
  bool _expanded = false;

  static String _dateShort(String iso, AppLang lang) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    const trMonths = [
      '',
      'Oca',
      'Şub',
      'Mar',
      'Nis',
      'May',
      'Haz',
      'Tem',
      'Ağu',
      'Eyl',
      'Eki',
      'Kas',
      'Ara',
    ];
    const enMonths = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final m = lang == AppLang.en ? enMonths[d.month] : trMonths[d.month];
    return '${d.day} $m';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final s = LanguageScope.of(context);
    final hotels = widget.trip.hotels;
    return _DrawerCollapsible(
      palette: p,
      expanded: _expanded,
      onToggle: () => setState(() => _expanded = !_expanded),
      icon: Icons.hotel_outlined,
      iconColor: p.gold,
      title: s.s('viewer.hotels').replaceAll('🏨 ', ''),
      badge: hotels.isEmpty
          ? s.s('drawer.hotels.empty')
          : s.p('drawer.hotels.count', {'n': '${hotels.length}'}),
      child: hotels.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final h in hotels)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: p.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: p.border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: p.gold.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.business_center_outlined,
                                size: 18,
                                color: p.gold,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    h.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: p.textPrimary,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    h.city,
                                    style: TextStyle(
                                      color: p.textSecondary,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today_outlined,
                                        size: 11,
                                        color: p.textMuted,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${_dateShort(h.checkIn, s.lang)} — ${_dateShort(h.checkOut, s.lang)}',
                                        style: TextStyle(
                                          color: p.textMuted,
                                          fontSize: 11,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures()
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Uçuşlar/Konaklama gibi drawer içi açılabilir bölümler için ortak kabuk.
/// Başlıkta: ikon + başlık + badge (sağda) + döner chevron. AnimatedSize
/// ile smooth aç/kapa.
class _DrawerCollapsible extends StatelessWidget {
  const _DrawerCollapsible({
    required this.palette,
    required this.expanded,
    required this.onToggle,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.badge,
    required this.child,
  });

  final ViewerPalette palette;
  final bool expanded;
  final VoidCallback onToggle;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String badge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      decoration: BoxDecoration(
        color: p.elevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, size: 16, color: iconColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: iconColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.expand_more,
                      size: 20,
                      color: p.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            clipBehavior: Clip.hardEdge,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: child,
                  )
                : const SizedBox(width: double.infinity),
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

/// Drawer içi keşif grid'i — referanstaki gibi yuvarlak ikon rozeti ve altında
/// tek satırlık etiket.
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
                height: 76,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    Navigator.of(context).pop();
                    a.onTap();
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: p.accent.withValues(alpha: 0.12),
                          border: Border.all(
                            color: p.accent.withValues(alpha: 0.18),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(a.icon, size: 23, color: p.accent),
                      ),
                      const SizedBox(height: 6),
                      Text(
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
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Araçlar bölümü — tek kart içinde dört dokunulabilir satır.
class _DrawerActionList extends StatelessWidget {
  const _DrawerActionList({required this.actions, required this.palette});

  final List<_DrawerActionSpec> actions;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      decoration: BoxDecoration(
        color: p.elevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  actions[index].onTap();
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(actions[index].icon, size: 20, color: p.fuji),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          actions[index].label,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: p.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (index < actions.length - 1)
              Divider(
                height: 1,
                indent: 48,
                color: p.border.withValues(alpha: 0.75),
              ),
          ],
        ],
      ),
    );
  }
}
