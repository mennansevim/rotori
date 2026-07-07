import 'package:flutter_test/flutter_test.dart';
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
}
