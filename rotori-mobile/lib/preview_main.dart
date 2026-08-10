// PREVIEW GİRİŞ NOKTASI — Supabase/login OLMADAN, seedli demo Trip ile
// tüm ekranları (planner adımları + viewer + keşif haritası) gezmek için.
//
// Çalıştır:
//   flutter run -d chrome -t lib/preview_main.dart
//
// Üretim girişi lib/main.dart'tır; bu dosya yalnızca görsel kontrol içindir.
import 'dart:math' as math;

import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/l10n.dart';
import 'core/supabase_client.dart' show currentUserProvider;
import 'data/exchange_rate_store.dart';
import 'data/language_store.dart';
import 'domain/city_transfers.dart';
import 'domain/destination_profiles.dart';
import 'domain/fill_empty_days.dart';
import 'domain/itinerary_generator.dart';
import 'domain/place_coords.dart';
import 'domain/route_matrix.dart';
import 'domain/trip_factory.dart';
import 'domain/types.dart';
import 'features/auth/auth_screen.dart';
import 'features/planner/planner_theme.dart';
import 'features/plans/add_hotel_page.dart';
import 'features/plans/create/create_plan_screen.dart';
import 'features/plans/flights/flight_details_page.dart';
import 'features/plans/plan_providers.dart';
import 'features/plans/plan_viewer_screen.dart';
import 'features/plans/plan_optimization_controller.dart';
import 'features/plans/plans_list_screen.dart';
import 'features/price_tag_scanner/view/scanner_screen.dart';
import 'features/reminders/reminders_screen.dart';
import 'features/live_currency_scanner/presentation/pages/live_currency_scanner_page.dart';
import 'features/viewer/budget_screen.dart';
import 'features/viewer/checklist_screen.dart';
import 'features/viewer/compass_screen.dart';
import 'features/viewer/day_map_screen.dart';
import 'features/viewer/eats_screen.dart';
import 'features/viewer/gps_sim_screen.dart';
import 'features/viewer/japanese_phrases_screen.dart';
import 'features/viewer/must_know_screen.dart';
import 'features/viewer/pre_departure_checklist_screen.dart';
import 'features/viewer/weather_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final demo = _buildDemoTrip();
  _hydratePreviewCoordinates(demo);

  runApp(
    DevicePreview(
      // Release'de otomatik devre dışı — bu dosya zaten sadece dev girişi.
      enabled: !kReleaseMode,
      // Varsayılan cihaz: iPhone 15 Pro (App Store hedef cihazı).
      defaultDevice: Devices.ios.iPhone15Pro,
      builder: (context) => ProviderScope(
        overrides: [
          // Supabase auth yok → repo null → save() no-op, geofence userId 'anon'.
          currentUserProvider.overrideWithValue(null),
          // Realtime yerine trip yayınla. Öncelik: oluşturma akışının ürettiği
          // taslak → 'new' boş trip → seedli demo.
          planByIdProvider.overrideWith((ref, id) {
            final draft = ref.watch(draftTripProvider);
            if (draft != null && draft.id == id) {
              return Stream<Trip>.value(draft);
            }
            if (id == 'new') return Stream<Trip>.value(_buildEmptyTrip());
            return Stream<Trip>.value(demo);
          }),
          // Gerçek "Planlarım" ekranını dolu göstermek için (Supabase pull'u no-op).
          localPlansProvider.overrideWithValue([demo]),
          plansPullProvider.overrideWith((ref) async => <Trip>[]),
          // Yalnızca tasarım/QA önizlemesi. Üretimde koordinattan süre
          // üretilmez; gerçek backend gateway'i veya güvenilir cache gerekir.
          routeMatrixRepositoryProvider.overrideWithValue(
            const _PreviewRouteMatrixRepository(),
          ),
        ],
        child: const _PreviewApp(),
      ),
    ),
  );
}

