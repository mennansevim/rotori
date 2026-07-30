import 'dart:convert';

/// Section A prompt'unun girdi ve çıktı JSON sözleşmesinin saf Dart modeli.
///
/// Aynı tipler hem AI agent'ı hem de deterministik `BeamSearchItineraryOptimizer`
/// tarafından `RoutePlanOutput`'a çevrilirken kullanılır; hard checker ve rubric
/// de bu tipler üzerinden çalışır.

enum PromptActivityCategory {
  sightseeing,
  meal,
  shopping,
  onsen,
  museum,
  park,
  shrine,
  nightlife,
  transit,
}

enum PromptTimePreference { morning, afternoon, evening }

enum PromptTransportMode {
  walking,
  train,
  metro,
  bus,
  taxi,
  shinkansen,
  regional,
}

enum PromptTimelineKind { activity, transit, idle }

enum PromptDropReason { noRoute, windowConflict, duration, redundant }

class PromptHotel {
  const PromptHotel({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.cluster,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String cluster;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'lat': latitude,
        'lng': longitude,
        'cluster': cluster,
      };

  static PromptHotel fromJson(Map<String, Object?> json) => PromptHotel(
        id: json['id']! as String,
        name: json['name']! as String,
        latitude: (json['lat']! as num).toDouble(),
        longitude: (json['lng']! as num).toDouble(),
        cluster: json['cluster']! as String,
      );
}

class PromptActivity {
  const PromptActivity({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.cluster,
    required this.category,
    required this.durationMinutes,
    this.minimumDurationMinutes,
    this.openingTime,
    this.closingTime,
    this.fixedStartTime,
    this.fixedEndTime,
    this.isFixed = false,
    this.isLocked = false,
    this.hasReservation = false,
    this.preferredTime,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String cluster;
  final PromptActivityCategory category;
  final int durationMinutes;
  final int? minimumDurationMinutes;

  /// HH:mm biçiminde açılış/kapanış — gün dışı taşma yok.
  final String? openingTime;
  final String? closingTime;
  final String? fixedStartTime;
  final String? fixedEndTime;
  final bool isFixed;
  final bool isLocked;
  final bool hasReservation;
  final PromptTimePreference? preferredTime;

  bool get hasFixedSchedule =>
      isFixed || isLocked || fixedStartTime != null || fixedEndTime != null;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'lat': latitude,
        'lng': longitude,
        'cluster': cluster,
        'category': category.name,
        'durationMinutes': durationMinutes,
        if (minimumDurationMinutes != null)
          'minimumDurationMinutes': minimumDurationMinutes,
        if (openingTime != null) 'openingTime': openingTime,
        if (closingTime != null) 'closingTime': closingTime,
        if (fixedStartTime != null) 'fixedStartTime': fixedStartTime,
        if (fixedEndTime != null) 'fixedEndTime': fixedEndTime,
        if (isFixed) 'isFixed': true,
        if (isLocked) 'isLocked': true,
        if (hasReservation) 'hasReservation': true,
        if (preferredTime != null) 'preferredTime': preferredTime!.name,
      };

  static PromptActivity fromJson(Map<String, Object?> json) => PromptActivity(
        id: json['id']! as String,
        name: json['name']! as String,
        latitude: (json['lat']! as num).toDouble(),
        longitude: (json['lng']! as num).toDouble(),
        cluster: json['cluster']! as String,
        category: PromptActivityCategory.values
            .byName(json['category']! as String),
        durationMinutes: (json['durationMinutes']! as num).toInt(),
        minimumDurationMinutes:
            (json['minimumDurationMinutes'] as num?)?.toInt(),
        openingTime: json['openingTime'] as String?,
        closingTime: json['closingTime'] as String?,
        fixedStartTime: json['fixedStartTime'] as String?,
        fixedEndTime: json['fixedEndTime'] as String?,
        isFixed: json['isFixed'] as bool? ?? false,
        isLocked: json['isLocked'] as bool? ?? false,
        hasReservation: json['hasReservation'] as bool? ?? false,
        preferredTime: json['preferredTime'] == null
            ? null
            : PromptTimePreference.values.byName(json['preferredTime']! as String),
      );
}

class PromptRouteEntry {
  const PromptRouteEntry({
    required this.fromId,
    required this.toId,
    required this.mode,
    required this.doorToDoorMinutes,
    required this.walkingMinutes,
    required this.transferCount,
    required this.yenCost,
    required this.reliability,
  });

