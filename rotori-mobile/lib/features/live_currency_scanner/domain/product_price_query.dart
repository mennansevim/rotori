import 'dart:math' as math;
import 'dart:ui' show Rect;

/// Türkiye tarafında fiyat karşılaştırması yapılacak pazar kaynakları.
enum ProductPriceSource { hepsiburada, trendyol, amazon }

extension ProductPriceSourceX on ProductPriceSource {
  String get id => switch (this) {
        ProductPriceSource.hepsiburada => 'hepsiburada',
        ProductPriceSource.trendyol => 'trendyol',
        ProductPriceSource.amazon => 'amazon',
      };
}

/// Tek kaynak sorgusunun anlık durumu.
enum ProductPriceSourceStatus { pending, loading, success, failed }

/// Ürün fiyat sorgusunun üst seviye akış durumu.
enum ProductPriceQueryStatus { idle, loading, completed, failed }

/// Kamerada sorgulanabilir olarak işaretlenen ürün adayı.
class ProductQueryCandidate {
  const ProductQueryCandidate({
    required this.id,
    required this.title,
    required this.amountInJpy,
    required this.boundingBox,
    required this.confidence,
    this.searchHints = const [],
  });

  final String id;
  final String title;

  /// Kamerada algılanan referans Japon Yeni fiyatı.
  final int amountInJpy;

  /// OCR görüntü koordinatındaki tahmini ürün alanı.
  final Rect boundingBox;

  /// 0..1 arası aday güveni.
  final double confidence;

  /// Backend sorgusunda kullanılabilecek ek token/hint listesi.
  final List<String> searchHints;
}

/// Tek market kaynağından dönen fiyat girdisi.
class ProductMarketQuote {
  const ProductMarketQuote({
    required this.source,
    required this.matchedTitle,
    required this.priceTry,
    required this.confidence,
    required this.fetchedAt,
    required this.isEstimated,
    this.deeplink,
  });

  final ProductPriceSource source;
  final String matchedTitle;
  final double priceTry;
  final double confidence;
  final DateTime fetchedAt;
  final bool isEstimated;
  final String? deeplink;
}

/// UI'da her kaynak için ilerleme satırı.
class ProductPriceSourceProgress {
  const ProductPriceSourceProgress({
    required this.source,
    required this.status,
    this.quote,
  });

  final ProductPriceSource source;
  final ProductPriceSourceStatus status;
  final ProductMarketQuote? quote;

  ProductPriceSourceProgress copyWith({
    ProductPriceSourceStatus? status,
    ProductMarketQuote? quote,
  }) {
    return ProductPriceSourceProgress(
      source: source,
      status: status ?? this.status,
      quote: quote ?? this.quote,
    );
  }
}

/// Japonya referans fiyatı ile TR market fiyatlarının özet karşılaştırması.
class ProductPriceComparison {
  const ProductPriceComparison({
    required this.candidate,
    required this.japanPriceTry,
    required this.turkeyMedianTry,
    required this.turkeyMinTry,
    required this.turkeyMaxTry,
    required this.differenceTry,
    required this.differenceRatio,
    required this.quotes,
  });

  final ProductQueryCandidate candidate;
  final double japanPriceTry;
  final double turkeyMedianTry;
  final double turkeyMinTry;
  final double turkeyMaxTry;

  /// TR medyan - JP referans. Pozitifse Japonya daha ucuz.
  final double differenceTry;

  /// [differenceTry] / [japanPriceTry].
  final double differenceRatio;

  final List<ProductMarketQuote> quotes;

  bool get isJapanCheaper => differenceTry > 0;

  factory ProductPriceComparison.fromQuotes({
    required ProductQueryCandidate candidate,
    required double japanPriceTry,
    required List<ProductMarketQuote> quotes,
  }) {
    final values = quotes.map((q) => q.priceTry).toList()..sort();
    if (values.isEmpty) {
      return ProductPriceComparison(
        candidate: candidate,
        japanPriceTry: japanPriceTry,
        turkeyMedianTry: japanPriceTry,
        turkeyMinTry: japanPriceTry,
        turkeyMaxTry: japanPriceTry,
        differenceTry: 0,
        differenceRatio: 0,
        quotes: const [],
      );
    }

    final min = values.first;
    final max = values.last;
    final median = _median(values);
    final diff = median - japanPriceTry;
    final ratio = japanPriceTry <= 0 ? 0.0 : diff / japanPriceTry;

    return ProductPriceComparison(
      candidate: candidate,
      japanPriceTry: japanPriceTry,
      turkeyMedianTry: median,
      turkeyMinTry: min,
      turkeyMaxTry: max,
      differenceTry: diff,
      differenceRatio: ratio,
      quotes: quotes,
    );
  }

  static double _median(List<double> sortedValues) {
    final n = sortedValues.length;
    final mid = n ~/ 2;
    if (n.isOdd) return sortedValues[mid];
    return (sortedValues[mid - 1] + sortedValues[mid]) / 2;
  }

  ProductPriceComparison withSortedQuotes() {
    final sorted = [...quotes]
      ..sort((a, b) {
        final ia = ProductPriceSource.values.indexOf(a.source);
        final ib = ProductPriceSource.values.indexOf(b.source);
        return ia.compareTo(ib);
      });
    return ProductPriceComparison(
      candidate: candidate,
      japanPriceTry: japanPriceTry,
      turkeyMedianTry: turkeyMedianTry,
      turkeyMinTry: turkeyMinTry,
      turkeyMaxTry: turkeyMaxTry,
      differenceTry: differenceTry,
      differenceRatio: differenceRatio,
      quotes: sorted,
    );
  }

  double clampedDifferencePercent({double min = -0.99, double max = 9.99}) {
    return (differenceRatio * 100).clamp(min, max).toDouble();
  }

  double normalizedSpread() {
    if (turkeyMedianTry <= 0) return 0;
    return ((turkeyMaxTry - turkeyMinTry) / math.max(1, turkeyMedianTry))
        .clamp(0, 1)
        .toDouble();
  }
}
