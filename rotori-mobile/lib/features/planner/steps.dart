// apps/planner/src/steps.ts birebir karşılığı.

import 'package:flutter/widgets.dart';

import '../../core/l10n.dart';

enum StepId { welcome, journey, title, hotels, plan, publish }

class StepDef {
  const StepDef(this.id, this.label, this.num);
  final StepId id;
  final String label;
  final int num;

  String labelFor(BuildContext context) =>
      LanguageScope.of(context).s('steps.${id.name}');
}

const List<StepDef> kSteps = [
  StepDef(StepId.welcome, 'Başla', 1),
  StepDef(StepId.journey, 'Rota', 2),
  StepDef(StepId.title, 'Başlık', 3),
  StepDef(StepId.hotels, 'Konaklama', 4),
  StepDef(StepId.plan, 'Plan', 5),
  StepDef(StepId.publish, 'Yayın', 6),
];

int stepIndex(StepId id) => kSteps.indexWhere((s) => s.id == id);