  final String fromId;
  final String toId;
  final PromptTransportMode mode;
  final int doorToDoorMinutes;
  final int walkingMinutes;
  final int transferCount;
  final int yenCost;
  final double reliability;

  Map<String, Object?> toJson() => {
        'fromId': fromId,
        'toId': toId,
        'mode': mode.name,
        'doorToDoorMinutes': doorToDoorMinutes,
        'walkingMinutes': walkingMinutes,
        'transferCount': transferCount,
        'yenCost': yenCost,
        'reliability': reliability,
      };

  static PromptRouteEntry fromJson(Map<String, Object?> json) =>
      PromptRouteEntry(
        fromId: json['fromId']! as String,
        toId: json['toId']! as String,
        mode: PromptTransportMode.values.byName(json['mode']! as String),
        doorToDoorMinutes: (json['doorToDoorMinutes']! as num).toInt(),
        walkingMinutes: (json['walkingMinutes']! as num).toInt(),
        transferCount: (json['transferCount']! as num).toInt(),
        yenCost: (json['yenCost']! as num).toInt(),
        reliability: (json['reliability']! as num).toDouble(),
      );
}

class RoutePlanScenario {
  const RoutePlanScenario({
    required this.id,
    required this.date,
    required this.city,
    required this.hotel,
    required this.dayStart,
    required this.dayEnd,
    required this.activities,
    required this.routeMatrix,
    this.seed,
    this.notes,
  });

  final String id;

  /// `YYYY-MM-DD`.
  final String date;
  final String city;
  final PromptHotel hotel;

  /// ISO datetime; `date` günü içindeki başlama saati.
  final DateTime dayStart;
  final DateTime dayEnd;
  final List<PromptActivity> activities;
  final List<PromptRouteEntry> routeMatrix;
  final int? seed;
  final String? notes;

  Map<String, Object?> toJson() => {
        'id': id,
        'date': date,
        'city': city,
        'hotel': hotel.toJson(),
        'dayStart': dayStart.toIso8601String(),
        'dayEnd': dayEnd.toIso8601String(),
        'activities': activities.map((a) => a.toJson()).toList(),
        'routeMatrix': routeMatrix.map((r) => r.toJson()).toList(),
        if (seed != null) 'seed': seed,
        if (notes != null) 'notes': notes,
      };

  static RoutePlanScenario fromJson(Map<String, Object?> json) =>
      RoutePlanScenario(
        id: json['id']! as String,
        date: json['date']! as String,
        city: json['city']! as String,
        hotel: PromptHotel.fromJson(
          (json['hotel']! as Map).cast<String, Object?>(),
        ),
        dayStart: DateTime.parse(json['dayStart']! as String),
        dayEnd: DateTime.parse(json['dayEnd']! as String),
        activities: (json['activities']! as List)
            .cast<Map<String, Object?>>()
            .map(PromptActivity.fromJson)
            .toList(),
        routeMatrix: (json['routeMatrix']! as List)
            .cast<Map<String, Object?>>()
            .map(PromptRouteEntry.fromJson)
            .toList(),
        seed: (json['seed'] as num?)?.toInt(),
        notes: json['notes'] as String?,
      );

  static RoutePlanScenario decode(String jsonText) =>
      fromJson(json.decode(jsonText) as Map<String, Object?>);
}

class PromptTimelineEntry {
  const PromptTimelineEntry.activity({
    required this.startTime,
    required this.endTime,
    required this.activityId,
  })  : kind = PromptTimelineKind.activity,
        fromId = null,
        toId = null,
        mode = null,
        doorToDoorMinutes = null,
        walkingMinutes = null,
        transferCount = null,
        yenCost = null,
        note = null;

