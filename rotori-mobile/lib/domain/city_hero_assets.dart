// Plan görüntüleyicisindeki şehir hero görselleri.
// Görseller uygulamaya gömülüdür; gezi sırasında ağ bağlantısı gerekmez.

import 'city_places.dart';

/// Plan verisindeki semt/şehir metnini küratörlü şehir anahtarına bağlar.
String cityHeroKeyFor(String? cityText) {
  final text = (cityText ?? '').toLowerCase();
  for (final city in kCityData) {
    if (city.aliases.any(text.contains)) return city.key;
  }
  return 'tokyo';
}

/// Şehir hero asset yolu. Bilinmeyen/eksik şehirlerde Tokyo güvenli fallback'tir;
/// geçersiz bir asset yolu yüzünden viewer boş kalmaz.
String cityHeroAssetFor(String? cityText) =>
    'assets/images/city-hero-${cityHeroKeyFor(cityText)}.webp';
