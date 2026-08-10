import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/ticketed_activity.dart';

void main() {
  test('tema parkları tam gün ve daha erken varış varsayımı alır', () {
    for (final title in [
      'Universal Studios Japan (USJ)',
      'Tokyo Disneyland',
      'Tokyo DisneySea',
    ]) {
      final defaults = ticketedActivityDefaultsForTitle(title);
      expect(defaults.durationMinutes, 720, reason: title);
      expect(defaults.arrivalBufferMinutes, 60, reason: title);
      expect(defaults.fullDay, isTrue, reason: title);
    }
  });

  test('teamLab deneyimleri ürün tipine göre süre alır', () {
    expect(ticketedActivityDefaultsForTitle('teamLab Planets').durationMinutes,
        180);
    expect(
        ticketedActivityDefaultsForTitle('teamLab Borderless').durationMinutes,
        240);
    expect(
        ticketedActivityDefaultsForTitle('teamLab Botanical Garden')
            .durationMinutes,
        120);
  });
}
