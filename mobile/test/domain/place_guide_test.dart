import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/city_places.dart';
import 'package:japan_trip/domain/place_guide.dart';

void main() {
  test('Senso-ji anahtar kelime rehberi çözer', () {
    final g = matchPlaceGuide('Senso-ji Asakusa');
    expect(g, isNotNull);
    expect(g!.id, 'sensoji');
    expect(g.imageUrls, isNotEmpty);
    expect(g.tips, isNotEmpty);
  });

  test('teamLab Planets → teamlab guide', () {
    final g = matchPlaceGuide('teamLab Planets');
    expect(g?.id, 'teamlab');
    expect(g?.advanceBookingDays, 30);
  });

  test('USJ → usj guide', () {
    expect(matchPlaceGuide('Universal Studios Japan')?.id, 'usj');
    expect(matchPlaceGuide('USJ günü')?.id, 'usj');
  });

  test('Shinkansen anahtar kelime', () {
    expect(matchPlaceGuide('Tokyo → Kyoto · Shinkansen Nozomi')?.id,
        'shinkansen');
  });

  test('bilinmeyen yer null döner', () {
    expect(matchPlaceGuide('Random Cafe X'), isNull);
  });

  group('kapsama — tüm küratörlü yerler', () {
    test('her şehir noktasının bir rehberi var', () {
      final missing = <String>[];
      for (final city in kCityData) {
        for (final p in city.places) {
          if (matchPlaceGuide(p.name) == null) {
            missing.add('${city.label}: ${p.name}');
          }
        }
      }
      expect(missing, isEmpty,
          reason: 'Rehbersiz yerler: ${missing.join(', ')}');
    });

    test('rehberlerde temel alanlar dolu', () {
      for (final city in kCityData) {
        for (final p in city.places) {
          final g = matchPlaceGuide(p.name)!;
          expect(g.imageUrls, isNotEmpty, reason: '${p.name} görselsiz');
          expect(g.visitDurationMin, greaterThan(0));
          expect(g.brief.length, greaterThan(40),
              reason: '${p.name} tanıtımı çok kısa');
          expect(g.tips.length, greaterThanOrEqualTo(3),
              reason: '${p.name} için en az 3 ipucu olmalı');
          expect(g.bestTimeOfDay, isNotEmpty);
        }
      }
    });

    test('görseller Wikimedia\'nın izin verdiği thumb boyutlarında', () {
      // Wikimedia yalnız 250/500/960/1280px sunuyor; başka genişlik 400 döner.
      final badWidth = RegExp(r'/(?!250px|500px|960px|1280px)\d+px-');
      for (final city in kCityData) {
        for (final p in city.places) {
          for (final url in matchPlaceGuide(p.name)!.imageUrls) {
            expect(badWidth.hasMatch(url), isFalse,
                reason: 'Geçersiz thumb boyutu: $url');
          }
        }
      }
    });
  });

  group('nearbyCityPlaces — gerçek yakınlık', () {
    test('teamLab için yakın Tokyo yerleri mesafeye göre sıralı', () {
      final near = nearbyCityPlaces(title: 'teamLab Planets');
      expect(near, hasLength(3));
      expect(near.any((n) => n.place.id == 'tk-teamlab'), isFalse,
          reason: 'Yer kendini önermemeli');
      for (var i = 1; i < near.length; i++) {
        expect(near[i].distanceM, greaterThanOrEqualTo(near[i - 1].distanceM));
      }
      expect(near.first.distanceM, lessThan(5000),
          reason: 'Toyosu çevresinde 5 km içinde nokta olmalı');
    });

    test('koordinat verilince başlık eşleşmese de çalışır', () {
      final near =
          nearbyCityPlaces(title: 'Öğle molası', lat: 35.6595, lng: 139.7005);
      expect(near, isNotEmpty);
      // Shibuya koordinatından en yakın nokta Shibuya Crossing'in kendisi.
      expect(near.first.place.id, 'tk-shibuya');
    });

    test('çözülemeyen başlık → boş liste (uydurma öneri yok)', () {
      expect(nearbyCityPlaces(title: 'Kahvaltı'), isEmpty);
    });

    test('şehirlerden 30 km+ uzak koordinat → boş liste', () {
      // Fuji Dağı zirvesi — hiçbir küratörlü şehre yakın değil.
      expect(
        nearbyCityPlaces(title: 'x', lat: 35.3606, lng: 138.7274),
        isEmpty,
      );
    });
  });
}
