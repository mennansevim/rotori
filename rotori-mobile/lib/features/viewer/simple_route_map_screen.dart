// Bağımsız (self-contained) gün rotası haritası.
//
// OpenStreetMap raster tile + flutter_map ile çalışır: API key yok, kredi
// kartı yok, tamamen ücretsiz. Verilen noktaları numaralı pinlerle gösterir,
// sıralı bir Polyline ile birbirine bağlar ve ekran ilk açıldığında bütün
// noktaları kadraja alacak şekilde otomatik ortalanır (CameraFit.bounds).
//
// Bu dosya kasıtlı olarak hiçbir Rotori domain tipine bağlı değildir; olduğu
// gibi başka bir projeye de taşınabilir. Bağımlılıklar sadece:
//   flutter_map: ^7.0.2
//   latlong2:    ^0.9.1
// (ikisi de pubspec.yaml'da zaten mevcut).

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// Neden CARTO, neden standart OSM değil?
// Standart `tile.openstreetmap.org` etiketleri her yerin YEREL dilinde basar
// (Japonya'da kanji) ve dil değiştirilemez. CARTO Voyager taban haritası da
// anahtarsız ve ücretsizdir AMA etiket dilini isteğin `Accept-Language`
// başlığına göre yerelleştirir: başlık `en`/`tr` gönderilince Latin isimler
// ("Kyoto", "Otsu") döner, başlık hiç gönderilmezse yerel isme (kanji) düşer.
// Bu yüzden tile isteğine daima açık bir Accept-Language ekliyoruz.
// Adil kullanım limitleri vardır; App Store ölçeğine çıkarken SLA'lı bir
// sağlayıcıya geçilmelidir.
const String _kTileUrl =
    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

/// CARTO'nun yük dağıtımı için kullandığı alt alan adları.
const List<String> _kTileSubdomains = ['a', 'b', 'c', 'd'];

/// Etiket dili gönderilmezse kullanılacak varsayılan (Latin isimler).
const String _kDefaultLabelLanguage = 'en';

/// Tile'ları işletim sisteminin görsel yükleyicisiyle çeken ve her isteğe
/// `Accept-Language` başlığı ekleyen sağlayıcı.
///
/// - Mobil (iOS/Android): başlık gönderilir → CARTO Latin etiket döner.
/// - Web (CanvasKit): tarayıcı `Accept-Language`'i worker fetch'inde forbidden
///   header olduğu için düşürebilir; bu durumda web önizlemesi yerel isim
///   gösterebilir. Yayınlanan mobil uygulama etkilenmez.
///
/// flutter_map'in varsayılan `NetworkTileProvider`'ı yerine bu kullanılır
/// (aynı gerekçe: web'de güvenilir çizim + başlık kontrolü).
class _LocalizedTileProvider extends TileProvider {
  _LocalizedTileProvider(this.languageCode);

  final String languageCode;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return NetworkImage(
      getTileUrl(coordinates, options),
      headers: {'Accept-Language': languageCode},
    );
  }
}

/// OSM kullanım şartlarının gerektirdiği tanımlayıcı. Kendi paket adını yaz.
const String _kUserAgentPackageName = 'com.mennansevim.rotori';

/// Noktaların hiçbiri yoksa haritayı buraya odakla (Japonya kaba merkezi).
const LatLng _kFallbackCenter = LatLng(36.2048, 138.2529);

/// Rota rengi.
const Color _kRouteColor = Color(0xFFE23D4D);

/// Harita üzerinde gösterilecek tek bir durak.
class RoutePoint {
  const RoutePoint({
    required this.latitude,
    required this.longitude,
    required this.title,
    this.subtitle,
  });

  final double latitude;
  final double longitude;
  final String title;
  final String? subtitle;

  LatLng get latLng => LatLng(latitude, longitude);
}

