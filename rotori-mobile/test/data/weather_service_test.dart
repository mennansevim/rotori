// weather_service saf birim testleri — AĞ YOK.
//   1) weatherInfo: WMO kod → (emoji, Türkçe etiket) eşlemesi.
//   2) parseForecast: örnek Open-Meteo JSON fixture → List<DayForecast>.

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/data/weather_service.dart';

void main() {
  _nullHorizonTests();

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

// ---------------------------------------------------------------------------
// Regresyon: tahmin ufkunun kenarında `null` alanlar 0'a ÇEVRİLMEZ.
//
// Open-Meteo, 16 günlük pencerenin sonunda weathercode/sıcaklık için null
// döndürebiliyor. Bunlar 0'a düşürülünce weathercode 0 = "açık gökyüzü"
// olduğu için ağustos Tokyo'sunda "☀️ 0°" gibi imkânsız bir gün üretiliyordu.
// Eksik gün artık hiç üretilmez.
void _nullHorizonTests() {
  group('parseForecast — eksik alanlar', () {
    test('null sıcaklık/kod olan gün atlanır (0°C uydurulmaz)', () {
      const body = '''
{"daily":{
  "time":["2026-08-12","2026-08-13","2026-08-14"],
  "weathercode":[0,null,3],
  "temperature_2m_max":[33.1,29.0,null],
  "temperature_2m_min":[25.0,22.0,21.0],
  "precipitation_probability_max":[10,20,30]
}}''';
      final out = parseForecast(body);

      // Yalnız tam veri taşıyan ilk gün kalmalı.
      expect(out, hasLength(1));
      expect(out.single.date, '2026-08-12');
      expect(out.single.tempMax, 33.1);

      // Hiçbir gün 0°C / kod 0 kombinasyonuyla uydurulmamalı.
      expect(out.any((f) => f.tempMax == 0 && f.tempMin == 0), isFalse);
      expect(out.map((f) => f.date), isNot(contains('2026-08-13')));
      expect(out.map((f) => f.date), isNot(contains('2026-08-14')));
    });

    test('yağış olasılığı null olabilir — gün korunur', () {
      const body = '''
{"daily":{
  "time":["2026-08-12"],
  "weathercode":[61],
  "temperature_2m_max":[28.0],
  "temperature_2m_min":[22.0],
  "precipitation_probability_max":[null]
}}''';
      final out = parseForecast(body);
      expect(out, hasLength(1));
      expect(out.single.precipProb, isNull);
      expect(out.single.code, 61);
    });
  });
}
