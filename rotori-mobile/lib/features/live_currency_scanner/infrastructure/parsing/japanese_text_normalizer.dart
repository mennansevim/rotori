/// Japon fiyat metinlerini kanonik biçime indirger.
///
/// Saf Dart, durumsuz. OCR'ın ürettiği tam-genişlik (full-width) rakamlar,
/// noktalama ve para sembolleri yarı-genişliğe (half-width) çevrilir; rakamlar
/// arasındaki boşluklar temizlenir ve 4+ haneli saf rakam dizileri binlik
/// virgülüyle yeniden gruplanır.
///
/// Örnekler:
///   `１２，８００円`  → `12,800円`
///   `￥９８０`        → `¥980`
///   `12 800 円`      → `12,800円`
class JapaneseTextNormalizer {
  const JapaneseTextNormalizer();

  static const int _fullwidthStart = 0xFF01;
  static const int _fullwidthEnd = 0xFF5E;
  static const int _fullwidthToAsciiOffset = 0xFEE0;
  static const int _ideographicSpace = 0x3000;
  static const int _fullwidthYen = 0xFFE5; // ￥
  static const int _halfwidthYen = 0x00A5; // ¥
  static const int _space = 0x20;

  String normalize(String input) {
    final folded = _foldWidth(input);
    final despaced = _stripInnerNumericSpaces(folded);
    final regrouped = _regroupThousands(despaced);
    return regrouped.trim();
  }

  /// Tam-genişlik karakterleri yarı-genişliğe indirger; ￥ → ¥.
  String _foldWidth(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune == _fullwidthYen) {
        buffer.writeCharCode(_halfwidthYen);
      } else if (rune == _ideographicSpace) {
        buffer.writeCharCode(_space);
      } else if (rune >= _fullwidthStart && rune <= _fullwidthEnd) {
        buffer.writeCharCode(rune - _fullwidthToAsciiOffset);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

  bool _isCurrencyMark(int code) =>
      code == _halfwidthYen || // ¥
      code == 0x5186; // 円

  /// İki rakam arasındaki ya da rakam ile para işareti arasındaki tek boşluğu
  /// kaldırır. `12 800 円` → `12800円`.
  String _stripInnerNumericSpaces(String input) {
    final codes = input.runes.toList();
    final out = <int>[];
    for (var i = 0; i < codes.length; i++) {
      final c = codes[i];
      if (c == _space) {
        final prev = out.isNotEmpty ? out.last : -1;
        final next = i + 1 < codes.length ? codes[i + 1] : -1;
        final prevOk = _isDigit(prev) || _isCurrencyMark(prev);
        final nextOk = _isDigit(next) || _isCurrencyMark(next);
        if (prevOk && nextOk) {
          continue; // boşluğu at
        }
      }
      out.add(c);
    }
    return String.fromCharCodes(out);
  }

  /// 4+ haneli, virgülsüz saf rakam dizilerini binlik virgülüyle gruplar.
  /// Zaten gruplu (`12,800`) veya kısa (`980`) diziler değişmez.
  String _regroupThousands(String input) {
    return input.replaceAllMapped(RegExp(r'(?<![\d,\.])\d{4,}(?![\d,\.])'),
        (m) {
      final digits = m.group(0)!;
      return _groupDigits(digits);
    });
  }

  String _groupDigits(String digits) {
    final buffer = StringBuffer();
    final n = digits.length;
    for (var i = 0; i < n; i++) {
      if (i > 0 && (n - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
