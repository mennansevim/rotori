// Canlı döviz kuru — açılışta çeker, kalıcı cache'ler.
//
// **Why:** Kurlar sabit varsayılanlardı (1 ¥ = 0.25 ₺) ve kullanıcı elle
// güncellemedikçe aylarca eski kalıyordu. Gerçek kur bunun ~%20 üstündeydi;
// bütçe ekranı yanlış rakam gösteriyordu.
//
// Sözleşme:
//  • Kaynak: open.er-api.com (anahtar gerektirmez, ECB/ticari besleme karması)
//  • Çağrı: uygulama açılışında BİR kez; ağ yoksa sessizce vazgeçilir.
//  • KULLANICININ ELLE GİRDİĞİ KUR EZİLMEZ — canlı kur yalnızca kullanıcı
//    hiç dokunmamışsa ya da açıkça "güncelle" derse uygulanır.
//  • Çevrimdışıda son bilinen kur kullanılır; hiç yoksa varsayılan.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// JPY tabanlı canlı kur uç noktası (API anahtarı gerektirmez).
const String kLiveFxEndpoint = 'https://open.er-api.com/v6/latest/JPY';

/// Bu süreden yeni bir cache varsa ağa çıkılmaz.
const Duration kFxFreshFor = Duration(hours: 12);

/// Ağdan dönen kur seti — "1 ¥ = X <birim>".
class LiveFxRates {
  const LiveFxRates({
    required this.jpyToTry,
    required this.jpyToUsd,
    required this.jpyToEur,
    required this.fetchedAt,
  });

  final double jpyToTry;
  final double jpyToUsd;
  final double jpyToEur;
  final DateTime fetchedAt;

  Map<String, dynamic> toJson() => {
        'try': jpyToTry,
        'usd': jpyToUsd,
        'eur': jpyToEur,
        'at': fetchedAt.toIso8601String(),
      };

  static LiveFxRates? fromJson(Map<String, dynamic> j) {
    final t = (j['try'] as num?)?.toDouble();
    final u = (j['usd'] as num?)?.toDouble();
    final e = (j['eur'] as num?)?.toDouble();
    final at = DateTime.tryParse('${j['at']}');
    if (t == null || u == null || e == null || at == null) return null;
    if (!_sane(t) || !_sane(u) || !_sane(e)) return null;
    return LiveFxRates(
      jpyToTry: t,
      jpyToUsd: u,
      jpyToEur: e,
      fetchedAt: at,
    );
  }

  /// Uç nokta bozuk/şaka değer dönerse bütçeyi mahvetmesin diye kaba
  /// akıl sağlığı kontrolü. 1 ¥ hiçbir para biriminde 10 birimden fazla
  /// etmez ve 0 olamaz.
  static bool _sane(double v) => v.isFinite && v > 0 && v < 10;
}

/// Canlı kuru çeken servis. Ağ hatası ATMAZ — null döner.
class LiveFxService {
  const LiveFxService({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<LiveFxRates?> fetch() async {
    final client = _client ?? http.Client();
    try {
      final res = await client
          .get(Uri.parse(kLiveFxEndpoint))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      final body = jsonDecode(res.body);
      if (body is! Map<String, dynamic>) return null;
      if (body['result'] != 'success') return null;

      final rates = body['rates'];
      if (rates is! Map) return null;

      double? pick(String code) {
        final v = rates[code];
        return v is num ? v.toDouble() : null;
      }

      final t = pick('TRY');
      final u = pick('USD');
      final e = pick('EUR');
      if (t == null || u == null || e == null) return null;
      if (!LiveFxRates._sane(t) ||
          !LiveFxRates._sane(u) ||
          !LiveFxRates._sane(e)) {
        return null;
      }

      final at = DateTime.tryParse('${body['time_last_update_utc']}') ??
          DateTime.now().toUtc();

      return LiveFxRates(
        jpyToTry: t,
        jpyToUsd: u,
        jpyToEur: e,
        fetchedAt: at,
      );
    } catch (_) {
      // Ağ yok / zaman aşımı / bozuk gövde — sessizce vazgeç, cache kalsın.
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }
}

final liveFxServiceProvider =
    Provider<LiveFxService>((ref) => const LiveFxService());
