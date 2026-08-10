// PreDepartureChecklist domain model birim testleri.
//
// Kapsam:
//   - toggle / addCustom / removeCustom / withDaysBefore ile yeni state üretimi
//     ve counter/allDone hesapları
//   - preset + stored birleştirme sırası ve override
//   - shouldShowBanner + daysUntil hesapları (deterministik `now`)
//   - PrepItem.customFromLabel — stabil id + emoji varsayılan
//   - PrepItem.fromJson / toJson round-trip

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/pre_departure_checklist.dart';

void main() {
  group('PrepItem', () {
    test('customFromLabel: stabil id ve varsayılan emoji üretir', () {
      final a = PrepItem.customFromLabel('Yelpaze', emoji: '');
      final b = PrepItem.customFromLabel('Yelpaze');
      expect(a.id, b.id);
      expect(a.custom, isTrue);
      expect(a.emoji, '📌');
      expect(a.labelTr, 'Yelpaze');
      expect(a.labelEn, 'Yelpaze');
    });

    test('toJson / fromJson round-trip', () {
      final item = PrepItem.customFromLabel('Kindle', emoji: '📚')
          .copyWith(checked: true);
      final j = item.toJson();
      final back = PrepItem.fromJson(j);
      expect(back.id, item.id);
      expect(back.emoji, '📚');
      expect(back.labelTr, 'Kindle');
      expect(back.labelEn, 'Kindle');
      expect(back.checked, isTrue);
      expect(back.custom, isTrue);
    });
  });

  group('PreDepartureChecklist.merged', () {
    test('preset sırası korunur, stored checked override uygulanır', () {
      final stored = [
        const PrepItem(id: 'passport', emoji: '📄', checked: true),
        PrepItem.customFromLabel('Kablo'),
      ];
      final st = PreDepartureChecklist.merged(
        tripId: 't1',
        presetTemplates: kPreDeparturePresets,
        stored: stored,
      );
      // Preset sıralaması ilk preset ile başlamalı
      expect(st.items.first.id, kPreDeparturePresets.first.id);
      // Passport checked=true olarak override edilmeli
      expect(
        st.items.firstWhere((i) => i.id == 'passport').checked,
        isTrue,
      );
      // Custom madde sona eklenmeli
      expect(st.items.last.custom, isTrue);
      expect(st.items.last.labelTr, 'Kablo');
      // Toplam: preset + 1 custom
      expect(st.totalCount, kPreDeparturePresets.length + 1);
    });

    test('bilinmeyen preset override id\'leri atlanır', () {
      final stored = [
        const PrepItem(id: 'eskiKaldırıldı', emoji: '?', checked: true),
      ];
      final st = PreDepartureChecklist.merged(
        tripId: 't1',
        presetTemplates: kPreDeparturePresets,
        stored: stored,
      );
      expect(st.totalCount, kPreDeparturePresets.length);
      expect(st.items.any((i) => i.id == 'eskiKaldırıldı'), isFalse);
    });

    test('daysBefore 1..30 aralığına clamp\'lenir', () {
      final a = PreDepartureChecklist.merged(
        tripId: 't1',
        presetTemplates: kPreDeparturePresets,
        stored: const [],
        daysBefore: 999,
      );
      expect(a.daysBefore, 30);
      final b = PreDepartureChecklist.merged(
        tripId: 't1',
        presetTemplates: kPreDeparturePresets,
        stored: const [],
        daysBefore: 0,
      );
      expect(b.daysBefore, 1);
    });
  });

  group('mutasyonlar', () {
    late PreDepartureChecklist st;
    setUp(() {
      st = PreDepartureChecklist.merged(
        tripId: 't1',
        presetTemplates: kPreDeparturePresets,
        stored: const [],
      );
    });

    test('toggle bilinen id\'yi işaretler ve geri alır', () {
      final on = st.toggle('passport');
      expect(on.items.firstWhere((i) => i.id == 'passport').checked, isTrue);
      final off = on.toggle('passport');
      expect(off.items.firstWhere((i) => i.id == 'passport').checked, isFalse);
    });

    test('toggle bilinmeyen id sessizce döner', () {
      final same = st.toggle('doesNotExist');
      expect(identical(same, st), isTrue);
    });

    test('addCustom yeni özel madde ekler', () {
      final next = st.addCustom(PrepItem.customFromLabel('Yelpaze'));
      expect(next.totalCount, st.totalCount + 1);
      expect(next.items.last.labelTr, 'Yelpaze');
    });

    test('addCustom aynı id\'yi ikinci kez eklemez', () {
      final one = st.addCustom(PrepItem.customFromLabel('Yelpaze'));
      final two = one.addCustom(PrepItem.customFromLabel('Yelpaze'));
      expect(two.totalCount, one.totalCount);
    });

    test('addCustom custom=false PrepItem\'ı reddeder', () {
      expect(
        () => st.addCustom(const PrepItem(id: 'x', emoji: '?')),
        throwsArgumentError,
      );
    });

    test('removeCustom yalnızca custom maddeyi siler', () {
      final withCustom = st.addCustom(PrepItem.customFromLabel('Kindle'));
      final id = withCustom.items.last.id;
      final removed = withCustom.removeCustom(id);
      expect(removed.totalCount, st.totalCount);

      // Preset silinemez
      final untouched = removed.removeCustom('passport');
      expect(identical(untouched, removed), isTrue);
    });

    test('storableItems yalnızca checked + custom içerir', () {
      final s2 = st
          .toggle('passport')
          .addCustom(PrepItem.customFromLabel('Kablo'));
      final storable = s2.storableItems();
      expect(storable, hasLength(2)); // 1 checked preset + 1 custom
      expect(storable.any((i) => i.id == 'passport'), isTrue);
      expect(storable.any((i) => i.custom), isTrue);
    });

    test('doneCount / allDone', () {
      expect(st.doneCount, 0);
      expect(st.allDone, isFalse);
      var all = st;
      for (final it in kPreDeparturePresets) {
        all = all.toggle(it.id);
      }
      expect(all.doneCount, kPreDeparturePresets.length);
      expect(all.allDone, isTrue);
    });
  });

  group('countdown / banner', () {
    final now = DateTime(2026, 9, 1);

    PreDepartureChecklist mk(int daysBefore) =>
        PreDepartureChecklist.merged(
          tripId: 't1',
          presetTemplates: kPreDeparturePresets,
          stored: const [],
          daysBefore: daysBefore,
        );

    test('daysUntil: gelecek tarih için pozitif, geçmiş için 0', () {
      expect(
        PreDepartureChecklist.daysUntil('2026-09-08', now: now),
        7,
      );
      expect(
        PreDepartureChecklist.daysUntil('2026-08-25', now: now),
        0,
      );
      expect(
        PreDepartureChecklist.daysUntil('bozuk', now: now),
        isNull,
      );
    });

    test('shouldShowBanner: eşiğe ulaşınca true', () {
      final st = mk(7);
      expect(st.shouldShowBanner('2026-09-10', now: now), isFalse); // 9 gün
      expect(st.shouldShowBanner('2026-09-08', now: now), isTrue); // 7 gün
      expect(st.shouldShowBanner('2026-09-01', now: now), isTrue); // bugün
      expect(st.shouldShowBanner('2026-08-25', now: now), isTrue); // geçmişte
    });

    test('shouldShowBanner: özel daysBefore=1 dar aralık', () {
      final st = mk(1);
      expect(st.shouldShowBanner('2026-09-03', now: now), isFalse);
      expect(st.shouldShowBanner('2026-09-02', now: now), isTrue);
    });
  });
}
