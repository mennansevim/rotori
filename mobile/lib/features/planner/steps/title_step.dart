import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/types.dart';
import '../planner_theme.dart';

/// TitleStep.tsx birebir — başlık, açıklama, tempo.
/// Kişi sayısı Rota adımının "Yolcu & seçenekler"inde yönetiliyor.
class TitleStep extends StatelessWidget {
  const TitleStep({super.key, required this.trip, required this.onChange});
  final Trip trip;
  final void Function(void Function(Trip)) onChange;

  String _autoTitle(BuildContext context) {
    final src = trip.tripStart.isNotEmpty ? trip.tripStart : trip.preferences.travelDates.start;
    final year = src.length >= 4 ? src.substring(0, 4) : '${DateTime.now().year}';
    return LanguageScope.of(context).p('title.autoTitle', {'year': year});
  }

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final computed = _autoTitle(context);
    final route = (trip.preferences.originCity?.isNotEmpty ?? false) &&
            (trip.preferences.destinationCity?.isNotEmpty ?? false)
        ? '${trip.preferences.originCity} → ${trip.preferences.destinationCity}'
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
      children: [
        PageHeadline(s.s('title.headline')),
        PageSub(route != null
            ? s.p('title.routeSummary', {'route': route, 'n': '${trip.days.length}'})
            : s.s('title.routeIncomplete')),
        PCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PCardTitle(s.s('title.displayName')),
              PField(
                label: s.s('title.field.title'),
                child: PTextField(
                  value: trip.title,
                  hint: computed,
                  onChanged: (v) => onChange((t) => t.title = v),
                ),
                hint: Text(
                  s.p('title.titleHint', {'sample': computed}),
                  style: const TextStyle(fontSize: 13, color: PT.textTertiary),
                ),
              ),
              PField(
                label: s.s('title.field.subtitle'),
                child: PTextField(
                  value: trip.subtitle ?? '',
                  hint: s.s('title.subtitleHint'),
                  onChanged: (v) => onChange((t) => t.subtitle = v),
                ),
              ),
              PField(
                label: s.s('title.field.pace'),
                child: _PaceDropdown(
                  value: trip.preferences.pace,
                  onChanged: (p) => onChange((t) => t.preferences.pace = p),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaceDropdown extends StatelessWidget {
  const _PaceDropdown({required this.value, required this.onChanged});
  final Pace value;
  final ValueChanged<Pace> onChanged;
  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: PT.bgSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PT.borderStrong),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Pace>(
          value: value,
          isExpanded: true,
          items: [
            DropdownMenuItem(value: Pace.relaxed, child: Text(s.s('title.pace.relaxed'))),
            DropdownMenuItem(value: Pace.moderate, child: Text(s.s('title.pace.moderate'))),
            DropdownMenuItem(value: Pace.intense, child: Text(s.s('title.pace.intense'))),
          ],
          onChanged: (v) => v != null ? onChanged(v) : null,
        ),
      ),
    );
  }
}
