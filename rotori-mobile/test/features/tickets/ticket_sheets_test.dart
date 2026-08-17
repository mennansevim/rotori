import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/core/l10n.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/tickets/domain/ticket_import_models.dart';
import 'package:rotori/features/tickets/presentation/ticket_add_sheet.dart';
import 'package:rotori/features/tickets/presentation/ticket_detail_sheet.dart';
import 'package:rotori/features/tickets/presentation/ticket_import_review_sheet.dart';
import 'package:rotori/features/viewer/viewer_theme.dart';

const _palette = ViewerPalette.appleLight;

String tr(String key) => L10n.resolve(key, AppLang.tr);

Widget _harness({
  required WidgetBuilder builder,
  TextScaler textScaler = TextScaler.noScaling,
}) =>
    MaterialApp(
      theme: _palette.toThemeData(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: LanguageScope(lang: AppLang.tr, child: Builder(builder: builder)),
    );

Ticket _ticket({
  String id = 'ticket-1',
  String label = 'teamLab Planets',
  bool purchased = true,
  String? visitDate,
  String? entryTime,
  String? localMediaRef,
  String? scannedText,
}) =>
    Ticket(
      id: id,
      kind: 'attraction',
      label: label,
      purchased: purchased,
      visitDate: visitDate,
      entryTime: entryTime,
      localMediaRef: localMediaRef,
      scannedText: scannedText,
    );

void main() {
  testWidgets(
      'source sheet exposes each source and returns its explicit result',
      (tester) async {
    for (final source in TicketAddSource.values) {
      TicketAddSource? result;
      await tester.pumpWidget(
        _harness(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showTicketAddSheet(
                    context: context,
                    palette: _palette,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isTrue,
      );
      expect(find.byKey(ValueKey('ticket-add-${source.name}')), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('ticket-add-${source.name}')));
      await tester.pumpAndSettle();

      expect(result, source);
    }
  });

  testWidgets('source sheet remains dismissible from its modal barrier',
      (tester) async {
    TicketAddSource? result = TicketAddSource.gallery;
    await tester.pumpWidget(
      _harness(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              result = await showTicketAddSheet(
                context: context,
                palette: _palette,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets(
      'review shows only discovered groups and requires a date selection before save',
      (tester) async {
    TicketReviewResult? result;
    const extraction = TicketExtractionResult(
      candidates: [
        TicketImportCandidate(
          id: 'date-1',
          type: TicketCandidateType.date,
          value: '2026-08-20',
          needsReview: false,
        ),
        TicketImportCandidate(
          id: 'date-2',
          type: TicketCandidateType.date,
          value: '2026-08-21',
          needsReview: true,
        ),
        TicketImportCandidate(
          id: 'time-1',
          type: TicketCandidateType.time,
          value: '09:30',
          needsReview: false,
        ),
        TicketImportCandidate(
          id: 'code-1',
          type: TicketCandidateType.confirmationCode,
          value: 'AB12CD',
          needsReview: false,
        ),
      ],
    );
    await tester.pumpWidget(
      _harness(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              result = await showTicketImportReviewSheet(
                context: context,
                extraction: extraction,
                initialTicket: _ticket(label: 'teamLab Planets'),
                palette: _palette,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('ticket-review-date-group')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('ticket-review-venue-group')), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
              find.byKey(const ValueKey('ticket-review-save')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('ticket-review-purchased')),
          )
          .value,
      isFalse,
    );

    await tester.drag(
      find.byKey(const ValueKey('ticket-review-scroll')),
      const Offset(0, -220),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ticket-review-date-date-2')),
        matching: find.byType(Radio<String>),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
              find.byKey(const ValueKey('ticket-review-save')))
          .onPressed,
      isNotNull,
    );
    await tester.drag(
      find.byKey(const ValueKey('ticket-review-scroll')),
      const Offset(0, -220),
    );
    await tester.pump();
    expect(
        find.byKey(const ValueKey('ticket-review-time-group')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ticket-review-remove-code-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ticket-review-save')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.ticket.visitDate, '2026-08-21');
    expect(result!.ticket.entryTime, '09:30');
    expect(result!.ticket.purchased, isFalse);
    expect(result!.ticket.scannedText, isNull);
    expect(
      result!.ticket.confirmedDetails
          .where((detail) => detail.semanticKey == 'confirmationCode'),
      isEmpty,
    );
  });

  testWidgets('empty review permits a manually entered label without OCR data',
      (tester) async {
    TicketReviewResult? result;
    await tester.pumpWidget(
      _harness(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              result = await showTicketImportReviewSheet(
                context: context,
                extraction: const TicketExtractionResult(
                  rawText: 'do not persist this',
                  qrPayloads: ['unselected-qr-payload'],
                ),
                initialTicket: _ticket(label: '', scannedText: 'legacy OCR'),
                palette: _palette,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ticket-review-label')),
      'Kyoto concert',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ticket-review-save')));
    await tester.pumpAndSettle();

    expect(result?.ticket.label, 'Kyoto concert');
    expect(result?.ticket.scannedText, isNull);
    expect(result?.ticket.confirmedDetails, isEmpty);
  });

  testWidgets('review keeps a QR candidate out of the ticket until selected',
      (tester) async {
    TicketReviewResult? result;
    await tester.pumpWidget(
      _harness(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              result = await showTicketImportReviewSheet(
                context: context,
                extraction: const TicketExtractionResult(
                  candidates: [
                    TicketImportCandidate(
                      id: 'qr-1',
                      type: TicketCandidateType.qr,
                      value: 'https://ticket.example/qr-1',
                      needsReview: true,
                    ),
                  ],
                  qrPayloads: ['https://ticket.example/qr-1'],
                ),
                initialTicket: _ticket(),
                palette: _palette,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final accept = find.byKey(const ValueKey('ticket-review-accept-qr-1'));
    expect(accept, findsOneWidget);
    expect(tester.widget<Checkbox>(accept).value, isFalse);

    await tester.tap(accept);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ticket-review-save')));
    await tester.pumpAndSettle();

    expect(
      result?.ticket.confirmedDetails.single.semanticKey,
      TicketCandidateType.qr.name,
    );
  });

  testWidgets('review omits an unchecked QR candidate from saved details',
      (tester) async {
    TicketReviewResult? result;
    await tester.pumpWidget(
      _harness(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              result = await showTicketImportReviewSheet(
                context: context,
                extraction: const TicketExtractionResult(
                  candidates: [
                    TicketImportCandidate(
                      id: 'qr-unchecked',
                      type: TicketCandidateType.qr,
                      value: 'https://ticket.example/unselected',
                      needsReview: true,
                    ),
                  ],
                ),
                initialTicket: _ticket(),
                palette: _palette,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey('ticket-review-accept-qr-unchecked')),
          )
          .value,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('ticket-review-save')));
    await tester.pumpAndSettle();

    expect(result?.ticket.confirmedDetails, isEmpty);
  });

  testWidgets('removing canonical candidates clears prior date and time',
      (tester) async {
    TicketReviewResult? result;
    await tester.pumpWidget(
      _harness(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              result = await showTicketImportReviewSheet(
                context: context,
                extraction: const TicketExtractionResult(
                  candidates: [
                    TicketImportCandidate(
                      id: 'replacement-date',
                      type: TicketCandidateType.date,
                      value: '2026-09-01',
                      needsReview: false,
                    ),
                    TicketImportCandidate(
                      id: 'replacement-time',
                      type: TicketCandidateType.time,
                      value: '10:15',
                      needsReview: false,
                    ),
                  ],
                ),
                initialTicket: _ticket(
                  visitDate: '2026-08-20',
                  entryTime: '09:00',
                ),
                palette: _palette,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('ticket-review-scroll')),
      const Offset(0, -220),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ticket-review-date-group')),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ticket-review-time-group')),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ticket-review-save')));
    await tester.pumpAndSettle();

    expect(result?.ticket.visitDate, isNull);
    expect(result?.ticket.entryTime, isNull);
  });

  testWidgets('a selected blank date keeps save disabled', (tester) async {
    await tester.pumpWidget(
      _harness(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => showTicketImportReviewSheet(
              context: context,
              extraction: const TicketExtractionResult(
                candidates: [
                  TicketImportCandidate(
                    id: 'editable-date',
                    type: TicketCandidateType.date,
                    value: '2026-09-01',
                    needsReview: false,
                  ),
                ],
              ),
              initialTicket: _ticket(
                visitDate: '2026-08-20',
                entryTime: '09:00',
              ),
              palette: _palette,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('ticket-review-scroll')),
      const Offset(0, -180),
    );
    await tester.pump();
    final candidate =
        find.byKey(const ValueKey('ticket-review-date-editable-date'));
    await tester.tap(
      find.descendant(of: candidate, matching: find.byType(Radio<String>)),
    );
    await tester.enterText(
      find.descendant(of: candidate, matching: find.byType(TextField)),
      '',
    );
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('ticket-review-save')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('a selected blank time clears a prior entry time on save',
      (tester) async {
    TicketReviewResult? result;
    await tester.pumpWidget(
      _harness(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              result = await showTicketImportReviewSheet(
                context: context,
                extraction: const TicketExtractionResult(
                  candidates: [
                    TicketImportCandidate(
                      id: 'valid-date',
                      type: TicketCandidateType.date,
                      value: '2026-09-01',
                      needsReview: false,
                    ),
                    TicketImportCandidate(
                      id: 'blank-time',
                      type: TicketCandidateType.time,
                      value: '10:15',
                      needsReview: false,
                    ),
                  ],
                ),
                initialTicket: _ticket(
                  visitDate: '2026-08-20',
                  entryTime: '09:00',
                ),
                palette: _palette,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('ticket-review-scroll')),
      const Offset(0, -220),
    );
    await tester.pump();
    final date = find.byKey(const ValueKey('ticket-review-date-valid-date'));
    await tester.tap(
      find.descendant(of: date, matching: find.byType(Radio<String>)),
    );
    final time = find.byKey(const ValueKey('ticket-review-time-blank-time'));
    await tester.enterText(
      find.descendant(of: time, matching: find.byType(TextField)),
      '',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ticket-review-save')));
    await tester.pumpAndSettle();

    expect(result?.ticket.visitDate, '2026-09-01');
    expect(result?.ticket.entryTime, isNull);
  });

  testWidgets('detail renders local media and returns a saved edited ticket',
      (tester) async {
    TicketDetailResult? result;
    await tester.pumpWidget(
      _harness(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              result = await showTicketDetailSheet(
                context: context,
                ticket: _ticket(),
                mediaBytes: Uint8List.fromList(_transparentPng),
                palette: _palette,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ticket-detail-media')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('ticket-detail-label')),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.byKey(const ValueKey('ticket-detail-label')),
      'teamLab Planets updated',
    );
    await tester.tap(find.byKey(const ValueKey('ticket-detail-save')));
    await tester.pumpAndSettle();

    expect(result?.action, TicketDetailAction.save);
    expect(result?.ticket?.label, 'teamLab Planets updated');
  });

  testWidgets('detail enables saving after an empty ticket receives a label',
      (tester) async {
    await tester.pumpWidget(
      _harness(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => showTicketDetailSheet(
              context: context,
              ticket: _ticket(label: ''),
              mediaBytes: null,
              palette: _palette,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
              find.byKey(const ValueKey('ticket-detail-save')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('ticket-detail-label')),
      'New ticket',
    );
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(
              find.byKey(const ValueKey('ticket-detail-save')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
      'detail exposes reattach and only deletes after a named confirmation',
      (tester) async {
    TicketDetailResult? result;
    final ticket = _ticket(localMediaRef: 'ticket-media://missing');
    await tester.pumpWidget(
      _harness(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              result = await showTicketDetailSheet(
                context: context,
                ticket: ticket,
                mediaBytes: null,
                palette: _palette,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text(tr('ticketDetail.reattachMedia')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ticket-detail-replace-media')));
    await tester.pumpAndSettle();
    expect(result?.action, TicketDetailAction.replaceMedia);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ticket-detail-delete')));
    await tester.pumpAndSettle();
    expect(find.textContaining(ticket.label), findsWidgets);
    await tester
        .tap(find.byKey(const ValueKey('ticket-detail-confirm-delete')));
    await tester.pumpAndSettle();

    expect(result?.action, TicketDetailAction.delete);
  });

  testWidgets('review remains usable at 2x Dynamic Type', (tester) async {
    await tester.pumpWidget(
      _harness(
        textScaler: const TextScaler.linear(2),
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => showTicketImportReviewSheet(
              context: context,
              extraction: const TicketExtractionResult(),
              initialTicket: _ticket(label: ''),
              palette: _palette,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ticket-review-label')),
      'A long enough ticket label to require a larger layout',
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('ticket-review-save')), findsOneWidget);
  });
}

const _transparentPng = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  8,
  215,
  99,
  248,
  207,
  192,
  240,
  31,
  0,
  5,
  0,
  1,
  255,
  137,
  153,
  61,
  29,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];
