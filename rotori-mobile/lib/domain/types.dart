// TypeScript packages/shared/src/types.ts'in Dart karşılığı.
// Plain Dart sınıfları; JSON'a serileştirilir (Supabase plans.doc jsonb).
// Not: MVP freezed'siz — Faz 3b'de freezed'e geçilecek (data class + copyWith + eşitlik).

import 'plan_field_signals.dart';
import 'route_execution.dart';

// ---------------------------------------------------------------------------
// Enum'lar (TS union type'larının Dart karşılığı — string ↔ enum eşleşmesi)
// ---------------------------------------------------------------------------

/// Plan oluşturulabilecek en uzun gezi süresi (gün).
const int kMaxTripDays = 31;

enum Pace { relaxed, moderate, intense }

enum WalkingTarget { light, moderate, intense }

enum TransportPreference { transit, taxiAssisted, walking, mixed }

enum PaymentPreference { creditCard, cash, creditAndCash, icCard }

enum InterestTag {
  anime,
  pokemon,
  shopping,
  temples,
  traditional,
  tech,
  kids,
  themeParks,
  photography,
  food,
}

enum FoodSensitivity {
  noPork,
  noPorkDerivatives,
  noSeafood,
  halalOnly,
  kidFriendly,
  turkishPalate,
  vegetarian,
  chickenFocus,
  noFattyMeat,
}

enum TicketKind {
  flight,
  train,
  bus,
  ferry,
  attraction,
  event,
  other,
}

enum TimelineItemKind { activity, transport, meal, hotel }

enum ActivityLockType {
  none,
  flight,
  trainReservation,
  hotel,
  ticketedEvent,
  external,
}

/// Walking target → günlük adım üst sınırı eşlemesi.
const Map<WalkingTarget, int> kWalkingTargetSteps = {
  WalkingTarget.light: 7000,
  WalkingTarget.moderate: 11000,
  WalkingTarget.intense: 15000,
};

// ---------------------------------------------------------------------------
// Enum ↔ string dönüşüm yardımcıları (JSON için)
// ---------------------------------------------------------------------------

String _paceToJson(Pace v) => v.name;
Pace? _paceFromJson(dynamic v) => switch (v) {
      'relaxed' => Pace.relaxed,
      'moderate' => Pace.moderate,
      'intense' => Pace.intense,
      _ => null,
    };

String _walkingTargetToJson(WalkingTarget v) => v.name;
WalkingTarget? _walkingTargetFromJson(dynamic v) => switch (v) {
      'light' => WalkingTarget.light,
      'moderate' => WalkingTarget.moderate,
      'intense' => WalkingTarget.intense,
      _ => null,
    };

String _transportPreferenceToJson(TransportPreference v) => switch (v) {
      TransportPreference.taxiAssisted => 'taxi_assisted',
      _ => v.name,
    };
TransportPreference? _transportPreferenceFromJson(dynamic v) => switch (v) {
      'transit' => TransportPreference.transit,
      'taxi_assisted' => TransportPreference.taxiAssisted,
      'walking' => TransportPreference.walking,
      'mixed' => TransportPreference.mixed,
      _ => null,
    };

String _paymentPreferenceToJson(PaymentPreference v) => switch (v) {
      PaymentPreference.creditCard => 'credit_card',
      PaymentPreference.creditAndCash => 'credit_and_cash',
      PaymentPreference.icCard => 'ic_card',
      _ => v.name,
    };
PaymentPreference? _paymentPreferenceFromJson(dynamic v) => switch (v) {
      'credit_card' => PaymentPreference.creditCard,
      'cash' => PaymentPreference.cash,
      'credit_and_cash' => PaymentPreference.creditAndCash,
      'ic_card' => PaymentPreference.icCard,
      _ => null,
    };

String _timelineKindToJson(TimelineItemKind v) => v.name;
TimelineItemKind? _timelineKindFromJson(dynamic v) => switch (v) {
      'activity' => TimelineItemKind.activity,
      'transport' => TimelineItemKind.transport,
      'meal' => TimelineItemKind.meal,
      'hotel' => TimelineItemKind.hotel,
      _ => null,
    };

String _activityLockTypeToJson(ActivityLockType value) => switch (value) {
      ActivityLockType.none => 'none',
      ActivityLockType.flight => 'flight',
      ActivityLockType.trainReservation => 'train_reservation',
      ActivityLockType.hotel => 'hotel',
      ActivityLockType.ticketedEvent => 'ticketed_event',
      ActivityLockType.external => 'external',
    };

ActivityLockType _activityLockTypeFromJson(dynamic value) => switch (value) {
      'flight' => ActivityLockType.flight,
      'train_reservation' => ActivityLockType.trainReservation,
      'hotel' => ActivityLockType.hotel,
      'ticketed_event' => ActivityLockType.ticketedEvent,
      'external' => ActivityLockType.external,
      _ => ActivityLockType.none,
    };

// ---------------------------------------------------------------------------
// Değer sınıfları — hepsi mutable, JSON'a çevrilebilir.
// ---------------------------------------------------------------------------

class ChildProfile {
  ChildProfile({required this.id, required this.age});
  final String id;
  final int age;

  factory ChildProfile.fromJson(Map<String, dynamic> j) =>
      ChildProfile(id: j['id'] as String, age: (j['age'] as num).toInt());

  Map<String, dynamic> toJson() => {'id': id, 'age': age};
}

class FlightLeg {
  FlightLeg(
      {required this.city, required this.airport, required this.dateTime});
  String city;
  String airport;
  String dateTime; // ISO string

