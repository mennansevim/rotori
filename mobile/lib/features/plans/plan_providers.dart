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

/// Belirli bir planı realtime + yerel senkron dinler.
final planByIdProvider = StreamProvider.family<Trip, String>((ref, planId) {
  final repo = ref.watch(plansRepositoryProvider);
  if (repo == null) return const Stream.empty();
  return repo.watch(planId);
});
