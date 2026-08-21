// Animasyonlu rota haritası — "Haritada gör" butonunun açtığı modal sayfa.
//
// Neden ayrı bir ekran: `day_map_screen.dart` etkileşimli "çalışma" haritası;
// burada amaç rotayı ANLATMAK. Standart OSM raster zemini üzerinde:
//   1) Kamera açılışta tüm durakları içine alacak şekilde `CameraFit.bounds`,
//   2) Rota çizgisi baştan sona akıcı biçimde çizilir (tek AnimationController),
//   3) Çizgi bir durağa ulaştığında o durağın kırmızı pini elastik "pop" ile
//      belirir ve yerinde sabit kalır.
//
// Performans notu: tile katmanı animasyonun DIŞINDA kalır. Yalnızca
// Polyline/Marker katmanları `AnimatedBuilder` ile yeniden kurulur ve çizim
// bittiğinde animasyon tamamen durur — sürekli dönen hiçbir kontrolcü kalmaz,
// harita boşta CPU yakmaz.
//
// Koordinatlar `place_coords.dart` ile çözülür (üretilmiş öğelerde lat/lng
// çoğunlukla NULL olduğundan başlık küratörlü şehir noktalarıyla eşleştirilir).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/l10n.dart';
import '../../core/rotori_motion.dart';
import '../../data/google_maps_launcher.dart';
import '../../domain/city_places.dart';
import '../../domain/destination_profiles.dart';
import '../../domain/hotel_location.dart';
import '../../domain/place_coords.dart';
import '../../domain/place_image_resolver.dart';
import '../../domain/types.dart';
import '../shared/place_detail_sheet.dart';
import 'offline_tile_provider.dart';
import 'viewer_theme.dart';

/// Japonya kaba merkezi — şehir de duraklar da yoksa haritayı buraya odakla.
const LatLng _kJapanCenter = LatLng(36.2048, 138.2529);

/// Rota vurgu rengi — Japon kırmızısı. Sade zeminde tek doygun renk odur.
const Color kRouteAccent = Color(0xFFE23D4D);

/// Otel pini rengi — rotanın kırmızısından kasten AYRI. Otel bir "durak"
/// değil, günün başladığı yer; aynı renk olsaydı sıralı duraklarla karışırdı.
const Color kHotelAccent = Color(0xFF2E7D6B);

/// Bir rota bacağı için ayrılan çizim süresi. Toplam süre bacak sayısıyla
/// ölçeklenir ama [_kMinDrawMs]/[_kMaxDrawMs] arasında sıkışır: 2 duraklı gün
/// aceleye gelmesin, 12 duraklı gün de kullanıcıyı bekletmesin.
const int _kMsPerLeg = 620;
const int _kMinDrawMs = 1200;
const int _kMaxDrawMs = 5200;

/// Bir pinin "pop" animasyonunun toplam süreye oranı.
///
/// Çizgi, kontrolcünün `1 - _kPinAppearWindow` noktasında son durağa varır;
/// kalan pencere son pinin belirmesine ayrılır. Aksi halde son durak tam
/// bitiş anında tetiklenir ve hiç görünmeden animasyon durur.
const double _kPinAppearWindow = 0.12;

/// Pin dairesinin çapı.
const double _kPinSize = 30;

/// Pin gövdesinin kutusu — sıra rozeti daireden taştığı için biraz geniş.
/// Daire kutunun tam ortasında durur, dolayısıyla kutunun merkezi = pinin ucu.
const double _kPinBox = _kPinSize + 10;

/// Marker kutusu — pin ortada, ad etiketi altında. Kutu ne kadar genişse
/// etiket o kadar uzun yazılabilir; ama kutular çakışınca dokunma alanları da
/// çakışır, bu yüzden ölçülü tutuldu. Yükseklik, pinin ALTINDA etikete yer
/// kalacak şekilde seçilir: `height / 2 >= _kPinBox / 2 + etiket yüksekliği`.
const double _kMarkerWidth = 112;
const double _kMarkerHeight = 112;

/// Ad etiketlerinin görünmeye başladığı zoom — altında etiketler üst üste
/// biner, harita okunmaz olur.
const double _kLabelMinZoom = 11.5;

/// Fotoğraflı durak marker'larının görünmeye başladığı zoom. Şehir ölçeğinde
/// marker'ları sade tutar; kullanıcı durağa yaklaştığında görseli öne çıkarır.
const double _kPhotoMarkerMinZoom = 15;
const double _kPhotoMarkerSize = 46;

