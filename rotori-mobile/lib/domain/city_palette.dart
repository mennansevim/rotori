// Şehir bazlı gün numarası paleti — hem planner (Plan adımı) hem viewer
// (Gün kartı) aynı renkleri kullansın diye tek yerde tanımlı.
//
// Renkler destinasyon order'ına göre atanır: order 0 (iniş şehri) her zaman
// paletin ilk rengini alır, order 1 ikinci, vb. Böylece "Tokyo iniş" plan +
// viewer arasında tutarlı olur.

import 'package:flutter/material.dart';

import 'types.dart';

/// 7 renk — 7'den fazla şehir seçilirse dönerek tekrar eder (modulo).
const List<Color> kCityPalette = [
  Color(0xFF3B82F6), // blue
  Color(0xFFEC4899), // pink
  Color(0xFF10B981), // emerald
  Color(0xFFF59E0B), // amber
  Color(0xFF8B5CF6), // violet
  Color(0xFF06B6D4), // cyan
  Color(0xFFEF4444), // red
];

/// Destinasyonlar sırasındaki index'e göre renk döndürür.
/// [destId] null veya listede yoksa paletin ilk rengi.
Color cityColorFor(List<TripDestination> destinations, String? destId) {
  if (destId == null || destinations.isEmpty) return kCityPalette.first;
  final sorted = [...destinations]..sort((a, b) => a.order.compareTo(b.order));
  final i = sorted.indexWhere((d) => d.id == destId);
  if (i < 0) return kCityPalette.first;
  return kCityPalette[i % kCityPalette.length];
}
