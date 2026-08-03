// Yerel hatırlatma deposu — SharedPreferences üzerinde JSON liste.
// Bilet açılış hatırlatmaları burada tutulur, bildirim planlaması
// features/notifications/notifications_service.dart tarafından yapılır.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Reminder {
  const Reminder({
    required this.id,
    required this.windowId,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.fireAt,
    required this.tip,
    required this.tripId,
  });

  final String id;
  final String windowId;
  final String title;
  final String subtitle;
  final String icon;
  final DateTime fireAt;
  final String tip;
  final String? tripId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'windowId': windowId,
        'title': title,
        'subtitle': subtitle,
        'icon': icon,
        'fireAt': fireAt.toIso8601String(),
        'tip': tip,
        'tripId': tripId,
      };

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
        id: j['id'] as String,
        windowId: (j['windowId'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        subtitle: (j['subtitle'] as String?) ?? '',
        icon: (j['icon'] as String?) ?? '🔔',
        fireAt: DateTime.parse(j['fireAt'] as String),
        tip: (j['tip'] as String?) ?? '',
        tripId: j['tripId'] as String?,
      );

  /// Bildirimin schedule için kullanılacağı stabil integer id.
  int get notificationId => id.hashCode & 0x7fffffff;
}

class RemindersStore extends StateNotifier<List<Reminder>> {
  RemindersStore() : super(const []) {
    _load();
  }

  static const _prefsKey = 'reminders_v1';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(Reminder.fromJson)
          .toList();
      if (mounted) state = list;
    } catch (e) {
      debugPrint('RemindersStore._load error: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(state.map((r) => r.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('RemindersStore._persist error: $e');
    }
  }

  bool hasFor(String windowId, {String? tripId}) => state.any((r) =>
      r.windowId == windowId && (tripId == null || r.tripId == tripId));

  Future<void> add(Reminder r) async {
    // Aynı windowId + tripId için tek uyarı tut — varsa değiştir.
    state = [
      ...state.where((x) => !(x.windowId == r.windowId && x.tripId == r.tripId)),
      r,
    ];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((r) => r.id != id).toList();
    await _persist();
  }

  Future<void> clear() async {
    state = const [];
    await _persist();
  }
}

final remindersProvider =
    StateNotifierProvider<RemindersStore, List<Reminder>>((ref) {
  return RemindersStore();
});
