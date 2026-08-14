// Harita tile sağlayıcısı.
//
// Tile'lar yalnızca Flutter'ın oturum içi bellek cache'inde tutulur. Uygulama
// tüm rota alanını önceden indirmez ve kalıcı bir offline tile arşivi üretmez.
// Bu ayrım harita sağlayıcısının ön-getirme/depolama kurallarına uymak ve
// kullanıcıya garanti edilemeyen bir çevrimdışı harita vaat etmemek içindir.

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

/// Anahtarsız, düşük hacimli beta kullanımı için standart OSM raster katmanı.
/// App Store ölçeğine çıkmadan önce üretim SLA'sı olan bir sağlayıcıyla aynı
/// sabit üzerinden değiştirilebilir.
const String kRotoriTileUrlTemplate =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

const String kOpenStreetMapCopyrightUrl =
    'https://www.openstreetmap.org/copyright';

/// Ağ tile'larını yalnızca Flutter'ın standart ImageCache'i üzerinden kullanan
/// sağlayıcı. Disk cache ve toplu ön-indirme özellikle desteklenmez.
class RotoriTileProvider extends TileProvider {
  RotoriTileProvider({super.headers});

  static final RotoriTileProvider shared = RotoriTileProvider();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return NetworkImage(
      getTileUrl(coordinates, options),
      headers: headers,
    );
  }
}
