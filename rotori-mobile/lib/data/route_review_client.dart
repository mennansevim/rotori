// Supabase Edge Function `review-route` için client.
//
// Üretilen günlük planı LLM'e okutup daha iyi bir SIRALAMA önerisi
// ister. Öneri istemcide `PlanScheduleEngine` üzerinden uygulanır; motor
// kilidi ve çakışmayı bağımsız doğruladığı için bu katman güven sınırı değil,
// yalnız öneri kaynağıdır (bkz. route_review.dart).

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';

const String routeReviewPromptVersion = 'route-review-candidate-v3';

/// Rota inceleme client'ı. Oturum yoksa null — inceleme atlanır.
///
/// **Why oturum şartı:** Edge Function kimlik doğruluyor (anahtar bizim,
/// fatura bizim). Önizleme/oturumsuz çalışmada üretim LLM'siz devam eder.
final routeReviewClientProvider = Provider<RouteReviewClient?>((ref) {
  if (ref.watch(currentUserProvider) == null) return null;
  return RouteReviewClient(supabase: ref.watch(supabaseProvider));
});

class RouteReviewCallResult {
  const RouteReviewCallResult({
    required this.review,
    required this.cacheHit,
    this.model,
    this.promptVersion = routeReviewPromptVersion,
    this.providerElapsedMs,
    this.inputTokens,
    this.outputTokens,
  });

  final RouteReview review;
  final bool cacheHit;
  final String? model;
  final String promptVersion;
  final int? providerElapsedMs;
  final int? inputTokens;
  final int? outputTokens;
}

class _CachedRouteReview {
  const _CachedRouteReview(this.result, this.createdAt);

  final RouteReviewCallResult result;
  final DateTime createdAt;
}

/// Bir gün için önerilen sıra ve saatler.
class RouteReviewDay {
  const RouteReviewDay({
    required this.dayNumber,
    required this.order,
    required this.times,
  });

  final int dayNumber;

  /// Durak id'lerinin önerilen sırası (girdiyle aynı küme).
  final List<String> order;

  /// id → `HH:mm`. Yalnız değişmesi önerilenler.
  final Map<String, String> times;

  static RouteReviewDay? tryFromJson(Map<String, dynamic> json) {
    final rawDayNumber = json['dayNumber'];
    final dayNumber = rawDayNumber is num ? rawDayNumber.toInt() : null;
    if (dayNumber == null) return null;
    final rawOrder = json['order'];
    final order = (rawOrder is List ? rawOrder : const <Object?>[])
        .whereType<String>()
        .toList(growable: false);
    final rawTimes = json['times'];
    final times = <String, String>{};
    if (rawTimes is Map) {
      for (final entry in rawTimes.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value is String) times[key] = value;
      }
    }
    if (order.isEmpty && times.isEmpty) return null;
    return RouteReviewDay(
      dayNumber: dayNumber,
      order: order,
      times: times,
    );
  }
}

/// LLM'in rota değerlendirmesi.
class RouteReview {
  const RouteReview({required this.days, required this.notes});

  final List<RouteReviewDay> days;

  /// Kısa gerekçeler (en fazla 3). Telemetriye ve tanılamaya gider.
  final List<String> notes;

  /// Uygulanacak bir öneri var mı?
  bool get hasSuggestions => days.isNotEmpty;

  static const RouteReview empty = RouteReview(days: [], notes: []);

  /// LLM gövdesini çözümler.
  ///
  /// **Why savunmalı cast:** Gövde model çıktısıdır — `days` pekâlâ string ya
  /// da sayı gelebilir. `as List?` bu durumda fırlatır ve üretimi kesecek bir
  /// istisnaya dönüşürdü; beklenen davranış "öneri yok" olmalı.
  static RouteReview fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'];
    final rawNotes = json['notes'];
    return RouteReview(
      days: (rawDays is List ? rawDays : const <Object?>[])
          .whereType<Map<String, dynamic>>()
          .map(RouteReviewDay.tryFromJson)
          .whereType<RouteReviewDay>()
          .toList(growable: false),
      notes: (rawNotes is List ? rawNotes : const <Object?>[])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}

class RouteReviewClient {
  RouteReviewClient({
    required this.supabase,
    this.cacheTtl = const Duration(days: 7),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SupabaseClient supabase;
  final Duration cacheTtl;
  final DateTime Function() _clock;
  final Map<String, _CachedRouteReview> _cache = {};

  /// Planı inceletir. Hata/limit durumunda [RouteReview.empty] döner —
  /// çağıran deterministik planı olduğu gibi tutar.
  Future<RouteReviewCallResult> review(Map<String, dynamic> payload) async {
    final request = <String, dynamic>{
      ...payload,
      'promptVersion': routeReviewPromptVersion,
    };
    final cacheKey = _stableHash(jsonEncode(request));
    final cached = _cache[cacheKey];
    if (cached != null && _clock().isBefore(cached.createdAt.add(cacheTtl))) {
      return RouteReviewCallResult(
        review: cached.result.review,
        cacheHit: true,
        model: cached.result.model,
        promptVersion: cached.result.promptVersion,
        providerElapsedMs: cached.result.providerElapsedMs,
        inputTokens: cached.result.inputTokens,
        outputTokens: cached.result.outputTokens,
      );
    }
    if (cached != null) _cache.remove(cacheKey);

    final response = await supabase.functions.invoke(
      'review-route',
      method: HttpMethod.post,
      body: jsonEncode(request),
    );
    if (response.status >= 400) {
      return const RouteReviewCallResult(
        review: RouteReview.empty,
        cacheHit: false,
      );
    }
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      return const RouteReviewCallResult(
        review: RouteReview.empty,
        cacheHit: false,
      );
    }
    final meta = data['meta'];
    final result = RouteReviewCallResult(
      review: RouteReview.fromJson(data),
      cacheHit: false,
      model: meta is Map ? meta['model'] as String? : null,
      promptVersion: meta is Map
          ? meta['promptVersion'] as String? ?? routeReviewPromptVersion
          : routeReviewPromptVersion,
      providerElapsedMs:
          meta is Map ? (meta['elapsedMs'] as num?)?.toInt() : null,
      inputTokens: meta is Map ? (meta['inputTokens'] as num?)?.toInt() : null,
      outputTokens:
          meta is Map ? (meta['outputTokens'] as num?)?.toInt() : null,
    );
    _cache[cacheKey] = _CachedRouteReview(result, _clock());
    return result;
  }
}

String _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash.toRadixString(16);
}
