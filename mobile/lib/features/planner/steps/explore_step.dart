import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/destination_profiles.dart';
import '../../../domain/explore.dart';
import '../../../domain/japan_suggestions.dart';
import '../../../domain/trip_factory.dart';
import '../../../domain/types.dart';
import '../planner_theme.dart';
import '../widgets/option_data.dart';

/// apps/planner/src/components/steps/ExploreStep.tsx portu + tercih paneli.
/// İlgi alanları, yürüyüş/ulaşım/ödeme tercihi, mutlaka-görülecekler ve
/// destinasyon keşif kartları. Çocuk profili Rota adımına, yemek hassasiyeti
/// Yemek adımına taşındı.
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

  void _addMustSee(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return;
    widget.onChange((t) {
      if (!t.preferences.mustSee.contains(v)) t.preferences.mustSee.add(v);
    });
    _mustSeeCtrl.clear();
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
          'Uçuş güzergahınıza göre popüler yerler ve varışta yapılacaklar. '
          'Beğendiğinizi tek dokunuşla plana ekleyin.',
        ),
        _interestsBlock(),
        _travelStyleBlock(),
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
              const SizedBox(height: 10),
              // 2-sütun kompakt grid — telefon genişliği için tasarlandı.
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.95,
                children: [
                  for (final p in places)
                    _PopularPlaceCard(
                      emoji: p.emoji,
                      name: p.name,
                      city: p.city,
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
    ];
  }
}

/// "⭐ Popüler gezilecek yerler" bölümüne özel kompakt kart — 2-sütun grid için.
/// Emoji + ad (bold 14, 2 satır ellipsis) + puan (12 gold) + şehir (12 muted).
class _PopularPlaceCard extends StatelessWidget {
  const _PopularPlaceCard({
    required this.emoji,
    required this.name,
    required this.city,
    required this.rating,
    required this.kidFriendly,
    required this.selected,
    required this.feedback,
    required this.onTap,
  });

  final String emoji;
  final String name;
  final String city;
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
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 22)),
                  const Spacer(),
                  if (kidFriendly)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Text('🧸', style: TextStyle(fontSize: 12)),
                    ),
                  if (selected)
                    Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: PT.accent,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.check,
                          size: 12, color: Colors.white),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  feedback ?? name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: feedback != null ? PT.accent : PT.text,
                  ),
                ),
              ),
              if (rating != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('${ratingStars(rating!)} $rating',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB8860B))),
                ),
              if (city.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    city,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: PT.textTertiary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
