import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

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

  /// TODO(Faz 2b): Sign in with Apple — iOS için native token; Supabase
  /// `signInWithIdToken(provider: OAuthProvider.apple, idToken: ..., nonce: ...)`
  /// kullanılacak. App Store için şart.
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseProvider));
});
