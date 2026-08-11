import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../data/telemetry_service.dart';
import '../env.dart';
import '../features/auth/auth_screen.dart';
import '../features/live_currency_scanner/presentation/pages/live_currency_scanner_page.dart';
import '../features/price_tag_scanner/view/scanner_screen.dart';
import '../features/plans/add_hotel_page.dart';
import '../features/plans/create/create_plan_screen.dart';
import '../features/plans/flights/flight_details_page.dart';
import '../features/plans/plan_providers.dart';
import '../features/plans/plan_viewer_screen.dart';
import '../features/plans/plans_list_screen.dart';
import '../features/reminders/reminders_screen.dart';
import '../features/viewer/pre_departure_checklist_screen.dart';
import 'supabase_client.dart';

/// Auth route-guard kararını tek bir yerde toplar.
String? resolveAuthRedirect({
  required bool loggedIn,
  required String matchedLocation,
}) {
  final atAuth = matchedLocation == '/auth';
  if (!loggedIn && !atAuth) return '/auth';
  if (loggedIn && atAuth) return '/plans';
  return null;
}

/// Uygulama router'ı. Auth state'e göre otomatik yönlendirme yapar:
///   - Oturum yok → /auth
///   - Oturum var → /
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefreshListenable(ref);

  return GoRouter(
    initialLocation: '/',
    observers: [
      TelemetryNavigatorObserver(),
      if (Env.isSentryConfigured) SentryNavigatorObserver(),
    ],
    refreshListenable: refresh,
    redirect: (context, state) {
      // Session'ı doğrudan SDK'dan oku (cache'li currentSessionProvider değil):
      // onAuthStateChange emit etmeden önce auth.currentSession senkron güncellenir.
      // Aksi halde refresh listenable, StreamProvider cache'inden önce ateşlenip
      // eski (null) session okunur ve ilk login denemesi başarısız görünür.
      final loggedIn = ref.read(supabaseProvider).auth.currentSession != null;
      return resolveAuthRedirect(
        loggedIn: loggedIn,
        matchedLocation: state.matchedLocation,
      );
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (_, __) => '/plans',
      ),
      GoRoute(
        path: '/plans',
        name: 'plans',
        builder: (context, state) => const PlansListScreen(),
      ),
      // '/plans/:id/...' desenlerinden ÖNCE gelmeli.
      GoRoute(
        path: '/plans/new',
        name: 'create_plan',
        builder: (context, state) => const CreatePlanScreen(),
      ),
      // Eski 6 adımlı wizard kaldırıldı — düzenleme artık planın kendi
      // üzerinde yapılıyor. Kayıtlı deep-link/bookmark'lar bozulmasın diye
      // viewer'a yönlendiriyoruz.
      GoRoute(
        path: '/plans/:id/edit',
        redirect: (context, state) =>
            '/plans/${state.pathParameters['id']}/view',
      ),
      GoRoute(
        path: '/plans/:id/view',
        name: 'plan_viewer',
        builder: (context, state) =>
            PlanViewerScreen(planId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/plans/:id/flights',
        name: 'flight_details',
        builder: (context, state) =>
            FlightDetailsPage(planId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/plans/:id/hotels/new',
        name: 'add_hotel',
        builder: (context, state) =>
            AddHotelPage(planId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/plans/:id/prep',
        name: 'pre_departure',
        builder: (context, state) =>
            _PreDepartureRoute(planId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/reminders',
        name: 'reminders',
        builder: (context, state) => const RemindersScreen(),
      ),
      GoRoute(
        path: '/live-currency-scanner',
        name: 'live_currency_scanner',
        builder: (context, state) => const LiveCurrencyScannerPage(),
      ),
      GoRoute(
        path: '/price-tag-scanner',
        name: 'price_tag_scanner',
        builder: (context, state) => const ScannerScreen(),
      ),
      GoRoute(
        path: '/auth',
        name: 'auth',
        builder: (context, state) => const AuthScreen(),
      ),
    ],
  );
});

/// `/plans/:id/prep` için trip yükleyip [PreDepartureChecklistScreen]'i açar.
class _PreDepartureRoute extends ConsumerWidget {
  const _PreDepartureRoute({required this.planId});
  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(planByIdProvider(planId));
    return planAsync.when(
      data: (trip) => PreDepartureChecklistScreen(trip: trip),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

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
