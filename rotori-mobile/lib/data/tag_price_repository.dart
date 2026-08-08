import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/price_tag_scanner/services/mock_price_repository.dart';

/// TR pazar yeri fiyat servisi.
///
/// Primary: Supabase Edge Function `fetch-tr-prices` → gerçek scraping.
/// Fallback: `MockPriceRepository` → deterministic mock (geliştirme / hata durumu).
class TagPriceRepository {
  const TagPriceRepository({
    required this.supabase,
    this.mock = const MockPriceRepository(),
  });

  final SupabaseClient supabase;
  final MockPriceRepository mock;

  /// Ürün modeli ve JP referans fiyatına göre TR pazar fiyatlarını getirir.
  ///
  /// Edge Function başarısız olursa mock'a düşer.
  Future<Map<String, dynamic>> fetchMarketplacePrices({
    required String productModel,
    required double referenceTryPrice,
    int? referenceJpyPrice,
  }) async {
    try {
      final response = await supabase.functions.invoke(
        'fetch-tr-prices',
        method: HttpMethod.post,
        body: jsonEncode({
          'productModel': productModel,
          'referenceJpyPrice': referenceJpyPrice,
        }),
      );

      if (response.status >= 200 && response.status < 300) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return _normalizePriceData(data, productModel);
        }
      }

      // Edge Function başarısız → mock
      return await _mockFallback(productModel, referenceTryPrice);
    } catch (_) {
      return await _mockFallback(productModel, referenceTryPrice);
    }
  }

  /// Edge Function response'u ScannerController'ın beklediği formata çevirir.
  Map<String, dynamic> _normalizePriceData(
    Map<String, dynamic> raw,
    String model,
  ) {
    final platformsRaw = raw['platforms'];
    final platforms = <Map<String, dynamic>>[];

    if (platformsRaw is List) {
      for (final item in platformsRaw) {
        if (item is Map<String, dynamic>) {
          platforms.add({
            'platform': item['platform']?.toString() ?? '-',
            'model': model,
            'priceTry': item['priceTry'] is num
                ? (item['priceTry'] as num).toInt()
                : 0,
            'currency': 'TRY',
            'url': item['url']?.toString() ?? '',
            'inStock': item['inStock'] == true,
            'confidence': item['confidence']?.toString() ?? 'low',
            'source': item['source']?.toString() ?? 'fallback',
            'title': item['title']?.toString(),
            'isReal': true,
          });
        }
      }
    }

    return {
      'model': model,
      'currency': 'TRY',
      'updatedAt': raw['updatedAt'] ?? DateTime.now().toUtc().toIso8601String(),
      'platforms': platforms,
      'isReal': true,
    };
  }

  Future<Map<String, dynamic>> _mockFallback(
    String model,
    double referenceTryPrice,
  ) async {
    final result = await mock.fetchMarketplacePrices(
      productModel: model,
      referenceTryPrice: referenceTryPrice,
    );
    result['isReal'] = false;
    return result;
  }
}
