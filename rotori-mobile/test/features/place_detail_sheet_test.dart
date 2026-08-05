// Yer detay sheet'i — rehberli (teamLab) ve rehbersiz durak için smoke test.
// Görseller testte yüklenemez (HTTP yok) → errorBuilder placeholder'a düşer.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/shared/place_detail_sheet.dart';

Widget _harness(TimelineItem item) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: FilledButton(
              onPressed: () => showPlaceDetailSheet(
                context: ctx,
                item: item,
                city: 'Tokyo',
                countryCode: 'JP',
              ),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('rehberli yer: stat bar render, sheet tam ekran kaplamaz',
      (tester) async {
    await tester.pumpWidget(_harness(TimelineItem(
      id: 't1',
      title: 'teamLab Planets',
      kind: TimelineItemKind.activity,
      time: '14:30',
    )));
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();

    expect(find.text('teamLab Planets'), findsOneWidget);
    // Stat bar hücreleri (⏱ Süre / 👣 Yürüme / 🎟 Bilet)
    expect(find.textContaining('Süre'), findsWidgets);
    expect(find.textContaining('Yürüme'), findsWidgets);
    // Tam ekran kaplamıyor: sheet üstünde boşluk kalmalı.
    final sheetTop = tester.getTopLeft(find.byType(ListView)).dy;
    expect(sheetTop, greaterThan(50));
  });

  testWidgets('rehbersiz yer: fallback içerik, ipuçları yok', (tester) async {
    await tester.pumpWidget(_harness(TimelineItem(
      id: 't2',
      title: 'Random Cafe X',
      kind: TimelineItemKind.meal,
      time: '12:00',
    )));
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();

    expect(find.text('Random Cafe X'), findsOneWidget);
    expect(find.text('İpuçları'), findsNothing);
    expect(find.text('Haritada aç'), findsOneWidget);
  });

  testWidgets('sheet sağ üst çarpı ile kapanır', (tester) async {
    await tester.pumpWidget(_harness(TimelineItem(
      id: 't3',
      title: 'Shibuya Sky',
      kind: TimelineItemKind.activity,
      time: '14:30',
    )));
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();

    expect(find.text('Shibuya Sky'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Shibuya Sky'), findsNothing);
  });
}
