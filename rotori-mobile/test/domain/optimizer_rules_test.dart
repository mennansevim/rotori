// "Rotayı optimize et" KURAL İHLALİ ÜRETMEZ.
//
// Uygulamanın kendi uyarı motoru (plan_warnings) optimizasyon çıktısını
// işaretliyorsa bu bir hatadır: kullanıcı bir düğmeye basıyor ve uygulama
// ona "bu plan yanlış" diyor. Gerçekte olan buydu — optimizasyonun akşam
// yemeği penceresi 17:30'dan, uyarı motorununki 18:00'den başlıyordu.

import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/day_optimizer.dart';
import 'package:japan_trip/domain/plan_warnings.dart';
import 'package:japan_trip/domain/types.dart';

TimelineItem _item(
  String id,
  String title,
  String time, {
  TimelineItemKind kind = TimelineItemKind.activity,
  double? lat,
  double? lng,
  int? durationMin,
}) =>
    TimelineItem(
      id: id,
      title: title,
      time: time,
      scheduledTime: time,
      kind: kind,
      lat: lat,
      lng: lng,
      durationMin: durationMin,
    );

DayPlan _day(List<TimelineItem> items) => DayPlan(
      dayNumber: 2,
      date: '2026-10-16',
      theme: 'Gün',
      items: items,
    );

void main() {
  group('öğün pencereleri tek kaynaktan', () {
    test('sabitler uyarı motorunun beklediği değerler', () {
      expect(kBreakfastStartMinutes, 6 * 60);
      expect(kBreakfastEndMinutes, 11 * 60);
      expect(kLunchStartMinutes, 11 * 60);
      expect(kLunchEndMinutes, 15 * 60);
      expect(kDinnerStartMinutes, 18 * 60);
      expect(kDinnerEndMinutes, 22 * 60);
    });

    test('18:00 öncesi akşam yemeği uyarı üretir (kural gerçek)', () {
      final warnings = planWarningsFor(_day([
        _item('d', '🍜 Akşam yemeği', '17:30',
            kind: TimelineItemKind.meal, durationMin: 60),
      ]));
      expect(
        warnings.where((w) => w.kind == PlanWarningKind.mealOutsideWindow),
        isNotEmpty,
        reason: '17:30 akşam yemeği ihlal sayılmalı — testin dayanağı bu',
      );
    });
  });

  group('optimizeDayItems çıktısı temiz', () {
    test('akşam yemeği 18:00 öncesine ÇEKİLMEZ', () {
      // Kullanıcının bildirdiği durum: optimizasyon sonrası 17:30 akşam yemeği.
      final out = optimizeDayItems([
        _item('a', '⛩️ Tapınak', '09:00',
            lat: 35.71, lng: 139.79, durationMin: 90),
        _item('b', '🗼 Kule', '11:00',
            lat: 35.70, lng: 139.78, durationMin: 90),
        _item('c', '🍜 Akşam yemeği', '19:00',
            kind: TimelineItemKind.meal, lat: 35.69, lng: 139.77,
            durationMin: 60),
      ]);

      final dinner = out.firstWhere((i) => i.title.contains('Akşam'));
      final min = timeToMin(dinner.time);
      expect(min, greaterThanOrEqualTo(kDinnerStartMinutes),
          reason: 'akşam yemeği ${dinner.time} — 18:00 öncesine çekilmiş');
    });

    test('çıktı uyarı motorunu tetiklemez', () {
      for (final items in [
        [
          _item('a', '⛩️ A', '09:00', lat: 35.71, lng: 139.79, durationMin: 90),
          _item('m', '🍱 Öğle yemeği', '13:00',
              kind: TimelineItemKind.meal, lat: 35.70, lng: 139.78,
              durationMin: 60),
          _item('b', '📸 B', '15:00', lat: 35.69, lng: 139.77, durationMin: 90),
          _item('d', '🍜 Akşam yemeği', '19:00',
              kind: TimelineItemKind.meal, lat: 35.68, lng: 139.76,
              durationMin: 60),
        ],
        [
          _item('a', '🌳 A', '10:00', lat: 35.60, lng: 139.70, durationMin: 90),
          _item('d', '🍣 Akşam yemeği', '18:30',
              kind: TimelineItemKind.meal, lat: 35.61, lng: 139.71,
              durationMin: 60),
        ],
      ]) {
        final out = optimizeDayItems(items);
        final meals = planWarningsFor(_day(out))
            .where((w) => w.kind == PlanWarningKind.mealOutsideWindow)
            .map((w) => w.message)
            .toList();
        expect(meals, isEmpty,
            reason: 'optimizasyon kendi çıktısını ihlal ettirdi: $meals');
      }
    });

    test('öğle yemeği kendi penceresinde kalır', () {
      final out = optimizeDayItems([
        _item('a', '⛩️ A', '09:00', lat: 35.71, lng: 139.79, durationMin: 90),
        _item('m', '🍱 Öğle yemeği', '12:30',
            kind: TimelineItemKind.meal, lat: 35.70, lng: 139.78,
            durationMin: 60),
      ]);
      final lunch = out.firstWhere((i) => i.title.contains('Öğle'));
      final min = timeToMin(lunch.time);
      expect(min, greaterThanOrEqualTo(kLunchStartMinutes));
      expect(min, lessThan(kLunchEndMinutes));
    });

    test('saatli giriş hâlâ oynatılmıyor', () {
      // Kural bağlama işi eski garantiyi bozmamalı.
      final out = optimizeDayItems([
        _item('a', '⛩️ A', '09:00', lat: 35.71, lng: 139.79, durationMin: 90),
        _item('t', '🪐 teamLab Planets', '15:00',
            lat: 35.64, lng: 139.79, durationMin: 90),
      ]);
      expect(out.firstWhere((i) => i.title.contains('teamLab')).time, '15:00');
    });
  });
}
