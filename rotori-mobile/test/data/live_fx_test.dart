// Canlı döviz kuru — çekme, doğrulama ve "elle girilen kur ezilmez" kuralı.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rotori/data/exchange_rate_store.dart';
import 'package:rotori/data/live_fx_service.dart';

/// Gerçek uç noktanın döndürdüğü biçim (kısaltılmış).
String _okBody({double tryRate = 0.3021}) => jsonEncode({
      'result': 'success',
      'time_last_update_utc': 'Sun, 09 Aug 2026 00:02:31 +0000',
      'base_code': 'JPY',
      'rates': {'TRY': tryRate, 'USD': 0.006332, 'EUR': 0.005482, 'JPY': 1},
    });

LiveFxService _service(MockClient client) => LiveFxService(client: client);

void main() {
  group('LiveFxService.fetch', () {
    test('başarılı yanıtı ayrıştırır', () async {
      final svc = _service(MockClient((_) async => http.Response(_okBody(), 200)));
      final r = await svc.fetch();

      expect(r, isNotNull);
      expect(r!.jpyToTry, closeTo(0.3021, 1e-9));
      expect(r.jpyToUsd, closeTo(0.006332, 1e-9));
      expect(r.jpyToEur, closeTo(0.005482, 1e-9));
      expect(r.fetchedAt.year, 2026);
    });

    test('JPY tabanlı uç noktaya gider', () async {
      Uri? seen;
      final svc = _service(MockClient((req) async {
        seen = req.url;
        return http.Response(_okBody(), 200);
      }));
      await svc.fetch();
      expect(seen.toString(), kLiveFxEndpoint);
    });

    test('HTTP hatasında null — patlamaz', () async {
      final svc = _service(MockClient((_) async => http.Response('nope', 500)));
      expect(await svc.fetch(), isNull);
    });

    test('ağ istisnasında null — patlamaz', () async {
      final svc = _service(MockClient((_) async => throw Exception('offline')));
      expect(await svc.fetch(), isNull);
    });

    test('bozuk gövdede null', () async {
      final svc = _service(MockClient((_) async => http.Response('{{{', 200)));
      expect(await svc.fetch(), isNull);
    });

    test('result != success ise null', () async {
      final body = jsonEncode({'result': 'error', 'rates': {'TRY': 0.3}});
      final svc = _service(MockClient((_) async => http.Response(body, 200)));
      expect(await svc.fetch(), isNull);
    });

    test('saçma kur reddedilir — bütçeyi bozmasın', () async {
      // 1 ¥ = 999 ₺ olamaz; uç nokta bozulursa sessizce yutmayalım.
      final svc = _service(
        MockClient((_) async => http.Response(_okBody(tryRate: 999), 200)),
      );
      expect(await svc.fetch(), isNull);
    });

    test('sıfır/negatif kur reddedilir', () async {
      for (final bad in [0.0, -1.0]) {
        final svc = _service(
          MockClient((_) async => http.Response(_okBody(tryRate: bad), 200)),
        );
        expect(await svc.fetch(), isNull, reason: '$bad kabul edildi');
      }
    });
  });

  group('kur önceliği', () {
    test('canlı kur varsayılanın üzerine yazar', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer(overrides: [
        liveFxServiceProvider.overrideWithValue(
          _service(MockClient((_) async => http.Response(_okBody(), 200))),
        ),
      ]);
      addTearDown(c.dispose);

      expect(c.read(jpyToTryProvider), kDefaultJpyToTry);
      await c.read(liveFxBootstrapProvider.future);
      expect(c.read(jpyToTryProvider), closeTo(0.3021, 1e-9),
          reason: 'canlı kur uygulanmadı');
    });

    test('KULLANICININ elle girdiği kur canlı kurla EZİLMEZ', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer(overrides: [
        liveFxServiceProvider.overrideWithValue(
          _service(MockClient((_) async => http.Response(_okBody(), 200))),
        ),
      ]);
      addTearDown(c.dispose);

      // Kullanıcı kendi kurunu giriyor.
      await c.read(jpyToTryProvider.notifier).set(0.5);
      expect(c.read(jpyToTryProvider), 0.5);

      await c.read(liveFxBootstrapProvider.future);
      expect(c.read(jpyToTryProvider), 0.5,
          reason: 'elle girilen kur canlı kurla ezildi');
    });

    test('ağ yoksa varsayılan korunur, çökmez', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer(overrides: [
        liveFxServiceProvider.overrideWithValue(
          _service(MockClient((_) async => throw Exception('offline'))),
        ),
      ]);
      addTearDown(c.dispose);

      await c.read(liveFxBootstrapProvider.future);
      expect(c.read(jpyToTryProvider), kDefaultJpyToTry);
    });

    test('cache yazılır ve ikinci açılışta ağa çıkılmaz', () async {
      SharedPreferences.setMockInitialValues({});
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response(_okBody(), 200);
      });

      final c1 = ProviderContainer(overrides: [
        liveFxServiceProvider.overrideWithValue(_service(client)),
      ]);
      await c1.read(liveFxBootstrapProvider.future);
      c1.dispose();
      expect(calls, 1);

      // İkinci açılış — cache taze, ağ çağrısı artmamalı.
      final c2 = ProviderContainer(overrides: [
        liveFxServiceProvider.overrideWithValue(_service(client)),
      ]);
      addTearDown(c2.dispose);
      await c2.read(liveFxBootstrapProvider.future);

      expect(calls, 1, reason: 'taze cache varken tekrar ağa çıkıldı');
      expect(c2.read(jpyToTryProvider), closeTo(0.3021, 1e-9));
    });
  });
}
