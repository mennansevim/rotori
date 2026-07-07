import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/destination_profiles.dart';
import '../../../domain/dietary.dart';
import '../../../domain/explore.dart';
import '../../../domain/japan_suggestions.dart';
import '../../../domain/trip_factory.dart';
import '../../../domain/types.dart';
import '../planner_theme.dart';
import '../widgets/option_data.dart';

/// apps/planner/src/components/steps/ExploreStep.tsx portu + tercih paneli.
/// Çocuk profilleri, ilgi alanları, yürüyüş/ulaşım/ödeme tercihi, yemek
/// hassasiyetleri, mutlaka-görülecekler ve destinasyon keşif kartları.
class ExploreStep extends StatefulWidget {
  const ExploreStep({super.key, required this.trip, required this.onChange});
  final Trip trip;
  final void Function(void Function(Trip)) onChange;

  @override
  State<ExploreStep> createState() => _ExploreStepState();
}

class _ExploreStepState extends State<ExploreStep> {
  /// React `added` state'i — kart bazlı geçici geri bildirim rozetleri.
  final Map<String, String> _added = {};
  final Map<String, Timer> _addedTimers = {};
  final TextEditingController _mustSeeCtrl = TextEditingController();

  Trip get trip => widget.trip;

  @override
  void dispose() {
    for (final t in _addedTimers.values) {
      t.cancel();
    }
    _mustSeeCtrl.dispose();
    super.dispose();
  }

