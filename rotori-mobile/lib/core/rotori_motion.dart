import 'package:flutter/material.dart';

/// Uygulamadaki hareketleri erişilebilirlik ayarlarıyla aynı sözleşmede tutar.
///
/// `disableAnimations` açıkken hareketli geçişler sıfır süreli olur; böylece
/// içerik kaybolmaz, yalnızca görsel hareket azaltılır.
abstract final class RotoriMotion {
  const RotoriMotion._();

  static bool reduce(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    return media?.disableAnimations == true ||
        media?.accessibleNavigation == true;
  }

  static Duration duration(BuildContext context, Duration normal) {
    return reduce(context) ? Duration.zero : normal;
  }

  static Curve curve(BuildContext context,
      {Curve normal = Curves.easeOutCubic}) {
    return reduce(context) ? Curves.linear : normal;
  }
}

/// Reduced Motion açıkken `AnimatedSize` yerine doğrudan child'ı döndürür.
/// Sıfır süreli `AnimatedSize`, Flutter'ın layout aşamasında yeniden layout
/// istemesine yol açabildiği için bu ayrım özellikle gereklidir.
class RotoriAnimatedSize extends StatelessWidget {
  const RotoriAnimatedSize({
    super.key,
    required this.duration,
    required this.curve,
    required this.child,
    this.alignment = Alignment.center,
    this.clipBehavior = Clip.hardEdge,
  });

  final Duration duration;
  final Curve curve;
  final Widget child;
  final AlignmentGeometry alignment;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    if (RotoriMotion.reduce(context)) return child;
    return AnimatedSize(
      duration: duration,
      curve: curve,
      alignment: alignment,
      clipBehavior: clipBehavior,
      child: child,
    );
  }
}
