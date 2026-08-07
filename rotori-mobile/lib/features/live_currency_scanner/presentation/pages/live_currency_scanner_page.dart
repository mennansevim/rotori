import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:ui' as ui;

import '../../../../core/l10n.dart';
import '../../../viewer/viewer_theme.dart';
import '../../application/live_currency_scanner_controller.dart';
import '../../application/live_currency_scanner_state.dart';
import '../../domain/currency_code.dart';
import '../../domain/product_price_query.dart';
import '../format/money_format.dart';
import '../../application/providers.dart';
import '../widgets/camera_currency_overlay.dart';
import '../widgets/camera_permission_view.dart';

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
    _enterImmersiveCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(liveCurrencyScannerControllerProvider.notifier).init();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restoreSystemUi();
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
              if (state.isLive)
                Positioned.fill(
                  child: CameraCurrencyOverlay(
                    tracks: state.trackedPrices,
                    imageSize: state.imageSize,
                    rotationDegrees: state.rotationDegrees,
                    mirrored: state.mirrored,
                    rate: state.exchangeRate,
                    settings: settings,
                    palette: palette,
                    queryCandidate: state.productQueryCandidate,
                  ),
                ),
              if (state.isLive &&
                  !state.isProductQuerySheetVisible &&
                  state.productQueryCandidate != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _QueryCallToActionCard(
                    candidate: state.productQueryCandidate!,
                    palette: palette,
                    onTap: controller.startProductPriceQuery,
                  ),
                ),
              if (state.isProductQuerySheetVisible)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _ProductPriceQuerySheet(
                    scannerState: state,
                    palette: palette,
                    onClose: controller.closeProductPriceQuerySheet,
                  ),
                ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10, right: 12),
                    child: _CloseCameraButton(onClose: () => _back(context)),
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

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/plans');
    }
  }

  Future<void> _enterImmersiveCamera() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: const <SystemUiOverlay>[],
    );
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}