/// Zoom butonlarının adım büyüklüğü.
const double _kZoomStep = 1;

/// Duraklar arası kümülatif ilerleme oranları (0..1).
///
/// `out[i]`, çizgi `points[i]`'ye ulaştığı andaki animasyon ilerlemesidir;
/// `out.first == 0`, `out.last == 1`. Bacak uzunlukları coğrafi olarak
/// ölçülür (boylam farkı enlem kosinüsüyle düzeltilir) — böylece uzun bir
/// bacak kısa bir bacaktan daha uzun sürede çizilir.
///
/// Tüm noktalar üst üsteyse (toplam uzunluk 0) eşit aralık döner.
List<double> routeProgressStops(List<LatLng> points) {
  if (points.isEmpty) return const [];
  if (points.length == 1) return const [0.0];
  final legs = <double>[];
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    final len = _legLength(points[i - 1], points[i]);
    legs.add(len);
    total += len;
  }
  final out = <double>[0.0];
  if (total <= 0) {
    for (var i = 1; i < points.length; i++) {
      out.add(i / (points.length - 1));
    }
    return out;
  }
  var acc = 0.0;
  for (final len in legs) {
    acc += len;
    out.add(acc / total);
  }
  // Kayan nokta birikimini kapat — son değer tam 1.0 olsun.
  out[out.length - 1] = 1.0;
  return out;
}

/// [points] rotasının `t` (0..1) ilerlemesine kadar çizilmiş bölümü.
///
/// Son parça ara noktada kalıyorsa uçta enterpolasyonla bir nokta üretilir;
/// böylece çizgi durakların arasında "akıyor" görünür. `t <= 0` iken tek
/// nokta döner (çizilecek bacak yok).
List<LatLng> partialRoute(List<LatLng> points, double t) {
  if (points.length < 2) return List<LatLng>.of(points);
  final clamped = t.clamp(0.0, 1.0);
  if (clamped >= 1.0) return List<LatLng>.of(points);
  if (clamped <= 0.0) return [points.first];

  final stops = routeProgressStops(points);
  final out = <LatLng>[points.first];
  for (var i = 1; i < points.length; i++) {
    if (stops[i] <= clamped) {
      out.add(points[i]);
      continue;
    }
    final span = stops[i] - stops[i - 1];
    final local = span <= 0 ? 1.0 : (clamped - stops[i - 1]) / span;
    if (local > 0) {
      final a = points[i - 1];
      final b = points[i];
      out.add(
        LatLng(
          a.latitude + (b.latitude - a.latitude) * local,
          a.longitude + (b.longitude - a.longitude) * local,
        ),
      );
    }
    break;
  }
  return out;
}

/// İki nokta arasındaki yaklaşık düzlemsel uzaklık (derece cinsinden, boylam
/// enlem kosinüsüyle düzeltilmiş). Şehir ölçeğinde oran hesabı için yeterli;
/// haversine'e gerek yok.
double _legLength(LatLng a, LatLng b) {
  final dLat = b.latitude - a.latitude;
  final meanLat = (a.latitude + b.latitude) / 2 * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.cos(meanLat);
  return math.sqrt(dLat * dLat + dLng * dLng);
}

/// Animasyonlu gün rotası haritasını modal bottom sheet olarak açar.
///
/// [tileProvider] yalnızca testlerde verilir (ağ isteği bypass); üretimde
/// null → [RotoriTileProvider.shared].
Future<void> showRouteMapSheet({
  required BuildContext context,
  required Trip trip,
  required DayPlan day,
  TileProvider? tileProvider,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => RouteMapSheet(
      trip: trip,
      day: day,
      tileProvider: tileProvider,
    ),
  );
}

/// Modal içeriği — paleti çözer, durakları hesaplar, responsive çerçeveyi kurar.
class RouteMapSheet extends ConsumerWidget {
  const RouteMapSheet({
    super.key,
    required this.trip,
    required this.day,
    this.tileProvider,
  });

  final Trip trip;
  final DayPlan day;
  final TileProvider? tileProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sheet, Navigator overlay'inde ViewerPaletteScope'un ÜSTÜNDE açılır;
    // paleti bu yüzden provider'dan okuyup kendi scope'umuzu kuruyoruz.
    final palette = ref.watch(viewerPaletteProvider);
    final s = LanguageScope.of(context);

