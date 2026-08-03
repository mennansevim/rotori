import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n.dart';
import '../../../data/language_store.dart';
import '../../../data/weather_service.dart';
import '../../../domain/booking_windows.dart';
import '../../../domain/city_palette.dart';
import '../../../domain/city_transfers.dart';
import '../../../domain/day_optimizer.dart';
import '../../../domain/destination_profiles.dart';
import '../../../domain/explore.dart';
import '../../../domain/fill_empty_days.dart';
import '../../../domain/itinerary_generator.dart';
import '../../../domain/japan_suggestions.dart';
import '../../../domain/place_guide.dart';
import '../../../domain/plan_schedule_engine.dart';
import '../../../domain/rules.dart';
import '../../../domain/trip_factory.dart';
import '../../../domain/types.dart';
import '../../shared/place_detail_sheet.dart';
import '../planner_theme.dart';
import '../widgets/booking_alert_dialog.dart';

/// AI plan servisi (POST /api/itinerary) mobil derlemede yapılandırılmadı.
/// Bu bayrak false iken doğrudan kural tabanlı üretici çalışır:
/// generateItineraryFromTrip(trip) + fillEmptyDays(trip). Ağ çağrısı yapılmaz.
/// TODO: Planner API deploy edilince (POST /api/itinerary) bunu aç ve
/// lib/features/planner/itinerary_lookup.dart:generateItinerary'yi kullan.
const bool _kApiEnabled = false;

/// YYYY-MM-DD biçimlendirici (gün dağılımı tarih blokları için).
String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// start..end (dahil) toplam gün sayısı. Geçersizse 0.
int _inclusiveDays(String start, String end) {
  final s = DateTime.tryParse(start);
  final e = DateTime.tryParse(end);
  if (s == null || e == null || e.isBefore(s)) return 0;
  return e.difference(s).inDays + 1;
}

/// apps/planner/src/components/steps/PlanStep.tsx + DayPlanCard.tsx portu.
/// Genişleyen gün kartları, saatli zaman çizelgesi, sürükle-sırala,
/// şehir geçişleri, keşif ve fallback-only "Gezi planı oluştur".
class PlanStep extends StatefulWidget {
  const PlanStep({super.key, required this.trip, required this.onChange});
  final Trip trip;
  final void Function(void Function(Trip)) onChange;

  @override
  State<PlanStep> createState() => _PlanStepState();
}

class _PlanStepState extends State<PlanStep> {
  static const _scheduleEngine = PlanScheduleEngine();
  late Set<int> _expanded;
  bool _planRevealed = false;
  bool _generating = false;

  /// Kullanıcı bir öneri kartında "Ulaşım değiştir" ile mod seçtiğinde,
  /// öneri kartı yeniden hesaplansa da seçim kalıcı kalsın diye
  /// fromDay|toDay anahtarı ile mode saklıyoruz.
  final Map<String, String> _transitionModeOverrides = {};

  Trip get trip => widget.trip;

  /// O an seçili uygulama dili — üretilen plan içeriği ve eklenen transferler bu
  /// dile göre metinlenir. (PlanStep düz StatefulWidget; provider'ı container
  /// üzerinden okuyoruz.)
  AppLang get _lang =>
      ProviderScope.containerOf(context, listen: false).read(appLangProvider);

  String _transitionKey(CityTransitionSuggestion s) =>
      '${s.fromDayNumber}|${s.toDayNumber}';

  /// Tarih (YYYY-MM-DD) → o günün hava tahmini. Open-Meteo'dan bir kez çekilir.
  Map<String, DayForecast> _forecast = const {};

