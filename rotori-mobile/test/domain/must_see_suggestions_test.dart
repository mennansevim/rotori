// "Bunları da gör" — öneri listesi + BOZMADAN yerleştirme sözleşmesi.

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/itinerary_generator.dart'
    show kDayEndMinutes, kDayStartMinutes;
import 'package:rotori/domain/destination_profiles.dart'
    show getDestinationForDate;
import 'package:rotori/domain/must_see_suggestions.dart';
import 'package:rotori/domain/plan_generation.dart';
import 'package:rotori/domain/trip_factory.dart';
import 'package:rotori/domain/types.dart';

Trip _tokyoKyotoTrip() => buildTripFromCities(
      cityKeys: const ['tokyo', 'kyoto'],
      startYmd: '2026-10-15',
      endYmd: '2026-10-24',
    );

int _min(String t) {
  final p = t.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

void main() {
  group('missingHighlights', () {
    test('yalnızca planın şehirlerinden önerir', () {
      final trip = _tokyoKyotoTrip();
      final out = missingHighlights(trip);
      expect(out, isNotEmpty);
      for (final p in out) {
        expect(['Tokyo', 'Kyoto'], contains(p.city),
            reason: '${p.name} (${p.city}) plan şehirlerinde değil');
      }
    });

    test('plana zaten girmiş yerleri önermez', () {
      final trip = _tokyoKyotoTrip();
      final inPlan = trip.days
          .expand((d) => d.items)
          .map((i) => i.title.toLowerCase())
          .toList();
      for (final p in missingHighlights(trip)) {
        expect(inPlan.any((t) => t.contains(p.name.toLowerCase())), isFalse,
            reason: '${p.name} zaten planda ama öneriliyor');
      }
    });

    test('destinasyonu olmayan planda boş döner', () {
      final trip = createEmptyTrip()..preferences.destinations.clear();
      expect(missingHighlights(trip), isEmpty);
    });

    test('liste kararlı — aynı plan için aynı sıra', () {
      final trip = _tokyoKyotoTrip();
      final a = missingHighlights(trip).map((p) => p.id).toList();
      final b = missingHighlights(trip).map((p) => p.id).toList();
      expect(a, b);
    });

    test('limit uygulanır', () {
      final trip = _tokyoKyotoTrip();
      expect(missingHighlights(trip, limit: 3).length, lessThanOrEqualTo(3));
    });
  });

  group('addHighlightsToPlan — mevcut planı BOZMAZ', () {
    test('eklemeden önceki öğelerin hiçbiri kaybolmaz ya da saati değişmez',
        () {
      final trip = _tokyoKyotoTrip();
      // Öncesini "parmak izi" olarak al: id → saat.
      final before = <String, String?>{
        for (final d in trip.days)
          for (final i in d.items) i.id: i.time ?? i.scheduledTime,
      };

      final picks = missingHighlights(trip, limit: 3);
      addHighlightsToPlan(trip, picks);

      final after = <String, String?>{
        for (final d in trip.days)
          for (final i in d.items) i.id: i.time ?? i.scheduledTime,
      };

      for (final e in before.entries) {
        expect(after.containsKey(e.key), isTrue,
            reason: '${e.key} plandan silinmiş');
        expect(after[e.key], e.value,
            reason: '${e.key} saati değişmiş: ${e.value} → ${after[e.key]}');
      }
    });

    test('kullanıcının elle değiştirdiği saat korunur', () {
      final trip = _tokyoKyotoTrip();
      // 2. günün ilk öğesini kullanıcı elle 08:15'e almış gibi davran.
      final day = trip.days[1];
      final edited = day.items.first..time = '08:15';
      edited.scheduledTime = '08:15';

      addHighlightsToPlan(trip, missingHighlights(trip, limit: 2));

      expect(day.items.firstWhere((i) => i.id == edited.id).time, '08:15');
    });
  });

  group('addHighlightsToPlan — yerleştirme kuralları', () {
    test('eklenen öğe 09:00-20:00 penceresine uyar', () {
      final trip = _tokyoKyotoTrip();
      final picks = missingHighlights(trip, limit: 4);
      final res = addHighlightsToPlan(trip, picks);

      for (final name in res.placed.keys) {
        final item = trip.days
            .expand((d) => d.items)
            .firstWhere((i) => i.title.contains(name));
        final start = _min(item.time!);
        expect(start, greaterThanOrEqualTo(kDayStartMinutes));
        expect(start + (item.durationMin ?? 90),
            lessThanOrEqualTo(kDayEndMinutes),
            reason: '$name 20:00\'yi aşıyor');
      }
    });

    test('eklenen öğe mevcut öğelerle çakışmaz', () {
      final trip = _tokyoKyotoTrip();
      final res = addHighlightsToPlan(trip, missingHighlights(trip, limit: 4));
      expect(res.placed, isNotEmpty);

      // Yalnızca DEĞİŞTİRDİĞİMİZ günleri denetle. Varış/dönüş günündeki
      // uçuş+transfer kalemleri üreticiden geliyor ve süreleri burada
      // bilinmiyor (transport 90 dk değil) — onları bu test kapsamaz.
      final touched = res.placed.values.toSet();
      for (final day in trip.days.where((d) => touched.contains(d.dayNumber))) {
        final timed = day.items
            .where((i) => (i.time ?? i.scheduledTime)?.contains(':') ?? false)
            .toList()
          ..sort((a, b) => _min(a.time ?? a.scheduledTime!)
              .compareTo(_min(b.time ?? b.scheduledTime!)));
        for (var i = 0; i + 1 < timed.length; i++) {
          final endPrev = _min(timed[i].time ?? timed[i].scheduledTime!) +
              (timed[i].durationMin ??
                  (timed[i].kind == TimelineItemKind.meal ? 45 : 90));
          final startNext = _min(timed[i + 1].time ?? timed[i + 1].scheduledTime!);
          expect(startNext, greaterThanOrEqualTo(endPrev),
              reason: 'G${day.dayNumber}: "${timed[i].title}" ile '
                  '"${timed[i + 1].title}" çakışıyor');
        }
      }
    });

    test('yer kendi şehrinin gününe konur', () {
      final trip = _tokyoKyotoTrip();
      final picks = missingHighlights(trip, limit: 5);
      final res = addHighlightsToPlan(trip, picks);

      final dests = trip.preferences.destinations;
      for (final entry in res.placed.entries) {
        final day = trip.days.firstWhere((d) => d.dayNumber == entry.value);
        final dest = getDestinationForDate(dests, day.date);
        final place = picks.firstWhere((p) => p.name == entry.key);
        expect(dest?.city, place.city,
            reason: '${place.name} (${place.city}) '
                '${dest?.city} gününe konmuş');
      }
    });

    test('eklenen öğe koordinat ve harita bağlantısı taşır', () {
      // Koordinatsız öğe haritada görünmez ve rota optimizasyonu onu
      // "konumu yok" diye eler — sessiz veri kaybı olur.
      final trip = _tokyoKyotoTrip();
      final res = addHighlightsToPlan(trip, missingHighlights(trip, limit: 5));
      expect(res.placed, isNotEmpty);

      for (final name in res.placed.keys) {
        final item = trip.days
            .expand((d) => d.items)
            .firstWhere((i) => i.title.contains(name));
        expect(item.mapUrl, isNotNull, reason: '$name harita bağlantısı yok');
        expect(item.lat, isNotNull, reason: '$name koordinatsız eklendi');
        expect(item.lng, isNotNull, reason: '$name koordinatsız eklendi');
      }
    });

    test('saatli giriş eklenirse kilitli gelir', () {
      // teamLab/Disney gibi bir yer bu yoldan eklenirse de bileti korunmalı.
      final trip = _tokyoKyotoTrip();
      // Planda zaten varsa öneri listesine düşmez; kaldırıp yeniden ekletelim.
      for (final d in trip.days) {
        d.items.removeWhere((i) => i.title.toLowerCase().contains('teamlab'));
      }
      final teamlab = missingHighlights(trip, limit: 30)
          .where((p) => p.name.toLowerCase().contains('teamlab'))
          .toList();
      if (teamlab.isEmpty) return; // havuzda yoksa bu iddia uygulanmaz

      final res = addHighlightsToPlan(trip, teamlab);
      if (res.placed.isEmpty) return; // gün doluysa yerleştirme beklenmez

      final item = trip.days
          .expand((d) => d.items)
          .firstWhere((i) => i.title.toLowerCase().contains('teamlab'));
      expect(item.lockType, ActivityLockType.ticketedEvent);
      expect(item.canChangeTime, isFalse);
    });

    test('eklenenler mustSee tercihine yazılır', () {
      final trip = _tokyoKyotoTrip();
      final res = addHighlightsToPlan(trip, missingHighlights(trip, limit: 3));
      for (final name in res.placed.keys) {
        expect(trip.preferences.mustSee, contains(name));
      }
    });

    test('sığmayan yer sessizce yutulmaz — unplaced içinde döner', () {
      final trip = _tokyoKyotoTrip();
      // Tüm günleri tıka basa doldur: 09:00-20:00 tek blok.
      for (final d in trip.days) {
        d.items
          ..clear()
          ..add(TimelineItem(
            id: 'full-${d.dayNumber}',
            title: 'Dolu gün',
            time: '09:00',
            scheduledTime: '09:00',
            durationMin: 11 * 60,
            kind: TimelineItemKind.activity,
          ));
      }
      final res = addHighlightsToPlan(trip, missingHighlights(trip, limit: 3));
      expect(res.placed, isEmpty);
      expect(res.unplaced, isNotEmpty);
      expect(res.allPlaced, isFalse);
    });

    test('boş seçimde plan değişmez', () {
      final trip = _tokyoKyotoTrip();
      final countBefore = trip.days.fold<int>(0, (n, d) => n + d.items.length);
      final res = addHighlightsToPlan(trip, const []);
      expect(res.placed, isEmpty);
      expect(res.unplaced, isEmpty);
      expect(res.allPlaced, isTrue);
      expect(trip.days.fold<int>(0, (n, d) => n + d.items.length), countBefore);
    });
  });
}
