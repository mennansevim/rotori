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
import '../../data/language_store.dart';
import '../../data/plans_repository.dart';
import '../../data/reminders_store.dart';
import '../../domain/destination_profiles.dart';
import '../../domain/types.dart';
import '../shared/place_detail_sheet.dart';
import '../viewer/budget_screen.dart';
import '../viewer/checklist_screen.dart';
import '../viewer/compass_screen.dart';
import '../viewer/day_map_screen.dart';
import '../viewer/home_widget_hook.dart';
import '../viewer/japanese_phrases_screen.dart';
import '../viewer/must_know_screen.dart';
import '../viewer/reward_map_screen.dart';
import '../viewer/sakura_overlay.dart';
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

/// ISO datetime → "13 Mayıs 16:00" (tr) / "May 13 16:00" (en) — uçuş bacakları.
String _formatLegDateTime(String iso, AppLang lang) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final months = L10n.monthsFor(lang);
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return lang == AppLang.en
      ? '${months[d.month]} ${d.day} $hh:$mm'
      : '${d.day} ${months[d.month]} $hh:$mm';
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

int _hotelNights(HotelStay h) {
  final ci = DateTime.tryParse(h.checkIn);
  final co = DateTime.tryParse(h.checkOut);
  if (ci == null || co == null) return 0;
  final diff = co.difference(ci).inMilliseconds;
  return diff <= 0 ? 0 : (diff / 86400000).round();
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

    return Theme(
      data: palette.toThemeData(),
      child: ViewerPaletteScope(
        palette: palette,
        child: Scaffold(
          backgroundColor: palette.bg,
          body: planAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  LanguageScope.of(context)
                      .p('viewer.loadFailed', {'err': '$err'}),
                  style: TextStyle(color: palette.textPrimary),
                ),
              ),
            ),
            data: (trip) => _ViewerBody(trip: trip, planId: planId),
          ),
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

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _TopStatusBar(
            trip: trip,
            palette: palette,
            planId: widget.planId,
            onOpenThemePicker: _openThemePicker,
            onOpenMap: _openMap,
            onOpenCompass: _openCompass,
            onOpenBudget: _openBudget,
            onOpenChecklist: _openChecklist,
            onOpenWeather: _openWeather,
            onOpenPhrases: _openPhrases,
            onOpenMustKnow: _openMustKnow,
          ),
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                _Hero(trip: trip, palette: palette, dayCount: days.length),
                const SizedBox(height: 24),
                _StatsRow(trip: trip, palette: palette, dayCount: days.length),
                const SizedBox(height: 16),
                _FlightsCard(trip: trip, palette: palette),
                _HotelsCard(trip: trip, palette: palette),
                const SizedBox(height: 8),
                Text(
                  LanguageScope.of(context)
                      .p('viewer.days.title', {'n': '${days.length}'}),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
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
                      isPast: i < activeIndex,
                      isActive: i == activeIndex,
                      onOpenItem: _openItem,
                      onOpenMap: _openDayMap,
                    ),
              ],
            ),
          ),
        ],
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
    required this.onOpenThemePicker,
    required this.onOpenMap,
    required this.onOpenCompass,
    required this.onOpenBudget,
    required this.onOpenChecklist,
    required this.onOpenWeather,
    required this.onOpenPhrases,
    required this.onOpenMustKnow,
  });

  final Trip trip;
  final ViewerPalette palette;
  final String planId;
  final VoidCallback onOpenThemePicker;
  final VoidCallback onOpenMap;
  final VoidCallback onOpenCompass;
  final VoidCallback onOpenBudget;
  final VoidCallback onOpenChecklist;
  final VoidCallback onOpenWeather;
  final VoidCallback onOpenPhrases;
  final VoidCallback onOpenMustKnow;

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
            Row(
              children: [
                _BarIconButton(
                  icon: Icons.arrow_back,
                  color: onColor,
                  tooltip: s.s('viewer.tt.back'),
                  onTap: () => context.go('/plans'),
                ),
                // Faz etiketi — sığmadığında tek satırda ellipsis, DEĞİL harf harf sarma.
                Flexible(
                  child: Text(
                    _phaseLabel(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      color: onColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Sağa sabit iki birincil aksiyon: bildirim + düzenle.
                _BarBellButton(
                  color: onColor,
                  onTap: () => context.push('/reminders'),
                ),
                _BarIconButton(
                  icon: Icons.edit_outlined,
                  color: onColor,
                  tooltip: s.s('viewer.tt.edit'),
                  onTap: () => context.go('/plans/${widget.planId}/edit'),
                ),
              ],
            ),
            // Aksiyon şeridi — 6 ikon; ekran darsa yatay kaydırılabilir.
            const SizedBox(height: 2),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                children: [
                  _BarIconButton(
                    icon: Icons.map_outlined,
                    color: onColor,
                    tooltip: s.s('viewer.tt.map'),
                    onTap: widget.onOpenMap,
                  ),
                  _BarIconButton(
                    icon: Icons.explore_outlined,
                    color: onColor,
                    tooltip: s.s('viewer.tt.compass'),
                    onTap: widget.onOpenCompass,
                  ),
                  _BarIconButton(
                    icon: Icons.wb_sunny_outlined,
                    color: onColor,
                    tooltip: s.s('viewer.tt.weather'),
                    onTap: widget.onOpenWeather,
                  ),
                  _BarIconButton(
                    icon: Icons.account_balance_wallet_outlined,
                    color: onColor,
                    tooltip: s.s('viewer.tt.budget'),
                    onTap: widget.onOpenBudget,
                  ),
                  _BarIconButton(
                    icon: Icons.luggage_outlined,
                    color: onColor,
                    tooltip: s.s('viewer.tt.checklist'),
                    onTap: widget.onOpenChecklist,
                  ),
                  _BarIconButton(
                    icon: Icons.translate,
                    color: onColor,
                    tooltip: s.s('viewer.tt.phrases'),
                    onTap: widget.onOpenPhrases,
                  ),
                  _BarIconButton(
                    icon: Icons.info_outline,
                    color: onColor,
                    tooltip: s.s('viewer.tt.mustKnow'),
                    onTap: widget.onOpenMustKnow,
                  ),
                  _BarIconButton(
                    icon: Icons.palette_outlined,
                    color: onColor,
                    tooltip: s.s('viewer.tt.theme'),
                    onTap: widget.onOpenThemePicker,
                  ),
                ],
              ),
            ),
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

// ---------------------------------------------------------------------------
// 3) Hero.
// ---------------------------------------------------------------------------

class _Hero extends StatelessWidget {
  const _Hero({
    required this.trip,
    required this.palette,
    required this.dayCount,
  });
  final Trip trip;
  final ViewerPalette palette;
  final int dayCount;

  int get _totalNights =>
      trip.hotels.fold(0, (s, h) => s + _hotelNights(h));

  List<FlightLeg> get _routeLegs {
    if (trip.flights.legs.isNotEmpty) return trip.flights.legs;
    final ob = trip.flights.outbound
        .where((f) => f.city.trim().isNotEmpty || f.airport.trim().isNotEmpty)
        .toList();
    final ret = trip.flights.returnLegs
        .where((f) => f.city.trim().isNotEmpty || f.airport.trim().isNotEmpty)
        .toList();
    if (ob.isEmpty) return [];
    final chain = [...ob];
    if (ret.isNotEmpty) {
      final last = chain.last;
      final firstRet = ret.first;
      final samePlace = last.city == firstRet.city &&
          (last.airport == firstRet.airport ||
              firstRet.airport.isEmpty ||
              last.airport.isEmpty);
      chain.addAll(samePlace ? ret.skip(1) : ret);
    }
    return chain;
  }

  @override
  Widget build(BuildContext context) {
    final legs = _routeLegs;
    return Stack(
      children: [
        Positioned.fill(
          child: SakuraOverlay(sakura: palette.sakura),
        ),
        Column(
          children: [
            const SizedBox(height: 8),
            _Pill(
              text: LanguageScope.of(context).p('viewer.heroPill', {
                'days': '$dayCount',
                'nights': '$_totalNights',
              }),
              palette: palette,
            ),
            const SizedBox(height: 16),
            _GradientTitle(text: trip.title, palette: palette),
            if (trip.subtitle != null && trip.subtitle!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                trip.subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ],
            if (legs.isNotEmpty) ...[
              const SizedBox(height: 20),
              _RouteChainCard(legs: legs, palette: palette),
            ],
          ],
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.palette});
  final String text;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: palette.gradientNight),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _GradientTitle extends StatelessWidget {
  const _GradientTitle({required this.text, required this.palette});
  final String text;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: palette.gradientTitle,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 44,
          fontWeight: FontWeight.w800,
          height: 1.1,
          color: Colors.white, // ShaderMask ile boyanır
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}

class _RouteChainCard extends StatelessWidget {
  const _RouteChainCard({required this.legs, required this.palette});
  final List<FlightLeg> legs;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < legs.length; i++) {
      children.add(_LegChip(leg: legs[i], palette: palette));
      if (i < legs.length - 1) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '→',
            style: TextStyle(
              color: palette.sakura,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ));
      }
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        children: children,
      ),
    );
  }
}