void _hydratePreviewCoordinates(Trip trip) {
  final destinations = [...trip.preferences.destinations]
    ..sort((a, b) => a.order.compareTo(b.order));
  for (final day in trip.days) {
    final destination = getDestinationForDate(destinations, day.date);
    final cityData = cityDataForKey(destination?.city);
    final fallbackLat = destination?.lat ??
        (cityData?.places.isNotEmpty == true
            ? cityData!.places.first.lat
            : null);
    final fallbackLng = destination?.lng ??
        (cityData?.places.isNotEmpty == true
            ? cityData!.places.first.lng
            : null);
    if (fallbackLat == null || fallbackLng == null) continue;
    final stops = resolveDayStops(
      day,
      cityKey: destination?.city,
      fallbackLat: fallbackLat,
      fallbackLng: fallbackLng,
    );
    for (final stop in stops) {
      stop.item
        ..lat = stop.lat
        ..lng = stop.lng;
    }
  }
}

class _PreviewRouteMatrixRepository implements RouteMatrixRepository {
  const _PreviewRouteMatrixRepository();

  @override
  Future<RouteMatrix> getRouteMatrix({
    required List<TripLocation> locations,
    required DateTime day,
    required RoutePreferences preferences,
  }) async {
    final entries = <RouteMatrixEntry>[];
    for (final from in locations) {
      for (final to in locations) {
        if (from.id == to.id) continue;
        final km = _previewDistanceKm(from, to);
        final walking = math.max(3, (km / 4.8 * 60).round());
        final transit = math.max(8, (km / 24 * 60).round() + 10);
        final taxi = math.max(6, (km / 30 * 60).round() + 5);
        entries.add(RouteMatrixEntry(
          fromLocationId: from.id,
          toLocationId: to.id,
          options: [
            TransportOption(
              mode: TransportMode.walking,
              doorToDoorMinutes: walking,
              walkingMinutes: walking,
              waitingMinutes: 0,
              transferCount: 0,
              estimatedCostYen: 0,
              reliabilityScore: .98,
              isEstimated: true,
            ),
            TransportOption(
              mode: TransportMode.train,
              doorToDoorMinutes: transit,
              walkingMinutes: math.min(10, walking),
              waitingMinutes: 5,
              transferCount: km > 8 ? 1 : 0,
              estimatedCostYen: math.max(150, (km * 45).round()),
              reliabilityScore: .9,
              isEstimated: true,
            ),
            TransportOption(
              mode: TransportMode.taxi,
              doorToDoorMinutes: taxi,
              walkingMinutes: 1,
              waitingMinutes: 4,
              transferCount: 0,
              estimatedCostYen: 500 + (km * 320).round(),
              reliabilityScore: .72,
              isEstimated: true,
            ),
          ],
        ));
      }
    }
    return RouteMatrix(entries: entries, version: 'preview-estimated-v1');
  }
}

