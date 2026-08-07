import 'dart:io' show File;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controller/scanner_controller.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterImmersiveMode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(scannerControllerProvider.notifier).init();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _exitImmersiveMode();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(scannerControllerProvider.notifier).handleLifecycle(state);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scannerControllerProvider);
    final controller = ref.read(scannerControllerProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraLayer(state, controller),
          if (state.isLive)
            const Positioned.fill(
              child: IgnorePointer(child: _ViewfinderMask()),
            ),
          if (state.isFrozen)
            const Positioned.fill(
              child: IgnorePointer(child: ColoredBox(color: Color(0x66000000))),
            ),

          // Üst: geri/flaş + kalıcı "sorgulanan ürün" paneli.
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      _GlassIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Geri',
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const Spacer(),
                      if (state.isLive)
                        _GlassIconButton(
                          icon: state.isTorchEnabled
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded,
                          tooltip: 'Flaş',
                          onTap: controller.toggleTorch,
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: _TopModelPanel(
                    state: state,
                    onEdit: () => _editModel(context, controller, state),
                  ),
                ),
              ],
            ),
          ),

          if (state.phase == ScannerPhase.error)
            Center(
              child: _ErrorCard(
                message: state.errorMessage ??
                    'Tarayıcı beklenmeyen bir hatayla durdu.',
                onRetry: controller.retry,
              ),
            )
          else if (state.isLive)
            Align(
              alignment: Alignment.bottomCenter,
              child: _CaptureBar(
                canCapture: state.canCapture,
                hasModel: state.hasModel,
                onCapture: controller.capture,
              ),
            )
          else
            Align(
              alignment: Alignment.bottomCenter,
              child: _FrozenResultPanel(
                state: state,
                onRescan: controller.resumeScanning,
                onEditModel: () => _editModel(context, controller, state),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editModel(
    BuildContext context,
    ScannerController controller,
    ScannerState state,
  ) async {
    final textController =
        TextEditingController(text: state.productModel ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1B1B1F),
          title: const Text(
            'Model kodunu düzelt',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: TextField(
            controller: textController,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
            decoration: const InputDecoration(
              hintText: 'Örn: WH-1000XM5',
              hintStyle: TextStyle(color: Color(0x88FFFFFF)),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0x55FFFFFF)),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF80D8FF)),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(textController.text),
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );

    if (result != null && result.trim().isNotEmpty) {
      await controller.setModelOverride(result);
    }
  }

  Widget _buildCameraLayer(ScannerState state, ScannerController controller) {
    if (state.isFrozen && state.capturedImagePath != null) {
      return Image.file(
        File(state.capturedImagePath!),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black),
      );
    }

    final cam = controller.cameraController;
    if (cam != null && cam.value.isInitialized && state.isCameraReady) {
      return _CoveredPreview(controller: cam);
    }

    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: CircularProgressIndicator(color: Color(0xFF80D8FF)),
      ),
    );
  }

  Future<void> _enterImmersiveMode() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: const <SystemUiOverlay>[],
    );
  }

  Future<void> _exitImmersiveMode() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}

class _CoveredPreview extends StatelessWidget {
  const _CoveredPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return CameraPreview(controller);
    }

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
  }
}

