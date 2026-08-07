import '../../domain/japanese_price_tax_type.dart';
import '../../domain/scanner_tuning.dart';
import 'japanese_text_normalizer.dart';

/// Parser'ın bir metin satırından çıkardığı ham fiyat adayı (kutusuz).
class PriceCandidate {
  const PriceCandidate({
    required this.amountInJpy,
    required this.taxType,
    required this.confidence,
    required this.rawText,
  });

  final int amountInJpy;
  final JapanesePriceTaxType taxType;
  final double confidence;
  final String rawText;

  @override
  String toString() =>
      'PriceCandidate(¥$amountInJpy, ${taxType.name}, ${confidence.toStringAsFixed(2)})';
}

/// Japon-yeni fiyat metnini ayrıştırır.
///
/// Saf Dart, durumsuz. Her sayıyı fiyat SAYMAZ: bir sayının fiyat kabul
/// edilmesi için yakınında `¥ ￥ 円 JPY` para işareti **veya** vergi etiketi
/// bulunmalıdır. Yüzde, tarih, saat, telefon, ürün kodu gibi bağlamlar elenir.
class JapanesePriceParser {
  const JapanesePriceParser({
    this.normalizer = const JapaneseTextNormalizer(),
  });

  final JapaneseTextNormalizer normalizer;

  // Bir sayının fiyat OLMADIĞINI gösteren bağlam birimleri (hemen ardından).
  static final RegExp _rejectSuffixUnit =
      RegExp(r'^\s*(年|月|日|時|分|秒|%|％|個|点|名|人|番|号|才|歳|g|kg|ml|L|cm|mm|km|m)');

  // Para işaretleri.
  static const String _yenMarks = r'¥￥';

  /// Bir bloktaki tüm satırları ayrıştırıp aday listesi döndürür.
  List<PriceCandidate> parse(String text) {
    final candidates = <PriceCandidate>[];
    for (final rawLine in text.split(RegExp(r'[\r\n]+'))) {
      candidates.addAll(parseLine(rawLine));
    }
    return resolveTaxPairs(candidates);
  }

  /// Tek satırdan aday fiyatları çıkarır.
  List<PriceCandidate> parseLine(String rawLine) {
    final line = normalizer.normalize(rawLine);
    if (line.isEmpty) return const [];

    final taxType = _detectTaxType(line);
    final results = <PriceCandidate>[];

    // Sayı token'ı: 12,800 / 1.280 / 980 (isteğe bağlı grup ayırıcılı).
    final numberPattern = RegExp(r'\d[\d.,]*\d|\d');
    for (final match in numberPattern.allMatches(line)) {
      final token = match.group(0)!;
      final start = match.start;
      final end = match.end;

      if (_looksLikeTime(line, start, end)) continue;
      if (_looksLikePhoneOrCode(line, start, end)) continue;

      // Ardından gelen bağlam birimi (年/月/%/個 ...) → fiyat değil.
      final after = line.substring(end);
      if (_rejectSuffixUnit.hasMatch(after)) continue;

      // Harf/kod komşuluğu → ürün/model kodu.
      if (_hasAlphaNeighbor(line, start, end)) continue;

      final amount = _interpretJpy(token);
      if (amount == null) continue;

      final hasCurrency = _currencyContext(line, start, end);
      final hasTaxLabel = taxType != JapanesePriceTaxType.unknown;

      // Para işareti veya vergi etiketi yoksa fiyat kabul etme (temkinli).
      if (!hasCurrency && !hasTaxLabel) continue;

      // Aralık dışı → ele.
      if (amount < ScannerTuning.minPlausibleJpy) continue;

      var confidence = ScannerTuning.baseConfidence;
      if (hasCurrency) confidence += ScannerTuning.currencyMarkBonus;
      if (hasTaxLabel) confidence += ScannerTuning.taxLabelBonus;
      if (amount >= ScannerTuning.minPlausibleJpy &&
          amount <= ScannerTuning.maxPlausibleJpy) {
        confidence += ScannerTuning.plausibleRangeBonus;
      } else {
        confidence -= ScannerTuning.plausibleRangeBonus; // şüpheli büyük değer
      }
      confidence = confidence.clamp(0.0, 1.0);

      results.add(PriceCandidate(
        amountInJpy: amount,
        taxType: taxType,
        confidence: confidence,
        rawText: token,
      ));
    }
    return results;
  }

