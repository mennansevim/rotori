// Offline yerel cache — SharedPreferences arkasında JSON depolar.
// MVP; Drift'e geçiş Faz 4b'de (ölçek büyürse).

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/types.dart';

/// Yerel plan verisi + eşlik eden meta (versiyon, dirty bayrağı).
class CachedPlan {
  CachedPlan({
    required this.trip,
    required this.version,
    required this.updatedAt,
    this.dirty = false,
  });

  final Trip trip;

  /// Sunucudan gelen `version` sayacı — sync sırasında çakışma tespiti için.
  int version;

  /// Sunucudan gelen `updated_at`. Yereldeki değişiklikler için `DateTime.now()`.
  DateTime updatedAt;

  /// true → yerel değişiklik var, henüz Supabase'e push edilmedi.
  bool dirty;

  Map<String, dynamic> toJson() => {
        'trip': trip.toJson(),
        'version': version,
        'updatedAt': updatedAt.toIso8601String(),
        'dirty': dirty,
      };

  factory CachedPlan.fromJson(Map<String, dynamic> j) => CachedPlan(
        trip: Trip.fromJson((j['trip'] as Map).cast<String, dynamic>()),
        version: (j['version'] as num?)?.toInt() ?? 1,
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        dirty: (j['dirty'] as bool?) ?? false,
      );
}

/// Kullanıcı başına yerel plan cache'i. Anahtar formatı:
///   viewer:plans:<userId>:<planId>  → Trip JSON
///   viewer:plans:<userId>:_index    → List<String> planId
class LocalPlanCache {
  LocalPlanCache(this._prefs, this._userId);
  final SharedPreferences _prefs;
  final String _userId;

  String _key(String planId) => 'viewer:plans:$_userId:$planId';
  String get _indexKey => 'viewer:plans:$_userId:_index';

  List<String> _readIndex() {
    final raw = _prefs.getString(_indexKey);
    if (raw == null) return const [];
    return List<String>.from(jsonDecode(raw) as List);
  }

  Future<void> _writeIndex(List<String> ids) async {
    await _prefs.setString(_indexKey, jsonEncode(ids));
  }

  /// Kullanıcının cache'lediği tüm planlar (özet için).
  List<CachedPlan> listAll() {
    final result = <CachedPlan>[];
    for (final id in _readIndex()) {
      final raw = _prefs.getString(_key(id));
      if (raw == null) continue;
      try {
        result.add(
          CachedPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } on FormatException {
        // Bozuk kayıt — atla, sonraki senkronda düzelir.
      }
    }
    return result;
  }

  CachedPlan? load(String planId) {
    final raw = _prefs.getString(_key(planId));
    if (raw == null) return null;
    return CachedPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(CachedPlan plan) async {
    await _prefs.setString(_key(plan.trip.id), jsonEncode(plan.toJson()));
    final idx = _readIndex();
    if (!idx.contains(plan.trip.id)) {
      await _writeIndex([...idx, plan.trip.id]);
    }
  }

  Future<void> delete(String planId) async {
    await _prefs.remove(_key(planId));
    final idx = _readIndex()..remove(planId);
    await _writeIndex(idx);
  }

  /// Belirli bir plana `dirty` bayrağını set eder — sync tetiklendiğinde
  /// hangi kayıtların Supabase'e push edileceğini bilmek için.
  Future<void> markDirty(String planId, {required bool dirty}) async {
    final cur = load(planId);
    if (cur == null) return;
    cur.dirty = dirty;
    await save(cur);
  }

  List<CachedPlan> dirtyPlans() =>
      listAll().where((p) => p.dirty).toList(growable: false);
}
