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
import '../../domain/city_places.dart';
import '../../domain/day_schedule.dart' as sched;
import '../../domain/destination_profiles.dart';
import '../../domain/place_coords.dart';
import '../../domain/place_image_resolver.dart';
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

  /// Akordiyon: aynı anda YALNIZCA bir gün açık. Bir güne tıklanınca o açılır,
  /// diğerleri kapanır. null = henüz belirlenmedi (ilk build'de aktif güne
  /// ayarlanır). -1 = hepsi kapalı (açık günü tekrar kapatınca).
  int? _expandedDayIndex;

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
    // İlk build'de akordiyon varsayılanı: aktif gün açık.
    _expandedDayIndex ??= activeIndex;

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
                        expanded: _editMode || _expandedDayIndex == i,
                        onToggleExpand: () => setState(() {
                          _expandedDayIndex =
                              _expandedDayIndex == i ? -1 : i;
                        }),
                        editMode: _editMode,
                        allDays: days,
                        onOpenItem: _openItem,
                        onOpenMap: _openDayMap,
                        onMoveWithinDay: _moveWithinDay,
                        onMoveItemToDay: _moveItemToDay,
                        onDeleteItem: _deleteItem,
                        onEditItemTime: _editItemTime,
                        onAddItem: _addItemToDay,
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

  void _persistAndRefresh() {
    ref.read(plansRepositoryProvider)?.save(widget.trip);
    if (mounted) setState(() {});
    HomeWidgetHook.pushFromTrip(widget.trip);
  }

  /// Aynı gün içinde item sırasını değiştirir (yukarı/aşağı ya da sürükleme).
  /// Yeni sıraya göre saatler makul aralıklarla yeniden yazılır.
  void _moveWithinDay(DayPlan day, int oldIdx, int newIdx) {
    if (newIdx < 0 || newIdx >= day.items.length || oldIdx == newIdx) return;
    final item = day.items.removeAt(oldIdx);
    day.items.insert(newIdx, item);
    sched.redistributeDayTimes(day.items);
    _persistAndRefresh();
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
    final hasTicketRecord = widget.trip.tickets.any((t) => t.label == it.title);
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
        item: it,
        currentDay: day,
        allDays: widget.trip.days,
      ),
    );
    if (result == null) return;

    final targetDay = result.targetDay;
    final newMin = result.timeMinutes;
    if (identical(targetDay, day)) {
      sched.applyManualTimeEdit(day.items, index, newMin);
    } else {
      // Gün değişti — kaynaktan çıkar, hedef günde uygun konuma yerleştir.
      final removed = day.items.removeAt(index);
      final moved = removed.copyWith(movedFromDay: day.dayNumber);
      _setItemTimeMinutes(moved, newMin);
      sched.insertItemSorted(targetDay.items, moved);
    }
    _persistAndRefresh();
  }

  /// TimelineItem.time + scheduledTime alanlarına HH:MM biçiminde saat basar.
  void _setItemTimeMinutes(TimelineItem item, int mins) {
    final hh = (mins ~/ 60).toString().padLeft(2, '0');
    final mm = (mins % 60).toString().padLeft(2, '0');
    item.time = '$hh:$mm';
    item.scheduledTime = '$hh:$mm';
  }

  /// Bir güne yeni durak ekler — şehir bazlı autocomplete + saat girişli sheet.
  Future<void> _addItemToDay(DayPlan day, TripDestination? dest) async {
    // Varsayılan saat: son durağın saati + 90 dk, yoksa 09:00.
    int defaultMin = 9 * 60;
    if (day.items.isNotEmpty) {
      final last = _timeToMinutes(
          day.items.last.time ?? day.items.last.scheduledTime);
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
    sched.insertItemSorted(day.items, item);
    _persistAndRefresh();
    if (!mounted) return;
    final s = LanguageScope.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.p('viewer.edit.addedSnack', {'title': item.title}))),
    );
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
        duration: const Duration(seconds: 5),
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
    final toCity =
        toDest.city.isNotEmpty ? toDest.city : toDest.countryName;
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
    required this.expanded,
    required this.onToggleExpand,
    required this.editMode,
    required this.allDays,
    required this.onOpenItem,
    required this.onOpenMap,
    required this.onMoveWithinDay,
    required this.onMoveItemToDay,
    required this.onDeleteItem,
    required this.onEditItemTime,
    required this.onAddItem,
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

  /// Aynı gün içinde item sırasını değiştir (yukarı/aşağı butonu için).
  final void Function(DayPlan day, int oldIdx, int newIdx) onMoveWithinDay;

  /// Item'ı hedef güne taşı.
  final void Function(DayPlan source, int itemIdx, DayPlan target)
      onMoveItemToDay;

  /// Item'ı plandan kaldır (SnackBar ile undo verilir).
  final void Function(DayPlan day, int itemIdx) onDeleteItem;

  /// Bir durağın saatini düzenle (time picker) → gün yeniden saatlenir.
  final void Function(DayPlan day, int itemIdx) onEditItemTime;

  /// Bu güne yeni durak ekle (autocomplete + saat sheet).
  final void Function(DayPlan day, TripDestination? dest) onAddItem;

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
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
    // Akordiyon: parent tek-açık mantığını yönetir. Düzenleme modunda tüm
    // günler zorla açık (kullanıcı kapalı gündeki item'ı düzenleyemez).
    final expanded = widget.editMode ? true : widget.expanded;
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
                : widget.onToggleExpand,
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
                  if (widget.editMode) ...[
                    // Düzenleme: sürükle-bırak sıralama + sol ok butonları +
                    // saate dokunarak düzenleme. Boşsa doğrudan ekleme çubuğu.
                    if (day.items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          LanguageScope.of(context).s('viewer.day.noItems'),
                          style: TextStyle(color: p.textMuted),
                        ),
                      )
                    else
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: day.items.length,
                        // Sürüklenirken temiz bir "kaldırma" efekti: hafif
                        // büyüme + yumuşak gölge. Varsayılan Material yukarı
                        // sıçramasını ve gri kartı gizler.
                        proxyDecorator: (child, index, anim) {
                          return AnimatedBuilder(
                            animation: anim,
                            builder: (context, _) {
                              final t = Curves.easeInOut.transform(anim.value);
                              final scale = 1.0 + 0.03 * t;
                              return Transform.scale(
                                scale: scale,
                                child: Material(
                                  color: Colors.transparent,
                                  elevation: 0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.22 * t),
                                          blurRadius: 18 * t,
                                          offset: Offset(0, 6 * t),
                                        ),
                                      ],
                                    ),
                                    child: child,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                        onReorder: (oldIndex, newIndex) {
                          if (newIndex > oldIndex) newIndex -= 1;
                          widget.onMoveWithinDay(day, oldIndex, newIndex);
                        },
                        itemBuilder: (ctx, i) => _EditableTimelineRow(
                          key: ValueKey(day.items[i].id),
                          day: day,
                          index: i,
                          palette: p,
                          dest: widget.dest,
                          allDays: widget.allDays,
                          onMoveWithinDay: widget.onMoveWithinDay,
                          onMoveItemToDay: widget.onMoveItemToDay,
                          onDeleteItem: widget.onDeleteItem,
                          onEditTime: () => widget.onEditItemTime(day, i),
                          onOpen: () =>
                              widget.onOpenItem(day.items[i], widget.dest),
                        ),
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
                          LanguageScope.of(context).s('viewer.day.noItems'),
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
    super.key,
    required this.day,
    required this.index,
    required this.palette,
    required this.dest,
    required this.allDays,
    required this.onMoveWithinDay,
    required this.onMoveItemToDay,
    required this.onDeleteItem,
    required this.onEditTime,
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
  final VoidCallback onEditTime;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = LanguageScope.of(context);
    final item = day.items[index];
    final isFirst = index == 0;
    final isLast = index == day.items.length - 1;
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
            // Sol ray: yukarı ok · sürükle tutamacı · aşağı ok.
            SizedBox(
              width: 30,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MiniIconBtn(
                    icon: Icons.keyboard_arrow_up_rounded,
                    color: p.textPrimary,
                    enabled: !isFirst,
                    onTap: () => onMoveWithinDay(day, index, index - 1),
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Icon(Icons.drag_indicator,
                          size: 15, color: p.textMuted),
                    ),
                  ),
                  _MiniIconBtn(
                    icon: Icons.keyboard_arrow_down_rounded,
                    color: p.textPrimary,
                    enabled: !isLast,
                    onTap: () => onMoveWithinDay(day, index, index + 1),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 2),
            // Saat rozeti — dokununca time picker.
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onEditTime,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.accent.withValues(alpha: 0.35)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: TextStyle(
                        color: p.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Icon(Icons.edit, size: 10, color: p.accent),
                  ],
                ),
              ),
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
            // Taşı / kaldır menüsü.
            PopupMenuButton<String>(
              tooltip: '',
              icon: Icon(Icons.more_vert, color: p.textMuted, size: 20),
              onSelected: (value) {
                if (value == 'delete') {
                  onDeleteItem(day, index);
                } else if (value.startsWith('day:')) {
                  final targetIdx = int.parse(value.substring(4));
                  onMoveItemToDay(day, index, allDays[targetIdx]);
                }
              },
              itemBuilder: (ctx) => <PopupMenuEntry<String>>[
                if (allDays.length > 1) ...[
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
                  const PopupMenuDivider(),
                ],
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
        ),
      ),
    );
  }
}

