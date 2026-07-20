import 'package:flutter/material.dart';

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

  static const List<({FoodSensitivity id, String label, String emoji})>
      _sensitivityOptions = [
    (id: FoodSensitivity.noPork, label: 'Domuz eti istemiyorum', emoji: '🚫🐖'),
    (
      id: FoodSensitivity.noPorkDerivatives,
      label: 'Domuz yağı / jelatin yok',
      emoji: '🚫🥓'
    ),
    (id: FoodSensitivity.noSeafood, label: 'Deniz ürünü istemiyorum', emoji: '🚫🐟'),
    (id: FoodSensitivity.halalOnly, label: 'Helal seçenek istiyorum', emoji: '🕌'),
    (id: FoodSensitivity.vegetarian, label: 'Vejetaryen', emoji: '🥗'),
    (id: FoodSensitivity.chickenFocus, label: 'Tavuk ağırlıklı', emoji: '🍗'),
    (id: FoodSensitivity.noFattyMeat, label: 'Yağlı et sevmiyorum', emoji: '🚫🥩'),
    (id: FoodSensitivity.kidFriendly, label: 'Çocuk dostu restoran', emoji: '🧒'),
    (
      id: FoodSensitivity.turkishPalate,
      label: 'Türk damak tadına yakın',
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
    final destinations = [...trip.preferences.destinations]
      ..sort((a, b) => a.order.compareTo(b.order));

    if (destinations.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
        children: const [
          PageHeadline('Yemek'),
          PageSub('Önce Rota adımında durak ekleyin.'),
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
        const PageHeadline('Yemek tercihleri'),
        const PageSub(
            'Hassasiyetlerini seç — plan ve restoran önerileri buna göre filtrelenir.'),

        // Global hassasiyet kartı
        PCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PCardTitle('🍽️ Yemek hassasiyetleri'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final opt in _sensitivityOptions)
                    PChip(
                      label: '${opt.emoji} ${opt.label}',
                      active: sensitivities.contains(opt.id),
                      onTap: () => _toggleSensitivity(opt.id),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Bu seçimler tüm gezi için geçerlidir; viewer\'da hap bilgi ve '
                'fraz kartlarına yansır.',
                style: TextStyle(fontSize: 13, color: PT.textSecondary, height: 1.4),
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
                      label: 'Kişi başı öğün ($currency)',
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
                      label: 'Para birimi',
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
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Öğünleri plana ekle',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: PT.text)),
                        SizedBox(height: 2),
                        Text(
                            'Gezi planı oluşturulurken öğle/akşam yemeği durakları eklenir.',
                            style:
                                TextStyle(fontSize: 12, color: PT.textTertiary)),
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

        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            'Yemek önerileri Rehber\'de (viewer) — bu hassasiyetlere göre '
            'restoranları orada listeliyoruz.',
            style: TextStyle(fontSize: 12, color: PT.textTertiary, height: 1.4),
          ),
        ),
      ],
    );
  }
}