class _CloseCameraButton extends StatelessWidget {
  const _CloseCameraButton({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final label = s.s('scanner.closeCamera');
    return Semantics(
      label: label,
      button: true,
      child: Tooltip(
        message: label,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Material(
              color: Colors.white.withValues(alpha: 0.14),
              child: InkWell(
                onTap: onClose,
                child: Ink(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
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

class _QueryCallToActionCard extends StatelessWidget {
  const _QueryCallToActionCard({
    required this.candidate,
    required this.palette,
    required this.onTap,
  });

  final ProductQueryCandidate candidate;
  final ViewerPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.52),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.s('scanner.market.queryReadyBadge'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFD8F3FF),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        candidate.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${s.s('scanner.market.jpReference')}: ${MoneyFormat.jpy(candidate.amountInJpy)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xC8FFFFFF),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.query_stats_rounded, size: 17),
                  label: Text(
                    s.s('scanner.market.queryCta'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductPriceQuerySheet extends StatelessWidget {
  const _ProductPriceQuerySheet({
    required this.scannerState,
    required this.palette,
    required this.onClose,
  });

  final LiveCurrencyScannerState scannerState;
  final ViewerPalette palette;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final candidate = scannerState.activeProductQueryCandidate ??
        scannerState.productQueryCandidate;
    final comparison = scannerState.productPriceComparison;

    final isLoading =
        scannerState.productQueryStatus == ProductPriceQueryStatus.loading;
    final isFailed =
        scannerState.productQueryStatus == ProductPriceQueryStatus.failed;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.68),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.s(
                          isLoading
                              ? 'scanner.market.loadingTitle'
                              : 'scanner.market.resultsTitle',
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      tooltip: s.s('scanner.market.close'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                if (candidate != null) ...[
                  Text(
                    candidate.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xE8FFFFFF),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${s.s('scanner.market.jpReference')}: ${MoneyFormat.jpy(candidate.amountInJpy)}',
                    style: const TextStyle(
                      color: Color(0xB5FFFFFF),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                for (final row in scannerState.productQueryProgress)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _SourceProgressRow(
                      row: row,
                      palette: palette,
                    ),
                  ),
                if (isFailed) ...[
                  Text(
                    s.s(scannerState.productQueryErrorMessageKey ??
                        'scanner.market.error.noResults'),
                    style: const TextStyle(
                      color: Color(0xFFFFCDD2),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (comparison != null) ...[
                  _ComparisonSummaryCard(
                    comparison: comparison,
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  s.s('scanner.market.estimatedHint'),
                  style: const TextStyle(
                    color: Color(0xA8FFFFFF),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceProgressRow extends StatelessWidget {
  const _SourceProgressRow({
    required this.row,
    required this.palette,
  });

  final ProductPriceSourceProgress row;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final sourceLabel = s.s('scanner.market.source.${row.source.id}');
    final quote = row.quote;

    Widget trailing;
    switch (row.status) {
      case ProductPriceSourceStatus.pending:
        trailing = Text(
          s.s('scanner.market.status.pending'),
          style: const TextStyle(color: Color(0xB0FFFFFF), fontSize: 11.5),
        );
        break;
      case ProductPriceSourceStatus.loading:
        trailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: palette.accent,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              s.s('scanner.market.status.loading'),
              style: const TextStyle(color: Color(0xB0FFFFFF), fontSize: 11.5),
            ),
          ],
        );
        break;
      case ProductPriceSourceStatus.success:
        if (quote == null) {
          trailing = const Text(
            '—',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          );
        } else {
          trailing = Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                MoneyFormat.format(quote.priceTry, CurrencyCode.tryl),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (quote.isEstimated)
                    _StatusMetaBadge(label: s.s('scanner.market.estimatedBadge')),
                  if (quote.isEstimated) const SizedBox(width: 6),
                  Text(
                    '${s.s('scanner.market.confidence')}: ${(quote.confidence * 100).round()}%',
                    style: const TextStyle(
                      color: Color(0xB8FFFFFF),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          );
        }
        break;
      case ProductPriceSourceStatus.failed:
        trailing = Text(
          s.s('scanner.market.status.failed'),
          style: const TextStyle(
            color: Color(0xFFFFCDD2),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        );
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              sourceLabel,
              style: const TextStyle(
                color: Color(0xE8FFFFFF),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _StatusMetaBadge extends StatelessWidget {
  const _StatusMetaBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xD2FFFFFF),
          fontSize: 9.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ComparisonSummaryCard extends StatelessWidget {
  const _ComparisonSummaryCard({
    required this.comparison,
  });

  final ProductPriceComparison comparison;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final diff = comparison.differenceTry;
    final diffPercent = comparison.clampedDifferencePercent();
    final positive = comparison.isJapanCheaper;
    final diffColor =
        positive ? const Color(0xFFA5D6A7) : const Color(0xFFFFCDD2);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.s('scanner.market.summaryTitle'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _SummaryLine(
            label: s.s('scanner.market.trMedian'),
            value: MoneyFormat.format(comparison.turkeyMedianTry, CurrencyCode.tryl),
          ),
          _SummaryLine(
            label: s.s('scanner.market.trMin'),
            value: MoneyFormat.format(comparison.turkeyMinTry, CurrencyCode.tryl),
          ),
          _SummaryLine(
            label: s.s('scanner.market.trMax'),
            value: MoneyFormat.format(comparison.turkeyMaxTry, CurrencyCode.tryl),
          ),
          _SummaryLine(
            label: s.s('scanner.market.jpReference'),
            value: MoneyFormat.format(comparison.japanPriceTry, CurrencyCode.tryl),
          ),
          _SummaryLine(
            label: s.s('scanner.market.diff'),
            value:
                '${diff >= 0 ? '+' : '-'}${MoneyFormat.format(diff.abs(), CurrencyCode.tryl)} (${diffPercent >= 0 ? '+' : ''}${diffPercent.toStringAsFixed(1)}%)',
            valueColor: diffColor,
          ),
          const SizedBox(height: 8),
          Text(
            positive
                ? s.s('scanner.market.cheaperInJapan')
                : s.s('scanner.market.expensiveInJapan'),
            style: TextStyle(
              color: diffColor,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xBCFFFFFF),
                fontSize: 11.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: 12.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
