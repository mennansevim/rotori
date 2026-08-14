// Hava durumu servisi — Open-Meteo (ücretsiz, API anahtarı YOK).
//
// React viewer'daki utils/weather.ts'in Flutter portu; sunum WeatherStrip.tsx'e
// sadık kalır ama veri Open-Meteo'dan canlı gelir. http paketi web + mobilde
// çalışır. Ağ hatası WeatherException olarak fırlatılır; UI yakalar.
//
// Uç nokta:
//   https://api.open-meteo.com/v1/forecast?latitude=..&longitude=..
//     &daily=weathercode,temperature_2m_max,temperature_2m_min,
//            precipitation_probability_max
//     &timezone=auto&forecast_days=16

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Tek bir günün tahmini. Tarih ISO (YYYY-MM-DD), kod WMO weathercode.
class DayForecast {
  const DayForecast({
    required this.date,
    required this.code,
    required this.tempMax,
    required this.tempMin,
    this.precipProb,
  });

  final String date;
  final int code;
  final double tempMax;
  final double tempMin;
  final int? precipProb;
}

/// Ağ/parse hatalarını UI'nın tek noktadan yakalayabilmesi için basit tip.
class WeatherException implements Exception {
  const WeatherException(this.message);
  final String message;
  @override
  String toString() => 'WeatherException: $message';
}

/// WMO weathercode → (emoji, Türkçe etiket).
///
///   0        açık          ☀️
///   1-3      parçalı bulutlu ⛅
///   45,48    sisli          🌫️
///   51-67    yağmurlu       🌧️
///   71-77    karlı          ❄️
///   80-82    sağanak        🌦️
///   95-99    gök gürültülü  ⛈️
///   diğer    —              🌡️
(String emoji, String labelKey) weatherInfo(int code) {
  if (code == 0) return ('☀️', 'wx.clear');
  if (code >= 1 && code <= 3) return ('⛅', 'wx.partlyCloudy');
  if (code == 45 || code == 48) return ('🌫️', 'wx.fog');
  if (code >= 51 && code <= 67) return ('🌧️', 'wx.rain');
  if (code >= 71 && code <= 77) return ('❄️', 'wx.snow');
  if (code >= 80 && code <= 82) return ('🌦️', 'wx.showers');
  if (code >= 95 && code <= 99) return ('⛈️', 'wx.thunderstorm');
  return ('🌡️', 'wx.unknown');
}

/// Open-Meteo `daily` yanıtını (ham JSON string) DayForecast listesine çevirir.
/// Saf fonksiyon — ağ yok; testlerde fixture ile doğrulanır.
List<DayForecast> parseForecast(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    throw const WeatherException('Geçersiz yanıt (JSON çözümlenemedi).');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const WeatherException('Beklenmeyen yanıt biçimi.');
  }
  final daily = decoded['daily'];
  if (daily is! Map<String, dynamic>) {
    throw const WeatherException('Günlük tahmin verisi bulunamadı.');
  }

  final times = (daily['time'] as List?) ?? const [];
  final codes = (daily['weathercode'] as List?) ?? const [];
  final maxT = (daily['temperature_2m_max'] as List?) ?? const [];
  final minT = (daily['temperature_2m_min'] as List?) ?? const [];
  final prob = (daily['precipitation_probability_max'] as List?) ?? const [];

  T? at<T>(List<dynamic> list, int i) => i < list.length ? list[i] as T? : null;

  final out = <DayForecast>[];
  for (var i = 0; i < times.length; i++) {
    final date = at<Object>(times, i)?.toString();
    if (date == null) continue;

    // Open-Meteo tahmin ufkunun kenarında alanları `null` döndürebilir.
    // Bunları 0'a çevirmek veri UYDURMAKTIR: weathercode 0 "açık gökyüzü"
    // demek olduğu için ağustos Tokyo'sunda "☀️ 0°" gibi imkânsız bir gün
    // üretiliyordu. Eksik gün hiç üretilmez; çağıran tarafta "tahmin yok"
    // olarak görünür.
    final code = at<num>(codes, i);
    final high = at<num>(maxT, i);
    final low = at<num>(minT, i);
    if (code == null || high == null || low == null) continue;

    out.add(
      DayForecast(
        date: date,
        code: code.toInt(),
        tempMax: high.toDouble(),
        tempMin: low.toDouble(),
        precipProb: (at<num>(prob, i))?.toInt(),
      ),
    );
  }
  return out;
}

/// Verilen konum için 16 günlük tahmini çeker. Anahtar/oturum YOK.
/// Hata durumunda [WeatherException] fırlatır.
Future<List<DayForecast>> fetchForecast(double lat, double lng) async {
  final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
    'latitude': '$lat',
    'longitude': '$lng',
    'daily': 'weathercode,temperature_2m_max,temperature_2m_min,'
        'precipitation_probability_max',
    'timezone': 'auto',
    'forecast_days': '16',
  });

  final http.Response resp;
  try {
    resp = await http.get(uri);
  } catch (e) {
    throw WeatherException('Ağ hatası: $e');
  }
  if (resp.statusCode != 200) {
    throw WeatherException('Sunucu hatası (${resp.statusCode}).');
  }
  return parseForecast(resp.body);
}
