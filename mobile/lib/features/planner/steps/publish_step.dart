import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/rules.dart';
import '../../../domain/types.dart';
import '../planner_theme.dart';
import '../steps.dart';

/// apps/planner/src/components/steps/PublishStep.tsx portu.
/// Uyarı paneli (collectTripWarnings) + yayın kilidi notu.
class PublishStep extends StatelessWidget {
  const PublishStep({
    super.key,
    required this.trip,
    required this.onChange,
    this.onGoToStep,
  });
  final Trip trip;
  final void Function(void Function(Trip)) onChange;

  /// Uyarıdaki "adıma dön" için — rules.dart step string'i ('hotels', 'plan'...).
  final void Function(StepId step)? onGoToStep;

  static const Map<String, String> _stepLabelKeys = {
    'journey': 'publish.step.journey',
    'explore': 'publish.step.explore',
    'title': 'publish.step.title',
    'hotels': 'publish.step.hotels',
    'food': 'publish.step.food',
    'plan': 'publish.step.plan',
    'calendar': 'publish.step.calendar',
  };

  static const Map<String, StepId> _stepIds = {
    'journey': StepId.journey,
    'explore': StepId.explore,
    'title': StepId.title,
    'hotels': StepId.hotels,
    'food': StepId.food,
    'plan': StepId.plan,
  };

  Color _severityColor(TripWarningSeverity s) => switch (s) {
        TripWarningSeverity.info => const Color(0xFF0369A1),
        TripWarningSeverity.warn => const Color(0xFFB45309),
        TripWarningSeverity.urgent => PT.danger,
      };

  Color _severityBg(TripWarningSeverity s) => switch (s) {
        TripWarningSeverity.info => const Color(0x140369A1),
        TripWarningSeverity.warn => const Color(0x14B45309),
        TripWarningSeverity.urgent => const Color(0x14BF4800),
      };

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final warnings = collectTripWarnings(trip);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
      children: [
        PageHeadline(s.s('publish.title')),
        PageSub(s.p('publish.subtitle', {'slug': trip.slug})),

        // Uyarı panelleri
        for (final w in warnings)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _severityBg(w.severity),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _severityColor(w.severity).withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.p(w.messageKey, w.messageParams ?? const {}),
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: _severityColor(w.severity))),
                if (w.step != null &&
                    _stepIds[w.step] != null &&
                    onGoToStep != null) ...[
                  const SizedBox(height: 10),
                  PButton(
                    label: s.p('publish.backToStep', {
                      'step': s.s(_stepLabelKeys[w.step] ?? w.step!),
                    }),
                    primary: false,
                    onPressed: () => onGoToStep!(_stepIds[w.step]!),
                  ),
                ],
              ],
            ),
          ),

        // Yayın kilidi notu.
        PCard(
          child: Text(s.s('publish.lockNote'),
              style: const TextStyle(
                  fontSize: 13, color: PT.textTertiary, height: 1.4)),
        ),
      ],
    );
  }
}
