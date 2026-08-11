// Plan viewer widget testi — temalı görüntüleyicinin temel davranışları:
// başlık render, aktif gün genişletilmiş + geçmiş gün soluk, tema seçici açılır.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/data/plans_repository.dart';
import 'package:rotori/core/supabase_client.dart';
import 'package:rotori/domain/route_matrix.dart';
import 'package:rotori/domain/route_execution.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rotori/core/l10n.dart';
import 'package:rotori/features/plans/premium_provider.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/plans/plan_providers.dart';
import 'package:rotori/features/plans/plan_optimization_controller.dart';
import 'package:rotori/features/plans/plan_viewer_screen.dart';

/// Bugüne göre birkaç geçmiş + bir aktif gün içeren örnek Trip.
Trip _sampleTrip() {
  final now = DateTime.now();
  String d(int offsetDays) {
    final t = now.add(Duration(days: offsetDays));
    return '${t.year.toString().padLeft(4, '0')}-'
        '${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
  }

  DayPlan mk(int n, int offset, String theme, String itemTitle) => DayPlan(
        dayNumber: n,
        date: d(offset),
        theme: theme,
        tags: const ['test'],
        items: [
          TimelineItem(id: 'it$n', title: itemTitle, time: '10:00'),
        ],
      );

  return Trip(
    id: 'trip-1',
    slug: 'test-trip',
    title: 'Japonya Test Gezisi',
    subtitle: 'Widget testi',
    timezone: 'Asia/Tokyo',
    tripStart: d(-2),
    tripEnd: d(2),
    flights: TripFlights(),
    preferences: TripPreferences(
      travelDates: TravelDates(start: d(-2), end: d(2)),
      pace: Pace.moderate,
    ),
    days: [
      mk(1, -2, 'Geçmiş Gün Teması', 'Gecmis Aktivite'),
      mk(2, 0, 'Aktif Gün Teması', 'Aktif Aktivite'),
      mk(3, 2, 'Gelecek Gün Teması', 'Gelecek Aktivite'),
    ],
  );
}

Trip _routeUiTrip() {
  final now = DateTime.now();
  final date = '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
  return Trip(
    id: 'route-ui-trip',
    slug: 'route-ui-trip',
    title: 'Tokyo Rota Testi',
    timezone: 'Asia/Tokyo',
    tripStart: date,
    tripEnd: date,
    flights: TripFlights(),
    preferences: TripPreferences(
      travelDates: TravelDates(start: date, end: date),
      pace: Pace.moderate,
      destinations: [
        TripDestination(
          id: 'tokyo',
          countryCode: 'JP',
          countryName: 'Japonya',
          city: 'Tokyo',
          arrivalDate: date,
          departureDate: date,
          order: 0,
          lat: 35.6812,
          lng: 139.7671,
        ),
      ],
    ),
    days: [
      DayPlan(
        dayNumber: 1,
        date: date,
        theme: 'Tokyo klasiği',
        items: [
          TimelineItem(
            id: 'b',
            title: 'Tokyo Skytree',
            lat: 35.7101,
            lng: 139.8107,
            durationMin: 60,
          ),
          TimelineItem(
            id: 'a',
            title: 'Senso-ji',
            lat: 35.7148,
            lng: 139.7967,
            durationMin: 60,
          ),
        ],
      ),
    ],
  );
}

