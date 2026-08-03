// PreDepartureChecklistRepository — plan başına hazırlık listesi durumu için
// offline-first depo.
//
// Sözleşme:
//   - `load(tripId)`  → yerel cache'ten okur, hemen döner. Sunucu (Supabase)
//                       varsa arka planda tazeler ve cache'i günceller.
//   - `save(state)`   → yerel cache'e yazar, sunucu varsa upsert'i dener
//                       (ağ yoksa sessizce döner; bir sonraki save'de tekrar).
//
// Backend YOK durumunda (`preview_main.dart` / testler): repository yalnızca
// SharedPreferences (veya opsiyonel InMemoryStorage) üzerinden çalışır.
//
// State model:
//   PreDepartureChecklist — yerel: `viewer:prep:<tripId>` anahtarında JSON.
//   Sunucuya storableItems() (checked + custom) yazılır; preset+unchecked
//   maddeler storage'a girmez, template ile birleştirilerek okunur.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';
import '../domain/pre_departure_checklist.dart';
import 'plans_repository.dart';

// ---------------------------------------------------------------------------
// Storage soyutlaması — SharedPreferences (üretim) veya bellek (testler).
// ---------------------------------------------------------------------------

abstract class PrepChecklistStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class SharedPrefsStorage implements PrepChecklistStorage {
  SharedPrefsStorage(this._prefs);
  final SharedPreferences _prefs;

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) async {
    await _prefs.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _prefs.remove(key);
  }
}

/// Sunucusuz ortam (preview + testler) için basit RAM depo.
class InMemoryStorage implements PrepChecklistStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _data.remove(key);
  }
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

class PreDepartureChecklistRepository {
  PreDepartureChecklistRepository({
    required PrepChecklistStorage storage,
    SupabaseClient? client,
  })  : _storage = storage,
        _client = client;

  final PrepChecklistStorage _storage;
  final SupabaseClient? _client;

  String _key(String tripId) => 'viewer:prep:$tripId';

  /// Bir plan için hazırlık listesini yükler. Yerelden hemen döner; sunucu
  /// erişilebilirse arka planda tazeleme yapılır. Sunucudaki `updated_at`
  /// yerelden yeni ise state güncellenmiş dönebilir.
  Future<PreDepartureChecklist> load(String tripId) async {
    // 1) Yerel.
    final local = await _readLocal(tripId);
    // 2) Sunucu tazeleme (best-effort).
    final remote = await _readRemote(tripId);
    if (remote != null) {
      // Sunucu > yerel ise yereli tazele.
      final localUpdated = local?.updatedAt;
      final remoteUpdated = remote.updatedAt;
      if (localUpdated == null ||
          (remoteUpdated != null && remoteUpdated.isAfter(localUpdated))) {
        await _writeLocal(remote);
        return remote;
      }
    }
    return local ??
        PreDepartureChecklist.merged(
          tripId: tripId,
          presetTemplates: kPreDeparturePresets,
          stored: const [],
        );
  }

  /// State'i kaydeder: önce yerel, ardından sunucu (varsa). Hata sessiz.
  Future<void> save(PreDepartureChecklist state) async {
    final now = DateTime.now();
    final withTs = state.copyWith(updatedAt: now);
    await _writeLocal(withTs);
    await _writeRemote(withTs);
  }

  Future<void> delete(String tripId) async {
    await _storage.remove(_key(tripId));
    final client = _client;
    if (client == null) return;
    try {
      await client
          .from('pre_departure_checklists')
          .delete()
          .eq('trip_id', tripId);
    } on Exception {
      // Ağ yok — sessizce geç.
    }
  }

  // --- Yerel ---------------------------------------------------------------

  Future<PreDepartureChecklist?> _readLocal(String tripId) async {
    try {
      final raw = await _storage.read(_key(tripId));
      if (raw == null || raw.isEmpty) return null;
      final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return _deserialize(tripId, map);
    } catch (e) {
      debugPrint('PreDepartureChecklistRepository._readLocal: $e');
      return null;
    }
  }

  Future<void> _writeLocal(PreDepartureChecklist state) async {
    try {
      final payload = _serialize(state);
      await _storage.write(_key(state.tripId), jsonEncode(payload));
    } catch (e) {
      debugPrint('PreDepartureChecklistRepository._writeLocal: $e');
    }
  }

  // --- Sunucu --------------------------------------------------------------

  Future<PreDepartureChecklist?> _readRemote(String tripId) async {
    final client = _client;
    if (client == null) return null;
    try {
      final row = await client
          .from('pre_departure_checklists')
          .select()
          .eq('trip_id', tripId)
          .maybeSingle();
      if (row == null) return null;
      return _deserialize(tripId, row.cast<String, dynamic>());
    } on Exception {
      return null;
    }
  }