double _previewDistanceKm(TripLocation a, TripLocation b) {
  const earthRadiusKm = 6371.0;
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dLat = lat2 - lat1;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

/// Sıfırdan planlama akışı için boş trip — planner welcome adımı ile başlar.
Trip _buildEmptyTrip() {
  final t = createEmptyTrip();
  t.title = 'Yeni seyahat';
  t.subtitle = '';
  return t;
}

/// Tokyo + Kyoto rotalı, dolu günlü, otelli demo trip.
Trip _buildDemoTrip() {
  var trip = createEmptyTrip();
  trip.title = 'Japonya 2026 (Önizleme)';
  trip.subtitle = 'Demo veri — birebir React portu kontrolü';

  final start = trip.preferences.travelDates.start;
  final end = trip.preferences.travelDates.end;

  final destinations = <TripDestination>[
    TripDestination(
      id: newDestinationId(),
      countryCode: 'JP',
      countryName: 'Japonya',
      city: 'Tokyo',
      airport: 'HND',
      lat: 35.6762,
      lng: 139.6503,
      arrivalDate: start,
      departureDate: _shiftYmd(start, 3),
      order: 0,
    ),
    TripDestination(
      id: newDestinationId(),
      countryCode: 'JP',
      countryName: 'Japonya',
      city: 'Kyoto',
      airport: 'ITM',
      lat: 35.0116,
      lng: 135.7681,
      arrivalDate: _shiftYmd(start, 3),
      departureDate: end,
      order: 1,
    ),
  ];

  trip = syncTripFromDestinations(
    trip,
    originCity: 'İstanbul',
    originAirport: 'IST',
    originLat: 41.2753,
    originLng: 28.7519,
    destinations: destinations,
    destinationFood: destinations.map(defaultFoodPrefsForDestination).toList(),
    travelStart: start,
    travelEnd: end,
  );

  // Günleri gerçek portlanmış üreticiyle doldur.
  var days = generateItineraryFromTrip(trip);
  days = fillEmptyDays(days, destinations);
  // Şehir geçişlerini (Shinkansen) ekle — planner._generate ile aynı pipeline.
  days = applyCityTransitions(days, destinations);
  trip.days = days;

  trip.hotels = [
    HotelStay(
      id: 'demo-hotel-1',
      city: 'Tokyo',
      name: 'Shinjuku Granbell Hotel',
      checkIn: start,
      checkOut: _shiftYmd(start, 3),
      address: '2-14-5 Kabukicho, Shinjuku, Tokyo',
      addressLocal: '東京都新宿区歌舞伎町2-14-5',
      phone: '+81 3-5155-2666',
    ),
  ];

  // Keşfet adımının da dolu görünmesi için örnek ilgi alanları.
  trip.preferences.interests = [
    InterestTag.temples,
    InterestTag.photography,
    InterestTag.tech,
  ];

  return ensureTripPreferences(trip);
}

String _shiftYmd(String ymd, int days) {
  final d = DateTime.parse(ymd).add(Duration(days: days));
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

class _PreviewApp extends ConsumerWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(appLangProvider);
    // Canlı döviz kuru — açılışta bir kez, sonuç beklenmez.
    ref.watch(liveFxBootstrapProvider);
    final router = GoRouter(
      initialLocation: '/plans',
      routes: [
        GoRoute(path: '/', redirect: (_, __) => '/plans'),
        GoRoute(path: '/plans', builder: (_, __) => const _PreviewHome()),
        // '/plans/:id/...' desenlerinden ÖNCE.
        GoRoute(
            path: '/plans/new', builder: (_, __) => const CreatePlanScreen()),
        // Gerçek uygulama ekranları (önizleme): giriş + "Planlarım".
        GoRoute(path: '/auth', builder: (_, __) => const AuthScreen()),
        GoRoute(
            path: '/planslist', builder: (_, __) => const PlansListScreen()),
        // Wizard kaldırıldı — eski deep-link'ler viewer'a düşer.
        GoRoute(
          path: '/plans/:id/edit',
          redirect: (_, s) => '/plans/${s.pathParameters['id']}/view',
        ),
        GoRoute(
          path: '/plans/:id/view',
          builder: (_, s) => PlanViewerScreen(planId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/plans/:id/flights',
          builder: (_, s) => FlightDetailsPage(planId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/plans/:id/hotels/new',
          builder: (_, s) => AddHotelPage(planId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/plans/:id/gpssim',
          builder: (_, s) => _GpsSimRoute(planId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/plans/:id/map/:day',
          builder: (_, s) => _DayMapRoute(
            planId: s.pathParameters['id']!,
            dayNumber: int.tryParse(s.pathParameters['day'] ?? '') ?? 1,
          ),
        ),
        GoRoute(
          path: '/plans/:id/compass',
          builder: (_, s) => _CompassRoute(planId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/plans/:id/eats',
          builder: (_, s) => _EatsRoute(planId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/plans/:id/budget',
          builder: (_, s) => _BudgetRoute(planId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/plans/:id/checklist',
          builder: (_, s) => _ChecklistRoute(planId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/plans/:id/prep',
          builder: (_, s) => _PrepRoute(planId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/plans/:id/weather',
          builder: (_, s) => _WeatherRoute(planId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/plans/:id/phrases',
          builder: (_, s) => _PhrasesRoute(planId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/plans/:id/mustknow',
          builder: (_, s) => _MustKnowRoute(planId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/reminders',
          builder: (_, __) => const RemindersScreen(),
        ),
        GoRoute(
          path: '/live-currency-scanner',
          builder: (_, __) => const LiveCurrencyScannerPage(),
        ),
        GoRoute(
          path: '/price-tag-scanner',
          builder: (_, __) => const ScannerScreen(),
        ),
      ],
    );
    return LanguageScope(
      lang: lang,
      child: MaterialApp.router(
        title: L10n.resolve('home.appTitle', lang),
        theme: PT.theme(),
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        // DevicePreview entegrasyonu: locale + MediaQuery cihaz frame'inden
        // gelsin. Kullanıcı device_preview toolbar'ından iPhone/iPad
        // frame + karanlık mod + dil değiştirebilir.
        locale: DevicePreview.locale(context) ?? Locale(lang.code),
        builder: DevicePreview.appBuilder,
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
  }
}

/// Preview: planByIdProvider'dan trip'i çözüp GPS simülatörünü açar.
class _GpsSimRoute extends ConsumerWidget {
  const _GpsSimRoute({required this.planId});
  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(planByIdProvider(planId));
    return planAsync.when(
      data: (trip) => GpsSimScreen(trip: trip),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Text(
            LanguageScope.of(context).p('home.planLoadFailed', {'err': '$e'}),
          ),
        ),
      ),
    );
  }
}

/// Preview: planByIdProvider'dan trip'i çözüp bir günün rota haritasını açar.
class _DayMapRoute extends ConsumerWidget {
  const _DayMapRoute({required this.planId, required this.dayNumber});
  final String planId;
  final int dayNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(planByIdProvider(planId));
    return planAsync.when(
      data: (trip) => DayMapScreen(
        trip: trip,
        dayNumber: dayNumber,
        onBack: () => context.go('/plans/$planId/view'),
      ),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Text(
            LanguageScope.of(context).p('home.planLoadFailed', {'err': '$e'}),
          ),
        ),
      ),
    );
  }
}

/// Preview: planByIdProvider'dan trip'i çözüp Pusula ekranını açar.
class _CompassRoute extends ConsumerWidget {
  const _CompassRoute({required this.planId});
  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(planByIdProvider(planId));
    return planAsync.when(
      data: (trip) => CompassScreen(trip: trip),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Text(
            LanguageScope.of(context).p('home.planLoadFailed', {'err': '$e'}),
          ),
        ),
      ),
    );
  }
}

/// Preview: planByIdProvider'dan trip'i çözüp Bütçe ekranını açar.
/// Preview: planByIdProvider'dan trip'i çözüp Rotori Eats'i açar.
/// Ekran normalde plan viewer drawer'ından açılıyor; doğrudan URL rotası
/// olmadan önizlemede tek başına görüntülenemiyordu.
class _EatsRoute extends ConsumerWidget {
  const _EatsRoute({required this.planId});
  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(planByIdProvider(planId));
    return planAsync.when(
      data: (trip) => EatsScreen(trip: trip),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Text(
            LanguageScope.of(context).p('home.planLoadFailed', {'err': '$e'}),
          ),
        ),
      ),
    );
  }
}

class _BudgetRoute extends ConsumerWidget {
  const _BudgetRoute({required this.planId});
  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(planByIdProvider(planId));
    return planAsync.when(
      data: (trip) => BudgetScreen(trip: trip),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Text(
            LanguageScope.of(context).p('home.planLoadFailed', {'err': '$e'}),
          ),
        ),
      ),
    );
  }
}

