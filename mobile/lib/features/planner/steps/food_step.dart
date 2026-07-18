import 'package:flutter/material.dart';

import '../../../domain/destination_profiles.dart';
import '../../../domain/dietary.dart';
import '../../../domain/types.dart';
import '../planner_theme.dart';

/// apps/planner/src/components/steps/FoodStep.tsx birebir portu.
/// 9 emoji hassasiyet toggle → global foodSensitivities + dietaryTags,
/// destinasyon başına beslenme/mutfak seçimi, öğün bütçesi, planMeals.
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

  /// FoodStep.tsx getFoodPrefs — yoksa boş kayıt döndürür (mevcut listeye yazılmaz).
  DestinationFoodPrefs _getFoodPrefs(String destId) {
    for (final f in trip.preferences.destinationFood) {
      if (f.destinationId == destId) return f;
    }
    return DestinationFoodPrefs(destinationId: destId);
  }

  /// FoodStep.tsx patchFood — destinationFood içinde upsert eder.
  void _patchFood(String destId, void Function(DestinationFoodPrefs) mutate) {
    onChange((t) {
      final list = t.preferences.destinationFood;
      var idx = list.indexWhere((f) => f.destinationId == destId);
      if (idx < 0) {
        list.add(DestinationFoodPrefs(destinationId: destId));
        idx = list.length - 1;
      }
      mutate(list[idx]);
    });
  }

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
              const SizedBox(height: 12),
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

        for (final dest in destinations)
          _DestFoodCard(
            key: ValueKey(dest.id),
            dest: dest,
            food: _getFoodPrefs(dest.id),
            dayCount: trip.days
                .where((d) =>
                    getDestinationForDate(destinations, d.date)?.id == dest.id)
                .length,
            onPatch: (mutate) => _patchFood(dest.id, mutate),
          ),
      ],
    );
  }
}

class _DestFoodCard extends StatelessWidget {
  const _DestFoodCard({
    super.key,
    required this.dest,
    required this.food,
    required this.dayCount,
    required this.onPatch,
  });
  final TripDestination dest;
  final DestinationFoodPrefs food;
  final int dayCount;
  final void Function(void Function(DestinationFoodPrefs)) onPatch;

  void _toggleTag(String id) {
    onPatch((f) {
      if (f.dietaryTags.contains(id)) {
        f.dietaryTags.remove(id);
      } else {
        f.dietaryTags.add(id);
      }
    });
  }

  void _toggleCuisine(String label) {
    onPatch((f) {
      if (f.foodLikes.contains(label)) {
        f.foodLikes.remove(label);
      } else {
        f.foodLikes.add(label);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = getDestinationProfile(dest.countryCode);
    final tags = food.dietaryTags.toSet();
    final cuisines = profile?.cuisines ?? const [];
    final dishes = profile?.dishRecommendations ?? const [];
    final dietaryOpts = dietaryForCountry(dest.countryCode);
    final currency = profile?.defaultCurrency ?? 'EUR';

    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık: bayrak · ülke · şehir · ~n gün
          RichText(
            text: TextSpan(
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: PT.text),
              children: [
                TextSpan(text: '${profile?.flag ?? ''} ${dest.countryName}'),
                if (dest.city.isNotEmpty) TextSpan(text: ' · ${dest.city}'),
                TextSpan(
                  text: ' · ~$dayCount gün',
                  style: const TextStyle(
                      fontWeight: FontWeight.w400, color: PT.textTertiary),
                ),
              ],
            ),
          ),

          if (dishes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Önerilen lezzetler (${dest.countryName})',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: PT.text)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final dish in dishes)
                  PChip(
                    label:
                        '${food.foodLikes.contains(dish) ? '✓ ' : '+ '}$dish',
                    active: food.foodLikes.contains(dish),
                    onTap: () => _toggleCuisine(dish),
                  ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          const Text('Beslenme tercihleri',
              style: TextStyle(fontSize: 13, color: PT.textSecondary)),
          const SizedBox(height: 8),
          // 2-sütun kompakt grid — telefonda 2 tile yan yana sığar.
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.4,
            children: [
              for (final opt in dietaryOpts)
                _DietTile(
                  emoji: opt.emoji,
                  label: opt.label,
                  selected: tags.contains(opt.id),
                  onTap: () => _toggleTag(opt.id),
                ),
            ],
          ),

          if (cuisines.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Mutfak türleri',
                style: TextStyle(fontSize: 13, color: PT.textSecondary)),
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.4,
              children: [
                for (final c in cuisines)
                  _DietTile(
                    emoji: c.emoji,
                    label: c.label,
                    selected: food.foodLikes.contains(c.label),
                    onTap: () => _toggleCuisine(c.label),
                  ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: PField(
                  label: 'Kişi başı öğün ($currency)',
                  child: PTextField(
                    value: '${food.mealBudgetPerPerson ?? 50}',
                    keyboardType: TextInputType.number,
                    onChanged: (v) => onPatch(
                        (f) => f.mealBudgetPerPerson = int.tryParse(v) ?? 0),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: PField(
                  label: 'Para birimi',
                  child: PTextField(
                    value: food.mealBudgetCurrency ?? currency,
                    onChanged: (v) => onPatch((f) => f.mealBudgetCurrency = v),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Kompakt 2-sütun grid için — emoji + tek satır label. Grid hücresine sığar.
class _DietTile extends StatelessWidget {
  const _DietTile({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? PT.accentSoft : PT.bgSubtle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? PT.accent : PT.borderStrong),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? PT.accent : PT.text,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, size: 16, color: PT.accent),
            ],
          ),
        ),
      ),
    );
  }
}
