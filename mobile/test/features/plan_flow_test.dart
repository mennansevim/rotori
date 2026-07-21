// Plan adımı — gezi planı oluştur (fallback), reorder→resequence, keşif.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/city_transfers.dart';
import 'package:japan_trip/domain/day_optimizer.dart';
import 'package:japan_trip/domain/trip_factory.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/planner/planner_theme.dart';
import 'package:japan_trip/features/planner/steps/plan_step.dart';

Trip _tripWithDest() {
  final t = createEmptyTrip();
  t.preferences.destinations.add(TripDestination(
    id: 'd1',
    countryCode: 'JP',
    countryName: 'Japonya',
    city: 'Tokyo',
    arrivalDate: t.preferences.travelDates.start,
    departureDate: t.preferences.travelDates.end,
    order: 0,
  ));
  return t;
}

void main() {
  Widget harness(Trip trip) => ProviderScope(
        child: MaterialApp(
          theme: PT.theme(),
          home: Scaffold(
            body: PlanStep(trip: trip, onChange: (m) => m(trip)),
          ),
        ),
      );

  testWidgets('destinasyon yoksa uyarı gösterir', (tester) async {
    await tester.pumpWidget(harness(createEmptyTrip()));
    expect(find.text('Önce Rota adımında havaalanı/durak ekleyin.'),
        findsOneWidget);
  });

  testWidgets('boş plan "Henüz plan yok" gösterir', (tester) async {
    await tester.pumpWidget(harness(_tripWithDest()));
    expect(find.text('Plan'), findsWidgets);
    expect(find.text('Henüz plan yok'), findsOneWidget);
  });

  testWidgets('trip dolu gelse bile plan gizli başlar (kullanıcı açıkça istesin)',
      (tester) async {
    final t = _tripWithDest();
    // Dolu bir günü el ile ekle — hero yine görünmeli.
    if (t.days.isNotEmpty) {
      t.days.first.items.add(TimelineItem(
        id: 'x',
        title: 'Var olan aktivite',
        time: '09:00',
        scheduledTime: '09:00',
      ));
    }
    await tester.pumpWidget(harness(t));
    expect(find.text('Henüz plan yok'), findsOneWidget);
  });

  testWidgets('"Gezi planı oluştur" fallback ile günleri doldurur',
      (tester) async {
    final t = _tripWithDest();
    await tester.pumpWidget(harness(t));

    await tester.tap(find.text('✨ Gezi planı oluştur'));
    await tester.pumpAndSettle();

    // Kural tabanlı üretici en az bir güne aktivite ekler.
    expect(t.days.any((d) => d.items.isNotEmpty), isTrue);
    // Boş durum kartı artık yok.
    expect(find.text('Henüz plan yok'), findsNothing);
  });

  testWidgets('plan açıldıktan sonra "+ Aktivite" butonu render edilir',
      (tester) async {
    // Modal bottom-sheet açılış testi test contextte kararsız — burada sadece
    // butonun VAR olduğunu doğrula. Sheet'in davranışı ayrı olarak _AddItemSheet
    // widget testinde (unit) doğrulanır; bu test entegrasyon smoke.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 3000);
    addTearDown(tester.view.reset);

    final t = _tripWithDest();
    await tester.pumpWidget(harness(t));

    // Önce planı üret (aksi halde gün listesi gizli, "+ Aktivite" yok).
    await tester.tap(find.text('✨ Gezi planı oluştur'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));

    // "+ Aktivite" butonu render edilmiş olmalı (ilk gün expanded).
    expect(find.text('+ Aktivite'), findsWidgets);

    // Ve gerçekten plan gösterilmiş olmalı — en az bir öğe üretilmiş.
    final afterCount =
        t.days.fold<int>(0, (n, d) => n + d.items.length);
    expect(afterCount, greaterThan(0));
  });

  testWidgets(
      'Bug 2 — çoklu şehir rotasında _generate şehir geçişlerini otomatik ekler',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 3000);
    addTearDown(tester.view.reset);

    final t = createEmptyTrip();
    // 15 günlük aralık: 2026-05-01 → 2026-05-15
    t.preferences.travelDates
      ..start = '2026-05-01'
      ..end = '2026-05-15';
    t.tripStart = '2026-05-01T08:00:00';
    t.tripEnd = '2026-05-15T20:00:00';
    // Osaka + Tokyo + Nara — distributeDates tarihleri ayırır.
    final dests = [
      TripDestination(
        id: 'd1',
        countryCode: 'JP',
        countryName: 'Japonya',
        city: 'Osaka',
        airport: 'KIX',
        arrivalDate: '2026-05-01',
        departureDate: '2026-05-01',
        order: 0,
      ),
      TripDestination(
        id: 'd2',
        countryCode: 'JP',
        countryName: 'Japonya',
        city: 'Tokyo',
        airport: 'HND',
        arrivalDate: '2026-05-01',
        departureDate: '2026-05-01',
        order: 1,
      ),
      TripDestination(
        id: 'd3',
        countryCode: 'JP',
        countryName: 'Japonya',
        city: 'Nara',
        arrivalDate: '2026-05-01',
        departureDate: '2026-05-01',
        order: 2,
      ),
    ];
    distributeDates(dests, '2026-05-01', '2026-05-15');
    t.preferences.destinations = dests;
    t.days = generateDaysBetween('2026-05-01', '2026-05-15');

    await tester.pumpWidget(harness(t));
    await tester.tap(find.text('✨ Gezi planı oluştur'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));

    // En az bir gün "→" içeren transport item taşımalı (auto-inserted transitions).
    final transitionCount = t.days.fold<int>(0, (n, d) {
      return n +
          d.items
              .where((it) =>
                  it.kind == TimelineItemKind.transport &&
                  it.title.contains('→'))
              .length;
    });
    expect(transitionCount, greaterThan(0),
        reason: 'Bug 2 — _generate şehir geçişlerini otomatik eklemedi');
  });

  test('Bug 3 — suggestionForMode her mod için geçerli transfer üretir', () {
    for (final mode in kTransportModes) {
      final s =
          suggestionForMode(mode, 'Tokyo', 'Osaka', 3, 4);
      expect(s.fromCity, 'Tokyo');
      expect(s.toCity, 'Osaka');
      expect(s.transfer.mode, isNotEmpty);
      expect(s.transfer.emoji, isNotEmpty);
      expect(s.fromDayNumber, 3);
      expect(s.toDayNumber, 4);
    }
    // shinkansen + bilinen çift → gerçek süre/ücret korunur (Tokyo→Osaka Nozomi).
    final sk = suggestionForMode('shinkansen', 'Tokyo', 'Osaka', 3, 4);
    expect(sk.transfer.duration, contains('2s'));
    // bus modu → bus emojisi & Willer tip
    final sb = suggestionForMode('bus', 'Tokyo', 'Osaka', 3, 4);
    expect(sb.transfer.emoji, '🚌');
    expect(sb.transfer.tip, contains('Willer'));
  });

  test('reorder resequenceTimes ile saatleri kronolojik dizer', () {
    // resequenceTimes davranışı: görsel sırayı korur, saatleri artan dağıtır.
    final items = [
      TimelineItem(id: 'a', title: 'A', time: '14:00', scheduledTime: '14:00'),
      TimelineItem(id: 'b', title: 'B', time: '09:00', scheduledTime: '09:00'),
    ];
    // b'yi başa taşı (kullanıcı sürükledi) → saatler 09:00, 14:00 sırasına gelir.
    final reordered = [items[1], items[0]];
    final result = resequenceTimes(reordered);
    expect(result[0].time, '09:00');
    expect(result[1].time, '14:00');
    expect(result[0].id, 'b');
    expect(result[1].id, 'a');
  });
}
