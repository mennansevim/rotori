// packages/shared/src/__tests__/cityTransfers.test.ts'in birebir Dart eşdeğeri.

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/city_transfers.dart';
import 'package:rotori/domain/day_optimizer.dart';
import 'package:rotori/domain/types.dart';

DayPlan _day({
  int dayNumber = 1,
  String date = '2026-10-01',
  List<TimelineItem>? items,
}) =>
    DayPlan(
      dayNumber: dayNumber,
      date: date,
      theme: '',
      tags: [],
      items: items ?? [],
    );

TripDestination _dest({
  String id = 'd1',
  String city = 'Tokyo',
  String arrivalDate = '2026-10-01',
  String departureDate = '2026-10-10',
  int order = 0,
}) =>
    TripDestination(
      id: id,
      countryCode: 'JP',
      countryName: 'Japonya',
      city: city,
      arrivalDate: arrivalDate,
      departureDate: departureDate,
      order: order,
    );

void main() {
  group('lookupTransfer', () {
    test('bilinen Tokyo→Osaka çiftini bulur', () {
      final t = lookupTransfer('Tokyo', 'Osaka');
      expect(t?.mode, contains('Shinkansen'));
      expect(t?.duration, matches(RegExp(r'2s')));
    });

    test('ters yönü de döndürür', () {
      expect(lookupTransfer('Osaka', 'Tokyo')?.mode, contains('Shinkansen'));
    });

    test('parantezli şehir isimlerini normalize eder', () {
      expect(
        lookupTransfer('Tokyo (Haneda)', 'Kyoto')?.mode,
        contains('Shinkansen'),
      );
    });

    test('bilinmeyen çift için null', () {
      expect(lookupTransfer('Tokyo', 'Pluto'), isNull);
    });
  });

  group('detectCityTransitions', () {
    test('item.cityId üzerinden geçişi bulur', () {
      final days = [
        _day(
          dayNumber: 1,
          items: [
            TimelineItem(
              id: 'i1',
              title: 'Senso-ji',
              cityId: 'Tokyo',
              kind: TimelineItemKind.activity,
            ),
          ],
        ),
        _day(
          dayNumber: 2,
          date: '2026-10-02',
          items: [
            TimelineItem(
              id: 'i2',
              title: 'Dotonbori',
              cityId: 'Osaka',
              kind: TimelineItemKind.activity,
            ),
          ],
        ),
      ];
      final transitions = detectCityTransitions(days, []);
      expect(transitions, hasLength(1));
      expect(transitions[0].fromCity, 'Tokyo');
      expect(transitions[0].toCity, 'Osaka');
      expect(transitions[0].toDayNumber, 2);
    });

    test('aynı şehirdeki ardışık günlerde transition yok', () {
      final days = [
        _day(
          dayNumber: 1,
          items: [TimelineItem(id: 'i1', title: 'A', cityId: 'Tokyo')],
        ),
        _day(
          dayNumber: 2,
          items: [TimelineItem(id: 'i2', title: 'B', cityId: 'Tokyo')],
        ),
      ];
      expect(detectCityTransitions(days, []), isEmpty);
    });

    test('destinasyondan fallback eder (cityId yoksa)', () {
      final days = [
        _day(dayNumber: 1, date: '2026-10-01'),
        _day(dayNumber: 2, date: '2026-10-05'),
      ];
      final dests = [
        _dest(
          id: 'd1',
          city: 'Tokyo',
          arrivalDate: '2026-10-01',
          departureDate: '2026-10-03',
        ),
        _dest(
          id: 'd2',
          city: 'Osaka',
          arrivalDate: '2026-10-04',
          departureDate: '2026-10-07',
          order: 1,
        ),
      ];
      final transitions = detectCityTransitions(days, dests);
      expect(transitions.first.fromCity, 'Tokyo');
      expect(transitions.first.toCity, 'Osaka');
    });
  });

  group('insertCityTransfer — saat dağıtımı', () {
    test('transfer 09:00 kalkar, sonraki aktiviteler varış sonrasına dağıtılır', () {
      final days = [
        _day(dayNumber: 2, date: '2026-10-04', items: [
          TimelineItem(id: 'a', title: 'X', kind: TimelineItemKind.activity, time: '09:00'),
          TimelineItem(id: 'b', title: 'Y', kind: TimelineItemKind.activity, time: '11:00'),
        ]),
      ];
      final sug = suggestionForMode('shinkansen', 'Tokyo', 'Kyoto', 1, 2);
      final out = insertCityTransfer(days, 2, sug);
      final items = out.first.items;
      // İlk öğe transfer (transport, → içerir) ve 09:00.
      expect(items.first.kind, TimelineItemKind.transport);
      expect(items.first.title, contains('→'));
      expect(items.first.time, '09:00');
      // Aktiviteler transferden (ve varıştan) sonra, artan sırada.
      expect(timeToMin(items[1].time!), greaterThan(timeToMin('09:00')));
      expect(timeToMin(items[2].time!), greaterThan(timeToMin(items[1].time!)));
    });

    test('applyCityTransitions çoklu şehir günlerine transfer ekler', () {
      final days = [
        _day(dayNumber: 1, date: '2026-10-01', items: [
          TimelineItem(id: 'i1', title: 'Senso-ji', cityId: 'Tokyo'),
        ]),
        _day(dayNumber: 2, date: '2026-10-02', items: [
          TimelineItem(id: 'i2', title: 'Fushimi Inari', cityId: 'Kyoto'),
        ]),
      ];
      final out = applyCityTransitions(days, []);
      final transfers = out
          .expand((d) => d.items)
          .where((it) =>
              it.kind == TimelineItemKind.transport && it.title.contains('→'))
          .toList();
      expect(transfers, hasLength(1));
      // idempotent: ikinci kez uygulama yeni transfer eklemez.
      final again = applyCityTransitions(out, []);
      final transfers2 = again
          .expand((d) => d.items)
          .where((it) =>
              it.kind == TimelineItemKind.transport && it.title.contains('→'))
          .toList();
      expect(transfers2, hasLength(1));
    });
  });

  group('hasExistingTransferTo', () {
    test('mevcut transport item için true', () {
      final day = _day(
        items: [
          TimelineItem(
            id: 't1',
            title: '🚄 Tokyo → Osaka • Shinkansen',
            kind: TimelineItemKind.transport,
          ),
        ],
      );
      expect(hasExistingTransferTo(day, 'Osaka'), isTrue);
    });

    test('benzer activity item için false', () {
      final day = _day(
        items: [
          TimelineItem(
            id: 'a1',
            title: 'Osaka kalesi gezisi',
            kind: TimelineItemKind.activity,
          ),
        ],
      );
      expect(hasExistingTransferTo(day, 'Osaka'), isFalse);
    });
  });
}
