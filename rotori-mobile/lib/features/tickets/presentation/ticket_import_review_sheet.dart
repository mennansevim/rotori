import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/types.dart';
import '../../viewer/viewer_theme.dart';
import '../domain/ticket_import_models.dart';

class TicketReviewResult {
  const TicketReviewResult(this.ticket);

  final Ticket ticket;
}

Future<TicketReviewResult?> showTicketImportReviewSheet({
  required BuildContext context,
  required TicketExtractionResult extraction,
  required Ticket initialTicket,
  required ViewerPalette palette,
}) {
  return showModalBottomSheet<TicketReviewResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: _sheetAnimationStyle(context),
    builder: (_) => TicketImportReviewSheet(
      extraction: extraction,
      initialTicket: initialTicket,
      palette: palette,
    ),
  );
}

class TicketImportReviewSheet extends StatefulWidget {
  const TicketImportReviewSheet({
    super.key,
    required this.extraction,
    required this.initialTicket,
    required this.palette,
  });

  final TicketExtractionResult extraction;
  final Ticket initialTicket;
  final ViewerPalette palette;

  @override
  State<TicketImportReviewSheet> createState() =>
      _TicketImportReviewSheetState();
}

class _TicketImportReviewSheetState extends State<TicketImportReviewSheet> {
  late final List<_EditableCandidate> _candidates = widget.extraction.candidates
      .map(_EditableCandidate.new)
      .toList(growable: true);
  late final TextEditingController _labelController;
  final List<_ManualDetail> _manualDetails = [];
  String? _selectedDateId;
  String? _selectedTimeId;
  var _purchased = false;

  ViewerPalette get p => widget.palette;

