// Keşfet ana yüzeyi — planlı durakları önceleyen, harita + liste akışı.
//
// Faz 1 sınırı bilinçlidir: "Yakınımda" yalnızca kullanıcının planındaki
// durakları konuma göre anlamlandırır; dışarıdan POI araması yapmaz. Böylece
// harita API'si, üçüncü taraf POI servisi veya beklenmedik konum isteği
// eklemeden faydalı bir ilk sürüm sunulur.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/l10n.dart';
import '../../domain/city_places.dart';
import '../../domain/destination_profiles.dart';
import '../../domain/geofence.dart' as geo;
import '../../domain/place_coords.dart';
import '../../domain/place_image_resolver.dart';
import '../../domain/types.dart';
import '../shared/place_detail_sheet.dart';
import 'geofence_service.dart';
import 'offline_tile_provider.dart';
import 'reward_map_screen.dart';
import 'route_map_sheet.dart';
import 'viewer_theme.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key, required this.trip});

  final Trip trip;

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

enum _ExploreMode { planned, nearby }

/// GPS örneği varsa planlı durakları yakınlığa göre sıralar. Örnek yoksa
/// plan sırasını aynen korur; kullanıcıya “yakındaki” diye tahmin satılmaz.
List<ResolvedStop> sortExploreStopsByDistance(
  List<ResolvedStop> stops,
  GeoSample? sample,
) {
  if (sample == null || stops.length < 2) return List.of(stops);
  final origin = geo.LatLng(sample.lat, sample.lng);
  final sorted = List<ResolvedStop>.of(stops);
  sorted.sort(
    (a, b) => geo
        .distanceMeters(origin, geo.LatLng(a.lat, a.lng))
        .compareTo(geo.distanceMeters(origin, geo.LatLng(b.lat, b.lng))),
  );
  return sorted;
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  _ExploreMode _mode = _ExploreMode.planned;
  int _selectedDayIndex = 0;

  List<DayPlan> get _days {
    final days = [...widget.trip.days];
    days.sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
    return days;
  }

  List<TripDestination> get _destinations {
    final destinations = [...widget.trip.preferences.destinations];
    destinations.sort((a, b) => a.order.compareTo(b.order));
    return destinations;
  }

  DayPlan? get _selectedDay {
    final days = _days;
    if (days.isEmpty) return null;
    final index = _selectedDayIndex.clamp(0, days.length - 1);
    return days[index];
  }

  TripDestination? _destinationFor(DayPlan? day) {
    if (day == null) return null;
    return getDestinationForDate(_destinations, day.date);
  }

  String _cityLabel(DayPlan? day) {
    final destination = _destinationFor(day);
    return cityDataForKey(destination?.city)?.label ??
        destination?.city ??
        day?.theme ??
        '';
  }

  LatLng _cityCenter(DayPlan? day) {
    final destination = _destinationFor(day);
    final city = cityDataForKey(destination?.city);
    final firstPlace =
        city == null || city.places.isEmpty ? null : city.places.first;
    return LatLng(
      destination?.lat ?? firstPlace?.lat ?? 36.2048,
      destination?.lng ?? firstPlace?.lng ?? 138.2529,
    );
  }

  List<ResolvedStop> _stopsFor(
    DayPlan? day,
    GeofenceController? controller,
  ) {
    if (day == null) return const [];
    final destination = _destinationFor(day);
    final city = cityDataForKey(destination?.city);
    final fallback = _cityCenter(day);
    final firstPlace =
        city == null || city.places.isEmpty ? null : city.places.first;
    final stops = resolveDayStops(
      day,
      cityKey: destination?.city,
      fallbackLat: destination?.lat ?? firstPlace?.lat ?? fallback.latitude,
      fallbackLng: destination?.lng ?? firstPlace?.lng ?? fallback.longitude,
    );
    return _mode == _ExploreMode.nearby
        ? sortExploreStopsByDistance(stops, controller?.lastSample)
        : stops;
  }

  Set<String> _visitedIds(GeofenceController? controller) {
    if (controller == null) return const {};
    return {
      for (final entry in controller.visits.records.entries)
        if (entry.value.completedAt != null) entry.key,
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = ViewerPalette.of(context);
    final s = LanguageScope.of(context);
    final controller = ref.watch(geofenceControllerProvider(widget.trip));
    final routeCities = detectTripCities(widget.trip);

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        title: Text(
          s.s('explore.title'),
          style: TextStyle(
            color: p.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
        ),
        actions: [
          IconButton(
            tooltip: s.s('explore.viewProgress'),
            icon: Icon(Icons.insights_outlined, color: p.textPrimary),
            onPressed: () => _openProgress(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: controller ?? _NoopListenable.instance,
        builder: (context, _) {
          final day = _selectedDay;
          final stops = _stopsFor(day, controller);
          return _ExploreBody(
            trip: widget.trip,
            palette: p,
            mode: _mode,
            days: _days,
            selectedDayIndex: _selectedDayIndex,
            cityLabel: _cityLabel(day),
            cityCenter: _cityCenter(day),
            stops: stops,
            routeCities: routeCities,
            controller: controller,
            visitedIds: _visitedIds(controller),
            onModeChanged: (mode) => setState(() => _mode = mode),
            onDayChanged: (index) => setState(() => _selectedDayIndex = index),
            onOpenStop: (stop) => _openStop(context, stop, day),
            onOpenMap: day == null
                ? null
                : () => showRouteMapSheet(
                      context: context,
                      trip: widget.trip,
                      day: day,
                    ),
            onOpenProgress: () => _openProgress(context),
          );
        },
      ),
    );
  }

  Future<void> _openStop(
    BuildContext context,
    ResolvedStop stop,
    DayPlan? day,
  ) async {
    final destination = _destinationFor(day);
    Ticket? existingTicket;
    for (final ticket in widget.trip.tickets) {
      if (ticket.label == stop.item.title ||
          (stop.item.placeId != null &&
              ticket.linkedActivityId == stop.item.id)) {
        existingTicket = ticket;
        break;
      }
    }
    await showPlaceDetailSheet(
      context: context,
      item: stop.item,
      city: destination?.city ?? _cityLabel(day),
      countryCode: destination?.countryCode,
      existingTicket: existingTicket,
    );
  }

  void _openProgress(BuildContext context) {
    final p = ViewerPalette.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: p.toThemeData(),
          child: ViewerPaletteScope(
            palette: p,
            child: RewardMapScreen(trip: widget.trip),
          ),
        ),
      ),
    );
  }
}