    final dests = [...trip.preferences.destinations]
      ..sort((a, b) => a.order.compareTo(b.order));
    final dest = getDestinationForDate(dests, day.date);
    final cityData = cityDataForKey(dest?.city);
    final cityCenter = _cityCenter(dest, cityData);
    final cityLabel =
        dest?.city.isNotEmpty == true ? dest!.city : (cityData?.label ?? '');

    final stops = resolveDayStops(
      day,
      cityKey: dest?.city,
      fallbackLat: cityCenter.latitude,
      fallbackLng: cityCenter.longitude,
    );

    // Günün başladığı yer. Koordinat çözülemezse (kısa maps.app.goo.gl linki
    // gibi) pin gösterilmez — oteli yanlış yerde göstermektense hiç
    // göstermemek doğru: kullanıcı sabah oraya yürümeye kalkar.
    final hotel = hotelForDate(trip.hotels, day.date);
    final hotelPoint = hotel == null ? null : hotelCoords(hotel);

    final media = MediaQuery.of(context);
    // Alçak ekranlarda haritaya daha fazla yer bırak; tablet/web'de sheet'i
    // ortalayıp genişliğini sınırla (tam ekrana yayılan harita hantal durur).
    final heightFactor = media.size.height < 700 ? 0.94 : 0.88;

