import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/types.dart';
import '../../viewer/viewer_theme.dart';

class TicketWalletCard extends StatelessWidget {
  const TicketWalletCard({
    super.key,
    required this.ticket,
    required this.palette,
    required this.now,
    required this.onOpen,
    required this.onOpenMedia,
  });

  final Ticket ticket;
  final ViewerPalette palette;
  final DateTime now;
  final VoidCallback onOpen;
  final VoidCallback onOpenMedia;

  @override
  Widget build(BuildContext context) {
    final status = _statusFor(context, ticket, now, palette);
    final colors = _featuredColors(ticket, palette);
    final semanticLabel = _ticketSemanticLabel(context, ticket, status.label);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: .16),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('ticket-wallet-card-press-${ticket.id}'),
              onTap: onOpen,
              excludeFromSemantics: true,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.pressed)
                    ? Colors.white.withValues(alpha: .12)
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      button: true,
                      label: semanticLabel,
                      onTap: onOpen,
                      child: ExcludeSemantics(
                        child: _FeaturedTicketContent(
                          ticket: ticket,
                          status: status,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TicketMediaButton(
                        ticket: ticket,
                        foreground: Colors.white,
                        background: Colors.white.withValues(alpha: .15),
                        onPressed: onOpenMedia,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TicketCompactList extends StatelessWidget {
  const TicketCompactList({
    super.key,
    required this.tickets,
    required this.palette,
    required this.now,
    required this.onOpen,
    required this.onOpenMedia,
  });

  final List<Ticket> tickets;
  final ViewerPalette palette;
  final DateTime now;
  final ValueChanged<Ticket> onOpen;
  final ValueChanged<Ticket> onOpenMedia;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(text: s.s('ticketWallet.otherReady'), palette: palette),
          const SizedBox(height: 10),
          for (var index = 0; index < tickets.length; index++) ...[
            _CompactTicketCard(
              ticket: tickets[index],
              palette: palette,
              now: now,
              onOpen: () => onOpen(tickets[index]),
              onOpenMedia: () => onOpenMedia(tickets[index]),
            ),
            if (index != tickets.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class TicketPendingGroup extends StatelessWidget {
  const TicketPendingGroup({
    super.key,
    required this.tickets,
    required this.palette,
    required this.now,
    required this.onOpen,
    required this.onOpenMedia,
  });

  final List<Ticket> tickets;
  final ViewerPalette palette;
  final DateTime now;
  final ValueChanged<Ticket> onOpen;
  final ValueChanged<Ticket> onOpenMedia;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(text: s.s('ticketWallet.pending'), palette: palette),
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.card,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(18),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Column(
                children: [
                  for (var index = 0; index < tickets.length; index++) ...[
                    _PendingTicketRow(
                      ticket: tickets[index],
                      palette: palette,
                      now: now,
                      onOpen: () => onOpen(tickets[index]),
                      onOpenMedia: () => onOpenMedia(tickets[index]),
                    ),
                    if (index != tickets.length - 1)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 16),
                        child: Divider(height: 1, color: palette.border),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TicketWalletEmptyState extends StatelessWidget {
  const TicketWalletEmptyState({
    super.key,
    required this.palette,
    required this.onAdd,
  });

  final ViewerPalette palette;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 48, 28, 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: .09),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.confirmation_number_outlined,
                size: 30,
                color: palette.accent,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            s.s('ticketWallet.empty.title'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 22,
              height: 1.15,
              fontWeight: FontWeight.w700,
              letterSpacing: -.3,
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              s.s('ticketWallet.empty.body'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 15,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: FilledButton.icon(
              key: const ValueKey('add-first-ticket'),
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(s.s('ticketWallet.empty.add')),
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 44),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TicketMediaButton extends StatelessWidget {
  const TicketMediaButton({
    super.key,
    required this.ticket,
    required this.foreground,
    required this.background,
    required this.onPressed,
  });

  final Ticket ticket;
  final Color foreground;
  final Color background;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final label = s.p('ticketWallet.openMedia', {'name': ticket.label});
    return Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      child: SizedBox.square(
        key: ValueKey('ticket-wallet-media-${ticket.id}'),
        dimension: 44,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            excludeFromSemantics: true,
            customBorder: const CircleBorder(),
            splashFactory: NoSplash.splashFactory,
            overlayColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.pressed)
                  ? foreground.withValues(alpha: .16)
                  : null,
            ),
            child: Icon(Icons.qr_code_2_rounded, size: 24, color: foreground),
          ),
        ),
      ),
    );
  }
}

class _FeaturedTicketContent extends StatelessWidget {
  const _FeaturedTicketContent({required this.ticket, required this.status});

  final Ticket ticket;
  final _TicketStatus status;

  @override
  Widget build(BuildContext context) {
    final facts = _factsFor(ticket);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusChip(
          ticketId: ticket.id,
          status: status,
          foreground: Colors.white,
          background: Colors.white.withValues(alpha: .16),
        ),
        const SizedBox(height: 18),
        Text(
          ticket.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            height: 1.08,
            fontWeight: FontWeight.w800,
            letterSpacing: -.45,
          ),
        ),
        const SizedBox(height: 14),
        _TicketDateTime(
          ticket: ticket,
          foreground: Colors.white.withValues(alpha: .94),
        ),
        if (facts.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (var index = 0; index < facts.length; index++) ...[
            _TicketFact(
              icon: facts[index].icon,
              value: facts[index].value,
              color: Colors.white.withValues(alpha: .88),
            ),
            if (index != facts.length - 1) const SizedBox(height: 7),
          ],
        ],
      ],
    );
  }
}

class _CompactTicketCard extends StatelessWidget {
  const _CompactTicketCard({
    required this.ticket,
    required this.palette,
    required this.now,
    required this.onOpen,
    required this.onOpenMedia,
  });

  final Ticket ticket;
  final ViewerPalette palette;
  final DateTime now;
  final VoidCallback onOpen;
  final VoidCallback onOpenMedia;

  @override
  Widget build(BuildContext context) {
    final status = _statusFor(context, ticket, now, palette);
    final semanticLabel = _ticketSemanticLabel(context, ticket, status.label);
    final tone = _ticketTone(ticket, palette);
    final usesLargeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final content = Semantics(
      button: true,
      label: semanticLabel,
      onTap: onOpen,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusChip(
              ticketId: ticket.id,
              status: status,
              foreground: tone,
              background: tone.withValues(alpha: .10),
            ),
            const SizedBox(height: 10),
            Text(
              ticket.label,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 17,
                height: 1.18,
                fontWeight: FontWeight.w700,
                letterSpacing: -.18,
              ),
            ),
            const SizedBox(height: 8),
            _TicketDateTime(
              ticket: ticket,
              foreground: palette.textSecondary,
            ),
          ],
        ),
      ),
    );
    final media = TicketMediaButton(
      ticket: ticket,
      foreground: tone,
      background: tone.withValues(alpha: .09),
      onPressed: onOpenMedia,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: tone.withValues(alpha: .24)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('ticket-wallet-card-press-${ticket.id}'),
            onTap: onOpen,
            excludeFromSemantics: true,
            splashFactory: NoSplash.splashFactory,
            overlayColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.pressed)
                  ? tone.withValues(alpha: .08)
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 15, 10, 12),
              child: usesLargeText
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        content,
                        const SizedBox(height: 10),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: media,
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: content),
                        const SizedBox(width: 8),
                        media,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingTicketRow extends StatelessWidget {
  const _PendingTicketRow({
    required this.ticket,
    required this.palette,
    required this.now,
    required this.onOpen,
    required this.onOpenMedia,
  });

  final Ticket ticket;
  final ViewerPalette palette;
  final DateTime now;
  final VoidCallback onOpen;
  final VoidCallback onOpenMedia;

  @override
  Widget build(BuildContext context) {
    final status = _statusFor(context, ticket, now, palette);
    final semanticLabel = _ticketSemanticLabel(context, ticket, status.label);
    final usesLargeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final content = Semantics(
      button: true,
      label: semanticLabel,
      onTap: onOpen,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ticket.label,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 16,
                height: 1.22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _StatusLine(
              ticketId: ticket.id,
              status: status,
              palette: palette,
            ),
            const SizedBox(height: 6),
            _TicketDateTime(
              ticket: ticket,
              foreground: palette.textSecondary,
            ),
          ],
        ),
      ),
    );
    final media = TicketMediaButton(
      ticket: ticket,
      foreground: palette.textSecondary,
      background: palette.bg,
      onPressed: onOpenMedia,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('ticket-wallet-card-press-${ticket.id}'),
        onTap: onOpen,
        excludeFromSemantics: true,
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.pressed)
              ? palette.accent.withValues(alpha: .07)
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          child: usesLargeText
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    content,
                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: media,
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: content),
                    const SizedBox(width: 8),
                    media,
                  ],
                ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, required this.palette});

  final String text;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          color: palette.textSecondary,
          fontSize: 13,
          height: 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: .12,
        ),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.ticketId,
    required this.status,
    required this.foreground,
    required this.background,
  });

  final String ticketId;
  final _TicketStatus status;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                status.icon,
                key: ValueKey('ticket-status-icon-$ticketId'),
                size: 15,
                color: foreground,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  status.label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.ticketId,
    required this.status,
    required this.palette,
  });

  final String ticketId;
  final _TicketStatus status;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              status.icon,
              key: ValueKey('ticket-status-icon-$ticketId'),
              size: 16,
              color: status.tone,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              status.label,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
}