  const PromptTimelineEntry.transit({
    required this.startTime,
    required this.endTime,
    required String this.fromId,
    required String this.toId,
    required PromptTransportMode this.mode,
    required int this.doorToDoorMinutes,
    required int this.walkingMinutes,
    required int this.transferCount,
    required int this.yenCost,
  })  : kind = PromptTimelineKind.transit,
        activityId = null,
        note = null;

  const PromptTimelineEntry.idle({
    required this.startTime,
    required this.endTime,
    this.note,
  })  : kind = PromptTimelineKind.idle,
        activityId = null,
        fromId = null,
        toId = null,
        mode = null,
        doorToDoorMinutes = null,
        walkingMinutes = null,
        transferCount = null,
        yenCost = null;

  final PromptTimelineKind kind;

  /// `HH:mm`. Prompt çıktısı gün-lokal saati yazar; tarih bilgisi senaryo
  /// üstünden çözülür.
  final String startTime;
  final String endTime;
  final String? activityId;
  final String? fromId;
  final String? toId;
  final PromptTransportMode? mode;
  final int? doorToDoorMinutes;
  final int? walkingMinutes;
  final int? transferCount;
  final int? yenCost;
  final String? note;

  Map<String, Object?> toJson() {
    switch (kind) {
      case PromptTimelineKind.activity:
        return {
          'kind': 'activity',
          'activityId': activityId,
          'start': startTime,
          'end': endTime,
        };
      case PromptTimelineKind.transit:
        return {
          'kind': 'transit',
          'fromId': fromId,
          'toId': toId,
          'mode': mode!.name,
          'start': startTime,
          'end': endTime,
          'doorToDoorMinutes': doorToDoorMinutes,
          'walkingMinutes': walkingMinutes,
          'transferCount': transferCount,
          'yenCost': yenCost,
        };
      case PromptTimelineKind.idle:
        return {
          'kind': 'idle',
          'start': startTime,
          'end': endTime,
          if (note != null) 'note': note,
        };
    }
  }

  static PromptTimelineEntry fromJson(Map<String, Object?> json) {
    final kindName = json['kind']! as String;
    final start = json['start']! as String;
    final end = json['end']! as String;
    switch (kindName) {
      case 'activity':
        return PromptTimelineEntry.activity(
          startTime: start,
          endTime: end,
          activityId: json['activityId']! as String,
        );
      case 'transit':
        return PromptTimelineEntry.transit(
          startTime: start,
          endTime: end,
          fromId: json['fromId']! as String,
          toId: json['toId']! as String,
          mode: PromptTransportMode.values.byName(json['mode']! as String),
          doorToDoorMinutes: (json['doorToDoorMinutes']! as num).toInt(),
          walkingMinutes: (json['walkingMinutes']! as num).toInt(),
          transferCount: (json['transferCount']! as num).toInt(),
          yenCost: (json['yenCost']! as num).toInt(),
        );
      case 'idle':
        return PromptTimelineEntry.idle(
          startTime: start,
          endTime: end,
          note: json['note'] as String?,
        );
      default:
        throw ArgumentError('Bilinmeyen timeline türü: $kindName');
    }
  }
}

class PromptDropped {
  const PromptDropped({required this.activityId, required this.reason});

  final String activityId;
  final PromptDropReason reason;

  Map<String, Object?> toJson() => {
        'activityId': activityId,
        'reason': switch (reason) {
          PromptDropReason.noRoute => 'no_route',
          PromptDropReason.windowConflict => 'window_conflict',
          PromptDropReason.duration => 'duration',
          PromptDropReason.redundant => 'redundant',
        },
      };

