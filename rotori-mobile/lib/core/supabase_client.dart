import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Uygulama boyunca kullanılan tek Supabase istemcisi.
/// `main.dart` içinde `Supabase.initialize(...)` bittikten sonra hazır olur.
final supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Oturum akışı — kullanıcı login/logout olduğunda tetiklenir.
/// UI bu stream'e Riverpod ile bağlanır → auth state değişince router yönlendirir.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseProvider).auth.onAuthStateChange;
});

/// O anki oturumu döndürür (senkron erişim için).
final currentSessionProvider = Provider<Session?>((ref) {
  // authStateProvider'ı izle ki oturum değiştiğinde bu da yeniden hesaplansın.
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentSession;
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(currentSessionProvider)?.user;
});
