// Bütçe hesaplama — plandaki tüm öğe maliyetlerini gün/kategori bazında
// toplar, JPY→TL çevirir, kişi başı böler ve planlanan/gerçekleşen yemek
// bütçesini karşılaştırır. Ağ YOK — kur elle güncellenir (bkz.
// data/exchange_rate_store.dart).
//
// Notlar:
// - Bir maliyetin para birimi `costCurrency`'dir; null ise 'JPY' varsayılır
//   (gezi Japonya'da).
// - `grandTotalJpy` yalnızca JPY cinsinden girilmiş ham maliyetlerin toplamıdır
//   (subtitle'da "≈ ¥X" göstermek için); TL'ye çevrilmiş değil.

import 'dart:math' as math;

import 'types.dart';

/// Verilen tutarı seçili JPY→TRY kuruyla TL'ye çevirir.
///
/// - JPY → `amount * jpyToTry`
/// - TRY / TL → `amount` (zaten TL)
/// - diğer para birimleri → `amount` (görüntülenecek değer varsayılır; basit tut)
double toTry(int amount, String currency, double jpyToTry) {
  final c = currency.trim().toUpperCase();
  return switch (c) {
    'JPY' || '¥' || 'YEN' => amount * jpyToTry,
    'TRY' || 'TL' || '₺' => amount.toDouble(),
    _ => amount.toDouble(),
  };
}

/// Bir maliyetin normalize edilmiş para birimi (null → 'JPY').
String _currencyOf(TimelineItem item) {
  final raw = item.costCurrency;
  if (raw == null || raw.trim().isEmpty) return 'JPY';
  return raw.trim().toUpperCase();
}

bool _isJpy(String currency) =>
    currency == 'JPY' || currency == '¥' || currency == 'YEN';

bool _isTry(String currency) =>
  currency == 'TRY' || currency == 'TL' || currency == '₺';

/// Bütçe özeti — tüm alanlar TL cinsinden (aksi belirtilmedikçe).
class BudgetSummary {
  const BudgetSummary({
    required this.grandTotalTry,
    required this.grandTotalJpy,
    required this.byCategoryTry,
    required this.byDay,
    required this.perPersonTry,
    required this.plannedMealTry,
    required this.actualMealTry,
    required this.itemsWithCost,
    required this.itemsTotal,
    required this.fixedEssentialTry,
    required this.discretionaryTry,
    required this.dailyBurnTry,
    required this.coverageRatio,
    required this.contingencyTry,
    required this.frugalScenarioTry,
    required this.realisticScenarioTry,
    required this.comfortScenarioTry,
    required this.suggestedCashTry,
    required this.nonStandardCurrencyItems,
  });

  /// Tüm maliyetlerin TL'ye çevrilmiş toplamı.
  final double grandTotalTry;

  /// Yalnızca JPY cinsinden girilmiş ham maliyetlerin toplamı (¥).
  final int grandTotalJpy;

  /// Kategoriye (TimelineItemKind) göre TL toplamları.
  final Map<TimelineItemKind, double> byCategoryTry;

  /// Güne göre TL toplamları (plan sırasıyla).
  final List<({int dayNumber, String date, double totalTry})> byDay;

  /// Kişi başı TL (grandTotalTry / party).
  final double perPersonTry;

  /// Planlanan yemek bütçesi TL: kişi başı × kişi × gün sayısı.
  final double plannedMealTry;

  /// Gerçekleşen yemek TL: plandaki yemek öğelerinin maliyet toplamı.
  final double actualMealTry;

  /// Maliyeti girilmiş öğe sayısı.
  final int itemsWithCost;

  /// Plandaki toplam öğe sayısı.
  final int itemsTotal;

  /// Ulaşım + konaklama gibi sabit/temel harcama kısmı (TL).
  final double fixedEssentialTry;

  /// Aktivite + yemek gibi esnek/discretionary harcama kısmı (TL).
  final double discretionaryTry;

  /// Günlük ortalama yakım hızı (TL/gün).
  final double dailyBurnTry;

  /// Maliyet girilen öğe kapsama oranı: 0..1.
  final double coverageRatio;

  /// Güvenlik payı (varsayılan %12).
  final double contingencyTry;