  /// Aynı ürüne ait 税込/税抜 çiftinde vergi dahil olanı bırakır.
  List<PriceCandidate> resolveTaxPairs(List<PriceCandidate> candidates) {
    if (candidates.length < 2) return candidates;
    final included = candidates.where((c) => c.taxType.isIncluded).toList();
    final excluded = candidates.where((c) => c.taxType.isExcluded).toList();
    if (included.isEmpty || excluded.isEmpty) return candidates;

    final drop = <PriceCandidate>{};
    for (final inc in included) {
      for (final exc in excluded) {
        if (drop.contains(exc)) continue;
        final ratio = inc.amountInJpy / exc.amountInJpy;
        if (ratio >= ScannerTuning.taxPairMinRatio &&
            ratio <= ScannerTuning.taxPairMaxRatio) {
          drop.add(exc); // vergi hariç olanı ana gösterimden çıkar
        }
      }
    }
    return candidates.where((c) => !drop.contains(c)).toList();
  }

  // --- İç yardımcılar ------------------------------------------------------

  JapanesePriceTaxType _detectTaxType(String line) {
    if (line.contains('税込')) return JapanesePriceTaxType.taxIncluded;
    if (line.contains('税抜') || line.contains('本体価格') || line.contains('本体')) {
      return JapanesePriceTaxType.taxExcluded;
    }
    return JapanesePriceTaxType.unknown;
  }

  /// [start,end) aralığındaki sayının hemen öncesinde ¥/￥ ya da sonrasında
  /// 円/JPY bulunuyor mu?
  bool _currencyContext(String line, int start, int end) {
    // Öncesi: boşlukları atla, ¥ veya ￥ ara.
    var i = start - 1;
    while (i >= 0 && line[i] == ' ') {
      i--;
    }
    if (i >= 0 && _yenMarks.contains(line[i])) return true;

    // Sonrası: boşlukları atla, 円 veya JPY ara.
    var j = end;
    while (j < line.length && line[j] == ' ') {
      j++;
    }
    if (j < line.length) {
      if (line[j] == '円') return true;
      final tail = line.substring(j);
      if (tail.startsWith('JPY') || tail.startsWith('jpy')) return true;
    }
    return false;
  }

  bool _looksLikeTime(String line, int start, int end) {
    // 12:30 gibi — sayının hemen öncesi/sonrası ':' ise saat.
    if (end < line.length && line[end] == ':') return true;
    if (start > 0 && line[start - 1] == ':') return true;
    return false;
  }

  bool _looksLikePhoneOrCode(String line, int start, int end) {
    // 03-1234-5678 gibi — sayının komşusunda '-' ve iki tarafında rakam grubu.
    final beforeDash = start > 0 && line[start - 1] == '-';
    final afterDash = end < line.length && line[end] == '-';
    return beforeDash || afterDash;
  }

  bool _hasAlphaNeighbor(String line, int start, int end) {
    final alpha = RegExp(r'[A-Za-z]');
    if (start > 0 && alpha.hasMatch(line[start - 1])) return true;
    if (end < line.length && alpha.hasMatch(line[end])) return true;
    return false;
  }

  /// Token'ı tam sayı yene çevirir.
  ///
  /// JPY'nin ondalık (kuruş) birimi yoktur; bu yüzden fiyat içindeki her `,`
  /// veya `.` daima binlik ayırıcıdır (ya da OCR gürültüsü) — asla ondalık
  /// değildir. Virgül mü nokta mı ayrımı yapmaya gerek yok: ikisini de kaldırıp
  /// kalan rakamları tam sayı olarak okuruz. `¥2,999` `¥2.999` `2 999` → 2999.
  int? _interpretJpy(String token) {
    final digitsOnly = token.replaceAll(RegExp(r'[.,]'), '');
    return int.tryParse(digitsOnly);
  }
}
