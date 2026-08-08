import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n.dart';
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
    final s = LanguageScope.of(context);
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
                  Expanded(
                    child: Text(
                      s.s('shell.brand'),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
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
                  _GhostButton(label: s.s('shell.newPlan'), onTap: onNewPlan),
                  _GhostButton(label: s.s('shell.guide'), onTap: onGuide),
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

/// iOS-tarzı kompakt adım göstergesi: "Adım 3/8 · Rota" + ince progress bar.
/// Yatay scroll'lu 8 daire yerine tek satırda ilerlemeyi gösterir;
/// mobilde daha temiz ve Apple HIG uyumludur.
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
    final total = kSteps.length;
    final stepDef = kSteps[currentIdx];
    final progress = (currentIdx + 1) / total;

    return Container(
      decoration: const BoxDecoration(
        color: PT.bgSubtle,
        border: Border(bottom: BorderSide(color: PT.border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${currentIdx + 1}/$total',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: PT.accent,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      stepDef.labelFor(context),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: PT.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: PT.borderStrong,
                    color: PT.accent,
                    minHeight: 3,
                  ),
                ),
              ],
            ),
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
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xCCFBFBFD), // rgba(251,251,253,0.8) + blur
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
                              label: LanguageScope.of(context).s('shell.back'),
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
      ),
    );
  }
}