class _TicketDateTime extends StatelessWidget {
  const _TicketDateTime({required this.ticket, required this.foreground});

  final Ticket ticket;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final date = _ticketDateLabel(context, ticket.visitDate);
    final time = _nonEmpty(ticket.entryTime);
    if (date == null && time == null) return const SizedBox.shrink();
    return Wrap(
      spacing: 12,
      runSpacing: 7,
      children: [
        if (date != null)
          _InlineFact(
            icon: Icons.calendar_today_rounded,
            value: date,
            color: foreground,
          ),
        if (time != null)
          _InlineFact(
            icon: Icons.schedule_rounded,
            value: time,
            color: foreground,
          ),
      ],
    );
  }
}

class _InlineFact extends StatelessWidget {
  const _InlineFact(
      {required this.icon, required this.value, required this.color});

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}

class _TicketFact extends StatelessWidget {
  const _TicketFact(
      {required this.icon, required this.value, required this.color});

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 13,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
}

class _TicketStatus {
  const _TicketStatus(
      {required this.label, required this.icon, required this.tone});

  final String label;
  final IconData icon;
  final Color tone;
}

class _TicketFactData {
  const _TicketFactData(this.icon, this.value);

  final IconData icon;
  final String value;
}

_TicketStatus _statusFor(
  BuildContext context,
  Ticket ticket,
  DateTime now,
  ViewerPalette palette,
) {
  final s = LanguageScope.of(context);
  if (ticket.purchased) {
    return _TicketStatus(
      label: s.s('ticketWallet.status.ready'),
      icon: Icons.check_circle_rounded,
      tone: palette.matcha,
    );
  }

  final bookingDate = _ticketDate(ticket.bookingOpens);
  if (bookingDate != null) {
    final days = bookingDate.difference(_dateOnly(now)).inDays;
    if (days > 1) {
      return _TicketStatus(
        label: s.p('ticketWallet.status.saleInDays', {'count': '$days'}),
        icon: Icons.event_rounded,
        tone: palette.gold,
      );
    }
    if (days == 1) {
      return _TicketStatus(
        label: s.s('ticketWallet.status.saleTomorrow'),
        icon: Icons.event_rounded,
        tone: palette.gold,
      );
    }
    if (days == 0) {
      return _TicketStatus(
        label: s.s('ticketWallet.status.saleToday'),
        icon: Icons.event_available_rounded,
        tone: palette.gold,
      );
    }
    return _TicketStatus(
      label: s.s('ticketWallet.status.pending'),
      icon: Icons.schedule_rounded,
      tone: palette.gold,
    );
  }

  if (_ticketDate(ticket.visitDate) == null &&
      _nonEmpty(ticket.entryTime) == null) {
    return _TicketStatus(
      label: s.s('ticketWallet.status.missingInfo'),
      icon: Icons.info_outline_rounded,
      tone: palette.sunset,
    );
  }

  return _TicketStatus(
    label: s.s('ticketWallet.status.pending'),
    icon: Icons.schedule_rounded,
    tone: palette.gold,
  );
}

