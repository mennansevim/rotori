import 'dart:ui' show Rect;

import 'detected_price.dart';

/// Overlay titremesini önlemek için, ardışık karelerde eşleştirilmiş ve
/// yumuşatılmış (smoothed) bir fiyat izi.
///
/// [smoothedBox] exponential smoothing ile yumuşatılmış sınır kutusudur;
/// [seenCount] kaç analiz karesinde görüldüğü, [firstSeenAtMs]/[lastSeenAtMs]
/// zaman damgalarıdır (test edilebilirlik için ms epoch olarak enjekte edilir).
class TrackedPrice {
  const TrackedPrice({
    required this.price,
    required this.smoothedBox,
    required this.seenCount,
    required this.firstSeenAtMs,
    required this.lastSeenAtMs,
  });

  /// En güncel (ham) fiyat detection'ı — tutar/vergi/güven buradan okunur.
  final DetectedPrice price;

  /// Yumuşatılmış görüntü-koordinat sınır kutusu (overlay konumu bundan türer).
  final Rect smoothedBox;

  /// Kaç ayrı analiz karesinde görüldü.
  final int seenCount;

  /// İlk görülme (ms since epoch, enjekte edilebilir saat).
  final int firstSeenAtMs;

  /// Son görülme (ms since epoch).
  final int lastSeenAtMs;

  /// Kararlı gösterim için iz kimliği (fiyatın kimliği).
  String get id => price.id;

  TrackedPrice copyWith({
    DetectedPrice? price,
    Rect? smoothedBox,
    int? seenCount,
    int? firstSeenAtMs,
    int? lastSeenAtMs,
  }) {
    return TrackedPrice(
      price: price ?? this.price,
      smoothedBox: smoothedBox ?? this.smoothedBox,
      seenCount: seenCount ?? this.seenCount,
      firstSeenAtMs: firstSeenAtMs ?? this.firstSeenAtMs,
      lastSeenAtMs: lastSeenAtMs ?? this.lastSeenAtMs,
    );
  }
}
