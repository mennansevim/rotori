import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import '../../domain/product_price_query.dart';
import '../../domain/scanner_tuning.dart';
import '../../domain/tracked_price.dart';
import '../ocr/on_device_text_recognizer.dart';

/// OCR satırları + fiyat izlerinden ürün sorgusu için aday üretir.
class ProductQueryCandidateResolver {
  const ProductQueryCandidateResolver();

  static final RegExp _electronicsKeyword = RegExp(
    r'(apple|macbook|iphone|ipad|airpods|watch|sony|nintendo|switch|playstation|ps5|canon|nikon|fujifilm|dyson|lenovo|asus|msi|surface|pixel|galaxy)',
    caseSensitive: false,
  );

  static final RegExp _modelHint = RegExp(
    r'(m[1-4]|a\d{3,4}|\d{2,3}\s?gb|\d\s?tb|ultra|pro|max|mini|oled|rtx|ryzen|i[3579]-?\d{3,5})',
    caseSensitive: false,
  );

  ProductQueryCandidate? resolve({
    required RecognizedFrame frame,
    required List<TrackedPrice> tracks,
  }) {
    if (tracks.isEmpty || frame.lines.isEmpty) return null;

    final anchor = _pickAnchorTrack(tracks);
    final bestLine = _pickBestLine(frame, anchor.smoothedBox);
    if (bestLine == null) return null;
    if (bestLine.score < ScannerTuning.queryCandidateMinScore) return null;

    final title = _normalizeTitle(bestLine.text);
    if (title.length < 5) return null;

    final mergedBox = anchor.smoothedBox
        .expandToInclude(bestLine.boundingBox)
        .inflate(ScannerTuning.queryFrameInflatePx);

    final confidence =
        ((anchor.price.confidence * 0.62) + (bestLine.score * 0.38))
            .clamp(0.0, 1.0)
            .toDouble();

    final hints = _extractHints(title);

    return ProductQueryCandidate(
      id: '${anchor.id}_${mergedBox.center.dx.round()}_${title.hashCode}',
      title: title,
      amountInJpy: anchor.price.amountInJpy,
      boundingBox: mergedBox,
      confidence: confidence,
      searchHints: hints,
    );
  }

  TrackedPrice _pickAnchorTrack(List<TrackedPrice> tracks) {
    final sorted = [...tracks]
      ..sort((a, b) {
        final sb = (b.price.confidence * 0.7) +
            ((b.seenCount / ScannerTuning.queryCandidateMinSeen)
                    .clamp(0.0, 1.0) *
                0.3);
        final sa = (a.price.confidence * 0.7) +
            ((a.seenCount / ScannerTuning.queryCandidateMinSeen)
                    .clamp(0.0, 1.0) *
                0.3);
        return sb.compareTo(sa);
      });
    return sorted.first;
  }

  _ScoredLine? _pickBestLine(RecognizedFrame frame, Rect anchorBox) {
    _ScoredLine? best;
    for (final line in frame.lines) {
      final text = line.text.trim();
      if (text.isEmpty) continue;
      if (_isMostlyNumeric(text)) continue;

      final score = _lineScore(text, line.boundingBox, anchorBox);
      if (best == null || score > best.score) {
        best = _ScoredLine(
          text: text,
          score: score,
          boundingBox: line.boundingBox,
        );
      }
    }
    return best;
  }

  double _lineScore(String text, Rect lineBox, Rect anchorBox) {
    final lower = text.toLowerCase();
    final hasKeyword = _electronicsKeyword.hasMatch(lower);
    final hasModelHint = _modelHint.hasMatch(lower);

    final alpha = RegExp(r'[a-zA-Z]').allMatches(text).length;
    final digit = RegExp(r'\d').allMatches(text).length;
    final usableChars = RegExp(r'[a-zA-Z0-9]').allMatches(text).length;
    final alphaRatio = usableChars == 0 ? 0.0 : alpha / usableChars;

    final distance = _distance(anchorBox.center, lineBox.center);
    final ref = math.max(anchorBox.longestSide, lineBox.longestSide);
    final proximity = (1 - (distance / math.max(1, ref * 7.5))).clamp(0.0, 1.0);

    final lengthScore = (text.length / 38).clamp(0.15, 1.0);

    var score = 0.0;
    score += hasKeyword ? 0.55 : 0.0;
    score += hasModelHint ? 0.22 : 0.0;
    score += proximity * 0.14;
    score += lengthScore * 0.06;
    score += alphaRatio * 0.03;

    if (digit > 0 && alpha == 0) {
      score -= 0.30;
    }

    return score.clamp(0.0, 1.0).toDouble();
  }

  bool _isMostlyNumeric(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    final nonNumeric = compact.replaceAll(RegExp(r'[0-9¥￥円.,:/\-+%()]'), '');
    final hasEnoughLetters = RegExp(r'[a-zA-Z]{2,}').hasMatch(nonNumeric);
    return !hasEnoughLetters;
  }

  String _normalizeTitle(String text) {
    var out = text
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[|｜]'), ' ')
        .trim();
    if (out.length > ScannerTuning.queryCandidateMaxTitleChars) {
      out = out.substring(0, ScannerTuning.queryCandidateMaxTitleChars).trimRight();
    }
    return out;
  }

  List<String> _extractHints(String title) {
    final lower = title.toLowerCase();
    final hints = <String>{};
    for (final m in _modelHint.allMatches(lower)) {
      final token = m.group(0)?.trim();
      if (token != null && token.isNotEmpty) hints.add(token);
    }
    if (_electronicsKeyword.hasMatch(lower)) {
      final m = _electronicsKeyword.firstMatch(lower)?.group(0);
      if (m != null && m.isNotEmpty) hints.add(m);
    }
    return hints.toList(growable: false);
  }

  double _distance(Offset a, Offset b) {
    final dx = a.dx - b.dx;
    final dy = a.dy - b.dy;
    return math.sqrt((dx * dx) + (dy * dy));
  }
}

class _ScoredLine {
  const _ScoredLine({
    required this.text,
    required this.score,
    required this.boundingBox,
  });

  final String text;
  final double score;
  final Rect boundingBox;
}
