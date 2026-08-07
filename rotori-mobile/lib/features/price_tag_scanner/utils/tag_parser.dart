import 'dart:math' as math;

/// OCR metninden ürün modeli + JPY fiyatı çıkarım sonucu.
class TagParseResult {
  const TagParseResult({
    required this.jpyPrice,
    required this.productModel,
    required this.hasTaxIncluded,
    required this.hasTaxExcluded,
    required this.normalizedText,
  });

  final int? jpyPrice;
  final String? productModel;
  final bool hasTaxIncluded;
  final bool hasTaxExcluded;
  final String normalizedText;

  bool get hasCoreData => jpyPrice != null && productModel != null;
}

class _PriceCandidate {
  const _PriceCandidate({
    required this.amount,
    required this.score,
    required this.taxIncluded,
    required this.taxExcluded,
  });

  final int amount;
  final int score;
  final bool taxIncluded;
  final bool taxExcluded;
}

/// Elektronik mağaza etiketlerini çözümleyen saf Dart parser.
///
/// - JPY fiyatı: `¥/￥/円/JPY` yakınlığından yakalar.
/// - `ポイント` bağlamındaki sayıları yok sayar.
/// - `税込` + `税抜` birlikteyse `税込` (vergi dahil) fiyatı önceliklidir.
/// - Model kodu: büyük harf/rakam/tire kombinasyonlarını seçer.
class TagParser {
  const TagParser();

  static final RegExp _numberPattern = RegExp(r'\d[\d,\.]{0,15}');
  static final RegExp _modelTokenPattern = RegExp(r'[A-Z0-9][A-Z0-9-]{4,}');
  static final RegExp _containsLetter = RegExp(r'[A-Z]');
  static final RegExp _containsDigit = RegExp(r'\d');
  static final RegExp _likelyUnitSuffix =
      RegExp(r'^\s*(年|月|日|時|分|秒|%|％|個|点|台|名|人|番|号)');

  static const Set<String> _modelStopWords = <String>{
    'JPY',
    'POINT',
    'POINTS',
    'TAX',
    'IN',
    'OUT',
    '税込',
    '税抜',
  };

  TagParseResult parse(String rawText) {
    final normalized = _normalize(rawText);
    final lines = normalized
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final price = _extractJpyPrice(lines);
    final model = _extractProductModel(normalized);

    final hasTaxIncluded = lines.any((line) => line.contains('税込'));
    final hasTaxExcluded =
        lines.any((line) => line.contains('税抜') || line.contains('本体価格'));

    return TagParseResult(
      jpyPrice: price,
      productModel: model,
      hasTaxIncluded: hasTaxIncluded,
      hasTaxExcluded: hasTaxExcluded,
      normalizedText: normalized,
    );
  }

  /// Tek bir metin parçasındaki en olası model kodunu döndürür (konum yok).
  /// Merkez-ağırlıklı oylama için satır satır çağrılır.
  String? extractModelToken(String text) => _extractProductModel(_normalize(text));

  /// Tek bir satırdaki JPY fiyatını döndürür (yoksa null).
  int? extractJpyPriceInLine(String line) {
    final result = _extractJpyPrice([_normalize(line)]);
    return result;
  }

  int? _extractJpyPrice(List<String> lines) {
    if (lines.isEmpty) return null;

    final candidates = <_PriceCandidate>[];

    for (final line in lines) {
      final taxIncluded = line.contains('税込');
      final taxExcluded = line.contains('税抜') || line.contains('本体価格');

      for (final match in _numberPattern.allMatches(line)) {
        final token = match.group(0);
        if (token == null || token.isEmpty) continue;

        final start = match.start;
        final end = match.end;

        if (_isPointsContext(line, start, end)) {
          continue;
        }

        final trailing = line.substring(end);
        if (_likelyUnitSuffix.hasMatch(trailing)) {
          continue;
        }

        final amount = int.tryParse(token.replaceAll(RegExp(r'[,\.]'), ''));
        if (amount == null || amount <= 0) {
          continue;
        }

        final hasYenContext = _hasYenContext(line, start, end);
        if (!hasYenContext && !taxIncluded && !taxExcluded) {
          continue;
        }

        var score = 0;
        if (taxIncluded) score += 40;
        if (taxExcluded) score += 6;
        if (hasYenContext) score += 20;
        if (token.contains(',') || token.contains('.')) score += 2;
        if (amount >= 100 && amount <= 5000000) score += 6;

        candidates.add(_PriceCandidate(
          amount: amount,
          score: score,
          taxIncluded: taxIncluded,
          taxExcluded: taxExcluded,
        ));
      }
    }

    if (candidates.isEmpty) return null;

    final included = candidates.where((c) => c.taxIncluded).toList();
    final pool = included.isNotEmpty ? included : candidates;

    pool.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.amount.compareTo(a.amount);
    });

    return pool.first.amount;
  }

  String? _extractProductModel(String normalizedText) {
    final upper = normalizedText.toUpperCase();
    final candidates = <({String token, int score})>[];
    for (final match in _modelTokenPattern.allMatches(upper)) {
      final raw = match.group(0);
      if (raw == null) continue;
      final token = raw.replaceAll(RegExp(r'^-+|-+$'), '');
      if (token.length < 5 || token.length > 24) continue;
      if (_modelStopWords.contains(token)) continue;
      if (!_containsLetter.hasMatch(token) || !_containsDigit.hasMatch(token)) {
        continue;
      }

      var score = 0;
      if (token.contains('-')) score += 5;
      if (RegExp(r'^[A-Z]{1,6}-[A-Z0-9-]+$').hasMatch(token)) score += 4;
      if (RegExp(r'^[A-Z0-9]+-[A-Z0-9]+-[A-Z0-9]+$').hasMatch(token)) {
        score += 2;
      }
      if (token.length >= 6 && token.length <= 14) score += 1;

      candidates.add((token: token, score: score));
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.token.length.compareTo(a.token.length);
    });

    return candidates.first.token;
  }

  bool _hasYenContext(String line, int start, int end) {
    final left = math.max(0, start - 4);
    final right = math.min(line.length, end + 6);
    final context = line.substring(left, right).toUpperCase();

    return context.contains('¥') ||
        context.contains('￥') ||
        context.contains('円') ||
        context.contains('JPY');
  }

  bool _isPointsContext(String line, int start, int end) {
    final left = math.max(0, start - 10);
    final right = math.min(line.length, end + 12);
    final context = line.substring(left, right).toUpperCase();

    return context.contains('ポイント') || context.contains('POINT');
  }

  String _normalize(String input) {
    final out = StringBuffer();

    for (final rune in input.runes) {
      if (rune == 0x3000) {
        out.write(' ');
        continue;
      }
      if (rune == 0xFF0C) {
        out.write(',');
        continue;
      }
      if (rune == 0xFF0E) {
        out.write('.');
        continue;
      }
      if (rune == 0xFFE5) {
        out.write('¥');
        continue;
      }
      if (rune >= 0xFF10 && rune <= 0xFF19) {
        out.writeCharCode(rune - 0xFEE0);
        continue;
      }
      if (rune >= 0xFF21 && rune <= 0xFF3A) {
        out.writeCharCode(rune - 0xFEE0);
        continue;
      }
      if (rune >= 0xFF41 && rune <= 0xFF5A) {
        out.writeCharCode(rune - 0xFEE0);
        continue;
      }
      out.writeCharCode(rune);
    }

    return out.toString();
  }
}