  @override
  void initState() {
    super.initState();
    // İlk 2 gün açık başlar (React slice(0,2)).
    _expanded = trip.days.take(2).map((d) => d.dayNumber).toSet();
    // Hava tahminini arka planda çek (ağ hatası sessizce yutulur).
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadForecast());
    // Plan listesi yalnızca "Gezi planı oluştur" tetiklendikten sonra açılır.
    // (Trip zaten dolu gelse bile başta gizli kalır — kullanıcı önce toolbar'ı
    // görsün, sonra açıkça istesin.)
  }

  /// Destinasyon-id → paletteki renk (shared city_palette.dart).
  Color _cityColor(String? destId) => cityColorFor(_destinations, destId);

  /// Her destinasyon için Open-Meteo'dan 16 günlük tahmin çek. Bir günün
  /// forecast'i, o tarihte hangi şehre ait olduğuna göre eşleştirilir —
  /// böylece Kyoto gününe Tokyo hava tahmini düşmez.
  Future<void> _loadForecast() async {
    final dests = _destinations;
    if (dests.isEmpty) return;
    final result = <String, DayForecast>{};
    final seenLatLng = <String>{};
    for (final d in dests) {
      final lat = d.lat, lng = d.lng;
      if (lat == null || lng == null) continue;
      final key = '$lat,$lng';
      if (!seenLatLng.add(key)) continue;
      try {
        final list = await fetchForecast(lat, lng);
        for (final f in list) {
          final match = getDestinationForDate(dests, f.date);
          if (match?.id == d.id) result[f.date] = f;
        }
      } catch (_) {
        // Ağ hatası — sessizce geç, hava badge'i o gün için gösterilmez.
      }
    }
    if (!mounted || result.isEmpty) return;
    setState(() => _forecast = result);
  }

  List<TripDestination> get _destinations => [...trip.preferences.destinations]
    ..sort((a, b) => a.order.compareTo(b.order));

  /// Her destinasyon için görüntülenecek gün sayısı: dest.days doluysa onu,
  /// yoksa eşit dağıtım (total ~/ n, kalan son destinasyona) kullanır.
  List<int> _effectiveDayAlloc(List<TripDestination> dests, int total) {
    final n = dests.length;
    if (n == 0) return const [];
    final base = total > 0 ? total ~/ n : 1;
    final safeBase = base < 1 ? 1 : base;
    final rem = total > 0 ? total - safeBase * n : 0;
    return [
      for (var i = 0; i < n; i++)
        dests[i].days ?? (safeBase + (i == n - 1 ? rem : 0)),
    ];
  }

  /// Bir destinasyonun gün sayısını [newVal] yapar. İlk dokunuşta tüm
  /// destinasyonların days'i (görüntülenen değerlerle) somutlaşır ki _generate
  /// "tümü dolu" koşulunu değerlendirebilsin.
  void _setDayAlloc(int index, int newVal) {
    final dests = _destinations;
    final total = _inclusiveDays(
        trip.preferences.travelDates.start, trip.preferences.travelDates.end);
    final eff = _effectiveDayAlloc(dests, total);
    widget.onChange((t) {
      final sorted = [...t.preferences.destinations]
        ..sort((a, b) => a.order.compareTo(b.order));
      for (var i = 0; i < sorted.length && i < eff.length; i++) {
        sorted[i].days = i == index ? newVal : eff[i];
      }
    });
    setState(() {});
  }

  /// Tek destinasyon satırı: şehir adı (+ iniş/dönüş rozeti) + − N + stepper.
  Widget _dayAllocRow(List<TripDestination> dests, int i, List<int> eff,
      int left, LanguageScope s) {
    final d = dests[i];
    final count = dests.length;
    final val = i < eff.length ? eff[i] : 1;
    final cityName = d.city.isNotEmpty ? d.city : d.countryName;
    String? badge;
    if (i == 0) {
      badge = s.s('journey.badge.arrival');
    } else if (i == count - 1 && count > 1) {
      badge = s.s('journey.badge.return');
    }
    final canInc = left > 0;
    final canDec = val > 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(cityName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: PT.text)),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: PT.accentSoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(badge,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: PT.accent)),
                  ),
                ],
              ],
            ),
          ),
          _stepperBtn(
              Icons.remove, canDec ? () => _setDayAlloc(i, val - 1) : null),
          SizedBox(
            width: 40,
            child: Text('$val',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: PT.text)),
          ),
          _stepperBtn(
              Icons.add, canInc ? () => _setDayAlloc(i, val + 1) : null),
        ],
      ),
    );
  }

  Widget _stepperBtn(IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: PT.bgSubtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: PT.borderStrong),
        ),
        child:
            Icon(icon, size: 18, color: enabled ? PT.accent : PT.textTertiary),
      ),
    );
  }

  void _toggleExpanded(int dayNumber) {
    setState(() {
      if (!_expanded.remove(dayNumber)) _expanded.add(dayNumber);
    });
  }

  // --- Gün / öğe mutasyonları -------------------------------------------------

  bool _applyScheduleCommand(PlanEditCommand command) {
    var applied = false;
    PlanEditFailure? failure;
    widget.onChange((trip) {
      final result = _scheduleEngine.apply(trip, command);
      if (result.isSuccess) {
        trip.days = result.trip!.days;
        applied = true;
      } else {
        failure = result.failure;
      }
    });
    if (!applied && mounted) {
      final s = LanguageScope.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failure?.code == PlanEditFailureCode.lockedActivity
                ? s.s('viewer.edit.locked')
                : s.s('viewer.edit.invalidChange'),
          ),
        ),
      );
    }
    return applied;
  }

  void _updateDay(int dayNumber, void Function(DayPlan) mutate) {
    widget.onChange((t) {
      for (final d in t.days) {
        if (d.dayNumber == dayNumber) {
          mutate(d);
          break;
        }
      }
    });
  }

  void _removeItem(int dayNumber, String itemId) {
    _applyScheduleCommand(
      DeleteActivity(dayNumber: dayNumber, activityId: itemId),
    );
  }

  void _replaceItem(int dayNumber, TimelineItem updated) {
    final currentDay =
        trip.days.firstWhere((day) => day.dayNumber == dayNumber);
    final current =
        currentDay.items.firstWhere((item) => item.id == updated.id);
    final timeParts = (updated.time ?? updated.scheduledTime ?? '').split(':');
    if (timeParts.length == 2) {
      final hour = int.tryParse(timeParts[0]);
      final minute = int.tryParse(timeParts[1]);
      if (hour != null &&
          minute != null &&
          (updated.time != current.time ||
              updated.scheduledTime != current.scheduledTime ||
              updated.durationMin != current.durationMin)) {
        final changed = _applyScheduleCommand(UpdateActivitySchedule(
          dayNumber: dayNumber,
          activityId: updated.id,
          startMinutes: hour * 60 + minute,
          durationMinutes: updated.durationMin ?? current.durationMin ?? 60,
        ));
        if (!changed) return;
      }
    }
    widget.onChange((t) {
      for (final d in t.days) {
        if (d.dayNumber == dayNumber) {
          final idx = d.items.indexWhere((it) => it.id == updated.id);
          if (idx >= 0) {
            final scheduled = d.items[idx];
            scheduled.title = updated.title;
            scheduled.description = updated.description;
            scheduled.tips = updated.tips;
            scheduled.cost = updated.cost;
            scheduled.costCurrency = updated.costCurrency;
          }
          break;
        }
      }
    });
  }

  void _addItem(
    int dayNumber, {
    required String title,
    required String time,
    required TimelineItemKind kind,
  }) {
    _applyScheduleCommand(AddActivity(
      dayNumber: dayNumber,
      activity: TimelineItem(
            id: newItemId(dayNumber),
            title: title,
            kind: kind,
            time: time,
            scheduledTime: time,
        durationMin: 90,
      ),
          ));
  }

  /// "+ Aktivite" akışı: bottom-sheet ile yer adı + boş saat dilimi + tür seçtir.
  void _openAddItemSheet(int dayNumber) {
    final day = trip.days.firstWhere(
      (d) => d.dayNumber == dayNumber,
      orElse: () => DayPlan(dayNumber: dayNumber, date: '', theme: ''),
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PT.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(PT.radiusLg)),
      ),
      builder: (ctx) => _AddItemSheet(
        occupiedTimes: [
          for (final it in day.items)
            (it.time ?? it.scheduledTime ?? '').trim(),
        ]..removeWhere((s) => s.isEmpty),
        onSubmit: (name, time, kind) {
          _addItem(dayNumber, title: name, time: time, kind: kind);
        },
      ),
    );
  }

  /// ReorderableListView.onReorderItem sonrası: newIndex zaten kaldırma için
  /// düzeltilmiş gelir. Listeyi yeniden diz + resequenceTimes.
  void _reorder(int dayNumber, int oldIndex, int newIndex) {
    final day = trip.days.firstWhere((day) => day.dayNumber == dayNumber);
    if (oldIndex < 0 || oldIndex >= day.items.length) return;
    _applyScheduleCommand(MoveActivityWithinDay(
      dayNumber: dayNumber,
      activityId: day.items[oldIndex].id,
      targetIndex: newIndex,
    ));
  }

  /// rules.dart moveItemBetweenDays(days, itemId, fromDay, toDay) + resequence.
  void _moveItemToDay(int fromDay, String itemId, int toDay) {
    if (_applyScheduleCommand(MoveActivityToDay(
      sourceDayNumber: fromDay,
      activityId: itemId,
      targetDayNumber: toDay,
    ))) {
    setState(() => _expanded.add(toDay));
  }
  }

  void _optimizeDay(int dayNumber) {
    widget.onChange((t) {
      for (final d in t.days) {
        if (d.dayNumber == dayNumber) {
          d.items = optimizeDayItems(d.items);
          break;
        }
      }
    });
  }

  // --- Gezi planı oluştur (fallback-only) ------------------------------------

  Future<void> _generate() async {
    if (_generating) return;
    final s = LanguageScope.of(context);
    // Dili await'lerden önce oku — üretim sonrası context defunct olabilir.
    final lang = _lang;

    // Zaten dolu bir plan varsa yeniden üretmeden önce onay al —
    // aksi halde elle yapılan düzenlemeler sessizce silinir.
    final hasPlan = trip.days.any((d) => d.items.isNotEmpty);
    if (hasPlan) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.s('plan.regenConfirmTitle')),
          content: Text(s.s('plan.regenConfirmBody')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(s.s('plan.cancel'))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(s.s('plan.regenConfirm'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;

    setState(() => _generating = true);
    // Loading bar'ın görünmesi için bir kare bekle (üretim senkron ve hızlı).
    await Future<void>.delayed(const Duration(milliseconds: 400));

    widget.onChange((t) {
      // GÜN DAĞILIMI: Kullanıcı her şehrin gün sayısını (Gün dağılımı
      // stepper'ları) elle belirlediyse — yani TÜM dest.days dolu ve toplamları
      // toplam güne eşitse — ardışık tarih blokları ata. Aksi halde MEVCUT
      // coverage-guard davranışını koru: bir şehir hiç güne düşmüyorsa
      // distributeDates ile yeniden dağıt (testler açık tarih verir; korunur).
      {
        final start = t.preferences.travelDates.start;
        final end = t.preferences.travelDates.end;
        final total = _inclusiveDays(start, end);
        final destsSorted = [...t.preferences.destinations]
          ..sort((a, b) => a.order.compareTo(b.order));
        final allSet = destsSorted.isNotEmpty &&
            destsSorted.every((d) => (d.days ?? 0) > 0);
        final sumDays = destsSorted.fold<int>(0, (n, d) => n + (d.days ?? 0));
        if (allSet && total > 0 && sumDays == total && start.isNotEmpty) {
          // Ardışık tarih blokları: her şehir dest.days kadar ardışık gün alır.
          for (var i = 0; i < destsSorted.length; i++) {
            destsSorted[i].order = i;
          }
          final startDt = DateTime.parse(start);
          var cursor = 0;
          for (var i = 0; i < destsSorted.length; i++) {
            final d = destsSorted[i];
            final isLast = i == destsSorted.length - 1;
            d.arrivalDate = _ymd(startDt.add(Duration(days: cursor)));
            var depOffset = cursor + d.days! - 1;
            if (isLast || depOffset > total - 1) depOffset = total - 1;
            d.departureDate = _ymd(startDt.add(Duration(days: depOffset)));
            cursor = depOffset + 1;
          }
          t.preferences.destinations = destsSorted;
          t.days = generateDaysBetween(start, end);
        } else if (destsSorted.length >= 2 &&
            start.isNotEmpty &&
            end.isNotEmpty) {
          // Coverage-guard: bir şehir hiç güne düşmüyorsa yeniden dağıt.
          final covered = <String>{};
          for (final d in t.days) {
            final dd = getDestinationForDate(destsSorted, d.date);
            if (dd != null) covered.add(dd.id);
          }
          if (!destsSorted.every((d) => covered.contains(d.id))) {
            for (var i = 0; i < destsSorted.length; i++) {
              destsSorted[i].order = i;
            }
            distributeDates(destsSorted, start, end);
            t.preferences.destinations = destsSorted;
            t.days = generateDaysBetween(start, end);
          }
        }
      }

      // ignore: dead_code
      if (_kApiEnabled) {
        // TODO: itinerary_lookup.generateItinerary(trip) ile AI dene.
      }
      // Eklenen şehir de dikkate alınsın diye günceli `t`'den oku (widget.trip
      // bayat olabilir — _destinations getter'ı kullanma).
      final destsNow = [...t.preferences.destinations]
        ..sort((a, b) => a.order.compareTo(b.order));
      final generated = generateItineraryFromTrip(t, lang: lang);
      t.days = fillEmptyDays(generated, destsNow, lang: lang);

      // BUG 2: Şehirler arası geçişleri otomatik ekle — kullanıcı her öneri için
      // ayrıca "Ekle"ye dokunmak zorunda kalmasın. Aynı gün hâlâ manuel
      // eklendiyse dokunulmaz (hasExistingTransferTo koruması).
      final transitions = detectCityTransitions(t.days, destsNow);
      var updated = t.days;
      for (final s in transitions) {
        final target = updated.firstWhere(
          (d) => d.dayNumber == s.toDayNumber,
          orElse: () => DayPlan(dayNumber: s.toDayNumber, date: '', theme: ''),
        );
        if (target.date.isEmpty) continue;
        if (!hasExistingTransferTo(target, s.toCity)) {
          updated = insertCityTransfer(updated, s.toDayNumber, s, lang: lang);
        }
      }
      t.days = updated;
    });

    if (!mounted) return;
    setState(() {
      _generating = false;
      _planRevealed = true;
      _expanded = trip.days.map((d) => d.dayNumber).toSet();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(hasPlan ? s.s('plan.regenerated') : s.s('plan.generated')),
        duration: const Duration(seconds: 2),
      ),
    );

    // USJ / Disney / Shinkansen bilet açılış uyarıları — plan içinde
    // yakalandıysa kullanıcıya hatırlatma teklif et.
    await _maybeShowBookingAlerts();
  }

  Future<void> _maybeShowBookingAlerts() async {
    final alerts = detectBookingAlerts(trip);
    if (alerts.isEmpty || !mounted) return;
    // ProviderScope.containerOf ile container al — PlanStep StatefulWidget kalabilsin.
    final container = ProviderScope.containerOf(context, listen: false);
    final result = await showBookingAlertsDialog(
      context: context,
      container: container,
      alerts: alerts,
      tripId: trip.id,
    );
    if (result != null && result.addedCount > 0 && mounted) {
      final s = LanguageScope.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(s.p('plan.remindersAdded', {'n': '${result.addedCount}'})),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Kullanıcının seçtiği mode override'ını uygula (varsa) — öneri kartındaki
  /// picker seçimi eklenirken de kullanılsın diye tek noktada yapılıyor.
  CityTransitionSuggestion _effectiveSuggestion(CityTransitionSuggestion s) {
    final override = _transitionModeOverrides[_transitionKey(s)];
    if (override == null) return s;
    return suggestionForMode(
        override, s.fromCity, s.toCity, s.fromDayNumber, s.toDayNumber);
  }

  void _addTransition(CityTransitionSuggestion s) {
    final eff = _effectiveSuggestion(s);
    final lang = _lang;
    widget.onChange((t) {
      t.days = insertCityTransfer(t.days, eff.toDayNumber, eff, lang: lang);
    });
  }

  void _addAllTransitions(List<CityTransitionSuggestion> list) {
    final lang = _lang;
    widget.onChange((t) {
      var days = t.days;
      for (final s in list) {
        final eff = _effectiveSuggestion(s);
        days = insertCityTransfer(days, eff.toDayNumber, eff, lang: lang);
      }
      t.days = days;
    });
  }

  /// Ulaşım modu seçimi — bottom sheet ile 4 seçenek. Seçim tamamlanmazsa null.
  Future<String?> _pickTransportMode(
      BuildContext context, String current) async {
    final s = LanguageScope.of(context);
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: PT.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(PT.radiusLg)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: PT.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(s.s('plan.pickTransportTitle'),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: PT.text)),
              const SizedBox(height: 12),
              for (final m in [
                (
                  id: 'shinkansen',
                  emoji: '🚄',
                  label: 'Shinkansen',
                  note: s.s('plan.mode.shinkansenNote'),
                ),
                (
                  id: 'train',
                  emoji: '🚆',
                  label: s.s('plan.mode.trainLabel'),
                  note: s.s('plan.mode.trainNote'),
                ),
                (
                  id: 'bus',
                  emoji: '🚌',
                  label: s.s('plan.mode.busLabel'),
                  note: s.s('plan.mode.busNote'),
                ),
                (
                  id: 'car',
                  emoji: '🚗',
                  label: s.s('plan.mode.carLabel'),
                  note: s.s('plan.mode.carNote'),
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(ctx, m.id),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: current == m.id ? PT.accentSoft : PT.bgSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: current == m.id ? PT.accent : PT.border),
                      ),
                      child: Row(
                        children: [
                          Text(m.emoji, style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.label,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: PT.text)),
                                const SizedBox(height: 2),
                                Text(m.note,
                                    style: const TextStyle(
                                        fontSize: 12, color: PT.textSecondary)),
                              ],
                            ),
                          ),
                          if (current == m.id)
                            const Icon(Icons.check_circle,
                                size: 20, color: PT.accent),
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

  /// Öneri kartındaki "Ulaşım değiştir" tetikleyicisi.
  void _onChangeTransitionMode(CityTransitionSuggestion s) async {
    final key = _transitionKey(s);
    final current = _transitionModeOverrides[key] ?? 'shinkansen';
    final picked = await _pickTransportMode(context, current);
    if (picked == null) return;
    setState(() {
      _transitionModeOverrides[key] = picked;
    });
  }

  // --- Keşfet -----------------------------------------------------------------

  void _openDiscover(int dayNumber, TripDestination dest) {
    final profile = getDestinationProfile(dest.countryCode);
    final places = profile?.popularPlaces ?? const <PlaceSuggestion>[];
    var pickedCount = 0;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PT.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(PT.radiusLg)),
      ),
      builder: (ctx) => _DiscoverSheet(
        city: dest.city,
        country: dest.countryName,
        flag: profile?.flag,
        places: places,
        onPick: (p) {
          widget.onChange((t) {
            t.days = addPlaceToDay(
                t.days,
                dayNumber,
                PlaceToAdd(
              name: p.name,
              emoji: p.emoji,
              steps: p.typicalSteps,
              city: p.city,
            ));
          });
          pickedCount++;
        },
      ),
    ).then((_) {
      if (pickedCount > 0) _optimizeDay(dayNumber);
    });
  }

  // --- Öğe düzenle sheet ------------------------------------------------------

  void _editItem(int dayNumber, TimelineItem item) {
    if (item.isFixed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            item.lockReason ??
                LanguageScope.of(context).s('viewer.edit.locked'),
          ),
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PT.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(PT.radiusLg)),
      ),
      builder: (ctx) => _ItemEditSheet(
        item: item,
        onSave: (updated) => _replaceItem(dayNumber, updated),
      ),
    );
  }

  // --- Yer detay popup (tanıtım + öneriler + adım + haritaya git) -------------

  void _openDetail(DayPlan day, TimelineItem item) {
    final dest = getDestinationForDate(_destinations, day.date);
    final existing = trip.tickets
        .where((t) => t.label == item.title)
        .cast<Ticket?>()
        .firstWhere((_) => true, orElse: () => null);
    showPlaceDetailSheet(
      context: context,
      item: item,
      city: dest?.city ?? '',
      countryCode: dest?.countryCode,
      existingTicket: existing,
      onAddTicket: (t) => widget.onChange((trip) {
        trip.tickets.removeWhere((x) => x.label == t.label);
        trip.tickets.add(t);
      }),
      onEdit: () {
        Navigator.pop(context);
        _editItem(day.dayNumber, item);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final destinations = _destinations;
    if (destinations.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
        children: [
          const PageHeadline('Plan'),
          PageSub(s.s('plan.emptyRouteSub')),
        ],
      );
    }

    final routeLabel = destinations
        .map((d) =>
            '${getDestinationProfile(d.countryCode)?.flag ?? ''} ${d.city.isNotEmpty ? d.city : d.countryName}')
        .join(' → ');
    final totalSteps =
        trip.days.fold<int>(0, (s, d) => s + (d.stepsEstimate ?? 0));
    final childCount = trip.preferences.childrenCount ?? 0;
    final allDaysEmpty =
        trip.days.isNotEmpty && trip.days.every((d) => d.items.isEmpty);

    // Gün dağılımı — her şehir için görüntülenecek gün adedi + kalan.
    final totalDays = _inclusiveDays(
        trip.preferences.travelDates.start, trip.preferences.travelDates.end);
    final dayAlloc = _effectiveDayAlloc(destinations, totalDays);
    final allocLeft = totalDays - dayAlloc.fold<int>(0, (n, v) => n + v);

    final transitions = _planRevealed
        ? detectCityTransitions(trip.days, destinations).where((s) {
            final day = trip.days
                .where((d) => d.dayNumber == s.toDayNumber)
                .cast<DayPlan?>()
                .firstWhere((_) => true, orElse: () => null);
            return day == null ? true : !hasExistingTransferTo(day, s.toCity);
          }).toList()
        : <CityTransitionSuggestion>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
      children: [
        const PageHeadline('Plan'),
        PageSub(s.p('plan.daysRoute',
                {'n': '${trip.days.length}', 'route': routeLabel}) +
            (childCount > 0
                ? s.p('plan.childrenSuffix', {'n': '$childCount'})
                : '')),

        // Toolbar: tempo pilleri + toplam adım + oluştur
        PCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(s.s('plan.pace'),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: PT.textTertiary)),
                  const SizedBox(width: 12),
                  ...[
                    (Pace.relaxed, s.s('plan.pace.relaxed')),
                    (Pace.moderate, s.s('plan.pace.moderate')),
                    (Pace.intense, s.s('plan.pace.intense')),
                  ].map((e) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: PChip(
                          label: e.$2,
                          active: trip.preferences.pace == e.$1,
                          onTap: () =>
                              widget.onChange((t) => t.preferences.pace = e.$1),
                        ),
                      )),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(s.s('plan.childrenQuestion'),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: PT.textTertiary)),
                  const SizedBox(width: 12),
                  ...[0, 1, 2, 3, 4].map((n) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: PChip(
                          label: '$n',
                          active: (trip.preferences.childProfiles.isNotEmpty
                                  ? trip.preferences.childProfiles.length
                                  : (trip.preferences.childrenCount ?? 0)) ==
                              n,
                          onTap: () => widget
                              .onChange((t) => t.preferences.childrenCount = n),
                        ),
                      )),
                ],
              ),
              if (totalSteps > 0) ...[
                const SizedBox(height: 12),
                Text(
                    s.p('plan.stepsK', {'n': '${(totalSteps / 1000).round()}'}),
                    style:
                        const TextStyle(fontSize: 13, color: PT.textSecondary)),
              ],

              // Gün dağılımı — her şehir için gün adedi stepper'ı.
              const SizedBox(height: 16),
              Text(s.s('plan.dayAlloc.title'),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: PT.textTertiary)),
              const SizedBox(height: 4),
              Text(
                  s.p('plan.dayAlloc.summary',
                      {'total': '$totalDays', 'left': '$allocLeft'}),
                  style:
                      const TextStyle(fontSize: 12, color: PT.textSecondary)),
              const SizedBox(height: 8),
              for (var i = 0; i < destinations.length; i++)
                _dayAllocRow(destinations, i, dayAlloc, allocLeft, s),

              const SizedBox(height: 16),
              if (_generating) ...[
                const ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    backgroundColor: PT.bgSubtle,
                    color: PT.accent,
                  ),
                ),
                const SizedBox(height: 10),
                Text(s.s('plan.generating'),
                    style:
                        const TextStyle(fontSize: 13, color: PT.textSecondary)),
              ] else
                PButton(
                  label: trip.days.any((d) => d.items.isNotEmpty)
                      ? s.s('plan.regenerate')
                      : s.s('plan.generate'),
                  block: true,
                  onPressed: _generate,
                ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            s.s('plan.introBlurb'),
            style: const TextStyle(
                fontSize: 13, color: PT.textSecondary, height: 1.4),
          ),
        ),

        // Şehir geçişleri
        if (transitions.isNotEmpty)
          PCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(s.s('plan.transitionsTitle'),
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: PT.text)),
                    ),
                    if (transitions.length > 1)
                      PButton(
                        label:
                            s.p('plan.addAll', {'n': '${transitions.length}'}),
                        primary: false,
                        onPressed: () => _addAllTransitions(transitions),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final s in transitions)
                  _TransitionRow(
                    suggestion: _effectiveSuggestion(s),
                    onAdd: () => _addTransition(s),
                    onChangeMode: () => _onChangeTransitionMode(s),
                  ),
              ],
            ),
          ),

        if (!_planRevealed)
          PCard(
            child: Column(
              children: [
                const Text('🗺️', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 12),
                Text(s.s('plan.noPlanTitle'),
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: PT.text)),
                const SizedBox(height: 8),
                Text(
                  s.s('plan.noPlanBody'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, color: PT.textSecondary, height: 1.5),
                ),
              ],
            ),
          )
        else if (allDaysEmpty)
          PCard(
            child: Column(
              children: [
                const Text('🗺️', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 12),
                Text(s.s('plan.emptyDaysTitle'),
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: PT.text)),
                const SizedBox(height: 8),
                Text(
                  s.s('plan.emptyDaysBody'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, color: PT.textSecondary, height: 1.5),
                ),
              ],
            ),
          )
        else
          for (final day in trip.days)
            _DayCard(
              key: ValueKey(day.dayNumber),
              day: day,
              destinations: destinations,
              prefs: trip.preferences,
              allDays: trip.days,
              expanded: _expanded.contains(day.dayNumber),
              bubbleColor:
                  _cityColor(getDestinationForDate(destinations, day.date)?.id),
              forecast: _forecast[day.date],
              onToggle: () => _toggleExpanded(day.dayNumber),
              onUpdateDay: (m) => _updateDay(day.dayNumber, m),
              onOpenDetail: (it) => _openDetail(day, it),
              onRemoveItem: (id) => _removeItem(day.dayNumber, id),
              onAddItem: () => _openAddItemSheet(day.dayNumber),
              onReorder: (o, n) => _reorder(day.dayNumber, o, n),
              onMoveItemToDay: (id, toDay) =>
                  _moveItemToDay(day.dayNumber, id, toDay),
              onOptimize: () => _optimizeDay(day.dayNumber),
              onDiscover: (dest) => _openDiscover(day.dayNumber, dest),
            ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Şehir geçiş satırı
// ---------------------------------------------------------------------------

class _TransitionRow extends StatelessWidget {
  const _TransitionRow({
    required this.suggestion,
    required this.onAdd,
    required this.onChangeMode,
  });
  final CityTransitionSuggestion suggestion;
  final VoidCallback onAdd;
  final VoidCallback onChangeMode;

  @override
  Widget build(BuildContext context) {
    final loc = LanguageScope.of(context);
    final s = suggestion;
    final t = s.transfer;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PT.bgSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PT.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(t.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${s.fromCity} → ${s.toCity} · ${loc.s(t.mode)}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: PT.text)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
              loc.p('plan.dayRange', {
                'from': '${s.fromDayNumber}',
                'to': '${s.toDayNumber}',
                'duration': t.duration,
                'fare': t.fare,
              }),
              style: const TextStyle(fontSize: 12, color: PT.textSecondary)),
          if (t.tip != null) ...[
            const SizedBox(height: 4),
            Text('💡 ${loc.s(t.tip!)}',
                style: const TextStyle(fontSize: 12, color: PT.textTertiary)),
          ],
          const SizedBox(height: 8),
          // "Ulaşım değiştir" chip — kullanıcı Shinkansen dışı bir seçenek istese
          // burada moda geçer; onAdd sonrasında bu mod ile ekleme yapılır.
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: onChangeMode,
              borderRadius: BorderRadius.circular(100),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: PT.bgElevated,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: PT.borderStrong),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.swap_horiz,
                        size: 14, color: PT.textSecondary),
                    const SizedBox(width: 6),
                    Text(loc.s('plan.changeTransport'),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: PT.textSecondary)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: PButton(label: loc.s('plan.add'), onPressed: onAdd),
          ),
        ],
      ),
    );
  }
}

