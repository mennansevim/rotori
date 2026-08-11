import '../../domain/destination_profiles.dart' show getDestinationForDate;
import '../../domain/itinerary_optimizer.dart';
import '../../domain/place_coords.dart';
import '../../domain/route_matrix.dart';
import '../../domain/route_time_bounds.dart';
import '../../domain/types.dart';
import 'plan_optimization_controller.dart';

typedef InitialRoutePreviewBuilder = Future<PlanOptimizationPreview> Function(
  DayOptimizationInput input,
);

/// Kural tabanlı ilk taslağı, kaydedilmeden önce günlük rota motorundan geçirir.
///
/// Uçuş, otel ve şehirler arası ulaşım içeren günler sabit operasyon günleridir;
/// bu günlerin sırası burada değiştirilmez. Diğer günlerde küratörlü gerçek
/// koordinatlar, mekan süreleri, açılış saatleri ve rota matrisi kullanılır.
Future<Trip> optimizeInitialTripRoutes({
  required Trip trip,
  required InitialRoutePreviewBuilder buildPreview,
  int planVersion = 1,
}) async {
  var optimized = Trip.fromJson(trip.toJson());
  final destinations = [...optimized.preferences.destinations]
    ..sort((a, b) => a.order.compareTo(b.order));

  for (final sourceDay in [...optimized.days]) {
    if (!_isOptimizableSightseeingDay(sourceDay)) continue;

    final destination = getDestinationForDate(destinations, sourceDay.date);
    final cityData = cityDataForKey(destination?.city);
    final centerLat = destination?.lat ??
        (cityData?.places.isNotEmpty == true
            ? cityData!.places.first.lat
            : null);
    final centerLng = destination?.lng ??
        (cityData?.places.isNotEmpty == true
            ? cityData!.places.first.lng
            : null);
    final date = DateTime.tryParse(sourceDay.date);
    if (centerLat == null || centerLng == null || date == null) continue;

    final prepared = Trip.fromJson(optimized.toJson());
    final day = prepared.days.firstWhere(
      (candidate) => candidate.dayNumber == sourceDay.dayNumber,
    );
    _hydrateDayCoordinates(
      day,
      cityKey: destination?.city,
      centerLat: centerLat,
      centerLng: centerLng,
    );

    final base = TripLocation(
      id: 'day-${day.dayNumber}-base',
      name: optimized.preferences.stayArea?.trim().isNotEmpty == true
          ? optimized.preferences.stayArea!.trim()
          : (destination?.city ?? 'Gün başlangıcı'),
      latitude: centerLat,
      longitude: centerLng,
      city: destination?.city,
      clusterId: destination?.city,
    );

    try {
      final preview = await buildPreview(
        DayOptimizationInput(
          trip: prepared,
          dayNumber: day.dayNumber,
          planVersion: planVersion,
          constraints: DayRouteConstraints(
            startLocation: base,
            endLocation: base,
            availableStartTime:
                DateTime(date.year, date.month, date.day, kRouteStartHour),
            availableEndTime:
                DateTime(date.year, date.month, date.day, kRouteEndHour),
          ),
          preferences: RoutePreferences(
            profile: RouteOptimizationProfile.balanced,
            maximumWalkingMinutes:
                optimized.preferences.maxStepsPerDay == null ? 180 : 120,
            partySize: optimized.preferences.partySize ?? 1,
          ),
        ),
      );
      optimized = preview.optimizedTrip;
    } on Object {
      // Tek bir gün için rota sağlayıcısı/optimizer sonuç üretemezse bütün planı
      // kaybetme. Üretilmiş güvenli taslak korunur; kullanıcı daha sonra o günü
      // yeniden optimize edebilir.
    }
  }
  return optimized;
}

bool _isOptimizableSightseeingDay(DayPlan day) {
  if (day.items.length < 2) return false;
  return !day.items.any(
    (item) =>
        item.kind == TimelineItemKind.transport ||
        item.kind == TimelineItemKind.hotel ||
        item.lockType == ActivityLockType.flight ||
        item.lockType == ActivityLockType.trainReservation,
  );
}

void _hydrateDayCoordinates(
  DayPlan day, {
  required String? cityKey,
  required double centerLat,
  required double centerLng,
}) {
  double? previousLat;
  double? previousLng;
  for (final item in day.items) {
    var lat = item.lat;
    var lng = item.lng;
    if (lat == null || lng == null) {
      final coordinate = resolvePlaceCoords(item.title, cityKey: cityKey);
      lat = coordinate?.lat;
      lng = coordinate?.lng;
    }

    // Öğün/serbest zaman gerçek bir POI değilse, bir önceki ziyaretin çevresinde
    // kabul edilir. Böylece şehir merkezine gidip geri dönüyormuş gibi sahte bir
    // rota oluşmaz. İlk kalem çözülemiyorsa şehir merkezi güvenli başlangıçtır.
    lat ??= previousLat ?? centerLat;
    lng ??= previousLng ?? centerLng;
    item
      ..lat = lat
      ..lng = lng;
    previousLat = lat;
    previousLng = lng;
  }
}
