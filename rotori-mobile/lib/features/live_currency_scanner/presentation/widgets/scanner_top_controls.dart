import 'package:flutter/material.dart';

import '../../../../core/l10n.dart';
import '../../../viewer/viewer_theme.dart';
import '../../domain/currency_code.dart';

/// Kamera üstündeki üst kontrol şeridi — geri, flash, para birimi, ayarlar.
class ScannerTopControls extends StatelessWidget {
  const ScannerTopControls({
    super.key,
    required this.palette,
    required this.currency,
    required this.flashEnabled,
    required this.onBack,
    required this.onToggleFlash,
    required this.onPickCurrency,
    required this.onOpenSettings,
  });

  final ViewerPalette palette;
  final CurrencyCode currency;
  final bool flashEnabled;
  final VoidCallback onBack;
  final VoidCallback onToggleFlash;
  final ValueChanged<CurrencyCode> onPickCurrency;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CircleButton(icon: Icons.arrow_back, onTap: onBack),
        const Spacer(),
        _CurrencyPicker(
          current: currency,
          onPick: onPickCurrency,
          accent: palette.accent,
        ),
        const SizedBox(width: 10),
        _CircleButton(
          icon: flashEnabled ? Icons.flash_on : Icons.flash_off,
          onTap: onToggleFlash,
          active: flashEnabled,
          activeColor: palette.gold,
        ),
        const SizedBox(width: 10),
        _CircleButton(icon: Icons.tune, onTap: onOpenSettings),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.activeColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            color: active ? (activeColor ?? Colors.amber) : Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _CurrencyPicker extends StatelessWidget {
  const _CurrencyPicker({
    required this.current,
    required this.onPick,
    required this.accent,
  });

  final CurrencyCode current;
  final ValueChanged<CurrencyCode> onPick;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: PopupMenuButton<CurrencyCode>(
        tooltip: s.s('scanner.targetCurrency'),
        onSelected: onPick,
        itemBuilder: (context) => [
          for (final c in CurrencyCode.values)
            PopupMenuItem<CurrencyCode>(
              value: c,
              child: Text('${c.symbol}  ${c.iso}'),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${current.symbol} ${current.iso}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
