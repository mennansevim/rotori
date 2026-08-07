import '../product_price_query.dart';

/// Kamerada yakalanan ürün için market kaynaklarından fiyat getirir.
abstract interface class ProductPriceQueryRepository {
  Future<ProductMarketQuote> fetchQuote({
    required ProductPriceSource source,
    required ProductQueryCandidate candidate,
    required double japanPriceTry,
  });
}