  @override
  void initState() {
    super.initState();
    final extractedLabel = _candidates
        .where((candidate) => candidate.type == TicketCandidateType.label)
        .map((candidate) => candidate.controller.text.trim())
        .where((value) => value.isNotEmpty)
        .firstOrNull;
    _labelController = TextEditingController(
      text: widget.initialTicket.label.trim().isNotEmpty
          ? widget.initialTicket.label
          : extractedLabel ?? '',
    )..addListener(_onChanged);

    final times = _ofType(TicketCandidateType.time);
    if (times.length == 1) {
      _selectedTimeId = times.single.id;
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    for (final candidate in _candidates) {
      candidate.dispose();
    }
    for (final detail in _manualDetails) {
      detail.dispose();
    }
    super.dispose();
  }

  List<_EditableCandidate> _ofType(TicketCandidateType type) => _candidates
      .where((candidate) => candidate.type == type)
      .toList(growable: false);

  bool get _requiresDateSelection =>
      _ofType(TicketCandidateType.date).isNotEmpty;

  bool get _canSave =>
      _labelController.text.trim().isNotEmpty &&
      (!_requiresDateSelection || _selectedDateId != null);

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _removeCandidate(_EditableCandidate candidate) {
    setState(() {
      if (_selectedDateId == candidate.id) _selectedDateId = null;
      if (_selectedTimeId == candidate.id) _selectedTimeId = null;
      _candidates.remove(candidate);
      candidate.dispose();
    });
  }

  void _addDetail() {
    setState(() => _manualDetails.add(_ManualDetail()));
  }

  void _save() {
    final ticketJson = widget.initialTicket.toJson()..remove('scannedText');
    final ticket = Ticket.fromJson(ticketJson);
    ticket.label = _labelController.text.trim();
    ticket.purchased = _purchased;

    final dates = _ofType(TicketCandidateType.date);
    if (dates.isNotEmpty) {
      ticket.visitDate = _selectedValue(_selectedDateId, dates);
    }
    final times = _ofType(TicketCandidateType.time);
    if (times.isNotEmpty) {
      ticket.entryTime = _selectedValue(_selectedTimeId, times);
    }
    final urls = _ofType(TicketCandidateType.url)
        .where((candidate) => candidate.accepted)
        .toList(growable: false);
    if (urls.isNotEmpty) ticket.url = urls.first.controller.text.trim();

    final s = LanguageScope.of(context);
    ticket.confirmedDetails = [
      for (final candidate in _candidates)
        if (candidate.accepted && _isDetailCandidate(candidate.type))
          _ticketDetailFor(
            candidate,
            label: s.s('ticketReview.candidate.${candidate.type.name}'),
          ),
      for (final detail in _manualDetails)
        if (detail.label.text.trim().isNotEmpty &&
            detail.value.text.trim().isNotEmpty)
          TicketDetail(
            id: 'manual:${_normalize(detail.label.text)}:${_normalize(detail.value.text)}',
            label: detail.label.text.trim(),
            value: detail.value.text.trim(),
          ),
    ];
    Navigator.of(context).pop(TicketReviewResult(ticket));
  }

  String? _selectedValue(
    String? id,
    List<_EditableCandidate> candidates,
  ) {
    if (id == null) return null;
    return candidates
        .where((candidate) => candidate.id == id)
        .map((candidate) => candidate.controller.text.trim())
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final disableAnimations = MediaQuery.of(context).disableAnimations ||
        MediaQuery.of(context).accessibleNavigation;
    return FractionallySizedBox(
      heightFactor: .9,
      child: Material(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: AnimatedPadding(
          duration: disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      s.s('ticketReview.title'),
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 24,
                        height: 1.12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.s('ticketReview.body'),
                      style: TextStyle(color: p.textSecondary, height: 1.4),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: p.border),
              Expanded(
                child: ListView(
                  key: const ValueKey('ticket-review-scroll'),
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  children: [
                    TextField(
                      key: const ValueKey('ticket-review-label'),
                      controller: _labelController,
                      textInputAction: TextInputAction.done,
                      style: TextStyle(color: p.textPrimary),
                      decoration: _decoration(s.s('ticketReview.label')),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile.adaptive(
                      key: const ValueKey('ticket-review-purchased'),
                      contentPadding: EdgeInsets.zero,
                      value: _purchased,
                      onChanged: (value) => setState(() => _purchased = value),
                      title: Text(
                        s.s('ticketReview.purchased'),
                        style: TextStyle(
                            color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        s.s('ticketReview.purchasedBody'),
                        style: TextStyle(color: p.textSecondary, fontSize: 12),
                      ),
                    ),
                    for (final type in TicketCandidateType.values)
                      if (type != TicketCandidateType.label &&
                          _ofType(type).isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _CandidateGroup(
                          type: type,
                          candidates: _ofType(type),
                          palette: p,
                          selectedId: switch (type) {
                            TicketCandidateType.date => _selectedDateId,
                            TicketCandidateType.time => _selectedTimeId,
                            _ => null,
                          },
                          onSelected: (id) => setState(() {
                            if (type == TicketCandidateType.date) {
                              _selectedDateId = id;
                            }
                            if (type == TicketCandidateType.time) {
                              _selectedTimeId = id;
                            }
                          }),
                          onRemove: _removeCandidate,
                          onAccepted: (candidate, accepted) => setState(
                            () => candidate.accepted = accepted,
                          ),
                          decoration: _decoration,
                        ),
                      ],
                    const SizedBox(height: 18),
                    TextButton.icon(
                      key: const ValueKey('ticket-review-add-detail'),
                      onPressed: _addDetail,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(s.s('ticketReview.addDetail')),
                    ),
                    for (final detail in _manualDetails)
                      _ManualDetailRow(
                        detail: detail,
                        palette: p,
                        labelDecoration:
                            _decoration(s.s('ticketReview.detailLabel')),
                        valueDecoration:
                            _decoration(s.s('ticketReview.detailValue')),
                        onRemove: () => setState(() {
                          _manualDetails.remove(detail);
                          detail.dispose();
                        }),
                      ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: p.card,
                  border: Border(top: BorderSide(color: p.border)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        key: const ValueKey('ticket-review-save'),
                        onPressed: _canSave ? _save : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: p.accent,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(s.s('ticketReview.save')),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: p.textSecondary),
        filled: true,
        fillColor: p.elevated,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.border),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      );
}

class _CandidateGroup extends StatelessWidget {
  const _CandidateGroup({
    required this.type,
    required this.candidates,
    required this.palette,
    required this.selectedId,
    required this.onSelected,
    required this.onRemove,
    required this.onAccepted,
    required this.decoration,
  });

  final TicketCandidateType type;
  final List<_EditableCandidate> candidates;
  final ViewerPalette palette;
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final ValueChanged<_EditableCandidate> onRemove;
  final void Function(_EditableCandidate candidate, bool accepted) onAccepted;
  final InputDecoration Function(String label) decoration;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final selectable =
        type == TicketCandidateType.date || type == TicketCandidateType.time;
    final content = Column(
      key: ValueKey('ticket-review-${type.name}-group'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.s('ticketReview.candidate.${type.name}'),
          style: TextStyle(
              color: palette.textPrimary, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        for (final candidate in candidates)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: selectable
                ? RadioListTile<String>(
                    key: ValueKey('ticket-review-${type.name}-${candidate.id}'),
                    value: candidate.id,
                    contentPadding:
                        const EdgeInsetsDirectional.only(start: 4, end: 4),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: TextField(
                      controller: candidate.controller,
                      style: TextStyle(color: palette.textPrimary),
                      decoration: decoration(s.s('ticketReview.value')),
                    ),
                    subtitle: candidate.needsReview
                        ? Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(
                              s.s('ticketReview.needsReview'),
                              style:
                                  TextStyle(color: palette.gold, fontSize: 12),
                            ),
                          )
                        : null,
                    secondary: SizedBox.square(
                      dimension: 44,
                      child: IconButton(
                        tooltip: s.s('ticketReview.remove'),
                        onPressed: () => onRemove(candidate),
                        icon: Icon(Icons.close_rounded,
                            color: palette.textSecondary),
                      ),
                    ),
                  )
                : _DetailCandidateRow(
                    candidate: candidate,
                    palette: palette,
                    decoration: decoration(s.s('ticketReview.value')),
                    onAccepted: (accepted) => onAccepted(candidate, accepted),
                    onRemove: () => onRemove(candidate),
                  ),
          ),
      ],
    );
    return selectable
        ? RadioGroup<String>(
            groupValue: selectedId,
            onChanged: onSelected,
            child: content,
          )
        : content;
  }
}

class _DetailCandidateRow extends StatelessWidget {
  const _DetailCandidateRow({
    required this.candidate,
    required this.palette,
    required this.decoration,
    required this.onAccepted,
    required this.onRemove,
  });

  final _EditableCandidate candidate;
  final ViewerPalette palette;
  final InputDecoration decoration;
  final ValueChanged<bool> onAccepted;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 44,
            child: Checkbox(
              key: ValueKey('ticket-review-accept-${candidate.id}'),
              value: candidate.accepted,
              semanticLabel: LanguageScope.of(context).s('ticketReview.accept'),
              onChanged: (value) => onAccepted(value ?? false),
            ),
          ),
          Expanded(
            child: TextField(
              controller: candidate.controller,
              onChanged: (_) {},
              style: TextStyle(color: palette.textPrimary),
              decoration: decoration,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox.square(
            dimension: 44,
            child: IconButton(
              key: ValueKey('ticket-review-remove-${candidate.id}'),
              tooltip: LanguageScope.of(context).s('ticketReview.remove'),
              onPressed: onRemove,
              icon: Icon(Icons.close_rounded, color: palette.textSecondary),
            ),
          ),
        ],
      );
}

class _ManualDetailRow extends StatelessWidget {
  const _ManualDetailRow({
    required this.detail,
    required this.palette,
    required this.labelDecoration,
    required this.valueDecoration,
    required this.onRemove,
  });

  final _ManualDetail detail;
  final ViewerPalette palette;
  final InputDecoration labelDecoration;
  final InputDecoration valueDecoration;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  TextField(
                    controller: detail.label,
                    style: TextStyle(color: palette.textPrimary),
                    decoration: labelDecoration,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: detail.value,
                    style: TextStyle(color: palette.textPrimary),
                    decoration: valueDecoration,
                  ),
                ],
              ),
            ),
            SizedBox.square(
              dimension: 44,
              child: IconButton(
                onPressed: onRemove,
                icon: Icon(Icons.close_rounded, color: palette.textSecondary),
              ),
            ),
          ],
        ),
      );
}

