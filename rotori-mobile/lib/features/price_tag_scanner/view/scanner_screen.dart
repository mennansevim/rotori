import 'dart:io' show File;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../plans/premium_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/tag_scanner_client.dart';
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
                isLimitReached: state.isLimitReached,
                remaining: state.dailyLimitRemaining ?? 10,
                maxScans: _premiumNow(ref, state) ? 100 : 10,
                isPremium: _premiumNow(ref, state),
                onPremiumTap: () => _showPremiumSheet(context),
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
    // iOS'ta boyut takası sorun çıkarabiliyor — direkt CameraPreview kullan.
    return CameraPreview(controller);
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
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
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
    );
  }
}

class _LockDots extends StatelessWidget {
  const _LockDots({required this.locked});

  final bool locked;

  @override
  Widget build(BuildContext context) {
    final color = locked ? const Color(0xFFA5D6A7) : const Color(0xFFFFE082);
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
    this.isLimitReached = false,
    this.remaining = 0,
    this.maxScans = 10,
    this.isPremium = false,
    this.onPremiumTap,
  });

  final bool canCapture;
  final bool hasModel;
  final VoidCallback onCapture;
  final bool isLimitReached;
  final int remaining;
  final int maxScans;
  final bool isPremium;
  final VoidCallback? onPremiumTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLimitReached)
              _LimitReachedCard(
                  onPremiumTap: onPremiumTap, isPremium: isPremium)
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isPremium
                          ? const Color(0xFFFFD700).withValues(alpha: 0.2)
                          : remaining <= 3
                              ? const Color(0xFFFFAB91).withValues(alpha: 0.2)
                              : const Color(0xFFA5D6A7).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isPremium
                          ? 'Premium $remaining/$maxScans'
                          : 'Ücretsiz $remaining/$maxScans',
                      style: TextStyle(
                        color: isPremium
                            ? const Color(0xFFFFD700)
                            : remaining <= 3
                                ? const Color(0xFFFFAB91)
                                : const Color(0xFFA5D6A7),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (!isPremium) ...[
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: onPremiumTap,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFFFD700).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: const Color(0xFFFFD700)
                                  .withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          'Premium 100/gün →',
                          style: TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
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
            ],
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
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 1.4),
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

