// JPY→döviz kur deposu — elle güncellenen kurları SharedPreferences'a kalıcı
// yazan basit StateNotifier'lar. Ağ YOK / canlı FX API YOK; kurlar çevrimdışı,
// kullanıcı tarafından güncellenir. Dört para birimi desteklenir: TRY, USD,
// EUR, JPY (referans). Tüm kurlar "1 ¥ = X <birim>" biçimindedir.
//
// viewer_theme.dart'taki viewerThemeProvider ile aynı desen: init'te yükler,
// set()'te hem state'i günceller hem de kalıcılaştırır.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/l10n.dart';
import 'plans_repository.dart';

/// Varsayılan JPY→TRY kuru (1 ¥ = 0.25 ₺). Kullanıcı elle değiştirebilir.
const double kDefaultJpyToTry = 0.25;

/// Varsayılan JPY→USD kuru (≈ 150 ¥/$). Kullanıcı elle değiştirebilir.
const double kDefaultJpyToUsd = 0.0067;

/// Varsayılan JPY→EUR kuru (≈ 160 ¥/€). Kullanıcı elle değiştirebilir.
const double kDefaultJpyToEur = 0.0062;

/// Bütçe ekranında gösterilecek para birimleri.
enum DisplayCurrency { tryLira, usd, eur, jpy }

extension DisplayCurrencyX on DisplayCurrency {
  /// Para birimi sembolü.
  String get symbol => switch (this) {
        DisplayCurrency.tryLira => '₺',
        DisplayCurrency.usd => '\$',
        DisplayCurrency.eur => '€',
        DisplayCurrency.jpy => '¥',
      };

  /// ISO benzeri kısa kod.
  String get code => switch (this) {
        DisplayCurrency.tryLira => 'TRY',
        DisplayCurrency.usd => 'USD',
        DisplayCurrency.eur => 'EUR',
        DisplayCurrency.jpy => 'JPY',
      };

  static DisplayCurrency fromCode(String? raw) => switch (raw) {
        'USD' => DisplayCurrency.usd,
        'EUR' => DisplayCurrency.eur,
        'JPY' => DisplayCurrency.jpy,
        _ => DisplayCurrency.tryLira,
      };

  /// Dile göre varsayılan görüntüleme birimi: TR → ₺, EN → $.
  static DisplayCurrency defaultFor(AppLang lang) =>
      lang == AppLang.en ? DisplayCurrency.usd : DisplayCurrency.tryLira;
}

/// Tek bir JPY→döviz kuru için ortak, kalıcı StateNotifier.
class _JpyRateNotifier extends StateNotifier<double> {
  _JpyRateNotifier(this._ref, this._key, double fallback) : super(fallback) {
    _load();
  }

  final Ref _ref;
  final String _key;

  Future<void> _load() async {
    final prefs = await _ref.read(sharedPrefsProvider.future);
    final stored = prefs.getDouble(_key);
    if (stored != null && stored > 0) state = stored;
  }

  /// Yeni kuru ayarlar (pozitif olmalı) ve kalıcılaştırır.
  Future<void> set(double rate) async {
    if (rate <= 0 || !rate.isFinite) return;
    state = rate;
    final prefs = await _prefs();
    await prefs.setDouble(_key, rate);
  }

  Future<SharedPreferences> _prefs() async {
    final cached = _ref.read(sharedPrefsProvider).valueOrNull;
    if (cached != null) return cached;
    return _ref.read(sharedPrefsProvider.future);
  }
}

// Geriye uyumlu tip adı (budget.dart / testler bunu bekleyebilir).
typedef JpyToTryNotifier = _JpyRateNotifier;

/// Seçili JPY→TRY kuru (kalıcı, elle güncellenir).
final jpyToTryProvider = StateNotifierProvider<_JpyRateNotifier, double>(
  (ref) => _JpyRateNotifier(ref, 'viewer:jpyTry', kDefaultJpyToTry),
);

/// Seçili JPY→USD kuru (kalıcı, elle güncellenir).
final jpyToUsdProvider = StateNotifierProvider<_JpyRateNotifier, double>(
  (ref) => _JpyRateNotifier(ref, 'viewer:jpyUsd', kDefaultJpyToUsd),
);

