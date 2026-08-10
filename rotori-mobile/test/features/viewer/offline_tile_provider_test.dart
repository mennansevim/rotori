// offline_tile_provider unit testleri — kritik olan Web Mercator tile x/y
// aralığı hesabıdır (ağ isteği yok, saf fonksiyon). CachingTileProvider'ın
// yapılandırılabilir olduğunu ve web'de prewarm'ın no-op olduğunu da
// doğrularız.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/features/viewer/offline_tile_provider.dart';

void main() {
  group('tileRange (Web Mercator)', () {
    test('z=0 → tek tile (0,0)', () {
      // Tüm dünya için z=0'da yalnızca 1 tile (2^0 = 1) vardır.
      final r = tileRange(
        south: -60,
        north: 60,
        west: -170,
        east: 170,
        zoom: 0,
      );
      expect(r.minX, 0);
      expect(r.maxX, 0);
      expect(r.minY, 0);
      expect(r.maxY, 0);
      expect(r.count, 1);
    });

    test('Tokyo yakın çevresi, z=13 → küçük bir aralık', () {
      // Tokyo ~35.68N, 139.65E civarı ~5x5 km kare.
      // z=13'te 1 tile ≈ 5km enlem — 1–3 tile beklenir.
      final r = tileRange(
        south: 35.66,
        north: 35.70,
        west: 139.63,
        east: 139.68,
        zoom: 13,
      );
      // Kaba doğrulama: aralık geçerli ve makul boyutta.
      expect(r.minX <= r.maxX, isTrue);
      expect(r.minY <= r.maxY, isTrue);
      expect(r.count, greaterThan(0));
      expect(r.count, lessThan(20));
      // z=13 için 8192 tile var; hepsi limitler içinde.
      const limit = (1 << 13) - 1;
      expect(r.minX, inInclusiveRange(0, limit));
      expect(r.maxX, inInclusiveRange(0, limit));
      expect(r.minY, inInclusiveRange(0, limit));
      expect(r.maxY, inInclusiveRange(0, limit));
    });

    test('Bilinen referans nokta — OpenStreetMap wiki (0,0) z=2', () {
      // wiki: lat=0, lon=0 → z=2'de tile (2, 2).
      final r = tileRange(
        south: -0.001,
        north: 0.001,
        west: -0.001,
        east: 0.001,
        zoom: 2,
      );
      // Ekvator/prime meridyen kesişimi tam olarak (2,2)'nin köşesi;
      // dar kutu ± civardaki karelere denk gelebilir. En azından 2'yi kapsamalı.
      expect(r.minX <= 2 && r.maxX >= 2, isTrue);
      expect(r.minY <= 2 && r.maxY >= 2, isTrue);
    });

    test('Ters sıralı bounds (min > max) düzeltilir', () {
      // Kullanıcı hatası olarak north<south gelirse fonksiyon takas eder.
      final r = tileRange(
        south: 35.70,
        north: 35.66, // ters
        west: 139.68,
        east: 139.63, // ters
        zoom: 12,
      );
      expect(r.minX <= r.maxX, isTrue);
      expect(r.minY <= r.maxY, isTrue);
      expect(r.count, greaterThan(0));
    });

    test('Kutupsal enlem klamplanır (Mercator tanım dışı)', () {
      // 89°N Mercator'da tanımsız; klamp sayesinde patlamamalı.
      final r = tileRange(
        south: 89.0,
        north: 89.5,
        west: 0.0,
        east: 1.0,
        zoom: 5,
      );
      const limit = (1 << 5) - 1;
      expect(r.minY, inInclusiveRange(0, limit));
      expect(r.maxY, inInclusiveRange(0, limit));
    });
  });

  group('CachingTileProvider', () {
    test('shared instance oluşur ve tekildir', () {
      final a = CachingTileProvider.shared;
      final b = CachingTileProvider.shared;
      expect(identical(a, b), isTrue);
    });

    test('yeni instance da yaratılabilir (test seam)', () {
      final p = CachingTileProvider();
      expect(p, isA<CachingTileProvider>());
    });

    test(
      'prewarmTiles web platformunda no-op — 0 döner',
      () async {
        // Bu test yalnızca web ortamında anlamlıdır; VM'de kIsWeb=false
        // olduğundan gerçek indirmeye kalkışır ve ağ olmadığında yavaş
        // olabilir. Bu yüzden yalnızca kIsWeb'de çalıştırırız.
        if (!kIsWeb) return;
        final count = await CachingTileProvider().prewarmTiles(
          south: 35.66,
          north: 35.67,
          west: 139.66,
          east: 139.67,
          minZoom: 12,
          maxZoom: 12,
        );
        expect(count, 0);
      },
    );

    test('prewarmTiles maxTiles limiti aşıldığında sessizce atlar', () async {
      // Çok geniş bir alan + yüksek zoom → binlerce tile.
      final count = await CachingTileProvider().prewarmTiles(
        south: -60,
        north: 60,
        west: -170,
        east: 170,
        minZoom: 12,
        maxZoom: 15,
        maxTiles: 10,
      );
      expect(count, 0);
    });
  });
}