/// Günlük tarama limiti dolduğunda gösterilen premium teklif kartı.
class _LimitReachedCard extends StatelessWidget {
  const _LimitReachedCard({this.onPremiumTap, this.isPremium = false});
  final VoidCallback? onPremiumTap;
  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    final title = isPremium ? 'Premium limit doldu' : 'Günlük limit doldu';
    final subtitle = isPremium
        ? 'Premium 100/100 · Yarın yenilenir'
        : 'Ücretsiz 10/10 · Premium\'da 100/gün';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color:
                (isPremium ? const Color(0xFFFFD700) : const Color(0xFFFFAB91))
                    .withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (isPremium
                          ? const Color(0xFFFFD700)
                          : const Color(0xFFFFAB91))
                      .withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                    isPremium
                        ? Icons.auto_awesome_rounded
                        : Icons.hourglass_empty_rounded,
                    size: 20,
                    color: isPremium
                        ? const Color(0xFFFFD700)
                        : const Color(0xFFFFAB91)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          if (!isPremium) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onPremiumTap,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                label: const Text('Premium\'a geç',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Premium bilgilendirme bottom sheet'i.
void _showPremiumSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1B1B1F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  size: 28, color: Color(0xFFFFD700)),
            ),
            const SizedBox(height: 14),
            const Text('Rotori Premium',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text(
              'Günlük 100 tarama hakkı. Fiyat etiketi tarayıcısını limitsiz kullan, '
              'istediğin kadar ürün sorgula.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Color(0xFFCFD8DC), fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            const _PremiumFeatureRow(
                icon: Icons.check_circle_rounded,
                text: 'Günlük 100 tarama (ücretsiz: 10)'),
            const _PremiumFeatureRow(
                icon: Icons.check_circle_rounded,
                text: 'GPT-4o-mini ile akıllı model tespiti'),
            const _PremiumFeatureRow(
                icon: Icons.check_circle_rounded,
                text: 'Trendyol, HB, Amazon canlı fiyat karşılaştırma'),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Kapat',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PremiumFeatureRow extends StatelessWidget {
  const _PremiumFeatureRow({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFFA5D6A7)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: Color(0xFFECEFF1), fontSize: 13.5))),
        ],
      ),
    );
  }
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
                          Row(
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
                              if (state.llmResult != null &&
                                  !state.isLlmFallback) ...[
                                const SizedBox(width: 6),
                                _LlmBadge(
                                    confidence: state.llmResult!.confidence),
                              ],
                              if (state.isLlmFallback) ...[
                                const SizedBox(width: 6),
                                const _FallbackBadge(),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          if (state.resolvedBrand != null)
                            Text(
                              state.resolvedBrand!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF90CAF9),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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
                // LLM'in tespit ettiği ikincil fiyatlar (kasko, garanti, aksesuar).
                if (state.secondaryPrices.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _SecondaryPricesSection(prices: state.secondaryPrices),
                ],

                if (model != '—') ...[
                  const SizedBox(height: 12),
                  _ManualSearchRow(model: model),
                ],
                const SizedBox(height: 14),
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

/// Tespit edilen modelle manuel arama butonları.
class _ManualSearchRow extends StatelessWidget {
  const _ManualSearchRow({required this.model});
  final String model;

  @override
  Widget build(BuildContext context) {
    final q = Uri.encodeQueryComponent(model);
    final searches = <({String label, IconData icon, String url})>[
      (
        label: 'Trendyol',
        icon: Icons.shopping_bag_outlined,
        url: 'https://www.trendyol.com/sr?q=$q'
      ),
      (
        label: 'Hepsiburada',
        icon: Icons.store_outlined,
        url: 'https://www.hepsiburada.com/ara?q=$q'
      ),
      (
        label: 'Amazon TR',
        icon: Icons.local_shipping_outlined,
        url: 'https://www.amazon.com.tr/s?k=$q'
      ),
      (
        label: 'Google',
        icon: Icons.search,
        url: 'https://www.google.com/search?q=$q+site:com.tr'
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fiyat araştır',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5),
          ),
          const SizedBox(height: 2),
          Text(
            'Model: $model',
            style: const TextStyle(
                color: Color(0xFF80D8FF),
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in searches)
                Material(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _openSearch(s.url),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(s.icon,
                              size: 14, color: const Color(0xFF80D8FF)),
                          const SizedBox(width: 6),
                          Text(s.label,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// LLM'in asıl üründen ayırdığı ikincil fiyatlar (kasko, garanti vb.).
class _SecondaryPricesSection extends StatelessWidget {
  const _SecondaryPricesSection({required this.prices});

  final List<PriceItem> prices;

  String _categoryLabel(PriceCategory cat) {
    switch (cat) {
      case PriceCategory.warranty:
        return 'Garanti';
      case PriceCategory.accessory:
        return 'Aksesuar';
      case PriceCategory.tax:
        return 'Vergi';
      case PriceCategory.point:
        return 'Puan';
      case PriceCategory.discount:
        return 'İndirim';
      default:
        return 'Diğer';
    }
  }

  Color _categoryColor(PriceCategory cat) {
    switch (cat) {
      case PriceCategory.warranty:
        return const Color(0xFFFFAB91);
      case PriceCategory.accessory:
        return const Color(0xFFCE93D8);
      case PriceCategory.tax:
        return const Color(0xFF80CBC4);
      case PriceCategory.point:
        return const Color(0xFFFFE082);
      case PriceCategory.discount:
        return const Color(0xFFA5D6A7);
      default:
        return const Color(0xFFB0BEC5);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: Colors.amber),
              SizedBox(width: 6),
              Text(
                'DİĞER FİYATLAR (asıl ürün değil)',
                style: TextStyle(
                  color: Color(0xFFFFCC80),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...prices.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color:
                            _categoryColor(p.category).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _categoryLabel(p.category),
                        style: TextStyle(
                          color: _categoryColor(p.category),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p.label.isNotEmpty ? p.label : '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFCFD8DC),
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    Text(
                      formatJpy(p.amountJpy),
                      style: const TextStyle(
                        color: Color(0xFFCFD8DC),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

/// LLM güven skoru rozeti.
class _LlmBadge extends StatelessWidget {
  const _LlmBadge({required this.confidence});

  final double confidence;

  @override
  Widget build(BuildContext context) {
    final pct = (confidence * 100).round();
    final color = pct >= 85
        ? const Color(0xFFA5D6A7)
        : pct >= 65
            ? const Color(0xFFFFE082)
            : const Color(0xFFFFAB91);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            'AI %$pct',
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// TagParser fallback rozeti (LLM başarısız olduğunda gösterilir).
class _FallbackBadge extends StatelessWidget {
  const _FallbackBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.rule_rounded, size: 11, color: Colors.amber),
          SizedBox(width: 3),
          Text(
            'regex',
            style: TextStyle(
              color: Color(0xFFFFCC80),
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Premium durumu: canlı bayrak (drawer anahtarı) VEYA sunucudan gelen
/// yetkilendirme. Ekran controller'ın açılışta aldığı tek seferlik
/// snapshot'a bağlı kalmasın diye provider da okunuyor.
bool _premiumNow(WidgetRef ref, ScannerState state) =>
    ref.watch(premiumProvider) || state.isPremiumUser == true;
