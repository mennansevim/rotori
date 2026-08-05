import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n.dart';
import '../../../viewer/viewer_theme.dart';
import '../../application/live_currency_scanner_controller.dart';
import '../../application/live_currency_scanner_state.dart';
import '../../application/providers.dart';
import '../../domain/currency_converter.dart';
import '../../domain/tracked_price.dart';
import '../format/money_format.dart';
import '../painters/currency_overlay_painter.dart';
import '../widgets/camera_currency_overlay.dart';
import '../widgets/camera_permission_view.dart';
import '../widgets/exchange_rate_status.dart';
import '../widgets/scanner_top_controls.dart';
import 'scanner_settings_page.dart';

/// Canlı para birimi tarayıcı ekranı — tam ekran kamera + fiyat overlay'leri.
class LiveCurrencyScannerPage extends ConsumerStatefulWidget {
  const LiveCurrencyScannerPage({super.key});

  @override
  ConsumerState<LiveCurrencyScannerPage> createState() =>
      _LiveCurrencyScannerPageState();
}

class _LiveCurrencyScannerPageState
    extends ConsumerState<LiveCurrencyScannerPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(liveCurrencyScannerControllerProvider.notifier).init();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref
        .read(liveCurrencyScannerControllerProvider.notifier)
        .handleAppLifecycle(state);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(viewerPaletteProvider);
    final state = ref.watch(liveCurrencyScannerControllerProvider);
    final controller = ref.read(liveCurrencyScannerControllerProvider.notifier);
    final settings = ref.watch(scannerSettingsControllerProvider).settings;
    final s = LanguageScope.of(context);

    return Theme(
      data: palette.toThemeData(),
      child: ViewerPaletteScope(
        palette: palette,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              _cameraLayer(context, state, controller, palette),
              if (state.isLive) ...[
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: CurrencyOverlayPainter(color: palette.accent),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CameraCurrencyOverlay(
                    tracks: state.trackedPrices,
                    imageSize: state.imageSize,
                    rotationDegrees: state.rotationDegrees,
                    mirrored: state.mirrored,
                    rate: state.exchangeRate,
                    settings: settings,
                    palette: palette,
                    onTap: (t) => _showDetail(context, t, palette),
                  ),
                ),
              ],
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      ScannerTopControls(
                        palette: palette,
                        currency: state.targetCurrency,
                        flashEnabled: state.flashEnabled,
                        onBack: () => _back(context),
                        onToggleFlash: controller.toggleFlash,
                        onPickCurrency: controller.setTargetCurrency,
                        onOpenSettings: () => _openSettings(context),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ExchangeRateStatus(
                          rate: state.exchangeRate,
                          freshness: state.rateFreshness,
                          palette: palette,
                        ),
                      ),
                      const Spacer(),
                      if (state.isLive) _bottomHint(context, state, palette, s),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cameraLayer(
    BuildContext context,
    LiveCurrencyScannerState state,
    LiveCurrencyScannerController controller,
    ViewerPalette palette,
  ) {
    switch (state.status) {
      case ScannerStatus.permissionDenied:
      case ScannerStatus.permissionPermanentlyDenied:
      case ScannerStatus.cameraUnavailable:
      case ScannerStatus.failure:
        return ColoredBox(
          color: palette.bg,
          child: CameraPermissionView(
            status: state.status,
            palette: palette,
            onRetry: controller.retry,
            detailText: state.errorMessageKey == null
                ? null
                : LanguageScope.of(context).s(state.errorMessageKey!),
          ),
        );
      case ScannerStatus.ready:
      case ScannerStatus.scanning:
        final cam = controller.cameraController;
        if (cam != null && cam.value.isInitialized) {
          try {
            return _CoveredPreview(controller: cam);
          } catch (e, st) {
            controller.reportUiException('preview_build', e, st);
            return ColoredBox(
              color: palette.bg,
              child: CameraPermissionView(
                status: ScannerStatus.failure,
                palette: palette,
                onRetry: controller.retry,
                detailText: LanguageScope.of(context)
                    .s('scanner.error.previewStability'),
              ),
            );
          }
        }
        return const ColoredBox(color: Colors.black);
      default:
        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: CircularProgressIndicator(color: palette.accent),
        );
    }
  }

  Widget _bottomHint(
    BuildContext context,
    LiveCurrencyScannerState state,
    ViewerPalette palette,
    LanguageScope s,
  ) {
    final text =
        state.hasDetections ? s.s('scanner.detecting') : s.s('scanner.hint');
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${s.s('scanner.onDevice')} · ${s.s('scanner.noUpload')}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 11),
        ),
      ],
    );
  }

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/plans');
    }
  }

  void _openSettings(BuildContext context) {
    final palette = ref.read(viewerPaletteProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: palette.toThemeData(),
          child: ViewerPaletteScope(
            palette: palette,
            child: const ScannerSettingsPage(),
          ),
        ),
      ),
    );
  }

  void _showDetail(
      BuildContext context, TrackedPrice track, ViewerPalette palette) {
    final s = LanguageScope.of(context);
    final settings = ref.read(scannerSettingsControllerProvider).settings;
    final rate = ref.read(liveCurrencyScannerControllerProvider).exchangeRate;
    if (rate == null) return;
    const converter = CurrencyConverter();
    final conversion = converter.convert(
      amountInJpy: track.price.amountInJpy,
      rate: rate,
      settings: settings,
    );
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.bg,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                MoneyFormat.jpy(track.price.amountInJpy),
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                MoneyFormat.format(
                    conversion.convertedAsDouble, settings.targetCurrency),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              _detailRow(
                palette,
                s.s('scanner.rateUsed'),
                '1¥ = ${rate.rate.toDouble().toStringAsFixed(4)} ${settings.targetCurrency.iso}',
              ),
              if (track.price.taxType.isIncluded)
                _detailRow(palette, s.s('scanner.taxIncluded'), '税込'),
              if (track.price.taxType.isExcluded)
                _detailRow(palette, s.s('scanner.taxExcluded'), '税抜'),
              _detailRow(
                palette,
                s.s('scanner.lastUpdated'),
                rate.fetchedAt.toLocal().toString().split('.').first,
              ),
              const SizedBox(height: 12),
              Text(
                '${s.s('scanner.onDevice')} · ${s.s('scanner.noUpload')}',
                style: TextStyle(color: palette.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(ViewerPalette palette, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: palette.textSecondary, fontSize: 14)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kamera preview'ini önizleme kutusuna BoxFit.cover ile sığdırır.
class _CoveredPreview extends StatelessWidget {
  const _CoveredPreview({required this.controller});
  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = controller.value.previewSize;
        if (previewSize == null) return CameraPreview(controller);
        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: previewSize.height,
              height: previewSize.width,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }
}