Trip _cityTransitionTrip() {
  final now = DateTime.now();
  String date(int offset) {
    final value = now.add(Duration(days: offset));
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  return Trip(
    id: 'city-transition-trip',
    slug: 'city-transition-trip',
    title: 'Tokyo Kyoto',
    timezone: 'Asia/Tokyo',
    tripStart: date(0),
    tripEnd: date(1),
    flights: TripFlights(),
    preferences: TripPreferences(
      travelDates: TravelDates(start: date(0), end: date(1)),
      pace: Pace.moderate,
      destinations: [
        TripDestination(
          id: 'tokyo',
          countryCode: 'JP',
          countryName: 'Japonya',
          city: 'Tokyo',
          arrivalDate: date(0),
          departureDate: date(0),
          order: 0,
        ),
        TripDestination(
          id: 'kyoto',
          countryCode: 'JP',
          countryName: 'Japonya',
          city: 'Kyoto',
          arrivalDate: date(1),
          departureDate: date(1),
          order: 1,
        ),
      ],
    ),
    days: [
      DayPlan(
        dayNumber: 1,
        date: date(0),
        theme: 'Tokyo',
        items: [
          TimelineItem(
            id: 'tokyo-stop',
            title: 'Tokyo İstasyonu',
            time: '09:00',
          ),
        ],
      ),
      DayPlan(
        dayNumber: 2,
        date: date(1),
        theme: 'Kyoto',
        items: [
          TimelineItem(
            id: 'kyoto-stop',
            title: 'Kyoto İstasyonu',
            time: '10:00',
          ),
        ],
      ),
    ],
  );
}

RouteMatrix _routeUiMatrix({bool estimated = false}) {
  return RouteMatrix(
    version: estimated ? 'estimated-v1' : 'provider-v1',
    entries: [
      _routeUiEntry('day-1-base', 'a', 12, estimated: estimated),
      _routeUiEntry('day-1-base', 'b', 32, estimated: estimated),
      _routeUiEntry('a', 'b', 9, estimated: estimated),
      _routeUiEntry('b', 'a', 28, estimated: estimated),
      _routeUiEntry('a', 'day-1-base', 18, estimated: estimated),
      _routeUiEntry('b', 'day-1-base', 15, estimated: estimated),
    ],
  );
}

Trip _savedRouteTrip() {
  final trip = _routeUiTrip();
  final day = DateTime.parse(trip.days.single.date);
  trip.days.single.routeExecutionSnapshot = RouteExecutionSnapshot(
    planId: trip.id,
    dayNumber: 1,
    planVersion: 1,
    activityHash: 'saved-hash',
    matrixVersion: 'provider-v1',
    generatedAt: DateTime.utc(2026, 8, 10),
    profile: RouteOptimizationProfile.balanced,
    providerIds: const ['route-provider'],
    legs: [
      RouteExecutionLeg(
        kind: RouteExecutionLegKind.departure,
        fromLocationId: 'day-1-base',
        fromName: 'Tokyo',
        toLocationId: 'b',
        toName: 'Tokyo Skytree',
        mode: TransportMode.metro,
        departureTime: DateTime(day.year, day.month, day.day, 8, 30),
        arrivalTime: DateTime(day.year, day.month, day.day, 8, 48),
        travelDurationMinutes: 18,
        rideMinutes: 11,
        accessMinutes: 4,
        walkingDurationMinutes: 4,
        waitingDurationMinutes: 3,
        transitWaitMinutes: 3,
        scheduleIdleMinutes: 0,
        transferCount: 0,
        costPerPersonYen: 180,
        partyTotalCostYen: 180,
        vehicleCount: 0,
        fareBasis: FareBasis.perPerson,
        reliabilityScore: .96,
        dataQuality: RouteExecutionDataQuality.reliable,
        complexityPenalty: 0,
        lineId: 'Ginza Line',
        directionId: 'Asakusa',
        providerId: 'route-provider',
      ),
    ],
  );
  return trip;
}

RouteMatrixEntry _routeUiEntry(
  String from,
  String to,
  int minutes, {
  required bool estimated,
}) {
  return RouteMatrixEntry(
    fromLocationId: from,
    toLocationId: to,
    options: [
      TransportOption(
        mode: TransportMode.metro,
        doorToDoorMinutes: minutes,
        walkingMinutes: 3,
        waitingMinutes: 2,
        transferCount: 0,
        estimatedCostYen: 180,
        reliabilityScore: estimated ? .5 : .96,
        isEstimated: estimated,
        lineId: 'Ginza Line',
        directionId: 'Asakusa',
        providerId: estimated ? 'coordinate-fallback' : 'route-provider',
      ),
    ],
  );
}

String tr(String key) => L10n.resolve(key, AppLang.tr);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget harness(
    Trip trip, {
    bool accessibleNavigation = false,
    RouteMatrixRepository? routeRepository,
  }) {
    return ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWith(
          (ref) async => SharedPreferences.getInstance(),
        ),
        currentUserProvider.overrideWithValue(null),
        planByIdProvider(trip.id).overrideWith((ref) => Stream.value(trip)),
        if (routeRepository != null)
          routeMatrixRepositoryProvider.overrideWithValue(routeRepository),
      ],
      child: MaterialApp(
        // Sonsuz sakura/pulse animasyonlarını testte kapat (deterministik).
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              accessibleNavigation: accessibleNavigation,
            ),
            child: PlanViewerScreen(planId: trip.id),
          ),
        ),
      ),
    );
  }

  testWidgets('başlık ve aktif gün teması render edilir', (tester) async {
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Viewer minimalize edildi — başlık artık body'de değil, drawer'ın
    // "Rotori" markası. Ana view sadece top bar + günler. Aktif gün açık
    // olmalı; aktivitesi görünür alana kaydırılıp doğrulanır.
    await tester.scrollUntilVisible(
      find.text('Aktif Aktivite'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Aktif Aktivite'), findsOneWidget);
    expect(find.text('Aktif Gün Teması'), findsWidgets);
  });

  testWidgets('geçmiş gün okunabilir tam opaklıkta render edilir',
      (tester) async {
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final opacities = tester
        .widgetList<Opacity>(
          find.ancestor(
            of: find.text('Geçmiş Gün Teması'),
            matching: find.byType(Opacity),
          ),
        )
        .map((w) => w.opacity)
        .toList();
    expect(opacities.contains(0.6), isFalse,
        reason: 'geçmiş gün içeriği plan sonrasında da net okunmalı');
  });

  testWidgets('aktif gün genişletilmiş, gelecek gün kapalı', (tester) async {
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Gelecek gün kapalı olduğu için aktivitesi başta görünmez.
    expect(find.text('Gelecek Aktivite'), findsNothing);
  });

  testWidgets('gelecek tarihli aktif günün erken saatleri geçmiş görünmez',
      (tester) async {
    final trip = _sampleTrip();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final date = '${tomorrow.year.toString().padLeft(4, '0')}-'
        '${tomorrow.month.toString().padLeft(2, '0')}-'
        '${tomorrow.day.toString().padLeft(2, '0')}';
    trip
      ..tripStart = date
      ..tripEnd = date
      ..days = [
        DayPlan(
          dayNumber: 1,
          date: date,
          theme: 'Gelecek rota',
          items: [
            TimelineItem(
              id: 'future-early',
              title: 'Gelecek Erken Aktivite',
              time: '00:01',
            ),
            TimelineItem(
              id: 'future-late',
              title: 'Gelecek İkinci Aktivite',
              time: '08:00',
            ),
          ],
        ),
      ];

    await tester.pumpWidget(harness(trip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final dimmedAncestors = tester
        .widgetList<Opacity>(
          find.ancestor(
            of: find.text('Gelecek Erken Aktivite'),
            matching: find.byType(Opacity),
          ),
        )
        .where((widget) => widget.opacity == .6);
    expect(dimmedAncestors, isEmpty);
    expect(find.text('Sıradaki'), findsOneWidget);
  });

  // Rota optimizasyonu artık PREMIUM arkasında: gün kartındaki buton
  // doğrudan optimizasyonu çalıştırmıyor, paywall sheet'ini açıyor.
  // Optimizasyon motorunun kendisi plan_optimization_controller_test.dart
  // tarafından kapsanıyor.
  // Rota optimizasyonu premium arkasında. ÜCRETSİZ kullanıcıda paywall,
  // PREMIUM kullanıcıda gerçek optimizasyon açılmalı. Eskiden buton premium
  // bayrağını hiç okumuyordu: kullanıcı premium'u açsa bile paywall geliyordu.
  testWidgets('ücretsiz kullanıcıda optimize butonu paywall açar',
      (tester) async {
    SharedPreferences.setMockInitialValues({kPremiumPrefsKey: false});
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final optimize = find.byKey(const ValueKey('optimize-route-2'));
    expect(optimize, findsOneWidget);
    expect(find.text('Premium'), findsWidgets);

    await tester.ensureVisible(optimize);
    await tester.tap(optimize);
    await tester.pumpAndSettle();

    expect(find.text(tr('routeOptimization.premium.title')), findsOneWidget);
  });

  testWidgets('premium açıkken paywall GELMEZ, rozet kalkar', (tester) async {
    SharedPreferences.setMockInitialValues({kPremiumPrefsKey: true});
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Provider prefs'i asenkron okuyor — yerleşmesini bekle.
    await tester.pump(const Duration(milliseconds: 200));

    final optimize = find.byKey(const ValueKey('optimize-route-2'));
    expect(optimize, findsOneWidget);
    expect(find.text('Premium'), findsNothing,
        reason: 'premium kullanıcıya kilit rozeti gösterilmemeli');

    await tester.ensureVisible(optimize);
    await tester.tap(optimize);
    await tester.pumpAndSettle();

    expect(find.text(tr('routeOptimization.premium.title')), findsNothing,
        reason: 'premium açıkken paywall açılmamalı');
  });

  testWidgets('optimizasyon ön izlemesi ulaşım türü, hat ve yönü gösterir',
      (tester) async {
    SharedPreferences.setMockInitialValues({kPremiumPrefsKey: true});
    await tester.pumpWidget(
      harness(
        _routeUiTrip(),
        routeRepository: FakeRouteMatrixRepository(_routeUiMatrix()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final optimize = find.byKey(const ValueKey('optimize-route-1'));
    await tester.scrollUntilVisible(
      optimize,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(optimize);
    await tester.pumpAndSettle();

    expect(find.text(tr('routeOptimization.legs.title')), findsOneWidget);
    expect(find.text('Metro'), findsWidgets);
    expect(find.textContaining('Hat: Ginza Line'), findsWidgets);
    expect(find.textContaining('Yön: Asakusa'), findsWidgets);
    expect(find.byKey(const ValueKey('route-execution-leg-0')), findsOneWidget);
  });

  testWidgets('tahmini rota kesin hat/yön ve görünür tahmin rozeti göstermez',
      (tester) async {
    SharedPreferences.setMockInitialValues({kPremiumPrefsKey: true});
    await tester.pumpWidget(
      harness(
        _routeUiTrip(),
        routeRepository:
            FakeRouteMatrixRepository(_routeUiMatrix(estimated: true)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final optimize = find.byKey(const ValueKey('optimize-route-1'));
    await tester.scrollUntilVisible(
      optimize,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(optimize);
    await tester.pumpAndSettle();

    expect(find.text(tr('routeOptimization.legs.estimated')), findsNothing);
    expect(find.textContaining('Hat: Ginza Line'), findsNothing);
    expect(find.textContaining('Yön: Asakusa'), findsNothing);
    expect(find.text(tr('routeOptimization.legs.estimatedHelp')), findsNothing);
  });

  testWidgets(
      'optimizasyon öncesinde tüm geçişler kompakt tahmin olarak görünür',
      (tester) async {
    await tester.pumpWidget(harness(_routeUiTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final departure = find.byKey(
      const ValueKey('saved-route-leg-1-day-1-base-b'),
    );
    final betweenStops = find.byKey(
      const ValueKey('saved-route-leg-1-b-a'),
    );
    await tester.scrollUntilVisible(
      departure,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(departure, findsOneWidget);
    expect(betweenStops, findsOneWidget);
    expect(tester.getSize(departure).height, lessThan(44));
    expect(
      find.descendant(
        of: departure,
        matching: find.text(tr('routeOptimization.legs.estimated')),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'onaylanmış rota snapshotı plan yeniden açılınca günlük akışta görünür',
      (tester) async {
    await tester.pumpWidget(harness(_savedRouteTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final savedLeg = find.byKey(
      const ValueKey('saved-route-leg-1-day-1-base-b'),
    );
    await tester.scrollUntilVisible(
      savedLeg,
      180,
      scrollable: find.byType(Scrollable).first,
    );

    expect(savedLeg, findsOneWidget);
    expect(find.text('Tokyo  →  Tokyo Skytree'), findsOneWidget);
    expect(find.text('Metro · 18 dk'), findsOneWidget);
    expect(tester.getSize(savedLeg).height, lessThan(44));
    expect(find.text(tr('routeOptimization.legs.departure')), findsNothing);
    expect(find.textContaining('Hat: Ginza Line'), findsNothing);
  });

  testWidgets(
      'şehir geçiş modu picker üzerinden değişir ve bilet aksiyonu sunar',
      (tester) async {
    await tester.pumpWidget(harness(_cityTransitionTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final transition = find.text('Tokyo → Kyoto');
    await tester.scrollUntilVisible(
      transition,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(transition);
    await tester.pumpAndSettle();

    expect(find.text('Tokyo → Kyoto ulaşımı'), findsOneWidget);
    expect(find.byKey(const ValueKey('city-transition-ticket-action')),
        findsOneWidget);
    await tester.tap(find.text('Otobüs'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('city-transition-mode-bus-true')),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('city-transition-Tokyo-Kyoto-bus')),
      findsOneWidget,
    );
  });

  testWidgets('şehir geçişi bilet editörü ESC ile güvenli kapanır',
      (tester) async {
    await tester.pumpWidget(harness(_cityTransitionTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final transition = find.text('Tokyo → Kyoto');
    await tester.scrollUntilVisible(
      transition,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(transition);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('city-transition-ticket-action')),
    );
    await tester.pumpAndSettle();

    expect(find.text(tr('viewer.ticketEditor.addTitle')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(tr('viewer.ticketEditor.addTitle')), findsNothing);
    expect(find.text('Tokyo → Kyoto ulaşımı'), findsOneWidget);
  });

  testWidgets('boş bilet sekmesi açıklama ve birincil ekleme aksiyonu gösterir',
      (tester) async {
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Biletler').last);
    await tester.pumpAndSettle();

    expect(find.text(tr('viewer.quick.noTickets')), findsOneWidget);
    expect(find.text(tr('viewer.quick.noTicketsHelp')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-first-ticket')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-first-ticket')));
    await tester.pumpAndSettle();
    expect(find.text(tr('viewer.ticketEditor.addTitle')), findsOneWidget);
  });

  testWidgets('Keşfet alt menü butonu keşif haritasını açar', (tester) async {
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text(tr('viewer.quick.explore')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(tr('reward.title')), findsOneWidget);
  });

  testWidgets('tema seçici açılır ve 3 tema listelenir', (tester) async {
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Aksiyon şeridi drawer'a taşındı — önce hamburger'a dokunup drawer'ı
    // aç, sonra palette butonuna tıkla.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Japon Gecesi'), findsOneWidget);
    expect(find.text('Apple Aydınlık'), findsOneWidget);
    expect(find.text('Sakura Yumuşak'), findsOneWidget);
  });

  testWidgets('hamburger menüsü dört net bölüm ve kaydırma sunar',
      (tester) async {
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.text('YOLCULUK'), findsOneWidget);
    expect(find.text('KEŞFET'), findsOneWidget);
    expect(find.text('ARAÇLAR'), findsOneWidget);
    expect(find.text('HESAP'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.byIcon(Icons.map_outlined), findsWidgets);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
    expect(find.byKey(const ValueKey('drawer-scanner-hero')), findsOneWidget);
    expect(find.text('Premium'), findsWidgets);
    expect(find.byKey(const ValueKey('drawer-action-Rotori Eats')),
        findsOneWidget);
  });

  testWidgets('uçuş satırı boş şehir+havaalanı ile "—" gösterir',
      (tester) async {
    final now = DateTime.now();
    String d(int off) {
      final t = now.add(Duration(days: off));
      return '${t.year.toString().padLeft(4, '0')}-'
          '${t.month.toString().padLeft(2, '0')}-'
          '${t.day.toString().padLeft(2, '0')}';
    }

    // Bir bacak: şehir + havaalanı boş; dateTime dolu (blank-leg değil).
    // Diğer bacak: normal Tokyo/HND. Amaç: boş satır "—" ile görünmeli,
    // tamamen blank filtre dışına atılmamalı (dateTime dolu).
    final trip = Trip(
      id: 'trip-flights',
      slug: 'flights-test',
      title: 'Uçuş Testi',
      timezone: 'Asia/Tokyo',
      tripStart: d(-1),
      tripEnd: d(1),
      flights: TripFlights(
        outbound: [
          FlightLeg(city: '', airport: '', dateTime: '${d(-1)}T10:00:00'),
          FlightLeg(
              city: 'Tokyo', airport: 'HND', dateTime: '${d(-1)}T18:00:00'),
        ],
        returnLegs: [
          // Tamamen boş bacak → filtre dışı kalmalı
          FlightLeg(city: '', airport: '', dateTime: ''),
        ],
      ),
      preferences: TripPreferences(
        travelDates: TravelDates(start: d(-1), end: d(1)),
        pace: Pace.moderate,
      ),
      days: [
        DayPlan(
            dayNumber: 1, date: d(0), theme: 'x', tags: const [], items: []),
      ],
    );

    await tester.pumpWidget(harness(trip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Uçuş özeti artık drawer'ın içinde — hamburger'a dokun, aç.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.flight_takeoff));
    await tester.pumpAndSettle();

    // Boş bacak "—" olarak render olmalı (_DrawerFlightsMini._iata)
    expect(find.text('—'), findsWidgets);
    // Dolu bacak korunmalı — IATA "HND" görünür (city yerine airport tercih).
    expect(find.textContaining('HND'), findsWidgets);
  });

  group('Düzenleme modu', () {
    testWidgets('durak eklerken bilet sabitleme seçenekleri açılır',
        (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(_sampleTrip()));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pump(const Duration(milliseconds: 100));

      final addStop = find.text(tr('viewer.edit.addPlace')).first;
      await tester.scrollUntilVisible(
        addStop,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(addStop);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'teamLab Planets');
      await tester.tap(find.byKey(const ValueKey('add-place-has-ticket')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ticket-duration-options')),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey('ticket-fixed-summary')), findsOneWidget);
      expect(find.text(tr('viewer.edit.addTicketed')), findsOneWidget);
    });

    testWidgets('✎ ikonuna basınca edit modu açılır, günler auto-expand olur',
        (tester) async {
      await tester.pumpWidget(harness(_sampleTrip()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Başlangıç: edit ikonu (kalem) görünür.
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

      // Edit moduna geç.
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Kalem → onay (✓) olur, baştan-oluştur (⟳) ikonu belirir.
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      // Yeni UX: satırlarda sürükleme tutamacı, gün başlığında yatay menü.
      expect(find.byIcon(Icons.drag_handle_rounded), findsWidgets);
      expect(find.byIcon(Icons.more_horiz), findsWidgets);
    });

    testWidgets('edit modunda sürükle/sil affordansları görünür',
        (tester) async {
      await tester.pumpWidget(harness(_sampleTrip()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Eski 3-nokta satır menüsü kaldırıldı; yerine drag + swipe akışı var.
      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(find.byKey(const ValueKey('draggable-it2')), findsOneWidget);
      expect(find.byKey(const ValueKey('dismiss-it2')), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsWidgets);
    });

    testWidgets('baştan-oluştur ikonu onay dialogu gösterir', (tester) async {
      await tester.pumpWidget(harness(_sampleTrip()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      // Onay dialogu — başlık + iki buton.
      expect(find.text('Plan baştan oluşturulsun mu?'), findsOneWidget);
      expect(find.text('Vazgeç'), findsOneWidget);
      expect(find.text('Baştan oluştur'), findsWidgets);
    });

    testWidgets('kilitli aktivite sürüklenemez ve değiştirilemez',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final trip = _sampleTrip();
      final locked = trip.days[1].items.single;
      locked
        ..lockType = ActivityLockType.flight
        ..fixedStartTime = '10:00'
        ..canChangeDay = false
        ..canChangeTime = false
        ..canReorder = false
        ..canDelete = false
        ..lockReason = 'Bu saat uçuş bilgisinden geliyor.';

      await tester.pumpWidget(harness(trip));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.lock), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Bu saat uçuş bilgisinden geliyor.',
        ),
        findsAtLeastNWidgets(1),
      );
      semantics.dispose();
    });

    testWidgets('başarılı taşıma işleminden sonra geri al planı geri getirir',
        (tester) async {
      await tester.pumpWidget(harness(_sampleTrip()));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pump(const Duration(milliseconds: 100));

      final source = find.text('Aktif Aktivite');
      final target = find.text('Gelecek Gün Teması');
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(source));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(
        tester.getCenter(target),
        timeStamp: const Duration(milliseconds: 300),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('11:15'), findsOneWidget);
      expect(find.text('Geri al'), findsOneWidget);
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).duration,
        const Duration(seconds: 5),
      );
      await tester.tap(find.text('Geri al'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('11:15'), findsNothing);
    });

    testWidgets(
        'mevcut transfer/check-in çakışması sürükle-bırak ile başka güne taşımayı engellemez',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final trip = _sampleTrip();
      trip.days[1].items = [
        TimelineItem(
          id: 'transfer',
          title: 'Otele transfer',
          time: '14:00',
          durationMin: 60,
          kind: TimelineItemKind.transport,
        ),
        TimelineItem(
          id: 'checkin',
          title: 'Varış & check-in',
          time: '15:00',
          durationMin: 120,
          kind: TimelineItemKind.hotel,
          lockType: ActivityLockType.hotel,
          fixedStartTime: '15:00',
          canChangeDay: false,
          canChangeTime: false,
          canReorder: false,
          canDelete: false,
        ),
        TimelineItem(
          id: 'dinner',
          title: 'Hafif akşam yemeği',
          time: '19:30',
          durationMin: 60,
          kind: TimelineItemKind.meal,
        ),
      ];

      await tester.pumpWidget(harness(trip));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pump(const Duration(milliseconds: 100));

      final source = find.byKey(const ValueKey('draggable-dinner'));
      final target = find.text('Gelecek Gün Teması');
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(source));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(
        tester.getCenter(target),
        timeStamp: const Duration(milliseconds: 300),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Hafif akşam yemeği → Gün 3'),
        findsOneWidget,
      );
      expect(find.text('Hafif akşam yemeği'), findsOneWidget);
    });

    testWidgets('uzun bas drag ve VoiceOver taşıma açıklaması bulunur',
        (tester) async {
      await tester.pumpWidget(harness(_sampleTrip()));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byWidgetPredicate((widget) => widget is LongPressDraggable),
        findsWidgets,
      );
      expect(
        find.bySemanticsLabel('Taşımak için uzun basıp sürükle'),
        findsWidgets,
      );
    });

    testWidgets('uzun basıp gün kartına bırakma anında güne ve saate taşır',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final trip = _sampleTrip();

      await tester.pumpWidget(harness(trip));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pump(const Duration(milliseconds: 100));

      final source = find.text('Aktif Aktivite');
      final target = find.text('Gelecek Gün Teması');
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(source));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(
        tester.getCenter(target),
        timeStamp: const Duration(milliseconds: 300),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Aktif Aktivite'), findsOneWidget);
      expect(find.text('11:15'), findsOneWidget,
          reason: 'hedef günün sonuna bırakılan aktivite otomatik saatlenmeli');
      expect(
        find.textContaining('Aktif Aktivite → Gün 3, 11:15'),
        findsOneWidget,
      );
    });

    testWidgets('geçersiz saat slotu gri ve dokunulamazdır', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final trip = _sampleTrip();
      trip.days[1].items = [
        TimelineItem(
          id: 'first',
          title: 'İlk Aktivite',
          time: '09:00',
          durationMin: 60,
        ),
        TimelineItem(
          id: 'second',
          title: 'İkinci Aktivite',
          time: '11:30',
          durationMin: 60,
        ),
      ];

      await tester.pumpWidget(harness(trip));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('11:30'));
      await tester.pumpAndSettle();

      final blocked =
          tester.widget<InkWell>(find.byKey(const ValueKey('time-slot-600')));
      expect(blocked.onTap, isNull, reason: '10:00 slotu pasif olmalı');
      final available =
          tester.widget<InkWell>(find.byKey(const ValueKey('time-slot-615')));
      expect(available.onTap, isNotNull, reason: '10:15 slotu seçilebilmeli');
    });

    testWidgets('hedef günde boşluk yoksa taşıma tamamlanamaz', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final trip = _sampleTrip();
      trip.days[2].items = [
        TimelineItem(
          id: 'busy',
          title: 'Dolu Gün',
          time: '08:00',
          durationMin: 14 * 60,
        ),
      ];

      await tester.pumpWidget(harness(trip));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pump(const Duration(milliseconds: 100));

      // Aktif gün öğesinin saat rozetinden düzenleme sheet'ini aç.
      await tester.tap(find.text('10:00').at(1));
      await tester.pumpAndSettle();

      final sheet = find.byType(BottomSheet);
      await tester.tap(
        find.descendant(of: sheet, matching: find.text('Gün 3')).first,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Bu günde uygun zaman aralığı bulunamadı.'),
        findsOneWidget,
      );
      final saveButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.descendant(of: sheet, matching: find.text('Kaydet')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets(
        'undo snackbarı erişilebilirlik modunda da 5 saniye sonra kapanır',
        (tester) async {
      await tester.pumpWidget(
        harness(_sampleTrip(), accessibleNavigation: true),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pump(const Duration(milliseconds: 100));

      final source = find.text('Aktif Aktivite');
      final target = find.text('Gelecek Gün Teması');
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(source));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(
        tester.getCenter(target),
        timeStamp: const Duration(milliseconds: 300),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Geri al'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(find.text('Geri al'), findsNothing);
    });
  });
}
