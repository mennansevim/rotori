import 'package:flutter/material.dart';

/// React planner'ın styles.css :root token'larının BİREBİR Dart karşılığı.
/// Açık Apple teması — viewer'ın koyu temasından ayrıdır.
///
/// Kaynak: apps/planner/src/styles.css :root
class PT {
  const PT._();

  // Renkler
  static const bg = Color(0xFFF5F5F7);
  static const bgElevated = Color(0xFFFFFFFF);
  static const bgSubtle = Color(0xFFFBFBFD);
  static const text = Color(0xFF1D1D1F);
  static const textSecondary = Color(0xFF6E6E73);
  static const textTertiary = Color(0xFF86868B);
  static const accent = Color(0xFF0071E3);
  static const accentHover = Color(0xFF0077ED);
  static const accentSoft = Color(0x140071E3); // rgba(0,113,227,0.08)
  static const border = Color(0x0F000000); // rgba(0,0,0,0.06)
  static const borderStrong = Color(0x1F000000); // rgba(0,0,0,0.12)
  static const danger = Color(0xFFBF4800);

  // Radyus
  static const radius = 14.0;
  static const radiusLg = 20.0;
  static const radiusPill = 980.0;

  // Gölgeler (CSS box-shadow karşılığı)
  static const shadowSm = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 3, offset: Offset(0, 1)),
  ];
  static const shadowMd = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 24, offset: Offset(0, 4)),
  ];

  // Marka ikonu gradyanı (pembe → mor)
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF8FAB), Color(0xFF7C6AEF)],
  );

  static const navHeight = 52.0;
  static const stepNavHeight = 56.0;

  /// SF Pro / system font — Flutter'da platform default'a bırakıyoruz,
  /// letter-spacing -0.01em body geneli.
  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.light(
        primary: accent,
        surface: bgElevated,
        onSurface: text,
      ),
      splashFactory: NoSplash.splashFactory,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: text,
        displayColor: text,
        fontFamily: '.SF Pro Text',
      ),
    );
  }
}

/// styles.css .page-headline
class PageHeadline extends StatelessWidget {
  const PageHeadline(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.64, // -0.02em
            height: 1.1,
            color: PT.text,
          ),
        ),
      );
}

/// styles.css .page-sub
class PageSub extends StatelessWidget {
  const PageSub(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 17,
            color: PT.textSecondary,
            height: 1.4,
          ),
        ),
      );
}

/// styles.css .card
class PCard extends StatelessWidget {
  const PCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 20),
        padding: padding ?? const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: PT.bgElevated,
          borderRadius: BorderRadius.circular(PT.radiusLg),
          border: Border.all(color: PT.border),
          boxShadow: PT.shadowSm,
        ),
        child: child,
      );
}

/// styles.css .card-title
class PCardTitle extends StatelessWidget {
  const PCardTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: PT.textTertiary,
          ),
        ),
      );
}

/// styles.css .field (label + kontrol + opsiyonel ipucu)
class PField extends StatelessWidget {
  const PField({super.key, required this.label, required this.child, this.hint});
  final String label;
  final Widget child;
  final Widget? hint;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500, color: PT.text)),
            const SizedBox(height: 8),
            child,
            if (hint != null) Padding(padding: const EdgeInsets.only(top: 6), child: hint!),
          ],
        ),
      );
}

/// styles.css .field input — metin girişi.
class PTextField extends StatelessWidget {
  const PTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint,
    this.keyboardType,
    this.invalid = false,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final TextInputType? keyboardType;
  final bool invalid;
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      onChanged: onChanged,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: PT.bgSubtle,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: invalid ? const Color(0xFFDC2626) : PT.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: PT.accent),
        ),
      ),
    );
  }
}

/// styles.css .chip / .chip-active (toggle çip)
class PChip extends StatelessWidget {
  const PChip({super.key, required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? PT.accentSoft : PT.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PT.radiusPill),
        side: BorderSide(color: active ? PT.accent : PT.borderStrong),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(PT.radiusPill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: active ? PT.accent : PT.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// styles.css .btn.btn-primary / .btn-secondary (pill)
class PButton extends StatelessWidget {
  const PButton({
    super.key,
    required this.label,
    this.onPressed,
    this.primary = true,
    this.block = false,
    this.leading,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool block;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final child = Row(
      mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 8)],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: primary ? Colors.white : PT.text,
            ),
          ),
        ),
      ],
    );
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: primary ? PT.accent : PT.bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PT.radiusPill),
          side: primary
              ? BorderSide.none
              : const BorderSide(color: PT.borderStrong),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(PT.radiusPill),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            child: child,
          ),
        ),
      ),
    );
  }
}
