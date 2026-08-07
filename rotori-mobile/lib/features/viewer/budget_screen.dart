// Bütçe & Harcama paneli — plandaki maliyetleri gün/kategori bazında toplar,
// JPY→TL çevirir (elle güncellenen kur), kişi başı böler, planlanan/gerçekleşen
// yemek bütçesini karşılaştırır ve küçük bir JPY→TL çevirici sunar.
//
// Ağ YOK / canlı FX API YOK — kur çevrimdışı, kullanıcı tarafından güncellenir.
// Viewer paletine uyumlu (Theme + ViewerPaletteScope), Türkçe UI.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/exchange_rate_store.dart';
import '../../data/unit_cost_table_store.dart';
import '../../domain/budget.dart';
import '../../domain/cost_estimate.dart';
import '../../domain/types.dart';
import 'viewer_theme.dart';

// ---------------------------------------------------------------------------
// Para biçimlendirme — Türkçe binlik ayracı ("." binlik). intl bağımlılığı YOK.
// ---------------------------------------------------------------------------

/// Bir tam sayıyı Türkçe binlik ayracıyla gruplar: 1234567 → "1.234.567".
String groupThousands(int value) {
  final neg = value < 0;
  var digits = value.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return '${neg ? '-' : ''}$buf';
}

/// "₺1.234" — TL, en yakın tam sayıya yuvarlanır.
String formatTry(double value) => '₺${groupThousands(value.round())}';

/// "¥12.340" — JPY, en yakın tam sayıya yuvarlanır.
String formatJpy(num value) => '¥${groupThousands(value.round())}';

/// Seçili görüntüleme birimiyle biçimlendirir: "$1.234" / "€1.234" / "₺1.234".
String formatMoney(num value, DisplayCurrency currency) =>
    '${currency.symbol}${groupThousands(value.round())}';

/// Kuru okunur biçimde: "0,25" (Türkçe ondalık virgül). Sondaki sıfırlar
/// kırpılır (0,5000 → 0,5), tam sayı ise ondalıksız (1 → 1).
String formatRate(double rate) {
  var s = rate.toStringAsFixed(4);
  s = s.replaceAll(RegExp(r'0+$'), '');
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s.replaceAll('.', ',');
}

// ---------------------------------------------------------------------------
// Kategori etiketleri.
// ---------------------------------------------------------------------------

String _kindLabelKey(TimelineItemKind kind) => switch (kind) {
      TimelineItemKind.activity => 'kind.activity',
      TimelineItemKind.meal => 'kind.meal',
      TimelineItemKind.transport => 'kind.transport',
      TimelineItemKind.hotel => 'kind.hotel',
    };

String _kindEmoji(TimelineItemKind kind) => switch (kind) {
      TimelineItemKind.activity => '🎯',
      TimelineItemKind.meal => '🍜',
      TimelineItemKind.transport => '🚃',
      TimelineItemKind.hotel => '🏨',
    };

Color _kindColor(TimelineItemKind kind, ViewerPalette p) => switch (kind) {
      TimelineItemKind.activity => p.fuji,
      TimelineItemKind.meal => p.sakura,
      TimelineItemKind.transport => p.sky,
      TimelineItemKind.hotel => p.gold,
    };

// Kategori sabit sırası (görüntüleme).
const List<TimelineItemKind> _kindOrder = [
  TimelineItemKind.activity,
  TimelineItemKind.meal,
  TimelineItemKind.transport,
  TimelineItemKind.hotel,
];

// ---------------------------------------------------------------------------
// Ekran.
// ---------------------------------------------------------------------------

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key, required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(viewerPaletteProvider);
    return Theme(
      data: palette.toThemeData(),
      child: ViewerPaletteScope(
        palette: palette,
        child: _BudgetView(trip: trip),
      ),
    );
  }
}

