import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/plan_generation.dart';
import 'package:rotori/features/viewer/pre_departure_checklist_screen.dart';

void main() {
  testWidgets('checklist does not show the pre-trip affiliate section',
      (tester) async {
    final trip = buildTripFromCities(
      cityKeys: const ['tokyo'],
      startYmd: '2026-10-15',
      endYmd: '2026-10-21',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: PreDepartureChecklistScreen(trip: trip)),
      ),
    );
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pump();

    expect(find.textContaining('Seyahat öncesi hallet'), findsNothing);
    expect(find.textContaining('Book before you go'), findsNothing);
  });
}
