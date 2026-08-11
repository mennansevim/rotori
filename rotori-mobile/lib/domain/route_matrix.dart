/// Rota sağlayıcısından gelen kapıdan kapıya seçeneklerin saf Dart modeli.
///
/// Matris yönlüdür: A → B kaydı, B → A için kullanılamaz. Süre üretmek veya
/// koordinatlardan tahmin yapmak bu katmanın sorumluluğu değildir.
enum TransportMode {
  walking,
  train,
  metro,
  bus,
  taxi,
  shinkansen,
  regionalTrain,
}

enum RouteOptimizationProfile {
  balanced,
  fastest,
  leastWalking,
  cheapest,
}

enum LuggageState { none, carried, checkedAtHotel, forwarded }

enum FareBasis { perPerson, perVehicle, flat }

class TransportCost {
  const TransportCost({
    required this.costPerPersonYen,
    required this.partyTotalCostYen,
    required this.vehicleCount,
    required this.fareBasis,
  });

  final int costPerPersonYen;
  final int partyTotalCostYen;
  final int vehicleCount;
  final FareBasis fareBasis;
}

class TripLocation {
  const TripLocation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.city,
    this.district,
    this.clusterId,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String? city;
  final String? district;
  final String? clusterId;
}

class RoutePreferences {
  const RoutePreferences({
    this.profile = RouteOptimizationProfile.balanced,
    this.maximumWalkingMinutes = 180,
    this.partySize = 1,
    this.luggageState = LuggageState.none,
    bool hasLuggage = false,
  }) : hasLuggage = hasLuggage || luggageState == LuggageState.carried;

  final RouteOptimizationProfile profile;
  final int maximumWalkingMinutes;
  final int partySize;
  final bool hasLuggage;
  final LuggageState luggageState;

  LuggageState get effectiveLuggageState =>
      luggageState == LuggageState.none && hasLuggage
          ? LuggageState.carried
          : luggageState;
}

class TransportOption {
  const TransportOption({
    required this.mode,
    required this.doorToDoorMinutes,
    required this.walkingMinutes,
    required this.waitingMinutes,
    required this.transferCount,
    required this.estimatedCostYen,
    required this.reliabilityScore,
    this.lineId,
    this.directionId,
    this.complexityPenalty = 0,
    this.isEstimated = false,
    this.rideMinutes,
    this.accessMinutes,
    this.transitWaitMinutes,
    this.bufferMinutes = 0,
    this.fareBasis = FareBasis.perPerson,
    this.vehicleCapacity = 4,
    this.providerId,
  });

  final TransportMode mode;
  final int doorToDoorMinutes;
  final int walkingMinutes;
  final int waitingMinutes;
  final int transferCount;
  final int estimatedCostYen;
  final double reliabilityScore;

  /// Aynı hatta ters yön hareketini saptamak için sağlayıcının normalize ettiği
  /// isteğe bağlı değerlerdir. Bilinmiyorsa geri dönüş kararı bunlara dayanmaz.
  final String? lineId;
  final String? directionId;

  /// Büyük istasyon, zor aktarma veya sağlayıcıya özgü karmaşıklık puanı.
  final double complexityPenalty;
  final bool isEstimated;
  final int? rideMinutes;
  final int? accessMinutes;
  final int? transitWaitMinutes;
  final int bufferMinutes;
  final FareBasis fareBasis;
  final int vehicleCapacity;
  final String? providerId;

  /// Saha gerçekliği düzeltmeleri (pass downgrade, trafik çarpanı, istasyon
  /// tamponu) uygulanmış bir kopya üretir. Matris kaydı değişmez; yalnız o
  /// yolculuk için değerlenmiş seçenek türetilir.
  TransportOption copyWith({
    int? doorToDoorMinutes,
    int? walkingMinutes,
    int? waitingMinutes,
    int? transferCount,
    int? estimatedCostYen,
    double? reliabilityScore,
    double? complexityPenalty,
    bool? isEstimated,
    int? rideMinutes,
    int? accessMinutes,
    int? transitWaitMinutes,
    String? lineId,
    String? providerId,
  }) =>
      TransportOption(
        mode: mode,
        doorToDoorMinutes: doorToDoorMinutes ?? this.doorToDoorMinutes,
        walkingMinutes: walkingMinutes ?? this.walkingMinutes,
        waitingMinutes: waitingMinutes ?? this.waitingMinutes,
        transferCount: transferCount ?? this.transferCount,
        estimatedCostYen: estimatedCostYen ?? this.estimatedCostYen,
        reliabilityScore: reliabilityScore ?? this.reliabilityScore,
        lineId: lineId ?? this.lineId,
        directionId: directionId,
        complexityPenalty: complexityPenalty ?? this.complexityPenalty,
        isEstimated: isEstimated ?? this.isEstimated,
        rideMinutes: rideMinutes ?? this.rideMinutes,
        accessMinutes: accessMinutes ?? this.accessMinutes,
        transitWaitMinutes: transitWaitMinutes ?? this.transitWaitMinutes,
        bufferMinutes: bufferMinutes,
        fareBasis: fareBasis,
        vehicleCapacity: vehicleCapacity,
        providerId: providerId ?? this.providerId,
      );