    return Theme(
      data: palette.toThemeData(),
      child: ViewerPaletteScope(
        palette: palette,
        // heightFactor: 1 → sheet çocuğunun boyunu sarar; üstte kalan alan
        // barrier olarak dokunulabilir kalır (dışına dokunup kapatma çalışır).
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 720,
              maxHeight: media.size.height * heightFactor,
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: Container(
                color: palette.bg,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SheetHeader(
                      palette: palette,
                      title: s.p('map.dayTitle', {'day': '${day.dayNumber}'}),
                      subtitle: [
                        if (cityLabel.isNotEmpty) cityLabel,
                        if (stops.isNotEmpty)
                          s.p('map.stopsCount', {'count': '${stops.length}'}),
                      ].join(' · '),
                      onClose: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: AnimatedRouteMap(
                        trip: trip,
                        day: day,
                        stops: stops,
                        cityCenter: cityCenter,
                        cityLabel: cityLabel,
                        destination: dest,
                        palette: palette,
                        tileProvider: tileProvider,
                        hotel: hotel,
                        hotelPoint: hotelPoint == null
                            ? null
                            : LatLng(hotelPoint.lat, hotelPoint.lng),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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

/// Sade zemin + sırayla çizilen rota + sabit kırmızı duraklar.
class AnimatedRouteMap extends StatefulWidget {
  const AnimatedRouteMap({
    super.key,
    required this.trip,
    required this.day,
    required this.stops,
    required this.cityCenter,
    required this.cityLabel,
    required this.destination,
    required this.palette,
    this.tileProvider,
    this.hotel,
    this.hotelPoint,
  });

  final Trip trip;
  final DayPlan day;
  final List<ResolvedStop> stops;
  final LatLng cityCenter;
  final String cityLabel;
  final TripDestination? destination;
  final ViewerPalette palette;
  final TileProvider? tileProvider;

  /// O gün kalınan otel — varsa haritada günün başlangıç noktası olarak
  /// gösterilir. Rotanın numaralı durakları arasına GİRMEZ.
  final HotelStay? hotel;

  /// Otelin çözülmüş koordinatı. Otel var ama koordinatı çözülemediyse null
  /// olur ve pin gizlenir.
  final LatLng? hotelPoint;

  @override
  State<AnimatedRouteMap> createState() => _AnimatedRouteMapState();
}

class _AnimatedRouteMapState extends State<AnimatedRouteMap>
    with SingleTickerProviderStateMixin {
  /// Rota çizim ilerlemesi (0..1) — polyline ve pin belirme sırasını sürer.
  late final AnimationController _drawCtrl;

  bool _reduceMotion = false;
  bool _motionConfigured = false;

  final MapController _mapCtrl = MapController();

  late List<LatLng> _points;
  late List<double> _stopFractions;

  @override
  void initState() {
    super.initState();
    _recomputeRoute();
    _drawCtrl = AnimationController(
      vsync: this,
      duration: _drawDuration(),
    );
    if (_points.length < 2) {
      // Tek durak (ya da hiç): çizecek bacak yok, pin hemen görünsün.
      _drawCtrl.value = 1.0;
    } else {
      // İlk kareden sonra başlat: sheet'in giriş animasyonu ile çakışmasın
      // ve harita ilk layout'unu (fitBounds) yapmış olsun.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_reduceMotion) _drawCtrl.forward();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextReduceMotion = RotoriMotion.reduce(context);
    if (_motionConfigured && nextReduceMotion == _reduceMotion) return;

    _motionConfigured = true;
    _reduceMotion = nextReduceMotion;
    if (_reduceMotion) {
      _drawCtrl
        ..stop()
        ..duration = Duration.zero
        ..value = 1.0;
    } else {
      _drawCtrl.duration = _drawDuration();
      if (_points.length >= 2 && _drawCtrl.value == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_reduceMotion) _drawCtrl.forward();
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.stops, widget.stops)) {
      _recomputeRoute();
      _drawCtrl.duration = _reduceMotion ? Duration.zero : _drawDuration();
      if (_reduceMotion) _drawCtrl.value = 1.0;
    }
  }

  void _recomputeRoute() {
    _points = [for (final s in widget.stops) LatLng(s.lat, s.lng)];
    _stopFractions = routeProgressStops(_points);
  }

  Duration _drawDuration() {
    final legs = math.max(1, _points.length - 1);
    final ms = (legs * _kMsPerLeg).clamp(_kMinDrawMs, _kMaxDrawMs);
    // Son pinin pop penceresi kadar uzat — bacak temposu bozulmasın.
    return Duration(milliseconds: (ms / (1 - _kPinAppearWindow)).round());
  }

  /// Çizgi ilerlemesi — kontrolcü `1 - _kPinAppearWindow`'a geldiğinde rota
  /// tamamlanır, kalan pencerede yalnızca son pin belirir.
  double get _lineProgress =>
      (_drawCtrl.value / (1 - _kPinAppearWindow)).clamp(0.0, 1.0);

  @override
  void dispose() {
    _drawCtrl.dispose();
    super.dispose();
  }

  ViewerPalette get palette => widget.palette;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final provider = widget.tileProvider ?? RotoriTileProvider.shared;

    return Stack(
      children: [
        Positioned.fill(child: _buildMap(provider)),
        if (widget.stops.isEmpty)
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: _EmptyBanner(palette: palette),
          ),
        Positioned(
          right: 12,
          top: 12,
          child: _ZoomControls(
            palette: palette,
            onZoomIn: () => _zoomBy(_kZoomStep),
            onZoomOut: () => _zoomBy(-_kZoomStep),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: _MapActionBar(
            palette: palette,
            canReplay: _points.length >= 2,
            onReplay: _replay,
            onFit: _fitToRoute,
            onOpenGoogleMaps: _openInGoogleMaps,
            attribution: s.s('map.minimalAttribution'),
          ),
        ),
      ],
    );
  }

  Widget _buildMap(TileProvider provider) {
    // Otel de kadraja girsin — aksi halde kamera duraklara sığar ve günün
    // başladığı yer ekranın dışında kalır.
    final framed = <LatLng>[
      ..._points,
      if (widget.hotelPoint != null) widget.hotelPoint!,
    ];

    final MapOptions options;
    if (framed.length >= 2) {
      options = MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(framed),
          padding: const EdgeInsets.fromLTRB(56, 56, 56, 96),
        ),
        minZoom: 3,
        maxZoom: 18,
        interactionOptions: const InteractionOptions(
          // Döndürme kapalı: rota okunurluğu kuzey-yukarı hizada kalsın.
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      );
    } else if (framed.length == 1) {
      options = MapOptions(
        initialCenter: framed.first,
        initialZoom: 14,
        minZoom: 3,
        maxZoom: 18,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      );
    } else {
      options = MapOptions(
        initialCenter: widget.cityCenter,
        initialZoom: widget.cityCenter == _kJapanCenter ? 5 : 11,
        minZoom: 3,
        maxZoom: 18,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      );
    }

    return FlutterMap(
      mapController: _mapCtrl,
      options: options,
      children: [
        TileLayer(
          // Standart OSM raster katmanı. Toplu indirme ve disk cache yoktur.
          urlTemplate: kRotoriTileUrlTemplate,
          userAgentPackageName: 'com.mennansevim.rotori',
          maxZoom: 19,
          tileProvider: provider,
        ),
        // Yalnızca rota katmanı her karede yeniden kurulur; tile katmanı bu
        // AnimatedBuilder'ın dışında kalır ve yeniden inşa edilmez.
        AnimatedBuilder(
          animation: _drawCtrl,
          builder: (_, __) => _buildRouteLayer(),
        ),
        AnimatedBuilder(
          animation: _drawCtrl,
          builder: (_, __) => _buildMarkerLayer(),
        ),
      ],
    );
  }

  /// Otelden ilk durağa giden kesikli "çıkış bacağı".
  ///
  /// Kesikli çünkü bu bir rota adımı değil, günün nereden başladığını anlatan
  /// bağlam: kullanıcı sabah otelden çıkıp ilk durağa gidiyor. Düz çizgi
  /// olsaydı numaralı rotanın bir parçası sanılırdı.
  Polyline? _hotelLeg() {
    final hp = widget.hotelPoint;
    if (hp == null || _points.isEmpty) return null;
    return Polyline(
      points: [hp, _points.first],
      color: kHotelAccent.withValues(alpha: 0.75),
      strokeWidth: 3,
      pattern: StrokePattern.dashed(segments: const [7, 6]),
      strokeCap: StrokeCap.round,
    );
  }

  Widget _buildRouteLayer() {
    final hotelLeg = _hotelLeg();
    if (_points.length < 2) {
      // Tek durak (ya da hiç) olsa bile otel bağlantısı anlamlı.
      return hotelLeg == null
          ? const SizedBox.shrink()
          : PolylineLayer(polylines: [hotelLeg]);
    }
    final drawn = partialRoute(_points, _lineProgress);
    if (drawn.length < 2) {
      return hotelLeg == null
          ? const SizedBox.shrink()
          : PolylineLayer(polylines: [hotelLeg]);
    }
    return PolylineLayer(
      polylines: [
        if (hotelLeg != null) hotelLeg,
        // Henüz çizilmemiş bölüm hayalet olarak durur — kullanıcı rotanın
        // nereye gideceğini baştan sezer, çizgi "boşluğa" akmaz.
        if (_lineProgress < 1.0)
          Polyline(
            points: _points,
            color: kRouteAccent.withValues(alpha: 0.16),
            strokeWidth: 3,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        Polyline(
          points: drawn,
          color: kRouteAccent,
          strokeWidth: 4.5,
          // Sade zeminde bile çizgi kaybolmasın diye ince beyaz kenarlık.
          borderColor: Colors.white.withValues(alpha: 0.9),
          borderStrokeWidth: 2.5,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      ],
    );
  }

  Widget _buildMarkerLayer() {
    final progress = _drawCtrl.value;
    final lineProgress = _lineProgress;
    final drawing =
        lineProgress > 0 && lineProgress < 1.0 && _points.length >= 2;
    final head = drawing ? partialRoute(_points, lineProgress).last : null;

    return MarkerLayer(
      markers: [
        // Otel — numaralı durakların ALTINDA çizilir (listede önce gelir), ki
        // aynı noktaya denk gelirse rota durağı üstte kalsın.
        if (widget.hotelPoint != null && widget.hotel != null)
          Marker(
            point: widget.hotelPoint!,
            width: _kMarkerWidth,
            height: _kMarkerHeight,
            alignment: Alignment.center,
            child: _HotelPin(
              hotel: widget.hotel!,
              palette: palette,
              onTap: _openHotel,
            ),
          ),
        // Çizginin ucundaki akan nokta — hareketin nereye gittiğini gösterir.
        if (head != null)
          Marker(
            point: head,
            width: 18,
            height: 18,
            alignment: Alignment.center,
            child: const _RouteHeadDot(),
          ),
        for (var i = 0; i < widget.stops.length; i++)
          Marker(
            point: _points[i],
            // Kutu, pin + altındaki ad etiketini birlikte sarar; nokta
            // kutunun MERKEZİNDE, yani pinin tam ortasında durur.
            width: _kMarkerWidth,
            height: _kMarkerHeight,
            alignment: Alignment.center,
            child: _RouteStopPin(
              stop: widget.stops[i],
              appear: _appearProgress(i, progress),
              onTap: () => _openStop(widget.stops[i]),
            ),
          ),
      ],
    );
  }

  /// `i`. durağın belirme ilerlemesi (0..1). Çizgi durağa ulaştığı anda
  /// başlar, [_kPinAppearWindow] kadarlık bir pencerede tamamlanır. İlk durak
  /// (fraction 0) animasyonun ilk penceresinde belirir — çizgi zaten oradan
  /// başlar.
  double _appearProgress(int i, double progress) {
    if (i >= _stopFractions.length) return 1.0;
    final start = _stopFractions[i] * (1 - _kPinAppearWindow);
    return ((progress - start) / _kPinAppearWindow).clamp(0.0, 1.0);
  }

  void _replay() {
    _drawCtrl
      ..reset()
      ..forward();
  }

  /// Kamerayı merkezi koruyarak [delta] kadar yakınlaştırır/uzaklaştırır.
  /// MapOptions'taki min/max sınırlarına klamplanır.
  void _zoomBy(double delta) {
    final camera = _mapCtrl.camera;
    final next = (camera.zoom + delta)
        .clamp(camera.minZoom ?? 3, camera.maxZoom ?? 18)
        .toDouble();
    if (next == camera.zoom) return;
    _mapCtrl.move(camera.center, next);
  }

  void _fitToRoute() {
    if (_points.length >= 2) {
      _mapCtrl.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(_points),
          padding: const EdgeInsets.fromLTRB(56, 56, 56, 96),
        ),
      );
      return;
    }
    _mapCtrl.move(
      _points.isNotEmpty ? _points.first : widget.cityCenter,
      _points.isNotEmpty ? 14 : 11,
    );
  }

  void _openStop(ResolvedStop stop) {
    final existing = widget.trip.tickets
        .where((t) => t.label == stop.item.title)
        .cast<Ticket?>()
        .firstWhere((_) => true, orElse: () => null);
    showPlaceDetailSheet(
      context: context,
      item: stop.item,
      city: widget.destination?.city ?? '',
      countryCode: widget.destination?.countryCode,
      existingTicket: existing,
    );
  }

  /// Otel pinine dokunma — oteli Google Maps'te açar. Kullanıcının otelden
  /// çıkarken isteyeceği tek şey yol tarifidir; ayrı bir detay sayfası
  /// göstermek araya gereksiz bir adım koyardı.
  Future<void> _openHotel() async {
    final hotel = widget.hotel;
    final point = widget.hotelPoint;
    if (hotel == null || point == null) return;
    await openGoogleMapsPoint(
      lat: point.latitude,
      lng: point.longitude,
      label: hotel.name,
    );
  }

  /// Günün duraklarını Google Maps'te aç — turn-by-turn navigasyon isteyen
  /// kullanıcı için kaçış kapısı (uygulama içi harita okuma modudur).
  Future<void> _openInGoogleMaps() async {
    final messenger = ScaffoldMessenger.of(context);
    final s = LanguageScope.of(context);
    final stops = widget.stops;

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
      lat: widget.cityCenter.latitude,
      lng: widget.cityCenter.longitude,
      label: widget.cityLabel.isNotEmpty ? widget.cityLabel : null,
    );
    if (!mounted) return;
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(s.s('map.openFailed'))));
    }
  }
}

