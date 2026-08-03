import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n.dart';
import '../../../viewer/viewer_theme.dart';
import '../../application/providers.dart';
import '../../domain/currency_code.dart';
import '../../domain/scanner_settings.dart';

/// Canlı para çevirici ayarları — hedef para birimi, kur, kart farkı, yuvarlama.
class ScannerSettingsPage extends ConsumerWidget {
  const ScannerSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = LanguageScope.of(context);
    final palette = ViewerPalette.of(context);
    final ui = ref.watch(scannerSettingsControllerProvider);
    final controller = ref.read(scannerSettingsControllerProvider.notifier);
    final settings = ui.settings;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(title: Text(s.s('scanner.settings'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _CurrencyTile(
            palette: palette,
            label: s.s('scanner.targetCurrency'),
            value: settings.targetCurrency,
            onChanged: controller.setTargetCurrency,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text(s.s('scanner.autoUpdate')),
            value: settings.autoUpdateRate,
            onChanged: controller.setAutoUpdate,
            activeThumbColor: palette.accent,
          ),
          SwitchListTile(
            title: Text(s.s('scanner.manualRate')),
            value: settings.useManualRate,
            onChanged: controller.setUseManualRate,
            activeThumbColor: palette.accent,
          ),
          if (settings.useManualRate)
            _ManualRateField(
              palette: palette,
              currency: settings.targetCurrency,
              initial: settings.manualRate,
              onChanged: controller.setManualRate,
            ),
          const Divider(height: 28),
          _CardMarkupField(
            palette: palette,
            label: s.s('scanner.cardMarkup'),
            initial: settings.cardMarkupPercent,
            onChanged: controller.setCardMarkup,
          ),
          const SizedBox(height: 8),
          _RoundingTile(
            palette: palette,
            label: s.s('scanner.rounding'),
            value: settings.rounding,
            onChanged: controller.setRounding,
          ),
          const SizedBox(height: 8),
          _PerformanceTile(
            palette: palette,
            label: s.s('scanner.performance'),
            value: settings.performanceProfile,
            onChanged: controller.setPerformanceProfile,
          ),
          const SizedBox(height: 24),
          Text(
            '${s.s('scanner.onDevice')} · ${s.s('scanner.noUpload')}',
            style: TextStyle(color: palette.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CurrencyTile extends StatelessWidget {
  const _CurrencyTile({
    required this.palette,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final ViewerPalette palette;
  final String label;
  final CurrencyCode value;
  final ValueChanged<CurrencyCode> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: DropdownButton<CurrencyCode>(
        value: value,
        underline: const SizedBox.shrink(),
        items: [
          for (final c in CurrencyCode.values)
            DropdownMenuItem(value: c, child: Text('${c.symbol}  ${c.iso}')),
        ],
        onChanged: (v) => v == null ? null : onChanged(v),
      ),
    );
  }
}

class _ManualRateField extends StatelessWidget {
  const _ManualRateField({
    required this.palette,
    required this.currency,
    required this.initial,
    required this.onChanged,
  });
  final ViewerPalette palette;
  final CurrencyCode currency;
  final String? initial;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextFormField(
        initialValue: initial,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        decoration: InputDecoration(
          prefixText: '1 JPY = ',
          suffixText: currency.iso,
          border: const OutlineInputBorder(),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _CardMarkupField extends StatelessWidget {
  const _CardMarkupField({
    required this.palette,
    required this.label,
    required this.initial,
    required this.onChanged,
  });
  final ViewerPalette palette;
  final String label;
  final double initial;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextFormField(
        initialValue: initial == 0 ? '' : initial.toString(),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        decoration: InputDecoration(
          labelText: label,
          suffixText: '%',
          border: const OutlineInputBorder(),
        ),
        onChanged: (v) => onChanged(double.tryParse(v) ?? 0),
      ),
    );
  }
}

class _RoundingTile extends StatelessWidget {
  const _RoundingTile({
    required this.palette,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final ViewerPalette palette;
  final String label;
  final RoundingPreference value;
  final ValueChanged<RoundingPreference> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    String labelFor(RoundingPreference r) => switch (r) {
          RoundingPreference.none => s.s('scanner.rounding.none'),
          RoundingPreference.nearestWhole => s.s('scanner.rounding.whole'),
          RoundingPreference.nearestTen => s.s('scanner.rounding.ten'),
        };
    return ListTile(
      title: Text(label),
      trailing: DropdownButton<RoundingPreference>(
        value: value,
        underline: const SizedBox.shrink(),
        items: [
          for (final r in RoundingPreference.values)
            DropdownMenuItem(value: r, child: Text(labelFor(r))),
        ],
        onChanged: (v) => v == null ? null : onChanged(v),
      ),
    );
  }
}

class _PerformanceTile extends StatelessWidget {
  const _PerformanceTile({
    required this.palette,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final ViewerPalette palette;
  final String label;
  final ScannerPerformanceProfile value;
  final ValueChanged<ScannerPerformanceProfile> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    String labelFor(ScannerPerformanceProfile p) => switch (p) {
          ScannerPerformanceProfile.batterySaver => s.s('scanner.perf.battery'),
          ScannerPerformanceProfile.balanced => s.s('scanner.perf.balanced'),
          ScannerPerformanceProfile.highAccuracy =>
            s.s('scanner.perf.accuracy'),
        };
    return ListTile(
      title: Text(label),
      trailing: DropdownButton<ScannerPerformanceProfile>(
        value: value,
        underline: const SizedBox.shrink(),
        items: [
          for (final p in ScannerPerformanceProfile.values)
            DropdownMenuItem(value: p, child: Text(labelFor(p))),
        ],
        onChanged: (v) => v == null ? null : onChanged(v),
      ),
    );
  }
}
