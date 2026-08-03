import 'package:decimal/decimal.dart';

import 'currency_code.dart';

/// Bir para birimi çifti için normalize edilmiş kur: `1 JPY = [rate] TARGET`.
///
/// [rate] her zaman `1 baz birim = X hedef birim` biçiminde normalize edilir.
/// Hassasiyet için [Decimal] kullanılır — double kayması yok. [isManual] kur
/// kullanıcı tarafından elle girildiyse true olur ve remote kur bunun üzerine
/// yazılmaz.
class ExchangeRate {
  ExchangeRate({
    required this.baseCurrency,
    required this.targetCurrency,
    required this.rate,
    required this.fetchedAt,
    required this.source,
    this.isManual = false,
  });

  /// Baz ISO kodu — bu üründe her zaman `JPY`.
  final String baseCurrency;

  /// Hedef ISO kodu (ör. `TRY`).
  final String targetCurrency;

  /// `1 baz = rate hedef`.
  final Decimal rate;

  /// Kurun elde edildiği/girildiği an.
  final DateTime fetchedAt;

  /// Kaynak etiketi (ör. `supabase`, `manual`, `fallback`).
  final String source;

  /// Kullanıcı tarafından elle girilmiş kur mu?
  final bool isManual;

  ExchangeRate copyWith({
    String? baseCurrency,
    String? targetCurrency,
    Decimal? rate,
    DateTime? fetchedAt,
    String? source,
    bool? isManual,
  }) {
    return ExchangeRate(
      baseCurrency: baseCurrency ?? this.baseCurrency,
      targetCurrency: targetCurrency ?? this.targetCurrency,
      rate: rate ?? this.rate,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      source: source ?? this.source,
      isManual: isManual ?? this.isManual,
    );
  }

  Map<String, dynamic> toJson() => {
        'base_currency': baseCurrency,
        'target_currency': targetCurrency,
        'rate': rate.toString(),
        'fetched_at': fetchedAt.toUtc().toIso8601String(),
        'source': source,
        'is_manual': isManual,
      };

  static ExchangeRate fromJson(Map<String, dynamic> json) => ExchangeRate(
        baseCurrency:
            (json['base_currency'] as String?) ?? CurrencyCode.baseIso,
        targetCurrency: (json['target_currency'] as String?) ?? 'TRY',
        rate: Decimal.parse('${json['rate']}'),
        fetchedAt: DateTime.tryParse('${json['fetched_at']}')?.toUtc() ??
            DateTime.now().toUtc(),
        source: (json['source'] as String?) ?? 'unknown',
        isManual: (json['is_manual'] as bool?) ?? false,
      );

  /// [now] anına göre kurun yaşı.
  Duration ageFrom(DateTime now) => now.toUtc().difference(fetchedAt.toUtc());
}