  void _markAdded(String key, String label) {
    _addedTimers[key]?.cancel();
    setState(() => _added[key] = label);
    _addedTimers[key] = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      setState(() => _added.remove(key));
    });
  }

  // --- React normalizeTitle: baştaki emoji/simgeleri at, küçük harfe indir ---
  String _normalizeTitle(String s) => s
      .replaceFirst(RegExp(r'^[^\p{L}\p{N}]+\s*', unicode: true), '')
      .toLowerCase()
      .trim();

  Set<String> get _planPlaceNames {
    final set = <String>{};
    for (final day in trip.days) {
      for (final item in day.items) {
        final t = _normalizeTitle(item.title);
        if (t.isNotEmpty) set.add(t);
      }
    }
    return set;
  }

  List<TripDestination> get _destinations =>
      [...trip.preferences.destinations]
        ..sort((a, b) => a.order.compareTo(b.order));

  int get _childrenCount => trip.preferences.childProfiles.isNotEmpty
      ? trip.preferences.childProfiles.length
      : (trip.preferences.childrenCount ?? 0);

  bool get _kidsMode => _childrenCount > 0;

  // ---- mutasyonlar ----

  void _toggleInterest(InterestTag tag) {
    widget.onChange((t) {
      final cur = t.preferences.interests;
      if (cur.contains(tag)) {
        cur.remove(tag);
      } else {
        cur.add(tag);
      }
    });
  }

  void _setChildrenCount(int count) {
    widget.onChange((t) {
      final cur = t.preferences.childProfiles;
      final next = <ChildProfile>[];
      for (var i = 0; i < count; i++) {
        next.add(i < cur.length
            ? cur[i]
            : ChildProfile(
                id: 'child-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-$i',
                age: 6,
              ));
      }
      t.preferences
        ..childProfiles = next
        ..childrenCount = count;
    });
  }

  void _setChildAge(String id, int age) {
    widget.onChange((t) {
      t.preferences.childProfiles = t.preferences.childProfiles
          .map((c) => c.id == id ? ChildProfile(id: c.id, age: age) : c)
          .toList();
    });
  }

  /// FoodStep.tsx toggleSensitivity ile aynı türetme mantığı.
  void _toggleSensitivity(FoodSensitivity id) {
    widget.onChange((t) {
      final cur = t.preferences.foodSensitivities;
      if (cur.contains(id)) {
        cur.remove(id);
      } else {
        cur.add(id);
      }
      final derived = dietaryTagsFromSensitivities(cur);
      const managed = [
        'no_pork',
        'no_seafood',
        'halal',
        'vegetarian',
        'kid_friendly',
        'chicken_focus',
        'turkish_palate',
        'no_fatty_meat',
      ];
      final kept =
          t.preferences.dietaryTags.where((tag) => !managed.contains(tag));
      t.preferences.dietaryTags = {...kept, ...derived}.toList();
    });
  }

  void _addMustSee(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return;
    widget.onChange((t) {
      if (!t.preferences.mustSee.contains(v)) t.preferences.mustSee.add(v);
    });
    _mustSeeCtrl.clear();
  }

  DestinationFoodPrefs _foodPrefsFor(Trip t, String destId) {
    for (final f in t.preferences.destinationFood) {
      if (f.destinationId == destId) return f;
    }
    return DestinationFoodPrefs(destinationId: destId);
  }

  void _toggleFoodInPlan(TripDestination dest, String label, String key) {
    final alreadyLiked = _foodPrefsFor(trip, dest.id).foodLikes.contains(label);
    widget.onChange((t) {
      final list = t.preferences.destinationFood;
      final idx = list.indexWhere((f) => f.destinationId == dest.id);
      final base = idx >= 0 ? list[idx] : _foodPrefsFor(t, dest.id);
      if (alreadyLiked) {
        base.foodLikes.remove(label);
      } else {
        base.foodLikes.add(label);
      }
      if (idx < 0) list.add(base);
    });
    _markAdded(key, alreadyLiked ? '✓ Plandan çıkarıldı' : '✓ Yemek planına eklendi');
  }

  void _removePlaceByName(String name) {
    final target = _normalizeTitle(name);
    widget.onChange((t) {
      t.days = t.days.map((d) {
        final items =
            d.items.where((it) => _normalizeTitle(it.title) != target).toList();
        if (items.length == d.items.length) return d;
        final tags =
            d.tags.where((tg) => _normalizeTitle(tg) != target).toList();
        final themeNorm = _normalizeTitle(d.theme);
        return d.copyWith(
          items: items,
          tags: tags,
          theme: themeNorm == target ? 'Gün ${d.dayNumber}' : d.theme,
        );
      }).toList();
    });
  }

  void _addPlace(TripDestination dest, PlaceSuggestion place) {
    if (_planPlaceNames.contains(place.name.toLowerCase().trim())) {
      _removePlaceByName(place.name);
      _markAdded('${dest.id}:${place.id}', '✓ Plandan çıkarıldı');
      return;
    }
    final dests = _destinations;
    final destDayNumbers = trip.days
        .where((day) => getDestinationForDate(dests, day.date)?.id == dest.id)
        .map((d) => d.dayNumber)
        .toList();
    final chosenDay = pickBestDayForDestination(trip.days, destDayNumbers) ??
        (trip.days.isNotEmpty ? trip.days.first.dayNumber : 1);
    widget.onChange((t) {
      t.days = addPlaceToDay(
        t.days,
        chosenDay,
        PlaceToAdd(
          name: place.name,
          emoji: place.emoji,
          steps: place.typicalSteps,
          city: place.city,
        ),
      );
    });
    if (chosenDay > 0) {
      _markAdded('${dest.id}:${place.id}', "✓ Gün $chosenDay'e eklendi");
    }
  }

  void _suggestKidRoute(TripDestination dest) {
    final profile = getDestinationProfile(dest.countryCode);
    if (profile == null) return;
    final kidPlaces = profile.popularPlaces.where(isKidFriendly).toList();
    final dests = _destinations;
    final countryDays = trip.days
        .where((d) => getDestinationForDate(dests, d.date)?.id == dest.id)
        .toList();
    if (kidPlaces.isEmpty || countryDays.isEmpty) return;
    widget.onChange((t) {
      var days = t.days;
      for (var i = 0; i < kidPlaces.length; i++) {
        final p = kidPlaces[i];
        final dn = countryDays[i % countryDays.length].dayNumber;
        days = addPlaceToDay(days, dn,
            PlaceToAdd(name: p.name, emoji: p.emoji, steps: p.typicalSteps));
      }
      t.days = days;
    });
    _markAdded('kidroute:${dest.id}',
        '✓ ${kidPlaces.length} yer ${countryDays.length} güne dağıtıldı');
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations;
    if (destinations.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
        children: const [
          PageHeadline('Keşfet'),
          PageSub('Önce Rota adımında varış havaalanlarını seçin.'),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
      children: [
        const PageHeadline('Keşfet'),
        const PageSub(
          'Uçuş güzergahınıza göre popüler yerler, önerilen yemekler ve '
          'varışta yapılacaklar. Beğendiğinizi tek dokunuşla plana ekleyin.',
        ),
        _childProfileBlock(),
        _interestsBlock(),
        _travelStyleBlock(),
        _sensitivitiesBlock(),
        _mustSeeBlock(),
        for (final dest in destinations) ..._destinationSections(dest),
      ],
    );
  }

  Widget _blockTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: PT.text)),
      );

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(fontSize: 13, color: PT.textSecondary)),
      );

  Widget _childProfileBlock() {
    final profiles = trip.preferences.childProfiles;
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _blockTitle('👶 Çocuk profili'),
          _hint('Yanında gelen çocuk varsa seç — plan çocuk dostu kurulur.'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in const [0, 1, 2, 3, 4])
                PChip(
                  label: n == 0 ? '— Çocuk yok' : '$n çocuk',
                  active: _childrenCount == n,
                  onTap: () => _setChildrenCount(n),
                ),
            ],
          ),
          if (profiles.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Yaşları',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: PT.text)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < profiles.length; i++)
                  _ChildAgeCard(
                    label: 'Çocuk ${i + 1}',
                    age: profiles[i].age,
                    onDec: () => _setChildAge(
                        profiles[i].id, (profiles[i].age - 1).clamp(0, 18)),
                    onInc: () => _setChildAge(
                        profiles[i].id, (profiles[i].age + 1).clamp(0, 18)),
                  ),
              ],
            ),
          ],
          if (_kidsMode)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '$_childrenCount çocuk seçili — çocuk dostu yerler öne '
                'çıkarılıyor, molalar artırılıyor.',
                style: const TextStyle(fontSize: 13, color: PT.accent),
              ),
            ),
        ],
      ),
    );
  }

  Widget _interestsBlock() {
    final interests = trip.preferences.interests;
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _blockTitle('🎯 İlgi alanların'),
          _hint('Birden fazla seç. Plan bunlara göre yönlendirilir.'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final opt in kInterestOptionsExplore)
                PChip(
                  label: '${opt.emoji} ${opt.label}',
                  active: interests.contains(opt.value),
                  onTap: () => _toggleInterest(opt.value),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _travelStyleBlock() {
    final prefs = trip.preferences;
    final walking = prefs.walkingTarget ?? WalkingTarget.moderate;
    final transport = prefs.transportPreference ?? TransportPreference.transit;
    final payment = prefs.paymentPreference;
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _blockTitle('🚶 Gezi stili'),
          _hint('Yürüyüş hedefi, ulaşım ve ödeme tercihini seç.'),
          const Text('Yürüyüş tempon',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: PT.text)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final opt in kWalkingOptions)
                PChip(
                  label: '${opt.emoji} ${opt.label} · ${opt.hint}',
                  active: walking == opt.value,
                  onTap: () => widget.onChange(
                      (t) => t.preferences.walkingTarget = opt.value),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Ulaşım tercihi',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: PT.text)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final opt in kTransportOptions)
                PChip(
                  label: '${opt.emoji} ${opt.label}',
                  active: transport == opt.value,
                  onTap: () => widget.onChange(
                      (t) => t.preferences.transportPreference = opt.value),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Ödeme tercihi',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: PT.text)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final opt in kPaymentOptions)
                PChip(
                  label: '${opt.emoji} ${opt.label}',
                  active: payment == opt.value,
                  onTap: () => widget.onChange(
                      (t) => t.preferences.paymentPreference = opt.value),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sensitivitiesBlock() {
    final sensitivities = trip.preferences.foodSensitivities;
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _blockTitle('🍽️ Yemek hassasiyetleri'),
          _hint('Plan ve restoran önerileri buna göre filtrelenir.'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final opt in kSensitivityOptions)
                PChip(
                  label: '${opt.emoji} ${opt.label}',
                  active: sensitivities.contains(opt.value),
                  onTap: () => _toggleSensitivity(opt.value),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mustSeeBlock() {
    final mustSee = trip.preferences.mustSee;
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _blockTitle('📌 Mutlaka görmek istediklerin'),
          _hint('Serbest liste — plan oluştururken önceliklendirilir.'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _mustSeeCtrl,
                  onSubmitted: _addMustSee,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Skytree, Fushimi Inari, teamLab…',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    filled: true,
                    fillColor: PT.bgSubtle,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: PT.borderStrong),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: PT.accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              PButton(
                label: 'Ekle',
                onPressed: () => _addMustSee(_mustSeeCtrl.text),
              ),
            ],
          ),
          if (mustSee.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final place in mustSee)
                  InputChip(
                    label: Text(place, style: const TextStyle(fontSize: 13)),
                    onDeleted: () => widget
                        .onChange((t) => t.preferences.mustSee.remove(place)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _destinationSections(TripDestination dest) {
    final profile = getDestinationProfile(dest.countryCode);
    final foods = recommendedFoods(dest.countryCode);
    var places = profile?.popularPlaces ?? const <PlaceSuggestion>[];
    if (_kidsMode) {
      places = [...places]..sort((a, b) =>
          (isKidFriendly(b) ? 1 : 0).compareTo(isKidFriendly(a) ? 1 : 0));
    }
    final planNames = _planPlaceNames;

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
        child: Row(
          children: [
            Text(
              '${profile?.flag ?? ''} ${dest.countryName.isNotEmpty ? dest.countryName : dest.city}',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: PT.text),
            ),
            const SizedBox(width: 8),
            if (dest.city.isNotEmpty)
              Text(dest.city,
                  style: const TextStyle(
                      fontSize: 14, color: PT.textSecondary)),
          ],
        ),
      ),
      if (places.isNotEmpty)
        PCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('⭐ Popüler gezilecek yerler',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: PT.text)),
                  ),
                  if (_kidsMode)
                    PButton(
                      label: _added['kidroute:${dest.id}'] ??
                          '🧸 Çocuk dostu rota öner',
                      primary: false,
                      onPressed: () => _suggestKidRoute(dest),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final p in places)
                    ExploreCard(
                      emoji: p.emoji,
                      name: p.name,
                      meta: p.city,
                      rating: placeRating(p),
                      kidFriendly: isKidFriendly(p),
                      selected:
                          planNames.contains(p.name.toLowerCase().trim()),
                      feedback: _added['${dest.id}:${p.id}'],
                      onTap: () => _addPlace(dest, p),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              const Text('Dokunarak ekle · ✓ rozetli karta tekrar dokun → çıkar',
                  style: TextStyle(fontSize: 12, color: PT.textTertiary)),
            ],
          ),
        ),
      if (foods.isNotEmpty)
        PCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🍽️ Önerilen yemekler',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: PT.text)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var idx = 0; idx < foods.length; idx++)
                    ExploreCard(
                      emoji: foods[idx].emoji ?? '🍽️',
                      name: foods[idx].label,
                      selected: _foodPrefsFor(trip, dest.id)
                          .foodLikes
                          .contains(foods[idx].label),
                      feedback: _added['food:${dest.id}:food-${dest.id}-$idx'],
                      onTap: () => _toggleFoodInPlan(dest, foods[idx].label,
                          'food:${dest.id}:food-${dest.id}-$idx'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                  'Dokunarak yemek planına ekle · ✓ rozetli karta tekrar dokun → çıkar',
                  style: TextStyle(fontSize: 12, color: PT.textTertiary)),
            ],
          ),
        ),
    ];
  }
}

