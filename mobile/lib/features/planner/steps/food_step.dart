import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/destination_profiles.dart';
import '../../../domain/dietary.dart';
import '../../../domain/types.dart';
import '../planner_theme.dart';

/// apps/planner/src/components/steps/FoodStep.tsx portu (sadeleştirilmiş).
/// 9 emoji hassasiyet toggle → global foodSensitivities + dietaryTags,
/// öğün bütçesi ve planMeals. Destinasyon başına lezzet/mutfak seçimi ve
/// restoran önerileri Rehber'e (viewer) taşındı.
class FoodStep extends StatelessWidget {
  const FoodStep({super.key, required this.trip, required this.onChange});
  final Trip trip;
  final void Function(void Function(Trip)) onChange;

  // `label` alanları L10n anahtarıdır; build içinde s(opt.label) ile çözülür.
  static const List<({FoodSensitivity id, String label, String emoji})>
      _sensitivityOptions = [
    (id: FoodSensitivity.noPork, label: 'food.sens.noPork', emoji: '🚫🐖'),
    (
      id: FoodSensitivity.noPorkDerivatives,
      label: 'food.sens.noPorkDerivatives',
      emoji: '🚫🥓'
    ),
    (id: FoodSensitivity.noSeafood, label: 'food.sens.noSeafood', emoji: '🚫🐟'),
    (id: FoodSensitivity.halalOnly, label: 'food.sens.halal', emoji: '🕌'),
    (id: FoodSensitivity.vegetarian, label: 'food.sens.vegetarian', emoji: '🥗'),
    (id: FoodSensitivity.chickenFocus, label: 'food.sens.chicken', emoji: '🍗'),
    (id: FoodSensitivity.noFattyMeat, label: 'food.sens.noFattyMeat', emoji: '🚫🥩'),
    (id: FoodSensitivity.kidFriendly, label: 'food.sens.kidFriendly', emoji: '🧒'),
    (
      id: FoodSensitivity.turkishPalate,
      label: 'food.sens.turkishPalate',
      emoji: '🇹🇷'
    ),
  ];

  // foodSensitivity'den türeyen tag'ler (React'taki sabit liste).
  static const _derivedTagIds = {
    'no_pork',
    'no_seafood',
    'halal',
    'vegetarian',
    'kid_friendly',
    'chicken_focus',
    'turkish_palate',
    'no_fatty_meat',
  };

  void _toggleSensitivity(FoodSensitivity id) {
    onChange((t) {
      final cur = t.preferences.foodSensitivities;
      if (cur.contains(id)) {
        cur.remove(id);
      } else {
        cur.add(id);
      }
      final derived = dietaryTagsFromSensitivities(cur).toSet();
      // Elle eklenen (türetilmemiş) tag'leri koru, türetilenleri yeniden hesapla.
      final existing =
          t.preferences.dietaryTags.where((tag) => !_derivedTagIds.contains(tag));
      t.preferences.dietaryTags = {...existing, ...derived}.toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final destinations = [...trip.preferences.destinations]
      ..sort((a, b) => a.order.compareTo(b.order));

    if (destinations.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
        children: [
          PageHeadline(s.s('food.title')),
          PageSub(s.s('food.emptyStops')),
        ],
      );
    }

    final sensitivities = trip.preferences.foodSensitivities.toSet();
    // Rota'daki ilk destinasyondan para birimini türet — global bütçe için.
    final currency =
        getDestinationProfile(destinations.first.countryCode)?.defaultCurrency ??
            'EUR';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
      children: [
        PageHeadline(s.s('food.prefsTitle')),
        PageSub(s.s('food.prefsSub')),

        // Global hassasiyet kartı
        PCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PCardTitle(s.s('food.sensTitle')),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final opt in _sensitivityOptions)
                    PChip(
                      label: '${opt.emoji} ${s.s(opt.label)}',
                      active: sensitivities.contains(opt.id),
                      onTap: () => _toggleSensitivity(opt.id),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                s.s('food.sensNote'),
                style: const TextStyle(
                    fontSize: 13, color: PT.textSecondary, height: 1.4),
              ),
            ],
          ),
        ),

        // Öğün bütçesi + planMeals kartı
        PCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PField(
                      label: s.p('food.mealPerPerson', {'currency': currency}),
                      child: PTextField(
                        value: '${trip.preferences.mealBudgetPerPerson ?? 50}',
                        keyboardType: TextInputType.number,
                        onChanged: (v) => onChange((t) => t.preferences
                            .mealBudgetPerPerson = int.tryParse(v) ?? 0),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: PField(
                      label: s.s('food.currency'),
                      child: PTextField(
                        value: trip.preferences.mealBudgetCurrency ?? currency,
                        onChanged: (v) => onChange(
                            (t) => t.preferences.mealBudgetCurrency = v),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.s('food.addMeals'),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: PT.text)),
                        const SizedBox(height: 2),
                        Text(s.s('food.addMealsHint'),
                            style: const TextStyle(
                                fontSize: 12, color: PT.textTertiary)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch.adaptive(
                    value: trip.preferences.planMeals ?? true,
                    activeTrackColor: PT.accent,
                    onChanged: (v) =>
                        onChange((t) => t.preferences.planMeals = v),
                  ),
                ],
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            s.s('food.viewerNote'),
            style: const TextStyle(
                fontSize: 12, color: PT.textTertiary, height: 1.4),
          ),
        ),
      ],
    );
  }
}
