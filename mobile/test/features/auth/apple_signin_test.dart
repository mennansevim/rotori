// Sign in with Apple — nonce yardımcıları (unit) + AuthScreen kurulum (widget).
//
// Apple akışının kendisi (getAppleIDCredential) yalnızca gerçek iOS/macOS
// cihazında çalışır ve burada test edilemez; bu yüzden saf/pure nonce
// fonksiyonlarını ve ekranın kurulabilirliğini doğruluyoruz.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/features/auth/auth_repository.dart';
import 'package:japan_trip/features/auth/auth_screen.dart';

void main() {
  group('nonce yardımcıları', () {
    test('generateRawNonce varsayılan 32 karakter üretir', () {
      expect(generateRawNonce().length, 32);
    });

    test('generateRawNonce uzunluk parametresine uyar', () {
      expect(generateRawNonce(16).length, 16);
      expect(generateRawNonce(64).length, 64);
    });

    test('generateRawNonce yalnızca izinli karakterleri içerir', () {
      final allowed = RegExp(r'^[A-Za-z0-9\-._]+$');
      for (var i = 0; i < 50; i++) {
        expect(allowed.hasMatch(generateRawNonce()), isTrue);
      }
    });

    test('generateRawNonce her çağrıda farklı değer üretir', () {
      final a = generateRawNonce();
      final b = generateRawNonce();
      expect(a, isNot(equals(b)));
    });

    test('sha256OfString 64 karakterlik hex döndürür', () {
      final hash = sha256OfString('herhangi-bir-nonce');
      expect(hash.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), isTrue);
    });

    test('sha256OfString deterministiktir (bilinen vektör)', () {
      // SHA-256("abc") — RFC/standart bilinen değer.
      expect(
        sha256OfString('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      // Aynı girdi → aynı çıktı.
      final n = generateRawNonce();
      expect(sha256OfString(n), sha256OfString(n));
    });
  });

  testWidgets('AuthScreen kurulur ve e-posta formu render olur',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AuthScreen()),
      ),
    );

    // E-posta/şifre formu her platformda görünür.
    expect(find.text('E-posta'), findsOneWidget);
    expect(find.text('Şifre'), findsOneWidget);
    expect(find.text('🇯🇵 Japan-Trip'), findsOneWidget);
    // Apple butonu platform gate'li: test host'u iOS/macOS değilse gizli.
    // Ekranın hatasız kurulması yeterli doğrulamadır.
  });
}
