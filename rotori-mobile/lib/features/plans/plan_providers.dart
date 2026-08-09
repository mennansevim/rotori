import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/plans_repository.dart';
import '../../domain/types.dart';

/// Sunucudan tüm planları çekip yerel cache'e yazar; UI initial pull için.
final plansPullProvider = FutureProvider<List<Trip>>((ref) async {
  final repo = ref.watch(plansRepositoryProvider);
  if (repo == null) return [];
  return repo.pullAll();
});

/// Yerel cache'ten anlık plan listesi (offline-first).
final localPlansProvider = Provider<List<Trip>>((ref) {
  // pullProvider tetikleyicisi — pull başarılıysa yerel yenilenir
  ref.watch(plansPullProvider);
  final repo = ref.watch(plansRepositoryProvider);
  if (repo == null) return const [];
  return repo.listLocal();
});

/// Yeni üretilen plan — oluşturma akışı viewer'a geçmeden önce buraya yazar.
///
/// Repository varken gereksizdir (`watch()` zaten yerel cache'ten anında yayın
/// yapar); repo null olduğunda (önizleme girişi, oturumsuz çalışma) planın
/// kaybolmaması için tek kaynaktır.
final draftTripProvider = StateProvider<Trip?>((ref) => null);

/// Belirli bir planı realtime + yerel senkron dinler.
final planByIdProvider = StreamProvider.family<Trip, String>((ref, planId) {
  final repo = ref.watch(plansRepositoryProvider);
  if (repo == null) {
    final draft = ref.watch(draftTripProvider);
    if (draft != null && draft.id == planId) return Stream<Trip>.value(draft);
    return const Stream.empty();
  }
  return repo.watch(planId);
});
