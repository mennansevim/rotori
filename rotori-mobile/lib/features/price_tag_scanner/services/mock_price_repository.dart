import 'dart:math' as math;

/// Hepsiburada / Trendyol / Amazon TR için gecikmeli mock fiyat servisi.
///
/// Dış API yerine deterministic JSON döndürür; UI/akış geliştirmede gerçek
/// ağa bağlanmadan stabil sonuç üretir.
class MockPriceRepository {
  const MockPriceRepository({
    this.delay = const Duration(seconds: 1),
  });

  final Duration delay;

  Future<Map<String, dynamic>> fetchMarketplacePrices({
    required String productModel,
    required double referenceTryPrice,
  }) async {
    await Future<void>.delayed(delay);

    final normalizedModel = productModel.trim().toUpperCase();
    final safeBase = referenceTryPrice <= 0 ? 1.0 : referenceTryPrice;
    final seed = _stableHash(normalizedModel);

    final hepsiburada = _buildPlatformPrice(
      seed: seed,
      salt: 11,
      platform: 'Hepsiburada',
      basePriceTry: safeBase,
      minFactor: 1.18,
      maxFactor: 1.40,
      searchUrl: _searchUrl('Hepsiburada', normalizedModel),
      model: normalizedModel,
    );

    final trendyol = _buildPlatformPrice(
      seed: seed,
      salt: 23,
      platform: 'Trendyol',
      basePriceTry: safeBase,
      minFactor: 1.16,
      maxFactor: 1.36,
      searchUrl: _searchUrl('Trendyol', normalizedModel),
      model: normalizedModel,
    );

    final amazon = _buildPlatformPrice(
      seed: seed,
      salt: 37,
      platform: 'Amazon TR',
      basePriceTry: safeBase,
      minFactor: 1.22,
      maxFactor: 1.48,
      searchUrl: _searchUrl('Amazon TR', normalizedModel),
      model: normalizedModel,
    );

    return <String, dynamic>{
      'model': normalizedModel,
      'currency': 'TRY',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'platforms': <Map<String, dynamic>>[
        hepsiburada,
        trendyol,
        amazon,
      ],
    };
  }

  /// Model koduna göre ilgili pazar yerinin GERÇEK arama sayfası URL'si.
  /// (Fiyat mock; ancak bu link kullanıcıyı gerçek arama sonuçlarına götürür.)
  String _searchUrl(String platform, String model) {
    final q = Uri.encodeQueryComponent(model);
    switch (platform) {
      case 'Hepsiburada':
        return 'https://www.hepsiburada.com/ara?q=$q';
      case 'Trendyol':
        return 'https://www.trendyol.com/sr?q=$q';
      case 'Amazon TR':
        return 'https://www.amazon.com.tr/s?k=$q';
      default:
        return 'https://www.google.com/search?q=$q';
    }
  }

  Map<String, dynamic> _buildPlatformPrice({
    required int seed,
    required int salt,
    required String platform,
    required double basePriceTry,
    required double minFactor,
    required double maxFactor,
    required String searchUrl,
    required String model,
  }) {
    final factor = _interpolate(seed, salt, minFactor, maxFactor);
    final price = math.max(1, (basePriceTry * factor).round());
    final confidence = _interpolate(seed, salt * 3, 0.82, 0.97);

    return <String, dynamic>{
      'platform': platform,
      'model': model,
      'priceTry': price,
      'currency': 'TRY',
      'url': searchUrl,
      'inStock': ((seed + salt) % 7) != 0,
      'confidence': double.parse(confidence.toStringAsFixed(2)),
      'isMock': true,
    };
  }

  double _interpolate(int seed, int salt, double min, double max) {
    final value = ((seed >> (salt % 13)) & 0xFF) / 255.0;
    return min + (max - min) * value;
  }

  int _stableHash(String input) {
    var hash = 17;
    for (final code in input.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash;
  }
}
