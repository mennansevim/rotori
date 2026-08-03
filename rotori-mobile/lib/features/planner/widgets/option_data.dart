// Planner adımlarında paylaşılan seçenek listeleri.
// Kaynaklar: ExploreStep.tsx INTEREST_OPTIONS, FoodStep.tsx SENSITIVITY_OPTIONS,
// PlanStep.tsx INTEREST/WALKING/TRANSPORT/PACE_OPTIONS.
//
// i18n: Kullanıcıya görünen `label`/`hint` alanları artık L10n anahtarıdır
// (ör. 'opt.interest.food'). Çağrı yerleri LanguageScope.of(context).s(opt.label)
// ile çözer. Enum `value` ve `emoji` alanları çeviri dışıdır.

import '../../../domain/types.dart';

class LabeledOption<T> {
  const LabeledOption(this.value, this.label, this.emoji, [this.hint]);
  final T value;

  /// L10n anahtarı — çağrı yerinde s(label) ile çözülür.
  final String label;
  final String emoji;

  /// L10n anahtarı (opsiyonel) — çağrı yerinde s(hint!) ile çözülür.
  final String? hint;
}

/// ExploreStep.tsx INTEREST_OPTIONS — sıra ve emoji birebir.
const List<LabeledOption<InterestTag>> kInterestOptionsExplore = [
  LabeledOption(InterestTag.anime, 'opt.interest.anime', '🎴'),
  LabeledOption(InterestTag.pokemon, 'opt.interest.pokemon', '⚡'),
  LabeledOption(InterestTag.shopping, 'opt.interest.shopping', '🛍️'),
  LabeledOption(InterestTag.temples, 'opt.interest.temples', '⛩️'),
  LabeledOption(InterestTag.traditional, 'opt.interest.traditional', '🎎'),
  LabeledOption(InterestTag.tech, 'opt.interest.tech', '🖥️'),
  LabeledOption(InterestTag.kids, 'opt.interest.kids', '🧸'),
  LabeledOption(InterestTag.themeParks, 'opt.interest.themeParks', '🎢'),
  LabeledOption(InterestTag.photography, 'opt.interest.photography', '📸'),
  LabeledOption(InterestTag.food, 'opt.interest.food', '🍜'),
];

/// PlanStep.tsx INTEREST_OPTIONS (wizard) — sıra ve emoji birebir.
const List<LabeledOption<InterestTag>> kInterestOptionsWizard = [
  LabeledOption(InterestTag.temples, 'opt.interestW.temples', '⛩️'),
  LabeledOption(InterestTag.traditional, 'opt.interestW.traditional', '🎎'),
  LabeledOption(InterestTag.anime, 'opt.interestW.anime', '🎌'),
  LabeledOption(InterestTag.pokemon, 'opt.interestW.pokemon', '🎮'),
  LabeledOption(InterestTag.tech, 'opt.interestW.tech', '💻'),
  LabeledOption(InterestTag.shopping, 'opt.interestW.shopping', '🛍️'),
  LabeledOption(InterestTag.food, 'opt.interestW.food', '🍣'),
  LabeledOption(InterestTag.themeParks, 'opt.interestW.themeParks', '🎢'),
  LabeledOption(InterestTag.kids, 'opt.interestW.kids', '👶'),
  LabeledOption(InterestTag.photography, 'opt.interestW.photography', '📷'),
];

/// FoodStep.tsx SENSITIVITY_OPTIONS — 9 hassasiyet, emoji birebir.
const List<LabeledOption<FoodSensitivity>> kSensitivityOptions = [
  LabeledOption(FoodSensitivity.noPork, 'opt.sens.noPork', '🚫🐖'),
  LabeledOption(
      FoodSensitivity.noPorkDerivatives, 'opt.sens.noPorkDerivatives', '🚫🥓'),
  LabeledOption(FoodSensitivity.noSeafood, 'opt.sens.noSeafood', '🚫🐟'),
  LabeledOption(FoodSensitivity.halalOnly, 'opt.sens.halal', '🕌'),
  LabeledOption(FoodSensitivity.vegetarian, 'opt.sens.vegetarian', '🥗'),
  LabeledOption(FoodSensitivity.chickenFocus, 'opt.sens.chicken', '🍗'),
  LabeledOption(FoodSensitivity.noFattyMeat, 'opt.sens.noFattyMeat', '🚫🥩'),
  LabeledOption(FoodSensitivity.kidFriendly, 'opt.sens.kidFriendly', '🧒'),
  LabeledOption(FoodSensitivity.turkishPalate, 'opt.sens.turkishPalate', '🇹🇷'),
];

/// PlanStep.tsx WALKING_OPTIONS.
const List<LabeledOption<WalkingTarget>> kWalkingOptions = [
  LabeledOption(
      WalkingTarget.light, 'opt.walk.light', '🚶', 'opt.walk.light.hint'),
  LabeledOption(WalkingTarget.moderate, 'opt.walk.moderate', '🚶‍♂️',
      'opt.walk.moderate.hint'),
  LabeledOption(
      WalkingTarget.intense, 'opt.walk.intense', '🏃', 'opt.walk.intense.hint'),
];

/// PlanStep.tsx TRANSPORT_OPTIONS.
const List<LabeledOption<TransportPreference>> kTransportOptions = [
  LabeledOption(TransportPreference.transit, 'opt.transport.transit', '🚇'),
  LabeledOption(TransportPreference.mixed, 'opt.transport.mixed', '🔀'),
  LabeledOption(TransportPreference.taxiAssisted, 'opt.transport.taxi', '🚕'),
  LabeledOption(TransportPreference.walking, 'opt.transport.walking', '🚶'),
];

/// Ödeme tercihi (types.ts PaymentPreference karşılığı).
const List<LabeledOption<PaymentPreference>> kPaymentOptions = [
  LabeledOption(PaymentPreference.creditCard, 'opt.payment.card', '💳'),
  LabeledOption(PaymentPreference.cash, 'opt.payment.cash', '💴'),
  LabeledOption(PaymentPreference.creditAndCash, 'opt.payment.cardCash', '💳💴'),
  LabeledOption(PaymentPreference.icCard, 'opt.payment.ic', '🎫'),
];

/// PlanStep.tsx PACE_OPTIONS — aktivite yoğunluğu açıklamalarıyla.
const List<LabeledOption<Pace>> kPaceOptions = [
  LabeledOption(Pace.relaxed, 'opt.pace.relaxed', '🌿', 'opt.pace.relaxed.hint'),
  LabeledOption(
      Pace.moderate, 'opt.pace.moderate', '⚖️', 'opt.pace.moderate.hint'),
  LabeledOption(Pace.intense, 'opt.pace.intense', '⚡', 'opt.pace.intense.hint'),
];

/// PlanStep.tsx PACE_LABELS. L10n anahtarı döner — çağrı yeri s(...) ile çözer.
String paceLabel(Pace p) => switch (p) {
      Pace.relaxed => 'opt.pace.relaxed',
      Pace.moderate => 'opt.pace.moderate',
      Pace.intense => 'opt.pace.intense',
    };
