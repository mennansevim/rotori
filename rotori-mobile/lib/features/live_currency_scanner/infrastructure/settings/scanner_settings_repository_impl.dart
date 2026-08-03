import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/repositories/scanner_settings_repository.dart';
import '../../domain/scanner_settings.dart';

/// Tarayıcı ayarlarını SharedPreferences'ta JSON olarak saklar.
class ScannerSettingsRepositoryImpl implements ScannerSettingsRepository {
  ScannerSettingsRepositoryImpl(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'scanner:settings';

  @override
  Future<ScannerSettings> load() async {
    final raw = _prefs.getString(_key);
    if (raw == null) return const ScannerSettings();
    try {
      return ScannerSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ScannerSettings();
    }
  }

  @override
  Future<void> save(ScannerSettings settings) async {
    await _prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}