class _NoopListenable extends ChangeNotifier {
  _NoopListenable._();
  static final instance = _NoopListenable._();
}

class _ExploreBody extends StatelessWidget {
  const _ExploreBody({
    required this.trip,
    required this.palette,
    required this.mode,
    required this.days,
    required this.selectedDayIndex,
    required this.cityLabel,
    required this.cityCenter,
    required this.stops,
    required this.routeCities,
    required this.controller,
    required this.visitedIds,
    required this.onModeChanged,
    required this.onDayChanged,
    required this.onOpenStop,
    required this.onOpenMap,
    required this.onOpenProgress,
  });

  final Trip trip;
  final ViewerPalette palette;
  final _ExploreMode mode;
  final List<DayPlan> days;
  final int selectedDayIndex;
  final String cityLabel;
  final LatLng cityCenter;
  final List<ResolvedStop> stops;
  final List<CityData> routeCities;
  final GeofenceController? controller;
  final Set<String> visitedIds;
  final ValueChanged<_ExploreMode> onModeChanged;
  final ValueChanged<int> onDayChanged;
  final ValueChanged<ResolvedStop> onOpenStop;
  final VoidCallback? onOpenMap;
  final VoidCallback onOpenProgress;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final total =
        routeCities.fold<int>(0, (sum, city) => sum + city.places.length);
    final routePlaceIds = {
      for (final city in routeCities)
        for (final place in city.places) place.id,
    };
    final visited = visitedIds.where(routePlaceIds.contains).length;
    final origin = mode == _ExploreMode.nearby && controller?.lastSample != null
        ? controller!.lastSample
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 32),
      children: [
        Text(
          s.p('explore.today', {'city': cityLabel.isEmpty ? '—' : cityLabel}),
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        _ExploreModePicker(
          palette: palette,
          mode: mode,
          onChanged: onModeChanged,
        ),
        if (days.length > 1) ...[
          const SizedBox(height: 16),
          _DaySelector(
            days: days,
            selectedIndex: selectedDayIndex,
            palette: palette,
            cityForDay: (day) {
              final destination = getDestinationForDate(
                [...trip.preferences.destinations]
                  ..sort((a, b) => a.order.compareTo(b.order)),
                day.date,
              );
              return cityDataForKey(destination?.city)?.label ??
                  destination?.city ??
                  day.theme;
            },
            onChanged: onDayChanged,
          ),
        ],
        if (mode == _ExploreMode.nearby) ...[
          const SizedBox(height: 16),
          _NearbyStatusCard(controller: controller, palette: palette),
        ],
        const SizedBox(height: 16),
        _MapCard(
          palette: palette,
          stops: stops,
          cityCenter: cityCenter,
          onOpenStop: onOpenStop,
          onOpenMap: onOpenMap,
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: Text(
                mode == _ExploreMode.nearby
                    ? s.s('explore.mode.nearby')
                    : s.s('explore.mode.planned'),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            Text(
              '${stops.length}',
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (stops.isEmpty)
          _NoStopsCard(palette: palette)
        else
          for (final stop in stops) ...[
            _ExploreStopCard(
              stop: stop,
              palette: palette,
              visited: visitedIds.contains(stop.place?.id ?? stop.item.id),
              distanceM: origin == null
                  ? null
                  : geo.distanceMeters(
                      geo.LatLng(origin.lat, origin.lng),
                      geo.LatLng(stop.lat, stop.lng),
                    ),
              showDistance: mode == _ExploreMode.nearby,
              onTap: () => onOpenStop(stop),
            ),
            const SizedBox(height: 10),
          ],
        if (total > 0) ...[
          const SizedBox(height: 14),
          _ProgressCard(
            palette: palette,
            visited: visited,
            total: total,
            onOpen: onOpenProgress,
          ),
        ],
      ],
    );
  }
}

class _ExploreModePicker extends StatelessWidget {
  const _ExploreModePicker({
    required this.palette,
    required this.mode,
    required this.onChanged,
  });

  final ViewerPalette palette;
  final _ExploreMode mode;
  final ValueChanged<_ExploreMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          _ModeChoice(
            palette: palette,
            selected: mode == _ExploreMode.planned,
            label: s.s('explore.mode.planned'),
            onTap: () => onChanged(_ExploreMode.planned),
          ),
          _ModeChoice(
            palette: palette,
            selected: mode == _ExploreMode.nearby,
            label: s.s('explore.mode.nearby'),
            onTap: () => onChanged(_ExploreMode.nearby),
          ),
        ],
      ),
    );
  }
}