  Future<void> _writeRemote(PreDepartureChecklist state) async {
    final client = _client;
    if (client == null) return;
    try {
      final items =
          state.storableItems().map((i) => i.toJson()).toList(growable: false);
      await client.from('pre_departure_checklists').upsert(
        {
          'trip_id': state.tripId,
          'items': items,
          'days_before': state.daysBefore,
        },
        onConflict: 'trip_id',
      );
    } on Exception {
      // Ağ yok / RLS başarısız — yerel yeterli.
    }
  }

  // --- Serialize/deserialize ----------------------------------------------

  Map<String, dynamic> _serialize(PreDepartureChecklist state) => {
        'items': state.storableItems().map((i) => i.toJson()).toList(),
        'days_before': state.daysBefore,
        'updated_at':
            (state.updatedAt ?? DateTime.now()).toIso8601String(),
      };

  PreDepartureChecklist _deserialize(
    String tripId,
    Map<String, dynamic> map,
  ) {
    final rawItems = (map['items'] as List? ?? const []).cast<dynamic>();
    final stored = rawItems
        .map((e) => PrepItem.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final daysBefore =
        (map['days_before'] as num?)?.toInt() ?? 7;
    final updatedAt = DateTime.tryParse(map['updated_at'] as String? ?? '');
    return PreDepartureChecklist.merged(
      tripId: tripId,
      presetTemplates: kPreDeparturePresets,
      stored: stored,
      daysBefore: daysBefore,
      updatedAt: updatedAt,
    );
  }
}

// ---------------------------------------------------------------------------
// Riverpod bağlantıları
// ---------------------------------------------------------------------------

/// Repository provider'ı. Login yoksa `SupabaseClient` null → yalnızca yerel
/// (SharedPreferences) çalışır. Testlerde `overrideWithValue` ile
/// [InMemoryStorage]'li bir repository verilebilir.
final preDepartureChecklistRepositoryProvider =
    Provider<PreDepartureChecklistRepository?>((ref) {
  final prefs = ref.watch(sharedPrefsProvider).valueOrNull;
  if (prefs == null) return null;
  final user = ref.watch(currentUserProvider);
  final client = user == null ? null : ref.watch(supabaseProvider);
  return PreDepartureChecklistRepository(
    storage: SharedPrefsStorage(prefs),
    client: client,
  );
});

/// Plan bazlı hazırlık listesi state notifier'ı.
class PreDepartureChecklistNotifier
    extends StateNotifier<PreDepartureChecklist> {
  PreDepartureChecklistNotifier(this._repo, this.tripId)
      : super(PreDepartureChecklist.merged(
          tripId: tripId,
          presetTemplates: kPreDeparturePresets,
          stored: const [],
        )) {
    _load();
  }

  final PreDepartureChecklistRepository? _repo;
  final String tripId;

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) return;
    try {
      final loaded = await repo.load(tripId);
      if (mounted) state = loaded;
    } catch (e) {
      debugPrint('PreDepartureChecklistNotifier._load: $e');
    }
  }

  Future<void> toggle(String id) async {
    final next = state.toggle(id);
    if (identical(next, state)) return;
    state = next;
    await _repo?.save(next);
  }

  Future<void> addCustom(String label, {String emoji = '📌'}) async {
    if (label.trim().isEmpty) return;
    final item = PrepItem.customFromLabel(label, emoji: emoji);
    final next = state.addCustom(item);
    if (identical(next, state)) return;
    state = next;
    await _repo?.save(next);
  }

  Future<void> removeCustom(String id) async {
    final next = state.removeCustom(id);
    if (identical(next, state)) return;
    state = next;
    await _repo?.save(next);
  }

  Future<void> setDaysBefore(int n) async {
    final clamped = n.clamp(1, 30);
    if (clamped == state.daysBefore) return;
    state = state.withDaysBefore(clamped);
    await _repo?.save(state);
  }

  /// Test yardımcısı — repo'dan taze durumu tekrar yükler.
  Future<void> refresh() => _load();
}

/// Plan bazlı hazırlık listesi provider'ı. Preview / offline modda repo null
/// olsa bile in-memory bir state döner.
final preDepartureChecklistProvider = StateNotifierProvider.family<
    PreDepartureChecklistNotifier, PreDepartureChecklist, String>(
  (ref, tripId) => PreDepartureChecklistNotifier(
    ref.watch(preDepartureChecklistRepositoryProvider),
    tripId,
  ),
);
