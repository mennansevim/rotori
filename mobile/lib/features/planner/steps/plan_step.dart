import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/booking_windows.dart';
import '../../../domain/city_transfers.dart';
import '../../../domain/day_optimizer.dart';
import '../../../domain/destination_profiles.dart';
import '../../../domain/explore.dart';
import '../../../domain/fill_empty_days.dart';
import '../../../domain/itinerary_generator.dart';
import '../../../domain/japan_suggestions.dart';
import '../../../domain/place_guide.dart';
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
  late Set<int> _expanded;
  bool _planRevealed = false;
  bool _generating = false;

  Trip get trip => widget.trip;

  @override
  void initState() {
    super.initState();
    // İlk 2 gün açık başlar (React slice(0,2)).
    _expanded = trip.days.take(2).map((d) => d.dayNumber).toSet();
    // Zaten dolu bir plan varsa gün listesi görünür başlasın.
    if (trip.days.any((d) => d.items.isNotEmpty)) _planRevealed = true;
  }

  List<TripDestination> get _destinations =>
      [...trip.preferences.destinations]..sort((a, b) => a.order.compareTo(b.order));

  void _toggleExpanded(int dayNumber) {
    setState(() {
      if (!_expanded.remove(dayNumber)) _expanded.add(dayNumber);
    });
  }

  // --- Gün / öğe mutasyonları -------------------------------------------------

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
    widget.onChange((t) {
      for (final d in t.days) {
        if (d.dayNumber == dayNumber) {
          d.items.removeWhere((it) => it.id == itemId);
          break;
        }
      }
    });
  }

  void _replaceItem(int dayNumber, TimelineItem updated) {
    widget.onChange((t) {
      for (final d in t.days) {
        if (d.dayNumber == dayNumber) {
          final idx = d.items.indexWhere((it) => it.id == updated.id);
          if (idx >= 0) d.items[idx] = updated;
          break;
        }
      }
    });
  }

  void _addItem(int dayNumber, String title) {
    widget.onChange((t) {
      for (final d in t.days) {
        if (d.dayNumber == dayNumber) {
          d.items.add(TimelineItem(
            id: newItemId(dayNumber),
            title: title,
            kind: TimelineItemKind.activity,
            time: '10:00',
            scheduledTime: '10:00',
          ));
          break;
        }
      }
    });
  }

  /// ReorderableListView.onReorderItem sonrası: newIndex zaten kaldırma için
  /// düzeltilmiş gelir. Listeyi yeniden diz + resequenceTimes.
  void _reorder(int dayNumber, int oldIndex, int newIndex) {
    widget.onChange((t) {
      for (final d in t.days) {
        if (d.dayNumber != dayNumber) continue;
        final items = [...d.items];
        final moved = items.removeAt(oldIndex);
        items.insert(newIndex, moved);
        d.items = resequenceTimes(items);
        break;
      }
    });
  }

  /// rules.dart moveItemBetweenDays(days, itemId, fromDay, toDay) + resequence.
  void _moveItemToDay(int fromDay, String itemId, int toDay) {
    widget.onChange((t) {
      final moved = moveItemBetweenDays(t.days, itemId, fromDay, toDay);
      // resequence her iki gün için.
      for (final d in moved) {
        if (d.dayNumber == fromDay || d.dayNumber == toDay) {
          d.items = resequenceTimes(d.items);
        }
      }
      t.days = moved;
    });
    setState(() => _expanded.add(toDay));
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

    // Zaten dolu bir plan varsa yeniden üretmeden önce onay al —
    // aksi halde elle yapılan düzenlemeler sessizce silinir.
    final hasPlan = trip.days.any((d) => d.items.isNotEmpty);
    if (hasPlan) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Planı yeniden oluştur'),
          content: const Text(
              'Mevcut plan küratörlü şablonlardan yeniden üretilecek. '
              'Elle yaptığınız düzenlemeler değişebilir. Devam edilsin mi?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Yeniden oluştur')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _generating = true);
    // Loading bar'ın görünmesi için bir kare bekle (üretim senkron ve hızlı).
    await Future<void>.delayed(const Duration(milliseconds: 400));

    widget.onChange((t) {
      // ignore: dead_code
      if (_kApiEnabled) {
        // TODO: itinerary_lookup.generateItinerary(trip) ile AI dene.
      }
      final generated = generateItineraryFromTrip(t);
      t.days = fillEmptyDays(generated, _destinations);
    });

    if (!mounted) return;
    setState(() {
      _generating = false;
      _planRevealed = true;
      _expanded = trip.days.map((d) => d.dayNumber).toSet();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(hasPlan
            ? '✨ Plan yeniden oluşturuldu'
            : '✨ Gezi planı oluşturuldu'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('🔔 ${result.addedCount} hatırlatma eklendi'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _addTransition(CityTransitionSuggestion s) {
    widget.onChange((t) {
      t.days = insertCityTransfer(t.days, s.toDayNumber, s);
    });
  }

  void _addAllTransitions(List<CityTransitionSuggestion> list) {
    widget.onChange((t) {
      var days = t.days;
      for (final s in list) {
        days = insertCityTransfer(days, s.toDayNumber, s);
      }
      t.days = days;
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
            t.days = addPlaceToDay(t.days, dayNumber, PlaceToAdd(
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
    final destinations = _destinations;
    if (destinations.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
        children: const [
          PageHeadline('Plan'),
          PageSub('Önce Rota adımında havaalanı/durak ekleyin.'),
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
        PageSub('${trip.days.length} gün · $routeLabel'
            '${childCount > 0 ? ' · $childCount çocuk' : ''}'),

        // Toolbar: tempo pilleri + toplam adım + oluştur
        PCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Tempo',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: PT.textTertiary)),
                  const SizedBox(width: 12),
                  ...[
                    (Pace.relaxed, 'Rahat'),
                    (Pace.moderate, 'Dengeli'),
                    (Pace.intense, 'Yoğun'),
                  ].map((e) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: PChip(
                          label: e.$2,
                          active: trip.preferences.pace == e.$1,
                          onTap: () => widget
                              .onChange((t) => t.preferences.pace = e.$1),
                        ),
                      )),
                ],
              ),
              if (totalSteps > 0) ...[
                const SizedBox(height: 12),
                Text('👣 ${(totalSteps / 1000).round()}k adım',
                    style: const TextStyle(
                        fontSize: 13, color: PT.textSecondary)),
              ],
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
                const Text('✨ Plan oluşturuluyor…',
                    style: TextStyle(fontSize: 13, color: PT.textSecondary)),
              ] else
                PButton(
                  label: trip.days.any((d) => d.items.isNotEmpty)
                      ? '✨ Planı yeniden oluştur'
                      : '✨ Gezi planı oluştur',
                  block: true,
                  onPressed: _generate,
                ),
            ],
          ),
        ),

        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'Saat saat aktivite, ulaşım, restoran ve ipuçları küratörlü '
            'şablonlardan üretilir. Günleri sürükleyerek düzenleyebilirsiniz.',
            style: TextStyle(fontSize: 13, color: PT.textSecondary, height: 1.4),
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
                    const Expanded(
                      child: Text('🚄 Şehirler arası geçiş önerisi',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: PT.text)),
                    ),
                    if (transitions.length > 1)
                      PButton(
                        label: 'Hepsini ekle (${transitions.length})',
                        primary: false,
                        onPressed: () => _addAllTransitions(transitions),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final s in transitions)
                  _TransitionRow(
                    suggestion: s,
                    onAdd: () => _addTransition(s),
                  ),
              ],
            ),
          ),

        if ((!_planRevealed || allDaysEmpty))
          PCard(
            child: Column(
              children: [
                const Text('🗺️', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 12),
                const Text('Henüz gezi planı yok',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: PT.text)),
                const SizedBox(height: 8),
                Text(
                  'Yukarıdaki "Gezi planı oluştur" butonuyla ${trip.days.length} '
                  'günlük programı saat saat hazırlayalım.',
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
              onToggle: () => _toggleExpanded(day.dayNumber),
              onUpdateDay: (m) => _updateDay(day.dayNumber, m),
              onOpenDetail: (it) => _openDetail(day, it),
              onRemoveItem: (id) => _removeItem(day.dayNumber, id),
              onAddItem: () => _addItem(day.dayNumber, 'Yeni aktivite'),
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
  const _TransitionRow({required this.suggestion, required this.onAdd});
  final CityTransitionSuggestion suggestion;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
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
                child: Text('${s.fromCity} → ${s.toCity} · ${t.mode}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: PT.text)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
              'Gün ${s.fromDayNumber} → Gün ${s.toDayNumber} · ${t.duration} · ${t.fare}',
              style: const TextStyle(fontSize: 12, color: PT.textSecondary)),
          if (t.tip != null) ...[
            const SizedBox(height: 4),
            Text('💡 ${t.tip}',
                style: const TextStyle(fontSize: 12, color: PT.textTertiary)),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: PButton(label: '+ Ekle', onPressed: onAdd),
          ),
        ],
      ),
    );
  }
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
  final VoidCallback onToggle;
  final void Function(void Function(DayPlan)) onUpdateDay;
  final ValueChanged<TimelineItem> onOpenDetail;
  final ValueChanged<String> onRemoveItem;
  final VoidCallback onAddItem;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(String itemId, int toDay) onMoveItemToDay;
  final VoidCallback onOptimize;
  final ValueChanged<TripDestination> onDiscover;

  @override
  Widget build(BuildContext context) {
    final dest = getDestinationForDate(destinations, day.date);
    final profile = dest != null ? getDestinationProfile(dest.countryCode) : null;
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
                      gradient: PT.brandGradient,
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
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(day.theme.isEmpty ? 'Gün ${day.dayNumber}' : day.theme,
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
                            Text('👣 ${((day.stepsEstimate ?? 0) / 1000).round()}k',
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
                      Text('${day.items.length} durak',
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
              label: 'Gün teması',
              child: PTextField(
                value: day.theme,
                hint: 'Örn. Asakusa & Skytree',
                onChanged: (v) => onUpdateDay((d) => d.theme = v),
              ),
            ),

            if (day.items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                    'Bu güne aktivite ekleyin veya başka günden taşıyın.',
                    style: TextStyle(fontSize: 13, color: PT.textTertiary)),
              )
            else
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

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: PButton(
                    label: '+ Aktivite',
                    primary: false,
                    onPressed: onAddItem,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PButton(
                    label: '⚡ Optimize et',
                    primary: false,
                    onPressed: day.items.length > 1 ? onOptimize : null,
                  ),
                ),
              ],
            ),
            if (dest != null) ...[
              const SizedBox(height: 10),
              PButton(
                label: '🌍 Yeni durak keşfet',
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aktiviteyi sil'),
        content: Text('"${it.title}" silinsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sil', style: TextStyle(color: PT.danger))),
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
                  child: Icon(Icons.drag_handle,
                      size: 20, color: PT.textTertiary),
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
                        child: Text('↕ Gün ${item.movedFromDay}\'den taşındı',
                            style: const TextStyle(
                                fontSize: 11, color: PT.textTertiary)),
                      ),
                    if (item.description != null && item.description!.isNotEmpty)
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
                  tooltip: 'Başka güne taşı',
                  onSelected: onMoveToDay,
                  itemBuilder: (ctx) => [
                    for (final d in otherDays)
                      PopupMenuItem(
                        value: d.dayNumber,
                        child: Text('Gün ${d.dayNumber} · ${d.date.length >= 5 ? d.date.substring(5) : d.date}'),
                      ),
                  ],
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: const Icon(Icons.close, size: 18, color: PT.textTertiary),
                tooltip: 'Sil',
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
              const Text('Aktiviteyi düzenle',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: PT.text)),
              const SizedBox(height: 16),
              PField(
                label: 'Başlık',
                child: PTextField(
                  value: _title,
                  onChanged: (v) => _title = v,
                ),
              ),
              PField(
                label: 'Saat',
                child: _ItemTimeBox(value: _time, onTap: _pickTime),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PField(
                      label: 'Süre (dk)',
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
                      label: 'Ücret',
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
                      label: 'Birim',
                      child: PTextField(
                        value: _costCurrency,
                        onChanged: (v) => _costCurrency = v,
                      ),
                    ),
                  ),
                ],
              ),
              PField(
                label: 'Açıklama',
                child: PTextField(
                  value: _description,
                  hint: 'Kısa açıklama',
                  onChanged: (v) => _description = v,
                ),
              ),
              PField(
                label: 'İpucu',
                child: PTextField(
                  value: _tips,
                  hint: 'Örn. Erken git, sıra uzun olur',
                  onChanged: (v) => _tips = v,
                ),
              ),
              if (widget.item.mapUrl != null &&
                  widget.item.mapUrl!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: PButton(
                    label: '🗺️ Harita linkini kopyala',
                    primary: false,
                    block: true,
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: widget.item.mapUrl!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Harita linki kopyalandı')),
                      );
                    },
                  ),
                ),
              PButton(label: 'Kaydet', block: true, onPressed: _save),
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
            Text(value.isEmpty ? 'Saat seç' : value,
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
                  const Text('Keşif portalı',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          color: PT.textTertiary)),
                  const SizedBox(height: 4),
                  Text(headline.isEmpty ? 'Yer önerileri' : headline,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: PT.text)),
                  const SizedBox(height: 4),
                  const Text(
                      'En çok ziyaret edilen yerler — karta dokununca plana eklenir.',
                      style: TextStyle(fontSize: 13, color: PT.textSecondary)),
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
                            ? 'Birden fazla seçebilirsin'
                            : '${_picked.length} yer eklendi',
                        style: const TextStyle(
                            fontSize: 13, color: PT.textSecondary)),
                  ),
                  PButton(
                      label: 'Bitti',
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
    // Küratörlü rehber varsa gerçek puanı ve pratik meta bilgiyi göster.
    final guide = matchPlaceGuide(place.name);
    final rating = guide?.averageRating ?? placeRating(place);
    final meta = [
      if (guide != null) '⏱ ${_formatGuideDuration(guide.visitDurationMin)}',
      if (guide?.advanceBookingDays != null)
        '🎟 ${guide!.advanceBookingDays} gün önce bilet',
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
                        Text('${ratingStars(rating)} ${rating.toStringAsFixed(1)}',
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
                            child: const Text('🧒 Çocuk dostu',
                                style: TextStyle(
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

String _formatGuideDuration(int minutes) {
  if (minutes < 60) return '$minutes dk';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) return '$h saat';
  return '$h sa $m dk';
}
