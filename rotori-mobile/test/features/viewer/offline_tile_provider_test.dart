import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/features/viewer/offline_tile_provider.dart';

void main() {
  group('RotoriTileProvider', () {
    test('shared instance tekildir', () {
      final a = RotoriTileProvider.shared;
      final b = RotoriTileProvider.shared;
      expect(identical(a, b), isTrue);
    });

    test('yeni instance test seam olarak yaratılabilir', () {
      final provider = RotoriTileProvider();
      expect(provider, isA<RotoriTileProvider>());
    });

    test('standart OSM URL ve attribution bağlantısı sabittir', () {
      expect(kRotoriTileUrlTemplate, contains('tile.openstreetmap.org'));
      expect(
        kOpenStreetMapCopyrightUrl,
        'https://www.openstreetmap.org/copyright',
      );
    });
  });
}
