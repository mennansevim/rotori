import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_screen.dart';
import '../features/home/home_screen.dart';
import 'supabase_client.dart';

/// Uygulama router'ı. Auth state'e göre otomatik yönlendirme yapar:
///   - Oturum yok → /auth
///   - Oturum var → /
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefreshListenable(ref);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = ref.read(currentSessionProvider) != null;
      final atAuth = state.matchedLocation == '/auth';
      if (!loggedIn && !atAuth) return '/auth';
      if (loggedIn && atAuth) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthScreen(),
      ),
    ],
  );
});

/// Auth stream'i router'ın refresh mekanizmasına köprüler — login/logout olunca
/// router redirect'i yeniden hesaplar.
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(this._ref) {
    _sub = _ref
        .read(supabaseProvider)
        .auth
        .onAuthStateChange
        .listen((_) => notifyListeners());
  }

  final Ref _ref;
  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
