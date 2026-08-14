// Plan üretimi sırasında gösterilen marka animasyonu.
//
// Rotori tanıtım animasyonundaki sırayı izler: önce torii çizilir, sonra
// ALTINDAN ROTA akar — logonun kendisi de bu iki parçadan oluşuyor
// (assets/images/rotori-logo.png). Rota kavisi, kırmızı kurdelenin yol olup
// açılmasının sadeleştirilmiş hâli.
//
// Neden vektör: PNG logo ölçeklenir ama ÇİZİLEMEZ. "Rota oluşuyor" hissi
// stroke'un ilerlemesinden geliyor, o yüzden mark elde Path olarak kuruldu.

import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../core/rotori_brand.dart';
import '../../viewer/viewer_theme.dart';

/// Marka torii + rota animasyonu. Süresiz döner; üretim bitince kaldırılır.
class RotoriRouteLoader extends StatefulWidget {
  const RotoriRouteLoader({
    super.key,
    required this.palette,
    this.size = 132,
    this.message,
  });

  final ViewerPalette palette;
  final double size;

  /// Altta gösterilen metin. Boş bırakılırsa yalnız mark çizilir.
  final String? message;

  @override
  State<RotoriRouteLoader> createState() => _RotoriRouteLoaderState();
}

class _RotoriRouteLoaderState extends State<RotoriRouteLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce == _reduceMotion && (reduce || _c.isAnimating)) return;
    _reduceMotion = reduce;
    // Erişilebilirlik: hareket azaltma açıkken döngü durur ve mark tamamlanmış
    // hâlde durur — boş bir kutu göstermemek için değeri 1'e sabitliyoruz.
    if (reduce) {
      _c.stop();
      _c.value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final message = widget.message;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              painter: _RotoriMarkPainter(
                progress: _c.value,
                torii: RotoriBrand.torii,
                route: RotoriBrand.route,
              ),
            ),
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 18),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

/// Torii + rota markasını 100×100 birim uzayında çizer.
///
/// Zaman çizgisi (tek döngü):
///   0.00 → 0.16  üst kiriş (kasagi)
///   0.16 → 0.30  ikinci kiriş (nuki), üç parça — logodaki iki boşluk
///   0.30 → 0.52  iki ayak
///   0.46 → 0.88  ROTA kavisi, ucunda ilerleyen nokta
///   0.88 → 1.00  bekleme + nokta sönümü
class _RotoriMarkPainter extends CustomPainter {
  _RotoriMarkPainter({
    required this.progress,
    required this.torii,
    required this.route,
  });

  final double progress;
  final Color torii;
  final Color route;

  static double _seg(double t, double from, double to) =>
      ((t - from) / (to - from)).clamp(0.0, 1.0);