/// Şehir-arası transfer eklenmiş gün altında gösterilen küçük Yamato Takkyubin
/// ipucu kartı — kullanıcıya valizini otele önceden gönderebileceğini hatırlatır.
class _YamatoTip extends StatelessWidget {
  const _YamatoTip();
  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PT.accentSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PT.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🐈', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.s('plan.yamatoTitle'),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: PT.accent)),
                const SizedBox(height: 4),
                Text(s.s('plan.yamatoBody'),
                    style: const TextStyle(
                        fontSize: 12, color: PT.text, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bir günde şehir-arası transfer öğesi (transport + title'da "→") var mı?
bool _dayHasCityTransition(DayPlan day) {
  return day.items.any(
    (it) => it.kind == TimelineItemKind.transport && it.title.contains('→'),
  );
}

// ---------------------------------------------------------------------------
// Gün kartı (DayPlanCard portu)
// ---------------------------------------------------------------------------

class _DayCard extends StatelessWidget {
  const _DayCard({
    super.key,
    required this.day,
    required this.destinations,
    required this.prefs,
    required this.allDays,
    required this.expanded,
    required this.bubbleColor,
    this.forecast,
    required this.onToggle,
    required this.onUpdateDay,
    required this.onOpenDetail,
    required this.onRemoveItem,
    required this.onAddItem,
    required this.onReorder,
    required this.onMoveItemToDay,
    required this.onOptimize,
    required this.onDiscover,
  });
  final DayPlan day;
  final List<TripDestination> destinations;
  final TripPreferences prefs;
  final List<DayPlan> allDays;
  final bool expanded;
  final Color bubbleColor;
  final DayForecast? forecast;
  final VoidCallback onToggle;
  final void Function(void Function(DayPlan)) onUpdateDay;
  final ValueChanged<TimelineItem> onOpenDetail;
  final ValueChanged<String> onRemoveItem;
  final VoidCallback onAddItem;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(String itemId, int toDay) onMoveItemToDay;
  final VoidCallback onOptimize;
  final ValueChanged<TripDestination> onDiscover;

  void _showWeatherDialog(BuildContext context, DayForecast f) {
    final s = LanguageScope.of(context);
    final info = weatherInfo(f.code);
    final emoji = info.$1;
    final label = s.s(info.$2);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PT.radius)),
        title: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  Text(f.date,
                      style: const TextStyle(
                          fontSize: 12, color: PT.textSecondary)),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _wxDialogRow(s.s('wx.high'), '${f.tempMax.round()}°C'),
            const SizedBox(height: 6),
            _wxDialogRow(s.s('wx.low'), '${f.tempMin.round()}°C'),
            if (f.precipProb != null) ...[
              const SizedBox(height: 6),
              _wxDialogRow(s.s('wx.precip'), '%${f.precipProb}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.s('wx.close')),
          ),
        ],
      ),
    );
  }