/// Küçük, dokunması kolay ok butonu (edit modu sıralama okları).
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
    if (k == TimelineItemKind.transport &&
        widget.item.title.contains('→')) {
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
        loadingBuilder: (_, child, prog) =>
            prog == null ? child : fallback,
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
  const _EditItemResult({required this.targetDay, required this.timeMinutes});
  final DayPlan targetDay;
  final int timeMinutes;
}

/// Aktivitenin gün + saatini birlikte düzenleyen bottom-sheet. Kullanıcı gün
/// değiştirmezse saat aynı gün içinde uygulanır; gün değiştirdiği anda saat
/// otomatik olarak hedef günün son aktivitesi + 90 dk'ya kayar — kullanıcı
/// isterse saati elle tekrar seçebilir.
class _EditItemDayTimeSheet extends StatefulWidget {
  const _EditItemDayTimeSheet({
    required this.palette,
    required this.item,
    required this.currentDay,
    required this.allDays,
  });

  final ViewerPalette palette;
  final TimelineItem item;
  final DayPlan currentDay;
  final List<DayPlan> allDays;

  @override
  State<_EditItemDayTimeSheet> createState() => _EditItemDayTimeSheetState();
}

class _EditItemDayTimeSheetState extends State<_EditItemDayTimeSheet> {
  late DayPlan _targetDay;
  late int _timeMinutes;
  bool _userTouchedTime = false;

