import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/city_places.dart';
import 'package:rotori/domain/place_guide.dart';

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

  /// Küratörlük sınırı domain'de tanımlı (kGuideCuratedCityKeys) — testte
  /// ayrı bir liste tutmak ikisini kaçınılmaz olarak ayrıştırırdı.
  Iterable<CityData> curatedCities() =>
      kCityData.where((c) => kGuideCuratedCityKeys.contains(c.key));

  group('kapsama — küratörlü şehirler', () {
    test('küratörlük sınırı gerçek şehirlere işaret ediyor', () {
      // Yanlış yazılmış bir anahtar kapsamayı sessizce boşaltırdı.
      for (final key in kGuideCuratedCityKeys) {
        expect(kCityData.any((c) => c.key == key), isTrue,
            reason: '$key kCityData\'da yok');
      }
      expect(curatedCities(), isNotEmpty);
    });

    test('her küratörlü şehir noktasının bir rehberi var', () {
      final missing = <String>[];
      for (final city in curatedCities()) {
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
      for (final city in curatedCities()) {
        for (final p in city.places) {
          final g = matchPlaceGuide(p.name)!;
          expect(g.imageUrls, isNotEmpty, reason: '${p.name} görselsiz');
          expect(g.visitDurationMin, greaterThan(0));
          // brief/bestTimeOfDay artık LText (tr+en); iki dil de dolu olmalı.
          expect(g.brief.tr.length, greaterThan(40),
              reason: '${p.name} TR tanıtımı çok kısa');
          expect(g.brief.en.length, greaterThan(40),
              reason: '${p.name} EN tanıtımı çok kısa');
          expect(g.tips.length, greaterThanOrEqualTo(3),
              reason: '${p.name} için en az 3 ipucu olmalı');
          expect(g.bestTimeOfDay.tr, isNotEmpty);
          expect(g.bestTimeOfDay.en, isNotEmpty);
        }
      }
    });

    test('görseller Wikimedia\'nın izin verdiği thumb boyutlarında', () {
      // Wikimedia yalnız 250/500/960/1280px sunuyor; başka genişlik 400 döner.
      final badWidth = RegExp(r'/(?!250px|500px|960px|1280px)\d+px-');
      for (final city in curatedCities()) {
        for (final p in city.places) {
          for (final url in matchPlaceGuide(p.name)!.imageUrls) {
            expect(badWidth.hasMatch(url), isFalse,
                reason: 'Geçersiz thumb boyutu: $url');
          }
        }
      }
    });
  });

  group('kapsam dışı şehirler güvenle bozulur', () {
    test('rehbersiz yer null döner, çökmez', () {
      final outside =
          kCityData.where((c) => !kGuideCuratedCityKeys.contains(c.key));
      expect(outside, isNotEmpty, reason: 'test anlamını yitirdi');
      for (final city in outside) {
        for (final p in city.places) {
          // Rehber olabilir de olmayabilir de — ÖNEMLİ OLAN patlamaması.
          expect(() => matchPlaceGuide(p.name), returnsNormally,
              reason: '${city.label}: ${p.name}');
        }
      }
    });

    test('rehbersiz yerin koordinatı var — görsel/harita yedeği çalışabilsin',
        () {
      for (final city in kCityData) {
        for (final p in city.places) {
          expect(p.lat, isNot(0), reason: '${p.name} enlemsiz');
          expect(p.lng, isNot(0), reason: '${p.name} boylamsız');
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
      // Japon Denizi'nde açık su — karadaki hiçbir küratörlü noktaya yakın
      // değil. Eskiden Fuji zirvesi kullanılıyordu; "Fuji & Kawaguchiko"
      // şehri eklenince zirve 4 km'lik bir yere komşu oldu ve testin
      // dayanağı sessizce çöktü. O yüzden VARSAYIMI da doğruluyoruz:
      // nokta gerçekten uzak mı, önce onu iddia et.
      const lat = 39.0;
      const lng = 135.0;
      for (final city in kCityData) {
        for (final p in city.places) {
          expect(_haversineKm(lat, lng, p.lat, p.lng), greaterThan(30),
              reason: '${p.name} seçilen "uzak" noktaya çok yakın — '
                  'test artık istediğini ölçmüyor');
        }
      }
      expect(nearbyCityPlaces(title: 'x', lat: lat, lng: lng), isEmpty);
    });
  });
}

/// İki koordinat arası kuş uçuşu mesafe (km) — testin "uzak" varsayımını
/// doğrulamak için.
double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}