  factory FlightLeg.fromJson(Map<String, dynamic> j) => FlightLeg(
        city: (j['city'] as String?) ?? '',
        airport: (j['airport'] as String?) ?? '',
        dateTime: (j['dateTime'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() =>
      {'city': city, 'airport': airport, 'dateTime': dateTime};
}

class HotelStay {
  HotelStay({
    required this.id,
    required this.city,
    required this.name,
    required this.checkIn,
    required this.checkOut,
    required this.address,
    this.addressLocal,
    this.mapsUrl,
    this.phone,
    this.notes,
  });
  final String id;
  String city;
  String name;
  String checkIn;
  String checkOut;
  String address;
  String? addressLocal;
  String? mapsUrl;
  String? phone;
  String? notes;

  factory HotelStay.fromJson(Map<String, dynamic> j) => HotelStay(
        id: j['id'] as String,
        city: (j['city'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        checkIn: (j['checkIn'] as String?) ?? '',
        checkOut: (j['checkOut'] as String?) ?? '',
        address: (j['address'] as String?) ?? '',
        addressLocal: j['addressLocal'] as String? ?? j['addressJa'] as String?,
        mapsUrl: j['mapsUrl'] as String?,
        phone: j['phone'] as String?,
        notes: j['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'city': city,
        'name': name,
        'checkIn': checkIn,
        'checkOut': checkOut,
        'address': address,
        if (addressLocal != null) 'addressLocal': addressLocal,
        if (mapsUrl != null) 'mapsUrl': mapsUrl,
        if (phone != null) 'phone': phone,
        if (notes != null) 'notes': notes,
      };
}

class Ticket {
  Ticket({
    required this.id,
    required this.kind,
    required this.label,
    required this.purchased,
    this.visitDate,
    this.bookingOpens,
    this.url,
    this.emoji,
    this.imageDataUrl,
    this.scannedText,
    this.linkedTransitionDayNumber,
    this.linkedActivityId,
    this.entryTime,
    this.durationMin,
    this.arrivalBufferMin,
  });
  final String id;
  String kind; // TicketKind veya string
  String label;
  String? visitDate;
  String? bookingOpens;
  bool purchased;
  String? url;
  String? emoji;
  String? imageDataUrl;
  String? scannedText;
  int? linkedTransitionDayNumber;
  String? linkedActivityId;
  String? entryTime;
  int? durationMin;
  int? arrivalBufferMin;

  factory Ticket.fromJson(Map<String, dynamic> j) => Ticket(
        id: j['id'] as String,
        kind: (j['kind'] as String?) ?? 'other',
        label: (j['label'] as String?) ?? '',
        visitDate: j['visitDate'] as String?,
        bookingOpens: j['bookingOpens'] as String?,
        purchased: (j['purchased'] as bool?) ?? false,
        url: j['url'] as String?,
        emoji: j['emoji'] as String?,
        imageDataUrl: j['imageDataUrl'] as String?,
        scannedText: j['scannedText'] as String?,
        linkedTransitionDayNumber:
            (j['linkedTransitionDayNumber'] as num?)?.toInt(),
        linkedActivityId: j['linkedActivityId'] as String?,
        entryTime: j['entryTime'] as String?,
        durationMin: (j['durationMin'] as num?)?.toInt(),
        arrivalBufferMin: (j['arrivalBufferMin'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'label': label,
        if (visitDate != null) 'visitDate': visitDate,
        if (bookingOpens != null) 'bookingOpens': bookingOpens,
        'purchased': purchased,
        if (url != null) 'url': url,
        if (emoji != null) 'emoji': emoji,
        if (imageDataUrl != null) 'imageDataUrl': imageDataUrl,
        if (scannedText != null) 'scannedText': scannedText,
        if (linkedTransitionDayNumber != null)
          'linkedTransitionDayNumber': linkedTransitionDayNumber,
        if (linkedActivityId != null) 'linkedActivityId': linkedActivityId,
        if (entryTime != null) 'entryTime': entryTime,
        if (durationMin != null) 'durationMin': durationMin,
        if (arrivalBufferMin != null) 'arrivalBufferMin': arrivalBufferMin,
      };
}

/// Bir şehre varılan günün kullanıcı tarafından seçilmiş ulaşım tercihi.
/// Opsiyoneldir; eski planlar bu alan olmadan açılır.
class CityTransitionPlan {
  const CityTransitionPlan({
    required this.fromCity,
    required this.toCity,
    required this.mode,
    this.linkedTicketId,
    this.railPass,
    this.durationMinutes,
    this.serviceLabel,
    this.options = const [],
    this.luggageStrategy,
  });

  final String fromCity;
  final String toCity;

  /// Seçili mod — `kTransportModes` değerlerinden biri. Timeline satırının,
  /// gün başlığının ve rozetin **tek doğruluk kaynağı**dır.
  final String mode;

  final String? linkedTicketId;

  /// JSON v3 — kullanıcının bileti (`RailPassType.name`). Motor bu satırdan
  /// okur ve Nozomi/Mizuho kısıtını buna göre uygular.
  final String? railPass;

  /// JSON v3 — pass düzeltmesi uygulandıktan sonraki geçiş süresi.
  final int? durationMinutes;

  /// JSON v3 — fiilen kullanılan Shinkansen servisi ("Hikari").
  final String? serviceLabel;

  /// JSON v3 — picker'a sunulan tüm mod seçenekleri. Motor üretir, UI seçer;
  /// böylece seçim ile timeline projeksiyonu ayrışamaz.
  final List<CityTransitionOption> options;

  /// JSON v3 — geçiş günü bagaj stratejisi (`LuggageHandlingStrategy.name`).
  final String? luggageStrategy;

  /// Seçili moda karşılık gelen seçenek; liste boşsa `null`.
  CityTransitionOption? get selectedOption {
    for (final option in options) {
      if (option.mode == mode) return option;
    }
    return null;
  }

  CityTransitionPlan copyWith({
    String? mode,
    String? linkedTicketId,
    String? railPass,
    int? durationMinutes,
    String? serviceLabel,
    List<CityTransitionOption>? options,
    String? luggageStrategy,
  }) {
    return CityTransitionPlan(
      fromCity: fromCity,
      toCity: toCity,
      mode: mode ?? this.mode,
      linkedTicketId: linkedTicketId ?? this.linkedTicketId,
      railPass: railPass ?? this.railPass,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      serviceLabel: serviceLabel ?? this.serviceLabel,
      options: options ?? this.options,
      luggageStrategy: luggageStrategy ?? this.luggageStrategy,
    );
  }

  factory CityTransitionPlan.fromJson(Map<String, dynamic> json) {
    return CityTransitionPlan(
      fromCity: (json['fromCity'] as String?) ?? '',
      toCity: (json['toCity'] as String?) ?? '',
      mode: (json['mode'] as String?) ?? 'train',
      linkedTicketId: json['linkedTicketId'] as String?,
      railPass: json['railPass'] as String?,
      durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
      serviceLabel: json['serviceLabel'] as String?,
      options: json['options'] is List
          ? List.unmodifiable((json['options'] as List)
              .map(CityTransitionOption.tryFromJson)
              .whereType<CityTransitionOption>())
          : const [],
      luggageStrategy: json['luggageStrategy'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'fromCity': fromCity,
        'toCity': toCity,
        'mode': mode,
        if (linkedTicketId != null) 'linkedTicketId': linkedTicketId,
        if (railPass != null) 'railPass': railPass,
        if (durationMinutes != null) 'durationMinutes': durationMinutes,
        if (serviceLabel != null) 'serviceLabel': serviceLabel,
        if (options.isNotEmpty)
          'options': options.map((o) => o.toJson()).toList(),
        if (luggageStrategy != null) 'luggageStrategy': luggageStrategy,
      };
}

class TripDestination {
  TripDestination({
    required this.id,
    required this.countryCode,
    required this.countryName,
    required this.city,
    required this.arrivalDate,
    required this.departureDate,
    required this.order,
    this.airport,
    this.lat,
    this.lng,
    this.airline,
    this.flightNo,
    this.days,
  });
  final String id;
  String countryCode;
  String countryName;
  String city;
  String? airport;
  double? lat;
  double? lng;
  String arrivalDate;
  String departureDate;
  int order;
  String? airline;
  String? flightNo;

  /// Bu şehirde geçirilecek gün sayısı (Plan adımı gün dağılımı yazar).
  /// null = kullanıcı elle belirlemedi → otomatik/eşit dağıtım kullanılır.
  int? days;

  factory TripDestination.fromJson(Map<String, dynamic> j) => TripDestination(
        id: j['id'] as String,
        countryCode: (j['countryCode'] as String?) ?? '',
        countryName: (j['countryName'] as String?) ?? '',
        city: (j['city'] as String?) ?? '',
        airport: j['airport'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        arrivalDate: (j['arrivalDate'] as String?) ?? '',
        departureDate: (j['departureDate'] as String?) ?? '',
        order: ((j['order'] as num?) ?? 0).toInt(),
        airline: j['airline'] as String?,
        flightNo: j['flightNo'] as String?,
        days: (j['days'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'countryCode': countryCode,
        'countryName': countryName,
        'city': city,
        if (airport != null) 'airport': airport,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'arrivalDate': arrivalDate,
        'departureDate': departureDate,
        'order': order,
        if (airline != null) 'airline': airline,
        if (flightNo != null) 'flightNo': flightNo,
        if (days != null) 'days': days,
      };
}

class DestinationFoodPrefs {
  DestinationFoodPrefs({
    required this.destinationId,
    List<String>? dietaryTags,
    List<String>? foodLikes,
    List<String>? foodDislikes,
    this.mealBudgetPerPerson,
    this.mealBudgetCurrency,
  })  : dietaryTags = dietaryTags ?? [],
        foodLikes = foodLikes ?? [],
        foodDislikes = foodDislikes ?? [];

  final String destinationId;
  List<String> dietaryTags;
  List<String> foodLikes;
  List<String> foodDislikes;
  int? mealBudgetPerPerson;
  String? mealBudgetCurrency;

  factory DestinationFoodPrefs.fromJson(Map<String, dynamic> j) =>
      DestinationFoodPrefs(
        destinationId: j['destinationId'] as String,
        dietaryTags: List<String>.from(j['dietaryTags'] as List? ?? const []),
        foodLikes: List<String>.from(j['foodLikes'] as List? ?? const []),
        foodDislikes: List<String>.from(j['foodDislikes'] as List? ?? const []),
        mealBudgetPerPerson: (j['mealBudgetPerPerson'] as num?)?.toInt(),
        mealBudgetCurrency: j['mealBudgetCurrency'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'destinationId': destinationId,
        'dietaryTags': dietaryTags,
        'foodLikes': foodLikes,
        'foodDislikes': foodDislikes,
        if (mealBudgetPerPerson != null)
          'mealBudgetPerPerson': mealBudgetPerPerson,
        if (mealBudgetCurrency != null)
          'mealBudgetCurrency': mealBudgetCurrency,
      };
}

class TravelDates {
  TravelDates({required this.start, required this.end});
  String start; // YYYY-MM-DD
  String end;

  factory TravelDates.fromJson(Map<String, dynamic> j) => TravelDates(
        start: (j['start'] as String?) ?? '',
        end: (j['end'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {'start': start, 'end': end};
}

class PlanAssumptions {
  const PlanAssumptions({
    required this.dateSource,
    required this.flightStatus,
    required this.hotelStatus,
    this.dateRationale,
    this.schemaVersion = currentSchemaVersion,
  });

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String dateSource;
  final String? dateRationale;
  final String flightStatus;
  final String hotelStatus;

  static PlanAssumptions? tryFromJson(Map<String, dynamic> json) {
    final version = (json['schemaVersion'] as num?)?.toInt() ?? 0;
    if (version != currentSchemaVersion) return null;
    return PlanAssumptions(
      schemaVersion: version,
      dateSource: (json['dateSource'] as String?) ?? 'userSelected',
      dateRationale: json['dateRationale'] as String?,
      flightStatus: (json['flightStatus'] as String?) ?? 'draft',
      hotelStatus: (json['hotelStatus'] as String?) ?? 'draft',
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'dateSource': dateSource,
        if (dateRationale != null) 'dateRationale': dateRationale,
        'flightStatus': flightStatus,
        'hotelStatus': hotelStatus,
      };
}

class TripPreferences {
  TripPreferences({
    required this.travelDates,
    required this.pace,
    List<String>? mustSee,
    List<String>? foodLikes,
    List<String>? foodDislikes,
    List<TripDestination>? destinations,
    List<DestinationFoodPrefs>? destinationFood,
    List<String>? dietary,
    List<String>? dietaryTags,
    List<InterestTag>? interests,
    List<FoodSensitivity>? foodSensitivities,
    List<ChildProfile>? childProfiles,
    List<String>? selectedCityIds,
    this.originCity,
    this.originAirport,
    this.originLat,
    this.originLng,
    this.returnAirline,
    this.returnFlightNo,
    this.returnDepartAirport,
    this.returnArrivalAirport,
    this.outboundArrivalTime,
    this.returnDepartTime,
    this.destinationCity,
    this.destinationCountry,
    this.mealBudgetJpyPerPerson,
    this.mealBudgetPerPerson,
    this.mealBudgetCurrency,
    this.planMeals,
    this.maxStepsPerDay,
    this.partySize,
    this.childrenCount,
    this.tripType,
    this.nearbyAirportsOrigin,
    this.nearbyAirportsDest,
    this.directFlightsOnly,
    this.walkingTarget,
    this.transportPreference,
    this.paymentPreference,
    this.hasTicket,
    this.stayArea,
    this.datesEstimated,
    this.planAssumptions,
  })  : mustSee = mustSee ?? [],
        foodLikes = foodLikes ?? [],
        foodDislikes = foodDislikes ?? [],
        destinations = destinations ?? [],
        destinationFood = destinationFood ?? [],
        dietary = dietary ?? [],
        dietaryTags = dietaryTags ?? [],
        interests = interests ?? [],
        foodSensitivities = foodSensitivities ?? [],
        childProfiles = childProfiles ?? [],
        selectedCityIds = selectedCityIds ?? [];

  TravelDates travelDates;
  String? originCity;
  String? originAirport;
  double? originLat;
  double? originLng;
  String? returnAirline;
  String? returnFlightNo;

  /// Dönüş uçuşunda Japonya tarafından kalkış havalimanı IATA.
  String? returnDepartAirport;

  /// Dönüş uçuşunda Türkiye tarafına iniş havalimanı IATA.
  String? returnArrivalAirport;

  /// Gidiş uçuşunun Japonya'ya iniş saati (HH:MM). Varış günü akışı bu
  /// saate göre kurulur (havaalanı → immigration → transfer → check-in).
  String? outboundArrivalTime;

  /// Dönüş uçuşunun Japonya'dan kalkış saati (HH:MM). Ayrılış günü akışı
  /// bu saate göre kurulur (check-out → transfer → havaalanı → uçuş).
  String? returnDepartTime;
  String? destinationCity;
  String? destinationCountry;
  List<TripDestination> destinations;
  List<DestinationFoodPrefs> destinationFood;
  List<String> mustSee;
  List<String> foodLikes;
  List<String> foodDislikes;
  List<String> dietary;
  List<String> dietaryTags;
  int? mealBudgetJpyPerPerson;
  int? mealBudgetPerPerson;
  String? mealBudgetCurrency;
  bool? planMeals;
  int? maxStepsPerDay;
  Pace pace;
  int? partySize;
  int? childrenCount;
  String? tripType; // 'roundtrip' | 'oneway' | 'multicity' — deprecated
  bool? nearbyAirportsOrigin;
  bool? nearbyAirportsDest;
  bool? directFlightsOnly;
  List<String> selectedCityIds;
  WalkingTarget? walkingTarget;
  TransportPreference? transportPreference;
  PaymentPreference? paymentPreference;
  List<ChildProfile> childProfiles;
  List<InterestTag> interests;
  List<FoodSensitivity> foodSensitivities;
  bool? hasTicket;

  /// Konaklanacak bölge/mahalle (opsiyonel) — otel eklenmediğinde taksi/rehber
  /// için serbest metin (örn. "Shinjuku", "Namba istasyon çevresi").
  String? stayArea;

  /// Tarihler kullanıcı tarafından değil, "tarih henüz belli değil" akışında
  /// sezona göre ÖNERİLDİYSE true. UI bunu "tahmini tarih" rozetiyle gösterir.
  bool? datesEstimated;
  PlanAssumptions? planAssumptions;

  factory TripPreferences.fromJson(Map<String, dynamic> j) => TripPreferences(
        travelDates: TravelDates.fromJson(
          (j['travelDates'] as Map?)?.cast<String, dynamic>() ??
              const {'start': '', 'end': ''},
        ),
        pace: _paceFromJson(j['pace']) ?? Pace.moderate,
        mustSee: List<String>.from(j['mustSee'] as List? ?? const []),
        foodLikes: List<String>.from(j['foodLikes'] as List? ?? const []),
        foodDislikes: List<String>.from(j['foodDislikes'] as List? ?? const []),
        destinations: (j['destinations'] as List? ?? const [])
            .map((e) => TripDestination.fromJson((e as Map).cast()))
            .toList(),
        destinationFood: (j['destinationFood'] as List? ?? const [])
            .map((e) => DestinationFoodPrefs.fromJson((e as Map).cast()))
            .toList(),
        dietary: List<String>.from(j['dietary'] as List? ?? const []),
        dietaryTags: List<String>.from(j['dietaryTags'] as List? ?? const []),
        walkingTarget: _walkingTargetFromJson(j['walkingTarget']),
        transportPreference:
            _transportPreferenceFromJson(j['transportPreference']),
        paymentPreference: _paymentPreferenceFromJson(j['paymentPreference']),
        childProfiles: (j['childProfiles'] as List? ?? const [])
            .map((e) => ChildProfile.fromJson((e as Map).cast()))
            .toList(),
        interests: (j['interests'] as List? ?? const [])
            .map(
              (e) => switch (e) {
                'anime' => InterestTag.anime,
                'pokemon' => InterestTag.pokemon,
                'shopping' => InterestTag.shopping,
                'temples' => InterestTag.temples,
                'traditional' => InterestTag.traditional,
                'tech' => InterestTag.tech,
                'kids' => InterestTag.kids,
                'theme_parks' => InterestTag.themeParks,
                'photography' => InterestTag.photography,
                'food' => InterestTag.food,
                _ => null,
              },
            )
            .whereType<InterestTag>()
            .toList(),
        foodSensitivities: (j['foodSensitivities'] as List? ?? const [])
            .map(
              (e) => switch (e) {
                'no_pork' => FoodSensitivity.noPork,
                'no_pork_derivatives' => FoodSensitivity.noPorkDerivatives,
                'no_seafood' => FoodSensitivity.noSeafood,
                'halal_only' => FoodSensitivity.halalOnly,
                'kid_friendly' => FoodSensitivity.kidFriendly,
                'turkish_palate' => FoodSensitivity.turkishPalate,
                'vegetarian' => FoodSensitivity.vegetarian,
                'chicken_focus' => FoodSensitivity.chickenFocus,
                'no_fatty_meat' => FoodSensitivity.noFattyMeat,
                _ => null,
              },
            )
            .whereType<FoodSensitivity>()
            .toList(),
        selectedCityIds:
            List<String>.from(j['selectedCityIds'] as List? ?? const []),
        originCity: j['originCity'] as String?,
        originAirport: j['originAirport'] as String?,
        originLat: (j['originLat'] as num?)?.toDouble(),
        originLng: (j['originLng'] as num?)?.toDouble(),
        returnAirline: j['returnAirline'] as String?,
        returnFlightNo: j['returnFlightNo'] as String?,
        returnDepartAirport: j['returnDepartAirport'] as String?,
        returnArrivalAirport: j['returnArrivalAirport'] as String?,
        outboundArrivalTime: j['outboundArrivalTime'] as String?,
        returnDepartTime: j['returnDepartTime'] as String?,
        destinationCity: j['destinationCity'] as String?,
        destinationCountry: j['destinationCountry'] as String?,
        mealBudgetJpyPerPerson: (j['mealBudgetJpyPerPerson'] as num?)?.toInt(),
        mealBudgetPerPerson: (j['mealBudgetPerPerson'] as num?)?.toInt(),
        mealBudgetCurrency: j['mealBudgetCurrency'] as String?,
        planMeals: j['planMeals'] as bool?,
        maxStepsPerDay: (j['maxStepsPerDay'] as num?)?.toInt(),
        partySize: (j['partySize'] as num?)?.toInt(),
        childrenCount: (j['childrenCount'] as num?)?.toInt(),
        tripType: j['tripType'] as String?,
        nearbyAirportsOrigin: j['nearbyAirportsOrigin'] as bool?,
        nearbyAirportsDest: j['nearbyAirportsDest'] as bool?,
        directFlightsOnly: j['directFlightsOnly'] as bool?,
        hasTicket: j['hasTicket'] as bool?,
        stayArea: j['stayArea'] as String?,
        datesEstimated: j['datesEstimated'] as bool?,
        planAssumptions: j['planAssumptions'] is Map
            ? PlanAssumptions.tryFromJson(
                (j['planAssumptions'] as Map).cast<String, dynamic>(),
              )
            : null,
      );

  Map<String, dynamic> toJson() => {
        'travelDates': travelDates.toJson(),
        'pace': _paceToJson(pace),
        'mustSee': mustSee,
        'foodLikes': foodLikes,
        'foodDislikes': foodDislikes,
        'destinations': destinations.map((d) => d.toJson()).toList(),
        'destinationFood': destinationFood.map((d) => d.toJson()).toList(),
        'dietary': dietary,
        'dietaryTags': dietaryTags,
        'selectedCityIds': selectedCityIds,
        'childProfiles': childProfiles.map((c) => c.toJson()).toList(),
        'interests': interests
            .map(
              (i) => switch (i) {
                InterestTag.themeParks => 'theme_parks',
                _ => i.name,
              },
            )
            .toList(),
        'foodSensitivities': foodSensitivities
            .map(
              (s) => switch (s) {
                FoodSensitivity.noPork => 'no_pork',
                FoodSensitivity.noPorkDerivatives => 'no_pork_derivatives',
                FoodSensitivity.noSeafood => 'no_seafood',
                FoodSensitivity.halalOnly => 'halal_only',
                FoodSensitivity.kidFriendly => 'kid_friendly',
                FoodSensitivity.turkishPalate => 'turkish_palate',
                FoodSensitivity.chickenFocus => 'chicken_focus',
                FoodSensitivity.noFattyMeat => 'no_fatty_meat',
                _ => s.name,
              },
            )
            .toList(),
        if (walkingTarget != null)
          'walkingTarget': _walkingTargetToJson(walkingTarget!),
        if (transportPreference != null)
          'transportPreference':
              _transportPreferenceToJson(transportPreference!),
        if (paymentPreference != null)
          'paymentPreference': _paymentPreferenceToJson(paymentPreference!),
        if (originCity != null) 'originCity': originCity,
        if (originAirport != null) 'originAirport': originAirport,
        if (originLat != null) 'originLat': originLat,
        if (originLng != null) 'originLng': originLng,
        if (returnAirline != null) 'returnAirline': returnAirline,
        if (returnFlightNo != null) 'returnFlightNo': returnFlightNo,
        if (returnDepartAirport != null)
          'returnDepartAirport': returnDepartAirport,
        if (returnArrivalAirport != null)
          'returnArrivalAirport': returnArrivalAirport,
        if (outboundArrivalTime != null)
          'outboundArrivalTime': outboundArrivalTime,
        if (returnDepartTime != null) 'returnDepartTime': returnDepartTime,
        if (destinationCity != null) 'destinationCity': destinationCity,
        if (destinationCountry != null)
          'destinationCountry': destinationCountry,
        if (mealBudgetJpyPerPerson != null)
          'mealBudgetJpyPerPerson': mealBudgetJpyPerPerson,
        if (mealBudgetPerPerson != null)
          'mealBudgetPerPerson': mealBudgetPerPerson,
        if (mealBudgetCurrency != null)
          'mealBudgetCurrency': mealBudgetCurrency,
        if (planMeals != null) 'planMeals': planMeals,
        if (maxStepsPerDay != null) 'maxStepsPerDay': maxStepsPerDay,
        if (partySize != null) 'partySize': partySize,
        if (childrenCount != null) 'childrenCount': childrenCount,
        if (tripType != null) 'tripType': tripType,
        if (nearbyAirportsOrigin != null)
          'nearbyAirportsOrigin': nearbyAirportsOrigin,
        if (nearbyAirportsDest != null)
          'nearbyAirportsDest': nearbyAirportsDest,
        if (directFlightsOnly != null) 'directFlightsOnly': directFlightsOnly,
        if (hasTicket != null) 'hasTicket': hasTicket,
        if (stayArea != null) 'stayArea': stayArea,
        if (datesEstimated != null) 'datesEstimated': datesEstimated,
        if (planAssumptions != null)
          'planAssumptions': planAssumptions!.toJson(),
      };
}

class TimelineItem {
  TimelineItem({
    required this.id,
    required this.title,
    this.placeId,
    this.canonicalPlaceHash,
    this.isCityTransition = false,
    this.transit,
    this.repeat,
    this.closure,
    this.time,
    this.description,
    this.mapUrl,
    this.tips,
    this.kind,
    this.movedFromDay,
    this.lat,
    this.lng,
    this.scheduledTime,
    this.durationMin,
    this.arrivalBufferMin,
    this.cost,
    this.costCurrency,
    this.cityId,
    this.lockType = ActivityLockType.none,
    this.fixedStartTime,
    this.fixedEndTime,
    this.openingTime,
    this.closingTime,
    this.canChangeDay = true,
    this.canChangeTime = true,
    this.canReorder = true,
    this.canDelete = true,
    this.lockReason,
  });

  final String id;
  final String? placeId;

  /// JSON v3 — `PlaceIdentityResolver` tarafından üretilen kararlı kanonik
  /// hash. Kanji/Kana/Romaji varyantları aynı değeri verir. Opsiyoneldir;
  /// yoksa kimlik başlıktan yeniden türetilir.
  final String? canonicalPlaceHash;

  final bool isCityTransition;

  /// JSON v3 — ulaşım satırının saha riski ve pass düzeltmeleri.
  final TransitSignals? transit;

  /// JSON v3 — tekrar politikası (bölge / zaman kotası / kullanıcı iradesi).
  final RepeatSignals? repeat;

  /// JSON v3 — teishukubi kapanış bilgisi ve Holiday Shift izi.
  final ClosureSignals? closure;

  String? time;
  String title;
  String? description;
  String? mapUrl;
  String? tips;
  TimelineItemKind? kind;
  int? movedFromDay;
  double? lat;
  double? lng;
  String? scheduledTime;
  int? durationMin;
  int? arrivalBufferMin;
  int? cost;
  String? costCurrency;
  String? cityId;
  ActivityLockType lockType;
  String? fixedStartTime;
  String? fixedEndTime;
  String? openingTime;
  String? closingTime;
  bool canChangeDay;
  bool canChangeTime;
  bool canReorder;
  bool canDelete;
  String? lockReason;

  bool get isFixed =>
      lockType != ActivityLockType.none ||
      fixedStartTime != null ||
      !canChangeTime ||
      !canReorder;

  /// Tekrar politikası çözümü — v3 alanı yoksa varsayılan `hardZero`.
  bool get allowsRepeat =>
      repeat?.userExplicitSelection == true ||
      repeat?.isRepeatableZone == true ||
      repeat?.policy == 'repeatableZone' ||
      repeat?.policy == 'userOverride' ||
      repeat?.policy == 'timeQuota';

  TimelineItem copyWith({
    String? placeId,
    String? canonicalPlaceHash,
    bool? isCityTransition,
    TransitSignals? transit,
    RepeatSignals? repeat,
    ClosureSignals? closure,
    String? time,
    String? scheduledTime,
    String? title,
    String? description,
    String? tips,
    TimelineItemKind? kind,
    int? durationMin,
    int? arrivalBufferMin,
    int? movedFromDay,
    ActivityLockType? lockType,
    String? fixedStartTime,
    String? fixedEndTime,
    String? openingTime,
    String? closingTime,
    bool? canChangeDay,
    bool? canChangeTime,
    bool? canReorder,
    bool? canDelete,
    String? lockReason,
  }) =>
      TimelineItem(
        id: id,
        placeId: placeId ?? this.placeId,
        canonicalPlaceHash: canonicalPlaceHash ?? this.canonicalPlaceHash,
        isCityTransition: isCityTransition ?? this.isCityTransition,
        transit: transit ?? this.transit,
        repeat: repeat ?? this.repeat,
        closure: closure ?? this.closure,
        title: title ?? this.title,
        time: time ?? this.time,
        description: description ?? this.description,
        mapUrl: mapUrl,
        tips: tips ?? this.tips,
        kind: kind ?? this.kind,
        movedFromDay: movedFromDay ?? this.movedFromDay,
        lat: lat,
        lng: lng,
        scheduledTime: scheduledTime ?? this.scheduledTime,
        durationMin: durationMin ?? this.durationMin,
        arrivalBufferMin: arrivalBufferMin ?? this.arrivalBufferMin,
        cost: cost,
        costCurrency: costCurrency,
        cityId: cityId,
        lockType: lockType ?? this.lockType,
        fixedStartTime: fixedStartTime ?? this.fixedStartTime,
        fixedEndTime: fixedEndTime ?? this.fixedEndTime,
        openingTime: openingTime ?? this.openingTime,
        closingTime: closingTime ?? this.closingTime,
        canChangeDay: canChangeDay ?? this.canChangeDay,
        canChangeTime: canChangeTime ?? this.canChangeTime,
        canReorder: canReorder ?? this.canReorder,
        canDelete: canDelete ?? this.canDelete,
        lockReason: lockReason ?? this.lockReason,
      );

  factory TimelineItem.fromJson(Map<String, dynamic> j) => TimelineItem(
        id: j['id'] as String,
        placeId: j['placeId'] as String?,
        canonicalPlaceHash: j['canonicalPlaceHash'] as String?,
        isCityTransition: (j['isCityTransition'] as bool?) ?? false,
        transit: TransitSignals.tryFromJson(j['transit']),
        repeat: _repeatSignalsFromJson(j),
        closure: ClosureSignals.tryFromJson(j['closure']),
        title: (j['title'] as String?) ?? '',
        time: j['time'] as String?,
        description: j['description'] as String?,
        mapUrl: j['mapUrl'] as String?,
        tips: j['tips'] as String?,
        kind: _timelineKindFromJson(j['kind']),
        movedFromDay: (j['movedFromDay'] as num?)?.toInt(),
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        scheduledTime: j['scheduledTime'] as String?,
        durationMin: (j['durationMin'] as num?)?.toInt(),
        arrivalBufferMin: (j['arrivalBufferMin'] as num?)?.toInt(),
        cost: (j['cost'] as num?)?.toInt(),
        costCurrency: j['costCurrency'] as String?,
        cityId: j['cityId'] as String?,
        lockType: _activityLockTypeFromJson(j['lockType']),
        fixedStartTime: j['fixedStartTime'] as String?,
        fixedEndTime: j['fixedEndTime'] as String?,
        openingTime: j['openingTime'] as String?,
        closingTime: j['closingTime'] as String?,
        canChangeDay: (j['canChangeDay'] as bool?) ?? true,
        canChangeTime: (j['canChangeTime'] as bool?) ?? true,
        canReorder: (j['canReorder'] as bool?) ?? true,
        canDelete: (j['canDelete'] as bool?) ?? true,
        lockReason: j['lockReason'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (placeId != null) 'placeId': placeId,
        if (canonicalPlaceHash != null)
          'canonicalPlaceHash': canonicalPlaceHash,
        if (isCityTransition) 'isCityTransition': true,
        if (transit != null && !transit!.isDefault)
          'transit': transit!.toJson(),
        if (repeat != null && !repeat!.isDefault) 'repeat': repeat!.toJson(),
        if (closure != null && !closure!.isDefault)
          'closure': closure!.toJson(),
        'title': title,
        if (time != null) 'time': time,
        if (description != null) 'description': description,
        if (mapUrl != null) 'mapUrl': mapUrl,
        if (tips != null) 'tips': tips,
        if (kind != null) 'kind': _timelineKindToJson(kind!),
        if (movedFromDay != null) 'movedFromDay': movedFromDay,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (scheduledTime != null) 'scheduledTime': scheduledTime,
        if (durationMin != null) 'durationMin': durationMin,
        if (arrivalBufferMin != null) 'arrivalBufferMin': arrivalBufferMin,
        if (cost != null) 'cost': cost,
        if (costCurrency != null) 'costCurrency': costCurrency,
        if (cityId != null) 'cityId': cityId,
        if (lockType != ActivityLockType.none)
          'lockType': _activityLockTypeToJson(lockType),
        if (fixedStartTime != null) 'fixedStartTime': fixedStartTime,
        if (fixedEndTime != null) 'fixedEndTime': fixedEndTime,
        if (openingTime != null) 'openingTime': openingTime,
        if (closingTime != null) 'closingTime': closingTime,
        if (!canChangeDay) 'canChangeDay': false,
        if (!canChangeTime) 'canChangeTime': false,
        if (!canReorder) 'canReorder': false,
        if (!canDelete) 'canDelete': false,
        if (lockReason != null) 'lockReason': lockReason,
      };
}

/// v2 dokümanları tekrar iznini düz `repeatAllowed` bayrağıyla taşıyordu.
/// v3 iç nesnesi yoksa bu bayrak `userOverride` politikasına yükseltilir —
/// eski planlarda tema parkı / çok günlü bilet davranışı korunur.
RepeatSignals? _repeatSignalsFromJson(Map<String, dynamic> j) {
  final nested = RepeatSignals.tryFromJson(j['repeat']);
  if (nested != null && !nested.isDefault) return nested;
  final legacy = j['repeatAllowed'] as bool?;
  if (legacy == true) {
    return const RepeatSignals(
      policy: 'userOverride',
      userExplicitSelection: true,
    );
  }
  return nested;
}

class DayHighlight {
  DayHighlight({required this.title, required this.body});
  final String title;
  final String body;

  factory DayHighlight.fromJson(Map<String, dynamic> j) =>
      DayHighlight(title: j['title'] as String, body: j['body'] as String);

  Map<String, dynamic> toJson() => {'title': title, 'body': body};
}

class DayPlan {
  DayPlan({
    required this.dayNumber,
    required this.date,
    required this.theme,
    List<String>? tags,
    List<TimelineItem>? items,
    List<DayHighlight>? highlights,
    this.weekday,
    this.stepsEstimate,
    this.stepsEstimateMax,
    this.taxiRecommended,
    this.routeMapsUrl,
    this.routeExecutionSnapshot,
    this.cityTransition,
    this.luggage,
    this.crowd,
  })  : tags = tags ?? [],
        items = items ?? [],
        highlights = highlights ?? [];

  int dayNumber;
  String date;
  String? weekday;
  String theme;
  List<String> tags;
  int? stepsEstimate;
  int? stepsEstimateMax;
  bool? taxiRecommended;
  String? routeMapsUrl;
  RouteExecutionSnapshot? routeExecutionSnapshot;
  CityTransitionPlan? cityTransition;

  /// JSON v3 — o günün bagaj stratejisi (Coin Locker / Hotel Drop / Yamato).
  LuggageSignals? luggage;

  /// JSON v3 — sezonluk yoğunluk çarpanları (Golden Week, Sakura…).
  CrowdSignals? crowd;

  List<TimelineItem> items;
  List<DayHighlight> highlights;

  /// TS'teki `{ ...day, ... }` spread'inin karşılığı — yeni DayPlan üretir.
  /// Not: null'a sıfırlama yapılamaz (?? deseni); mevcut kullanım için yeterli.
  DayPlan copyWith({
    String? theme,
    List<String>? tags,
    List<TimelineItem>? items,
    List<DayHighlight>? highlights,
    int? stepsEstimate,
    int? stepsEstimateMax,
    bool? taxiRecommended,
    RouteExecutionSnapshot? routeExecutionSnapshot,
    CityTransitionPlan? cityTransition,
    LuggageSignals? luggage,
    CrowdSignals? crowd,
  }) =>
      DayPlan(
        dayNumber: dayNumber,
        date: date,
        theme: theme ?? this.theme,
        weekday: weekday,
        tags: tags ?? this.tags,
        stepsEstimate: stepsEstimate ?? this.stepsEstimate,
        stepsEstimateMax: stepsEstimateMax ?? this.stepsEstimateMax,
        taxiRecommended: taxiRecommended ?? this.taxiRecommended,
        routeMapsUrl: routeMapsUrl,
        // Aktivite listesi değiştiğinde eski bacaklar artık güvenilir değildir.
        // Yeni snapshot yalnız optimizasyon onay akışı tarafından açıkça verilir.
        routeExecutionSnapshot: routeExecutionSnapshot ??
            (items == null ? this.routeExecutionSnapshot : null),
        cityTransition: cityTransition ?? this.cityTransition,
        luggage: luggage ?? this.luggage,
        crowd: crowd ?? this.crowd,
        items: items ?? this.items,
        highlights: highlights ?? this.highlights,
      );

  factory DayPlan.fromJson(Map<String, dynamic> j) => DayPlan(
        dayNumber: (j['dayNumber'] as num).toInt(),
        date: (j['date'] as String?) ?? '',
        theme: (j['theme'] as String?) ?? '',
        weekday: j['weekday'] as String?,
        tags: List<String>.from(j['tags'] as List? ?? const []),
        stepsEstimate: (j['stepsEstimate'] as num?)?.toInt(),
        stepsEstimateMax: (j['stepsEstimateMax'] as num?)?.toInt(),
        taxiRecommended: j['taxiRecommended'] as bool?,
        routeMapsUrl: ((j['route'] as Map?)?['mapsUrl'] as String?),
        routeExecutionSnapshot: j['routeExecution'] is Map
            ? RouteExecutionSnapshot.tryFromJson(
                (j['routeExecution'] as Map).cast<String, dynamic>(),
              )
            : null,
        cityTransition: j['cityTransition'] is Map
            ? CityTransitionPlan.fromJson(
                (j['cityTransition'] as Map).cast<String, dynamic>(),
              )
            : null,
        luggage: LuggageSignals.tryFromJson(j['luggage']),
        crowd: CrowdSignals.tryFromJson(j['crowd']),
        items: (j['items'] as List? ?? const [])
            .map((e) => TimelineItem.fromJson((e as Map).cast()))
            .toList(),
        highlights: (j['highlights'] as List? ?? const [])
            .map((e) => DayHighlight.fromJson((e as Map).cast()))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'dayNumber': dayNumber,
        'date': date,
        'theme': theme,
        'tags': tags,
        'items': items.map((i) => i.toJson()).toList(),
        if (weekday != null) 'weekday': weekday,
        if (stepsEstimate != null) 'stepsEstimate': stepsEstimate,
        if (stepsEstimateMax != null) 'stepsEstimateMax': stepsEstimateMax,
        if (taxiRecommended != null) 'taxiRecommended': taxiRecommended,
        if (routeMapsUrl != null) 'route': {'mapsUrl': routeMapsUrl},
        if (routeExecutionSnapshot != null)
          'routeExecution': routeExecutionSnapshot!.toJson(),
        if (cityTransition != null) 'cityTransition': cityTransition!.toJson(),
        if (luggage != null) 'luggage': luggage!.toJson(),
        if (crowd != null && !crowd!.isDefault) 'crowd': crowd!.toJson(),
        if (highlights.isNotEmpty)
          'highlights': highlights.map((h) => h.toJson()).toList(),
      };
}

class TripFlights {
  TripFlights({
    List<FlightLeg>? outbound,
    List<FlightLeg>? returnLegs,
    List<FlightLeg>? legs,
  })  : outbound = outbound ?? [],
        returnLegs = returnLegs ?? [],
        legs = legs ?? [];

  /// Kalkış (outbound) — Türkiye → Japonya (birden fazla aktarma bacağı olabilir).
  List<FlightLeg> outbound;

  /// Dönüş — Japonya → Türkiye. TS'te `return` idi (rezerve kelime),
  /// Dart'ta `returnLegs`; JSON key aynı: `return`.
  List<FlightLeg> returnLegs;

  /// Tam rota (opsiyonel): kalkış → duraklar → eve dönüş.
  List<FlightLeg> legs;

  factory TripFlights.fromJson(Map<String, dynamic> j) => TripFlights(
        outbound: (j['outbound'] as List? ?? const [])
            .map((e) => FlightLeg.fromJson((e as Map).cast()))
            .toList(),
        returnLegs: (j['return'] as List? ?? const [])
            .map((e) => FlightLeg.fromJson((e as Map).cast()))
            .toList(),
        legs: (j['legs'] as List? ?? const [])
            .map((e) => FlightLeg.fromJson((e as Map).cast()))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'outbound': outbound.map((f) => f.toJson()).toList(),
        'return': returnLegs.map((f) => f.toJson()).toList(),
        if (legs.isNotEmpty) 'legs': legs.map((f) => f.toJson()).toList(),
      };
}

class Deadlines {
  Deadlines(
      {this.shinkansenBooking, this.skytreeVisit, this.skytreeBookingOpens});
  String? shinkansenBooking;
  String? skytreeVisit;
  String? skytreeBookingOpens;

  factory Deadlines.fromJson(Map<String, dynamic> j) => Deadlines(
        shinkansenBooking: j['shinkansenBooking'] as String?,
        skytreeVisit: j['skytreeVisit'] as String?,
        skytreeBookingOpens: j['skytreeBookingOpens'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (shinkansenBooking != null) 'shinkansenBooking': shinkansenBooking,
        if (skytreeVisit != null) 'skytreeVisit': skytreeVisit,
        if (skytreeBookingOpens != null)
          'skytreeBookingOpens': skytreeBookingOpens,
      };
}

class Trip {
  Trip({
    required this.id,
    required this.slug,
    required this.title,
    required this.timezone,
    required this.tripStart,
    required this.tripEnd,
    required this.flights,
    required this.preferences,
    List<HotelStay>? hotels,
    List<Ticket>? tickets,
    List<DayPlan>? days,
    this.subtitle,
    this.deadlines,
  })  : hotels = hotels ?? [],
        tickets = tickets ?? [],
        days = days ?? [];

  final String id;
  final String slug;
  String title;
  String? subtitle;
  String timezone;
  String tripStart;
  String tripEnd;
  TripFlights flights;
  List<HotelStay> hotels;
  List<Ticket> tickets;
  TripPreferences preferences;
  List<DayPlan> days;
  Deadlines? deadlines;

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: j['id'] as String,
        slug: j['slug'] as String,
        title: (j['title'] as String?) ?? '',
        subtitle: j['subtitle'] as String?,
        timezone: (j['timezone'] as String?) ?? 'Asia/Tokyo',
        tripStart: (j['tripStart'] as String?) ?? '',
        tripEnd: (j['tripEnd'] as String?) ?? '',
        flights: TripFlights.fromJson(
          (j['flights'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        preferences: TripPreferences.fromJson(
          (j['preferences'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        hotels: (j['hotels'] as List? ?? const [])
            .map((e) => HotelStay.fromJson((e as Map).cast()))
            .toList(),
        tickets: (j['tickets'] as List? ?? const [])
            .map((e) => Ticket.fromJson((e as Map).cast()))
            .toList(),
        days: (j['days'] as List? ?? const [])
            .map((e) => DayPlan.fromJson((e as Map).cast()))
            .toList(),
        deadlines: j['deadlines'] == null
            ? null
            : Deadlines.fromJson((j['deadlines'] as Map).cast()),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'slug': slug,
        'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        'timezone': timezone,
        'tripStart': tripStart,
        'tripEnd': tripEnd,
        'flights': flights.toJson(),
        'hotels': hotels.map((h) => h.toJson()).toList(),
        'tickets': tickets.map((t) => t.toJson()).toList(),
        'preferences': preferences.toJson(),
        'days': days.map((d) => d.toJson()).toList(),
        if (deadlines != null) 'deadlines': deadlines!.toJson(),
      };
}