/// Bir günün planlanan duraklarını OSM üzerinde gösteren hazır ekran.
///
/// Kullanım:
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => SimpleRouteMapScreen(
///     title: '2. Gün · Kyoto',
///     points: const [
///       RoutePoint(latitude: 35.0116, longitude: 135.7681, title: 'Kyoto İstasyonu'),
///       RoutePoint(latitude: 34.9671, longitude: 135.7727, title: 'Fushimi Inari'),
///       RoutePoint(latitude: 35.0394, longitude: 135.7292, title: 'Kinkaku-ji'),
///     ],
///   ),
/// ));
/// ```
class SimpleRouteMapScreen extends StatefulWidget {
  const SimpleRouteMapScreen({
    super.key,
    required this.points,
    this.title = 'Rota',
    this.tileUrl = _kTileUrl,
    this.tileSubdomains = _kTileSubdomains,
    this.labelLanguage = _kDefaultLabelLanguage,
    this.tileProvider,
  });

  /// Gün içinde gidilecek noktalar (ziyaret sırasına göre).
  final List<RoutePoint> points;

  /// AppBar başlığı.
  final String title;

  /// Taban harita tile URL şablonu. Varsayılan Latin etiketli CARTO Voyager.
  /// Japonca etiketli standart OSM istersen:
  /// `https://tile.openstreetmap.org/{z}/{x}/{y}.png` (o zaman [tileSubdomains]
  /// boş liste ver).
  final String tileUrl;

  /// [tileUrl] içindeki `{s}` için alt alan adları. `{s}` yoksa boş liste ver.
  final List<String> tileSubdomains;

  /// Harita etiketlerinin dili (`Accept-Language`). Uygulamanın seçili diline
  /// bağla — örn. `Localizations.localeOf(context).languageCode`. Japonya için
  /// hem `en` hem `tr` Latin isim döndürür.
  final String labelLanguage;

  /// Testlerde ağ isteğini bypass etmek için enjekte edilebilir. Üretimde
  /// null bırak → varsayılan ağ sağlayıcısı kullanılır.
  final TileProvider? tileProvider;

  @override
  State<SimpleRouteMapScreen> createState() => _SimpleRouteMapScreenState();
}

class _SimpleRouteMapScreenState extends State<SimpleRouteMapScreen> {
  final MapController _mapController = MapController();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final latLngs = [for (final p in points) p.latLng];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (latLngs.isNotEmpty)
            IconButton(
              tooltip: 'Rotaya sığdır',
              icon: const Icon(Icons.center_focus_strong),
              onPressed: () => _fitToPoints(latLngs),
            ),
        ],
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: _cameraOptions(latLngs),
        children: [
          // 1) Latin etiketli raster zemin katmanı (API key gerektirmez).
          TileLayer(
            urlTemplate: widget.tileUrl,
            subdomains: widget.tileSubdomains,
            userAgentPackageName: _kUserAgentPackageName,
            maxZoom: 19,
            tileProvider: widget.tileProvider ??
                _LocalizedTileProvider(widget.labelLanguage),
          ),

          // 2) Noktalar arası rota çizgisi. Açık zeminde çizgi kaybolmasın
          //    diye önce beyaz halo, üstüne kırmızı ana çizgi çizilir.
          if (latLngs.length >= 2)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: latLngs,
                  color: Colors.white.withValues(alpha: 0.9),
                  strokeWidth: 8,
                ),
                Polyline(
                  points: latLngs,
                  color: _kRouteColor,
                  strokeWidth: 4.5,
                ),
              ],
            ),

          // 3) Numaralı pinler — dokununca alt bilgi kartı açar.
          MarkerLayer(
            markers: [
              for (var i = 0; i < points.length; i++)
                Marker(
                  point: points[i].latLng,
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  child: _NumberedPin(
                    order: i + 1,
                    onTap: () => _showPointSheet(context, points[i], i + 1),
                  ),
                ),
            ],
          ),

          // 4) Lisans atıfı (kullanım şartı gereği zorunlu).
          const RichAttributionWidget(
            attributions: [
              TextSourceAttribution('© OpenStreetMap · © CARTO'),
            ],
          ),
        ],
      ),
    );
  }

  /// İlk açılışta kameranın nereye/nasıl oturacağını belirler.
  /// - 2+ nokta → hepsini kadraja alan sınırlara (CameraFit.bounds) otur.
  /// - 1 nokta → o noktaya yakın zoom ile odaklan.
  /// - 0 nokta → varsayılan merkez.
  MapOptions _cameraOptions(List<LatLng> latLngs) {
    if (latLngs.length >= 2) {
      return MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(latLngs),
          padding: const EdgeInsets.all(56),
        ),
        minZoom: 3,
        maxZoom: 18,
      );
    }
    if (latLngs.length == 1) {
      return MapOptions(
        initialCenter: latLngs.first,
        initialZoom: 14,
        minZoom: 3,
        maxZoom: 18,
      );
    }
    return const MapOptions(
      initialCenter: _kFallbackCenter,
      initialZoom: 5,
      minZoom: 3,
      maxZoom: 18,
    );
  }

  /// Kullanıcı harita üzerinde gezindikten sonra tekrar tüm noktalara sığdırır.
  void _fitToPoints(List<LatLng> latLngs) {
    if (latLngs.isEmpty) return;
    if (latLngs.length == 1) {
      _mapController.move(latLngs.first, 14);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(latLngs),
        padding: const EdgeInsets.all(56),
      ),
    );
  }

  void _showPointSheet(BuildContext context, RoutePoint point, int order) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _kRouteColor,
                  radius: 16,
                  child: Text(
                    '$order',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    point.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (point.subtitle != null && point.subtitle!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(point.subtitle!),
            ],
            const SizedBox(height: 12),
            Text(
              '${point.latitude.toStringAsFixed(5)}, '
              '${point.longitude.toStringAsFixed(5)}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Numaralı yuvarlak pin — kırmızı zemin, beyaz numara.
class _NumberedPin extends StatelessWidget {
  const _NumberedPin({required this.order, required this.onTap});

  final int order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _kRouteColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
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
            fontSize: 16,
            height: 1,
          ),
        ),
      ),
    );
  }
}