  /// Senaryo tahmini (TL): temkinli.
  final double frugalScenarioTry;

  /// Senaryo tahmini (TL): gerçekçi.
  final double realisticScenarioTry;

  /// Senaryo tahmini (TL): konforlu.
  final double comfortScenarioTry;

  /// Nakit ağırlıklı noktalar için önerilen alt seviye nakit (TL).
  final double suggestedCashTry;

  /// JPY/TRY dışındaki para birimi girdisi sayısı.
  final int nonStandardCurrencyItems;
}

/// Trip'in tüm gün/öğe maliyetlerini toplayıp [BudgetSummary] üretir.
BudgetSummary computeBudget(Trip trip, {required double jpyToTry}) {
  var grandTotalTry = 0.0;
  var grandTotalJpy = 0;
  var actualMealTry = 0.0;
  var itemsWithCost = 0;
  var itemsTotal = 0;
  var nonStandardCurrencyItems = 0;

  final byCategory = <TimelineItemKind, double>{};
  final byDay = <({int dayNumber, String date, double totalTry})>[];

  for (final day in trip.days) {
    var dayTotalTry = 0.0;
    for (final item in day.items) {
      itemsTotal++;
      final cost = item.cost;
      if (cost == null) continue;

      final currency = _currencyOf(item);
      final tryValue = toTry(cost, currency, jpyToTry);

      grandTotalTry += tryValue;
      dayTotalTry += tryValue;
      if (_isJpy(currency)) grandTotalJpy += cost;
      if (!_isJpy(currency) && !_isTry(currency)) {
        nonStandardCurrencyItems++;
      }
      itemsWithCost++;

      final kind = item.kind ?? TimelineItemKind.activity;
      byCategory[kind] = (byCategory[kind] ?? 0) + tryValue;

      if (kind == TimelineItemKind.meal) actualMealTry += tryValue;
    }
    byDay.add((
      dayNumber: day.dayNumber,
      date: day.date,
      totalTry: dayTotalTry,
    ));
  }

  final party = math.max(1, trip.preferences.partySize ?? 1);
  final perPersonTry = grandTotalTry / party;
  final fixedEssentialTry =
      (byCategory[TimelineItemKind.transport] ?? 0) +
          (byCategory[TimelineItemKind.hotel] ?? 0);
  final discretionaryTry = math.max(0.0, grandTotalTry - fixedEssentialTry);
  final dailyBurnTry = trip.days.isEmpty ? 0.0 : grandTotalTry / trip.days.length;
  final coverageRatio = itemsTotal == 0 ? 0.0 : itemsWithCost / itemsTotal;
  final contingencyTry = grandTotalTry * 0.12;
  final frugalScenarioTry = grandTotalTry * 0.9;
  final realisticScenarioTry = grandTotalTry * 1.1;
  final comfortScenarioTry = grandTotalTry * 1.3;
  final suggestedCashTry = (grandTotalTry * 0.35) + (actualMealTry * 0.15);

  final mealPerPerson = trip.preferences.mealBudgetPerPerson ?? 0;
  final plannedMealTry = mealPerPerson == 0
      ? 0.0
      : toTry(
            mealPerPerson,
            trip.preferences.mealBudgetCurrency ?? 'JPY',
            jpyToTry,
          ) *
          party *
          trip.days.length;

  return BudgetSummary(
    grandTotalTry: grandTotalTry,
    grandTotalJpy: grandTotalJpy,
    byCategoryTry: byCategory,
    byDay: byDay,
    perPersonTry: perPersonTry,
    plannedMealTry: plannedMealTry,
    actualMealTry: actualMealTry,
    itemsWithCost: itemsWithCost,
    itemsTotal: itemsTotal,
    fixedEssentialTry: fixedEssentialTry,
    discretionaryTry: discretionaryTry,
    dailyBurnTry: dailyBurnTry,
    coverageRatio: coverageRatio,
    contingencyTry: contingencyTry,
    frugalScenarioTry: frugalScenarioTry,
    realisticScenarioTry: realisticScenarioTry,
    comfortScenarioTry: comfortScenarioTry,
    suggestedCashTry: suggestedCashTry,
    nonStandardCurrencyItems: nonStandardCurrencyItems,
  );
}