  @override
  void initState() {
    super.initState();
    _targetDay = widget.currentDay;
    _timeMinutes = sched.timeToMinutes(
            widget.item.time ?? widget.item.scheduledTime) ??
        9 * 60;
  }

  /// Hedef günün son durağı + 90 dk (yoksa 09:00). Yeni güne otomatik saat
  /// önermek için — kullanıcı istediği zaman saati elle değiştirebilir.
  int _autoTimeFor(DayPlan day) {
    if (day.items.isEmpty) return 9 * 60;
    final last = sched
        .timeToMinutes(day.items.last.time ?? day.items.last.scheduledTime);
    if (last == null) return 9 * 60;
    return (last + 90).clamp(0, 24 * 60 - 1);
  }

  void _pickDay(DayPlan d) {
    if (identical(d, _targetDay)) return;
    setState(() {
      _targetDay = d;
      if (!_userTouchedTime) _timeMinutes = _autoTimeFor(d);
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: _timeMinutes ~/ 60, minute: _timeMinutes % 60),
      builder: (ctx, child) => Theme(
        data: widget.palette.toThemeData(),
        child: MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _timeMinutes = picked.hour * 60 + picked.minute;
      _userTouchedTime = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final p = widget.palette;
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final hh = (_timeMinutes ~/ 60).toString().padLeft(2, '0');
    final mm = (_timeMinutes % 60).toString().padLeft(2, '0');
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
                          label: s
                              .p('viewer.edit.dayShort', {'n': '${d.dayNumber}'}),
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
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickTime,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: p.accent.withValues(alpha: 0.4), width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.access_time, size: 18, color: p.accent),
                      const SizedBox(width: 10),
                      Text(
                        '$hh:$mm',
                        style: TextStyle(
                          color: p.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),
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
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(s.s('viewer.edit.cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        _EditItemResult(
                          targetDay: _targetDay,
                          timeMinutes: _timeMinutes,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
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
          color: active
              ? palette.accent
              : palette.accent.withValues(alpha: 0.10),
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
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                            style:
                                TextStyle(color: p.textSecondary, fontSize: 12),
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
        style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700),
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
      _DrawerActionSpec(
          icon: Icons.palette_outlined,
          label: s.s('viewer.tt.theme'),
          onTap: onOpenThemePicker),
      // Tüm rotayı Google Maps'te aç — günlerden ilk konumlu duraklarını
      // sırayla waypoint yapıp Google Maps `dir` URL'i ile açar.
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DrawerHero(palette: p),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DrawerMetricsMini(
                      trip: trip, palette: p, dayCount: dayCount),
                  const SizedBox(height: 14),
                  _DrawerFlightsMini(trip: trip, palette: p),
                  const SizedBox(height: 10),
                  _DrawerHotelsMini(trip: trip, palette: p),
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
                  _DrawerActionGrid(actions: toolActions, palette: p),
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
            // Apple App Store Guideline 5.1.1(v): kayıt varsa silme akışı da
            // olmak zorunda. İki adımlı onay + RPC delete_current_user çağırır.
            _DrawerNavTile(
              palette: p,
              icon: Icons.delete_forever_rounded,
              label: s.s('drawer.deleteAccount'),
              destructive: true,
              onTap: () async {
                Navigator.of(context).pop(); // drawer'ı kapat
                await _confirmAndDeleteAccount(context, ref);
              },
            ),
            const SizedBox(height: 8),
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
                    tooltip: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
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
      '', 'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
    ];
    const enMonths = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
                Text(
                  _dateShort(from.dateTime, s.lang),
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
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
                          fontFeatures:
                              const [FontFeature.tabularFigures()],
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
                      Row(
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
                              fontFeatures:
                                  const [FontFeature.tabularFigures()],
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
    final tripsCount =
        (outbound.isNotEmpty ? 1 : 0) + (ret.isNotEmpty ? 1 : 0);
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
      '', 'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
    ];
    const enMonths = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
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
                    padding:
                        const EdgeInsets.fromLTRB(14, 0, 14, 12),
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