/// Sheet başlığı — sürükleme tutamağı, gün/şehir bilgisi, kapatma.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final ViewerPalette palette;
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: palette.borderStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close),
                color: palette.textSecondary,
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Harita sağ üstündeki dikey yakınlaştırma kontrolü. Pinch/çift dokunuş
/// zaten açık; bu, tek elle ve masaüstünde kesin adımlı zoom sağlar.
class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.palette,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final ViewerPalette palette;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.card.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(
            key: const ValueKey('route-map-zoom-in'),
            palette: palette,
            icon: Icons.add,
            tooltip: LanguageScope.of(context).s('map.zoomIn'),
            onTap: onZoomIn,
          ),
          Container(width: 26, height: 1, color: palette.border),
          _ZoomButton(
            key: const ValueKey('route-map-zoom-out'),
            palette: palette,
            icon: Icons.remove,
            tooltip: LanguageScope.of(context).s('map.zoomOut'),
            onTap: onZoomOut,
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    super.key,
    required this.palette,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final ViewerPalette palette;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 40,
          height: 38,
          child: Icon(icon, size: 19, color: palette.textPrimary),
        ),
      ),
    );
  }
}

/// Harita üstündeki yüzen aksiyon barı — tekrar oynat, rotaya sığdır,
/// Google Maps'te aç. Altında zorunlu OSM atfı.
class _MapActionBar extends StatelessWidget {
  const _MapActionBar({
    required this.palette,
    required this.canReplay,
    required this.onReplay,
    required this.onFit,
    required this.onOpenGoogleMaps,
    required this.attribution,
  });