/// Preview: planByIdProvider'dan trip'i çözüp Valiz & Hazırlık ekranını açar.
/// Preview: planByIdProvider'dan trip'i çözüp Japonca frazlar sayfasını açar.
class _PhrasesRoute extends ConsumerWidget {
  const _PhrasesRoute({required this.planId});
  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(planByIdProvider(planId));
    return planAsync.when(
      data: (trip) => JapanesePhrasesScreen(trip: trip),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Text(
            LanguageScope.of(context).p('home.planLoadFailed', {'err': '$e'}),
          ),
        ),
      ),
    );
  }
}

/// Preview: planByIdProvider'dan trip'i çözüp "Mutlaka bilmeniz gerekenler"i açar.
class _MustKnowRoute extends ConsumerWidget {
  const _MustKnowRoute({required this.planId});
  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(planByIdProvider(planId));
    return planAsync.when(
      data: (trip) => MustKnowScreen(trip: trip),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Text(
            LanguageScope.of(context).p('home.planLoadFailed', {'err': '$e'}),
          ),
        ),
      ),
    );
  }
}

class _ChecklistRoute extends ConsumerWidget {
  const _ChecklistRoute({required this.planId});
  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(planByIdProvider(planId));
    return planAsync.when(
      data: (trip) => ChecklistScreen(trip: trip),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Text(
            LanguageScope.of(context).p('home.planLoadFailed', {'err': '$e'}),
          ),
        ),
      ),
    );
  }
}

