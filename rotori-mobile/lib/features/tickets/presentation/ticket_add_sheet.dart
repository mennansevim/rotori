import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../viewer/viewer_theme.dart';

enum TicketAddSource { gallery, camera, plan, manual }

Future<TicketAddSource?> showTicketAddSheet({
  required BuildContext context,
  required ViewerPalette palette,
  bool showPlanOption = true,
}) {
  return showModalBottomSheet<TicketAddSource>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: _sheetAnimationStyle(context),
    builder: (sheetContext) => TicketAddSheetBody(
      palette: palette,
      showPlanOption: showPlanOption,
      onSelect: (source) => Navigator.pop(sheetContext, source),
    ),
  );
}

class TicketAddSheetBody extends StatelessWidget {
  const TicketAddSheetBody({
    super.key,
    required this.palette,
    this.showPlanOption = true,
    required this.onSelect,
  });

  final ViewerPalette palette;
  final bool showPlanOption;
  final ValueChanged<TicketAddSource> onSelect;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Material(
      color: palette.card,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.s('ticketAdd.title'),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 24,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.35,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                s.s('ticketAdd.body'),
                style: TextStyle(color: palette.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 20),
              _SourceAction(
                source: TicketAddSource.gallery,
                icon: Icons.photo_library_outlined,
                title: s.s('ticketAdd.gallery'),
                subtitle: s.s('ticketAdd.galleryBody'),
                palette: palette,
                onTap: onSelect,
              ),
              const SizedBox(height: 10),
              _SourceAction(
                source: TicketAddSource.camera,
                icon: Icons.document_scanner_outlined,
                title: s.s('ticketAdd.camera'),
                subtitle: s.s('ticketAdd.cameraBody'),
                palette: palette,
                onTap: onSelect,
              ),
              const SizedBox(height: 18),
              if (showPlanOption) ...[
                _SourceAction(
                  source: TicketAddSource.plan,
                  icon: Icons.map_outlined,
                  title: s.s('ticketAdd.plan'),
                  subtitle: s.s('ticketAdd.planBody'),
                  palette: palette,
                  onTap: onSelect,
                ),
                const SizedBox(height: 10),
              ],
              _SourceAction(
                source: TicketAddSource.manual,
                icon: Icons.edit_note_outlined,
                title: s.s('ticketAdd.manual'),
                subtitle: s.s('ticketAdd.manualBody'),
                palette: palette,
                onTap: onSelect,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceAction extends StatelessWidget {
  const _SourceAction({
    required this.source,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.onTap,
  });

  final TicketAddSource source;
  final IconData icon;
  final String title;
  final String subtitle;
  final ViewerPalette palette;
  final ValueChanged<TicketAddSource> onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      child: SizedBox(
        key: ValueKey('ticket-add-${source.name}'),
        height: 64,
        child: Material(
          color: palette.elevated,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () => onTap(source),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(icon, color: palette.accent, size: 25),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: palette.textMuted),
                ],
              ),
            ),
          ),
        ),
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
