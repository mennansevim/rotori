import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase Edge Function `parse-price-tag` için client.
///
/// Cihazdaki OCR metnini alır, GPT-4o-mini ile yapılandırılmış ürün
/// bilgisine çevirir. Kasko/garanti/aksesuar fiyatlarını asıl üründen ayırır.
class TagScannerClient {
  const TagScannerClient({required this.supabase});

  final SupabaseClient supabase;

  /// Edge Function'a OCR metnini gönderir, LLM sonucunu döndürür.
  ///
  /// [ocrLines] — kameradan okunan metin satırları (ham).
  /// [region] — mağaza ülkesi (varsayılan: Japan).
  ///
  /// Başarısız olursa [TagScanResult] döner. Hata durumunda exception fırlatır.
  Future<TagScanResult> parse({
    required List<String> ocrLines,
    String region = 'Japan',
  }) async {
    final ocrText = ocrLines.join('\n');

    final response = await supabase.functions.invoke(
      'parse-price-tag',
      method: HttpMethod.post,
      body: jsonEncode({
        'ocrText': ocrText,
        'region': region,
      }),
    );

    if (response.status == 429) {
      final body = response.data is Map ? response.data as Map<String, dynamic> : <String, dynamic>{};
      final limit = body['limit'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      throw TagScannerLimitExceeded(
        remaining: (limit['remaining'] as num?)?.toInt() ?? 0,
        premium: limit['premium'] as bool? ?? false,
      );
    }

    if (response.status >= 400) {
      final body = response.data is Map ? response.data as Map<String, dynamic> : <String, dynamic>{};
      final error = body['error']?.toString() ?? 'Unknown error';
      throw TagScannerApiException('Edge Function error (${response.status}): $error');
    }

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw TagScannerApiException('Unexpected response type: ${data.runtimeType}');
    }

    return TagScanResult.fromJson(data);
  }
}

/// Edge Function'dan dönen yapılandırılmış etiket sonucu.
class TagScanResult {
  const TagScanResult({
    required this.productModel,
    required this.brand,
    required this.mainPriceJpy,
    required this.taxIncluded,
    required this.prices,
    required this.confidence,
    required this.cached,
    this.limitRemaining,
    this.limitPremium,
  });

  final String? productModel;
  final String? brand;
  final int? mainPriceJpy;
  final bool taxIncluded;
  final List<PriceItem> prices;
  final double confidence;
  final bool cached;
  final int? limitRemaining;
  final bool? limitPremium;

  /// İkincil fiyatlar (kasko, garanti, aksesuar).
  List<PriceItem> get secondaryPrices =>
      prices.where((p) => !p.isMainPrice).toList();

  /// Ana ürün dışında kaç tane yan fiyat tespit edilmiş.
  int get secondaryCount => secondaryPrices.length;

  factory TagScanResult.fromJson(Map<String, dynamic> json) {
    final pricesRaw = json['prices'];
    final prices = <PriceItem>[];
    if (pricesRaw is List) {
      for (final item in pricesRaw) {
        if (item is Map<String, dynamic>) {
          prices.add(PriceItem.fromJson(item));
        }
      }
    }

    final limit = json['limit'];
    final limitMap = limit is Map<String, dynamic> ? limit : null;

    return TagScanResult(
      productModel: json['productModel']?.toString(),
      brand: json['brand']?.toString(),
      mainPriceJpy: json['mainPriceJpy'] is int
          ? json['mainPriceJpy'] as int
          : (json['mainPriceJpy'] is num
              ? (json['mainPriceJpy'] as num).round()
              : null),
      taxIncluded: json['taxIncluded'] == true,
      prices: prices,
      confidence: (json['confidence'] is num)
          ? (json['confidence'] as num).toDouble()
          : 0.5,
      cached: json['cached'] == true,
      limitRemaining:
          limitMap?['remaining'] is int ? limitMap!['remaining'] as int : null,
      limitPremium: limitMap?['premium'] is bool
          ? limitMap!['premium'] as bool
          : null,
    );
  }
}

class PriceItem {
  const PriceItem({
    required this.label,
    required this.amountJpy,
    required this.isMainPrice,
    required this.category,
  });

  final String label;
  final int amountJpy;
  final bool isMainPrice;
  final PriceCategory category;

  factory PriceItem.fromJson(Map<String, dynamic> json) {
    return PriceItem(
      label: json['label']?.toString() ?? '',
      amountJpy: json['amountJpy'] is int
          ? json['amountJpy'] as int
          : (json['amountJpy'] is num
              ? (json['amountJpy'] as num).round()
              : 0),
      isMainPrice: json['isMainPrice'] == true,
      category: _parseCategory(json['category']?.toString()),
    );
  }

  static PriceCategory _parseCategory(String? raw) {
    switch (raw) {
      case 'main_product':
        return PriceCategory.mainProduct;
      case 'warranty':
        return PriceCategory.warranty;
      case 'accessory':
        return PriceCategory.accessory;
      case 'tax':
        return PriceCategory.tax;
      case 'point':
        return PriceCategory.point;
      case 'discount':
        return PriceCategory.discount;
      default:
        return PriceCategory.other;
    }
  }
}

enum PriceCategory {
  mainProduct,
  warranty,
  accessory,
  tax,
  point,
  discount,
  other,
}

/// Günlük tarama limiti aşıldı.
class TagScannerLimitExceeded implements Exception {
  const TagScannerLimitExceeded({
    required this.remaining,
    required this.premium,
  });

  final int remaining;
  final bool premium;

  @override
  String toString() => premium
      ? 'TagScannerLimitExceeded(premium user, should not happen)'
      : 'Günlük 10 ücretsiz tarama hakkınız doldu. Premium\'a geçin.'
      ;
}

class TagScannerApiException implements Exception {
  const TagScannerApiException(this.message);

  final String message;

  @override
  String toString() => 'TagScannerApiException: $message';
}
