import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/types.dart';
import '../../viewer/viewer_theme.dart';
import 'ticket_wallet_cards.dart';

class TicketWalletView extends StatelessWidget {
  const TicketWalletView({
    super.key,
    required this.tickets,
    required this.palette,
    required this.now,
    required this.onAdd,
    required this.onOpen,
    required this.onOpenMedia,
  });

  final List<Ticket> tickets;
  final ViewerPalette palette;
  final DateTime now;
  final VoidCallback onAdd;
  final ValueChanged<Ticket> onOpen;
  final ValueChanged<Ticket> onOpenMedia;

  @override
  Widget build(BuildContext context) {
    final ready = tickets.where((ticket) => ticket.purchased).toList()
      ..sort(_compareReadyTickets);
    final pending = tickets.where((ticket) => !ticket.purchased).toList();
    final today = _dateOnly(now);
    final upcoming = ready.where((ticket) {
      final date = _ticketDate(ticket);
      return date != null && !date.isBefore(today);
    }).toList();
    final featured = upcoming.isNotEmpty
        ? upcoming.first
        : (ready.isEmpty ? null : ready.first);
    final otherReady = ready
        .where((ticket) => ticket.id != featured?.id)
        .toList(growable: false);
    final summary = _walletSummary(
      context,
      ticketCount: tickets.length,
      readyCount: ready.length,
      featured: featured,
      today: today,
    );

    return CustomScrollView(
      key: const ValueKey('ticket-wallet-scroll'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          sliver: SliverToBoxAdapter(
            child: _WalletHeader(
              palette: palette,
              summary: summary,
              onAdd: onAdd,
            ),
          ),
        ),
        if (tickets.isEmpty)
          SliverToBoxAdapter(
            child: TicketWalletEmptyState(
              key: const ValueKey('ticket-wallet-empty'),
              palette: palette,
              onAdd: onAdd,
            ),
          ),
        if (featured != null)
          SliverToBoxAdapter(
            child: TicketWalletCard(
              key: const ValueKey('ticket-wallet-featured'),
              ticket: featured,
              palette: palette,
              now: now,
              onOpen: () => onOpen(featured),
              onOpenMedia: () => onOpenMedia(featured),
            ),
          ),
        if (otherReady.isNotEmpty)
          SliverToBoxAdapter(
            child: TicketCompactList(
              key: const ValueKey('ticket-wallet-compact-list'),
              tickets: otherReady,
              palette: palette,
              now: now,
              onOpen: onOpen,
              onOpenMedia: onOpenMedia,
            ),
          ),
        if (pending.isNotEmpty)
          SliverToBoxAdapter(
            child: TicketPendingGroup(
              key: const ValueKey('ticket-wallet-pending-group'),
              tickets: pending,
              palette: palette,
              now: now,
              onOpen: onOpen,
              onOpenMedia: onOpenMedia,
            ),
          ),
      ],
    );
  }
}

class _WalletHeader extends StatelessWidget {
  const _WalletHeader({
    required this.palette,
    required this.summary,
    required this.onAdd,
  });

  final ViewerPalette palette;
  final String? summary;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final addLabel = s.s('ticketWallet.add');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                s.s('ticketWallet.title'),
                key: const ValueKey('ticket-wallet-title'),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 34,
                  height: 1.04,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.72,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Semantics(
              button: true,
              label: addLabel,
              onTap: onAdd,
              child: SizedBox.square(
                key: const ValueKey('ticket-wallet-add'),
                dimension: 44,
                child: Material(
                  color: palette.accent.withValues(alpha: .10),
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: onAdd,
                    excludeFromSemantics: true,
                    customBorder: const CircleBorder(),
                    splashFactory: NoSplash.splashFactory,
                    overlayColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.pressed)
                          ? palette.accent.withValues(alpha: .16)
                          : null,
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      size: 25,
                      color: palette.accent,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (summary != null) ...[
          const SizedBox(height: 8),
          Text(
            summary!,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

String? _walletSummary(
  BuildContext context, {
  required int ticketCount,
  required int readyCount,
  required Ticket? featured,
  required DateTime today,
}) {
  if (ticketCount == 0) return null;
  final s = LanguageScope.of(context);
  final parts = <String>[
    s.p(
      ticketCount == 1
          ? 'ticketWallet.summary.tickets.singular'
          : 'ticketWallet.summary.tickets.plural',
      {'count': '$ticketCount'},
    ),
    s.p(
      readyCount == 1
          ? 'ticketWallet.summary.ready.singular'
          : 'ticketWallet.summary.ready.plural',
      {'count': '$readyCount'},
    ),
  ];
  final featuredDate = featured == null ? null : _ticketDate(featured);
  if (featuredDate != null && !featuredDate.isBefore(today)) {
    final days = featuredDate.difference(today).inDays;
    parts.add(switch (days) {
      0 => s.s('ticketWallet.summary.next.today'),
      1 => s.s('ticketWallet.summary.next.tomorrow'),
      _ => s.p('ticketWallet.summary.next.days', {'count': '$days'}),
    });
  }
  return parts.join(s.s('ticketWallet.summary.separator'));
}

int _compareReadyTickets(Ticket left, Ticket right) {
  final leftDate = _ticketDate(left);
  final rightDate = _ticketDate(right);
  if (leftDate == null && rightDate != null) return 1;
  if (leftDate != null && rightDate == null) return -1;
  if (leftDate != null && rightDate != null) {
    final dateComparison = leftDate.compareTo(rightDate);
    if (dateComparison != 0) return dateComparison;
  }
  return left.id.compareTo(right.id);
}

DateTime? _ticketDate(Ticket ticket) {
  final raw = ticket.visitDate?.trim();
  if (raw == null || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
