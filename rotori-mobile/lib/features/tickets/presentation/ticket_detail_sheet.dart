import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/types.dart';
import '../../viewer/viewer_theme.dart';

enum TicketDetailAction { save, replaceMedia, delete }

class TicketDetailResult {
  const TicketDetailResult({required this.action, this.ticket});

  final TicketDetailAction action;
  final Ticket? ticket;
}

Future<TicketDetailResult?> showTicketDetailSheet({
  required BuildContext context,
  required Ticket ticket,
  required Uint8List? mediaBytes,
  required ViewerPalette palette,
}) {
  return showModalBottomSheet<TicketDetailResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: _sheetAnimationStyle(context),
    builder: (_) => TicketDetailSheet(
      ticket: ticket,
      mediaBytes: mediaBytes,
      palette: palette,
    ),
  );
}

class TicketDetailSheet extends StatefulWidget {
  const TicketDetailSheet({
    super.key,
    required this.ticket,
    required this.mediaBytes,
    required this.palette,
  });

  final Ticket ticket;
  final Uint8List? mediaBytes;
  final ViewerPalette palette;

  @override
  State<TicketDetailSheet> createState() => _TicketDetailSheetState();
}

class _TicketDetailSheetState extends State<TicketDetailSheet> {
  late final TextEditingController _labelController;
  late var _purchased = widget.ticket.purchased;

  ViewerPalette get p => widget.palette;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.ticket.label)
      ..addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final s = LanguageScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.s('ticketDetail.deleteTitle')),
        content: Text(
          s.p('ticketDetail.deleteBody', {'name': widget.ticket.label}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.s('ticketDetail.cancel')),
          ),
          FilledButton(
            key: const ValueKey('ticket-detail-confirm-delete'),
            style: FilledButton.styleFrom(
              backgroundColor: p.sunset,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.s('ticketDetail.deleteConfirm')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(
        const TicketDetailResult(action: TicketDetailAction.delete),
      );
    }
  }

  void _save() {
    final json = widget.ticket.toJson()..remove('scannedText');
    final ticket = Ticket.fromJson(json)
      ..label = _labelController.text.trim()
      ..purchased = _purchased;
    Navigator.of(context).pop(
      TicketDetailResult(action: TicketDetailAction.save, ticket: ticket),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
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
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    s.s('ticketDetail.title'),
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 24,
                      height: 1.12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.35,
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: p.border),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  children: [
                    if (widget.mediaBytes != null) ...[
                      ClipRRect(
                        key: const ValueKey('ticket-detail-media'),
                        borderRadius: BorderRadius.circular(18),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: Image.memory(
                            widget.mediaBytes!,
                            fit: BoxFit.cover,
                            semanticLabel: s.p(
                              'ticketDetail.mediaLabel',
                              {'name': widget.ticket.label},
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else if (widget.ticket.localMediaRef != null) ...[
                      _MissingMedia(
                        palette: p,
                        onReplace: () => Navigator.of(context).pop(
                          const TicketDetailResult(
                            action: TicketDetailAction.replaceMedia,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        key: const ValueKey('ticket-detail-replace-media'),
                        onPressed: () => Navigator.of(context).pop(
                          const TicketDetailResult(
                            action: TicketDetailAction.replaceMedia,
                          ),
                        ),
                        icon: const Icon(Icons.photo_camera_back_outlined),
                        label: Text(s.s('ticketDetail.replaceMedia')),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      key: const ValueKey('ticket-detail-label'),
                      controller: _labelController,
                      style: TextStyle(color: p.textPrimary),
                      decoration: _decoration(s.s('ticketDetail.label')),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _purchased,
                      onChanged: (value) => setState(() => _purchased = value),
                      title: Text(
                        s.s('ticketDetail.purchased'),
                        style: TextStyle(
                            color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final detail in widget.ticket.confirmedDetails)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          detail.label,
                          style:
                              TextStyle(color: p.textSecondary, fontSize: 13),
                        ),
                        subtitle: Text(
                          detail.value,
                          style: TextStyle(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        key: const ValueKey('ticket-detail-delete'),
                        onPressed: _confirmDelete,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: p.sunset,
                          side: BorderSide(
                              color: p.sunset.withValues(alpha: .45)),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text(s.s('ticketDetail.delete')),
                      ),
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
                        key: const ValueKey('ticket-detail-save'),
                        onPressed:
                            _labelController.text.trim().isEmpty ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: p.accent,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(s.s('ticketDetail.save')),
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

class _MissingMedia extends StatelessWidget {
  const _MissingMedia({required this.palette, required this.onReplace});

  final ViewerPalette palette;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.elevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(Icons.broken_image_outlined, color: palette.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              s.s('ticketDetail.reattachMedia'),
              style: TextStyle(
                  color: palette.textPrimary, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
              onPressed: onReplace, child: Text(s.s('ticketDetail.reattach'))),
        ],
      ),
    );
  }
}

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
