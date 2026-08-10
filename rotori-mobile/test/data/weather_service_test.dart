// weather_service saf birim testleri — AĞ YOK.
//   1) weatherInfo: WMO kod → (emoji, Türkçe etiket) eşlemesi.
//   2) parseForecast: örnek Open-Meteo JSON fixture → List<DayForecast>.

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/data/weather_service.dart';

void main() {
  group('weatherInfo', () {
    test('bilinen kod aralıkları doğru emoji/etiket verir', () {
      // weatherInfo artık i18n anahtarı döndürür (etiket LanguageScope ile çözülür).
      expect(weatherInfo(0), ('☀️', 'wx.clear'));
      expect(weatherInfo(1), ('⛅', 'wx.partlyCloudy'));
      expect(weatherInfo(3), ('⛅', 'wx.partlyCloudy'));
      expect(weatherInfo(45), ('🌫️', 'wx.fog'));
      expect(weatherInfo(48), ('🌫️', 'wx.fog'));
      expect(weatherInfo(51), ('🌧️', 'wx.rain'));
      expect(weatherInfo(65), ('🌧️', 'wx.rain'));
      expect(weatherInfo(67), ('🌧️', 'wx.rain'));
      expect(weatherInfo(71), ('❄️', 'wx.snow'));
      expect(weatherInfo(77), ('❄️', 'wx.snow'));
      expect(weatherInfo(80), ('🌦️', 'wx.showers'));
      expect(weatherInfo(82), ('🌦️', 'wx.showers'));
      expect(weatherInfo(95), ('⛈️', 'wx.thunderstorm'));
      expect(weatherInfo(99), ('⛈️', 'wx.thunderstorm'));
    });

    test('bilinmeyen kod fallback döner', () {
      expect(weatherInfo(123), ('🌡️', 'wx.unknown'));
      expect(weatherInfo(-1), ('🌡️', 'wx.unknown'));
    });
  });

  group('parseForecast', () {
    const fixture = '''
{
  "latitude": 35.68,
  "longitude": 139.65,
  "timezone": "Asia/Tokyo",
  "daily": {
    "time": ["2026-07-17", "2026-07-18", "2026-07-19"],
    "weathercode": [0, 61, 95],
    "temperature_2m_max": [31.4, 28.0, 26.6],
    "temperature_2m_min": [24.1, 22.5, 21.0],
    "precipitation_probability_max": [10, 80, null]
  }
}
''';

    test('daily dizilerini doğru DayForecast listesine çevirir', () {
      final list = parseForecast(fixture);
      expect(list.length, 3);

      expect(list[0].date, '2026-07-17');
      expect(list[0].code, 0);
      expect(list[0].tempMax, 31.4);
      expect(list[0].tempMin, 24.1);
      expect(list[0].precipProb, 10);

      expect(list[1].code, 61);
      expect(list[1].precipProb, 80);

      // null yağış olasılığı → null.
      expect(list[2].code, 95);
      expect(list[2].precipProb, isNull);
    });

    test('daily eksikse WeatherException fırlatır', () {
      expect(
        () => parseForecast('{"error": true}'),
        throwsA(isA<WeatherException>()),
      );
    });

    test('bozuk JSON WeatherException fırlatır', () {
      expect(
        () => parseForecast('not json'),
        throwsA(isA<WeatherException>()),
      );
    });
  });
}
