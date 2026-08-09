// Oluşturma akışı 2/2 — "Ne zaman?"
//
// Gün dağılımı önizlemesi GERÇEK üretim fonksiyonundan beslenir
// (previewCityDistribution) — burada ayrı bir hesap YOKTUR.

import 'package:flutter/material.dart';

import '../../../core/date_format.dart';
import '../../../core/l10n.dart';
import '../../../domain/plan_generation.dart';
import '../../../domain/route_sanity.dart';
import '../../viewer/viewer_theme.dart';
import 'route_warning_card.dart';
import 'create_plan_widgets.dart';

class DateSelectPage extends StatelessWidget {
  const DateSelectPage({
    super.key,
    required this.palette,
    required this.startYmd,
    required this.endYmd,
    required this.cityCount,
    required this.datesEstimated,
    required this.distribution,
    required this.generating,
    required this.onPickRange,
    required this.onUnknownDates,
    required this.onEditCities,
    required this.onGenerate,
    required this.onAdjustDays,
    required this.routeSanity,
    required this.selectedKeys,
    required this.onFixRoute,
  });

  final ViewerPalette palette;
  final String startYmd;
  final String endYmd;
  final int cityCount;
  final bool datesEstimated;
  final List<CityNights> distribution;
  final bool generating;
  final VoidCallback onPickRange;
  final VoidCallback onUnknownDates;
  final VoidCallback onEditCities;
  final VoidCallback? onGenerate;

  /// (şehirKey, delta) — kullanıcı bir şehrin gününü ±1 değiştirdi. Toplam
  /// gün sabit kaldığı için fark komşu şehirden alınır/verilir.
  final void Function(String cityKey, int delta) onAdjustDays;

  /// Rota sırası tutarlılık sonucu — mantıksızsa kart gösterilir.
  final RouteSanity routeSanity;
  final List<String> selectedKeys;
  final void Function(List<String> order) onFixRoute;

  bool get _hasDates => startYmd.isNotEmpty && endYmd.isNotEmpty;
  int get _totalDays => inclusiveDays(startYmd, endYmd);
  bool get _tooManyCities => _hasDates && cityCount > _totalDays;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            children: [
              _DateCard(
                palette: palette,
                startYmd: startYmd,
                endYmd: endYmd,
                onTap: onPickRange,
              ),
              if (!_hasDates) ...[
                const SizedBox(height: 12),
                _UnknownDatesPill(palette: palette, onTap: onUnknownDates),
              ],
              if (datesEstimated) ...[
                const SizedBox(height: 12),
                _Note(
                  palette: palette,
                  color: palette.gold,
                  text: s.s('create.dates.estimated'),
                ),
              ],
              if (_tooManyCities) ...[
                const SizedBox(height: 12),
                _Note(
                  palette: palette,
                  color: palette.sunset,
                  text: s.s('create.dates.tooManyCities'),
                  action: TextButton(
                    onPressed: onEditCities,
                    child: Text(
                      s.s('create.dates.editCities'),
                      style: TextStyle(
                        color: palette.sunset,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
              if (_hasDates && !_tooManyCities && distribution.isNotEmpty) ...[
                const SizedBox(height: 14),
                RouteWarningCard(
                  palette: palette,
                  sanity: routeSanity,
                  currentOrder: selectedKeys,
                  onApply: onFixRoute,
                ),
                _NightsBreakdownCard(
                  palette: palette,
                  totalDays: _totalDays,
                  distribution: distribution,
                  onAdjustDays: onAdjustDays,
                ),
              ],
            ],
          ),
        ),
        CreateBottomBar(
          palette: palette,
          child: BrandButton(
            palette: palette,
            block: true,
            busy: generating,
            // Bu artık son adım DEĞİL: tarihlerden sonra beslenme tercihi ve
            // öğün bütçesi adımı geliyor. "Oluştur" demek yanıltıcı olurdu.
            label: generating
                ? s.s('create.generating')
                : s.s('create.dates.continue'),
            onPressed: onGenerate,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _DateCard extends StatelessWidget {
  const _DateCard({
    required this.palette,
    required this.startYmd,
    required this.endYmd,
    required this.onTap,
  });
  final ViewerPalette palette;
  final String startYmd;
  final String endYmd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final hasDates = startYmd.isNotEmpty && endYmd.isNotEmpty;

    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: hasDates ? palette.border : palette.fuji.withValues(alpha: 0.5),
              width: hasDates ? 1 : 1.5,
            ),
          ),
          child: hasDates
              ? Row(
                  children: [
                    Expanded(
                      child: _DateColumn(
                        palette: palette,
                        label: s.s('create.dates.depart'),
                        ymd: startYmd,
                        lang: s.lang,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 38,
                      color: palette.border,
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    Expanded(
                      child: _DateColumn(
                        palette: palette,
                        label: s.s('create.dates.return'),
                        ymd: endYmd,
                        lang: s.lang,
                      ),
                    ),
                    Text(
                      s.s('create.dates.change'),
                      style: TextStyle(
                        color: palette.fuji,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Icon(Icons.calendar_month_rounded,
                        color: palette.fuji, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.s('create.dates.pick'),
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.s('create.dates.pickHint'),
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: palette.textMuted),
                  ],
                ),
        ),
      ),
    );
  }
}

class _DateColumn extends StatelessWidget {
  const _DateColumn({
    required this.palette,
    required this.label,
    required this.ymd,
    required this.lang,
  });
  final ViewerPalette palette;
  final String label;
  final String ymd;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          formatShortDate(ymd, lang),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _UnknownDatesPill extends StatelessWidget {
  const _UnknownDatesPill({required this.palette, required this.onTap});
  final ViewerPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: palette.card,
        borderRadius: BorderRadius.circular(980),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(980),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(980),
              border: Border.all(color: palette.borderStrong),
            ),
            child: Text(
              s.s('create.dates.unknown'),
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({
    required this.palette,
    required this.color,
    required this.text,
    this.action,
  });
  final ViewerPalette palette;
  final Color color;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (action != null)
            Align(alignment: Alignment.centerLeft, child: action!),
        ],
      ),
    );
  }
}

class _NightsBreakdownCard extends StatelessWidget {
  const _NightsBreakdownCard({
    required this.palette,
    required this.totalDays,
    required this.distribution,
    required this.onAdjustDays,
  });
  final ViewerPalette palette;
  final int totalDays;
  final List<CityNights> distribution;
  final void Function(String cityKey, int delta) onAdjustDays;