  Widget _wxDialogRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 14, color: PT.textSecondary)),
        Text(value,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: PT.text)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final dest = getDestinationForDate(destinations, day.date);
    final profile =
        dest != null ? getDestinationProfile(dest.countryCode) : null;
    final overLimit = suggestTaxiForDay(day, prefs);

    return PCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık satırı
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(PT.radius),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${day.dayNumber}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(day.date,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: PT.text)),
                            if (day.weekday != null) ...[
                              const SizedBox(width: 6),
                              Text(day.weekday!,
                                  style: const TextStyle(
                                      fontSize: 12, color: PT.textTertiary)),
                            ],
                            if (forecast != null) ...[
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () =>
                                    _showWeatherDialog(context, forecast!),
                                borderRadius: BorderRadius.circular(999),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: PT.bgSubtle,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: PT.border),
                                  ),
                                  child: Text(
                                    '${weatherInfo(forecast!.code).$1} ${forecast!.tempMax.round()}°',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: PT.text),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                            day.theme.isEmpty
                                ? s.p('plan.dayN', {'n': '${day.dayNumber}'})
                                : day.theme,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: PT.text)),
                        if (dest != null)
                          Text(
                              '${profile?.flag ?? ''} ${dest.city.isNotEmpty ? dest.city : dest.countryName}',
                              style: const TextStyle(
                                  fontSize: 12, color: PT.textSecondary)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (day.stepsEstimate != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                                '👣 ${((day.stepsEstimate ?? 0) / 1000).round()}k',
                                style: const TextStyle(
                                    fontSize: 12, color: PT.textSecondary)),
                            if (overLimit) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('🚕',
                                    style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ],
                        ),
                      const SizedBox(height: 4),
                      Text(s.p('plan.stops', {'n': '${day.items.length}'}),
                          style: const TextStyle(
                              fontSize: 12, color: PT.textTertiary)),
                    ],
                  ),
                  const SizedBox(width: 6),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more,
                      size: 22, color: PT.textTertiary),
                ],
              ),
            ),
          ),

          if (day.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in day.tags)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: PT.bgSubtle,
                      borderRadius: BorderRadius.circular(PT.radiusPill),
                      border: Border.all(color: PT.border),
                    ),
                    child: Text(tag,
                        style: const TextStyle(
                            fontSize: 12, color: PT.textSecondary)),
                  ),
              ],
            ),
          ],

          if (expanded) ...[
            const SizedBox(height: 12),
            // Tema düzenle
            PField(
              label: s.s('plan.dayTheme'),
              child: PTextField(
                value: day.theme,
                hint: s.s('plan.dayThemeHint'),
                onChanged: (v) => onUpdateDay((d) => d.theme = v),
              ),
            ),

            if (day.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(s.s('plan.dayEmpty'),
                    style:
                        const TextStyle(fontSize: 13, color: PT.textTertiary)),
              )
            else ...[
              if (_dayHasCityTransition(day)) ...[
                const SizedBox(height: 4),
                const _YamatoTip(),
              ],
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: day.items.length,
                onReorderItem: onReorder,
                itemBuilder: (ctx, idx) {
                  final it = day.items[idx];
                  return _TimelineTile(
                    key: ValueKey(it.id),
                    index: idx,
                    item: it,
                    otherDays: allDays
                        .where((d) => d.dayNumber != day.dayNumber)
                        .toList(),
                    onTap: () => onOpenDetail(it),
                    onRemove: () => _confirmRemove(context, it),
                    onMoveToDay: (toDay) => onMoveItemToDay(it.id, toDay),
                  );
                },
              ),
            ],

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: PButton(
                    label: s.s('plan.addActivity'),
                    primary: false,
                    onPressed: onAddItem,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PButton(
                    label: s.s('plan.optimize'),
                    primary: false,
                    onPressed: day.items.length > 1 ? onOptimize : null,
                  ),
                ),
              ],
            ),
            if (dest != null) ...[
              const SizedBox(height: 10),
              PButton(
                label: s.s('plan.discover'),
                block: true,
                onPressed: () => onDiscover(dest),
              ),
            ],
          ],
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context, TimelineItem it) async {
    final s = LanguageScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.s('plan.removeConfirmTitle')),
        content: Text(s.p('plan.removeConfirmBody', {'title': it.title})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.s('plan.cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.s('plan.delete'),
                  style: const TextStyle(color: PT.danger))),
        ],
      ),
    );
    if (ok == true) onRemoveItem(it.id);
  }
}

