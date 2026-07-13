import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/plans_repository.dart';
import '../../domain/types.dart';
import '../plans/plan_providers.dart';
import 'planner_shell.dart';
import 'planner_theme.dart';
import 'steps.dart';
import 'steps/explore_step.dart';
import 'steps/food_step.dart';
import 'steps/hotels_step.dart';
import 'steps/journey_step.dart';
import 'steps/plan_step.dart';
import 'steps/publish_step.dart';
import 'steps/title_step.dart';
import 'steps/welcome_step.dart';

/// apps/planner/src/App.tsx birebir shell:
/// top-nav + step-pills + adım gövdesi + bottom-bar, tek Trip'i düzenler.
class PlannerScreen extends ConsumerStatefulWidget {
  const PlannerScreen({super.key, required this.planId, this.initialStep});
  final String planId;

  /// Yalnızca önizleme/deep-link için başlangıç adımı; normalde welcome.
  final StepId? initialStep;

  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends ConsumerState<PlannerScreen> {
  Trip? _trip;
  late StepId _step = widget.initialStep ?? StepId.welcome;
  Timer? _saveDebounce;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  void _onChange(void Function(Trip) mutate) {
    if (_trip == null) return;
    setState(() => mutate(_trip!));
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () {
      final repo = ref.read(plansRepositoryProvider);
      final trip = _trip;
      if (repo != null && trip != null) repo.save(trip);
    });
  }

  // --- App.tsx: completedSteps ---
  Set<StepId> _completed(Trip t) {
    final done = <StepId>{};
    final dests = t.preferences.destinations;
    final hasRoute = ((t.preferences.originCity?.trim().isNotEmpty ?? false) ||
            (t.flights.outbound.isNotEmpty &&
                t.flights.outbound.first.city.trim().isNotEmpty)) &&
        dests.isNotEmpty &&
        dests.every((d) => d.city.trim().isNotEmpty);
    if (hasRoute && t.preferences.travelDates.start.isNotEmpty) {
      done.add(StepId.journey);
    }
    final title = t.title.trim();
    if (title.isNotEmpty &&
        title != 'Yeni seyahat' &&
        title != 'Japonya Turu') {
      done.add(StepId.title);
    }
    // Keşfet: opsiyonel gezgin tercihleri — en az bir ilgi alanı, gezgin
    // profili ya da yemek hassasiyeti seçilmişse tamamlandı say.
    // (React App.tsx'te explore hiç işaretlenmez; bilinçli hafif sapma.)
    if (t.preferences.interests.isNotEmpty ||
        t.preferences.childProfiles.isNotEmpty ||
        t.preferences.foodSensitivities.isNotEmpty) {
      done.add(StepId.explore);
    }
    if (_hotelsComplete(t)) done.add(StepId.hotels);
    if (t.preferences.destinationFood
        .any((f) => f.dietaryTags.isNotEmpty || f.foodLikes.isNotEmpty)) {
      done.add(StepId.food);
    }
    if (t.days.any((d) => d.items.isNotEmpty)) done.add(StepId.plan);
    done.add(StepId.publish);

    // Kullanıcı bir adımdan sonrakine ilerlediyse geçilen adımlar tick alır.
    // Continue butonu gerekli veri şartlarını zaten sağlıyor, o yüzden
    // "önceki tüm adımlar tamamlandı" varsayımı güvenli.
    final currentIdx = stepIndex(_step);
    for (var i = 0; i < currentIdx; i++) {
      done.add(kSteps[i].id);
    }
    return done;
  }

  bool _hotelsComplete(Trip t) {
    final dests = t.preferences.destinations;
    if (dests.isEmpty) return false;
    final hotels = t.hotels;
    if (hotels.isEmpty) return false;
    return hotels.every((h) =>
        h.city.trim().isNotEmpty &&
        h.name.trim().isNotEmpty &&
        h.address.trim().isNotEmpty);
  }