  int get resolvedAccessMinutes => accessMinutes ?? walkingMinutes;
  int get resolvedTransitWaitMinutes => transitWaitMinutes ?? waitingMinutes;
  int get resolvedRideMinutes =>
      rideMinutes ??
      (doorToDoorMinutes -
              resolvedAccessMinutes -
              resolvedTransitWaitMinutes -
              bufferMinutes)
          .clamp(0, doorToDoorMinutes);

  TransportCost costForParty(int partySize) {
    final size = partySize < 1 ? 1 : partySize;
    return switch (fareBasis) {
      FareBasis.perPerson => TransportCost(
          costPerPersonYen: estimatedCostYen,
          partyTotalCostYen: estimatedCostYen * size,
          vehicleCount: 0,
          fareBasis: fareBasis,
        ),
      FareBasis.perVehicle => _vehicleCost(size),
      FareBasis.flat => TransportCost(
          costPerPersonYen: (estimatedCostYen / size).ceil(),
          partyTotalCostYen: estimatedCostYen,
          vehicleCount: 0,
          fareBasis: fareBasis,
        ),
    };
  }

  TransportCost _vehicleCost(int partySize) {
    final capacity = vehicleCapacity < 1 ? 1 : vehicleCapacity;
    final count = (partySize / capacity).ceil();
    final total = estimatedCostYen * count;
    return TransportCost(
      costPerPersonYen: (total / partySize).ceil(),
      partyTotalCostYen: total,
      vehicleCount: count,
      fareBasis: fareBasis,
    );
  }

  bool get isValid =>
      doorToDoorMinutes >= 0 &&
      walkingMinutes >= 0 &&
      waitingMinutes >= 0 &&
      transferCount >= 0 &&
      estimatedCostYen >= 0 &&
      reliabilityScore >= 0 &&
      reliabilityScore <= 1;
}

class RouteMatrixEntry {
  RouteMatrixEntry({
    required this.fromLocationId,
    required this.toLocationId,
    required List<TransportOption> options,
  }) : options = List.unmodifiable(options);

  final String fromLocationId;
  final String toLocationId;
  final List<TransportOption> options;
}

class RouteMatrix {
  RouteMatrix({
    required List<RouteMatrixEntry> entries,
    this.version = 'unknown',
  })  : entries = List.unmodifiable(entries),
        _byDirection = {
          for (final entry in entries)
            _directionKey(entry.fromLocationId, entry.toLocationId): entry,
        };

  final List<RouteMatrixEntry> entries;
  final String version;
  final Map<String, RouteMatrixEntry> _byDirection;

  RouteMatrixEntry? entry(String fromLocationId, String toLocationId) {
    if (fromLocationId == toLocationId) {
      return RouteMatrixEntry(
        fromLocationId: fromLocationId,
        toLocationId: toLocationId,
        options: const [
          TransportOption(
            mode: TransportMode.walking,
            doorToDoorMinutes: 0,
            walkingMinutes: 0,
            waitingMinutes: 0,
            transferCount: 0,
            estimatedCostYen: 0,
            reliabilityScore: 1,
          ),
        ],
      );
    }
    return _byDirection[_directionKey(fromLocationId, toLocationId)];
  }

  List<TransportOption> options(String fromLocationId, String toLocationId) =>
      entry(fromLocationId, toLocationId)?.options ?? const [];

  static String _directionKey(String from, String to) => '$from\u0000$to';
}

abstract interface class RouteMatrixRepository {
  Future<RouteMatrix> getRouteMatrix({
    required List<TripLocation> locations,
    required DateTime day,
    required RoutePreferences preferences,
  });
}

/// Test ve çevrimdışı geliştirme için deterministik repository.
///
/// Verilen matrisi değiştirmeden döndürür ve çağrı bilgilerini kaydeder.
class FakeRouteMatrixRepository implements RouteMatrixRepository {
  FakeRouteMatrixRepository(this.matrix);

  final RouteMatrix matrix;
  int callCount = 0;
  List<String> lastRequestedLocationIds = const [];
  DateTime? lastRequestedDay;
  RoutePreferences? lastRequestedPreferences;

  @override
  Future<RouteMatrix> getRouteMatrix({
    required List<TripLocation> locations,
    required DateTime day,
    required RoutePreferences preferences,
  }) async {
    callCount++;
    lastRequestedLocationIds =
        List.unmodifiable(locations.map((location) => location.id));
    lastRequestedDay = day;
    lastRequestedPreferences = preferences;
    return matrix;
  }
}