// ---------------------------------------------------------------------------
// Zaman çizelgesi öğesi
// ---------------------------------------------------------------------------

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    super.key,
    required this.index,
    required this.item,
    required this.otherDays,
    required this.onTap,
    required this.onRemove,
    required this.onMoveToDay,
  });
  final int index;
  final TimelineItem item;
  final List<DayPlan> otherDays;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final ValueChanged<int> onMoveToDay;

  IconData _kindIcon(TimelineItemKind? k) => switch (k) {
        TimelineItemKind.meal => Icons.restaurant,
        TimelineItemKind.transport => Icons.directions_transit,
        TimelineItemKind.hotel => Icons.hotel,
        _ => Icons.place,
      };

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final time = item.time ?? item.scheduledTime ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: PT.bgSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PT.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(top: 2, right: 4),
                  child:
                      Icon(Icons.drag_handle, size: 20, color: PT.textTertiary),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(time,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: PT.accent)),
              ),
              const SizedBox(width: 6),
              Icon(_kindIcon(item.kind), size: 16, color: PT.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: PT.text)),
                    if (item.movedFromDay != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                            s.p('plan.movedFrom',
                                {'n': '${item.movedFromDay}'}),
                            style: const TextStyle(
                                fontSize: 11, color: PT.textTertiary)),
                      ),
                    if (item.description != null &&
                        item.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(item.description!,
                            style: const TextStyle(
                                fontSize: 12, color: PT.textSecondary)),
                      ),
                    if (item.cost != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                            '${item.cost} ${item.costCurrency ?? ''}'.trim(),
                            style: const TextStyle(
                                fontSize: 12, color: PT.textTertiary)),
                      ),
                    if (item.tips != null && item.tips!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('💡 ${item.tips}',
                            style: const TextStyle(
                                fontSize: 12, color: PT.textTertiary)),
                      ),
                  ],
                ),
              ),
              if (otherDays.isNotEmpty)
                PopupMenuButton<int>(
                  icon: const Icon(Icons.swap_vert,
                      size: 20, color: PT.textTertiary),
                  tooltip: s.s('plan.moveToDay'),
                  onSelected: onMoveToDay,
                  itemBuilder: (ctx) => [
                    for (final d in otherDays)
                      PopupMenuItem(
                        value: d.dayNumber,
                        child: Text(s.p('plan.dayWithDate', {
                          'n': '${d.dayNumber}',
                          'date':
                              d.date.length >= 5 ? d.date.substring(5) : d.date,
                        })),
                      ),
                  ],
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: const Icon(Icons.close, size: 18, color: PT.textTertiary),
                tooltip: s.s('plan.delete'),
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Öğe düzenle sheet
// ---------------------------------------------------------------------------

class _ItemEditSheet extends StatefulWidget {
  const _ItemEditSheet({required this.item, required this.onSave});
  final TimelineItem item;
  final ValueChanged<TimelineItem> onSave;

  @override
  State<_ItemEditSheet> createState() => _ItemEditSheetState();
}

class _ItemEditSheetState extends State<_ItemEditSheet> {
  late String _title = widget.item.title;
  late String _time = widget.item.time ?? widget.item.scheduledTime ?? '';
  late String _description = widget.item.description ?? '';
  late String _tips = widget.item.tips ?? '';
  late int? _duration = widget.item.durationMin;
  late int? _cost = widget.item.cost;
  late String _costCurrency = widget.item.costCurrency ?? 'JPY';

  void _save() {
    final src = widget.item;
    final updated = TimelineItem(
      id: src.id,
      title: _title.trim().isEmpty ? src.title : _title.trim(),
      time: _time.isEmpty ? null : _time,
      scheduledTime: _time.isEmpty ? null : _time,
      description: _description.trim().isEmpty ? null : _description.trim(),
      tips: _tips.trim().isEmpty ? null : _tips.trim(),
      kind: src.kind,
      movedFromDay: src.movedFromDay,
      lat: src.lat,
      lng: src.lng,
      durationMin: _duration,
      cost: _cost,
      costCurrency: _cost == null ? null : _costCurrency,
      cityId: src.cityId,
      mapUrl: src.mapUrl,
      lockType: src.lockType,
      fixedStartTime: src.fixedStartTime,
      fixedEndTime: src.fixedEndTime,
      canChangeDay: src.canChangeDay,
      canChangeTime: src.canChangeTime,
      canReorder: src.canReorder,
      canDelete: src.canDelete,
      lockReason: src.lockReason,
    );
    widget.onSave(updated);
    Navigator.pop(context);
  }

  Future<void> _pickTime() async {
    TimeOfDay init = const TimeOfDay(hour: 10, minute: 0);
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_time);
    if (m != null) {
      init = TimeOfDay(
          hour: int.parse(m.group(1)!), minute: int.parse(m.group(2)!));
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: init,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _time =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollCtrl) => SafeArea(
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: PT.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(s.s('plan.editActivity'),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: PT.text)),
              const SizedBox(height: 16),
              PField(
                label: s.s('plan.fieldTitle'),
                child: PTextField(
                  value: _title,
                  onChanged: (v) => _title = v,
                ),
              ),
              PField(
                label: s.s('plan.fieldTime'),
                child: _ItemTimeBox(value: _time, onTap: _pickTime),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PField(
                      label: s.s('plan.fieldDuration'),
                      child: PTextField(
                        value: _duration?.toString() ?? '',
                        hint: '90',
                        keyboardType: TextInputType.number,
                        onChanged: (v) => _duration = int.tryParse(v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: PField(
                      label: s.s('plan.fieldCost'),
                      child: PTextField(
                        value: _cost?.toString() ?? '',
                        hint: '1500',
                        keyboardType: TextInputType.number,
                        onChanged: (v) => _cost = int.tryParse(v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 80,
                    child: PField(
                      label: s.s('plan.fieldCurrency'),
                      child: PTextField(
                        value: _costCurrency,
                        onChanged: (v) => _costCurrency = v,
                      ),
                    ),
                  ),
                ],
              ),
              PField(
                label: s.s('plan.fieldDescription'),
                child: PTextField(
                  value: _description,
                  hint: s.s('plan.fieldDescriptionHint'),
                  onChanged: (v) => _description = v,
                ),
              ),
              PField(
                label: s.s('plan.fieldTips'),
                child: PTextField(
                  value: _tips,
                  hint: s.s('plan.fieldTipsHint'),
                  onChanged: (v) => _tips = v,
                ),
              ),
              if (widget.item.mapUrl != null && widget.item.mapUrl!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: PButton(
                    label: s.s('plan.copyMapLink'),
                    primary: false,
                    block: true,
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: widget.item.mapUrl!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.s('plan.mapLinkCopied'))),
                      );
                    },
                  ),
                ),
              PButton(label: s.s('plan.save'), block: true, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemTimeBox extends StatelessWidget {
  const _ItemTimeBox({required this.value, required this.onTap});
  final String value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: PT.bgSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: PT.borderStrong),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule, size: 16, color: PT.textSecondary),
            const SizedBox(width: 10),
            Text(value.isEmpty ? s.s('plan.pickTime') : value,
                style: TextStyle(
                    fontSize: 15,
                    color: value.isEmpty ? PT.textTertiary : PT.text)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Keşif sheet (PlaceDiscoveryModal fallback-only portu)
// ---------------------------------------------------------------------------

class _DiscoverSheet extends StatefulWidget {
  const _DiscoverSheet({
    required this.city,
    required this.country,
    required this.flag,
    required this.places,
    required this.onPick,
  });
  final String city;
  final String country;
  final String? flag;
  final List<PlaceSuggestion> places;
  final ValueChanged<PlaceSuggestion> onPick;

  @override
  State<_DiscoverSheet> createState() => _DiscoverSheetState();
}

class _DiscoverSheetState extends State<_DiscoverSheet> {
  final Set<String> _picked = {};

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final flag = widget.flag != null ? '${widget.flag} ' : '';
    final headline = widget.city.isNotEmpty && widget.country.isNotEmpty
        ? '$flag${widget.city}, ${widget.country}'
        : '$flag${widget.city.isNotEmpty ? widget.city : widget.country}';

    return DraggableScrollableSheet(
      // Tam ekran kaplamasın — yukarı çekilerek büyütülebilir.
      initialChildSize: 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollCtrl) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: PT.borderStrong,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(s.s('plan.discoverPortal'),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          color: PT.textTertiary)),
                  const SizedBox(height: 4),
                  Text(
                      headline.isEmpty
                          ? s.s('plan.placeSuggestions')
                          : headline,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: PT.text)),
                  const SizedBox(height: 4),
                  Text(s.s('plan.discoverSub'),
                      style: const TextStyle(
                          fontSize: 13, color: PT.textSecondary)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
                  for (final p in widget.places)
                    _DiscoverCard(
                      place: p,
                      picked: _picked.contains(p.id),
                      onTap: () {
                        widget.onPick(p);
                        setState(() => _picked.add(p.id));
                      },
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                        _picked.isEmpty
                            ? s.s('plan.pickMultiple')
                            : s.p(
                                'plan.placesAdded', {'n': '${_picked.length}'}),
                        style: const TextStyle(
                            fontSize: 13, color: PT.textSecondary)),
                  ),
                  PButton(
                      label: s.s('plan.done'),
                      onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoverCard extends StatelessWidget {
  const _DiscoverCard({
    required this.place,
    required this.picked,
    required this.onTap,
  });
  final PlaceSuggestion place;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    // Küratörlü rehber varsa gerçek puanı ve pratik meta bilgiyi göster.
    final guide = matchPlaceGuide(place.name);
    final rating = guide?.averageRating ?? placeRating(place);
    final meta = [
      if (guide != null)
        '⏱ ${_formatGuideDuration(context, guide.visitDurationMin)}',
      if (guide?.advanceBookingDays != null)
        s.p('plan.advanceBooking', {'n': '${guide!.advanceBookingDays}'}),
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: picked ? PT.accentSoft : PT.bgSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: picked ? PT.accent : PT.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(place.emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(place.name,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: PT.text)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                            '${ratingStars(rating)} ${rating.toStringAsFixed(1)}',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFFF59E0B))),
                        if (isKidFriendly(place)) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: PT.bgElevated,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: PT.border),
                            ),
                            child: Text(s.s('plan.kidFriendly'),
                                style: const TextStyle(
                                    fontSize: 11, color: PT.textSecondary)),
                          ),
                        ],
                      ],
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(meta,
                          style: const TextStyle(
                              fontSize: 11.5, color: PT.textSecondary)),
                    ],
                  ],
                ),
              ),
              Icon(picked ? Icons.check_circle : Icons.add_circle_outline,
                  size: 24, color: picked ? PT.accent : PT.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatGuideDuration(BuildContext context, int minutes) {
  final s = LanguageScope.of(context);
  if (minutes < 60) return s.p('plan.durMin', {'n': '$minutes'});
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) return s.p('plan.durHour', {'n': '$h'});
  return s.p('plan.durHourMin', {'h': '$h', 'm': '$m'});
}

