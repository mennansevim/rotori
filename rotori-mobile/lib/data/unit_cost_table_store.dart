// Birim maliyet tablosu sağlayıcısı — offline-öncelikli kaynak zinciri:
//   1) Supabase `unit_costs` (uzaktan güncellenebilir; başarılı çekim cache'lenir)
//   2) Yerel cache (son başarılı Supabase çekimi, SharedPreferences)
//   3) Gömülü INI asset (assets/data/unit_costs.ini)
//   4) Saf-Dart gömülü varsayılan (UnitCostTable.defaults)
//
// Ağ hatası/erişim yoksa sessizce bir alt kaynağa düşer. Değerleri güvenilir
// backend/Supabase yazar; istemci YALNIZCA okur (RLS). AI KULLANILMAZ.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/supabase_client.dart';
import '../domain/cost_estimate.dart';
import 'plans_repository.dart';

/// Son başarılı Supabase çekiminin cache anahtarı.
const _kUnitCostCacheKey = 'budget:unitCostSections';

/// Supabase satırlarını `section → {key: value}` haritasına dönüştürür.
Map<String, Map<String, String>> _sectionsFromRows(List<dynamic> rows) {
  final sections = <String, Map<String, String>>{};
  for (final row in rows) {
    if (row is! Map) continue;
    final sec = (row['section'] as String?)?.trim().toLowerCase() ?? '';
    final key = (row['key'] as String?)?.trim().toLowerCase() ?? '';
    if (sec.isEmpty || key.isEmpty) continue;
    (sections[sec] ??= {})[key] = '${row['value'] ?? ''}';
  }
  return sections;
}

/// Birim maliyet tablosu — Supabase → cache → INI → varsayılan.
final unitCostTableProvider = FutureProvider<UnitCostTable>((ref) async {
  final prefs = await ref.read(sharedPrefsProvider.future);

  // 1) Supabase — uzaktan güncellenebilir kaynak.
  try {
    final rows = await ref
        .read(supabaseProvider)
        .from('unit_costs')
        .select('section,key,value');
    final sections = _sectionsFromRows(rows as List);
    if (sections.isNotEmpty) {
      await prefs.setString(_kUnitCostCacheKey, jsonEncode(sections));
      return UnitCostTable.fromSections(sections);
    }
  } catch (_) {
    // Offline / erişim yok — cache/asset'e düş.
  }

  // 2) Yerel cache (son başarılı Supabase çekimi).
  final cached = prefs.getString(_kUnitCostCacheKey);
  if (cached != null && cached.isNotEmpty) {
    try {
      final decoded = (jsonDecode(cached) as Map).map(
        (k, v) => MapEntry(
          k as String,
          (v as Map).map((kk, vv) => MapEntry(kk as String, '$vv')),
        ),
      );
      return UnitCostTable.fromSections(decoded);
    } catch (_) {
      // Bozuk cache — asset'e düş.
    }
  }

  // 3) Gömülü INI asset.
  try {
    final raw = await rootBundle.loadString('assets/data/unit_costs.ini');
    return UnitCostTable.parseIni(raw);
  } catch (_) {
    // 4) Gömülü varsayılan.
    return UnitCostTable.defaults();
  }
});
