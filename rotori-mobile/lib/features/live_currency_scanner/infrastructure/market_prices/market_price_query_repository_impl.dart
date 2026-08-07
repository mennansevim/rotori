import 'dart:async';

import '../../domain/product_price_query.dart';
import '../../domain/repositories/product_price_query_repository.dart';

/// Gerçek backend gelene kadar demo/önizleme için deterministik fiyat üretir.
///
/// Not: Bu implementasyon canlı pazar verisi çekmez; UI/akış doğrulama içindir.
class MarketPriceQueryRepositoryImpl implements ProductPriceQueryRepository {
  const MarketPriceQueryRepositoryImpl();

  @override
  Future<ProductMarketQuote> fetchQuote({
    required ProductPriceSource source,
    required ProductQueryCandidate candidate,
    required double japanPriceTry,
  }) async {
    final seed = _stableHash('${candidate.title}|${source.id}|${candidate.amountInJpy}');
    final delayMs = 260 + (seed % 620);
    await Future<void>.delayed(Duration(milliseconds: delayMs));

    final baseMultiplier = switch (source) {
      ProductPriceSource.hepsiburada => 1.30,
      ProductPriceSource.trendyol => 1.27,
      ProductPriceSource.amazon => 1.36,
    };

    final swing = ((seed % 17) - 8) / 100; // -0.08..+0.08
    final multiplier = (baseMultiplier + swing).clamp(1.05, 2.2).toDouble();
    final rawTry = japanPriceTry * multiplier;
    final roundedTry = ((rawTry / 10).round() * 10).toDouble();
    final confidence = (0.68 + ((seed % 19) / 100)).clamp(0.55, 0.92).toDouble();

    return ProductMarketQuote(
      source: source,
      matchedTitle: _matchedTitle(candidate.title, source),
      priceTry: roundedTry,
      confidence: confidence,
      fetchedAt: DateTime.now().toUtc(),
      isEstimated: true,
      deeplink: null,
    );
  }

  String _matchedTitle(String title, ProductPriceSource source) {
    final suffix = switch (source) {
      ProductPriceSource.hepsiburada => 'HB',
      ProductPriceSource.trendyol => 'TY',
      ProductPriceSource.amazon => 'Amazon',
    };
    return '$title · $suffix';
  }

  int _stableHash(String input) {
    var h = 2166136261;
    for (final c in input.codeUnits) {
      h ^= c;
      h = (h * 16777619) & 0x7fffffff;
    }
    return h;
  }
}