// ---------------------------------------------------------------------------
// _AddItemSheet — "+ Aktivite" akışı için insancıl bottom-sheet.
// ---------------------------------------------------------------------------

class _AddItemSheet extends StatefulWidget {
  const _AddItemSheet({
    required this.occupiedTimes,
    required this.onSubmit,
  });

  /// Günün mevcut item saatleri ("HH:mm" biçiminde). Bu saatlerin ±30 dk
  /// çevresindeki dilimler filtrelenir.
  final List<String> occupiedTimes;
  final void Function(String name, String time, TimelineItemKind kind) onSubmit;

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  final TextEditingController _nameCtrl = TextEditingController();
  TimelineItemKind _kind = TimelineItemKind.activity;
  late List<String> _slots;
  late String _time;
  bool _submitted = false;

  static const List<({TimelineItemKind kind, String labelKey, String emoji})>
      _kindOptions = [
    (
      kind: TimelineItemKind.activity,
      labelKey: 'plan.kindActivity',
      emoji: '📍'
    ),
    (kind: TimelineItemKind.meal, labelKey: 'plan.kindMeal', emoji: '🍽️'),
    (
      kind: TimelineItemKind.transport,
      labelKey: 'plan.kindTransport',
      emoji: '🚆'
    ),
    (kind: TimelineItemKind.hotel, labelKey: 'plan.kindHotel', emoji: '🏨'),
  ];

