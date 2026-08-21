// Plan viewer widget testi — temalı görüntüleyicinin temel davranışları:
// başlık render, aktif gün genişletilmiş + geçmiş gün soluk, tema seçici açılır.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rotori/data/plans_repository.dart';
import 'package:rotori/core/supabase_client.dart';
import 'package:rotori/domain/plan_schedule_engine.dart';
import 'package:rotori/domain/route_matrix.dart';
import 'package:rotori/domain/route_execution.dart';
import 'package:rotori/features/tickets/data/ticket_local_media_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rotori/core/debug_clock.dart';
import 'package:rotori/data/device_steps.dart';
import 'package:rotori/core/l10n.dart';
import 'package:rotori/features/plans/premium_provider.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/plans/plan_edit_session.dart';
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

/// Tek günlük, saatli üç duraklı Trip — saat bazlı "sıradaki aktivite"
/// seçimini sabit bir "şimdi" ile test etmek için.
Trip _hourTrip(DateTime day) {
  final date = '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
  return Trip(
    id: 'hour-trip',
    slug: 'hour-trip',
    title: 'Saat Testi',
    subtitle: 'Widget testi',
    timezone: 'Asia/Tokyo',
    tripStart: date,
    tripEnd: date,
    flights: TripFlights(),
    preferences: TripPreferences(
      travelDates: TravelDates(start: date, end: date),
      pace: Pace.moderate,
    ),
    days: [
      DayPlan(
        dayNumber: 1,
        date: date,
        theme: 'Saat Günü',
        tags: const ['test'],
        items: [
          TimelineItem(id: 'h1', title: 'Sabah Durağı', time: '09:00'),
          TimelineItem(id: 'h2', title: 'Öğlen Durağı', time: '13:00'),
          TimelineItem(id: 'h3', title: 'Akşam Durağı', time: '18:00'),
        ],
      ),
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

Trip _explicitTransportTrip() {
  final trip = _routeUiTrip();
  trip.days.single.items = [
    TimelineItem(
      id: 'airport-transfer',
      title: 'Otele transfer',
      description: '14:45 varış · 30 dk · Metro · Otobüs · Taksi',
      time: '14:15',
      kind: TimelineItemKind.transport,
    ),
    TimelineItem(
      id: 'hotel-checkin',
      title: 'Varış & check-in',
      time: '15:15',
      kind: TimelineItemKind.hotel,
    ),
  ];
  return trip;
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

class _MemoryTicketMediaStore implements TicketLocalMediaStore {
  final Map<String, Uint8List> _staged = {};
  final Map<String, Uint8List> _committed = {};
  var _nextId = 0;

  int get stagedCount => _staged.length;
  int get committedCount => _committed.length;
  Uint8List? lastStagedBytes;

  void seedCommitted(String ref, List<int> bytes) {
    _committed[ref] = Uint8List.fromList(bytes);
  }

  bool containsCommitted(String ref) => _committed.containsKey(ref);

  @override
  Future<StagedTicketMedia> stage({
    required String planId,
    required String ticketId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final normalized = normalizeTicketMediaExtension(extension);
    final token = '$planId/$ticketId/${_nextId++}';
    lastStagedBytes = Uint8List.fromList(bytes);
    _staged[token] = Uint8List.fromList(bytes);
    return StagedTicketMedia(token: token, extension: normalized);
  }

  @override
  Future<String> commit(StagedTicketMedia media) async {
    final bytes = _staged.remove(media.token)!;
    final ref = 'memory:${media.token}.${media.extension}';
    _committed[ref] = bytes;
    return ref;
  }

  @override
  Future<Uint8List?> read(String localMediaRef) async =>
      _committed[localMediaRef];

  @override
  Future<void> discard(StagedTicketMedia media) async {
    _staged.remove(media.token);
  }

  @override
  Future<void> delete(String localMediaRef) async {
    _committed.remove(localMediaRef);
  }

  @override
  Future<void> cleanupStale({required DateTime now}) async {}
}

void main() {
  setUp(() {
    // Viewer regresyonları eski düzen davranışını doğrudan test eder; yeni
    // kurulum varsayılanı viewer_theme_test.dart içinde ayrıca doğrulanır.
    SharedPreferences.setMockInitialValues({
      'viewer:template': 'journey-progress',
      kPremiumPrefsKey: true,
    });
  });

  Widget harness(
    Trip trip, {
    bool accessibleNavigation = false,
    RouteMatrixRepository? routeRepository,
    bool debugClock = false,
    DateTime? nowOverride,
    int? deviceSteps,
    TicketLocalMediaStore? ticketMediaStore,
    Future<XFile?> Function(ImageSource source)? pickTicketImage,
    Future<PlanEditResult> Function(
      PlanEditSession session,
      PlanEditCommand command,
    )? executeTicketCommand,
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
        // Debug saat barı varsayılan kapalı; yalnız saat testleri açar.
        if (debugClock) debugClockBarEnabledProvider.overrideWithValue(true),
        // Sabit "şimdi": saat bazlı sıradaki-aktivite seçimini duvar saatinden
        // bağımsız test etmek için.
        if (nowOverride != null) nowProvider.overrideWithValue(nowOverride),
        // Telefon adım sayacını taklit et.
        if (deviceSteps != null)
          deviceStepReaderProvider.overrideWithValue((_) async => deviceSteps),
        if (ticketMediaStore != null)
          ticketLocalMediaStoreProvider.overrideWithValue(ticketMediaStore),
        if (pickTicketImage != null)
          ticketImagePickerProvider.overrideWithValue(pickTicketImage),
        if (executeTicketCommand != null)
          ticketEditCommandExecutorProvider
              .overrideWithValue(executeTicketCommand),
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

  testWidgets('geçmiş gün görüntülemede gizli, düzenleme modunda geri gelir',
      (tester) async {
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Görüntüleme modu: geçmiş gün (1. gün) listeden düşer, aktif gün en üstte.
    expect(find.text('Geçmiş Gün Teması'), findsNothing);
    expect(find.text('Aktif Gün Teması'), findsWidgets);

    // Düzenleme moduna geç → geçmiş gün de düzenlenebilsin diye geri gelir.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Geçmiş Gün Teması'), findsWidgets);
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

  testWidgets('hava durumuna göre düzenle aksiyonu ücretsiz kullanıcıda görünür',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      kPremiumPrefsKey: false,
      'viewer:template': 'journey-progress',
    });
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final optimize = find.byKey(const ValueKey('optimize-route-2'));
    expect(optimize, findsOneWidget);
    expect(find.text(tr('routeOptimization.weatherAction')), findsOneWidget);

    await tester.scrollUntilVisible(
      optimize,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(optimize);
    await tester.pumpAndSettle();

    expect(find.text(tr('routeOptimization.needTwoStops')), findsOneWidget);
  });

  testWidgets('premium durumu hava aksiyonunun etiketini değiştirmez',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      kPremiumPrefsKey: true,
      'viewer:template': 'journey-progress',
    });
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Provider prefs'i asenkron okuyor — yerleşmesini bekle.
    await tester.pump(const Duration(milliseconds: 200));

    final optimize = find.byKey(const ValueKey('optimize-route-2'));
    expect(optimize, findsOneWidget);
    expect(find.text(tr('routeOptimization.weatherAction')), findsOneWidget);

    await tester.scrollUntilVisible(
      optimize,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(optimize);
    await tester.pumpAndSettle();

    expect(find.text(tr('routeOptimization.premium.title')), findsNothing);
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

    // Hem kalkış hem duraklar-arası bacak, varış durağının rozetine iner.
    final departureBadge =
        find.byKey(const ValueKey('timeline-transit-badge-b'));
    final betweenStopsBadge =
        find.byKey(const ValueKey('timeline-transit-badge-a'));
    await tester.scrollUntilVisible(
      departureBadge,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(departureBadge, findsOneWidget);
    expect(betweenStopsBadge, findsOneWidget);

    // Rozet kartı büyütmemeli: tek satırlık kompakt yükseklik.
    expect(tester.getSize(departureBadge).height, lessThan(24));

    // Ayrı bacak satırları kaldırıldı.
    expect(
      find.byKey(const ValueKey('saved-route-leg-1-day-1-base-b')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('saved-route-leg-1-b-a')), findsNothing);
    expect(
      find.descendant(
        of: departureBadge,
        matching: find.text(tr('routeOptimization.legs.estimated')),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'açık ulaşım öğesi kendi özetini gösterir, çevresinde sahte bacak üretmez',
      (tester) async {
    // Trip'in tek günü bugüne kurulu (14:15/15:15 saatli duraklar); gerçek
    // saat bu saatleri geçmişse `_isTripFinished` devreye girip günlük
    // timeline yerine "Gezi tamamlandı" raporunu gösterir ve bu testi saatin
    // koşulma anına bağlı kılardı. `nowOverride` günü sabit 10:00'a kilitler.
    final today = DateTime.now();
    final beforeAnyStop = DateTime(today.year, today.month, today.day, 10);
    await tester.pumpWidget(
      harness(_explicitTransportTrip(), nowOverride: beforeAnyStop),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -360),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('14:45 varış · 30 dk · Metro · Otobüs · Taksi'),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('saved-route-leg-1-day-1-base-airport-transfer'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('saved-route-leg-1-airport-transfer-hotel-checkin'),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'uzun açıklamalı durakta ulaşım rozeti taşmaz ve etiketi tam görünür',
      (tester) async {
    // Regresyon: rozetin iç Row'u flex'siz Text taşıdığı için maxWidth:
    // infinity ile ölçülüyordu; ellipsis devreye girmiyor, Container clip
    // yapmadığı için taşan "… dk" komşu açıklamanın üstüne basıyordu.
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final trip = _savedRouteTrip();
    trip.days.single.items.firstWhere((item) => item.id == 'b').description =
        'Tokyo · cumartesi kalabalığı için sabah erken saatleri tercih et';

    await tester.pumpWidget(harness(trip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final badge = find.byKey(const ValueKey('timeline-transit-badge-b'));
    await tester.scrollUntilVisible(
      badge,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Overflow olsaydı RenderFlex hata fırlatırdı.
    expect(tester.takeException(), isNull);

    // Rozet etiketi kırpılmadan duruyor ve satır tek satırlık kalıyor.
    expect(find.text('Metro · 18 dk'), findsOneWidget);
    expect(tester.getSize(badge).height, lessThan(24));

    // Açıklama rozetin üstüne binmiyor: ya sağında ya alt satırda durur.
    final badgeRect = tester.getRect(badge);
    final descRect = tester.getRect(find.textContaining('cumartesi'));
    expect(
      descRect.left >= badgeRect.right - 0.5 ||
          descRect.top >= badgeRect.bottom - 0.5,
      isTrue,
      reason: 'açıklama rozetle çakışıyor: $descRect vs $badgeRect',
    );
  });

  testWidgets(
      'onaylanmış rota snapshotı plan yeniden açılınca günlük akışta görünür',
      (tester) async {
    await tester.pumpWidget(harness(_savedRouteTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // Geliş bacağı artık kendi satırında değil, varış durağının alt
    // başlığındaki rozettedir.
    final badge = find.byKey(const ValueKey('timeline-transit-badge-b'));
    await tester.scrollUntilVisible(
      badge,
      180,
      scrollable: find.byType(Scrollable).first,
    );

    expect(badge, findsOneWidget);
    expect(find.text('Metro · 18 dk'), findsOneWidget);

    // Ayrı bacak satırı ve onun "A  →  B" metni kaldırıldı.
    expect(
      find.byKey(const ValueKey('saved-route-leg-1-day-1-base-b')),
      findsNothing,
    );
    expect(find.text('Tokyo  →  Tokyo Skytree'), findsNothing);
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
    // Satırlardan küçük görseller kalkınca liste kısaldı ve hedef sabit üst
    // barın altına düşebiliyor; biraz geri kaydırıp barın altından çıkar.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
    await tester.pumpAndSettle();
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

  testWidgets('şehir geçiş nesnesi kartlar arasında eşit boşlukta durur',
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
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
    await tester.pumpAndSettle();

    final pill = find.byKey(
      const ValueKey('city-transition-Tokyo-Kyoto-shinkansen'),
    );
    expect(pill, findsOneWidget);

    // Kapsül tek dokunma hedefi ve gövdesi yeterince yüksek. Eskiden çerçeveli
    // Container'ın 12px padding'i InkWell'in DIŞINDA kalıyordu.
    expect(tester.getSize(pill).height, greaterThanOrEqualTo(34));

    // Dikey ritim: gün kartı kendi altına 12px bırakıyor, bu yüzden geçiş
    // satırının ÜST boşluğu 0 ve ALT boşluğu 12 olmalı — iki kart arasında
    // eşit 12/12. Eskiden `symmetric(vertical: 8)` vardı; üstte 20px (kartın
    // 12'si + pill'in 8'i), altta 8px oluşuyordu.
    final insets = find
        .ancestor(of: pill, matching: find.byType(Padding))
        .evaluate()
        .map((e) => (e.widget as Padding).padding)
        .toList();
    expect(
      insets,
      contains(const EdgeInsets.only(bottom: 12)),
      reason: 'geçiş satırının sarmalayıcı boşluğu 0/12 değil: $insets',
    );
    expect(
      insets,
      isNot(contains(const EdgeInsets.symmetric(vertical: 8, horizontal: 4))),
      reason: 'eski asimetrik boşluk geri gelmiş',
    );

    // `open_in_new` kaldırıldı: pill dışarı açmıyor, mod seçiciyi açıyor.
    expect(
      find.descendant(
          of: pill, matching: find.byIcon(Icons.open_in_new_rounded)),
      findsNothing,
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
    // Satırlardan küçük görseller kalkınca liste kısaldı ve hedef sabit üst
    // barın altına düşebiliyor; biraz geri kaydırıp barın altından çıkar.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
    await tester.pumpAndSettle();
    await tester.tap(transition);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('city-transition-ticket-action')),
    );
    await tester.pumpAndSettle();

    expect(find.text(tr('ticketReview.title')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(tr('ticketReview.title')), findsNothing);
    expect(find.text('Tokyo → Kyoto ulaşımı'), findsOneWidget);
  });

  testWidgets('Biletler sekmesi wallet başlığını ve kalıcı alt navı gösterir',
      (tester) async {
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text(tr('viewer.quick.tickets')).last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ticket-wallet-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('ticket-wallet-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('viewer-quick-nav')), findsOneWidget);
  });

  testWidgets('Biletler ana sayfanın kaydırma konumunu miras almaz',
      (tester) async {
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await tester.pump();
    await tester.tap(find.text(tr('viewer.quick.tickets')).last);
    await tester.pumpAndSettle();

    final title = find.byKey(const ValueKey('ticket-wallet-title'));
    expect(title, findsOneWidget);
    expect(tester.getTopLeft(title).dy, greaterThanOrEqualTo(0));
    expect(tester.getBottomRight(title).dy, lessThan(600));
  });

  testWidgets('ticket manuel giriş aynı review akışından walletta görünür',
      (tester) async {
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text(tr('viewer.quick.tickets')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ticket-wallet-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('viewer-quick-nav')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ticket-add-manual')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ticket-review-label')),
      'Ghibli Museum',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ticket-review-save')));
    await tester.pumpAndSettle();

    expect(find.text('Ghibli Museum'), findsOneWidget);
    expect(find.byKey(const ValueKey('viewer-quick-nav')), findsOneWidget);
  });

  testWidgets('ticket ekleme sheeti viewer shell üstünde açılır',
      (tester) async {
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text(tr('viewer.quick.tickets')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ticket-wallet-add')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ticket-add-gallery')), findsOneWidget);
    expect(find.byKey(const ValueKey('viewer-quick-nav')), findsOneWidget);
  });

  testWidgets(
      'aktivite detayındaki bilet ekle ortak wallet akışını açar ve alt navı korur',
      (tester) async {
    final trip = _sampleTrip();
    trip.days[1].items = [
      TimelineItem(
        id: 'activity-ticket-entry',
        title: 'teamLab Planets',
        time: '10:00',
      ),
    ];
    await tester.pumpWidget(harness(trip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final activity = find.text('teamLab Planets');
    await tester.scrollUntilVisible(
      activity,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(activity);
    await tester.pumpAndSettle();

    final addTicket = find.byKey(const ValueKey('place-detail-add-ticket'));
    await tester.dragUntilVisible(
      addTicket,
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    final quickNavElement =
        tester.element(find.byKey(const ValueKey('viewer-quick-nav')));
    await tester.tap(addTicket);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ticket-wallet-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('ticket-add-gallery')), findsOneWidget);
    expect(find.byKey(const ValueKey('ticket-add-manual')), findsOneWidget);
    expect(find.byKey(const ValueKey('ticket-add-plan')), findsNothing);
    expect(
      tester.element(find.byKey(const ValueKey('viewer-quick-nav'))),
      same(quickNavElement),
    );
  });

  testWidgets('aktivite detayından manuel bilet etkinliğe kimlikle bağlanır',
      (tester) async {
    final trip = _sampleTrip();
    trip.days[1].items = [
      TimelineItem(
        id: 'activity-ticket-attach',
        title: 'teamLab Planets',
        time: '10:00',
      ),
    ];
    final commands = <PlanEditCommand>[];
    await tester.pumpWidget(harness(
      trip,
      executeTicketCommand: (_, command) async {
        commands.add(command);
        return PlanEditResult.success(trip, const []);
      },
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final activity = find.text('teamLab Planets');
    await tester.scrollUntilVisible(
      activity,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(activity);
    await tester.pumpAndSettle();
    final addTicket = find.byKey(const ValueKey('place-detail-add-ticket'));
    await tester.dragUntilVisible(
      addTicket,
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    await tester.tap(addTicket);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ticket-add-manual')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ticket-review-save')));
    await tester.pumpAndSettle();

    expect(commands, hasLength(1));
    expect(commands.single, isA<AttachTicketToActivity>());
    expect(
      (commands.single as AttachTicketToActivity).activityId,
      'activity-ticket-attach',
    );
  });

  testWidgets('ticket detaydan silinince wallettan kaldırılır', (tester) async {
    final trip = _sampleTrip()
      ..tickets = [
        Ticket(
          id: 'delete-me',
          kind: 'attraction',
          label: 'Silinecek Bilet',
          purchased: true,
          visitDate: _sampleTrip().days.last.date,
        ),
      ];
    await tester.pumpWidget(harness(trip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text(tr('viewer.quick.tickets')).last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('ticket-wallet-card-press-delete-me')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ticket-detail-delete')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('ticket-detail-confirm-delete')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Silinecek Bilet'), findsNothing);
    expect(find.byKey(const ValueKey('ticket-wallet-empty')), findsOneWidget);
  });

  testWidgets('bağlı bilet detay kaydı etkinlik komutunu kullanır',
      (tester) async {
    final trip = _sampleTrip()
      ..tickets = [
        Ticket(
          id: 'linked-ticket',
          kind: 'attraction',
          label: 'Bağlı Bilet',
          purchased: true,
          linkedActivityId: 'it2',
        ),
      ];
    final commands = <PlanEditCommand>[];
    await tester.pumpWidget(harness(
      trip,
      executeTicketCommand: (_, command) async {
        commands.add(command);
        return PlanEditResult.success(trip, const []);
      },
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text(tr('viewer.quick.tickets')).last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('ticket-wallet-card-press-linked-ticket')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ticket-detail-label')),
      'Bağlı Bilet Güncel',
    );
    await tester.tap(find.byKey(const ValueKey('ticket-detail-save')));
    await tester.pumpAndSettle();

    expect(commands, hasLength(1));
    expect(commands.single, isA<AttachTicketToActivity>());
  });

  testWidgets('plandan bilet seçimi review üzerinden etkinliğe bağlanır',
      (tester) async {
    final trip = _sampleTrip();
    trip.days[1].items = [
      TimelineItem(
        id: 'plan-ticket-item',
        title: 'teamLab Planets',
        time: '14:30',
      ),
    ];
    final commands = <PlanEditCommand>[];
    await tester.pumpWidget(harness(
      trip,
      executeTicketCommand: (_, command) async {
        commands.add(command);
        return PlanEditResult.success(trip, const []);
      },
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text(tr('viewer.quick.tickets')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ticket-wallet-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ticket-add-plan')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('teamLab Planets'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('ticket-review-label')),
          )
          .controller
          ?.text,
      'teamLab Planets',
    );
    await tester.tap(find.byKey(const ValueKey('ticket-review-save')));
    await tester.pumpAndSettle();

    expect(commands, hasLength(1));
    expect(commands.single, isA<AttachTicketToActivity>());
  });

  testWidgets('medya değiştirme kaydı başarısızsa eski medya korunur',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const oldRef = 'memory:old-ticket.png';
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final mediaStore = _MemoryTicketMediaStore()
      ..seedCommitted(oldRef, pngBytes);
    final trip = _sampleTrip()
      ..tickets = [
        Ticket(
          id: 'replace-ticket',
          kind: 'attraction',
          label: 'Medyası Değişecek',
          purchased: true,
          localMediaRef: oldRef,
        ),
      ];
    await tester.pumpWidget(harness(
      trip,
      ticketMediaStore: mediaStore,
      pickTicketImage: (_) async => XFile.fromData(
        Uint8List.fromList(pngBytes),
        name: 'replacement.png',
        mimeType: 'image/png',
      ),
      executeTicketCommand: (_, __) async => PlanEditResult.failure(
        const PlanEditFailure(
          PlanEditFailureCode.activityNotFound,
          message: 'simulated replacement failure',
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text(tr('viewer.quick.tickets')).last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('ticket-wallet-card-press-replace-ticket')),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('ticket-detail-replace-media')),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(
      find.byKey(const ValueKey('ticket-detail-replace-media')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr('ticketAdd.gallery')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ticket-review-save')));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;

    expect(mediaStore.containsCommitted(oldRef), isTrue);
    expect(mediaStore.committedCount, 1);
    expect(mediaStore.stagedCount, 0);
  });

  testWidgets('silme kaydı başarısızsa mevcut medya korunur', (tester) async {
    const mediaRef = 'memory:keep-me.png';
    final mediaStore = _MemoryTicketMediaStore()
      ..seedCommitted(
        mediaRef,
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
    final trip = _sampleTrip()
      ..tickets = [
        Ticket(
          id: 'keep-ticket',
          kind: 'attraction',
          label: 'Korunacak Bilet',
          purchased: true,
          localMediaRef: mediaRef,
        ),
      ];
    await tester.pumpWidget(harness(
      trip,
      ticketMediaStore: mediaStore,
      executeTicketCommand: (_, __) async => PlanEditResult.failure(
        const PlanEditFailure(
          PlanEditFailureCode.activityNotFound,
          message: 'simulated delete failure',
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text(tr('viewer.quick.tickets')).last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('ticket-wallet-card-press-keep-ticket')),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('ticket-detail-delete')),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(
      find.byType(Scrollable).last,
      const Offset(0, -140),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ticket-detail-delete')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('ticket-detail-confirm-delete')),
    );
    await tester.pumpAndSettle();

    expect(mediaStore.containsCommitted(mediaRef), isTrue);
    expect(find.text('Korunacak Bilet'), findsOneWidget);
  });

  testWidgets('ticket import persistence hatasında medya rollback edilir',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final mediaStore = _MemoryTicketMediaStore();
    final picked = XFile.fromData(
      Uint8List.fromList(const [137, 80, 78, 71]),
      name: 'ticket.png',
      mimeType: 'image/png',
    );
    await tester.pumpWidget(harness(
      _sampleTrip(),
      ticketMediaStore: mediaStore,
      pickTicketImage: (_) async => picked,
      executeTicketCommand: (_, __) async => PlanEditResult.failure(
        const PlanEditFailure(
          PlanEditFailureCode.activityNotFound,
          message: 'simulated persistence failure',
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text(tr('viewer.quick.tickets')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ticket-wallet-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ticket-add-gallery')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ticket-review-label')),
      'Rollback Bileti',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ticket-review-save')));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;

    expect(mediaStore.stagedCount, 0);
    expect(mediaStore.committedCount, 0);
    expect(mediaStore.lastStagedBytes, orderedEquals(const [137, 80, 78, 71]));
    expect(find.text('Rollback Bileti'), findsNothing);
  });

  test('aynı başlıklı bağlı bilet başka etkinliğe eşleşmez', () {
    final linked = Ticket(
      id: 'linked-a',
      kind: 'attraction',
      label: 'teamLab Planets',
      purchased: true,
      linkedActivityId: 'activity-a',
    );
    final item = TimelineItem(id: 'activity-b', title: 'teamLab Planets');

    expect(findExistingTicketForItem([linked], item), isNull);
  });

  testWidgets('Keşfet alt menü butonu keşif haritasını açar', (tester) async {
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final nav = find.byKey(const ValueKey('viewer-quick-nav')).hitTestable();
    final originalNavElement = tester.element(nav);
    final originalNavTopLeft = tester.getTopLeft(nav);

    await tester.tap(find.text(tr('viewer.quick.explore')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(tr('reward.title')), findsOneWidget);
    final visibleNav =
        find.byKey(const ValueKey('viewer-quick-nav')).hitTestable();
    expect(visibleNav, findsOneWidget);
    expect(tester.element(visibleNav), same(originalNavElement));
    expect(tester.getTopLeft(visibleNav), originalNavTopLeft);
  });

  testWidgets('tasarım seçici yatay üç önizlemeyi ve ücretsiz kilitleri sunar',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
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
    expect(find.text('Yolculuk'), findsOneWidget);
    expect(find.text('Rota Panoraması'), findsWidgets);
    expect(
      find.byKey(const ValueKey('viewer-template-horizontal-list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('viewer-template-selected-route-panorama')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('viewer-template-lock-journey-progress')),
      findsOneWidget,
    );
    await tester.drag(
      find.byKey(const ValueKey('viewer-template-horizontal-list')),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Harita'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('viewer-template-lock-map-focus')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('viewer-template-journey-progress')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('viewer-template-map-focus')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('viewer-template-map-focus')));
    await tester.pump();
    expect(find.text(tr('viewer.template.premium.title')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('rotori-premium-sheet')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('viewer-template-premium-close')),
    );
    await tester.tap(
      find.byKey(const ValueKey('viewer-template-premium-close')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('viewer-template-map-hero')),
      findsNothing,
    );
  });

  testWidgets('premium kullanıcı harita tasarımını açabilir', (tester) async {
    SharedPreferences.setMockInitialValues({kPremiumPrefsKey: true});
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byIcon(Icons.palette_outlined));
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('viewer-template-horizontal-list')),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('viewer-template-map-focus')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('viewer-template-map-hero')),
      findsOneWidget,
    );
  });

  testWidgets(
      'harita tasarımında gün seçimi haritayı ve tek rota kartını değiştirir',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'viewer:template': 'map-focus',
    });
    final trip = _sampleTrip();

    await tester.pumpWidget(harness(trip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.byKey(const ValueKey('viewer-template-map-hero')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('viewer-map-route-day-2')),
        matching: find.text('Aktif Aktivite'),
      ),
      findsOneWidget,
    );
    expect(find.text('Gecmis Aktivite'), findsNothing);
    expect(find.text('Gelecek Aktivite'), findsNothing);

    final dayThreeChip = tester.widget<InkWell>(
      find.byKey(const ValueKey('viewer-map-day-3')),
    );
    dayThreeChip.onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('viewer-map-route-day-3')),
        matching: find.text('Gelecek Aktivite'),
      ),
      findsOneWidget,
    );
    expect(find.text('Aktif Aktivite'), findsNothing);
    expect(find.text('Gecmis Aktivite'), findsNothing);
    expect(
      find.byKey(ValueKey('viewer-map-${trip.days[2].date}')),
      findsOneWidget,
    );
    final dayStrip = tester.widget<ListView>(
      find.byKey(const ValueKey('viewer-map-day-strip')),
    );
    expect(dayStrip.physics, isA<NeverScrollableScrollPhysics>());
  });

  testWidgets(
      'harita tasarımı sıradaki aktivite kartını haritanın altında gösterir',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'viewer:template': 'map-focus',
    });

    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // Gelecek bir günü seç: o günün ilk aktivitesi her zaman "sıradaki"dir,
    // böylece test duvar saatinden bağımsız (aktif gün, saatin ilerlemesiyle
    // "tamamlandı" olup kartı gizleyebilirdi).
    final dayThreeChip = tester.widget<InkWell>(
      find.byKey(const ValueKey('viewer-map-day-3')),
    );
    dayThreeChip.onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Kart harita ile aynı ekranda, ayrı bir sabit blok olarak durur.
    expect(
      find.byKey(const ValueKey('viewer-map-next-activity')),
      findsOneWidget,
    );
    // "SIRADAKI" rozeti kartın içinde görünür.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('viewer-map-next-activity')),
        matching: find.text('SIRADAKI'),
      ),
      findsOneWidget,
    );
    // Kart seçili günün ilk aktivitesini gösterir.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('viewer-map-next-activity')),
        matching: find.textContaining('Gelecek Aktivite'),
      ),
      findsOneWidget,
    );
    final mapHeight = tester
        .getSize(find.byKey(const ValueKey('viewer-template-map-hero')))
        .height;
    expect(mapHeight, inInclusiveRange(241.0, 270.0));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('viewer-map-next-activity')))
          .height,
      lessThanOrEqualTo(78),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('viewer-map-day-strip'))).height,
      closeTo(62, 0.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('rota panoraması tasarımı adım halkası ve metrikleri gösterir',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'viewer:template': 'route-panorama',
    });
    final trip = _sampleTrip();
    trip.days[1].stepsEstimate = 12400;

    await tester.pumpWidget(harness(trip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.byKey(const ValueKey('viewer-template-panorama-hero')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('viewer-panorama-step-ring')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('viewer-panorama-contrast-overlay')),
      findsOneWidget,
    );
    // Adım plandan gelir ve binlik ayraçla yazılır.
    expect(
      find.byKey(const ValueKey('viewer-panorama-steps')),
      findsOneWidget,
    );
    expect(find.text('12.400'), findsOneWidget);
    // Kalori adımdan türer: 12400 * 0.04 = 496.
    expect(find.text('496 kcal'), findsOneWidget);
    // Alt şerit metrikleri.
    expect(find.text('durak'), findsOneWidget);
    expect(find.text('ilerleme'), findsOneWidget);
    expect(find.text('kalan'), findsOneWidget);
    expect(find.text('rezervasyon'), findsOneWidget);
    // Gün akışı yolculuk tasarımıyla aynı kalır — aktif gün kartı yerinde.
    // Panoramanın üstündeki metrik kartı + sıradaki-aktivite bandı ekstra yer
    // kapladığı için gün kartı ilk ekranda olmayabilir, kaydırarak doğrula.
    await tester.scrollUntilVisible(
      find.text('Aktif Gün Teması'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Aktif Gün Teması'), findsWidgets);

    expect(
      find.byKey(const ValueKey('viewer-day-card-active-accent')),
      findsOneWidget,
    );
  });

  testWidgets('tema ve dil seçenekleri aynı satır içi seçim desenini kullanır',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byIcon(Icons.palette_outlined));
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('viewer-theme-option-apple-light')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('viewer-language-option-tr')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('viewer-theme-option-apple-light')),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('viewer-language-option-tr')),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'rota panoraması son GÜN değilken tamamlandı bandını hâlâ gösterir',
      (tester) async {
    // REGRESYON: panorama başlığı yolculuk temasının header'ını değiştiriyor
    // ama altındaki "sıradaki aktivite / gün tamamlandı" bandı
    // (_JourneyHeroSheet) unutulup hiç render edilmemişti — günün son
    // aktivitesi geçtiğinde kullanıcıya hiçbir şey söylenmiyordu. Bu, gezinin
    // SON günü olmayan bir gün tamamlandığında (gezi bitmedi) hâlâ eski
    // sade banner'ın çıktığını doğrular — tam rapor yalnız gezi tamamen
    // bittiğinde (bkz. bir altındaki test) devreye girmeli.
    SharedPreferences.setMockInitialValues({
      'viewer:template': 'route-panorama',
    });
    final trip = _sampleTrip(); // 3 gün: geçmiş, bugün (aktif), gelecek.
    final now = DateTime.now();
    // Bugünün (aktif gün, 2. gün) tek aktivitesi 10:00 — günü geç bir saate
    // taşı ki tamamlanmış sayılsın, ama gelecekte 3. gün hâlâ duruyor.
    final lateToday = DateTime(now.year, now.month, now.day, 23, 59);

    await tester.pumpWidget(harness(trip, nowOverride: lateToday));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.byKey(const ValueKey('viewer-template-panorama-hero')),
      findsOneWidget,
    );
    expect(find.text('Bugünün planı tamamlandı'), findsOneWidget);
    // Gezi bitmedi — tam rapor ÇIKMAMALI.
    expect(
      find.byKey(const ValueKey('viewer-trip-completion-report')),
      findsNothing,
    );
  });

  testWidgets(
      'rota panoraması gezinin SON aktivitesi geçince tam rapor gösterir',
      (tester) async {
    // Tek günlük gezide o gün aynı zamanda SON gün de olduğu için, günü
    // bitirmek gezinin TAMAMINI bitirir — artık sade banner değil, tüm
    // geziyi özetleyen detaylı rapor gösterilmeli ve gün kartı kapanmalı.
    SharedPreferences.setMockInitialValues({
      'viewer:template': 'route-panorama',
    });
    final trip = _hourTrip(DateTime(2026, 6, 15));

    // 19:00 → günün son durağı (18:00) da geçti, sıradaki kalmadı.
    await tester.pumpWidget(
      harness(trip, nowOverride: DateTime(2026, 6, 15, 19)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // Sade "Bugünün planı tamamlandı" bandı DEĞİL, tam rapor çıkmalı.
    expect(find.text('Bugünün planı tamamlandı'), findsNothing);
    expect(
      find.byKey(const ValueKey('viewer-trip-completion-report')),
      findsOneWidget,
    );
    expect(find.text('Gezi tamamlandı! 🎉'), findsOneWidget);
    // Gün kartı kapanmış olmalı — "Sabah Durağı" (ilk durak) görünmemeli.
    expect(find.text('Sabah Durağı'), findsNothing);
    // "Günleri gör" ile tekrar açılabilmeli.
    await tester.tap(
      find.byKey(const ValueKey('viewer-trip-report-toggle-days')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sabah Durağı'), findsOneWidget);
  });

  testWidgets('cihazdan gelen adım plan tahminini geçersiz kılar',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'viewer:template': 'route-panorama',
    });
    final trip = _sampleTrip();
    trip.days[1].stepsEstimate = 12400;

    await tester.pumpWidget(
      harness(
        trip,
        // Telefon sağlık verisi varmış gibi davran.
        deviceSteps: 8250,
      ),
    );
    await tester.pump();
    // Cihaz okuması asenkron — future çözülene kadar plan tahmini görünür.
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();

    // Plan tahmini değil cihaz değeri gösterilir + CİHAZ rozeti çıkar.
    expect(find.text('8.250'), findsOneWidget);
    expect(find.text('12.400'), findsNothing);
    expect(find.text('CİHAZ'), findsOneWidget);
    // Kalori de cihaz adımından hesaplanır: 8250 * 0.04 = 330.
    expect(find.text('330 kcal'), findsOneWidget);
  });

  testWidgets('harita tasarımında gezi bitince rapor CTA\'sı bottom sheet açar',
      (tester) async {
    // Harita günleri kapatmaz (tarih şeridiyle geziliyor kalır), ama gezi
    // tamamen bittiğinde "sıradaki aktivite" boşluğunda tam rapora götüren
    // bir CTA çıkmalı — aksi halde harita temasında da sessizlik olurdu.
    SharedPreferences.setMockInitialValues({
      'viewer:template': 'map-focus',
    });
    final trip = _hourTrip(DateTime(2026, 6, 15));

    // Bottom sheet açılışı haritayı yeniden düzenler ve testte gerçek ağ
    // olmadığı için tile istekleri 400 ile döner — bu, davranışla ilgisiz
    // bir gürültü. Diğer map testlerinin aksine burada CTA'ya dokunma +
    // sheet açılışı birden fazla ek pump tetiklediği için görmezden gel.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception is NetworkImageLoadException) return;
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    await tester.pumpWidget(
      harness(trip, nowOverride: DateTime(2026, 6, 15, 19)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final cta = find.byKey(const ValueKey('viewer-map-trip-complete-cta'));
    expect(cta, findsOneWidget);
    // Normal "sıradaki aktivite" kartı artık yok, CTA onun yerinde.
    expect(
      find.byKey(const ValueKey('viewer-map-next-activity')),
      findsNothing,
    );

    await tester.tap(cta);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      find.byKey(const ValueKey('viewer-trip-completion-report')),
      findsOneWidget,
    );
  });

  testWidgets('debug saat barı gün ilerletince yolculuk ilerleme sayacı artar',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'viewer:template': 'journey-progress',
    });

    await tester.pumpWidget(harness(_sampleTrip(), debugClock: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // Bar yalnız opt-in ile görünür.
    expect(
      find.byKey(const ValueKey('viewer-debug-clock-bar')),
      findsOneWidget,
    );
    // Aktif gün bugün = 2. gün → sayaç 2/3.
    expect(find.text('2/3'), findsOneWidget);

    // +1 gün: aktif gün 3'e kayar → sayaç 3/3.
    await tester.tap(
      find.byKey(const ValueKey('viewer-debug-clock-day-fwd')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('3/3'), findsOneWidget);
    expect(find.text('2/3'), findsNothing);
  });

  testWidgets(
      'gün ilerleyince geçmişte kalan gün gizlenir, yeni aktif gün en üstte',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'viewer:template': 'journey-progress',
    });

    await tester.pumpWidget(harness(_sampleTrip(), debugClock: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // Başta: 1. gün (geçmiş) gizli, 2. gün (aktif) görünür.
    expect(find.text('Geçmiş Gün Teması'), findsNothing);
    expect(find.text('Aktif Gün Teması'), findsWidgets);

    // +1 gün → aktif gün 3'e kayar; artık 2. gün de geçmişte kalıp gizlenir,
    // 3. gün (yeni aktif) görünür ve otomatik açılır.
    await tester.tap(
      find.byKey(const ValueKey('viewer-debug-clock-day-fwd')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Aktif Gün Teması'), findsNothing);
    expect(find.text('Gelecek Gün Teması'), findsWidgets);
    // Yeni aktif gün otomatik açık → aktivitesi görünür.
    expect(find.text('Gelecek Aktivite'), findsOneWidget);
  });

  testWidgets(
      'debug saat barı gün ilerletince harita sıradaki aktiviteyi günceller',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'viewer:template': 'map-focus',
    });

    await tester.pumpWidget(harness(_sampleTrip(), debugClock: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.byKey(const ValueKey('viewer-debug-clock-bar')),
      findsOneWidget,
    );

    // +1 gün → aktif gün 3 (gelecek); seçili gün otomatik takip eder ve kart
    // o günün ilk aktivitesini gösterir.
    await tester.tap(
      find.byKey(const ValueKey('viewer-debug-clock-day-fwd')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('viewer-map-next-activity')),
        matching: find.textContaining('Gelecek Aktivite'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('saat ilerledikçe sıradaki aktivite günün sonraki durağına kayar',
      (tester) async {
    // Yolculuk teması: harita/tile yok, sıradaki-aktivite kartı hero içinde.
    SharedPreferences.setMockInitialValues({
      'viewer:template': 'journey-progress',
    });
    final trip = _hourTrip(DateTime(2026, 6, 15));

    // 10:00 → sıradaki, 13:00'daki "Öğlen Durağı".
    await tester.pumpWidget(
      harness(trip, nowOverride: DateTime(2026, 6, 15, 10)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('viewer-journey-next-activity')),
        matching: find.textContaining('Öğlen Durağı'),
      ),
      findsOneWidget,
    );

    // 14:00 → 13:00 geçti, sıradaki 18:00'daki "Akşam Durağı".
    await tester.pumpWidget(
      harness(trip, nowOverride: DateTime(2026, 6, 15, 14)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('viewer-journey-next-activity')),
        matching: find.textContaining('Akşam Durağı'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('viewer-journey-next-activity')),
        matching: find.textContaining('Öğlen Durağı'),
      ),
      findsNothing,
    );
  });

  testWidgets('yolculuk tasarımı hero görseli ve parçalı ilerlemeyi gösterir',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'viewer:template': 'journey-progress',
    });

    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.byKey(const ValueKey('viewer-template-journey-hero')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('viewer-journey-progress-background')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('viewer-journey-segmented-progress')),
      findsOneWidget,
    );
    expect(find.text('İLERLEMEN'), findsOneWidget);

    expect(
      find.byKey(const ValueKey('viewer-panorama-city-background')),
      findsNothing,
    );

    // Hero görseli kartın tamamını kaplar; şehir fotoğrafı bu şablona ait
    // değildir.
    final heroWidth = tester
        .getSize(find.byKey(const ValueKey('viewer-template-journey-hero')))
        .width;
    final backgroundWidth = tester
        .getSize(
            find.byKey(const ValueKey('viewer-journey-progress-background')))
        .width;
    expect(
      backgroundWidth,
      closeTo(heroWidth, 0.5),
      reason: 'yolculuk hero görseli kartın tamamını kaplamıyor',
    );
  });

  testWidgets('şehir fotoğrafı yalnız rota panoraması kartında gösterilir',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'viewer:template': 'route-panorama',
    });

    await tester.pumpWidget(harness(_routeUiTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final imageFinder =
        find.byKey(const ValueKey('viewer-panorama-city-background'));
    final heroFinder =
        find.byKey(const ValueKey('viewer-template-panorama-hero'));
    final image = tester.widget<Image>(imageFinder);
    expect((image.image as AssetImage).assetName,
        'assets/images/city-hero-tokyo.webp');
    final imageSize = tester.getSize(imageFinder);
    final heroSize = tester.getSize(heroFinder);
    // Container anahtarı border ve 12 dp alt margin'i de ölçer; fotoğraf
    // bunların içindeki kırpılmış kart yüzeyini kaplar.
    expect(imageSize.width, closeTo(heroSize.width - 2, 0.5));
    expect(imageSize.height, closeTo(heroSize.height - 14, 0.5));
    expect(
      find.byKey(const ValueKey('viewer-template-journey-hero')),
      findsNothing,
    );
  });

  testWidgets(
      'harita tasarımında düzenleme yalnız seçili günü açık ve düzenlenebilir tutar',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'viewer:template': 'map-focus',
    });

    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final dayThreeChip = tester.widget<InkWell>(
      find.byKey(const ValueKey('viewer-map-day-3')),
    );
    dayThreeChip.onTap!();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.byKey(const ValueKey('viewer-template-map-hero')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('viewer-map-route-day-3')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('viewer-map-route-day-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('viewer-map-route-day-2')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('draggable-it3')), findsOneWidget);
    expect(find.byKey(const ValueKey('draggable-it1')), findsNothing);
    expect(find.byKey(const ValueKey('draggable-it2')), findsNothing);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('hamburger menüsü Keşfet ve Hesap bölümleriyle kaydırma sunar',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      kPremiumPrefsKey: false,
      'viewer:template': 'journey-progress',
    });
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    // "YOLCULUK" etiketi kaldırıldı: özet kartı en üstte, başlıksız duruyor.
    expect(find.text('YOLCULUK'), findsNothing);
    expect(find.text('KEŞFET'), findsOneWidget);
    expect(find.text('ARAÇLAR'), findsNothing);
    expect(find.text('HESAP'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.byIcon(Icons.map_outlined), findsWidgets);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('drawer-discover-group')),
        matching: find.byIcon(Icons.palette_outlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('drawer-account-actions')),
        matching: find.byIcon(Icons.palette_outlined),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('drawer-travel-essentials')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('drawer-scanner-hero')), findsOneWidget);
    expect(find.text('Premium'), findsWidgets);
    expect(find.byKey(const ValueKey('drawer-action-Rotori Eats')),
        findsOneWidget);
  });

  testWidgets('uçuş satırı boş şehir+havaalanı ile "—" gösterir',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
          FlightLeg(
              city: 'Tokyo', airport: 'HND', dateTime: '${d(0)}T20:00:00'),
          FlightLeg(
              city: 'İstanbul', airport: 'IST', dateTime: '${d(1)}T06:00:00'),
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

    final flightIcon = find.byIcon(Icons.flight_takeoff);
    expect(flightIcon, findsOneWidget);
    expect(tester.widget<Icon>(flightIcon).size, 16);
    final flightIconContainer = find
        .ancestor(of: flightIcon, matching: find.byType(Container))
        .first;
    expect(tester.getSize(flightIconContainer), const Size(30, 30));

    await tester.tap(find.byIcon(Icons.flight_takeoff));
    await tester.pumpAndSettle();

    // Boş bacak "—" olarak render olmalı (_DrawerFlightsMini._iata)
    expect(find.text('—'), findsWidgets);
    // Dolu bacak korunmalı — IATA "HND" görünür (city yerine airport tercih).
    expect(find.textContaining('HND'), findsWidgets);
    // Referans uçuş kompozisyonunun başlık ve süre katmanı da görünür.
    expect(find.text('GEZİ 1'), findsOneWidget);
    expect(find.text('8sa 00dk'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('drawer-flight-day-offset')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
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

    testWidgets('edit modunda durak kilitlenip kilidi açılabilir',
        (tester) async {
      final trip = _sampleTrip();
      final target = trip.days
          .expand((d) => d.items)
          .firstWhere((i) => i.canUserToggleLock && !i.isFixed);

      await tester.pumpWidget(harness(trip));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pump(const Duration(milliseconds: 100));

      // Kilitsiz durakta "kilitle" aksiyonu var, "kilidi aç" yok.
      final pin = find.byKey(ValueKey('pin-${target.id}'));
      expect(pin, findsOneWidget);
      expect(find.byKey(ValueKey('unpin-${target.id}')), findsNothing);

      await tester.ensureVisible(pin);
      await tester.pumpAndSettle();
      await tester.tap(pin);
      await tester.pumpAndSettle();

      // Kilitlendi: rozet taraf değiştirdi ve onay mesajı çıktı.
      expect(find.text(tr('viewer.edit.pinned')), findsOneWidget);
      expect(find.byKey(ValueKey('unpin-${target.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('pin-${target.id}')), findsNothing);
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
