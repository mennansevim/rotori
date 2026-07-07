// apps/planner/src/steps.ts birebir karşılığı.

enum StepId { welcome, journey, explore, title, hotels, food, plan, publish }

class StepDef {
  const StepDef(this.id, this.label, this.num);
  final StepId id;
  final String label;
  final int num;
}

/// steps.ts STEPS dizisi — sıra ve etiketler birebir (i18n nav.* Türkçesi).
const List<StepDef> kSteps = [
  StepDef(StepId.welcome, 'Başla', 1),
  StepDef(StepId.journey, 'Rota', 2),
  StepDef(StepId.explore, 'Keşfet', 3),
  StepDef(StepId.title, 'Başlık', 4),
  StepDef(StepId.hotels, 'Konaklama', 5),
  StepDef(StepId.food, 'Yemek', 6),
  StepDef(StepId.plan, 'Plan', 7),
  StepDef(StepId.publish, 'Yayın', 8),
];

int stepIndex(StepId id) => kSteps.indexWhere((s) => s.id == id);