class _LegChip extends StatelessWidget {
  const _LegChip({required this.leg, required this.palette});
  final FlightLeg leg;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final cityLabel = leg.airport.isNotEmpty
        ? '${leg.city} (${leg.airport})'
        : (leg.city.isNotEmpty ? leg.city : leg.airport);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          cityLabel,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        if (leg.dateTime.isNotEmpty)
          Text(
            _formatLegDateTime(leg.dateTime, LanguageScope.of(context).lang),
            style: TextStyle(color: palette.textMuted, fontSize: 11),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 5) İstatistik kartları.
// ---------------------------------------------------------------------------

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.trip,
    required this.palette,
    required this.dayCount,
  });
  final Trip trip;
  final ViewerPalette palette;
  final int dayCount;

  @override
  Widget build(BuildContext context) {
    final loc = LanguageScope.of(context);
    final totalNights = trip.hotels.fold(0, (s, h) => s + _hotelNights(h));
    final dests = [...trip.preferences.destinations]
      ..sort((a, b) => a.order.compareTo(b.order));

    final cards = <Widget>[];
    if (totalNights > 0) {
      cards.add(_StatCard(
        emoji: '🏨',
        value: '$totalNights',
        label: loc.s('viewer.stat.nights'),
        palette: palette,
      ));
    }
    for (final dest in dests.take(3)) {
      final nights = trip.hotels
          .where((h) => dest.city.isNotEmpty && h.city.contains(dest.city))
          .fold(0, (s, h) => s + _hotelNights(h));
      if (nights > 0) {
        cards.add(_StatCard(
          emoji: '📍',
          value: '$nights',
          label: loc.p('viewer.stat.cityNights', {'city': dest.city}),
          palette: palette,
        ));
      }
    }
    if (trip.tickets.isNotEmpty) {
      cards.add(_StatCard(
        emoji: '🎫',
        value: '${trip.tickets.length}',
        label: loc.s('viewer.stat.tickets'),
        palette: palette,
      ));
    }
    cards.add(_StatCard(
      emoji: '📅',
      value: '$dayCount',
      label: loc.s('viewer.stat.days'),
      palette: palette,
    ));

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: cards,
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.emoji,
    required this.value,
    required this.label,
    required this.palette,
  });
  final String emoji;
  final String value;
  final String label;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.of(context).size.width - 32 - 20) / 3;
    return Container(
      width: width.clamp(96, 160),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: palette.accent,
              fontWeight: FontWeight.w800,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6) Uçuş + otel kartları.
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.palette,
    required this.children,
  });
  final String title;
  final ViewerPalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _FlightsCard extends StatelessWidget {
  const _FlightsCard({required this.trip, required this.palette});
  final Trip trip;
  final ViewerPalette palette;

  /// Tamamen boş bir bacak — filtre dışı bırakılır (görüntülemede işe yaramaz).
  static bool _isBlankLeg(FlightLeg leg) =>
      leg.city.trim().isEmpty &&
      leg.airport.trim().isEmpty &&
      leg.dateTime.trim().isEmpty;

  @override
  Widget build(BuildContext context) {
    final outbound =
        trip.flights.outbound.where((l) => !_isBlankLeg(l)).toList();
    final returnLegs =
        trip.flights.returnLegs.where((l) => !_isBlankLeg(l)).toList();
    if (outbound.isEmpty && returnLegs.isEmpty) {
      return const SizedBox.shrink();
    }
    return _SectionCard(
      title: LanguageScope.of(context).s('viewer.flights'),
      palette: palette,
      children: [
        for (final leg in outbound)
          _FlightRow(leg: leg, arrow: '→', palette: palette),
        for (final leg in returnLegs)
          _FlightRow(leg: leg, arrow: '←', palette: palette),
      ],
    );
  }
}

