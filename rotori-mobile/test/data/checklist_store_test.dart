// ChecklistNotifier birim testleri — toggle/addCustom/removeCustom/reset ve
// SharedPreferences üzerinden kalıcılık (yeniden yükleme) doğrulanır.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/data/checklist_store.dart';
import 'package:rotori/data/plans_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tripId = 'trip-checklist';

ProviderContainer _makeContainer() {
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWith(
        (ref) async => SharedPreferences.getInstance(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Notifier'ın _load()'unun bitmesini bekler (async init).
Future<ChecklistNotifier> _readLoaded(ProviderContainer c) async {
  final notifier = c.read(checklistProvider(_tripId).notifier);
  // sharedPrefsProvider.future + ilk load'un tamamlanması için pump.
  await c.read(sharedPrefsProvider.future);
  await Future<void>.delayed(Duration.zero);
  return notifier;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('toggle bir maddeyi işaretler ve tekrar kaldırır', () async {
    final c = _makeContainer();
    final notifier = await _readLoaded(c);

    expect(c.read(checklistProvider(_tripId)).checkedIds, isEmpty);

    await notifier.toggle('doc-passport');
    expect(
      c.read(checklistProvider(_tripId)).checkedIds,
      contains('doc-passport'),
    );

    await notifier.toggle('doc-passport');
    expect(
      c.read(checklistProvider(_tripId)).checkedIds,
      isNot(contains('doc-passport')),
    );
  });

  test('toggle SharedPreferences\'a yazar ve yeniden yüklenince geri gelir',
      () async {
    final c1 = _makeContainer();
    final n1 = await _readLoaded(c1);
    await n1.toggle('doc-passport');
    await n1.toggle('pay-cash-yen');

    // Aynı mock prefs üzerinden yeni container → durum geri yüklenmeli.
    final c2 = _makeContainer();
    await _readLoaded(c2);
    final reloaded = c2.read(checklistProvider(_tripId)).checkedIds;
    expect(reloaded, containsAll(['doc-passport', 'pay-cash-yen']));
  });

  test('addCustom özel madde ekler; removeCustom siler', () async {
    final c = _makeContainer();
    final notifier = await _readLoaded(c);

    await notifier.addCustom('Kültür / pratik', 'Yelpaze');
    final st = c.read(checklistProvider(_tripId));
    expect(st.customItems, hasLength(1));
    expect(st.customItems.first.label, 'Yelpaze');
    expect(st.customItems.first.category, 'Kültür / pratik');

    final id = st.customItems.first.id;
    await notifier.toggle(id);
    expect(c.read(checklistProvider(_tripId)).checkedIds, contains(id));

    await notifier.removeCustom(id);
    final after = c.read(checklistProvider(_tripId));
    expect(after.customItems, isEmpty);
    // Silinen özel maddenin işareti de temizlenmeli.
    expect(after.checkedIds, isNot(contains(id)));
  });

  test('addCustom boş etiketi yok sayar', () async {
    final c = _makeContainer();
    final notifier = await _readLoaded(c);
    await notifier.addCustom('Belgeler', '   ');
    expect(c.read(checklistProvider(_tripId)).customItems, isEmpty);
  });

  test('custom madde de yeniden yüklenince kalıcıdır', () async {
    final c1 = _makeContainer();
    final n1 = await _readLoaded(c1);
    await n1.addCustom('Elektronik', 'Kindle');

    final c2 = _makeContainer();
    await _readLoaded(c2);
    final custom = c2.read(checklistProvider(_tripId)).customItems;
    expect(custom, hasLength(1));
    expect(custom.first.label, 'Kindle');
  });

  test('reset işaretleri ve özel maddeleri temizler', () async {
    final c = _makeContainer();
    final notifier = await _readLoaded(c);
    await notifier.toggle('doc-passport');
    await notifier.addCustom('Belgeler', 'Ehliyet');

    await notifier.reset();
    final st = c.read(checklistProvider(_tripId));
    expect(st.checkedIds, isEmpty);
    expect(st.customItems, isEmpty);

    // Kalıcılaştırma da temizlenmeli.
    final c2 = _makeContainer();
    await _readLoaded(c2);
    final st2 = c2.read(checklistProvider(_tripId));
    expect(st2.checkedIds, isEmpty);
    expect(st2.customItems, isEmpty);
  });
}
