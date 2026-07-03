// PlansRepository — Faz 4'ün kalbi.
//
// Sözleşme:
//   watch(planId)  → yerelden anında yay + Supabase realtime aboneliği; sunucudan
//                    bir güncelleme gelirse yerel cache + stream güncellenir.
//   save(trip)     → önce yerel (optimistik, dirty=true), sonra Supabase upsert;
//                    başarılıysa dirty=false + version güncellenir. Ağ yoksa
//                    dirty kalır, bir sonraki connectivity_plus tetiğinde push.
//   list()         → yerel liste (offline-first).
//   syncDirty()    → dirty tüm kayıtları Supabase'e push eder.
//
// Çakışma: last-write-wins. Sunucudan gelen `version` yereldekiden büyükse
//   yerel kayıt üzerine yazılır ve stream'e emit edilir. `onConflict` callback
//   ile UI kullanıcıya "başka cihazdan güncellendi" toast'ı gösterebilir.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';
import '../domain/types.dart';
import 'local_plan_cache.dart';

// ---------------------------------------------------------------------------
// Provider'lar
// ---------------------------------------------------------------------------

/// Uygulama boyunca tek SharedPreferences instance'ı.
final sharedPrefsProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

/// Login'li kullanıcı için LocalPlanCache.
final localPlanCacheProvider = Provider<LocalPlanCache?>((ref) {
  final prefs = ref.watch(sharedPrefsProvider).valueOrNull;
  final user = ref.watch(currentUserProvider);
  if (prefs == null || user == null) return null;
  return LocalPlanCache(prefs, user.id);
});

/// Repository — tüm plan işlemlerinin tek girişi.
final plansRepositoryProvider = Provider<PlansRepository?>((ref) {
  final client = ref.watch(supabaseProvider);
  final cache = ref.watch(localPlanCacheProvider);
  final userId = ref.watch(currentUserProvider)?.id;
  if (cache == null || userId == null) return null;
  return PlansRepository(client: client, cache: cache, userId: userId);
});

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

class PlanConflict {
  PlanConflict({required this.planId, required this.serverVersion});
  final String planId;
  final int serverVersion;
}

class PlansRepository {
  PlansRepository({
    required SupabaseClient client,
    required LocalPlanCache cache,
    required String userId,
  })  : _client = client,
        _cache = cache,
        _userId = userId;

  final SupabaseClient _client;
  final LocalPlanCache _cache;
  final String _userId;

