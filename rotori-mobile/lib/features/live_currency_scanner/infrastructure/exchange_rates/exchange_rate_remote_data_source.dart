import 'package:decimal/decimal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/exchange_rate.dart';

/// Kuru Supabase `exchange_rates` tablosundan okur. Yazma yetkisi istemcide
/// YOKtur — değerleri güvenilir backend/Edge Function yazar (RLS ile korunur).
class ExchangeRateRemoteDataSource {
  ExchangeRateRemoteDataSource(this._client);

  final SupabaseClient _client;

  /// `1 [base] = X [target]` kurunu döndürür; kayıt yoksa null.
  Future<ExchangeRate?> fetch({
    required String base,
    required String target,
  }) async {
    final row = await _client
        .from('exchange_rates')
        .select('base_currency,target_currency,rate,source,fetched_at')
        .eq('base_currency', base)
        .eq('target_currency', target)
        .maybeSingle();
    if (row == null) return null;
    return ExchangeRate(
      baseCurrency: row['base_currency'] as String,
      targetCurrency: row['target_currency'] as String,
      rate: Decimal.parse('${row['rate']}'),
      fetchedAt: DateTime.tryParse('${row['fetched_at']}')?.toUtc() ??
          DateTime.now().toUtc(),
      source: (row['source'] as String?) ?? 'supabase',
      isManual: false,
    );
  }
}
