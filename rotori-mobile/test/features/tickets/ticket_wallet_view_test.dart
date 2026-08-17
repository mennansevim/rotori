import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rotori/core/l10n.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/tickets/presentation/ticket_wallet_view.dart';
import 'package:rotori/features/viewer/viewer_theme.dart';

const _palette = ViewerPalette.appleLight;
final _now = DateTime(2026, 8, 18, 12);

String tr(String key) => L10n.resolve(key, AppLang.tr);

String trp(String key, Map<String, String> params) =>
    L10n.parametrize(tr(key), params);

Ticket ticket({
  required String id,
  required String label,
  required bool purchased,
  String? visitDate,
  String? bookingOpens,
  String? entryTime,
  String? localMediaRef,
  List<TicketDetail> details = const [],
}) =>
    Ticket(
      id: id,
      kind: 'experience',
      label: label,
      purchased: purchased,
      visitDate: visitDate,
      bookingOpens: bookingOpens,
      entryTime: entryTime,
      localMediaRef: localMediaRef,
      confirmedDetails: details,
    );

Widget harness({
  required List<Ticket> tickets,
  AppLang lang = AppLang.tr,
  TextScaler textScaler = TextScaler.noScaling,
  VoidCallback? onAdd,
  ValueChanged<Ticket>? onOpen,
  ValueChanged<Ticket>? onOpenMedia,
}) =>
    MaterialApp(
      theme: _palette.toThemeData(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: LanguageScope(
        lang: lang,
        child: Scaffold(
          backgroundColor: _palette.bg,
          body: TicketWalletView(
            tickets: tickets,
            palette: _palette,
            now: _now,
            onAdd: onAdd ?? () {},
            onOpen: onOpen ?? (_) {},
            onOpenMedia: onOpenMedia ?? (_) {},
          ),
        ),
      ),
    );

void main() {
  testWidgets(
      'groups a copied list and features the earliest future ready ticket',
      (tester) async {
    final tickets = [
      ticket(
        id: 'pending-sale',
        label: 'teamLab Borderless',
        purchased: false,
        bookingOpens: '2026-08-25',
      ),
      ticket(
        id: 'ready-soon',
        label: 'Ghibli Museum',
        purchased: true,
        visitDate: '2026-08-20',
        localMediaRef: 'ticket-media://ready-soon',
      ),
      ticket(
        id: 'ready-past',
        label: 'Tokyo Skytree',
        purchased: true,
        visitDate: '2026-08-10',
        localMediaRef: 'ticket-media://ready-past',
      ),
    ];
    final originalOrder = tickets.map((item) => item.id).toList();

    await tester.pumpWidget(harness(tickets: tickets));
    await tester.pump();

    expect(find.byKey(const ValueKey('ticket-wallet-title')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('ticket-wallet-featured')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ticket-wallet-compact-list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ticket-wallet-pending-group')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('ticket-wallet-add')), findsOneWidget);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ticket-wallet-featured')),
        matching: find.text('Ghibli Museum'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ticket-wallet-compact-list')),
        matching: find.text('Tokyo Skytree'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ticket-wallet-pending-group')),
        matching: find.text('teamLab Borderless'),
      ),
      findsOneWidget,
    );
    expect(tickets.map((item) => item.id), originalOrder);

    final expectedSummary = [
      trp('ticketWallet.summary.tickets.plural', {'count': '3'}),
      trp('ticketWallet.summary.ready.plural', {'count': '2'}),
      trp('ticketWallet.summary.next.days', {'count': '2'}),
    ].join(tr('ticketWallet.summary.separator'));
    expect(find.text(expectedSummary), findsOneWidget);
  });

  testWidgets('pending rows expose sale countdown and missing-info status',
      (tester) async {
    await tester.pumpWidget(
      harness(
        tickets: [
          ticket(
            id: 'sale',
            label: 'Universal Studios Japan',
            purchased: false,
            bookingOpens: '2026-08-25',
          ),
          ticket(
            id: 'missing',
            label: 'Local concert',
            purchased: false,
          ),
        ],
      ),
    );
    await tester.pump();

    expect(
      find.text(trp('ticketWallet.status.saleInDays', {'count': '7'})),
      findsOneWidget,
    );
    expect(find.text(tr('ticketWallet.status.missingInfo')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ticket-status-icon-sale')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ticket-status-icon-missing')),
      findsOneWidget,
    );
  });

  testWidgets('card summary and media action are separate semantic targets',
      (tester) async {
    final ready = ticket(
      id: 'ready',
      label: 'Shinkansen Tokyo to Kyoto',
      purchased: true,
      visitDate: '2026-08-20',
      entryTime: '09:10',
      localMediaRef: 'ticket-media://ready',
    );
    final opened = <String>[];
    final openedMedia = <String>[];
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      harness(
        tickets: [ready],
        onOpen: (item) => opened.add(item.id),
        onOpenMedia: (item) => openedMedia.add(item.id),
      ),
    );
    await tester.pump();

    final date = trp('ticketWallet.date', {
      'day': '20',
      'month': L10n.monthsShortFor(AppLang.tr)[8],
      'year': '2026',
    });
    final details = [date, '09:10'].join(tr('ticketWallet.semantic.separator'));
    final cardLabel = trp('ticketWallet.semantic.summary', {
      'name': ready.label,
      'details': details,
      'status': tr('ticketWallet.status.ready'),
    });
    final mediaLabel = trp('ticketWallet.openMedia', {'name': ready.label});

    expect(find.bySemanticsLabel(cardLabel), findsOneWidget);
    expect(find.bySemanticsLabel(mediaLabel), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('ticket-wallet-add'))),
      const Size.square(44),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('ticket-wallet-media-ready'))),
      const Size.square(44),
    );

    final inkWell = tester.widget<InkWell>(
      find.byKey(const ValueKey('ticket-wallet-card-press-ready')),
    );
    final pressedColor = inkWell.overlayColor?.resolve({WidgetState.pressed});
    expect(inkWell.splashFactory, same(NoSplash.splashFactory));
    expect(pressedColor?.a, greaterThan(0));

    await tester.tap(find.bySemanticsLabel(cardLabel));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ticket-wallet-media-ready')));
    await tester.pump();

    expect(opened, ['ready']);
    expect(openedMedia, ['ready']);
    semantics.dispose();
  });

  testWidgets('empty wallet has calm copy and a first-ticket action',
      (tester) async {
    var addCount = 0;

    await tester.pumpWidget(
      harness(tickets: const [], onAdd: () => addCount++),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('ticket-wallet-empty')), findsOneWidget);
    expect(find.text(tr('ticketWallet.empty.title')), findsOneWidget);
    expect(find.text(tr('ticketWallet.empty.body')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-first-ticket')), findsOneWidget);
    expect(find.byKey(const ValueKey('ticket-wallet-featured')), findsNothing);
    expect(
      find.byKey(const ValueKey('ticket-wallet-pending-group')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('add-first-ticket')));
    await tester.pump();
    expect(addCount, 1);
  });

  testWidgets('390pt width at 2x text scale lays out without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness(
        textScaler: const TextScaler.linear(2),
        tickets: [
          ticket(
            id: 'long-ready',
            label:
                'Shinkansen reserved seat from Tokyo Station to Kyoto Station',
            purchased: true,
            visitDate: '2026-08-20',
            entryTime: '09:10',
            localMediaRef: 'ticket-media://long-ready',
            details: const [
              TicketDetail(
                id: 'venue',
                semanticKey: 'venue',
                label: 'Venue',
                value: 'Tokyo Station Marunouchi South Gate',
              ),
              TicketDetail(
                id: 'party',
                semanticKey: 'partySize',
                label: 'Party size',
                value: '4',
              ),
            ],
          ),
          ticket(
            id: 'second-ready',
            label: 'teamLab Planets timed admission',
            purchased: true,
            visitDate: '2026-08-23',
            localMediaRef: 'ticket-media://second-ready',
          ),
          ticket(
            id: 'long-pending',
            label: 'Universal Studios Japan Express Pass reservation',
            purchased: false,
            bookingOpens: '2026-08-25',
          ),
        ],
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('ticket-wallet-title')), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('ticket-wallet-scroll')),
      const Offset(0, -2400),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('ticket-wallet-pending-group')),
      findsOneWidget,
    );
  });
}
