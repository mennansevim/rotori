import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/plan_warnings.dart';
import 'package:japan_trip/domain/types.dart';

DayPlan _day(List<TimelineItem> items) => DayPlan(
      dayNumber: 1,
      date: '2026-10-01',
      theme: '',
      tags: const [],
      items: items,
    );

TimelineItem _item(String id, String time, {int? durationMin}) => TimelineItem(
      id: id,
      title: id,
      kind: TimelineItemKind.activity,
      time: time,
      durationMin: durationMin,
    );

void main() {
  test('süresi belirtilmeyen ardışık transfer zinciri sahte çakışma üretmez',
      () {
    final warnings = planWarningsFor(_day([
      _item('check-in', '11:00'),
      _item('transfer', '11:30'),
      _item('airport', '12:00'),
    ]));

    expect(warnings, isEmpty);
  });

  test('bildirilen süre ve yetersiz geçiş gerçek çakışmayı yakalar', () {
    final warnings = planWarningsFor(_day([
      _item('shibuya', '09:00', durationMin: 90),
      _item('senso-ji', '10:00', durationMin: 90),
    ]));

    expect(warnings, hasLength(1));
    expect(warnings.single.kind, PlanWarningKind.timeConflict);
    expect(warnings.single.activityId, 'senso-ji');
  });
}
