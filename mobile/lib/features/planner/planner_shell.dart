import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/reminders_store.dart';
import 'planner_theme.dart';
import 'steps.dart';

/// styles.css .top-nav — sticky üst bar (marka + aksiyonlar).
class TopNav extends ConsumerWidget implements PreferredSizeWidget {
  const TopNav({
    super.key,
    required this.onNewPlan,
    required this.onGuide,
    required this.onLang,
    this.lang = 'TR',
  });
  final VoidCallback onNewPlan;
  final VoidCallback onGuide;
  final VoidCallback onLang;
  final String lang;

  @override
  Size get preferredSize => const Size.fromHeight(PT.navHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminderCount = ref.watch(remindersProvider).length;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xD1FBFBFD), // rgba(251,251,253,0.82)
        border: Border(bottom: BorderSide(color: PT.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  // Marka
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: PT.brandGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Text('✈️', style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(width: 10),
                  // Esnek: dar ekranda kısalır (…), sağdaki aksiyonlar taşmaz.
                  const Expanded(
                    child: Text(
                      'Seyahat',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                        color: PT.text,
                      ),
                    ),
                  ),
                  _BellButton(
                    count: reminderCount,
                    onTap: () => context.push('/reminders'),
                  ),
                  _GhostButton(label: '🌐 $lang', onTap: onLang),
                  _GhostButton(label: 'Yeni plan', onTap: onNewPlan),
                  _GhostButton(label: 'Rehber', onTap: onGuide),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Zil (hatırlatmalar) — sağ üstte badge sayı ile.
class _BellButton extends StatelessWidget {
  const _BellButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(PT.radiusPill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(LucideIcons.bell, size: 18, color: PT.accent),
              if (count > 0)
                Positioned(
                  right: -6,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE74C3C),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    constraints: const BoxConstraints(minWidth: 16),
                    alignment: Alignment.center,
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// styles.css .btn-ghost
class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(PT.radiusPill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          child: Text(
            label,
            style: const TextStyle(
              color: PT.accent,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Apple-stili adım flow'u: bağlı daireler + ilerleme çizgisi.
/// Tamamlanan ✓ (mavi), aktif dolu (siyah), kilitli 🔒 (soluk), sıradaki numaralı.
class StepNav extends StatelessWidget {
  const StepNav({
    super.key,
    required this.current,
    required this.completed,
    required this.locked,
    required this.onStep,
  });
  final StepId current;
  final Set<StepId> completed;
  final Set<StepId> locked;
  final void Function(StepId) onStep;

  @override
  Widget build(BuildContext context) {
    final currentIdx = stepIndex(current);
    return Container(
      decoration: const BoxDecoration(
        color: PT.bgSubtle,
        border: Border(bottom: BorderSide(color: PT.border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < kSteps.length; i++) ...[
                    if (i > 0)
                      _Connector(filled: i <= currentIdx),
                    _StepNode(
                      step: kSteps[i],
                      state: _stateFor(i, currentIdx, kSteps[i].id),
                      onTap: locked.contains(kSteps[i].id)
                          ? null
                          : () => onStep(kSteps[i].id),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  _NodeState _stateFor(int i, int currentIdx, StepId id) {
    if (id == current) return _NodeState.active;
    if (locked.contains(id)) return _NodeState.locked;
    if (completed.contains(id)) return _NodeState.done;
    return _NodeState.upcoming;
  }
}

enum _NodeState { active, done, locked, upcoming }

/// İki daire arasındaki ilerleme çizgisi (daire merkezi hizasında).
class _Connector extends StatelessWidget {
  const _Connector({required this.filled});
  final bool filled;
  @override
  Widget build(BuildContext context) {
    return Padding(
      // daire çapı 28 → merkez 14; çizgi 2px → top 13
      padding: const EdgeInsets.only(top: 13),
      child: Container(
        width: 28,
        height: 2,
        decoration: BoxDecoration(
          color: filled ? PT.accent : PT.borderStrong,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

/// Tek adım düğümü: daire (numara/✓/🔒) + altında etiket.
class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.step,
    required this.state,
    required this.onTap,
  });
  final StepDef step;
  final _NodeState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (Color circleBg, Color circleFg, Border? circleBorder) = switch (state) {
      _NodeState.active => (PT.text, Colors.white, null),
      _NodeState.done => (PT.accent, Colors.white, null),
      _NodeState.locked => (
          PT.bgSubtle,
          PT.textTertiary,
          Border.all(color: PT.borderStrong),
        ),
      _NodeState.upcoming => (
          PT.bgElevated,
          PT.textSecondary,
          Border.all(color: PT.borderStrong),
        ),
    };
    final labelColor = switch (state) {
      _NodeState.active => PT.text,
      _NodeState.done => PT.accent,
      _NodeState.locked => PT.textTertiary,
      _NodeState.upcoming => PT.textSecondary,
    };

    final Widget circleChild = switch (state) {
      _NodeState.done => const Icon(Icons.check, size: 16, color: Colors.white),
      _NodeState.locked =>
        const Icon(Icons.lock, size: 13, color: PT.textTertiary),
      _ => Text(
          '${step.num}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: circleFg,
          ),
        ),
    };

    return Opacity(
      opacity: state == _NodeState.locked ? 0.55 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: circleBg,
                  border: circleBorder,
                  boxShadow: state == _NodeState.active
                      ? const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: circleChild,
              ),
              const SizedBox(height: 6),
              Text(
                step.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      state == _NodeState.active ? FontWeight.w600 : FontWeight.w500,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// styles.css .bottom-bar — fixed alt aksiyon barı (Geri / Devam).
class BottomBar extends StatelessWidget {
  const BottomBar({
    super.key,
    required this.showBack,
    required this.onBack,
    required this.continueLabel,
    required this.onContinue,
    this.continueEnabled = true,
  });
  final bool showBack;
  final VoidCallback? onBack;
  final String continueLabel;
  final VoidCallback? onContinue;
  final bool continueEnabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xE6FBFBFD), // rgba(251,251,253,0.9)
        border: Border(top: BorderSide(color: PT.border)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  if (showBack)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 200),
                          child: PButton(
                            label: 'Geri',
                            primary: false,
                            block: true,
                            onPressed: onBack,
                          ),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: PButton(
                          label: continueLabel,
                          block: true,
                          onPressed: continueEnabled ? onContinue : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