  /// Bir şehirden gün alınabilmesi için en az 1 günü kalmalı; gün eklenebilmesi
  /// için başka bir şehrin 1'den fazla günü olmalı (toplam sabit).
  bool _canDecrease(CityNights c) => c.days > 1;
  bool _canIncrease(CityNights c) =>
      distribution.any((o) => o.cityKey != c.cityKey && o.days > 1);

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final maxDays = distribution.fold<int>(1, (m, c) => c.days > m ? c.days : m);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.p('create.dates.nights', {
              'nights': '${totalDays - 1}',
              'days': '$totalDays',
            }),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          for (final c in distribution) ...[
            Row(
              children: [
                Text(c.emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  child: Text(
                    c.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maxDays == 0 ? 0 : c.days / maxDays,
                      backgroundColor: palette.border,
                      color: palette.fuji,
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _DayStepper(
                  palette: palette,
                  days: c.days,
                  label: s.p('create.dates.cityDays', {'n': '${c.days}'}),
                  onDecrease: _canDecrease(c)
                      ? () => onAdjustDays(c.cityKey, -1)
                      : null,
                  onIncrease: _canIncrease(c)
                      ? () => onAdjustDays(c.cityKey, 1)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 2),
          Text(
            s.s('create.dates.splitEditable'),
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// −  N gün  +  — toplam gün sabit kalır, fark komşu şehirden alınır.
class _DayStepper extends StatelessWidget {
  const _DayStepper({
    required this.palette,
    required this.days,
    required this.label,
    required this.onDecrease,
    required this.onIncrease,
  });
  final ViewerPalette palette;
  final int days;
  final String label;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepperButton(
          palette: palette,
          icon: Icons.remove_rounded,
          onTap: onDecrease,
        ),
        SizedBox(
          width: 52,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _StepperButton(
          palette: palette,
          icon: Icons.add_rounded,
          onTap: onIncrease,
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.palette,
    required this.icon,
    required this.onTap,
  });
  final ViewerPalette palette;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.3,
        child: Material(
          color: palette.elevated,
          shape: CircleBorder(side: BorderSide(color: palette.border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 30,
              height: 30,
              child: Icon(icon, size: 16, color: palette.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