  /// Uzak `plans` satırını dinler + yerel değişiklikleri birleştirir.
  Stream<Trip> watch(String planId) {
    late StreamController<Trip> controller;
    RealtimeChannel? channel;

    Future<void> emitFromCache() async {
      final local = _cache.load(planId);
      if (local != null) controller.add(local.trip);
    }

    Future<void> handleServerRow(Map<String, dynamic> row) async {
      final serverVersion = (row['version'] as num?)?.toInt() ?? 1;
      final serverUpdated =
          DateTime.tryParse(row['updated_at'] as String? ?? '') ??
              DateTime.now();
      final doc = row['doc'];
      if (doc == null) return;
      final docMap = doc is String
          ? (jsonDecode(doc) as Map).cast<String, dynamic>()
          : (doc as Map).cast<String, dynamic>();
      final trip = Trip.fromJson(docMap);
      final cur = _cache.load(planId);
      // last-write-wins: sunucu > yerel ise yereli ez.
      if (cur == null || serverVersion >= cur.version) {
        await _cache.save(
          CachedPlan(
            trip: trip,
            version: serverVersion,
            updatedAt: serverUpdated,
            dirty: false,
          ),
        );
        controller.add(trip);
      }
    }

    controller = StreamController<Trip>.broadcast(
      onListen: () async {
        // 1) Cache'ten hemen yay (offline-first).
        await emitFromCache();

        // 2) Sunucudan tazele.
        try {
          final row = await _client
              .from('plans')
              .select()
              .eq('id', planId)
              .maybeSingle();
          if (row != null) await handleServerRow(row);
        } on Exception {
          // Ağ yok — cache yeterli.
        }

        // 3) Realtime aboneliği (kendi cihazlar arası canlı senkron; Faz 6a'da genişler).
        channel = _client
            .channel('plan:$planId')
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'plans',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'id',
                value: planId,
              ),
              callback: (payload) => handleServerRow(payload.newRecord),
            )
            .subscribe();
      },
      onCancel: () async {
        if (channel != null) await _client.removeChannel(channel!);
      },
    );

    return controller.stream;
  }

  /// Kullanıcının planlarının özet listesi (yerel + uzak birleştirmez; yerel
  /// önce, sync sonrası uzak günceller. MVP: sadece yerel liste.).
  List<Trip> listLocal() => _cache.listAll().map((c) => c.trip).toList();

  /// Uzak sunucudan tüm planları çeker ve yerel cache'e yazar (login sonrası
  /// initial pull için). Ağ yoksa sessizce çıkar; UI yerel cache'ten devam.
  Future<List<Trip>> pullAll() async {
    try {
      final rows = await _client
          .from('plans')
          .select()
          .eq('owner_id', _userId)
          .order('updated_at', ascending: false);
      final trips = <Trip>[];
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final doc = row['doc'];
        if (doc == null) continue;
        final docMap = doc is String
            ? (jsonDecode(doc) as Map).cast<String, dynamic>()
            : (doc as Map).cast<String, dynamic>();
        final trip = Trip.fromJson(docMap);
        trips.add(trip);
        await _cache.save(
          CachedPlan(
            trip: trip,
            version: (row['version'] as num?)?.toInt() ?? 1,
            updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '') ??
                DateTime.now(),
            dirty: false,
          ),
        );
      }
      return trips;
    } on Exception {
      return listLocal();
    }
  }

  /// Yerel değişikliği kaydet + sunucuya push et. Sunucu erişilemezse
  /// dirty=true kalır ve `syncDirty` çağrılana kadar bekler.
  ///
  /// Return: sunucu güncellemesi başarılıysa yeni `version`, aksi halde null.
  Future<int?> save(Trip trip) async {
    // 1) Yerel (optimistik).
    final existing = _cache.load(trip.id);
    final version = existing?.version ?? 1;
    await _cache.save(
      CachedPlan(
        trip: trip,
        version: version,
        updatedAt: DateTime.now(),
        dirty: true,
      ),
    );

    // 2) Sunucu — upsert.
    try {
      final row = await _client
          .from('plans')
          .upsert({
            'id': trip.id,
            'owner_id': _userId,
            'slug': trip.slug,
            'title': trip.title,
            'doc': trip.toJson(),
            // NOT: version DB trigger'ı tarafından otomatik artırılır.
          })
          .select('version, updated_at')
          .single();
      final newVersion = (row['version'] as num?)?.toInt() ?? version + 1;
      final newUpdated =
          DateTime.tryParse(row['updated_at'] as String? ?? '') ??
              DateTime.now();
      await _cache.save(
        CachedPlan(
          trip: trip,
          version: newVersion,
          updatedAt: newUpdated,
          dirty: false,
        ),
      );
      return newVersion;
    } on Exception {
      // Ağ yok / hata — dirty kalır.
      return null;
    }
  }

  /// Dirty tüm planları sunucuya push etmeyi dener (arka plan senkron için).
  Future<int> syncDirty() async {
    final dirty = _cache.dirtyPlans();
    var pushed = 0;
    for (final p in dirty) {
      final v = await save(p.trip);
      if (v != null) pushed++;
    }
    return pushed;
  }

  Future<void> delete(String planId) async {
    await _cache.delete(planId);
    try {
      await _client.from('plans').delete().eq('id', planId);
    } on Exception {
      // Ağ yok — bir sonraki senkronda tekrar denenir.
    }
  }
}