  static PromptDropped fromJson(Map<String, Object?> json) => PromptDropped(
        activityId: json['activityId']! as String,
        reason: switch (json['reason']! as String) {
          'no_route' => PromptDropReason.noRoute,
          'window_conflict' => PromptDropReason.windowConflict,
          'duration' => PromptDropReason.duration,
          'redundant' => PromptDropReason.redundant,
          final other =>
            throw ArgumentError('Bilinmeyen drop reason: $other'),
        },
      );
}

class PromptMetrics {
  const PromptMetrics({
    required this.totalTransitMinutes,
    required this.totalWalkingMinutes,
    required this.totalTransfers,
    required this.totalYenCost,
    required this.clusterEntries,
    required this.backtracking,
    required this.hasLunch,
    required this.hasDinner,
  });

  final int totalTransitMinutes;
  final int totalWalkingMinutes;
  final int totalTransfers;
  final int totalYenCost;

  /// Farklı cluster'a giriş sayısı (aynı cluster ardışıksa +1 sayılmaz).
  final int clusterEntries;

  /// Section A soft-3'e göre 0/1/2 sınırında bir bayrak. Metric olarak int
  /// tutulur, rubric üzerinde 0 → tam puan.
  final int backtracking;
  final bool hasLunch;
  final bool hasDinner;

  Map<String, Object?> toJson() => {
        'totalTransitMinutes': totalTransitMinutes,
        'totalWalkingMinutes': totalWalkingMinutes,
        'totalTransfers': totalTransfers,
        'totalYenCost': totalYenCost,
        'clusterEntries': clusterEntries,
        'backtracking': backtracking,
        'hasLunch': hasLunch,
        'hasDinner': hasDinner,
      };

  static PromptMetrics fromJson(Map<String, Object?> json) => PromptMetrics(
        totalTransitMinutes: (json['totalTransitMinutes']! as num).toInt(),
        totalWalkingMinutes: (json['totalWalkingMinutes']! as num).toInt(),
        totalTransfers: (json['totalTransfers']! as num).toInt(),
        totalYenCost: (json['totalYenCost']! as num).toInt(),
        clusterEntries: (json['clusterEntries']! as num).toInt(),
        backtracking: (json['backtracking']! as num).toInt(),
        hasLunch: json['hasLunch']! as bool,
        hasDinner: json['hasDinner']! as bool,
      );
}

class RoutePlanOutput {
  const RoutePlanOutput({
    required this.date,
    required this.timeline,
    required this.dropped,
    required this.metrics,
    required this.warnings,
  });

  final String date;
  final List<PromptTimelineEntry> timeline;
  final List<PromptDropped> dropped;
  final PromptMetrics metrics;
  final List<String> warnings;

  Iterable<PromptTimelineEntry> get activities =>
      timeline.where((entry) => entry.kind == PromptTimelineKind.activity);
  Iterable<PromptTimelineEntry> get transits =>
      timeline.where((entry) => entry.kind == PromptTimelineKind.transit);

  Map<String, Object?> toJson() => {
        'date': date,
        'timeline': timeline.map((entry) => entry.toJson()).toList(),
        'dropped': dropped.map((drop) => drop.toJson()).toList(),
        'metrics': metrics.toJson(),
        'warnings': warnings,
      };

  static RoutePlanOutput fromJson(Map<String, Object?> json) => RoutePlanOutput(
        date: json['date']! as String,
        timeline: (json['timeline']! as List)
            .cast<Map<String, Object?>>()
            .map(PromptTimelineEntry.fromJson)
            .toList(),
        dropped: (json['dropped'] as List? ?? const [])
            .cast<Map<String, Object?>>()
            .map(PromptDropped.fromJson)
            .toList(),
        metrics: PromptMetrics.fromJson(
          (json['metrics']! as Map).cast<String, Object?>(),
        ),
        warnings:
            ((json['warnings'] as List?) ?? const []).cast<String>().toList(),
      );

  static RoutePlanOutput decode(String jsonText) =>
      fromJson(json.decode(jsonText) as Map<String, Object?>);
}