  bool _canContinueJourney(Trip t) {
    final dests = t.preferences.destinations;
    return ((t.preferences.originCity?.trim().isNotEmpty ?? false) ||
            (t.flights.outbound.isNotEmpty &&
                t.flights.outbound.first.city.trim().isNotEmpty)) &&
        dests.isNotEmpty &&
        dests.every((d) => d.city.trim().isNotEmpty);
  }

  bool _planReady(Trip t) => t.days.any((d) => d.items.isNotEmpty);

  Set<StepId> _locked(Trip t) {
    final locked = <StepId>{};
    if (!_canContinueJourney(t)) {
      locked.addAll([
        StepId.explore,
        StepId.title,
        StepId.hotels,
        StepId.food,
        StepId.plan,
        StepId.publish,
      ]);
    }
    if (!_planReady(t)) locked.add(StepId.publish);
    return locked;
  }

  void _goNext() {
    final i = stepIndex(_step);
    if (i < kSteps.length - 1) setState(() => _step = kSteps[i + 1].id);
  }

  void _goPrev() {
    final i = stepIndex(_step);
    if (i > 0) setState(() => _step = kSteps[i - 1].id);
  }

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(planByIdProvider(widget.planId));

    // İlk yüklemede local trip'i kur.
    planAsync.whenData((t) {
      _trip ??= t;
    });

    final trip = _trip;
    if (trip == null) {
      return Theme(
        data: PT.theme(),
        child: const Scaffold(
          backgroundColor: PT.bg,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final completed = _completed(trip);
    final locked = _locked(trip);
    final i = stepIndex(_step);
    final isWelcome = _step == StepId.welcome;

    // Bottom-bar continue disabled mantığı (App.tsx)
    bool continueEnabled = true;
    if (_step == StepId.journey && !_canContinueJourney(trip)) {
      continueEnabled = false;
    }
    if (_step == StepId.hotels && !_hotelsComplete(trip))
      continueEnabled = false;
    if (_step == StepId.plan && !_planReady(trip)) continueEnabled = false;

    return Theme(
      data: PT.theme(),
      child: Scaffold(
        backgroundColor: PT.bg,
        body: Column(
          children: [
            TopNav(
              onNewPlan: () => context.go('/plans'),
              onGuide: () => context.go('/plans/${widget.planId}/view'),
              onLang: () {},
            ),
            StepNav(
              current: _step,
              completed: completed,
              locked: locked,
              onStep: (s) => setState(() => _step = s),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (_step == StepId.plan || _step == StepId.journey)
                        ? 960
                        : 680,
                  ),
                  child: _buildBody(trip),
                ),
              ),
            ),
            if (!isWelcome)
              BottomBar(
                showBack: i > 0,
                onBack: _goPrev,
                continueLabel: i < kSteps.length - 1 ? 'Devam' : 'Rehber',
                continueEnabled: continueEnabled,
                onContinue: i < kSteps.length - 1
                    ? _goNext
                    : () => context.go('/plans/${widget.planId}/view'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(Trip trip) {
    switch (_step) {
      case StepId.welcome:
        return WelcomeStep(
          trip: trip,
          onChange: _onChange,
          onContinue: _goNext,
        );
      case StepId.journey:
        return JourneyStep(
          trip: trip,
          onChange: _onChange,
        );
      case StepId.explore:
        return ExploreStep(
          trip: trip,
          onChange: _onChange,
        );
      case StepId.title:
        return TitleStep(
          trip: trip,
          onChange: _onChange,
        );
      case StepId.hotels:
        return HotelsStep(
          trip: trip,
          onChange: _onChange,
        );
      case StepId.food:
        return FoodStep(
          trip: trip,
          onChange: _onChange,
        );
      case StepId.plan:
        return PlanStep(
          trip: trip,
          onChange: _onChange,
        );
      case StepId.publish:
        return PublishStep(
          trip: trip,
          onChange: _onChange,
          onGoToStep: (s) => setState(() => _step = s),
        );
    }
  }
}
