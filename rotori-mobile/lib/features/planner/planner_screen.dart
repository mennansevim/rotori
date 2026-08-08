import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../data/language_store.dart';
import '../../data/plans_repository.dart';
import '../../domain/types.dart';
import '../plans/plan_providers.dart';
import 'planner_shell.dart';
import 'planner_theme.dart';
import 'steps.dart';
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
    if (_hotelsComplete(t)) done.add(StepId.hotels);
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
    final stayArea = t.preferences.stayArea?.trim() ?? '';
    if (stayArea.isNotEmpty) return true;
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

  /// Başla adımı tamam mı? Kullanıcı "biletim var" / "planlıyorum"
  /// kartlarından birini seçtiyse (hasTicket artık null değil) ya da plan
  /// zaten rota verisine sahipse (mevcut/ilerlemiş plan) tamamlanmış sayılır.
  bool _welcomeComplete(Trip t) =>
      t.preferences.hasTicket != null || _canContinueJourney(t);

  bool _planReady(Trip t) => t.days.any((d) => d.items.isNotEmpty);

  Set<StepId> _locked(Trip t) {
    final locked = <StepId>{};
    // Başla (welcome) bitmeden Rota ve sonrası kilitli — kullanıcı bir yol
    // ("biletim var" / "planlıyorum") seçmeden üstteki adım çubuğundan
    // 2. adıma (Rota) atlayamasın.
    if (!_welcomeComplete(t)) {
      locked.addAll([
        StepId.journey,
        StepId.title,
        StepId.hotels,
        StepId.plan,
        StepId.publish,
      ]);
    }
    if (!_canContinueJourney(t)) {
      locked.addAll([
        StepId.title,
        StepId.hotels,
        StepId.plan,
        StepId.publish,
      ]);
    }
    if (!_planReady(t)) locked.add(StepId.publish);
    return locked;
  }

  void _goNext() {
    HapticFeedback.lightImpact();
    final i = stepIndex(_step);
    if (i < kSteps.length - 1) setState(() => _step = kSteps[i + 1].id);
  }

  void _goPrev() {
    HapticFeedback.selectionClick();
    final i = stepIndex(_step);
    if (i > 0) setState(() => _step = kSteps[i - 1].id);
  }

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(planByIdProvider(widget.planId));
    final lang = ref.watch(appLangProvider);
    final s = LanguageScope.of(context);

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
    if (_step == StepId.hotels && !_hotelsComplete(trip)) {
      continueEnabled = false;
    }
    if (_step == StepId.plan && !_planReady(trip)) continueEnabled = false;

    return Theme(
      data: PT.theme(),
      child: Scaffold(
        backgroundColor: PT.bg,
        body: Column(
          children: [
            TopNav(
              lang: lang.code.toUpperCase(),
              onNewPlan: () => context.go('/plans'),
              onGuide: () => context.go('/plans/${widget.planId}/view'),
              onLang: () => ref.read(appLangProvider.notifier).set(
                    lang == AppLang.tr ? AppLang.en : AppLang.tr,
                  ),
            ),
            StepNav(
              current: _step,
              completed: completed,
              locked: locked,
              onStep: (s) => setState(() => _step = s),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                behavior: HitTestBehavior.translucent,
                child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (_step == StepId.plan || _step == StepId.journey)
                        ? 960
                        : 680,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: _buildBody(trip),
                    ),
                  ),
                ),
              ),
              ),
            ),
            if (!isWelcome)
              BottomBar(
                showBack: i > 0,
                onBack: _goPrev,
                continueLabel:
                    s.s(i < kSteps.length - 1 ? 'shell.continue' : 'shell.createPlan'),
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