class _ModeChoice extends StatelessWidget {
  const _ModeChoice({
    required this.palette,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final ViewerPalette palette;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: selected
              ? palette.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color:
                      selected ? palette.accentStrong : palette.textSecondary,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DaySelector extends StatelessWidget {
  const _DaySelector({
    required this.days,
    required this.selectedIndex,
    required this.palette,
    required this.cityForDay,
    required this.onChanged,
  });

  final List<DayPlan> days;
  final int selectedIndex;
  final ViewerPalette palette;
  final String Function(DayPlan day) cityForDay;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final day = days[index];
          final selected = index == selectedIndex;
          return Semantics(
            button: true,
            selected: selected,
            label: s.p('explore.day', {
              'n': '${day.dayNumber}',
              'city': cityForDay(day),
            }),
            child: ChoiceChip(
              label: Text(
                s.p('explore.day', {
                  'n': '${day.dayNumber}',
                  'city': cityForDay(day),
                }),
              ),
              selected: selected,
              onSelected: (_) => onChanged(index),
              labelStyle: TextStyle(
                color: selected ? palette.accentStrong : palette.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
              backgroundColor: palette.card,
              selectedColor: palette.accent.withValues(alpha: 0.12),
              side: BorderSide(
                  color: selected
                      ? palette.accent.withValues(alpha: 0.45)
                      : palette.border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999)),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          );
        },
      ),
    );
  }
}

