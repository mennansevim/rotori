// Yer görsellerini katmanlı (hybrid) çözer:
//
//   1. Küratörlü `place_guide.dart` → elle doğrulanmış Wikimedia URL'leri
//      (en güvenilir, anında, ağ isteği yok).
//   2. Eşleşme yoksa Wikipedia REST/Query API → yer adından otomatik görsel
//      (landmark'lar için ~%95-99 doğru, anahtarsız, ücretsiz).
//   3. Hiçbiri yoksa boş liste → UI emoji fallback'e düşer.
//
// Çözülen sonuçlar in-memory cache'lenir (pozitif + negatif) — aynı yer için
// tekrar ağ isteği yapılmaz. Görsel byte'ları ise Image.network / tarayıcı
// HTTP cache üzerinden gelir, performans etkilenmez.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'place_guide.dart';

class PlaceImageResolver {
  PlaceImageResolver._();
  static final PlaceImageResolver instance = PlaceImageResolver._();

  // Çözülmüş sonuç cache'i (title.lower -> url listesi). Boş liste = negatif.
  final Map<String, List<String>> _cache = {};
  // Devam eden istekler (aynı anda birden fazla çağrıyı tekilleştirir).
  final Map<String, Future<List<String>>> _inflight = {};

  /// [title] için görsel URL'lerini döndürür. Önce küratörlü rehber,
  /// yoksa Wikipedia. Sonuç cache'lenir.
  Future<List<String>> resolve(String title, {String? city}) {
    final key = title.trim().toLowerCase();
    if (key.isEmpty) return Future.value(const []);

    final cached = _cache[key];
    if (cached != null) return Future.value(cached);

    // 1) Küratörlü rehber — anında.
    final guide = matchPlaceGuide(title);
    if (guide != null && guide.imageUrls.isNotEmpty) {
      _cache[key] = guide.imageUrls;
      return Future.value(guide.imageUrls);
    }

    // 2) Wikipedia — ağdan, tekilleştirilmiş.
    return _inflight[key] ??= _fetchFromWikipedia(title, city: city).then((urls) {
      _cache[key] = urls;
      _inflight.remove(key);
      return urls;
    }).catchError((_) {
      _cache[key] = const [];
      _inflight.remove(key);
      return const <String>[];
    });
  }

  /// Rehberde varsa senkron (ağ isteği olmadan) döndürür, yoksa null.
  List<String>? peekCurated(String title) {
    final guide = matchPlaceGuide(title);
    if (guide != null && guide.imageUrls.isNotEmpty) return guide.imageUrls;
    return null;
  }

  Future<List<String>> _fetchFromWikipedia(String title,
      {String? city}) async {
    // Japonya bağlamı doğruluğu artırır ("Ginza" gibi genel adlar için).
    final query = city != null && city.isNotEmpty
        ? '$title $city Japan'
        : '$title Japan';

    // İngilizce Wikipedia landmark kapsamı en geniş. generator=search ile
    // en alakalı sayfayı bulup pageimages thumbnail'ını alıyoruz.
    for (final lang in const ['en', 'ja']) {
      final uri = Uri.https('$lang.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'format': 'json',
        'prop': 'pageimages',
        'piprop': 'thumbnail|original',
        'pithumbsize': '800',
        'generator': 'search',
        'gsrsearch': query,
        'gsrlimit': '1',
        'gsrnamespace': '0',
        'origin': '*', // web CORS için gerekli
      });

      final res = await http
          .get(uri, headers: {'User-Agent': 'japan-trip-app/1.0'})
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) continue;

      final data = json.decode(res.body) as Map<String, dynamic>;
      final pages = (data['query'] as Map<String, dynamic>?)?['pages']
          as Map<String, dynamic>?;
      if (pages == null || pages.isEmpty) continue;

      final page = pages.values.first as Map<String, dynamic>;
      final thumb = (page['thumbnail'] as Map<String, dynamic>?)?['source']
          as String?;
      final original = (page['original'] as Map<String, dynamic>?)?['source']
          as String?;
      final url = original ?? thumb;
      if (url != null && url.isNotEmpty) return [url];
    }

    return const [];
  }
}
