// Valiz & Hazırlık deposu — her plan (trip) için ayrı işaretli durum + özel
// maddeler. SharedPreferences altında `viewer:checklist:<tripId>` anahtarıyla
// JSON olarak saklanır:
//   { "checkedIds": [...], "custom": [ {id, category, label, note}, ... ] }
//
// reminders_store / exchange_rate_store desenini izler: init'te yükler,
// her değişiklikte kalıcılaştırır, JSON'a toleranslıdır (hata yutulur).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/packing_data.dart';
import 'plans_repository.dart';

/// Bir plan için kontrol listesi durumu (değişmez).
class ChecklistState {
  const ChecklistState({
    this.checkedIds = const {},
    this.customItems = const [],
  });

  /// İşaretlenmiş madde id'leri (hem şablon hem özel maddeler için).
  final Set<String> checkedIds;

  /// Kullanıcının eklediği özel maddeler.
  final List<ChecklistItem> customItems;

  ChecklistState copyWith({
    Set<String>? checkedIds,
    List<ChecklistItem>? customItems,
  }) =>
      ChecklistState(
        checkedIds: checkedIds ?? this.checkedIds,
        customItems: customItems ?? this.customItems,
      );
}

class ChecklistNotifier extends StateNotifier<ChecklistState> {
  ChecklistNotifier(this._ref, this.tripId) : super(const ChecklistState()) {
    _load();
  }

  final Ref _ref;
  final String tripId;

  String get _key => 'viewer:checklist:$tripId';

  Future<void> _load() async {
    try {
      final prefs = await _ref.read(sharedPrefsProvider.future);
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
      final checked = ((map['checkedIds'] as List?) ?? const [])
          .map((e) => e.toString())
          .toSet();
      final custom = ((map['custom'] as List?) ?? const [])
          .cast<dynamic>()
          .map((e) => ChecklistItem.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      if (mounted) {
        state = ChecklistState(checkedIds: checked, customItems: custom);
      }
    } catch (e) {
      debugPrint('ChecklistNotifier._load error: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await _prefs();
      final payload = {
        'checkedIds': state.checkedIds.toList(),
        'custom': state.customItems.map((c) => c.toJson()).toList(),
      };
      await prefs.setString(_key, jsonEncode(payload));
    } catch (e) {
      debugPrint('ChecklistNotifier._persist error: $e');
    }
  }

  Future<SharedPreferences> _prefs() async {
    final cached = _ref.read(sharedPrefsProvider).valueOrNull;
    if (cached != null) return cached;
    return _ref.read(sharedPrefsProvider.future);
  }

  /// Bir maddenin işaretini değiştirir (işaretle / kaldır) ve kalıcılaştırır.
  Future<void> toggle(String id) async {
    final next = {...state.checkedIds};
    if (!next.remove(id)) next.add(id);
    state = state.copyWith(checkedIds: next);
    await _persist();
  }

  /// Özel bir madde ekler. Id, gerçek zamana ihtiyaç duymadan label+kategori
  /// karmasından türetilir (stabil). Aynı id zaten varsa yok sayılır.
  Future<void> addCustom(String category, String label) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return;
    final cat = category.trim().isEmpty ? 'Diğer' : category.trim();
    final id = 'custom-$cat-${trimmed.hashCode}';
    if (state.customItems.any((c) => c.id == id)) return;
    final item = ChecklistItem(id: id, category: cat, label: trimmed);
    state = state.copyWith(customItems: [...state.customItems, item]);
    await _persist();
  }

  /// Özel bir maddeyi siler (ve varsa işaretini de temizler).
  Future<void> removeCustom(String id) async {
    state = state.copyWith(
      customItems: state.customItems.where((c) => c.id != id).toList(),
      checkedIds: {...state.checkedIds}..remove(id),
    );
    await _persist();
  }

  /// Tüm işaretleri ve özel maddeleri temizler.
  Future<void> reset() async {
    state = const ChecklistState();
    await _persist();
  }
}

/// Plan bazlı kontrol listesi durumu (kalıcı).
final checklistProvider = StateNotifierProvider.family<ChecklistNotifier,
    ChecklistState, String>(
  (ref, tripId) => ChecklistNotifier(ref, tripId),
);