class _MapCard extends StatelessWidget {
  const _MapCard({
    required this.palette,
    required this.stops,
    required this.cityCenter,
    required this.onOpenStop,
    required this.onOpenMap,
  });

  final ViewerPalette palette;
  final List<ResolvedStop> stops;
  final LatLng cityCenter;
  final ValueChanged<ResolvedStop> onOpenStop;
  final VoidCallback? onOpenMap;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
                alpha: palette.brightness == Brightness.dark ? 0.18 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
            child: Row(
              children: [
                Icon(Icons.map_outlined, size: 20, color: palette.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.s('explore.map'),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (onOpenMap != null)
                  TextButton(
                    onPressed: onOpenMap,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(s.s('explore.openFullMap')),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 250,
            child: _ExploreMap(
              stops: stops,
              cityCenter: cityCenter,
              palette: palette,
              onOpenStop: onOpenStop,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Text(
              s.s('explore.mapHint'),
              style: TextStyle(color: palette.textMuted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExploreMap extends StatelessWidget {
  const _ExploreMap({
    required this.stops,
    required this.cityCenter,
    required this.palette,
    required this.onOpenStop,
  });

  final List<ResolvedStop> stops;
  final LatLng cityCenter;
  final ViewerPalette palette;
  final ValueChanged<ResolvedStop> onOpenStop;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final points = [for (final stop in stops) LatLng(stop.lat, stop.lng)];
    final options = points.length >= 2
        ? MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(points),
              padding: const EdgeInsets.fromLTRB(44, 38, 44, 44),
            ),
            minZoom: 3,
            maxZoom: 18,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          )
        : MapOptions(
            initialCenter: points.isEmpty ? cityCenter : points.first,
            initialZoom: points.isEmpty ? 11 : 14,
            minZoom: 3,
            maxZoom: 18,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
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
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                  Polyline(
                    points: points,
                    color: palette.accent,
                    strokeWidth: 4,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final stop in stops)
                  Marker(
                    point: LatLng(stop.lat, stop.lng),
                    width: 58,
                    height: 58,
                    alignment: Alignment.center,
                    child: _ExplorePin(
                      stop: stop,
                      palette: palette,
                      onTap: () => onOpenStop(stop),
                    ),
                  ),
              ],
            ),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(s.s('map.osmAttribution')),
              ],
            ),
          ],
        ),
        if (stops.isEmpty)
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.card.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette.border),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  s.s('explore.noStopsTitle'),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ExplorePin extends StatelessWidget {
  const _ExplorePin({
    required this.stop,
    required this.palette,
    required this.onTap,
  });

  final ResolvedStop stop;
  final ViewerPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = _curatedImageUrl(stop);
    return Semantics(
      button: true,
      label: stop.item.title,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: palette.card,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x45000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: imageUrl == null
                  ? Center(
                      child: Text(stop.place?.emoji ?? '📍',
                          style: const TextStyle(fontSize: 20)))
                  : Image.network(imageUrl, fit: BoxFit.cover),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  '${stop.order}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExploreStopCard extends StatelessWidget {
  const _ExploreStopCard({
    required this.stop,
    required this.palette,
    required this.visited,
    required this.distanceM,
    required this.showDistance,
    required this.onTap,
  });

  final ResolvedStop stop;
  final ViewerPalette palette;
  final bool visited;
  final double? distanceM;
  final bool showDistance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final category = stop.place?.category.of(s.lang) ?? '';
    final details = <String>[
      if (showDistance && distanceM != null) _formatDistance(s, distanceM!),
      if (stop.item.time?.isNotEmpty == true)
        stop.item.time!
      else if (stop.item.scheduledTime?.isNotEmpty == true)
        stop.item.scheduledTime!,
      if (stop.item.durationMin != null)
        s.p('explore.duration', {'n': '${stop.item.durationMin}'}),
    ];
    return Semantics(
      button: true,
      label: stop.item.title,
      child: Material(
        color: palette.card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _StopThumbnail(stop: stop, palette: palette),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stop.item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (category.isNotEmpty) category,
                          if (details.isNotEmpty) details.join(' · '),
                        ].join(' · ').isEmpty
                            ? s.s('explore.inPlan')
                            : [
                                if (category.isNotEmpty) category,
                                if (details.isNotEmpty) details.join(' · '),
                              ].join(' · '),
                        style: TextStyle(
                            color: palette.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      visited
                          ? Icons.check_circle_rounded
                          : Icons.chevron_right_rounded,
                      color: visited ? palette.matcha : palette.textMuted,
                      size: 22,
                    ),
                    if (visited) ...[
                      const SizedBox(height: 2),
                      Text(
                        s.s('explore.visited'),
                        style: TextStyle(
                            color: palette.matcha,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
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

String _formatDistance(LanguageScope s, double meters) {
  if (meters < 1000) {
    return s.p('explore.distanceMeters', {'n': '${meters.round()}'});
  }
  return s.p('explore.distanceKilometers', {
    'n': (meters / 1000).toStringAsFixed(1),
  });
}

class _StopThumbnail extends StatelessWidget {
  const _StopThumbnail({required this.stop, required this.palette});

  final ResolvedStop stop;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final imageUrl = _curatedImageUrl(stop);
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(15),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl == null
          ? Center(
              child: Text(stop.place?.emoji ?? '📍',
                  style: const TextStyle(fontSize: 24)))
          : Image.network(imageUrl, fit: BoxFit.cover),
    );
  }
}

class _NearbyStatusCard extends StatelessWidget {
  const _NearbyStatusCard({required this.controller, required this.palette});

  final GeofenceController? controller;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final status = controller?.status;
    final hasFix = controller?.lastSample != null;
    final isGranted = status == GeofencePermissionStatus.granted;
    final isDeniedForever = status == GeofencePermissionStatus.deniedForever;
    final isUnsupported = status == GeofencePermissionStatus.unsupported;
    final statusLabel = isUnsupported
        ? s.s('reward.tracking.unsupported')
        : isDeniedForever
            ? s.s('reward.tracking.deniedForever')
            : isGranted
                ? s.s('reward.tracking.on')
                : s.s('reward.tracking.off');

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(
            isGranted ? Icons.my_location_rounded : Icons.location_on_outlined,
            color: isGranted ? palette.matcha : palette.accent,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusLabel,
                  style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  s.s(
                    hasFix ? 'explore.nearbyActive' : 'explore.nearbyWaiting',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12.5,
                      height: 1.25),
                ),
              ],
            ),
          ),
          if (controller != null && !isGranted && !isUnsupported)
            TextButton(
              onPressed: () {
                if (isDeniedForever) {
                  controller!.openSettings();
                } else {
                  controller!.start();
                }
              },
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 40),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                isDeniedForever
                    ? s.s('reward.tracking.openSettings')
                    : s.s('reward.tracking.start'),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

class _NoStopsCard extends StatelessWidget {
  const _NoStopsCard({required this.palette});

  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.explore_outlined, color: palette.textMuted, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.s('explore.noStopsTitle'),
                  style: TextStyle(
                      color: palette.textPrimary, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  s.s('explore.noStopsBody'),
                  style: TextStyle(
                      color: palette.textSecondary, height: 1.3, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.palette,
    required this.visited,
    required this.total,
    required this.onOpen,
  });

  final ViewerPalette palette;
  final int visited;
  final int total;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final progress = total == 0 ? 0.0 : (visited / total).clamp(0.0, 1.0);
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.emoji_events_outlined,
                      color: palette.gold, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.s('explore.progressTitle'),
                      style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    s.p('explore.progressSummary', {
                      'visited': '$visited',
                      'total': '$total',
                    }),
                    style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded,
                      color: palette.textMuted, size: 20),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: palette.textMuted.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(palette.matcha),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                s.s('explore.viewProgress'),
                style: TextStyle(
                    color: palette.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String? _curatedImageUrl(ResolvedStop stop) {
  final resolver = PlaceImageResolver.instance;
  final direct = resolver.peekCurated(stop.item.title);
  if (direct != null && direct.isNotEmpty) return direct.first;
  final place = stop.place;
  if (place == null) return null;
  final matched = resolver.peekCurated(place.name);
  return matched == null || matched.isEmpty ? null : matched.first;
}
