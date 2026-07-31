import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/bug_report.dart';
import 'package:japan_trip/domain/trip_factory.dart';

void main() {
  test('BugReport JSON hassas plan ayrıntılarını taşımaz', () {
    final trip = createEmptyTrip();
    trip.title = 'Tokyo planı';
    final report = BugReport(
      message: 'Saatler çakıştı',
      category: BugReportCategory.schedule,
      planId: 'plan-1',
      contactEmail: 'user@example.com',
      context: BugReport.contextForTrip(
        trip: trip,
        planId: 'plan-1',
        appVersion: '1.0.0+1',
        platform: 'test',
        locale: 'tr',
      ),
    );

    final json = report.toJson();
    expect(json['category'], 'schedule');
    expect(json['message'], 'Saatler çakıştı');
    expect(json['contact_email'], 'user@example.com');
    expect(json['context'], isA<Map<String, Object?>>());
    final context = json['context']! as Map<String, Object?>;
    expect(context.containsKey('tripTitle'), isFalse);
    final days = context['days']! as List<Object?>;
    final firstDay = days.first! as Map<String, Object?>;
    expect(firstDay['items'], isA<List<Object?>>());
    expect(
      (firstDay['items']! as List<Object?>).every(
        (item) => !(item! as Map<String, Object?>).containsKey('title'),
      ),
      isTrue,
    );
    expect(report.contextJson(), contains('schemaVersion'));
  });
}
