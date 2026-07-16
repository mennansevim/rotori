// JPY→TRY kur deposu — elle güncellenen kuru SharedPreferences'a ('viewer:jpyTry')
// kalıcı yazan basit StateNotifier. Ağ YOK / canlı FX API YOK; kur çevrimdışı,
// kullanıcı tarafından güncellenir.
//
// viewer_theme.dart'taki viewerThemeProvider ile aynı desen: init'te yükler,
// set()'te hem state'i günceller hem de kalıcılaştırır.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plans_repository.dart';

/// Varsayılan JPY→TRY kuru (1 ¥ = 0.25 ₺). Kullanıcı elle değiştirebilir.
const double kDefaultJpyToTry = 0.25;

class JpyToTryNotifier extends StateNotifier<double> {
  JpyToTryNotifier(this._ref) : super(kDefaultJpyToTry) {
    _load();
  }

  final Ref _ref;
  static const _key = 'viewer:jpyTry';

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

/// Seçili JPY→TRY kuru (kalıcı, elle güncellenir).
final jpyToTryProvider = StateNotifierProvider<JpyToTryNotifier, double>(
  (ref) => JpyToTryNotifier(ref),
);