class _EditableCandidate {
  _EditableCandidate(TicketImportCandidate candidate)
      : id = candidate.id,
        type = candidate.type,
        needsReview = candidate.needsReview,
        accepted = candidate.type != TicketCandidateType.qr,
        controller = TextEditingController(text: candidate.value);

  final String id;
  final TicketCandidateType type;
  final bool needsReview;
  bool accepted;
  final TextEditingController controller;

  void dispose() => controller.dispose();
}

class _ManualDetail {
  final TextEditingController label = TextEditingController();
  final TextEditingController value = TextEditingController();

  void dispose() {
    label.dispose();
    value.dispose();
  }
}

bool _isDetailCandidate(TicketCandidateType type) => switch (type) {
      TicketCandidateType.venue ||
      TicketCandidateType.confirmationCode ||
      TicketCandidateType.seat ||
      TicketCandidateType.gate ||
      TicketCandidateType.partySize ||
      TicketCandidateType.qr =>
        true,
      _ => false,
    };

TicketDetail _ticketDetailFor(
  _EditableCandidate candidate, {
  required String label,
}) {
  final value = candidate.controller.text.trim();
  return TicketDetail(
    id: '${candidate.type.name}:${_normalize(value)}',
    semanticKey: candidate.type.name,
    label: label,
    value: value,
  );
}

String _normalize(String value) =>
    Uri.encodeComponent(value.trim().toLowerCase());

AnimationStyle _sheetAnimationStyle(BuildContext context) {
  final mediaQuery = MediaQuery.of(context);
  if (mediaQuery.disableAnimations || mediaQuery.accessibleNavigation) {
    return const AnimationStyle(
      duration: Duration.zero,
      reverseDuration: Duration.zero,
    );
  }
  return const AnimationStyle(
    duration: Duration(milliseconds: 260),
    reverseDuration: Duration(milliseconds: 220),
  );
}

extension on Iterable<String> {
  String? get firstOrNull => isEmpty ? null : first;
}