String _ticketSemanticLabel(
  BuildContext context,
  Ticket ticket,
  String status,
) {
  final s = LanguageScope.of(context);
  final details = <String>[
    if (_ticketDateLabel(context, ticket.visitDate) case final date?) date,
    if (_nonEmpty(ticket.entryTime) case final time?) time,
  ];
  if (details.isEmpty) {
    return s.p('ticketWallet.semantic.summaryNoDetails', {
      'name': ticket.label,
      'status': status,
    });
  }
  return s.p('ticketWallet.semantic.summary', {
    'name': ticket.label,
    'details': details.join(s.s('ticketWallet.semantic.separator')),
    'status': status,
  });
}

String? _ticketDateLabel(BuildContext context, String? raw) {
  final date = _ticketDate(raw);
  if (date == null) return null;
  final s = LanguageScope.of(context);
  return s.p('ticketWallet.date', {
    'day': '${date.day}',
    'month': L10n.monthsShortFor(s.lang)[date.month],
    'year': '${date.year}',
  });
}

List<_TicketFactData> _factsFor(Ticket ticket) {
  final facts = <_TicketFactData>[];
  for (final detail in ticket.confirmedDetails) {
    final value = _nonEmpty(detail.value);
    if (value == null) continue;
    switch (detail.semanticKey) {
      case 'venue':
        facts.add(_TicketFactData(Icons.location_on_outlined, value));
        break;
      case 'partySize':
        facts.add(_TicketFactData(Icons.group_outlined, value));
        break;
    }
  }
  return facts;
}

List<Color> _featuredColors(Ticket ticket, ViewerPalette palette) {
  final kind = ticket.kind.toLowerCase();
  if (kind.contains('train') ||
      kind.contains('rail') ||
      kind.contains('shinkansen')) {
    return [palette.sky, palette.fuji];
  }
  if (kind.contains('theme') ||
      kind.contains('disney') ||
      kind.contains('usj') ||
      kind.contains('teamlab')) {
    return [palette.sakura, palette.fuji];
  }
  return [palette.accent, palette.accentStrong];
}

Color _ticketTone(Ticket ticket, ViewerPalette palette) =>
    _featuredColors(ticket, palette).first;

DateTime? _ticketDate(String? raw) {
  final value = _nonEmpty(raw);
  if (value == null) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
