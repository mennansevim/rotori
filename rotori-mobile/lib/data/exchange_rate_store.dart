// JPY→döviz kur deposu. Dört para birimi: TRY, USD, EUR, JPY (referans).
// Tüm kurlar "1 ¥ = X <birim>" biçimindedir.
//
// Kur önceliği:
//   1. KULLANICININ ELLE GİRDİĞİ kur — hiçbir şey ezmez,
//   2. canlı kur (açılışta çekilir, cache'lenir — bkz. live_fx_service.dart),
//   3. sabit varsayılan (yalnızca ilk açılış + ağ yok durumunda).
//
// viewer_theme.dart'taki viewerThemeProvider ile aynı desen: init'te yükler,
// set()'te hem state'i günceller hem de kalıcılaştırır.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/l10n.dart';
import 'live_fx_service.dart';
import 'plans_repository.dart';

/// Varsayılan JPY→TRY kuru — YALNIZCA ilk açılışta ve ağ yokken kullanılır;
/// normalde canlı kur bunun üzerine yazar.
const double kDefaultJpyToTry = 0.25;

/// Kullanıcının kuru elle değiştirdiğini işaretleyen prefs anahtarı eki.
/// Elle girilen kur canlı kurla EZİLMEZ.
const String kManualRateSuffix = ':manual';

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

  /// Kullanıcı bu kuru elle girdi mi? Canlı kur bunu ezmez.
  bool _manual = false;
  bool get isManual => _manual;

  /// Kullanıcı bu oturumda elle bir değer girdi mi? Açılıştaki [_load]
  /// asenkron; kullanıcı o çözülmeden kur girerse geç gelen load hem değeri
  /// hem de "elle girildi" işaretini EZERDİ.
  bool _userTouched = false;

  Future<void> _load() async {
    final prefs = await _ref.read(sharedPrefsProvider.future);
    if (_userTouched) return; // elle giriş kazanır
    _manual = prefs.getBool('$_key$kManualRateSuffix') ?? false;
    final stored = prefs.getDouble(_key);
    if (stored != null && stored > 0) state = stored;
  }

  /// Kullanıcının elle girdiği kur — kalıcı ve canlı kurla EZİLMEZ.
  Future<void> set(double rate) async {
    if (rate <= 0 || !rate.isFinite) return;
    _userTouched = true;
    _manual = true;
    state = rate;
    final prefs = await _prefs();
    await prefs.setDouble(_key, rate);
    await prefs.setBool('$_key$kManualRateSuffix', true);
  }

  /// Canlı kaynaktan gelen kur. Kullanıcı elle bir değer girdiyse UYGULANMAZ.
  Future<void> applyLive(double rate) async {
    if (_manual) return;
    if (rate <= 0 || !rate.isFinite) return;
    state = rate;
    final prefs = await _prefs();
    await prefs.setDouble(_key, rate);
  }

  /// Elle girilen kuru unutup canlı kura geri döner.
  Future<void> clearManual() async {
    _userTouched = true;
    _manual = false;
    final prefs = await _prefs();
    await prefs.setBool('$_key$kManualRateSuffix', false);
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


// ---------------------------------------------------------------------------
// Canlı kur senkronu
// ---------------------------------------------------------------------------

const String _kFxCacheKey = 'viewer:fxCache';

/// Son başarılı canlı kur çekiminin zamanı (cache'ten). UI tazelik göstermek
/// için okuyabilir; kayıt yoksa null.
final fxLastUpdatedProvider = StateProvider<DateTime?>((ref) => null);

/// Canlı kurları uygular: cache tazeyse ağa çıkmaz, değilse çeker.
///
/// Uygulama açılışında bir kez çağrılır. Hata ATMAZ — ağ yoksa cache,
/// cache yoksa varsayılan kurlarla devam edilir.
Future<void> syncLiveFxRates(Ref ref, {bool force = false}) async {
  final prefs = await ref.read(sharedPrefsProvider.future);

  // 1) Cache'i oku ve hemen uygula (ağ beklemeden doğru rakam görünsün).
  LiveFxRates? cached;
  final raw = prefs.getString(_kFxCacheKey);
  if (raw != null) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        cached = LiveFxRates.fromJson(decoded);
      }
    } catch (_) {
      // Bozuk cache — yok say.
    }
  }
  if (cached != null) {
    await _applyRates(ref, cached);
    ref.read(fxLastUpdatedProvider.notifier).state = cached.fetchedAt;
  }

  // 2) Cache tazeyse ağa çıkma.
  final age = cached == null
      ? null
      : DateTime.now().toUtc().difference(cached.fetchedAt.toUtc());
  if (!force && age != null && age < kFxFreshFor) return;

  // 3) Canlı çek — başarısızsa sessizce cache/varsayılanla devam.
  final fresh = await ref.read(liveFxServiceProvider).fetch();
  if (fresh == null) return;

  await _applyRates(ref, fresh);
  ref.read(fxLastUpdatedProvider.notifier).state = fresh.fetchedAt;
  await prefs.setString(_kFxCacheKey, jsonEncode(fresh.toJson()));
}

/// Açılışta BİR kez tetiklenen canlı kur senkronu.
///
/// Kök widget bunu izler ama sonucunu beklemez — ağ yavaşsa uygulama
/// açılışı gecikmez, kurlar geldiğinde ekran kendiliğinden güncellenir.
final liveFxBootstrapProvider =
    FutureProvider<void>((ref) => syncLiveFxRates(ref));

Future<void> _applyRates(Ref ref, LiveFxRates r) async {
  await ref.read(jpyToTryProvider.notifier).applyLive(r.jpyToTry);
  await ref.read(jpyToUsdProvider.notifier).applyLive(r.jpyToUsd);
  await ref.read(jpyToEurProvider.notifier).applyLive(r.jpyToEur);
}