/// Seçili JPY→EUR kuru (kalıcı, elle güncellenir).
final jpyToEurProvider = StateNotifierProvider<_JpyRateNotifier, double>(
  (ref) => _JpyRateNotifier(ref, 'viewer:jpyEur', kDefaultJpyToEur),
);

/// Verilen görüntüleme birimi için "1 ¥ = X <birim>" kurunu döndürür.
/// JPY referans olduğundan 1.0'dır. Diğerleri kalıcı provider'lardan okunur.
double jpyRateFor(WidgetRef ref, DisplayCurrency currency) => switch (currency) {
      DisplayCurrency.tryLira => ref.watch(jpyToTryProvider),
      DisplayCurrency.usd => ref.watch(jpyToUsdProvider),
      DisplayCurrency.eur => ref.watch(jpyToEurProvider),
      DisplayCurrency.jpy => 1.0,
    };

/// Görüntüleme birimini elle değiştiren notifier. `null` = kullanıcı henüz
/// seçmedi → ekran dile göre varsayılanı kullanır.
class DisplayCurrencyNotifier extends StateNotifier<DisplayCurrency?> {
  DisplayCurrencyNotifier(this._ref) : super(null) {
    _load();
  }

  final Ref _ref;
  static const _key = 'viewer:displayCurrency';

  Future<void> _load() async {
    final prefs = await _ref.read(sharedPrefsProvider.future);
    final stored = prefs.getString(_key);
    if (stored != null && stored.isNotEmpty) {
      state = DisplayCurrencyX.fromCode(stored);
    }
  }

  Future<void> set(DisplayCurrency currency) async {
    state = currency;
    final prefs = _ref.read(sharedPrefsProvider).valueOrNull ??
        await _ref.read(sharedPrefsProvider.future);
    if (prefs == null) return;
    await prefs.setString(_key, currency.code);
  }
}

/// Kullanıcının seçtiği görüntüleme birimi (null → dile göre varsayılan).
final displayCurrencyProvider =
    StateNotifierProvider<DisplayCurrencyNotifier, DisplayCurrency?>(
  (ref) => DisplayCurrencyNotifier(ref),
);

/// Kullanıcının elle girdiği gerçek maliyet üstünüşleri (JPY cinsinden), kalem
/// anahtarına göre. Girilirse tahmin yerine bu değer kullanılır (isteğe bağlı).
class CostOverrideNotifier extends StateNotifier<Map<String, int>> {
  CostOverrideNotifier(this._ref) : super(const {}) {
    _load();
  }

  final Ref _ref;
  static const _key = 'viewer:costOverridesJpy';

  Future<void> _load() async {
    final prefs = await _ref.read(sharedPrefsProvider.future);
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        state = {
          for (final entry in decoded.entries)
            if (entry.value is num && (entry.value as num) >= 0)
              entry.key.toString(): (entry.value as num).round(),
        };
      }
    } catch (_) {
      // Bozuk kayıt yok sayılır; boş üstünüş tablosuyla devam.
    }
  }

  /// Bir kalem için gerçek JPY tutarı ayarlar (>=0). Kalıcılaştırır.
  Future<void> set(String category, int jpy) async {
    if (jpy < 0) return;
    state = {...state, category: jpy};
    await _persist();
  }

  /// Bir kalemin üstünüşünü kaldırır → tekrar tahmine döner.
  Future<void> clear(String category) async {
    if (!state.containsKey(category)) return;
    final next = {...state}..remove(category);
    state = next;
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = _ref.read(sharedPrefsProvider).valueOrNull ??
        await _ref.read(sharedPrefsProvider.future);
    if (prefs == null) return;
    await prefs.setString(_key, jsonEncode(state));
  }
}

/// Kalem bazlı gerçek maliyet üstünüşleri (JPY).
final costOverrideProvider =
    StateNotifierProvider<CostOverrideNotifier, Map<String, int>>(
  (ref) => CostOverrideNotifier(ref),
);
