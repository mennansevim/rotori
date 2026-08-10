// Şehirler arası transfer + saat yeniden sıralama — saf domain testleri.
//
// Kaynak: test/features/plan_flow_test.dart (wizard sökülürken buraya
// taşındı; UI'dan bağımsız oldukları için korunuyor).

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/core/l10n.dart';
import 'package:rotori/domain/city_transfers.dart';
import 'package:rotori/domain/day_optimizer.dart';
import 'package:rotori/domain/types.dart';

void main() {
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
    // bus modu → bus emojisi & Willer tip (tip artık i18n anahtarı; TR'ye çöz)
    final sb = suggestionForMode('bus', 'Tokyo', 'Osaka', 3, 4);
    expect(sb.transfer.emoji, '🚌');
    expect(L10n.resolve('${sb.transfer.tip}', AppLang.tr), contains('Willer'));
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