/// Preview: planByIdProvider'dan trip'i çözüp Yolculuk Öncesi Hazırlık
/// ekranını açar (repository backend'siz — SharedPreferences fallback).
class _PrepRoute extends ConsumerWidget {
  const _PrepRoute({required this.planId});
  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(planByIdProvider(planId));
    return planAsync.when(
      data: (trip) => PreDepartureChecklistScreen(trip: trip),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Text(
            LanguageScope.of(context).p('home.planLoadFailed', {'err': '$e'}),
          ),
        ),
      ),
    );
  }
}

/// Preview: planByIdProvider'dan trip'i çözüp Hava Durumu ekranını açar.
class _WeatherRoute extends ConsumerWidget {
  const _WeatherRoute({required this.planId});
  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(planByIdProvider(planId));
    return planAsync.when(
      data: (trip) => WeatherScreen(trip: trip),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Text(
            LanguageScope.of(context).p('home.planLoadFailed', {'err': '$e'}),
          ),
        ),
      ),
    );
  }
}

class _PreviewHome extends ConsumerWidget {
  const _PreviewHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const id = 'demo';
    final s = LanguageScope.of(context);
    final lang = ref.watch(appLangProvider);
    return Scaffold(
      backgroundColor: PT.bg,
      appBar: AppBar(
        title: Text(s.s('home.appBar')),
        backgroundColor: PT.bg,
        foregroundColor: PT.text,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _LangToggle(
              active: lang,
              onSelect: (l) => ref.read(appLangProvider.notifier).set(l),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                s.s('home.demoLoaded'),
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700, color: PT.text),
              ),
              const SizedBox(height: 6),
              Text(
                s.s('home.demoSub'),
                style: const TextStyle(color: PT.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 28),
              _NavCard(
                emoji: '✨',
                title: s.s('home.card.new.title'),
                subtitle: s.s('home.card.new.sub'),
                onTap: () => context.push('/plans/new'),
              ),
              const SizedBox(height: 12),
              _NavCard(
                emoji: '✈️',
                title: s.s('flights.title'),
                subtitle: s.s('viewer.addFlight.body'),
                onTap: () => context.push('/plans/$id/flights'),
              ),
              const SizedBox(height: 12),
              _NavCard(
                emoji: '📖',
                title: s.s('home.card.viewer.title'),
                subtitle: s.s('home.card.viewer.sub'),
                onTap: () => context.go('/plans/$id/view'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Küçük TR/EN dil seçici — demo home için (planner TopNav'daki onLang
/// deseninin sadeleştirilmiş, segmentli hali). Etiketler dil kodudur (çeviri
/// gerektirmez); aktif dili `appLangProvider.notifier.set` ile değiştirir.
class _LangToggle extends StatelessWidget {
  const _LangToggle({required this.active, required this.onSelect});
  final AppLang active;
  final ValueChanged<AppLang> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PT.bgSubtle,
        borderRadius: BorderRadius.circular(PT.radiusPill),
        border: Border.all(color: PT.border),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final l in AppLang.values)
            _LangChip(
              label: l.code.toUpperCase(),
              selected: l == active,
              onTap: () => onSelect(l),
            ),
        ],
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(PT.radiusPill),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? PT.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(PT.radiusPill),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : PT.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PCard(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: PT.text)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 13, color: PT.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: PT.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