class _BudgetView extends ConsumerWidget {
  const _BudgetView({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ViewerPalette.of(context);
    final s = LanguageScope.of(context);
    final selected =
        ref.watch(displayCurrencyProvider) ?? DisplayCurrencyX.defaultFor(s.lang);
    final rate = jpyRateFor(ref, selected);
    final summary = computeBudget(trip, jpyToTry: rate);
    final unitTable =
        ref.watch(unitCostTableProvider).valueOrNull ?? UnitCostTable.defaults();
    final estimate = estimateTripCost(trip, unitTable);
    final overrides = ref.watch(costOverrideProvider);

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          s.s('budget.title'),
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        backgroundColor: palette.card,
        foregroundColor: palette.textPrimary,
        elevation: 0,
      ),
      // Boş alana dokununca klavye kapanır (döviz girdisi tuzağına karşı).
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            _CurrencyRatesCard(
              selected: selected,
              rate: rate,
              palette: palette,
              onSelect: (currency) =>
                  ref.read(displayCurrencyProvider.notifier).set(currency),
              onEditRate: () => _editRate(context, ref, selected, rate),
            ),
            const SizedBox(height: 16),
            _EstimatedCostBreakdownCard(
              estimate: estimate,
              currency: selected,
              jpyRate: rate,
              overrides: overrides,
              palette: palette,
              onEditLine: (category) => _editLineCost(
                context,
                ref,
                category,
                selected,
                rate,
                overrides[category.name],
              ),
              onClearLine: (category) =>
                  ref.read(costOverrideProvider.notifier).clear(category.name),
            ),
            if (summary.itemsWithCost > 0) ...[
              const SizedBox(height: 16),
              _CategorySection(
                summary: summary,
                palette: palette,
              ),
              const SizedBox(height: 16),
              _DaySection(
                summary: summary,
                palette: palette,
              ),
            ],
            const SizedBox(height: 16),
            _ConverterSection(
              rate: rate,
              currency: selected,
              palette: palette,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editRate(
    BuildContext context,
    WidgetRef ref,
    DisplayCurrency currency,
    double current,
  ) async {
    // JPY referans birimidir; kuru düzenlenemez.
    if (currency == DisplayCurrency.jpy) return;
    final controller = TextEditingController(text: formatRate(current));
    final palette = ref.read(viewerPaletteProvider);
    final s = LanguageScope.of(context);
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) {
        return Theme(
          data: palette.toThemeData(),
          child: AlertDialog(
            backgroundColor: palette.card,
            title: Text(
              s.s('budget.editRate'),
              style: TextStyle(color: palette.textPrimary),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.p('budget.rateQuestionCurrency', {'code': currency.code}),
                  style: TextStyle(color: palette.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => Navigator.of(ctx).pop(
                    double.tryParse(controller.text.trim().replaceAll(',', '.')),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  decoration: InputDecoration(
                    prefixText: '${currency.symbol} ',
                    prefixStyle: TextStyle(color: palette.textSecondary),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.s('budget.rateManual'),
                  style: TextStyle(color: palette.textMuted, fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(s.s('common.cancel')),
              ),
              FilledButton(
                onPressed: () {
                  final parsed = double.tryParse(
                    controller.text.trim().replaceAll(',', '.'),
                  );
                  Navigator.of(ctx).pop(parsed);
                },
                child: Text(s.s('common.save')),
              ),
            ],
          ),
        );
      },
    );
    if (result != null && result > 0) {
      final notifier = switch (currency) {
        DisplayCurrency.tryLira => ref.read(jpyToTryProvider.notifier),
        DisplayCurrency.usd => ref.read(jpyToUsdProvider.notifier),
        DisplayCurrency.eur => ref.read(jpyToEurProvider.notifier),
        DisplayCurrency.jpy => ref.read(jpyToTryProvider.notifier),
      };
      await notifier.set(result);
    }
  }

  /// Bir gider kalemi için gerçek maliyeti seçili para biriminde girer; JPY'ye
  /// çevirip üstünüş olarak saklar. Boş bırakılırsa üstünüş kaldırılır.
  Future<void> _editLineCost(
    BuildContext context,
    WidgetRef ref,
    CostCategory category,
    DisplayCurrency currency,
    double jpyRate,
    int? currentJpy,
  ) async {
    final palette = ref.read(viewerPaletteProvider);
    final s = LanguageScope.of(context);
    final initial = currentJpy != null && jpyRate > 0
        ? groupThousands((currentJpy * jpyRate).round()).replaceAll('.', '')
        : '';
    final controller = TextEditingController(text: initial);
    final result = await showDialog<double?>(
      context: context,
      builder: (ctx) {
        return Theme(
          data: palette.toThemeData(),
          child: AlertDialog(
            backgroundColor: palette.card,
            title: Text(
              s.p('budget.editLineTitle', {'item': s.s(_costCatKey(category))}),
              style: TextStyle(color: palette.textPrimary),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.s('budget.editLineHint'),
                  style: TextStyle(color: palette.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => Navigator.of(ctx).pop(
                    double.tryParse(controller.text.trim().replaceAll(',', '.')),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  decoration: InputDecoration(
                    prefixText: '${currency.symbol} ',
                    prefixStyle: TextStyle(color: palette.textSecondary),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              if (currentJpy != null)
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(-1.0),
                  child: Text(s.s('budget.clearOverride')),
                ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(s.s('common.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(
                  double.tryParse(controller.text.trim().replaceAll(',', '.')),
                ),
                child: Text(s.s('common.save')),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    final notifier = ref.read(costOverrideProvider.notifier);
    if (result < 0) {
      await notifier.clear(category.name);
      return;
    }
    if (result > 0 && jpyRate > 0) {
      await notifier.set(category.name, (result / jpyRate).round());
    }
  }
}

// ---------------------------------------------------------------------------
// Kart kabuğu.
// ---------------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.palette, required this.child, this.borderColor});

  final ViewerPalette palette;
  final Widget child;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? palette.border),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, required this.palette});
  final String text;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          color: palette.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1) Döviz kurları + görüntüleme birimi seçici (₺ / $ / € / ¥).
// ---------------------------------------------------------------------------

class _CurrencyRatesCard extends StatelessWidget {
  const _CurrencyRatesCard({
    required this.selected,
    required this.rate,
    required this.palette,
    required this.onSelect,
    required this.onEditRate,
  });

  final DisplayCurrency selected;
  final double rate;
  final ViewerPalette palette;
  final ValueChanged<DisplayCurrency> onSelect;
  final VoidCallback onEditRate;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final p = palette;
    return _Card(
      palette: p,
      borderColor: p.accent.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.s('budget.currencyTitle'),
            style: TextStyle(color: p.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final currency in DisplayCurrency.values)
                _CurrencyChip(
                  currency: currency,
                  selected: currency == selected,
                  palette: p,
                  onTap: () => onSelect(currency),
                ),
            ],
          ),
          if (selected != DisplayCurrency.jpy) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '1 ¥ = ${selected.symbol}${formatRate(rate)}',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onEditRate,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text(s.s('budget.editRate')),
                  style: TextButton.styleFrom(
                    foregroundColor: p.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              s.s('budget.rateManual'),
              style: TextStyle(color: p.textMuted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _CurrencyChip extends StatelessWidget {
  const _CurrencyChip({
    required this.currency,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final DisplayCurrency currency;
  final bool selected;
  final ViewerPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Material(
      color: selected ? p.accent : p.elevated,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            '${currency.symbol} ${currency.code}',
            style: TextStyle(
              color: selected ? Colors.white : p.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2c) Tahmini gider dökümü — yıl bazlı birim tablodan (AI'sız) kalem kalem
//     min–max. "Bu rota sizin için ₺X – ₺Y arası" başlığı + kategori satırları
//     + örnek birim fiyatlar.
// ---------------------------------------------------------------------------

String _costCatEmoji(CostCategory c) => switch (c) {
      CostCategory.flight => '✈️',
      CostCategory.hotel => '🏨',
      CostCategory.food => '🍜',
      CostCategory.train => '🚄',
      CostCategory.taxi => '🚕',
      CostCategory.shopping => '🛍️',
      CostCategory.electronics => '🎮',
      CostCategory.attractions => '🎢',
    };

String _costCatKey(CostCategory c) => switch (c) {
      CostCategory.flight => 'budget.cat.flight',
      CostCategory.hotel => 'budget.cat.hotel',
      CostCategory.food => 'budget.cat.food',
      CostCategory.train => 'budget.cat.train',
      CostCategory.taxi => 'budget.cat.taxi',
      CostCategory.shopping => 'budget.cat.shopping',
      CostCategory.electronics => 'budget.cat.electronics',
      CostCategory.attractions => 'budget.cat.attractions',
    };

class _EstimatedCostBreakdownCard extends StatelessWidget {
  const _EstimatedCostBreakdownCard({
    required this.estimate,
    required this.currency,
    required this.jpyRate,
    required this.overrides,
    required this.palette,
    required this.onEditLine,
    required this.onClearLine,
  });

  final CostEstimate estimate;
  final DisplayCurrency currency;
  final double jpyRate;
  final Map<String, int> overrides;
  final ViewerPalette palette;
  final ValueChanged<CostCategory> onEditLine;
  final ValueChanged<CostCategory> onClearLine;

  int _effMin(CostLine line) => overrides[line.category.name] ?? line.minJpy;
  int _effMax(CostLine line) => overrides[line.category.name] ?? line.maxJpy;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final p = palette;
    var totalMinJpy = 0;
    var totalMaxJpy = 0;
    for (final line in estimate.lines) {
      totalMinJpy += _effMin(line);
      totalMaxJpy += _effMax(line);
    }
    final minMoney = totalMinJpy * jpyRate;
    final maxMoney = totalMaxJpy * jpyRate;
    final childrenStr = estimate.children > 0
        ? s.p('budget.estimate.people', {
            'adults': '${estimate.adults}',
            'children': '${estimate.children}',
          })
        : s.p('budget.estimate.adultsOnly', {'adults': '${estimate.adults}'});

    return _Card(
      palette: p,
      borderColor: p.accent.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.s('budget.estimate.title'),
            style: TextStyle(color: p.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 6),
          // İki değerli aralık tek satıra sığsın (küçülterek).
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${formatMoney(minMoney, currency)} – ${formatMoney(maxMoney, currency)}',
              maxLines: 1,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            s.p('budget.estimate.sub', {
              'jpyMin': formatJpy(totalMinJpy),
              'jpyMax': formatJpy(totalMaxJpy),
              'days': '${estimate.days}',
              'people': childrenStr,
            }),
            style: TextStyle(
              color: p.textMuted,
              fontSize: 12.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 14),
          for (final line in estimate.lines)
            _EstimateRow(
              emoji: _costCatEmoji(line.category),
              label: s.s(_costCatKey(line.category)),
              minMoney: _effMin(line) * jpyRate,
              maxMoney: _effMax(line) * jpyRate,
              currency: currency,
              isOverridden: overrides.containsKey(line.category.name),
              palette: p,
              onEdit: () => onEditLine(line.category),
              onClear: () => onClearLine(line.category),
            ),
          const SizedBox(height: 4),
          Text(
            s.s('budget.estimate.editHint'),
            style: TextStyle(color: p.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: p.elevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.border),
            ),
            child: Text(
              s.p('budget.estimate.note', {'year': '${estimate.year}'}),
              style: TextStyle(color: p.textSecondary, fontSize: 12),
            ),
          ),
          if (estimate.references.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              s.s('budget.estimate.refTitle'),
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ref in estimate.references)
                  _ReferenceChip(
                    label: _referenceLabel(s, ref.key),
                    jpy: ref.jpy,
                    jpyRate: jpyRate,
                    currency: currency,
                    palette: p,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _referenceLabel(LanguageScope s, String key) {
    final resolved = s.s('budget.ref.$key');
    // Bilinmeyen anahtar için l10n kendi anahtarını döner → ham anahtarı göster.
    if (resolved == 'budget.ref.$key') {
      return key.replaceAll('_', ' ');
    }
    return resolved;
  }
}

class _EstimateRow extends StatelessWidget {
  const _EstimateRow({
    required this.emoji,
    required this.label,
    required this.minMoney,
    required this.maxMoney,
    required this.currency,
    required this.isOverridden,
    required this.palette,
    required this.onEdit,
    required this.onClear,
  });

  final String emoji;
  final String label;
  final double minMoney;
  final double maxMoney;
  final DisplayCurrency currency;
  final bool isOverridden;
  final ViewerPalette palette;
  final VoidCallback onEdit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = LanguageScope.of(context);
    final valueText = isOverridden
        ? formatMoney(minMoney, currency)
        : '${formatMoney(minMoney, currency)} – ${formatMoney(maxMoney, currency)}';
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.textSecondary, fontSize: 13.5),
                    ),
                  ),
                  if (isOverridden) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: p.matcha.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        s.s('budget.overrideBadge'),
                        style: TextStyle(
                          color: p.matcha,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  valueText,
                  maxLines: 1,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 34,
              height: 34,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 16,
                tooltip: isOverridden
                    ? s.s('budget.clearOverride')
                    : s.s('budget.editLine'),
                onPressed: isOverridden ? onClear : onEdit,
                icon: Icon(
                  isOverridden ? Icons.close_rounded : Icons.edit_outlined,
                  color: p.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferenceChip extends StatelessWidget {
  const _ReferenceChip({
    required this.label,
    required this.jpy,
    required this.jpyRate,
    required this.currency,
    required this.palette,
  });

  final String label;
  final int jpy;
  final double jpyRate;
  final DisplayCurrency currency;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: p.elevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: p.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            '${formatJpy(jpy)} · ≈ ${formatMoney(jpy * jpyRate, currency)}',
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3) Kategoriye göre.
// ---------------------------------------------------------------------------

class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.summary, required this.palette});

  final BudgetSummary summary;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final k in _kindOrder)
        if ((summary.byCategoryTry[k] ?? 0) > 0)
          (kind: k, value: summary.byCategoryTry[k]!),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    final maxVal = entries
        .map((e) => e.value)
        .fold<double>(0, (a, b) => b > a ? b : a);

    return _Card(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            text: LanguageScope.of(context).s('budget.byCategory'),
            palette: palette,
          ),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CategoryBar(
                kind: e.kind,
                value: e.value,
                fraction: maxVal > 0 ? e.value / maxVal : 0,
                palette: palette,
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.kind,
    required this.value,
    required this.fraction,
    required this.palette,
  });

  final TimelineItemKind kind;
  final double value;
  final double fraction;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final color = _kindColor(kind, palette);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('${_kindEmoji(kind)} ', style: const TextStyle(fontSize: 14)),
            Expanded(
              child: Text(
                LanguageScope.of(context).s(_kindLabelKey(kind)),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              formatTry(value),
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Container(
                    height: 8,
                    width: double.infinity,
                    color: palette.elevated,
                  ),
                  Container(
                    height: 8,
                    width: constraints.maxWidth * fraction.clamp(0.0, 1.0),
                    color: color,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 4) Güne göre.
// ---------------------------------------------------------------------------

class _DaySection extends StatelessWidget {
  const _DaySection({required this.summary, required this.palette});

  final BudgetSummary summary;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    if (summary.byDay.isEmpty) return const SizedBox.shrink();
    return _Card(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            text: LanguageScope.of(context).s('budget.byDay'),
            palette: palette,
          ),
          for (final d in summary.byDay)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.elevated,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${d.dayNumber}',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      d.date,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    formatTry(d.totalTry),
                    style: TextStyle(
                      color: d.totalTry > 0
                          ? palette.textPrimary
                          : palette.textMuted,
                      fontSize: 14,
                      fontWeight: d.totalTry > 0
                          ? FontWeight.w700
                          : FontWeight.w400,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4) Çevirici — JPY girdi → seçili birim çıktı (canlı).
// ---------------------------------------------------------------------------

class _ConverterSection extends StatefulWidget {
  const _ConverterSection({
    required this.rate,
    required this.currency,
    required this.palette,
  });

  final double rate;
  final DisplayCurrency currency;
  final ViewerPalette palette;

  @override
  State<_ConverterSection> createState() => _ConverterSectionState();
}

class _ConverterSectionState extends State<_ConverterSection> {
  final _controller = TextEditingController(text: '1000');
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _dismiss() => FocusScope.of(context).unfocus();

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final s = LanguageScope.of(context);
    final jpy =
        double.tryParse(_controller.text.trim().replaceAll(',', '.')) ?? 0;
    final converted = jpy * widget.rate;
    final targetLabel = widget.currency == DisplayCurrency.jpy
        ? s.s('budget.yen')
        : '${widget.currency.symbol} ${widget.currency.code}';

    return _Card(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(text: s.s('budget.converter'), palette: palette),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            // Numerik klavyede return tuşu yok; dış alana dokununca da kapansın.
            onTapOutside: (_) => _dismiss(),
            onEditingComplete: _dismiss,
            onSubmitted: (_) => _dismiss(),
            // iOS'un kötü konumlanan "Metni Tara" (Live Text kamera) seçeneğini
            // bu alandan kaldır — OCR için özel canlı çevirici ekranı vardır.
            contextMenuBuilder: (context, editableState) {
              final items = editableState.contextMenuButtonItems
                  .where((item) =>
                      item.type != ContextMenuButtonType.liveTextInput)
                  .toList();
              return AdaptiveTextSelectionToolbar.buttonItems(
                anchors: editableState.contextMenuAnchors,
                buttonItems: items,
              );
            },
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            onChanged: (_) => setState(() {}),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            decoration: InputDecoration(
              labelText: s.s('budget.yen'),
              labelStyle: TextStyle(color: palette.textSecondary),
              prefixText: '¥ ',
              prefixStyle: TextStyle(color: palette.textSecondary),
              // Klavye üstünde "return" olmadığı için görünür "Bitti" düğmesi.
              suffixIcon: _focusNode.hasFocus
                  ? TextButton(
                      onPressed: _dismiss,
                      child: Text(s.s('common.done')),
                    )
                  : null,
              border: const OutlineInputBorder(),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: palette.border),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.accent.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  targetLabel,
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  formatMoney(converted, widget.currency),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

