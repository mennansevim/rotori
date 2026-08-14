// Yeni plan oluşturma akışının ortak görsel parçaları.
//
// Tamamı ViewerPalette yüzeyidir — planner'ın PT (Apple mavi/gri) temasına
// bağlı DEĞİLDİR. Böylece "Planlarım → oluştur → plan" tek görsel dilde akar.

import 'package:flutter/material.dart';

import '../../../core/rotori_brand.dart';
import '../../viewer/viewer_theme.dart';

/// Marka gradyanlı üst başlık. plans_list_screen._PlansHeader ile aynı
/// anatomiye sahiptir (旅 rozeti + başlık + alt satır, alt köşeler r28) —
/// listeden bu akışa geçiş görsel olarak kesintisiz olsun diye.
///
/// Gradyan üç temada da doygun olduğu için metin/ikon DAİMA beyazdır.
class BrandHero extends StatelessWidget {
  const BrandHero({
    super.key,
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.step,
    required this.totalSteps,
    this.onBack,
  });

  final ViewerPalette palette;
  final String title;
  final String subtitle;

  /// 0 tabanlı aktif adım — sağ üstteki noktalar için.
  final int step;
  final int totalSteps;
  final VoidCallback? onBack;

  static const Color _on = Colors.white;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        // Marka gradyanı temadan DEĞİL, marka sabitlerinden gelir.
        gradient: LinearGradient(
          colors: RotoriBrand.heroGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: _on),
                    onPressed: onBack,
                    tooltip: MaterialLocalizations.of(context)
                        .backButtonTooltip,
                  ),
                  const Spacer(),
                  for (var i = 0; i < totalSteps; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: i == step ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: _on.withValues(alpha: i <= step ? 0.95 : 0.38),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  children: [
                    // 旅 kanjisi yerine markanın kendi işareti. Logo beyaz
                    // zeminli olduğu için rozet de beyaz: kırmızı hero
                    // üzerinde torii net okunur.
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _on,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: _on.withValues(alpha: 0.5)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        RotoriBrand.logoAsset,
                        fit: BoxFit.cover,
                        // Asset yüklenemezse hero boş bir kutu göstermesin.
                        errorBuilder: (_, __, ___) => const Center(
                          child: Text(
                            '旅',
                            style: TextStyle(
                              color: RotoriBrand.torii,
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: _on,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _on.withValues(alpha: 0.82),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Şehir kartı. Seçiliyken mor dolgu + beyaz metin, sağ üstte rota sırası.
class CityTile extends StatelessWidget {
  const CityTile({
    super.key,
    required this.palette,
    required this.emoji,
    required this.label,
    required this.placeCountLabel,
    required this.selected,
    required this.orderIndex,
    required this.onTap,
  });

  final ViewerPalette palette;
  final String emoji;
  final String label;
  final String placeCountLabel;
  final bool selected;

  /// 1 tabanlı rota sırası; seçili değilse 0.
  final int orderIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : palette.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? palette.fuji : palette.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? palette.fuji : palette.border,
            width: 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: palette.fuji.withValues(alpha: 0.32),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedScale(
                        duration: const Duration(milliseconds: 180),
                        scale: selected ? 1.08 : 1,
                        alignment: Alignment.centerLeft,
                        child: Text(emoji, style: const TextStyle(fontSize: 32)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        placeCountLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? Colors.white.withValues(alpha: 0.78)
                              : palette.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  if (selected)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$orderIndex',
                          style: TextStyle(
                            color: palette.fuji,
                            fontSize: 12,
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
      ),
    );
  }
}

/// Alt aksiyon barı — üstte ince ayraç, altta SafeArea.
class CreateBottomBar extends StatelessWidget {
  const CreateBottomBar({super.key, required this.palette, required this.child});
  final ViewerPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: child,
        ),
      ),
    );
  }
}

/// Marka pill butonu — dolu (primary) veya çerçeveli.
class BrandButton extends StatelessWidget {
  const BrandButton({
    super.key,
    required this.palette,
    required this.label,
    required this.onPressed,
    this.block = false,
    this.busy = false,
    this.tone,
    this.radius = 980,
  });

  /// Planı üreten son adımın CTA turuncusu.
  ///
  /// **Why sabit renk:** Paletten gelemiyor — appleLight'ta `sunset` kırmızı
  /// (#FF3B30), japanDark'ta `gold` açık sarı (#FFD54F); ikisi de beyaz
  /// etiketle bu butonun görünmesi gerektiği gibi görünmüyor.
  static const Color ctaOrange = Color(0xFFF97316);

  final ViewerPalette palette;
  final String label;
  final VoidCallback? onPressed;
  final bool block;

  /// true iken buton kilitlenir ve içinde spinner gösterilir.
  final bool busy;

  /// Dolgu rengi. null → `palette.fuji` (akışın ara adımlarındaki mavi).
  final Color? tone;

  /// Köşe yarıçapı. Varsayılan pill; CTA için daha az yuvarlak kullanılır.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled || busy ? 1 : 0.4,
      child: Material(
        color: tone ?? palette.fuji,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(radius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
            child: Row(
              mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy) ...[
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
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
