// packages/shared/src/geofence.ts'in Dart portu.
// Haversine mesafe + Geofence / VisitRecord / VisitState modelleri.
// Matematik React referansıyla birebir aynıdır (R = 6371000, derece→radyan).

import 'dart:math' as math;

/// Varsayılan minimum kalma süresi (sn) — 10 dk.
const int kDefaultMinDwell = 600;

/// Basit lat/lng değer çifti.
class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;
}

/// Mesafe (metre) — Haversine. Geofence kontrolü için yeterli hassasiyette.
double distanceMeters(LatLng a, LatLng b) {
  const r = 6371000.0;
  double toRad(double d) => (d * math.pi) / 180;
  final dLat = toRad(b.lat - a.lat);
  final dLng = toRad(b.lng - a.lng);
  final lat1 = toRad(a.lat);
  final lat2 = toRad(b.lat);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// GPS ile otomatik ziyaret algılanan nokta tanımı.
class Geofence {
  const Geofence({
    required this.id,
    required this.name,
    required this.city,
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    required this.minDwellSeconds,
    required this.xp,
    required this.emoji,
    this.mapX = 0,
    this.mapY = 0,
  });

  final String id;
  final String name;
  final String city;
  final double lat;
  final double lng;
  final double radiusMeters;
  final int minDwellSeconds;
  final int xp;
  final String emoji;

  /// Stilize harita koordinatları (viewBox 0..600 x 0..360) — mini-kroki
  /// projeksiyonu kullanıldığından mobilde 0 bırakılır.
  final double mapX;
  final double mapY;

  factory Geofence.fromJson(Map<String, dynamic> j) => Geofence(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        city: (j['city'] as String?) ?? '',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        radiusMeters: ((j['radiusMeters'] as num?) ?? 120).toDouble(),
        minDwellSeconds:
            ((j['minDwellSeconds'] as num?) ?? kDefaultMinDwell).toInt(),
        xp: ((j['xp'] as num?) ?? 0).toInt(),
        emoji: (j['emoji'] as String?) ?? '📍',
        mapX: ((j['mapX'] as num?) ?? 0).toDouble(),
        mapY: ((j['mapY'] as num?) ?? 0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'city': city,
        'lat': lat,
        'lng': lng,
        'radiusMeters': radiusMeters,
        'minDwellSeconds': minDwellSeconds,
        'xp': xp,
        'emoji': emoji,
        'mapX': mapX,
        'mapY': mapY,
      };
}

/// Tek bir geofence için ziyaret kaydı.
class VisitRecord {
  const VisitRecord({
    required this.geofenceId,
    this.totalDwellSeconds = 0,
    this.firstSeenAt,
    this.completedAt,
  });

  final String geofenceId;

  /// Biriken kalma süresi (sn) — kesirli olabilir (tick aralıkları ms bazlı).
  final double totalDwellSeconds;

  /// İlk algılanma zamanı (ISO 8601).
  final String? firstSeenAt;

  /// Tamamlanma zamanı (ISO 8601) — set edilmişse nokta "gezildi".
  final String? completedAt;

  VisitRecord copyWith({
    double? totalDwellSeconds,
    String? firstSeenAt,
    String? completedAt,
  }) =>
      VisitRecord(
        geofenceId: geofenceId,
        totalDwellSeconds: totalDwellSeconds ?? this.totalDwellSeconds,
        firstSeenAt: firstSeenAt ?? this.firstSeenAt,
        completedAt: completedAt ?? this.completedAt,
      );

  factory VisitRecord.fromJson(Map<String, dynamic> j) => VisitRecord(
        geofenceId: (j['geofenceId'] as String?) ?? '',
        totalDwellSeconds: ((j['totalDwellSeconds'] as num?) ?? 0).toDouble(),
        firstSeenAt: j['firstSeenAt'] as String?,
        completedAt: j['completedAt'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'geofenceId': geofenceId,
        'totalDwellSeconds': totalDwellSeconds,
        if (firstSeenAt != null) 'firstSeenAt': firstSeenAt,
        if (completedAt != null) 'completedAt': completedAt,
      };
}

/// Tüm ziyaret kayıtları (geofenceId → kayıt).
class VisitState {
  const VisitState({this.records = const {}});

  final Map<String, VisitRecord> records;

  /// React'taki upsertRecord karşılığı — mevcut kaydın üzerine patch uygular.
  VisitState upsert(
    String geofenceId, {
    double? totalDwellSeconds,
    String? firstSeenAt,
    String? completedAt,
  }) {
    final cur = records[geofenceId] ?? VisitRecord(geofenceId: geofenceId);
    return VisitState(records: {
      ...records,
      geofenceId: cur.copyWith(
        totalDwellSeconds: totalDwellSeconds,
        firstSeenAt: firstSeenAt,
        completedAt: completedAt,
      ),
    });
  }

  factory VisitState.fromJson(Map<String, dynamic> j) {
    final raw = j['records'];
    if (raw is! Map) return const VisitState();
    final records = <String, VisitRecord>{};
    raw.forEach((key, value) {
      if (value is Map) {
        records[key as String] =
            VisitRecord.fromJson(value.cast<String, dynamic>());
      }
    });
    return VisitState(records: records);
  }

  Map<String, dynamic> toJson() => {
        'records': records.map((k, v) => MapEntry(k, v.toJson())),
      };
}
