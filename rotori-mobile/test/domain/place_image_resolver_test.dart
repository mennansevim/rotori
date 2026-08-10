import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/place_image_resolver.dart';

void main() {
  group('PlaceImageResolver', () {
    test('küratörlü yer için görsel senkron döner (ağ yok)', () async {
      // Senso-ji place_guide.dart'ta küratörlü — peekCurated non-null olmalı.
      final urls = PlaceImageResolver.instance.peekCurated('Senso-ji Asakusa');
      expect(urls, isNotNull);
      expect(urls!, isNotEmpty);
      expect(urls.first, startsWith('http'));
    });

    test('küratörlü resolve anında (aynı frame) tamamlanır', () async {
      final urls =
          await PlaceImageResolver.instance.resolve('Senso-ji Asakusa');
      expect(urls, isNotEmpty);
    });

    test('eşleşmeyen başlıkta peekCurated null', () {
      final urls = PlaceImageResolver.instance
          .peekCurated('Zzz Olmayan Yer 12345');
      expect(urls, isNull);
    });

    test('boş başlık boş liste döndürür (ağ denemez)', () async {
      final urls = await PlaceImageResolver.instance.resolve('   ');
      expect(urls, isEmpty);
    });

    test('küratörlü sonuç büyük/küçük harf duyarsız eşleşir', () {
      final a = PlaceImageResolver.instance.peekCurated('SENSO-JI ASAKUSA');
      final b = PlaceImageResolver.instance.peekCurated('senso-ji asakusa');
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a, equals(b));
    });
  });
}
