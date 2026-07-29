// Çevrimdışı tile cache sağlayıcısı — kullanıcı bir günün haritasını çevrimiçi
// açtığında OSM raster tile'ları yerel diske (iOS/Android) yazar; sonraki
// açılışlarda internet yoksa aynı kareler cache'ten yüklenir. Web'de
// (kIsWeb=true) `flutter_cache_manager` dosya API'si yoktur; bu durumda
// güvenli fallback olarak düz `NetworkImage` döneriz (çevrimdışı avantajı yok
// ama build + çevrimiçi görüntüleme çalışır).
//
// `prewarmTiles`: verilen sınırlar + zoom aralığı için tile x/y hücrelerini
// önceden indirir (max 400 kare — üstündeki durumlar sessizce atlanır). Web'de
// no-op.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_map/flutter_map.dart';

/// Web Mercator tile aralığı — [minX,maxX] x [minY,maxY] hücreleri.
class TileRangeXY {
  const TileRangeXY({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final int minX;
  final int maxX;
  final int minY;
  final int maxY;

  int get count => (maxX - minX + 1) * (maxY - minY + 1);
}

/// Web Mercator formülüyle bir bounds + zoom kombinasyonundan tile x/y
/// aralığını hesaplar. Ünite testinde saf fonksiyon olarak sınanır.
///
/// Not: `bounds.west`/`east` normalde -180..180; kutupsal enlemlerde
/// Mercator projeksiyonu tanımlı değildir → 85.05° civarına klamplanır.
TileRangeXY tileRange({
  required double south,
  required double north,
  required double west,
  required double east,
  required int zoom,
}) {
  assert(zoom >= 0 && zoom <= 22, 'zoom aralık dışı: $zoom');
  final n = 1 << zoom; // 2^zoom
  int xTile(double lng) => ((lng + 180.0) / 360.0 * n).floor();
  int yTile(double lat) {
    // Mercator kutup limitleri.
    final clamped = lat.clamp(-85.05112878, 85.05112878);
    final r = clamped * math.pi / 180.0;
    return ((1.0 - math.log(math.tan(r) + 1.0 / math.cos(r)) / math.pi) /
            2.0 *
            n)
        .floor();
  }

  var minX = xTile(west);
  var maxX = xTile(east);
  // Kuzey daha küçük y verir; sırayı düzelt.
  var minY = yTile(north);
  var maxY = yTile(south);
  if (minX > maxX) {
    final t = minX;
    minX = maxX;
    maxX = t;
  }
  if (minY > maxY) {
    final t = minY;
    minY = maxY;
    maxY = t;
  }
  final limit = n - 1;
  return TileRangeXY(
    minX: minX.clamp(0, limit),
    maxX: maxX.clamp(0, limit),
    minY: minY.clamp(0, limit),
    maxY: maxY.clamp(0, limit),
  );
}

/// OSM raster tile'larını yerel cache'e yazan/okuyan sağlayıcı.
///
/// [TileLayer.tileProvider] alanına verildiğinde:
/// - Mobil: `flutter_cache_manager` üzerinden diske yazar; sonradan
///   ağ olmasa bile aynı URL'ler cache'ten okunur.
/// - Web (`kIsWeb`): düz `NetworkImage` — çevrimdışı avantajı yok, ama
///   `flutter build web` kırılmaz.
class CachingTileProvider extends TileProvider {
  CachingTileProvider({super.headers});

  /// Uygulama boyunca tek bir cache instance yeter — day_map_screen bunu
  /// varsayılan olarak kullanır. (Test'ler kendi mock provider'ını enjekte
  /// eder, bu paylaşım onları etkilemez.)
  static final CachingTileProvider shared = CachingTileProvider();

  /// 30 gün TTL, max 500 tile — kaba bir üst sınır. `japan_trip_tiles`
  /// namespace'i başka cache'lerle çakışmasın diye ayrık.
  static final BaseCacheManager _cacheManager = CacheManager(
    Config(
      _kCacheKey,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 500,
    ),
  );

  static const String _kCacheKey = 'japan_trip_tiles_v1';

  /// TileLayer bunu her hücre için çağırır. Web'de NetworkImage'e düşeriz.
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    if (kIsWeb) {
      return NetworkImage(url);
    }
    return _CachedTileImageProvider(
      url: url,
      headers: headers,
      cacheManager: _cacheManager,
    );
  }

  /// Verilen [bounds] için [minZoom]..[maxZoom] aralığındaki tile'ları
  /// önceden indirir. Toplam tile sayısı [maxTiles]'i aşarsa sessizce atlar
  /// (kullanıcı çok geniş bir alan seçtiyse GB'lık indirmeye girmesin).
  ///
  /// Web'de no-op — 0 döner.
  Future<int> prewarmTiles({
    required double south,
    required double north,
    required double west,
    required double east,
    required int minZoom,
    required int maxZoom,
    String urlTemplate =
        'https://mt0.google.com/vt/lyrs=m&x={x}&y={y}&z={z}&hl=ja&gl=JP',
    void Function(int done, int total)? onProgress,
    int maxTiles = 400,
  }) async {
    if (kIsWeb) {
      // Web'de cache_manager IO API'lerine sahip değil — sessizce atla.
      return 0;
    }
    final ranges = <int, TileRangeXY>{};
    var total = 0;
    for (var z = minZoom; z <= maxZoom; z++) {
      final r = tileRange(
        south: south,
        north: north,
        west: west,
        east: east,
        zoom: z,
      );
      ranges[z] = r;
      total += r.count;
    }
    if (total == 0) return 0;
    if (total > maxTiles) {
      debugPrint(
        'CachingTileProvider.prewarmTiles: $total > $maxTiles, atlanıyor',
      );
      return 0;
    }
    var done = 0;
    for (var z = minZoom; z <= maxZoom; z++) {
      final r = ranges[z]!;
      for (var x = r.minX; x <= r.maxX; x++) {
        for (var y = r.minY; y <= r.maxY; y++) {
          final url = urlTemplate
              .replaceAll('{s}', '0')
              .replaceAll('{z}', '$z')
              .replaceAll('{x}', '$x')
              .replaceAll('{y}', '$y');
          try {
            await _cacheManager.downloadFile(url, authHeaders: headers);
          } catch (e) {
            // Tek bir tile'ın başarısızlığı toplu işlemi durdurmasın.
            debugPrint('prewarm tile başarısız $url: $e');
          }
          done++;
          onProgress?.call(done, total);
        }
      }
    }
    return done;
  }
}

/// Cache'ten dosya okuyan / gerekirse indiren `ImageProvider`. Yalnızca mobil
/// tarafta kullanılır (web'de üstteki provider NetworkImage'e düşer).
class _CachedTileImageProvider extends ImageProvider<_CachedTileImageProvider> {
  const _CachedTileImageProvider({
    required this.url,
    required this.headers,
    required this.cacheManager,
  });

  final String url;
  final Map<String, String> headers;
  final BaseCacheManager cacheManager;

  @override
  Future<_CachedTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: url,
    );
  }

  Future<ui.Codec> _loadAsync(
    _CachedTileImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final file = await cacheManager.getSingleFile(url, headers: headers);
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw StateError('boş tile: $url');
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(buffer);
    } catch (_) {
      // Cache miss + ağ yok → şeffaf 1x1 PNG döner; harita çökmesin.
      final buffer =
          await ui.ImmutableBuffer.fromUint8List(TileProvider.transparentImage);
      return decode(buffer);
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _CachedTileImageProvider && other.url == url;
  }

  @override
  int get hashCode => url.hashCode;
}
