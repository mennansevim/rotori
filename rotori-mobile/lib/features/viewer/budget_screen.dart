// Bütçe & Harcama paneli — plandaki maliyetleri gün/kategori bazında toplar,
// JPY→seçili birime çevirir (elle güncellenen kur), kişi başı böler ve tahmini
// gider dökümünü animasyonlu halka grafikle payına göre gösterir.
//
// Kaldırılanlar: JPY→TL çevirici bölümü (ayrı bir Canlı Fiyat Çevirici ekranı
// var; buradaki kopya kartın en altında yer tutuyordu) ve "Örnek birim
// fiyatlar" çip ızgarası (tahmin notu zaten birim tablosuna dayandığını
// söylüyor).
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
    // Kompakt kart.
    //
    // **Why:** Bu kart ilk ekranın üçte birini yiyordu: "Para birimi" başlığı,
    // çip satırı, tazelik satırı, 20px'lik kur satırı + buton, ve altında
    // "Kur elle güncellenir" dipnotu — beş ayrı blok. Oysa çipler zaten para
    // birimi seçtiğini söylüyor ("₺ TRY"), dipnotu da "Kuru düzenle" butonu
    // ima ediyor. Kalanı tek satıra indi.
    return _Card(
      palette: p,
      borderColor: p.accent.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 7,
            runSpacing: 7,
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
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '1 ¥ = ${selected.symbol}${formatRate(rate)}',
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 10),
                // Tazelik artık kurun YANINDA: "1 ¥ = ₺0,3 · 11 saat önce".
                Expanded(child: _RateFreshness(palette: p)),
                TextButton.icon(
                  onPressed: onEditRate,
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: Text(s.s('budget.editRate')),
                  style: TextButton.styleFrom(
                    foregroundColor: p.accent,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            '${currency.symbol} ${currency.code}',
            style: TextStyle(
              color: selected ? Colors.white : p.textPrimary,
              fontSize: 13,
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
          const SizedBox(height: 10),
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
          const SizedBox(height: 6),
          Text(
            s.s('budget.estimate.editHint'),
            style: TextStyle(color: p.textMuted, fontSize: 12),
          ),
          // Pasta, hesabın HEMEN ALTINDA: satırlar "ne kadar", pasta "hangisi
          // baskın" sorusunu cevaplıyor. Bir kalem elle değiştirilince
          // dilimler yeni paya doğru animasyonla akar.
          if (_amounts().isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: p.border),
            const SizedBox(height: 12),
            _BudgetSharePie(
              key: const ValueKey('budget-share-pie'),
              amounts: _amounts(),
              palette: p,
            ),
          ],
          const SizedBox(height: 12),
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
        ],
      ),
    );
  }

  /// Pasta için kalem başına ORTA değer (min–maks ortalaması), JPY.
  ///
  /// **Why orta:** Başlıktaki toplam bir ARALIK; "aralığın payı" tanımsız
  /// olurdu. Elle girilen kalemlerde min == max olduğundan orta = girilen
  /// değer. Sıfır kalemler (taksi/elektronik kullanılmadıysa) pastaya
  /// girmez — 0°'lik dilim yalnızca lejandı şişirir.
  Map<CostCategory, double> _amounts() {
    final out = <CostCategory, double>{};
    for (final line in estimate.lines) {
      final mid = (_effMin(line) + _effMax(line)) / 2;
      if (mid > 0) out[line.category] = mid;
    }
    return out;
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
        // Satır arası 6 → 1. Sekiz kalem × 12px fazladan boşluk, pastayı ve
        // notu ekranın altına itiyordu. Satırın kendi 30px'lik ikon yüksekliği
        // dokunma hedefini zaten taşıyor.
        padding: const EdgeInsets.symmetric(vertical: 1),
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
              width: 30,
              height: 30,
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

// ---------------------------------------------------------------------------
// 2d) Gider dağılımı — animasyonlu halka grafik.
// ---------------------------------------------------------------------------

/// Kalem başına hue (derece) — yedi ton, çember üzerinde ~51° aralıklı.
///
/// **Why paletten ton SEÇİLMİYOR:** `ViewerPalette` kategorik bir skala olarak
/// tasarlanmadı ve tonları aynı tema içinde ÇAKIŞIYOR. Açık temada
/// accent (#0071E3), sky (#007AFF) ve accentStrong (#0A6DCA) neredeyse aynı
/// mavi; koyu temada accent ile fuji BİREBİR aynı mor (#7C6AEF). İlk iki
/// denemede halkadaki dilimler bu yüzden ayırt edilemedi. Hue'ları elle ve
/// eşit aralıklı seçmek her temada ayrışmayı garanti eder; doygunluk ve
/// parlaklık temadan gelir, böylece kart zemininde okunur kalır.
///
/// Elektronik dizide YOK: nötr gri alır. Çoğu planda 0 olan, yani pastadan en
/// sık kaybolan kalem o — griyi ona vermek renk bütçesini konuşan kalemlere
/// bırakıyor.
const Map<CostCategory, double> _costCatHue = {
  CostCategory.flight: 212, // mavi
  CostCategory.train: 263, // mor
  CostCategory.food: 314, // magenta
  CostCategory.taxi: 5, // kırmızı
  CostCategory.hotel: 56, // amber
  CostCategory.attractions: 107, // fıstık yeşili
  CostCategory.shopping: 158, // turkuaz
};

Color _costCatColor(CostCategory c, ViewerPalette p) {
  final hue = _costCatHue[c];
  if (hue == null) {
    return Color.lerp(p.textMuted, p.textPrimary, .2) ?? p.textMuted;
  }
  final dark = p.brightness == Brightness.dark;
  return HSLColor.fromAHSL(
    1,
    hue,
    dark ? .58 : .74,
    dark ? .66 : .47,
  ).toColor();
}

/// Hangi kalem pastada ne kadar yer kaplıyor.
///
/// **Why halka, dolu pasta değil:** ortadaki boşluk baskın kalemi yazıyla
/// söyleyebiliyor; dolu pastada o bilgiyi ancak dilimlerin üstüne sıkıştırarak
/// verirdik ve sekiz kalemde okunmazdı.
///
/// **Why animasyon:** kullanıcı bir kalemi elle değiştirdiğinde dilimin
/// sıçraması "ne değişti"yi gizler. Paylar eski değerden yenisine akınca
/// hangi kalemin büyüdüğü görünür.
class _BudgetSharePie extends StatefulWidget {
  const _BudgetSharePie({
    super.key,
    required this.amounts,
    required this.palette,
  });

  /// Kalem → JPY tutar. Sıfır kalemler çağıran tarafından ayıklanır.
  final Map<CostCategory, double> amounts;
  final ViewerPalette palette;

  @override
  State<_BudgetSharePie> createState() => _BudgetSharePieState();
}

class _BudgetSharePieState extends State<_BudgetSharePie>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Animasyonun başladığı ve bittiği paylar (0..1), kalem başına.
  late Map<CostCategory, double> _from;
  late Map<CostCategory, double> _to;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 620),
      vsync: this,
    );
    _from = _zeroShares();
    _to = _sharesOf(widget.amounts);
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _BudgetSharePie old) {
    super.didUpdateWidget(old);
    final next = _sharesOf(widget.amounts);
    if (_sameShares(next, _to)) return;
    // Yeni animasyon, DURAN kareden başlar — kullanıcı üst üste değer girerse
    // dilimler sıfıra dönüp yeniden büyümez.
    _from = _lerpShares(_from, _to, _curved(_controller.value));
    _to = next;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static double _curved(double t) => Curves.easeOutCubic.transform(t);

  Map<CostCategory, double> _zeroShares() =>
      {for (final c in CostCategory.values) c: 0};

  /// Tutarları paya (0..1) çevirir. Kalemler SABİT sırada tutulur; eksikler 0.
  /// Böylece bir kalem sıfırlanıp pastadan çıksa da ara değer hesabı bozulmaz.
  Map<CostCategory, double> _sharesOf(Map<CostCategory, double> amounts) {
    final total = amounts.values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return _zeroShares();
    return {
      for (final c in CostCategory.values) c: (amounts[c] ?? 0) / total,
    };
  }

  bool _sameShares(Map<CostCategory, double> a, Map<CostCategory, double> b) {
    for (final c in CostCategory.values) {
      if (((a[c] ?? 0) - (b[c] ?? 0)).abs() > 0.0005) return false;
    }
    return true;
  }

  Map<CostCategory, double> _lerpShares(
    Map<CostCategory, double> a,
    Map<CostCategory, double> b,
    double t,
  ) =>
      {
        for (final c in CostCategory.values)
          c: (a[c] ?? 0) + ((b[c] ?? 0) - (a[c] ?? 0)) * t,
      };

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final s = LanguageScope.of(context);
    // Erişilebilirlik: hareket kapalıysa animasyon yok, son duruma otur.
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final finalShares = _sharesOf(widget.amounts);
    final visible = CostCategory.values
        .where((c) => (widget.amounts[c] ?? 0) > 0)
        .toList()
      ..sort((a, b) =>
          (widget.amounts[b] ?? 0).compareTo(widget.amounts[a] ?? 0));
    if (visible.isEmpty) return const SizedBox.shrink();
    final top = visible.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              s.s('budget.share.title'),
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                s.s('budget.share.basis'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.textMuted, fontSize: 11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Semantics(
              label: [
                s.s('budget.share.title'),
                for (final c in visible)
                  '${s.s(_costCatKey(c))} '
                      '%${((finalShares[c] ?? 0) * 100).round()}',
              ].join('. '),
              child: SizedBox(
                width: 118,
                height: 118,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final shares = reduceMotion
                        ? finalShares
                        : _lerpShares(_from, _to, _curved(_controller.value));
                    return CustomPaint(
                      painter: _DonutPainter(
                        slices: [
                          for (final c in visible)
                            (
                              color: _costCatColor(c, p),
                              share: shares[c] ?? 0,
                            ),
                        ],
                        track: p.border,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _costCatEmoji(top),
                              style: const TextStyle(fontSize: 17),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              '%${((finalShares[top] ?? 0) * 100).round()}',
                              style: TextStyle(
                                color: p.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final c in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: _costCatColor(c, p),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              s.s(_costCatKey(c)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '%${((finalShares[c] ?? 0) * 100).round()}',
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
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
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices, required this.track});

  final List<({Color color, double share})> slices;
  final Color track;

  static const double _stroke = 17;

  /// Dilimler arası boşluk (radyan). Aynı tondaki komşu dilimler birbirine
  /// karışmasın; çok küçük dilimde boşluk dilimden büyük olmasın diye
  /// dilimin kendi payıyla sınırlanır.
  static const double _gap = 0.035;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (size.shortestSide - _stroke) / 2,
    );

    canvas.drawArc(
      rect,
      0,
      6.283185307179586,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..color = track,
    );

    // 12 yönünden başla, saat yönünde ilerle — okuma sırası lejandla aynı.
    var start = -1.5707963267948966;
    for (final slice in slices) {
      final full = slice.share * 6.283185307179586;
      if (full <= 0) continue;
      final gap = _gap.clamp(0.0, full * 0.5);
      canvas.drawArc(
        rect,
        start + gap / 2,
        full - gap,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..strokeCap = StrokeCap.butt
          ..color = slice.color,
      );
      start += full;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.track != track ||
      old.slices.length != slices.length ||
      () {
        for (var i = 0; i < slices.length; i++) {
          if (old.slices[i].color != slices[i].color ||
              old.slices[i].share != slices[i].share) {
            return true;
          }
        }
        return false;
      }();
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

/// Kurun ne zaman güncellendiğini gösterir. Canlı kur hiç çekilemediyse
/// (ilk açılış + ağ yok) hiçbir şey göstermez — yanlış güven vermeyelim.
class _RateFreshness extends ConsumerWidget {
  const _RateFreshness({required this.palette});
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updated = ref.watch(fxLastUpdatedProvider);
    if (updated == null) return const SizedBox.shrink();
    final s = LanguageScope.of(context);
    final diff = DateTime.now().toUtc().difference(updated.toUtc());

    final String when;
    if (diff.inMinutes < 60) {
      when =
          s.p('budget.rateAgeMinShort', {'n': '${diff.inMinutes.clamp(1, 59)}'});
    } else if (diff.inHours < 24) {
      when = s.p('budget.rateAgeHourShort', {'n': '${diff.inHours}'});
    } else {
      when = s.p('budget.rateAgeDayShort', {'n': '${diff.inDays}'});
    }

    // Kur satırının İÇİNDE, yanında duruyor — kendi satırı yok.
    return Row(
      children: [
        Icon(Icons.sync_rounded, size: 12, color: palette.textMuted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            when,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.textMuted, fontSize: 11),
          ),
        ),
      ],
    );
  }
}
