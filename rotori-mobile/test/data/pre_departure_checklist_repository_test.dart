// PreDepartureChecklistRepository birim testleri.
//
// InMemoryStorage kullanılır (Supabase client=null) — network yok, sadece
// load/save/delete + JSON round-trip + preset+stored merge sonrası state
// bütünlüğü doğrulanır.

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/data/pre_departure_checklist_repository.dart';
import 'package:rotori/domain/pre_departure_checklist.dart';

PreDepartureChecklistRepository _makeRepo() {
  return PreDepartureChecklistRepository(storage: InMemoryStorage());
}

void main() {
  test('yeni tripId için boş bir state döner (preset + hiçbir işaret yok)',
      () async {
    final repo = _makeRepo();
    final st = await repo.load('trip-a');
    expect(st.tripId, 'trip-a');
    expect(st.totalCount, kPreDeparturePresets.length);
    expect(st.doneCount, 0);
    expect(st.daysBefore, 7);
  });

  test('save + load: toggle ve custom maddeler round-trip',
      () async {
    final repo = _makeRepo();
    var st = await repo.load('trip-a');
    st = st
        .toggle('passport')
        .toggle('esim')
        .addCustom(PrepItem.customFromLabel('Kindle', emoji: '📚'));
    await repo.save(st);

    // Aynı storage üzerinden farklı repo → aynı veri
    // (aynı InMemoryStorage örneğine ihtiyaç var; bu testte repo bir tane).
    final reloaded = await repo.load('trip-a');
    expect(
      reloaded.items.firstWhere((i) => i.id == 'passport').checked,
      isTrue,
    );
    expect(
      reloaded.items.firstWhere((i) => i.id == 'esim').checked,
      isTrue,
    );
    final custom = reloaded.items.where((i) => i.custom).toList();
    expect(custom, hasLength(1));
    expect(custom.first.labelTr, 'Kindle');
    expect(custom.first.emoji, '📚');
  });

  test('save daysBefore\'ı kalıcılaştırır', () async {
    final repo = _makeRepo();
    var st = await repo.load('trip-a');
    st = st.withDaysBefore(14);
    await repo.save(st);
    final reloaded = await repo.load('trip-a');
    expect(reloaded.daysBefore, 14);
  });

  test('storableItems çıktısı preset+unchecked maddeleri storage\'a yazmaz',
      () async {
    final repo = _makeRepo();
    var st = await repo.load('trip-a');
    st = st.toggle('passport');
    await repo.save(st);
    // Merge geri getirdiğinde preset unchecked'lar hâlâ görünmeli
    final reloaded = await repo.load('trip-a');
    expect(reloaded.totalCount, kPreDeparturePresets.length);
    expect(
      reloaded.items.firstWhere((i) => i.id == 'passport').checked,
      isTrue,
    );
    expect(
      reloaded.items.firstWhere((i) => i.id == 'jrPass').checked,
      isFalse,
    );
  });

  test('delete state\'i temizler', () async {
    final repo = _makeRepo();
    var st = await repo.load('trip-a');
    st = st.toggle('passport');
    await repo.save(st);
    await repo.delete('trip-a');
    final after = await repo.load('trip-a');
    expect(after.doneCount, 0);
    expect(after.items.where((i) => i.custom), isEmpty);
  });

  test('birden çok tripId birbirine karışmaz', () async {
    final repo = _makeRepo();
    var a = await repo.load('trip-a');
    var b = await repo.load('trip-b');
    a = a.toggle('passport');
    b = b
        .toggle('esim')
        .addCustom(PrepItem.customFromLabel('Kablo'));
    await repo.save(a);
    await repo.save(b);

    final ra = await repo.load('trip-a');
    final rb = await repo.load('trip-b');
    expect(
      ra.items.firstWhere((i) => i.id == 'passport').checked,
      isTrue,
    );
    expect(
      ra.items.firstWhere((i) => i.id == 'esim').checked,
      isFalse,
    );
    expect(
      rb.items.firstWhere((i) => i.id == 'esim').checked,
      isTrue,
    );
    expect(rb.items.any((i) => i.custom), isTrue);
  });
}
