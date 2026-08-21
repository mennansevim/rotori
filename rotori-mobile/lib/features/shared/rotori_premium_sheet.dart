import 'package:flutter/material.dart';

const _premiumGold = Color(0xFFFFD166);
const _premiumInk = Color(0xFF211A47);

@immutable
class RotoriPremiumBenefit {
  const RotoriPremiumBenefit({required this.icon, required this.text});

  final IconData icon;
  final String text;
}

Future<T?> showRotoriPremiumSheet<T>(
  BuildContext context, {
  required String title,
  required String body,
  required String closeLabel,
  required List<RotoriPremiumBenefit> benefits,
  IconData emblem = Icons.workspace_premium_rounded,
  Key? sheetKey,
  Key? closeButtonKey,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => RotoriPremiumSheet(
      title: title,
      body: body,
      closeLabel: closeLabel,
      benefits: benefits,
      emblem: emblem,
      sheetKey: sheetKey,
      closeButtonKey: closeButtonKey,
      onClose: () => Navigator.of(sheetContext).pop(),
    ),
  );
}

class RotoriPremiumSheet extends StatelessWidget {
  const RotoriPremiumSheet({
    super.key,
    required this.title,
    required this.body,
    required this.closeLabel,
    required this.benefits,
    required this.onClose,
    this.emblem = Icons.workspace_premium_rounded,
    this.sheetKey,
    this.closeButtonKey,
  });

  final String title;
  final String body;
  final String closeLabel;
  final List<RotoriPremiumBenefit> benefits;
  final IconData emblem;
  final VoidCallback onClose;
  final Key? sheetKey;
  final Key? closeButtonKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return KeyedSubtree(
      key: sheetKey,
      child: Material(
        key: const ValueKey('rotori-premium-sheet'),
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 680,
              maxHeight: MediaQuery.sizeOf(context).height * .9,
            ),
            child: DecoratedBox(
              key: const ValueKey('rotori-premium-surface'),
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF211A47), Color(0xFF3A286D)],
                ),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(22, 14, 22, 22 + bottomInset),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .25),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      key: const ValueKey('rotori-premium-emblem'),
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: _premiumGold.withValues(alpha: .15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _premiumGold.withValues(alpha: .42),
                        ),
                      ),
                      child: Icon(emblem, color: _premiumGold, size: 31),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.5,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: .78),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),
                    for (var index = 0; index < benefits.length; index++) ...[
                      _BenefitRow(
                        key: ValueKey('rotori-premium-benefit-$index'),
                        benefit: benefits[index],
                      ),
                      if (index < benefits.length - 1)
                        const SizedBox(height: 9),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: closeButtonKey,
                        onPressed: onClose,
                        style: FilledButton.styleFrom(
                          backgroundColor: _premiumGold,
                          foregroundColor: _premiumInk,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          closeLabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w900),
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

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({super.key, required this.benefit});

  final RotoriPremiumBenefit benefit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(benefit.icon, size: 20, color: _premiumGold),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            benefit.text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .92),
              fontSize: 13.5,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
