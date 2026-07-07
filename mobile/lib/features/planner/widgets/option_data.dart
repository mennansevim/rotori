// Planner adımlarında paylaşılan seçenek listeleri.
// Kaynaklar: ExploreStep.tsx INTEREST_OPTIONS, FoodStep.tsx SENSITIVITY_OPTIONS,
// PlanStep.tsx INTEREST/WALKING/TRANSPORT/PACE_OPTIONS.

import '../../../domain/types.dart';

class LabeledOption<T> {
  const LabeledOption(this.value, this.label, this.emoji, [this.hint]);
  final T value;
  final String label;
  final String emoji;
  final String? hint;
}

/// ExploreStep.tsx INTEREST_OPTIONS — sıra ve emoji birebir.
const List<LabeledOption<InterestTag>> kInterestOptionsExplore = [
  LabeledOption(InterestTag.anime, 'Anime / Manga', '🎴'),
  LabeledOption(InterestTag.pokemon, 'Pokémon', '⚡'),
  LabeledOption(InterestTag.shopping, 'Alışveriş', '🛍️'),
  LabeledOption(InterestTag.temples, 'Tapınaklar', '⛩️'),
  LabeledOption(InterestTag.traditional, 'Geleneksel Japonya', '🎎'),
  LabeledOption(InterestTag.tech, 'Teknoloji mağazaları', '🖥️'),
  LabeledOption(InterestTag.kids, 'Çocuk aktiviteleri', '🧸'),
  LabeledOption(InterestTag.themeParks, 'Tema parkları', '🎢'),
  LabeledOption(InterestTag.photography, 'Fotoğraf noktaları', '📸'),
  LabeledOption(InterestTag.food, 'Yemek keşfi', '🍜'),
];

/// PlanStep.tsx INTEREST_OPTIONS (wizard) — sıra ve emoji birebir.
const List<LabeledOption<InterestTag>> kInterestOptionsWizard = [
  LabeledOption(InterestTag.temples, 'Tapınaklar', '⛩️'),
  LabeledOption(InterestTag.traditional, 'Geleneksel', '🎎'),
  LabeledOption(InterestTag.anime, 'Anime & manga', '🎌'),
  LabeledOption(InterestTag.pokemon, 'Pokemon & oyun', '🎮'),
  LabeledOption(InterestTag.tech, 'Teknoloji', '💻'),
  LabeledOption(InterestTag.shopping, 'Alışveriş', '🛍️'),
  LabeledOption(InterestTag.food, 'Yemek odaklı', '🍣'),
  LabeledOption(InterestTag.themeParks, 'Tema parklar', '🎢'),
  LabeledOption(InterestTag.kids, 'Çocuk dostu', '👶'),
  LabeledOption(InterestTag.photography, 'Fotoğrafçılık', '📷'),
];

/// FoodStep.tsx SENSITIVITY_OPTIONS — 9 hassasiyet, emoji birebir.
const List<LabeledOption<FoodSensitivity>> kSensitivityOptions = [
  LabeledOption(FoodSensitivity.noPork, 'Domuz eti istemiyorum', '🚫🐖'),
  LabeledOption(
      FoodSensitivity.noPorkDerivatives, 'Domuz yağı / jelatin yok', '🚫🥓'),
  LabeledOption(FoodSensitivity.noSeafood, 'Deniz ürünü istemiyorum', '🚫🐟'),
  LabeledOption(FoodSensitivity.halalOnly, 'Helal seçenek istiyorum', '🕌'),
  LabeledOption(FoodSensitivity.vegetarian, 'Vejetaryen', '🥗'),
  LabeledOption(FoodSensitivity.chickenFocus, 'Tavuk ağırlıklı', '🍗'),
  LabeledOption(FoodSensitivity.noFattyMeat, 'Yağlı et sevmiyorum', '🚫🥩'),
  LabeledOption(FoodSensitivity.kidFriendly, 'Çocuk dostu restoran', '🧒'),
  LabeledOption(FoodSensitivity.turkishPalate, 'Türk damak tadına yakın', '🇹🇷'),
];

/// PlanStep.tsx WALKING_OPTIONS.
const List<LabeledOption<WalkingTarget>> kWalkingOptions = [
  LabeledOption(WalkingTarget.light, 'Az', '🚶', '~7k adım/gün'),
  LabeledOption(WalkingTarget.moderate, 'Orta', '🚶‍♂️', '~11k adım/gün'),
  LabeledOption(WalkingTarget.intense, 'Yoğun', '🏃', '~15k+ adım/gün'),
];

/// PlanStep.tsx TRANSPORT_OPTIONS.
const List<LabeledOption<TransportPreference>> kTransportOptions = [
  LabeledOption(TransportPreference.transit, 'Toplu taşıma', '🚇'),
  LabeledOption(TransportPreference.mixed, 'Karışık', '🔀'),
  LabeledOption(TransportPreference.taxiAssisted, 'Taksi destekli', '🚕'),
  LabeledOption(TransportPreference.walking, 'Yürüyüş ağırlıklı', '🚶'),
];

/// Ödeme tercihi (types.ts PaymentPreference karşılığı).
const List<LabeledOption<PaymentPreference>> kPaymentOptions = [
  LabeledOption(PaymentPreference.creditCard, 'Kredi kartı', '💳'),
  LabeledOption(PaymentPreference.cash, 'Nakit', '💴'),
  LabeledOption(PaymentPreference.creditAndCash, 'Kart + nakit', '💳💴'),
  LabeledOption(PaymentPreference.icCard, 'IC kart (Suica/Pasmo)', '🎫'),
];

/// PlanStep.tsx PACE_OPTIONS — aktivite yoğunluğu açıklamalarıyla.
const List<LabeledOption<Pace>> kPaceOptions = [
  LabeledOption(Pace.relaxed, 'Rahat', '🌿', 'Az durak, uzun molalar'),
  LabeledOption(Pace.moderate, 'Dengeli', '⚖️', 'Standart tempo'),
  LabeledOption(Pace.intense, 'Yoğun', '⚡', 'Çok yer, sıkı program'),
];

/// PlanStep.tsx PACE_LABELS.
String paceLabel(Pace p) => switch (p) {
      Pace.relaxed => 'Rahat',
      Pace.moderate => 'Dengeli',
      Pace.intense => 'Yoğun',
    };
