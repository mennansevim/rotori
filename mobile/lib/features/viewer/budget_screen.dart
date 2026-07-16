// Bütçe & Harcama paneli — plandaki maliyetleri gün/kategori bazında toplar,
// JPY→TL çevirir (elle güncellenen kur), kişi başı böler, planlanan/gerçekleşen
// yemek bütçesini karşılaştırır ve küçük bir JPY→TL çevirici sunar.
//
// Ağ YOK / canlı FX API YOK — kur çevrimdışı, kullanıcı tarafından güncellenir.
// Viewer paletine uyumlu (Theme + ViewerPaletteScope), Türkçe UI.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/exchange_rate_store.dart';
import '../../domain/budget.dart';
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

String _kindLabel(TimelineItemKind kind) => switch (kind) {
      TimelineItemKind.activity => 'Aktivite',
      TimelineItemKind.meal => 'Yemek',
      TimelineItemKind.transport => 'Ulaşım',
      TimelineItemKind.hotel => 'Otel',
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
    final rate = ref.watch(jpyToTryProvider);
    final summary = computeBudget(trip, jpyToTry: rate);
    final party = trip.preferences.partySize ?? 1;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          '💰 Bütçe',
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          if (summary.itemsWithCost == 0) ...[
            _EmptyBanner(palette: palette),
            const SizedBox(height: 16),
          ],
          _TotalCard(summary: summary, party: party, palette: palette),
          const SizedBox(height: 16),
          _RateCard(
            rate: rate,
            palette: palette,
            onEdit: () => _editRate(context, ref, rate),
          ),
          if (summary.itemsWithCost > 0) ...[
            const SizedBox(height: 16),
            _CategorySection(summary: summary, palette: palette),
            const SizedBox(height: 16),
            _DaySection(summary: summary, palette: palette),
          ],
          if (summary.plannedMealTry > 0 || summary.actualMealTry > 0) ...[
            const SizedBox(height: 16),
            _MealBudgetSection(summary: summary, palette: palette),
          ],
          const SizedBox(height: 16),
          _ConverterSection(rate: rate, palette: palette),
        ],
      ),
    );
  }

  Future<void> _editRate(
    BuildContext context,
    WidgetRef ref,
    double current,
  ) async {
    final controller = TextEditingController(text: formatRate(current));
    final palette = ref.read(viewerPaletteProvider);
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) {
        return Theme(
          data: palette.toThemeData(),
          child: AlertDialog(
            backgroundColor: palette.card,
            title: Text(
              'Kuru düzenle',
              style: TextStyle(color: palette.textPrimary),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1 ¥ kaç ₺?',
                  style: TextStyle(color: palette.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  autofocus: true,
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
                    prefixText: '₺ ',
                    prefixStyle: TextStyle(color: palette.textSecondary),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Kur elle güncellenir (çevrimdışı).',
                  style: TextStyle(color: palette.textMuted, fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('İptal'),
              ),
              FilledButton(
                onPressed: () {
                  final parsed = double.tryParse(
                    controller.text.trim().replaceAll(',', '.'),
                  );
                  Navigator.of(ctx).pop(parsed);
                },
                child: const Text('Kaydet'),
              ),
            ],
          ),
        );
      },
    );
    if (result != null && result > 0) {
      await ref.read(jpyToTryProvider.notifier).set(result);
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
// 1) Toplam hero.
// ---------------------------------------------------------------------------

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.summary,
    required this.party,
    required this.palette,
  });

  final BudgetSummary summary;
  final int party;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return _Card(
      palette: palette,
      borderColor: palette.accent.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Toplam tahmini harcama',
            style: TextStyle(color: palette.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            formatTry(summary.grandTotalTry),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 40,
              fontWeight: FontWeight.w800,
              height: 1.1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (summary.grandTotalJpy > 0) ...[
            const SizedBox(height: 4),
            Text(
              '(≈ ${formatJpy(summary.grandTotalJpy)} JPY)',
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 14,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: palette.elevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                const Text('👤', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Kişi başı',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  '${formatTry(summary.perPersonTry)} ($party kişi)',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${summary.itemsWithCost}/${summary.itemsTotal} öğede maliyet girili',
            style: TextStyle(color: palette.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2) Kur.
// ---------------------------------------------------------------------------

class _RateCard extends StatelessWidget {
  const _RateCard({
    required this.rate,
    required this.palette,
    required this.onEdit,
  });

  final double rate;
  final ViewerPalette palette;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return _Card(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Döviz kuru',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '1 ¥ = ₺${formatRate(rate)}',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Kuru düzenle'),
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Kur elle güncellenir (çevrimdışı).',
            style: TextStyle(color: palette.textMuted, fontSize: 12),
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
          _SectionTitle(text: 'Kategoriye göre', palette: palette),
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
                _kindLabel(kind),
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
          _SectionTitle(text: 'Güne göre', palette: palette),
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
// 5) Yemek bütçesi (planlanan vs gerçekleşen).
// ---------------------------------------------------------------------------

class _MealBudgetSection extends StatelessWidget {
  const _MealBudgetSection({required this.summary, required this.palette});

  final BudgetSummary summary;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final planned = summary.plannedMealTry;
    final actual = summary.actualMealTry;
    final over = planned > 0 && actual > planned;
    final barColor = over ? palette.sunset : palette.matcha;
    final fraction = planned > 0 ? (actual / planned).clamp(0.0, 1.0) : 1.0;

    return _Card(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(text: 'Yemek bütçesi', palette: palette),
          Text.rich(
            TextSpan(
              style: TextStyle(color: palette.textSecondary, fontSize: 14),
              children: [
                const TextSpan(text: 'Planlanan '),
                TextSpan(
                  text: formatTry(planned),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(text: ' · Gerçekleşen '),
                TextSpan(
                  text: formatTry(actual),
                  style: TextStyle(
                    color: over ? palette.sunset : palette.matcha,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Container(
                      height: 10,
                      width: double.infinity,
                      color: palette.elevated,
                    ),
                    Container(
                      height: 10,
                      width: constraints.maxWidth * fraction,
                      color: barColor,
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            over
                ? 'Bütçe aşıldı — planlanandan ${formatTry(actual - planned)} fazla.'
                : planned > 0
                    ? 'Bütçe içinde — ${formatTry(planned - actual)} kaldı.'
                    : 'Henüz planlanan yemek bütçesi yok.',
            style: TextStyle(
              color: over ? palette.sunset : palette.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6) Çevirici — JPY girdi → TL çıktı (canlı).
// ---------------------------------------------------------------------------

class _ConverterSection extends StatefulWidget {
  const _ConverterSection({required this.rate, required this.palette});

  final double rate;
  final ViewerPalette palette;

  @override
  State<_ConverterSection> createState() => _ConverterSectionState();
}

class _ConverterSectionState extends State<_ConverterSection> {
  final _controller = TextEditingController(text: '1000');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final jpy =
        double.tryParse(_controller.text.trim().replaceAll(',', '.')) ?? 0;
    final tl = jpy * widget.rate;

    return _Card(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(text: 'Çevirici', palette: palette),
          TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
              labelText: 'Japon Yeni (¥)',
              labelStyle: TextStyle(color: palette.textSecondary),
              prefixText: '¥ ',
              prefixStyle: TextStyle(color: palette.textSecondary),
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
                  'Türk Lirası (₺)',
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  formatTry(tl),
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

// ---------------------------------------------------------------------------
// Boş durum banner'ı.
// ---------------------------------------------------------------------------

class _EmptyBanner extends StatelessWidget {
  const _EmptyBanner({required this.palette});

  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💡', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Planda henüz maliyet girilmemiş — Plan adımında aktivitelere '
              'ücret ekleyin.',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