  /// Path'in baştan [fraction] kadarını döndürür.
  static Path _partial(Path source, double fraction) {
    if (fraction >= 1) return source;
    final out = Path();
    if (fraction <= 0) return out;
    for (final metric in source.computeMetrics()) {
      out.addPath(
        metric.extractPath(0, metric.length * fraction),
        Offset.zero,
      );
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 100;
    canvas.save();
    canvas.scale(scale);

    final t = Curves.easeInOut.transform(progress.clamp(0.0, 1.0));

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = torii;

    // --- 1) Üst kiriş: uçları aşağı sarkan geniş kavis. ---
    final kasagi = Path()
      ..moveTo(4, 27)
      ..quadraticBezierTo(50, 3, 96, 27);
    stroke.strokeWidth = 10;
    canvas.drawPath(_partial(kasagi, _seg(t, 0, .16)), stroke);

    // --- 2) İkinci kiriş: üç parça, aradaki iki boşluk logodaki çentikler. ---
    final nukiProgress = _seg(t, .16, .30);
    stroke.strokeWidth = 8;
    const nukiY = 44.0;
    const nukiSpans = [(16.0, 38.0), (43.0, 57.0), (62.0, 84.0)];
    for (var i = 0; i < nukiSpans.length; i++) {
      // Parçalar sırayla değil birlikte açılır; soldan sağa hafif gecikmeli.
      final local = ((nukiProgress * 3) - i).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final span = nukiSpans[i];
      final x2 = span.$1 + (span.$2 - span.$1) * local;
      canvas.drawLine(Offset(span.$1, nukiY), Offset(x2, nukiY), stroke);
    }

    // --- 3) Ayaklar: dışa doğru hafif açılır. ---
    final legProgress = _seg(t, .30, .52);
    stroke.strokeWidth = 10;
    if (legProgress > 0) {
      final left = Path()
        ..moveTo(30, 30)
        ..lineTo(22, 95);
      final right = Path()
        ..moveTo(70, 30)
        ..lineTo(78, 95);
      canvas.drawPath(_partial(left, legProgress), stroke);
      canvas.drawPath(_partial(right, legProgress), stroke);
    }

    // --- 4) ROTA: sol alttan sağ üste süzülen kavis. ---
    //
    // Logodaki kurdele/yol bu. Torii bittikten hemen sonra (hafif bindirmeli)
    // başlar — tanıtım animasyonundaki "R çizilir, sonra rota akar" sırası.
    final routeProgress = _seg(t, .46, .88);
    if (routeProgress > 0) {
      // Logodaki kurdele: sol ayağın dibinden başlar, nuki'nin altından
      // geçerek sağ üste süzülür.
      // Aşağıda uzun kalıp sağda dikleşir — logodaki geniş yol kavisi.
      // Düz çapraz bir çizgi torii'yi "üstü çizilmiş" gösteriyordu.
      final path = Path()
        ..moveTo(11, 96)
        ..cubicTo(30, 93, 47, 85, 61, 71)
        ..cubicTo(73, 59, 81, 47, 89, 31);

      final revealed = _partial(path, routeProgress);
      // Yol gövdesi: kalın, yumuşak uçlu.
      canvas.drawPath(
        revealed,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 9
          ..color = route,
      );
      // İnce açık orta şerit — yol hissi.
      canvas.drawPath(
        revealed,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.4
          ..color = Colors.white.withValues(alpha: 0.7),
      );

      // İlerleyen uç noktası: rotanın "çizilmekte olduğunu" anlatır.
      final metrics = path.computeMetrics().toList();
      if (metrics.isNotEmpty) {
        final metric = metrics.first;
        final tangent =
            metric.getTangentForOffset(metric.length * routeProgress);
        if (tangent != null) {
          final fade = 1 - _seg(t, .88, 1);
          canvas.drawCircle(
            tangent.position,
            7.5,
            Paint()..color = route.withValues(alpha: 0.18 * fade),
          );
          canvas.drawCircle(
            tangent.position,
            3.6,
            Paint()..color = Colors.white,
          );
          canvas.drawCircle(
            tangent.position,
            2.2,
            Paint()..color = route,
          );
        }
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_RotoriMarkPainter old) =>
      old.progress != progress || old.torii != torii || old.route != route;
}

/// Plan üretilirken ekranı kaplayan katman.
///
/// Üretim artık LLM incelemesi de içerdiği için gözle görülür sürüyor;
/// butondaki spinner tek başına "takıldı mı?" hissi veriyordu.
class RotoriGeneratingOverlay extends StatelessWidget {
  const RotoriGeneratingOverlay({
    super.key,
    required this.palette,
    this.message,
  });

  final ViewerPalette palette;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Semantics(
      liveRegion: true,
      label: message ?? s.s('create.generating'),
      child: ColoredBox(
        color: palette.bg.withValues(alpha: 0.92),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: RotoriRouteLoader(
              palette: palette,
              message: message ?? s.s('create.generating'),
            ),
          ),
        ),
      ),
    );
  }
}
