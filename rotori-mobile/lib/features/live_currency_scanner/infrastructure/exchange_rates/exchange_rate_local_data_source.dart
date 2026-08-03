import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/exchange_rate.dart';

/// Kurları cihazda (SharedPreferences) cache'ler. Manuel kurlar ayrı anahtarda
/// tutulur; remote güncelleme manueli ezmez.
class ExchangeRateLocalDataSource {
  ExchangeRateLocalDataSource(this._prefs);

  final SharedPreferences _prefs;

  static const _cachePrefix = 'fx:cache:';
  static const _manualPrefix = 'fx:manual:';

  String _key(String prefix, String base, String target) =>
      '$prefix${base}_$target';

  Future<void> cache(ExchangeRate rate) async {
    await _prefs.setString(
      _key(_cachePrefix, rate.baseCurrency, rate.targetCurrency),
      jsonEncode(rate.toJson()),
    );
  }

  ExchangeRate? readCached(String base, String target) =>
      _read(_key(_cachePrefix, base, target));

  Future<void> saveManual(ExchangeRate rate) async {
    await _prefs.setString(
      _key(_manualPrefix, rate.baseCurrency, rate.targetCurrency),
      jsonEncode(rate.copyWith(isManual: true).toJson()),
    );
  }

  ExchangeRate? readManual(String base, String target) =>
      _read(_key(_manualPrefix, base, target));

  Future<void> clearManual(String base, String target) async {
    await _prefs.remove(_key(_manualPrefix, base, target));
  }

  ExchangeRate? _read(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return ExchangeRate.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