class _ViewfinderMask extends StatelessWidget {
  const _ViewfinderMask();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ViewfinderMaskPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _ViewfinderMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      size.width * kPriceTagViewfinderNormalizedRect.left,
      size.height * kPriceTagViewfinderNormalizedRect.top,
      size.width * kPriceTagViewfinderNormalizedRect.width,
      size.height * kPriceTagViewfinderNormalizedRect.height,
    );
    final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(18));

    final darkLayer = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(rRect),
    );

    canvas.drawPath(
      darkLayer,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.56)
        ..style = PaintingStyle.fill,
    );

    canvas.drawRRect(
      rRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.92),
    );

    final glowRect = rRect.inflate(1.5);
    canvas.drawRRect(
      glowRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8)
        ..color = const Color(0x4480D8FF),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Material(
            color: Colors.white.withValues(alpha: 0.15),
            child: InkWell(
              onTap: onTap,
              child: Ink(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: Icon(icon, size: 18, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopModelPanel extends StatelessWidget {
  const _TopModelPanel({required this.state, required this.onEdit});

  final ScannerState state;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final model = state.productModel;
    final hasModel = model != null && model.isNotEmpty;
    final jpy = state.jpyPrice;
    final tr = state.tryPrice;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasModel
              ? const Color(0xFF80D8FF).withValues(alpha: 0.65)
              : Colors.white.withValues(alpha: 0.16),
          width: hasModel ? 1.4 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      hasModel
                          ? Icons.qr_code_2_rounded
                          : Icons.search_rounded,
                      size: 15,
                      color: const Color(0xFF80D8FF),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasModel ? 'SORGULANAN ÜRÜN' : 'MODEL ARANIYOR…',
                      style: const TextStyle(
                        color: Color(0xFF9BE7FF),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                    if (hasModel) ...[
                      const SizedBox(width: 8),
                      _LockDots(locked: state.isModelLocked),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  hasModel ? model : 'Etiketi çerçeveye alın',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: hasModel ? 20 : 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: hasModel ? 0.5 : 0,
                  ),
                ),
                if (jpy != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${formatJpy(jpy)}  →  ${tr == null ? '—' : formatTry(tr)}  ·  kur 0.22',
                    style: const TextStyle(
                      color: Color(0xFFCFD8DC),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (hasModel)
            IconButton(
              onPressed: onEdit,
              tooltip: 'Modeli düzelt',
              icon: const Icon(Icons.edit_rounded,
                  color: Colors.white, size: 20),
            ),
        ],
      ),
    );
  }
}

class _LockDots extends StatelessWidget {
  const _LockDots({required this.locked});

  final bool locked;

  @override
  Widget build(BuildContext context) {
    final color =
        locked ? const Color(0xFFA5D6A7) : const Color(0xFFFFE082);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          locked ? Icons.check_circle_rounded : Icons.timelapse_rounded,
          size: 13,
          color: color,
        ),
        const SizedBox(width: 3),
        Text(
          locked ? 'kararlı' : 'okunuyor',
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _CaptureBar extends StatelessWidget {
  const _CaptureBar({
    required this.canCapture,
    required this.hasModel,
    required this.onCapture,
  });

  final bool canCapture;
  final bool hasModel;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              hasModel
                  ? 'Modeli yakaladık — çekip fiyatı sorgulayın'
                  : 'Model kodunu çerçeveye hizalayın',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Colors.black, blurRadius: 6)],
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: canCapture ? onCapture : null,
              child: Opacity(
                opacity: canCapture ? 1 : 0.45,
                child: Container(
                  height: 58,
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0090C8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35), width: 1.4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.center_focus_strong_rounded,
                          color: Colors.white, size: 22),
                      SizedBox(width: 10),
                      Text(
                        'Çek & Fiyat Sorgula',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatJpy(int value) => '¥${_groupThousands(value.toString())}';

String formatTry(num value) {
  final rounded = value.toStringAsFixed(2);
  final parts = rounded.split('.');
  final grouped = _groupThousands(parts.first);
  return '₺$grouped.${parts[1]}';
}

Future<void> _openSearch(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

String _groupThousands(String raw) {
  final negative = raw.startsWith('-');
  final digits = negative ? raw.substring(1) : raw;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final fromRight = digits.length - i;
    buffer.write(digits[i]);
    if (fromRight > 1 && fromRight % 3 == 1) {
      buffer.write(',');
    }
  }
  return negative ? '-$buffer' : '$buffer';
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.7)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tarayıcı Hatası',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(color: Color(0xFFECEFF1), fontSize: 13),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Tekrar Dene'),
          ),
        ],
      ),
    );
  }
}

class _FrozenResultPanel extends StatelessWidget {
  const _FrozenResultPanel({
    required this.state,
    required this.onRescan,
    required this.onEditModel,
  });

  final ScannerState state;
  final VoidCallback onRescan;
  final VoidCallback onEditModel;

  @override
  Widget build(BuildContext context) {
    final model = state.productModel ?? '—';
    final jpy = state.jpyPrice;
    final tr = state.tryPrice;
    final isFetching = state.phase == ScannerPhase.fetchingMockPrices;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.52,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'SORGULANAN ÜRÜN',
                            style: TextStyle(
                              color: Color(0xFF9BE7FF),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            model,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onEditModel,
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: const Text('Düzelt'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF80D8FF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _MetricTile(
                        label: 'Japonya Fiyatı',
                        value: jpy == null ? '—' : formatJpy(jpy),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MetricTile(
                        label: 'TL Karşılığı',
                        value: tr == null ? '—' : formatTry(tr),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (isFetching)
                  const Row(
                    children: [
                      SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Hepsiburada, Trendyol ve Amazon TR fiyatları alınıyor…',
                          style: TextStyle(
                            color: Color(0xFFECEFF1),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  )
                else if (state.marketPrices.isNotEmpty) ...[
                  Text(
                    'Türkiye pazar yerleri · tahmini fiyat (mock)',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...state.marketPrices.map((item) {
                    final platform = item['platform']?.toString() ?? '-';
                    final priceRaw = item['priceTry'];
                    final price = priceRaw is num ? priceRaw.toDouble() : 0.0;
                    final inStock = item['inStock'] == true;
                    final url = item['url']?.toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _MarketPriceCard(
                        platform: platform,
                        priceTry: formatTry(price),
                        inStock: inStock,
                        onOpen: url == null ? null : () => _openSearch(url),
                      ),
                    );
                  }),
                  const SizedBox(height: 4),
                  Text(
                    'Fiyatlar demo amaçlı üretilir. "Sitede ara" gerçek arama '
                    'sayfasını açar.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onRescan,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0090C8),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.replay_rounded, size: 20),
                    label: const Text(
                      'Tekrar Tara',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
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

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xB3FFFFFF),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketPriceCard extends StatelessWidget {
  const _MarketPriceCard({
    required this.platform,
    required this.priceTry,
    required this.inStock,
    this.onOpen,
  });

  final String platform;
  final String priceTry;
  final bool inStock;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final stockColor = inStock ? const Color(0xFFA5D6A7) : const Color(0xFFFFCDD2);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      platform,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (onOpen != null) ...[
                      const SizedBox(height: 2),
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Sitede ara',
                            style: TextStyle(
                              color: Color(0xFF80D8FF),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 2),
                          Icon(Icons.north_east_rounded,
                              size: 11, color: Color(0xFF80D8FF)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                priceTry,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: stockColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: stockColor.withValues(alpha: 0.8)),
                ),
                child: Text(
                  inStock ? 'Stokta' : 'Stok yok',
                  style: TextStyle(
                    color: stockColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
