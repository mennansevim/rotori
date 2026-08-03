import 'package:flutter/material.dart';

import '../../../../core/l10n.dart';
import '../../../viewer/viewer_theme.dart';
import '../../application/live_currency_scanner_state.dart';

/// İzin reddi / kamera hatası durumlarını anlatan tam ekran görünüm.
class CameraPermissionView extends StatelessWidget {
  const CameraPermissionView({
    super.key,
    required this.status,
    required this.palette,
    required this.onRetry,
    this.onOpenSettings,
  });

  final ScannerStatus status;
  final ViewerPalette palette;
  final VoidCallback onRetry;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final p = palette;

    final (title, body, icon) = switch (status) {
      ScannerStatus.permissionDenied => (
          s.s('scanner.permTitle'),
          s.s('scanner.permBody'),
          Icons.no_photography_outlined,
        ),
      ScannerStatus.permissionPermanentlyDenied => (
          s.s('scanner.permTitle'),
          s.s('scanner.permDeniedBody'),
          Icons.no_photography_outlined,
        ),
      ScannerStatus.cameraUnavailable => (
          s.s('scanner.cameraUnavailable'),
          s.s('scanner.permBody'),
          Icons.videocam_off_outlined,
        ),
      _ => (
          s.s('scanner.cameraFailed'),
          s.s('scanner.permBody'),
          Icons.error_outline,
        ),
    };

    final permanent = status == ScannerStatus.permissionPermanentlyDenied;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: p.textSecondary),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: p.textSecondary, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 24),
            if (permanent && onOpenSettings != null)
              FilledButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: Text(s.s('scanner.openSettings')),
                style: FilledButton.styleFrom(backgroundColor: p.accent),
              )
            else
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(s.s('scanner.retry')),
                style: FilledButton.styleFrom(backgroundColor: p.accent),
              ),
          ],
        ),
      ),
    );
  }
}
