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
import 'steps/journey_step.dart';
import 'steps/welcome_step.dart';

/// apps/planner/src/App.tsx birebir shell:
/// top-nav + step-pills + adım gövdesi + bottom-bar, tek Trip'i düzenler.
class PlannerScreen extends ConsumerStatefulWidget {
  const PlannerScreen({super.key, required this.planId});
  final String planId;

  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends ConsumerState<PlannerScreen> {
  Trip? _trip;
  StepId _step = StepId.welcome;
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
    if (_hotelsComplete(t)) done.add(StepId.hotels);
    if (t.preferences.destinationFood
        .any((f) => f.dietaryTags.isNotEmpty || f.foodLikes.isNotEmpty)) {
      done.add(StepId.food);
    }
    if (t.days.any((d) => d.items.isNotEmpty)) done.add(StepId.plan);
    done.add(StepId.publish);
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
      default:
        return _NotYetPorted(step: _step);
    }
  }
}

/// Henüz portlanmamış adımlar için dürüst placeholder — sahte tasarım DEĞİL.
/// Bir sonraki iterasyonda ilgili React ekranı birebir portlanacak.
class _NotYetPorted extends StatelessWidget {
  const _NotYetPorted({required this.step});
  final StepId step;
  @override
  Widget build(BuildContext context) {
    final label = kSteps.firstWhere((s) => s.id == step).label;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
      children: [
        PageHeadline(label),
        const PageSub('Bu adım React planner\'dan birebir portlanıyor.'),
        PCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🚧 $label ekranı',
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: PT.text)),
              const SizedBox(height: 8),
              const Text(
                'Welcome ekranı + shell (top-nav, adım pill\'leri, bottom-bar) '
                'React tasarımıyla birebir hazır. Kalan adımlar sırayla, aynı '
                'sadakatle geliyor.',
                style: TextStyle(
                    fontSize: 14, color: PT.textSecondary, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
