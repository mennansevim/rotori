// apps/viewer/src/utils/visitStore.ts'in Dart portu.
// GPS ziyaret kayıtları — SharedPreferences arkasında JSON depolar.
// Anahtar formatı React ile aynı: viewer:visits:<userId>

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/geofence.dart';

class VisitStore {
  VisitStore(this._prefs, this._userId);

  final SharedPreferences _prefs;
  final String _userId;

  String get _key => 'viewer:visits:$_userId';

  /// Kayıtlı ziyaret durumu; bozuk/eksik kayıt boş state döner.
  VisitState load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const VisitState();
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) return const VisitState();
      return VisitState.fromJson(parsed);
    } on FormatException {
      return const VisitState();
    }
  }

  Future<void> save(VisitState state) async {
    await _prefs.setString(_key, jsonEncode(state.toJson()));
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
  }
}
