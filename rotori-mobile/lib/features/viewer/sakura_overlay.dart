// Sakura yaprağı yağmuru — hero'nun arkasında sürekli düşen yapraklar.
// React'te yok; mobil viewer'a özel dekoratif katman.
//
// AnimationController (sürekli döngü) + CustomPainter. ~22 yaprak; her biri
// rastgele x, boyut, düşme süresi, yatay salınım, dönüş, opaklık ve palet
// rengi. Hafif (RepaintBoundary) ve dokunmayı engellemez (IgnorePointer).

import 'dart:math' as math;

import 'package:flutter/material.dart';

class SakuraOverlay extends StatefulWidget {
  const SakuraOverlay({
    super.key,
    required this.sakura,
    this.petalCount = 22,
  });

  /// Palet ana sakura rengi (diğer tonlar bundan türetilir).
  final Color sakura;
  final int petalCount;

  @override
  State<SakuraOverlay> createState() => _SakuraOverlayState();
}

class _SakuraOverlayState extends State<SakuraOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Petal> _petals;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random();
    _petals = List.generate(widget.petalCount, (_) => _Petal.random(rnd));
    // 60 sn'lik uzun döngü; her yaprak kendi süresine göre faz alır.
    // repeat() didChangeDependencies'te başlatılır (hareket-azalt ayarına göre).
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Hareketi azalt" (erişilebilirlik) açıksa yapraklar sabit kalır.
    // Bu ayrıca widget testlerinde sonsuz ticker'ı kapatır (deterministik).
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce == _reduceMotion && (reduce || _controller.isAnimating)) return;
    _reduceMotion = reduce;
    if (reduce) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = <Color>[
      widget.sakura,
      const Color(0xFFFFC3D7),
      const Color(0xFFFFE0EC), // daha açık pembe
    ];
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _SakuraPainter(
              petals: _petals,
              t: _controller.value,
              colors: colors,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _Petal {
  _Petal({
    required this.x,
    required this.size,
    required this.fallSeconds,
    required this.phase,
    required this.swayAmp,
    required this.swaySpeed,
    required this.rotSpeed,
    required this.opacity,
    required this.colorIndex,
  });

  final double x; // 0..1 yatay başlangıç
  final double size; // 8..16 px
  final double fallSeconds; // 6..11 sn
  final double phase; // 0..1 başlangıç fazı
  final double swayAmp; // yatay salınım genliği (px)
  final double swaySpeed; // salınım frekansı
  final double rotSpeed; // dönüş hızı
  final double opacity; // 0.5..0.9
  final int colorIndex;

  factory _Petal.random(math.Random r) => _Petal(
        x: r.nextDouble(),
        size: 8 + r.nextDouble() * 8,
        fallSeconds: 6 + r.nextDouble() * 5,
        phase: r.nextDouble(),
        swayAmp: 12 + r.nextDouble() * 26,
        swaySpeed: 1.5 + r.nextDouble() * 2.5,
        rotSpeed: (r.nextBool() ? 1 : -1) * (1 + r.nextDouble() * 2),
        opacity: 0.5 + r.nextDouble() * 0.4,
        colorIndex: r.nextInt(3),
      );
}

class _SakuraPainter extends CustomPainter {
  _SakuraPainter({
    required this.petals,
    required this.t,
    required this.colors,
  });

  final List<_Petal> petals;
  final double t; // 0..1 (60 sn döngü)
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0 || size.width <= 0) return;
    const loopSeconds = 60.0;
    final elapsed = t * loopSeconds;

    for (final p in petals) {
      // Her yaprak kendi düşme süresine göre 0..1 ilerleme.
      final prog = ((elapsed / p.fallSeconds) + p.phase) % 1.0;
      final y = prog * (size.height + 40) - 20;
      final sway =
          math.sin((prog * p.swaySpeed * 2 * math.pi)) * p.swayAmp;
      final x = p.x * size.width + sway;
      final angle = prog * p.rotSpeed * 2 * math.pi;

      final paint = Paint()
        ..color = colors[p.colorIndex].withValues(alpha: p.opacity)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      _drawPetal(canvas, p.size, paint);
      canvas.restore();
    }
  }

  /// Basit yaprak: iki eğrili oval (kiraz çiçeği yaprağı silüeti).
  void _drawPetal(Canvas canvas, double s, Paint paint) {
    final path = Path()
      ..moveTo(0, -s / 2)
      ..quadraticBezierTo(s / 2, -s / 4, s / 3, s / 2)
      ..quadraticBezierTo(0, s / 3, -s / 3, s / 2)
      ..quadraticBezierTo(-s / 2, -s / 4, 0, -s / 2)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SakuraPainter oldDelegate) => oldDelegate.t != t;
}
