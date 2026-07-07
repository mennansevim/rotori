import 'package:flutter/material.dart';

import '../../../domain/types.dart';
import '../planner_theme.dart';

/// TitleStep.tsx birebir — başlık, açıklama, kişi sayısı, tempo.
class TitleStep extends StatelessWidget {
  const TitleStep({super.key, required this.trip, required this.onChange});
  final Trip trip;
  final void Function(void Function(Trip)) onChange;

  String _autoTitle() {
    final src = trip.tripStart.isNotEmpty ? trip.tripStart : trip.preferences.travelDates.start;
    final year = src.length >= 4 ? src.substring(0, 4) : '${DateTime.now().year}';
    return 'Japonya $year';
  }

  @override
  Widget build(BuildContext context) {
    final computed = _autoTitle();
    final route = (trip.preferences.originCity?.isNotEmpty ?? false) &&
            (trip.preferences.destinationCity?.isNotEmpty ?? false)
        ? '${trip.preferences.originCity} → ${trip.preferences.destinationCity}'
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
      children: [
        const PageHeadline('Planına isim ver'),
        PageSub(route != null ? 'Rotanız: $route · ${trip.days.length} gün' : 'Önce Rota adımında rotayı tamamlayın.'),
        PCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PCardTitle('Görünen ad'),
              PField(
                label: 'Başlık',
                child: PTextField(
                  value: trip.title,
                  hint: computed,
                  onChanged: (v) => onChange((t) => t.title = v),
                ),
                hint: Text(
                  'Gezinin yılına göre otomatik belirlenir (örn. $computed). İstersen elle değiştirebilirsin.',
                  style: const TextStyle(fontSize: 13, color: PT.textTertiary),
                ),
              ),
              PField(
                label: 'Açıklama (opsiyonel)',
                child: PTextField(
                  value: trip.subtitle ?? '',
                  hint: 'Kısa bir not',
                  onChanged: (v) => onChange((t) => t.subtitle = v),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PField(
                      label: 'Kişi sayısı',
                      child: PTextField(
                        value: '${trip.preferences.partySize ?? 2}',
                        keyboardType: TextInputType.number,
                        onChanged: (v) => onChange((t) => t.preferences.partySize = int.tryParse(v) ?? 2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: PField(
                      label: 'Tempo',
                      child: _PaceDropdown(
                        value: trip.preferences.pace,
                        onChanged: (p) => onChange((t) => t.preferences.pace = p),
                      ),
                    ),
                  ),
                ],
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
          items: const [
            DropdownMenuItem(value: Pace.relaxed, child: Text('Rahat')),
            DropdownMenuItem(value: Pace.moderate, child: Text('Dengeli')),
            DropdownMenuItem(value: Pace.intense, child: Text('Yoğun')),
          ],
          onChanged: (v) => v != null ? onChanged(v) : null,
        ),
      ),
    );
  }
}
