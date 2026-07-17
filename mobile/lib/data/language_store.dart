// Uygulama dili deposu — seçili dili SharedPreferences'a ('app:lang') kalıcı
// yazan basit StateNotifier. Varsayılan AppLang.tr.
//
// exchange_rate_store.dart ile birebir aynı desen: init'te yükler, set()'te hem
// state'i günceller hem de kalıcılaştırır.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/l10n.dart';
import 'plans_repository.dart';

class AppLangNotifier extends StateNotifier<AppLang> {
  AppLangNotifier(this._ref) : super(AppLang.tr) {
    _load();
  }

  final Ref _ref;
  static const _key = 'app:lang';

  Future<void> _load() async {
    final prefs = await _ref.read(sharedPrefsProvider.future);
    state = AppLangX.fromCode(prefs.getString(_key));
  }

  /// Yeni dili ayarlar ve kalıcılaştırır.
  Future<void> set(AppLang lang) async {
    state = lang;
    final prefs = await _prefs();
    await prefs.setString(_key, lang.code);
  }

  Future<SharedPreferences> _prefs() async {
    final cached = _ref.read(sharedPrefsProvider).valueOrNull;
    if (cached != null) return cached;
    return _ref.read(sharedPrefsProvider.future);
  }
}

/// Seçili uygulama dili (kalıcı). Varsayılan Türkçe.
final appLangProvider = StateNotifierProvider<AppLangNotifier, AppLang>(
  (ref) => AppLangNotifier(ref),
);
