import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import '../../domain/detected_price.dart';
import '../../domain/scanner_tuning.dart';
import '../../domain/tracked_price.dart';

/// Ardışık analiz kareleri arasında fiyatları izleyip overlay titremesini
/// önler.
///
/// Saf Dart, durumlu ama deterministik: saat dışarıdan `nowMs` olarak enjekte
/// edilir (testlenebilir). Eşleştirme yalnız tutara değil, kutu kesişimine
/// (IoU) veya merkez yakınlığına da bakar; böylece aynı fiyatlı iki farklı
/// ürün ayrı izler olarak kalır. Kutu konumu exponential smoothing ile
/// yumuşatılır.
class PriceDetectionTracker {
  PriceDetectionTracker({ScannerTuning? tuning});

  final List<TrackedPrice> _tracks = [];

  /// Yalnızca gösterilmeye hazır (yeterince görülmüş, taze) izler.
  List<TrackedPrice> get visibleTracks => _tracks
      .where((t) => t.seenCount >= ScannerTuning.minSeenToDisplay)
      .toList();

  List<TrackedPrice> get allTracks => List.unmodifiable(_tracks);

  /// Yeni bir analiz karesindeki [detections] ile izleri günceller.
  /// [nowMs] geçerli zaman (ms since epoch). Görünür izleri döndürür.
  List<TrackedPrice> update(List<DetectedPrice> detections, int nowMs) {
    final matchedTrackIds = <String>{};

    for (final det in detections) {
      final match = _bestMatch(det, matchedTrackIds);
      if (match != null) {
        matchedTrackIds.add(match.id);
        _replaceTrack(match, _mergeInto(match, det, nowMs));
      } else {
        _tracks.add(TrackedPrice(
          price: det,
          smoothedBox: det.boundingBox,
          seenCount: 1,
          firstSeenAtMs: nowMs,
          lastSeenAtMs: nowMs,
        ));
      }
    }

    // Bayatlamış izleri kaldır.
    _tracks.removeWhere(
        (t) => nowMs - t.lastSeenAtMs > ScannerTuning.staleTrackMs);

    return visibleTracks;
  }

  /// İz durumunu tümüyle temizler (ekran kapanışı / kamera resetinde).
  void reset() => _tracks.clear();

  TrackedPrice? _bestMatch(DetectedPrice det, Set<String> taken) {
    TrackedPrice? best;
    double bestScore = 0;
    for (final t in _tracks) {
      if (taken.contains(t.id)) continue;
      if (t.price.amountInJpy != det.amountInJpy) continue;
      final iou = _iou(t.smoothedBox, det.boundingBox);
      final near = _centerClose(t.smoothedBox, det.boundingBox);
      if (iou >= ScannerTuning.matchIouThreshold || near) {
        final score = iou + (near ? 0.1 : 0);
        if (score > bestScore) {
          bestScore = score;
          best = t;
        }
      }
    }
    return best;
  }

  TrackedPrice _mergeInto(TrackedPrice track, DetectedPrice det, int nowMs) {
    final smoothed = _smoothRect(track.smoothedBox, det.boundingBox);
    // En güncel/güvenli fiyatı taşı ama kimliği koru (kararlı overlay).
    final price = det.copyWith(id: track.id);
    return track.copyWith(
      price: price,
      smoothedBox: smoothed,
      seenCount: track.seenCount + 1,
      lastSeenAtMs: nowMs,
    );
  }

  void _replaceTrack(TrackedPrice oldTrack, TrackedPrice next) {
    final i = _tracks.indexWhere((t) => t.id == oldTrack.id);
    if (i >= 0) _tracks[i] = next;
  }

  Rect _smoothRect(Rect prev, Rect next) {
    const pw = ScannerTuning.boxSmoothingPrevWeight;
    const nw = ScannerTuning.boxSmoothingNewWeight;
    return Rect.fromLTRB(
      prev.left * pw + next.left * nw,
      prev.top * pw + next.top * nw,
      prev.right * pw + next.right * nw,
      prev.bottom * pw + next.bottom * nw,
    );
  }

  double _iou(Rect a, Rect b) {
    final interLeft = math.max(a.left, b.left);
    final interTop = math.max(a.top, b.top);
    final interRight = math.min(a.right, b.right);
    final interBottom = math.min(a.bottom, b.bottom);
    final iw = interRight - interLeft;
    final ih = interBottom - interTop;
    if (iw <= 0 || ih <= 0) return 0;
    final inter = iw * ih;
    final union = a.width * a.height + b.width * b.height - inter;
    if (union <= 0) return 0;
    return inter / union;
  }

  bool _centerClose(Rect a, Rect b) {
    final ca = Offset(a.center.dx, a.center.dy);
    final cb = Offset(b.center.dx, b.center.dy);
    final dist = (ca - cb).distance;
    final refSize = math.max(a.shortestSide, b.shortestSide);
    if (refSize <= 0) return false;
    return dist <= refSize * ScannerTuning.matchCenterDistanceRatio;
  }
}
