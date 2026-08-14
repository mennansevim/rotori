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
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import '../../data/google_maps_launcher.dart';
import '../../domain/city_places.dart';
import '../../domain/destination_profiles.dart';
import '../../domain/place_coords.dart';
import '../../domain/types.dart';
import '../shared/place_detail_sheet.dart';
import 'offline_tile_provider.dart';
import 'viewer_theme.dart';

/// Japonya kaba merkezi — şehir de duraklar da yoksa haritayı buraya odakla.
const LatLng _kJapanCenter = LatLng(36.2048, 138.2529);
const Color _kRouteRed = Color(0xFFE23D4D);

class DayMapScreen extends ConsumerWidget {
  const DayMapScreen({
    super.key,
    required this.trip,
    required this.dayNumber,
    this.tileProvider,
    this.onBack,
  });

  final Trip trip;
  final int dayNumber;
  final VoidCallback? onBack;

  /// Test'lerde ağ tile isteğini bypass etmek için enjekte edilir; üretimde
  /// null → [RotoriTileProvider.shared]. Testler ağ isteğini bypass etmek için
  /// kendi sağlayıcısını enjekte eder.
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
          onBack: onBack,
        ),
      ),
    );
  }
}

class _DayMapView extends StatefulWidget {
  const _DayMapView({
    required this.trip,
    required this.day,
    required this.palette,
    this.tileProvider,
    this.onBack,
  });

  final Trip trip;
  final DayPlan? day;
  final ViewerPalette palette;
  final TileProvider? tileProvider;
  final VoidCallback? onBack;

  @override
  State<_DayMapView> createState() => _DayMapViewState();
}

class _DayMapViewState extends State<_DayMapView> {
  // Prewarm ilerleme durumu — 0..1 arası; null iken overlay gizli.
  Trip get trip => widget.trip;
  DayPlan? get day => widget.day;
  ViewerPalette get palette => widget.palette;
  TileProvider? get tileProvider => widget.tileProvider;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final dests = [...trip.preferences.destinations]
      ..sort((a, b) => a.order.compareTo(b.order));
    final dest = day != null ? getDestinationForDate(dests, day!.date) : null;
    final cityData = cityDataForKey(dest?.city);
    final cityLabel =
        dest?.city.isNotEmpty == true ? dest!.city : (cityData?.label ?? '');
    // Kamera merkezi: duraklar varsa CameraFit ile sınırlara oturur; tek durak
    // varsa o noktaya; hiç durak yoksa şehir merkezine (yoksa Japonya).
    final cityCenter = _cityCenter(dest, cityData);

    final stops = day != null
        ? resolveDayStops(
            day!,
            cityKey: dest?.city,
            fallbackLat: cityCenter.latitude,
            fallbackLng: cityCenter.longitude,
          )
        : const <ResolvedStop>[];

    final effectiveProvider = tileProvider ?? RotoriTileProvider.shared;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        leading: BackButton(onPressed: _handleBack),
        title: Text(
          s.p('map.dayTitle', {'day': '${day?.dayNumber ?? '?'}'}) +
              (cityLabel.isNotEmpty ? ' · $cityLabel' : ''),
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        backgroundColor: palette.card,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        actions: [
          // Google Maps'te aç — bugünün duraklarını Google Maps'e taşır.
          // Duraklar varsa çoklu waypoint rota; yoksa şehir merkezini.
          IconButton(
            tooltip: s.s('map.openInGoogleMaps'),
            icon: const Icon(Icons.open_in_new),
            color: palette.textPrimary,
            onPressed: () => _openInGoogleMaps(stops, cityCenter, cityLabel),
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildMap(context, stops, cityCenter, effectiveProvider),
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

  void _handleBack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    widget.onBack?.call();
  }

  Widget _buildMap(
    BuildContext context,
    List<ResolvedStop> stops,
    LatLng cityCenter,
    TileProvider effectiveProvider,
  ) {
    final s = LanguageScope.of(context);
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
          // Standart OSM raster katmanı. Toplu indirme ve disk cache yoktur.
          urlTemplate: kRotoriTileUrlTemplate,
          userAgentPackageName: 'com.mennansevim.rotori',
          maxZoom: 19,
          tileProvider: effectiveProvider,
        ),
        if (points.length >= 2)
          PolylineLayer(
            polylines: [
              // Açık harita zemininde rota kaybolmasın: önce beyaz halo,
              // üstüne Japon kırmızısı ana çizgi.
              Polyline(
                points: points,
                color: Colors.white.withValues(alpha: 0.92),
                strokeWidth: 8,
              ),
              Polyline(
                points: points,
                color: _kRouteRed,
                strokeWidth: 4.5,
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
                  onTap: () => _openStop(context, stop),
                ),
              ),
          ],
        ),
        RichAttributionWidget(
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
    );
  }

  /// Bugünün duraklarını Google Maps'te aç. Durak sayısı:
  /// - 2+ → çoklu waypoint rota (`openGoogleMapsRoute`); ilk = origin,
  ///   son = destination, ara noktalar = waypoints (max 9).
  /// - 1 → tek nokta arama (`openGoogleMapsPoint`).
  /// - 0 → şehir merkezini gösteren tek nokta araması (kullanıcı hâlâ
  ///   Google Maps'te şehri görebilir).
  Future<void> _openInGoogleMaps(
    List<ResolvedStop> stops,
    LatLng cityCenter,
    String cityLabel,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final s = LanguageScope.of(context);
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
    // Boş gün — şehir merkezini aç (kullanıcı Google Maps'te en azından
    // Tokyo/Kyoto vs. konumunu görsün).
    final ok = await openGoogleMapsPoint(
      lat: cityCenter.latitude,
      lng: cityCenter.longitude,
      label: cityLabel.isNotEmpty ? cityLabel : null,
    );
    if (!mounted) return;
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(s.s('map.openFailed'))));
    }
  }

  void _openStop(BuildContext context, ResolvedStop stop) {
    final dests = [...trip.preferences.destinations]
      ..sort((a, b) => a.order.compareTo(b.order));
    final dest = day != null ? getDestinationForDate(dests, day!.date) : null;
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

/// Numaralı yuvarlak pin — rota kırmızısı zemin, beyaz numara. Dokununca
/// yer detay popup'ını açar.
class _NumberedPin extends StatelessWidget {
  const _NumberedPin({
    required this.order,
    required this.onTap,
  });

  final int order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        key: ValueKey('route-stop-$order'),
        decoration: BoxDecoration(
          color: _kRouteRed,
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
    final s = LanguageScope.of(context);
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
        s.s('map.emptyBanner'),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: palette.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
