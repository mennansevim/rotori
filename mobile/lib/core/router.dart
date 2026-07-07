import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_screen.dart';
import '../features/planner/planner_screen.dart';
import '../features/plans/plan_viewer_screen.dart';
import '../features/plans/plans_list_screen.dart';
import '../features/reminders/reminders_screen.dart';
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
      if (loggedIn && atAuth) return '/plans';
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (_, __) => '/plans',
      ),
      GoRoute(
        path: '/plans',
        builder: (context, state) => const PlansListScreen(),
      ),
      GoRoute(
        path: '/plans/:id/edit',
        builder: (context, state) =>
            PlannerScreen(planId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/plans/:id/view',
        builder: (context, state) =>
            PlanViewerScreen(planId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/reminders',
        builder: (context, state) => const RemindersScreen(),
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
