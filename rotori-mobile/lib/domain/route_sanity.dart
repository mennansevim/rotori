// Rota tutarlılık kontrolü — "Tokyo → Nara → Sapporo → Kyoto" gibi
// coğrafi olarak mantıksız sıralamaları yakalar ve düzeltme önerir.
//
// **Neden gerekli:** Şehir seçim ekranında SEÇİM SIRASI = ROTA SIRASI.
// Kullanıcı şehirleri akla geldiği sırayla seçiyor, coğrafyaya göre değil.
// 21 şehirle bu hata çok kolay: Kansai'de gezerken araya Hokkaido girmesi
// yüzlerce kilometre fazladan yol demek ve kullanıcı bunu plan üretilene
// kadar fark etmiyor.
//
// Bu dosya SAF'tır: Flutter importu yok.

import 'dart:math' as math;

import 'city_places.dart';

/// Öneriyi göstermeye değer kılan en az kazanç. Bunun altındaki farklar
/// gürültü — kullanıcıyı her küçük sapmada uyarmak kartı değersizleştirir.
const double _kMinSavingKm = 150;

/// Kazancın toplam mesafeye oranı da anlamlı olmalı; 3000 km'lik bir rotada
/// 150 km kazanç uyarmaya değmez.
const double _kMinSavingRatio = 0.15;

/// Rotanın toplam uzunluğu (km) ve önerilen daha kısa sıralama.
class RouteSanity {
  const RouteSanity({
    required this.currentKm,
    required this.suggestedKm,
    required this.suggestedOrder,
  });

  final double currentKm;
  final double suggestedKm;

  /// Önerilen şehir anahtarı sırası. Öneri yoksa mevcut sırayla aynıdır.
  final List<String> suggestedOrder;

  double get savedKm => currentKm - suggestedKm;

  /// Kullanıcıya gösterilmeye değer bir kazanç var mı?
  bool get hasSuggestion =>
      savedKm >= _kMinSavingKm &&
      currentKm > 0 &&
      savedKm / currentKm >= _kMinSavingRatio;
}

/// İki şehir arası kuş uçuşu mesafe (km).
double _distanceKm((double, double) a, (double, double) b) {
  const earthRadiusKm = 6371.0;
  final lat1 = a.$1 * math.pi / 180;
  final lat2 = b.$1 * math.pi / 180;
  final dLat = lat2 - lat1;
  final dLng = (b.$2 - a.$2) * math.pi / 180;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

/// Şehrin merkezi — küratörlü yerlerin ortalaması.
(double, double)? cityCenter(String cityKey) {
  final match = kCityData.where((c) => c.key == cityKey);
  if (match.isEmpty || match.first.places.isEmpty) return null;
  final places = match.first.places;
  var lat = 0.0;
  var lng = 0.0;
  for (final p in places) {
    lat += p.lat;
    lng += p.lng;
  }
  return (lat / places.length, lng / places.length);
}

double _totalKm(List<String> order) {
  var sum = 0.0;
  for (var i = 0; i + 1 < order.length; i++) {
    final a = cityCenter(order[i]);
    final b = cityCenter(order[i + 1]);
    if (a == null || b == null) continue;
    sum += _distanceKm(a, b);
  }
  return sum;
}

/// [cityKeys] sırasını değerlendirir ve daha kısa bir sıralama önerir.
///
/// İLK ŞEHİR SABİT KALIR — kullanıcının uçuşla indiği yer odur; onu
/// değiştirmek öneriyi kullanışsız yapar. Kalan şehirler için:
///  • n ≤ 8 → tam permütasyon (kesin en iyi),
///  • n > 8 → en yakın komşu + 2-opt (yeterince iyi, hızlı).
RouteSanity checkRouteOrder(List<String> cityKeys) {
  final known =
      cityKeys.where((k) => cityCenter(k) != null).toList(growable: false);
  if (known.length < 3) {
    // 2 şehirde sıralama tercihi var, "yanlış" yok.
    return RouteSanity(
      currentKm: _totalKm(known),
      suggestedKm: _totalKm(known),
      suggestedOrder: List<String>.from(cityKeys),
    );
  }

  final current = _totalKm(known);
  final first = known.first;
  final rest = known.sublist(1);

  final best = rest.length <= 7
      ? _bestByPermutation(first, rest)
      : _bestByHeuristic(first, rest);

  final bestOrder = [first, ...best];
  final bestKm = _totalKm(bestOrder);

  // Öneri mevcut sıradan kötüyse (olmamalı) mevcut sırayı koru.
  if (bestKm >= current) {
    return RouteSanity(
      currentKm: current,
      suggestedKm: current,
      suggestedOrder: List<String>.from(cityKeys),
    );
  }
  return RouteSanity(
    currentKm: current,
    suggestedKm: bestKm,
    suggestedOrder: bestOrder,
  );
}

List<String> _bestByPermutation(String first, List<String> rest) {
  List<String>? best;
  var bestKm = double.infinity;

  void permute(List<String> chosen, List<String> remaining) {
    if (remaining.isEmpty) {
      final km = _totalKm([first, ...chosen]);
      if (km < bestKm) {
        bestKm = km;
        best = List<String>.from(chosen);
      }
      return;
    }
    for (var i = 0; i < remaining.length; i++) {
      final next = remaining[i];
      permute(
        [...chosen, next],
        [...remaining.sublist(0, i), ...remaining.sublist(i + 1)],
      );
    }
  }

  permute(const [], rest);
  return best ?? rest;
}

List<String> _bestByHeuristic(String first, List<String> rest) {
  // En yakın komşu ile başla.
  final remaining = [...rest];
  final order = <String>[];
  var currentKey = first;
  while (remaining.isNotEmpty) {
    var bestIdx = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < remaining.length; i++) {
      final a = cityCenter(currentKey);
      final b = cityCenter(remaining[i]);
      if (a == null || b == null) continue;
      final d = _distanceKm(a, b);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    currentKey = remaining.removeAt(bestIdx);
    order.add(currentKey);
  }

  // 2-opt ile iyileştir.
  var improved = true;
  var guard = 0;
  while (improved && guard < 100) {
    improved = false;
    guard++;
    for (var i = 0; i < order.length - 1; i++) {
      for (var j = i + 1; j < order.length; j++) {
        final candidate = [...order];
        // i..j aralığını ters çevir
        final segment = candidate.sublist(i, j + 1).reversed.toList();
        candidate.replaceRange(i, j + 1, segment);
        if (_totalKm([first, ...candidate]) < _totalKm([first, ...order])) {
          order
            ..clear()
            ..addAll(candidate);
          improved = true;
        }
      }
    }
  }
  return order;
}
