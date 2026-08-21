import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository.dart';

/// Preview hedefinde Supabase başlatılmadığı için auth ekranını çalışır tutan
/// yerel repository. Başarılı sonucu route callback'i taşır; gerçek oturum
/// üretmez ve hiçbir kullanıcı verisini ağ üzerinden göndermez.
class PreviewAuthRepository extends AuthRepository {
  PreviewAuthRepository()
      : super(
          SupabaseClient(
            'https://preview.invalid',
            'preview-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async => AuthResponse();

  @override
  Future<AuthResponse> signUpWithPassword({
    required String email,
    required String password,
  }) async => AuthResponse();

  @override
  Future<void> signInWithApple() async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}
