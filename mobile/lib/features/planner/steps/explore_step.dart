import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/types.dart';
import '../planner_theme.dart';
import '../widgets/option_data.dart';

/// apps/planner/src/components/steps/ExploreStep.tsx portu + tercih paneli.
/// İlgi alanları, yürüyüş/ulaşım/ödeme tercihi ve mutlaka-görülecekler.
/// Popüler gezilecek yerler artık burada inline gösterilmez — "Gezi planı
/// oluştur"a basıldığında Plan adımında bir popup (PopularPlacesDialog) açılır.
class ExploreStep extends StatefulWidget {
  const ExploreStep({super.key, required this.trip, required this.onChange});
  final Trip trip;
  final void Function(void Function(Trip)) onChange;

  @override
  State<ExploreStep> createState() => _ExploreStepState();
}

class _ExploreStepState extends State<ExploreStep> {
  final TextEditingController _mustSeeCtrl = TextEditingController();

  Trip get trip => widget.trip;

  @override
  void dispose() {
    _mustSeeCtrl.dispose();
    super.dispose();
  }

  List<TripDestination> get _destinations =>
      [...trip.preferences.destinations]
        ..sort((a, b) => a.order.compareTo(b.order));

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

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final destinations = _destinations;
    if (destinations.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
        children: [
          PageHeadline(s.s('explore.title')),
          PageSub(s.s('explore.emptyAirports')),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
      children: [
        PageHeadline(s.s('explore.title')),
        PageSub(s.s('explore.sub')),
        _interestsBlock(),
        _travelStyleBlock(),
        _mustSeeBlock(),
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
    final s = LanguageScope.of(context);
    final interests = trip.preferences.interests;
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _blockTitle(s.s('explore.interests.title')),
          _hint(s.s('explore.interests.hint')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final opt in kInterestOptionsExplore)
                PChip(
                  label: '${opt.emoji} ${s.s(opt.label)}',
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
    final s = LanguageScope.of(context);
    final prefs = trip.preferences;
    final walking = prefs.walkingTarget ?? WalkingTarget.moderate;
    final transport = prefs.transportPreference ?? TransportPreference.transit;
    final payment = prefs.paymentPreference;
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _blockTitle(s.s('explore.style.title')),
          _hint(s.s('explore.style.hint')),
          Text(s.s('explore.style.walkLabel'),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: PT.text)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final opt in kWalkingOptions)
                PChip(
                  label: '${opt.emoji} ${s.s(opt.label)} · ${s.s(opt.hint!)}',
                  active: walking == opt.value,
                  onTap: () => widget.onChange(
                      (t) => t.preferences.walkingTarget = opt.value),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(s.s('explore.style.transportLabel'),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: PT.text)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final opt in kTransportOptions)
                PChip(
                  label: '${opt.emoji} ${s.s(opt.label)}',
                  active: transport == opt.value,
                  onTap: () => widget.onChange(
                      (t) => t.preferences.transportPreference = opt.value),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(s.s('explore.style.paymentLabel'),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: PT.text)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final opt in kPaymentOptions)
                PChip(
                  label: '${opt.emoji} ${s.s(opt.label)}',
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
    final s = LanguageScope.of(context);
    final mustSee = trip.preferences.mustSee;
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _blockTitle(s.s('explore.mustSee.title')),
          _hint(s.s('explore.mustSee.hint')),
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
                label: s.s('common.add'),
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
}
