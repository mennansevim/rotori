// Saatli giriş kilidi — teamLab / Disneyland / USJ rota optimizasyonunda
// OYNATILMAZ. Bileti belirli bir saate kesildiği için saati değişirse
// kullanıcının bileti geçersiz olur.

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/day_optimizer.dart';
import 'package:rotori/domain/japan_suggestions.dart';
import 'package:rotori/domain/plan_generation.dart';
import 'package:rotori/domain/types.dart';

TimelineItem _item(
  String id,
  String title,
  String time, {
  double? lat,
  double? lng,
  TimelineItemKind kind = TimelineItemKind.activity,
}) =>
    TimelineItem(
      id: id,
      title: title,
      time: time,
      scheduledTime: time,
      kind: kind,
      lat: lat,
      lng: lng,
    );

void main() {
  group('isTimedEntryTitle', () {
    test('saatli giriş yerlerini tanır', () {
      expect(isTimedEntryTitle('🪐 teamLab Planets'), isTrue);
      expect(isTimedEntryTitle('team Lab Borderless'), isTrue);
      expect(isTimedEntryTitle('🏰 Tokyo Disneyland'), isTrue);
      expect(isTimedEntryTitle('Tokyo DisneySea'), isTrue);
      expect(isTimedEntryTitle('🎢 Universal Studios Japan'), isTrue);
      expect(isTimedEntryTitle('USJ Express Pass'), isTrue);
    });

    test('sıradan yerleri kilitlemez', () {
      expect(isTimedEntryTitle('⛩️ Senso-ji Asakusa'), isFalse);
      expect(isTimedEntryTitle('🗼 Tokyo Skytree'), isFalse);
      expect(isTimedEntryTitle('🍣 Kuromon Market'), isFalse);
    });
  });

  group('isTimeLocked', () {
    test('başlıktan türetir — kilit alanı boş eski planlar da korunur', () {
      final old = _item('a', '🪐 teamLab Planets', '13:00');
      expect(old.isFixed, isFalse, reason: 'eski kayıtta kilit alanı yok');
      expect(isTimeLocked(old), isTrue, reason: 'başlıktan türetilmeliydi');
    });

    test('kullanıcının elle kilitlediği öğe de kilitli sayılır', () {
      final pinned = _item('b', '⛩️ Senso-ji', '09:00')..canChangeTime = false;
      expect(isTimeLocked(pinned), isTrue);
    });

    test('serbest öğe kilitli değil', () {
      expect(isTimeLocked(_item('c', '⛩️ Senso-ji', '09:00')), isFalse);
    });
  });

  group('optimizeDayItems saatli girişi oynatmaz', () {
    test('teamLab saati optimizasyondan sonra da aynı kalır', () {
      // Koordinatlar teamLab'ı coğrafi olarak "ilk sıraya" çekecek şekilde
      // seçildi — kilit olmasaydı sabaha alınırdı.
      final items = [
        _item('a', '⛩️ Senso-ji Asakusa', '09:00', lat: 35.7148, lng: 139.7967),
        _item('b', '🪐 teamLab Planets', '15:00', lat: 35.6486, lng: 139.7900),
        _item('c', '🗼 Tokyo Skytree', '11:00', lat: 35.7101, lng: 139.8107),
      ];

      final out = optimizeDayItems(items);
      final teamlab = out.firstWhere((i) => i.title.contains('teamLab'));
      expect(teamlab.time, '15:00',
          reason: 'saatli giriş oynatıldı — bilet geçersiz olurdu');
      expect(teamlab.scheduledTime, '15:00');
    });

    test('Disneyland günü optimizasyonda saatini korur', () {
      final items = [
        _item('a', '🏰 Tokyo Disneyland', '09:00', lat: 35.6329, lng: 139.8804),
        _item('b', '🍜 Akşam yemeği', '19:00',
            lat: 35.6300, lng: 139.8800, kind: TimelineItemKind.meal),
      ];
      final out = optimizeDayItems(items);
      expect(out.firstWhere((i) => i.title.contains('Disney')).time, '09:00');
    });

    test('kilitsiz öğeler hâlâ yeniden dizilebiliyor', () {
      // Kilit eklemek optimizasyonu tamamen dondurmamalı.
      final items = [
        _item('a', '⛩️ Güney tapınak', '09:00', lat: 35.60, lng: 139.70),
        _item('b', '🌳 Kuzey park', '11:00', lat: 35.80, lng: 139.70),
        _item('c', '📸 Orta nokta', '14:00', lat: 35.70, lng: 139.70),
      ];
      final out = optimizeDayItems(items);
      // En kuzeyden başlar → sıra değişmeli.
      expect(out.first.title, contains('Kuzey'));
    });
  });

  group('üretici saatli girişi kilitli işaretler', () {
    test('yeni planda teamLab/Disney ticketedEvent olur', () {
      final trip = buildTripFromCities(
        cityKeys: const ['tokyo'],
        startYmd: '2026-10-15',
        endYmd: '2026-10-24',
      );
      final timed = trip.days
          .expand((d) => d.items)
          .where((i) => isTimedEntryTitle(i.title))
          .toList();

      expect(timed, isNotEmpty,
          reason: 'Tokyo planında teamLab ya da Disney bekleniyordu');
      for (final i in timed) {
        expect(i.lockType, ActivityLockType.ticketedEvent,
            reason: '${i.title} kilitlenmemiş');
        expect(i.canChangeTime, isFalse);
        expect(i.isFixed, isTrue);
      }
    });

    test('sıradan aktiviteler serbest kalır', () {
      final trip = buildTripFromCities(
        cityKeys: const ['kyoto'],
        startYmd: '2026-10-15',
        endYmd: '2026-10-20',
      );
      final normal = trip.days
          .expand((d) => d.items)
          .where((i) =>
              i.kind == TimelineItemKind.activity &&
              i.lockType == ActivityLockType.none &&
              !isTimedEntryTitle(i.title))
          .toList();
      expect(normal, isNotEmpty);
      expect(normal.every((i) => i.canChangeTime), isTrue);
    });
  });
}