  @override
  void initState() {
    super.initState();
    _slots = _computeSlots();
    // Varsayılan: 10:00'dan itibaren ilk boş dilim; yoksa listedeki ilk.
    _time = _slots.firstWhere(
      (s) => _minutes(s) >= _minutes('10:00'),
      orElse: () => _slots.isNotEmpty ? _slots.first : '10:00',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  int _minutes(String hhmm) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm);
    if (m == null) return -1;
    return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  String _fmt(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// 08:00 → 22:00, 30 dk aralıkla, dolu dilimlerin ±30 dk çevresi hariç.
  List<String> _computeSlots() {
    final occupied = <int>[
      for (final t in widget.occupiedTimes)
        if (_minutes(t) >= 0) _minutes(t),
    ];
    final result = <String>[];
    for (var m = 8 * 60; m <= 22 * 60; m += 30) {
      final blocked = occupied.any((o) => (o - m).abs() < 30);
      if (!blocked) result.add(_fmt(m));
    }
    return result;
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    setState(() => _submitted = true);
    if (name.isEmpty) return;
    widget.onSubmit(name, _time, _kind);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final noSlots = _slots.isEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: PT.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(s.s('plan.addActivityTitle'),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: PT.text)),
              const SizedBox(height: 16),
              PField(
                label: s.s('plan.placeName'),
                hint: _submitted && _nameCtrl.text.trim().isEmpty
                    ? Text(s.s('plan.placeNameRequired'),
                        style: const TextStyle(fontSize: 12, color: PT.danger))
                    : null,
                child: TextField(
                  controller: _nameCtrl,
                  autofocus: true,
                  onSubmitted: (_) => _submit(),
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: s.s('plan.placeNameHint'),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    filled: true,
                    fillColor: PT.bgSubtle,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: _submitted && _nameCtrl.text.trim().isEmpty
                              ? PT.danger
                              : PT.borderStrong),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: PT.accent),
                    ),
                  ),
                ),
              ),
              PField(
                label: s.s('plan.fieldTime'),
                hint: noSlots
                    ? Text(s.s('plan.noSlots'),
                        style: const TextStyle(fontSize: 12, color: PT.danger))
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: PT.bgSubtle,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: PT.borderStrong),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _slots.contains(_time)
                          ? _time
                          : (_slots.isNotEmpty ? _slots.first : null),
                      isExpanded: true,
                      hint: Text(s.s('plan.pickTime')),
                      items: [
                        for (final s in _slots)
                          DropdownMenuItem(value: s, child: Text(s)),
                      ],
                      onChanged: noSlots
                          ? null
                          : (v) {
                              if (v != null) setState(() => _time = v);
                            },
                    ),
                  ),
                ),
              ),
              PField(
                label: s.s('plan.kindOptional'),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final opt in _kindOptions)
                      PChip(
                        label: '${opt.emoji} ${s.s(opt.labelKey)}',
                        active: _kind == opt.kind,
                        onTap: () => setState(() => _kind = opt.kind),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: PButton(
                      label: s.s('plan.cancel'),
                      primary: false,
                      block: true,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PButton(
                      label: s.s('plan.addPlain'),
                      block: true,
                      onPressed: noSlots ? null : _submit,
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