  final ViewerPalette palette;
  final bool canReplay;
  final VoidCallback onReplay;
  final VoidCallback onFit;
  final VoidCallback onOpenGoogleMaps;
  final String attribution;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: palette.card.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              if (canReplay) ...[
                _BarButton(
                  key: const ValueKey('route-map-replay'),
                  palette: palette,
                  icon: Icons.replay,
                  label: s.s('map.replay'),
                  onTap: onReplay,
                ),
                const SizedBox(width: 5),
              ],
              _BarButton(
                key: const ValueKey('route-map-fit'),
                palette: palette,
                icon: Icons.center_focus_strong_outlined,
                label: s.s('map.fitRoute'),
                onTap: onFit,
              ),
              const SizedBox(width: 5),
              _BarButton(
                key: const ValueKey('route-map-google'),
                palette: palette,
                icon: Icons.navigation_outlined,
                label: s.s('map.navigate'),
                onTap: onOpenGoogleMaps,
                emphasized: true,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            attribution,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    super.key,
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });

  final ViewerPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final fg = emphasized ? Colors.white : palette.textPrimary;
    return Expanded(
      child: Material(
        color: emphasized ? kRouteAccent : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
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

/// Kırmızı durak pini — çizgi ulaştığında kısa bir "pop" ile belirir ve
/// ORADA SABİT KALIR (sürekli dönen bir animasyonu yoktur; harita üzerinde
/// titreşen nokta okumayı zorlaştırıyordu). Pin gövdesinde durağın emoji/tür
/// ikonu, hemen altında (yakınlaşınca) durağın adı görünür.
class _RouteStopPin extends StatelessWidget {
  const _RouteStopPin({
    required this.stop,
    required this.appear,
    required this.onTap,
  });

  final ResolvedStop stop;

  /// 0..1 — belirme ilerlemesi (0 iken pin hiç çizilmez).
  final double appear;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (appear <= 0) return const SizedBox.shrink();
    // easeOutBack: hafif bir "pop" verir ama elasticOut gibi salınmadan
    // oturur — pin yerleştikten sonra tamamen sabit kalır.
    final scale = Curves.easeOutBack.transform(appear);
    // Ad etiketi yalnızca şehir ölçeğinde ve üstünde — uzaklaşınca etiketler
    // üst üste binip haritayı okunmaz hale getirir.
    final zoom = MapCamera.maybeOf(context)?.zoom ?? 0;
    final imageUrl = _curatedImageUrl(stop);
    final showPhoto = imageUrl != null && zoom >= _kPhotoMarkerMinZoom;
    final showLabel = zoom >= _kLabelMinZoom && !showPhoto;

    return Opacity(
      // Opaklık ölçekten hızlı dolar; pin daha büyümesini bitirmeden nettir.
      opacity: (appear * 2.2).clamp(0.0, 1.0),
      // Column DEĞİL Stack: etiket yüksekliği yazı tipi metriklerine göre
      // platformdan platforma birkaç piksel oynar ve Column bunu "overflow"
      // hatası sayardı. Stack'te pin daima kutunun merkezinde (= coğrafi
      // nokta) durur, etiket onun altına konumlanır.
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (showLabel)
            Positioned(
              top: _kMarkerHeight / 2 + _kPinBox / 2 + 4,
              left: 0,
              right: 0,
              // Etiket dokunmayı yutmasın: harita sürüklemesi etiketin
              // üzerinden de çalışsın, dokunma yalnızca pinde olsun.
              child: IgnorePointer(
                child: Center(child: _StopLabel(text: stop.item.title)),
              ),
            ),
          Transform.scale(
            key: ValueKey('route-stop-${stop.order}'),
            scale: scale,
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: showPhoto
                  ? _PhotoPinCore(stop: stop, imageUrl: imageUrl)
                  : _PinCore(stop: stop),
            ),
          ),
        ],
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

/// Yalnızca önceden küratörlenmiş görselleri kullanır; harita pan/zoom
/// sırasında yeni Wikipedia araması başlatmaz.
class _PhotoPinCore extends StatelessWidget {
  const _PhotoPinCore({required this.stop, required this.imageUrl});

  final ResolvedStop stop;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: stop.item.title,
      button: true,
      child: SizedBox(
        width: _kPhotoMarkerSize + 2,
        height: _kPhotoMarkerSize + 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 1,
              top: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  width: _kPhotoMarkerSize,
                  height: _kPhotoMarkerSize,
                  decoration: BoxDecoration(
                    color: Colors.white,
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
                    errorBuilder: (_, __, ___) => _PinCore(stop: stop),
                  ),
                ),
              ),
            ),
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: kRouteAccent, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${stop.order}',
                  style: const TextStyle(
                    color: kRouteAccent,
                    fontWeight: FontWeight.w800,
                    fontSize: 9.5,
                    height: 1,
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

/// Pulse'tan bağımsız, sabit pin gövdesi — `AnimatedBuilder`'ın `child`'ı
/// olarak bir kez kurulur, her karede yeniden inşa edilmez.
///
/// Gövdede durağın türü (küratörlü nokta emojisi, yoksa `TimelineItemKind`
/// ikonu) durur; sıra numarası sağ üstteki küçük rozete taşınır — böylece hem
/// "burası ne" hem "kaçıncı durak" tek bakışta okunur.
class _PinCore extends StatelessWidget {
  const _PinCore({required this.stop});

  final ResolvedStop stop;

  @override
  Widget build(BuildContext context) {
    final emoji = stop.place?.emoji;
    return SizedBox(
      width: _kPinBox,
      height: _kPinBox,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 5,
            top: 5,
            child: Container(
              width: _kPinSize,
              height: _kPinSize,
              decoration: BoxDecoration(
                color: kRouteAccent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: kRouteAccent.withValues(alpha: 0.45),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: emoji != null && emoji.isNotEmpty
                  ? Text(
                      emoji,
                      style: const TextStyle(fontSize: 15, height: 1),
                    )
                  : Icon(
                      _kindIcon(stop.item.kind),
                      size: 16,
                      color: Colors.white,
                    ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: kRouteAccent, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                '${stop.order}',
                style: const TextStyle(
                  color: kRouteAccent,
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

IconData _kindIcon(TimelineItemKind? kind) => switch (kind) {
      TimelineItemKind.meal => Icons.restaurant,
      TimelineItemKind.transport => Icons.directions_transit,
      TimelineItemKind.hotel => Icons.hotel,
      _ => Icons.place,
    };

/// Pinin altındaki ad etiketi — sade zeminde okunur kalması için opak zemin
/// ve ince kenarlık. Uzun adlar tek satırda kısaltılır.
/// Günün başladığı otel pini.
///
/// Numaralı rota duraklarından üç şekilde ayrışır: yeşil renk, yuvarlak yerine
/// "ev" silueti veren damla form ve numara yerine yatak ikonu. Böylece
/// haritaya bakan biri onu bir durak sanmaz — "buradan çıkıyorum" der.
class _HotelPin extends StatelessWidget {
  const _HotelPin({
    required this.hotel,
    required this.palette,
    required this.onTap,
  });

  final HotelStay hotel;
  final ViewerPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zoom = MapCamera.maybeOf(context)?.zoom ?? 0;
    final showLabel = zoom >= _kLabelMinZoom;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (showLabel)
          Positioned(
            top: _kMarkerHeight / 2 + _kPinBox / 2 + 4,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(child: _StopLabel(text: hotel.name)),
            ),
          ),
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: _kPinBox,
            height: _kPinBox,
            child: Center(
              child: Container(
                width: _kPinSize,
                height: _kPinSize,
                decoration: BoxDecoration(
                  color: kHotelAccent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.hotel_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StopLabel extends StatelessWidget {
  const _StopLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = ViewerPalette.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: _kMarkerWidth),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: palette.card.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
      ),
    );
  }
}

/// Çizginin ucundaki akan nokta — yalnızca çizim sürerken görünür.
class _RouteHeadDot extends StatelessWidget {
  const _RouteHeadDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: kRouteAccent, width: 4),
        boxShadow: [
          BoxShadow(
            color: kRouteAccent.withValues(alpha: 0.5),
            blurRadius: 10,
          ),
        ],
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