class _FlightRow extends StatelessWidget {
  const _FlightRow({
    required this.leg,
    required this.arrow,
    required this.palette,
  });
  final FlightLeg leg;
  final String arrow;
  final ViewerPalette palette;

  /// buildRouteLegs bazen city/airport boş bacaklar üretebilir — satır asla
  /// tamamen boş görünmesin diye kademeli fallback:
  ///   - ikisi de boş → "—"
  ///   - sadece şehir boş → havaalanı kodu tek başına
  ///   - sadece havaalanı boş → şehir tek başına
  ///   - ikisi de dolu → "City (IATA)"
  String get _placeLabel {
    final city = leg.city.trim();
    final airport = leg.airport.trim();
    if (city.isEmpty && airport.isEmpty) return '—';
    if (city.isEmpty) return airport;
    if (airport.isEmpty) return city;
    return '$city ($airport)';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            '$arrow ',
            style: TextStyle(color: palette.sakura, fontSize: 15),
          ),
          Expanded(
            child: Text(
              _placeLabel,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            leg.dateTime.isNotEmpty
                ? _formatLegDateTime(
                    leg.dateTime, LanguageScope.of(context).lang)
                : '',
            style: TextStyle(color: palette.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _HotelsCard extends StatelessWidget {
  const _HotelsCard({required this.trip, required this.palette});
  final Trip trip;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    if (trip.hotels.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      title: LanguageScope.of(context).s('viewer.stays'),
      palette: palette,
      children: [
        for (final h in trip.hotels)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${h.name} · ${h.city}',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (h.address.isNotEmpty)
                  Text(
                    h.address,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                Text(
                  '${h.checkIn} → ${h.checkOut}',
                  style: TextStyle(color: palette.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
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
    required this.isPast,
    required this.isActive,
    required this.onOpenItem,
    required this.onOpenMap,
  });
  final DayPlan day;
  final ViewerPalette palette;
  final TripDestination? dest;
  final bool isPast;
  final bool isActive;
  final void Function(TimelineItem item, TripDestination? dest) onOpenItem;
  final void Function(DayPlan day) onOpenMap;

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
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DayBadge(day: day, palette: p),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
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
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: p.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
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
}

class _DayBadge extends StatelessWidget {
  const _DayBadge({required this.day, required this.palette});
  final DayPlan day;
  final ViewerPalette palette;

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
        gradient: LinearGradient(colors: palette.gradientNight),
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
