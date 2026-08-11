import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../../data/telemetry_service.dart';

/// Ham (raw) nonce için kullanılan güvenli karakter kümesi (URL-safe).
const _nonceCharset =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';

/// Kriptografik olarak güvenli, rastgele **ham** nonce üretir.
///
/// Apple akışında bu ham nonce Supabase'e (`signInWithIdToken(nonce:)`)
/// gönderilir; Apple'a ise bunun SHA-256 özeti verilir. Test edilebilir
/// olması için saf (pure) top-level fonksiyon olarak tutulur.
String generateRawNonce([int length = 32]) {
  final random = Random.secure();
  return List.generate(
    length,
    (_) => _nonceCharset[random.nextInt(_nonceCharset.length)],
  ).join();
}

/// Verilen string'in SHA-256 özetini onaltılık (hex) olarak döndürür.
///
/// Çıktı her zaman 64 karakterdir ve aynı girdi için deterministiktir.
/// Apple `getAppleIDCredential(nonce:)` bu hash'lenmiş değeri bekler.
String sha256OfString(String input) {
  final bytes = utf8.encode(input);
  return sha256.convert(bytes).toString();
}

/// Auth işlemlerinin tek girişi. Ekranlar doğrudan Supabase'i çağırmaz;
/// böylece ileride Apple/Google native login eklenince tek nokta değişir.
class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUpWithPassword({
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  /// Aktif kullanıcının hesabını ve tüm verilerini siler.
  ///
  /// Apple App Store Guideline 5.1.1(v) gereği: hesap oluşturma varsa,
  /// uygulama içinden silme akışı da olmak zorunda. Client `admin.deleteUser`'ı
  /// service_role key olmadan çağıramadığı için Supabase'de
  /// `delete_current_user()` RPC fonksiyonu tanımlı (migration 0004);
  /// `security definer` ile aktif kullanıcının verisini + auth kaydını siler.
  ///
  /// Başarılı silme sonrası local session temizlenir — router auth ekranına
  /// yönlendirir. Hata durumunda [Exception] fırlatılır (UI SnackBar).
  Future<void> deleteAccount() async {
    final userId = _client.auth.currentUser?.id;
    try {
      await _client.rpc<void>('delete_current_user');
    } catch (e) {
      throw Exception('Hesap silinemedi. Lütfen tekrar deneyin: $e');
    }
    if (userId != null) {
      await TelemetryService.instance.clearUser(userId);
    }
    // Auth user zaten silindi; local session'ı da temizle ki router yönlendirsin.
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Kullanıcı silindiği için signOut hata verebilir — normal, yut.
    }
  }

  /// Sign in with Apple — iOS/macOS native token akışı.
  ///
  /// Akış:
  /// 1. Güvenli **ham** nonce üretilir ve SHA-256 özeti alınır.
  /// 2. Apple'a hash'lenmiş nonce ile kimlik istenir; `identityToken` alınır.
  /// 3. Supabase'e `signInWithIdToken` ile **ham** nonce + idToken gönderilir
  ///    (Supabase ham nonce'u bekler; standart replay-koruması deseni).
  ///
  /// Kullanıcı akışı iptal ederse sessizce döner; diğer hatalarda Türkçe
  /// mesajlı bir [Exception] fırlatır (UI SnackBar'da gösterir).
  Future<void> signInWithApple() async {
    final rawNonce = generateRawNonce();
    final hashedNonce = sha256OfString(rawNonce);
    try {
      final cred = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
      final idToken = cred.identityToken;
      if (idToken == null) {
        throw Exception(
            'Apple kimlik jetonu alınamadı. Lütfen tekrar deneyin.');
      }
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      // Kullanıcı vazgeçtiyse hata gösterme, sessizce çık.
      if (e.code == AuthorizationErrorCode.canceled) return;
      throw Exception('Apple ile giriş başarısız oldu: ${e.message}');
    }
  }

  /// Google ile Giriş — Supabase OAuth akışı (web view + deep link).
  ///
  /// Akış:
  /// 1. `signInWithOAuth` sistem tarayıcısını (iOS: ASWebAuthenticationSession,
  ///    Android: Chrome Custom Tabs) açar; Google login sayfası gösterilir.
  /// 2. Kullanıcı onaylayınca Google → Supabase callback URL'ine yönlenir
  ///    (`https://<ref>.supabase.co/auth/v1/callback`).
  /// 3. Supabase kendi tarafında access/refresh token üretir ve deep link ile
  ///    uygulamaya geri döner (`io.supabase.rotori://login-callback/`).
  /// 4. supabase_flutter otomatik olarak session'ı yakalar → authStateProvider
  ///    tetiklenir → router HomeScreen'e yönlendirir.
  ///
  /// Web'de deep link yerine aynı pencerede redirect olur.
  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : 'io.supabase.rotori://login-callback/',
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseProvider));
});
