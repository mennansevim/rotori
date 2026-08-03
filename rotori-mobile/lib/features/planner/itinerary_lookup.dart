// apps/planner/src/utils/itineraryLookup.ts birebir karşılığı.
// Önce AI endpoint'ini dener (aynı JSON sözleşmesi: Trip gönder,
// { source, days: AiItineraryDay[] } al); 501/502/ağ hatasında kural
// tabanlı üreticiye (generateItineraryFromTrip + fillEmptyDays) düşer.

import 'dart:convert';
import 'dart:io';

import '../../domain/fill_empty_days.dart';
import '../../domain/itinerary_generator.dart';
import '../../domain/types.dart';

/// AI plan servisi taban URL'i (React'ta dev-proxy'li `/api/itinerary`).
/// Mobil derlemede henüz bir host yapılandırılmadı — boş bırakılınca
/// doğrudan kural tabanlı fallback çalışır.
/// TODO: Planner API deploy edilince `--dart-define=ITINERARY_API_BASE=...`
/// ile ver (örn. https://planner.example.com); endpoint `POST <base>/api/itinerary`.
const String kItineraryApiBase =
    String.fromEnvironment('ITINERARY_API_BASE', defaultValue: '');

enum ItinerarySource { ai, rules }

enum ItineraryReason { ok, notConfigured, aiFailed, network, unknown }

class ItineraryResult {
  const ItineraryResult({
    required this.source,
    required this.reason,
    required this.days,
  });
  final ItinerarySource source;
  final ItineraryReason reason;
  final List<DayPlan> days;
}

List<TripDestination> _sortedDestinations(Trip trip) =>
    [...trip.preferences.destinations]
      ..sort((a, b) => a.order.compareTo(b.order));

ItineraryResult _rules(Trip trip, ItineraryReason reason) => ItineraryResult(
      source: ItinerarySource.rules,
      reason: reason,
      days: fillEmptyDays(
        generateItineraryFromTrip(trip),
        _sortedDestinations(trip),
      ),
    );

/// Önce AI dener; başarısızsa kural tabanlı üreticiye düşer.
/// [client] test için enjekte edilebilir.
Future<ItineraryResult> generateItinerary(
  Trip trip, {
  HttpClient? client,
}) async {
  if (kItineraryApiBase.isEmpty) {
    // API tabanı yapılandırılmamış — React'taki 501 (not-configured) muadili.
    return _rules(trip, ItineraryReason.notConfigured);
  }

  final http = client ?? HttpClient();
  http.connectionTimeout = const Duration(seconds: 20);
  try {
    final uri = Uri.parse('$kItineraryApiBase/api/itinerary');
    final req = await http.postUrl(uri);
    req.headers.contentType = ContentType.json;
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.write(jsonEncode(trip.toJson()));
    final resp = await req.close().timeout(const Duration(seconds: 120));

    if (resp.statusCode == 501) {
      return _rules(trip, ItineraryReason.notConfigured);
    }
    if (resp.statusCode == 502) return _rules(trip, ItineraryReason.aiFailed);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return _rules(trip, ItineraryReason.unknown);
    }

    final body = await resp.transform(utf8.decoder).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final source = data['source'] as String?;
    final rawDays = data['days'] as List?;
    if (source == 'ai' && rawDays != null && rawDays.isNotEmpty) {
      final aiDays = rawDays
          .map((e) => AiItineraryDay.fromJson((e as Map).cast()))
          .toList();
      final merged = mergeAiItinerary(trip.days, aiDays);
      return ItineraryResult(
        source: ItinerarySource.ai,
        reason: ItineraryReason.ok,
        days: fillEmptyDays(merged, _sortedDestinations(trip)),
      );
    }
    return _rules(trip, ItineraryReason.aiFailed);
  } on Object {
    return _rules(trip, ItineraryReason.network);
  } finally {
    if (client == null) http.close(force: true);
  }
}
