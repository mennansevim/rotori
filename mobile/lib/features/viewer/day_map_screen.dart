// Gün rotası haritası — bir günün duraklarını OpenStreetMap üzerinde numaralı
// pinlerle gösterir, sırayla bir çizgiyle bağlar ve pine dokununca yer detay
// popup'ını açar. Viewer paletine uyumlu (Theme + ViewerPaletteScope).
//
// Koordinatlar place_coords.dart ile çözülür (çoğu üretilmiş öğede lat/lng
// NULL olduğundan başlık küratörlü şehir noktalarıyla eşleştirilir).
// OSM raster tile ağdan çekilir (API key yok); mobil + web'de çalışır.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/city_places.dart';
import '../../domain/destination_profiles.dart';
import '../../domain/place_coords.dart';
import '../../domain/types.dart';
import '../shared/place_detail_sheet.dart';
import 'viewer_theme.dart';

/// Japonya kaba merkezi — şehir de duraklar da yoksa haritayı buraya odakla.
const LatLng _kJapanCenter = LatLng(36.2048, 138.2529);

class DayMapScreen extends ConsumerWidget {
  const DayMapScreen({
    super.key,
    required this.trip,
    required this.dayNumber,
    this.tileProvider,
  });

  final Trip trip;
  final int dayNumber;

  /// Test'lerde ağ tile isteğini bypass etmek için enjekte edilir; üretimde
  /// null → varsayılan OSM ağ sağlayıcısı kullanılır.
  final TileProvider? tileProvider;

  DayPlan? get _day {
    for (final d in trip.days) {
      if (d.dayNumber == dayNumber) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(viewerPaletteProvider);
    return Theme(
      data: palette.toThemeData(),
      child: ViewerPaletteScope(
        palette: palette,
        child: _DayMapView(
          trip: trip,
          day: _day,
          palette: palette,
          tileProvider: tileProvider,
        ),
      ),
    );
  }
}

class _DayMapView extends StatelessWidget {
  const _DayMapView({
    required this.trip,
    required this.day,
    required this.palette,
    this.tileProvider,
  });

  final Trip trip;
  final DayPlan? day;
  final ViewerPalette palette;
  final TileProvider? tileProvider;

  @override
  Widget build(BuildContext context) {
    final dests = [...trip.preferences.destinations]
      ..sort((a, b) => a.order.compareTo(b.order));
    final dest =
        day != null ? getDestinationForDate(dests, day!.date) : null;
    final cityData = cityDataForKey(dest?.city);
    final cityLabel = dest?.city.isNotEmpty == true
        ? dest!.city
        : (cityData?.label ?? '');

    final stops = day != null
        ? resolveDayStops(day!, cityKey: dest?.city)
        : const <ResolvedStop>[];

    // Kamera merkezi: duraklar varsa CameraFit ile sınırlara oturur; tek durak
    // varsa o noktaya; hiç durak yoksa şehir merkezine (yoksa Japonya).
    final cityCenter = _cityCenter(dest, cityData);

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          '🗺️ Gün ${day?.dayNumber ?? '?'}'
          '${cityLabel.isNotEmpty ? ' · $cityLabel' : ''}',
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        backgroundColor: palette.card,
        foregroundColor: palette.textPrimary,
        elevation: 0,
      ),
      body: Stack(
        children: [
          _buildMap(context, stops, cityCenter),
          if (stops.isEmpty)
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: _EmptyBanner(palette: palette),
            ),
        ],
      ),
    );
  }

  Widget _buildMap(
    BuildContext context,
    List<ResolvedStop> stops,
    LatLng cityCenter,
  ) {
    final points = [for (final s in stops) LatLng(s.lat, s.lng)];

    final MapOptions options;
    if (points.length >= 2) {
      options = MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(48),
        ),
        minZoom: 3,
        maxZoom: 18,
      );
    } else if (points.length == 1) {
      options = MapOptions(
        initialCenter: points.first,
        initialZoom: 14,
        minZoom: 3,
        maxZoom: 18,
      );
    } else {
      options = MapOptions(
        initialCenter: cityCenter,
        initialZoom: cityCenter == _kJapanCenter ? 5 : 11,
        minZoom: 3,
        maxZoom: 18,
      );
    }

    return FlutterMap(
      options: options,
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.japantrip.app',
          maxZoom: 19,
          tileProvider: tileProvider,
        ),
        if (points.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                color: palette.fuji.withValues(alpha: 0.75),
                strokeWidth: 4,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (final stop in stops)
              Marker(
                point: LatLng(stop.lat, stop.lng),
                width: 34,
                height: 34,
                alignment: Alignment.center,
                child: _NumberedPin(
                  order: stop.order,
                  palette: palette,
                  onTap: () => _openStop(context, stop),
                ),
              ),
          ],
        ),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution(
              '© OpenStreetMap katkıda bulunanlar',
              onTap: () {},
            ),
          ],
        ),
      ],
    );
  }

  void _openStop(BuildContext context, ResolvedStop stop) {
    final dests = [...trip.preferences.destinations]
      ..sort((a, b) => a.order.compareTo(b.order));
    final dest =
        day != null ? getDestinationForDate(dests, day!.date) : null;
    final existing = trip.tickets
        .where((t) => t.label == stop.item.title)
        .cast<Ticket?>()
        .firstWhere((_) => true, orElse: () => null);
    showPlaceDetailSheet(
      context: context,
      item: stop.item,
      city: dest?.city ?? '',
      countryCode: dest?.countryCode,
      existingTicket: existing,
    );
  }

  /// Şehir merkezi: destinasyon lat/lng'si, yoksa küratörlü noktaların
  /// ortalaması, o da yoksa Japonya merkezi.
  LatLng _cityCenter(TripDestination? dest, CityData? cityData) {
    if (dest?.lat != null && dest?.lng != null) {
      return LatLng(dest!.lat!, dest.lng!);
    }
    if (cityData != null && cityData.places.isNotEmpty) {
      var lat = 0.0;
      var lng = 0.0;
      for (final p in cityData.places) {
        lat += p.lat;
        lng += p.lng;
      }
      final n = cityData.places.length;
      return LatLng(lat / n, lng / n);
    }
    return _kJapanCenter;
  }
}

/// Numaralı yuvarlak pin — palette.accent zemin, beyaz numara. Dokununca
/// yer detay popup'ını açar.
class _NumberedPin extends StatelessWidget {
  const _NumberedPin({
    required this.order,
    required this.palette,
    required this.onTap,
  });

  final int order;
  final ViewerPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: palette.accent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          '$order',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _EmptyBanner extends StatelessWidget {
  const _EmptyBanner({required this.palette});
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
          ),
        ],
      ),
      child: Text(
        'Bu güne haritada gösterilecek konumlu durak yok.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: palette.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