/// ExploreCardGrid.tsx kart karşılığı — emoji + ad + puan + çocuk rozeti.
class ExploreCard extends StatelessWidget {
  const ExploreCard({
    super.key,
    required this.emoji,
    required this.name,
    required this.selected,
    required this.onTap,
    this.meta,
    this.rating,
    this.kidFriendly = false,
    this.feedback,
  });

  final String emoji;
  final String name;
  final String? meta;
  final double? rating;
  final bool kidFriendly;
  final bool selected;
  final String? feedback;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? PT.accentSoft : PT.bgSubtle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PT.radius),
        side: BorderSide(color: selected ? PT.accent : PT.borderStrong),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(PT.radius),
        onTap: onTap,
        child: Container(
          width: 150,
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 22)),
                  const Spacer(),
                  if (selected)
                    Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: PT.accent,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.check,
                          size: 13, color: Colors.white),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                feedback ?? name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: feedback != null ? PT.accent : PT.text,
                ),
              ),
              if (meta != null || rating != null || kidFriendly) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (rating != null)
                      Text('${ratingStars(rating!)} $rating',
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFFB8860B))),
                    if (rating != null && (meta != null || kidFriendly))
                      const SizedBox(width: 6),
                    if (meta != null)
                      Flexible(
                        child: Text(meta!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: PT.textTertiary)),
                      ),
                    if (kidFriendly)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Text('🧸', style: TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChildAgeCard extends StatelessWidget {
  const _ChildAgeCard({
    required this.label,
    required this.age,
    required this.onDec,
    required this.onInc,
  });
  final String label;
  final int age;
  final VoidCallback onDec;
  final VoidCallback onInc;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: PT.bgSubtle,
        borderRadius: BorderRadius.circular(PT.radius),
        border: Border.all(color: PT.borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: PT.textSecondary)),
          const SizedBox(width: 10),
          _StepperBtn(label: '−', onTap: onDec, semantics: 'Yaşı azalt'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('$age',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: PT.text)),
          ),
          _StepperBtn(label: '+', onTap: onInc, semantics: 'Yaşı arttır'),
          const SizedBox(width: 6),
          const Text('yaş',
              style: TextStyle(fontSize: 12, color: PT.textTertiary)),
        ],
      ),
    );
  }
}

class _StepperBtn extends StatelessWidget {
  const _StepperBtn(
      {required this.label, required this.onTap, required this.semantics});
  final String label;
  final VoidCallback onTap;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantics,
      child: Material(
        color: PT.bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: PT.borderStrong),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: const SizedBox(width: 44, height: 44)
              .let((box) => SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                        child: Text(label,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: PT.text))),
                  )),
        ),
      ),
    );
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
