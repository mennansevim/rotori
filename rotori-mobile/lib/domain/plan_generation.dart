// Plan üretiminin TEK doğru merkezi.
//
// Hem yeni 2 adımlı oluşturma akışı (features/plans/create/) hem de mevcut
// planner Plan adımı buradan geçer. Amaç: "şehir + tarih" girdisinden dolu bir
// gezi planı üretmek. Origin, uçuş, otel, must-see hiçbiri ZORUNLU DEĞİLDİR —
// motor bunlar olmadan da çalışır.
//
// Bu dosya SAF'tır: Flutter widget importu yoktur, yalnızca domain + AppLang.

import '../core/l10n.dart' show AppLang;
import 'activity_identity.dart';
import 'city_places.dart';
import 'city_transfers.dart';
import 'destination_profiles.dart';
import 'fill_empty_days.dart';
import 'itinerary_generator.dart';
import 'japan_seasonality.dart';
import 'japan_suggestions.dart' show isTimedEntryTitle, kJapanDayTemplates;
import 'trip_factory.dart';
import 'types.dart';

// ---------------------------------------------------------------------------
// Tarih yardımcıları (trip_factory'deki private eşlenikleriyle aynı biçim)
// ---------------------------------------------------------------------------

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// [start] ve [end] DAHİL gün sayısı. Geçersiz girdide 0.
int inclusiveDays(String start, String end) {
  final s = DateTime.tryParse(start);
  final e = DateTime.tryParse(end);
  if (s == null || e == null || e.isBefore(s)) return 0;
  return e.difference(s).inDays + 1;
}

// ---------------------------------------------------------------------------
// Destinasyon kurulumu
// ---------------------------------------------------------------------------

/// [cityKeys] (kCityData.key) → sıralı TripDestination listesi.
///
/// İki kural pazarlık dışıdır:
///  • `countryCode` DAİMA 'JP' — kDestinationProfiles yalnızca JP içeriyor,
///    başka kod verilirse getDestinationProfile null döner ve o günler BOŞ kalır.
///  • `city` DAİMA kCityData.label — itinerary_generator'ın içerik havuzu
///    (_cityPool) şehri bu isimle arıyor.
///
/// Gün dağılımı KÖR EŞİT BÖLME değildir — [_cityContentWeight] ile şehrin
/// içerik derinliğine (gün şablonu / gezilecek yer sayısı) orantılı pay
/// verilir (bkz. [_weightedDaySplit]). Şehir sayısı gün sayısını aşarsa
/// (bilinen sınır, UI üretim öncesi bunu engeller) eski kör-eşit
/// [distributeDates]'e düşülür — o durumda ağırlıklı payın min-1 garantisi
/// sağlanamaz.
/// [dayOverrides]: kullanıcı 2. ekranda gün sayısını elle ayarladıysa
/// şehirKey → gün. Verilen değerler aynen uygulanır (toplamı gün sayısına
/// eşit olmalı); verilmeyen şehirler ağırlıklı paylarını alır.
List<TripDestination> buildDestinations({
  required List<String> cityKeys,
  required String startYmd,
  required String endYmd,
  Map<String, int>? dayOverrides,
}) {
  final dests = <TripDestination>[];
  final matchedKeys = <String>[];
  for (final key in cityKeys) {
    final data = kCityData.where((c) => c.key == key).toList();
    if (data.isEmpty) continue; // bilinmeyen anahtar sessizce atlanır
    final c = data.first;
    final coords = _cityCenter(c);
    dests.add(TripDestination(
      id: newDestinationId(),
      countryCode: 'JP',
      countryName: 'Japonya',
      city: c.label,
      lat: coords?.$1,
      lng: coords?.$2,
      arrivalDate: startYmd,
      departureDate: endYmd,
      order: dests.length,
    ));
    matchedKeys.add(key);
  }

  final total = inclusiveDays(startYmd, endYmd);
  if (dests.isNotEmpty && total >= dests.length) {
    _applyWeightedDayBlocks(
      dests,
      matchedKeys,
      startYmd,
      total,
      dayOverrides: dayOverrides,
    );
  } else {
    distributeDates(dests, startYmd, endYmd);
  }
  return dests;
}

/// Şehir başına önerilen gün sayısı — 2. ekrandaki stepper'ların BAŞLANGIÇ
/// değeri. Kullanıcı buradan artırıp azaltır; [buildDestinations]'a
/// `dayOverrides` olarak geri verilir.
Map<String, int> suggestedDaySplit(
  List<String> cityKeys,
  String startYmd,
  String endYmd,
) {
  final total = inclusiveDays(startYmd, endYmd);
  final keys = cityKeys
      .where((k) => kCityData.any((c) => c.key == k))
      .toList(growable: false);
  if (keys.isEmpty || total < keys.length) return const {};
  final days = _weightedDaySplit(keys.map(_cityContentWeight).toList(), total);
  return {for (var i = 0; i < keys.length; i++) keys[i]: days[i]};
}

/// Bir şehrin "içerik kapasitesi": kaç GÜN dolduracak kadar küratörlü
/// materyali var. Önce gün şablonu sayısı (varsa — Tokyo 4, Osaka 2, Kyoto/
/// Nara 1); şablonu olmayan şehirlerde (Hiroshima, Sapporo, Kanazawa)
/// gezilecek yer sayısından türetilir (~3 yer/gün).
///
/// Sonuca +1 TABAN eklenir: ham oran (Tokyo 4 : Kyoto 1) çok keskin — 7
/// günlük bir gezide Kyoto'yu tek güne (yalnızca "ayrılış" günü) düşürüyor,
/// yani kullanıcının seçtiği ikinci şehir pratikte hiç gezilmemiş oluyor.
/// Taban, her şehre içerik farkı ne olursa olsun makul bir pay garanti eder
/// (Tokyo 5 : Kyoto 2 — hâlâ Tokyo'ya ağırlık ama Kyoto görülebilir kalır).
int _cityContentWeight(String cityKey) {
  final data = kCityData.where((c) => c.key == cityKey).toList();
  if (data.isEmpty) return 2;
  final label = data.first.label;
  final templateCount = kJapanDayTemplates
      .where((t) => t.city.toLowerCase() == label.toLowerCase())
      .length;
  if (templateCount > 0) return 1 + templateCount;
  final placeCount = data.first.places.length;
  final derived = placeCount <= 0 ? 0 : (placeCount / 3).round();
  return 1 + derived.clamp(0, 1 << 30);
}

/// Ağırlıklara göre [totalDays]'i dağıtır — en büyük kalan yöntemi. Her
/// eleman en az 1 gün alır (çağıran `cityKeys.length <= totalDays` garanti
/// etmeli). Toplam DAİMA [totalDays]'e eşittir.
List<int> _weightedDaySplit(List<int> weights, int totalDays) {
  final n = weights.length;
  if (n == 0) return const [];
  final sumW = weights.fold<int>(0, (a, b) => a + b);
  final raw = [for (final w in weights) totalDays * w / sumW];
  final days = [for (final r in raw) r.floor()];
  for (var i = 0; i < n; i++) {
    if (days[i] < 1) days[i] = 1;
  }

  var diff = totalDays - days.fold<int>(0, (a, b) => a + b);
  if (diff > 0) {
    // En büyük kesirli kalana sırayla ekle (klasik "largest remainder").
    final order = List<int>.generate(n, (i) => i)
      ..sort((a, b) =>
          (raw[b] - raw[b].floor()).compareTo(raw[a] - raw[a].floor()));
    var i = 0;
    while (diff > 0) {
      days[order[i % n]] += 1;
      diff--;
      i++;
    }
  } else if (diff < 0) {
    // min-1 garantisi toplamı aştıysa en büyükten azalt (1'in altına inmez).
    final order = List<int>.generate(n, (i) => i)
      ..sort((a, b) => days[b].compareTo(days[a]));
    var i = 0;
    var guard = 0;
    while (diff < 0 && guard < n * totalDays + 10) {
      final idx = order[i % n];
      if (days[idx] > 1) {
        days[idx] -= 1;
        diff++;
      }
      i++;
      guard++;
    }
  }
  return days;
}

/// [buildDestinations]'ın içerik-ağırlıklı gün ataması. Ardışık tarih
/// blokları üretir (assignDayBlocks'taki "elle belirlenmiş" dal ile aynı
/// biçim) — distributeDates'in aksine şehir başına pay eşit DEĞİLDİR.
void _applyWeightedDayBlocks(
  List<TripDestination> dests,
  List<String> matchedKeys,
  String startYmd,
  int totalDays, {
  Map<String, int>? dayOverrides,
}) {
  List<int> days;
  final override = dayOverrides;
  if (override != null &&
      matchedKeys.every((k) => (override[k] ?? 0) > 0) &&
      matchedKeys.fold<int>(0, (n, k) => n + override[k]!) == totalDays) {
    // Kullanıcı gün dağılımını elle ayarladı — aynen uygula.
    days = matchedKeys.map((k) => override[k]!).toList();
  } else {
    days = _weightedDaySplit(
      matchedKeys.map(_cityContentWeight).toList(),
      totalDays,
    );
  }

  final startDt = DateTime.parse(startYmd);
  var cursor = 0;
  for (var i = 0; i < dests.length; i++) {
    final isLast = i == dests.length - 1;
    dests[i]
      ..arrivalDate = _ymd(startDt.add(Duration(days: cursor)))
      ..order = i;
    var depOffset = cursor + days[i] - 1;
    if (isLast || depOffset > totalDays - 1) depOffset = totalDays - 1;
    dests[i].departureDate = _ymd(startDt.add(Duration(days: depOffset)));
    cursor = depOffset + 1;
  }
}

/// Şehir merkezi ≈ o şehrin noktalarının ortalaması. Rota/harita için yeterli.
(double, double)? _cityCenter(CityData c) {
  if (c.places.isEmpty) return null;
  var lat = 0.0, lng = 0.0;
  for (final p in c.places) {
    lat += p.lat;
    lng += p.lng;
  }
  return (lat / c.places.length, lng / c.places.length);
}

// ---------------------------------------------------------------------------
// Gün blokları
// ---------------------------------------------------------------------------

/// Şehirlere gün blokları atar ve [t.days] iskeletini yeniden üretir.
///
/// İki mod:
///  • Kullanıcı her şehrin gün sayısını elle belirlediyse (TÜM dest.days dolu
///    ve toplamları toplam güne eşit) → ardışık tarih blokları.
///  • Aksi halde coverage-guard: bir şehir hiçbir güne düşmüyorsa
///    distributeDates ile yeniden dağıtılır.
///
/// Kaynak: plan_step._generate() (eski satır 453-503).
void assignDayBlocks(Trip t) {
  final start = t.preferences.travelDates.start;
  final end = t.preferences.travelDates.end;
  final total = inclusiveDays(start, end);
  final dests = [...t.preferences.destinations]
    ..sort((a, b) => a.order.compareTo(b.order));
  if (dests.isEmpty || start.isEmpty) return;

  final allSet = dests.every((d) => (d.days ?? 0) > 0);
  final sumDays = dests.fold<int>(0, (n, d) => n + (d.days ?? 0));

  if (allSet && total > 0 && sumDays == total) {
    for (var i = 0; i < dests.length; i++) {
      dests[i].order = i;
    }
    final startDt = DateTime.parse(start);
    var cursor = 0;
    for (var i = 0; i < dests.length; i++) {
      final d = dests[i];
      final isLast = i == dests.length - 1;
      d.arrivalDate = _ymd(startDt.add(Duration(days: cursor)));
      var depOffset = cursor + d.days! - 1;
      if (isLast || depOffset > total - 1) depOffset = total - 1;
      d.departureDate = _ymd(startDt.add(Duration(days: depOffset)));
      cursor = depOffset + 1;
    }
    t.preferences.destinations = dests;
    t.days = generateDaysBetween(start, end);
    return;
  }

  if (dests.length >= 2 && end.isNotEmpty) {
    final covered = <String>{};
    for (final d in t.days) {
      final dd = getDestinationForDate(dests, d.date);
      if (dd != null) covered.add(dd.id);
    }
    if (!dests.every((d) => covered.contains(d.id))) {
      for (var i = 0; i < dests.length; i++) {
        dests[i].order = i;
      }
      distributeDates(dests, start, end);
      t.preferences.destinations = dests;
      t.days = generateDaysBetween(start, end);
    }
  }
}

/// Kural tabanlı gün doldurma: aktiviteler + öğünler + şehirler arası transfer.
///
/// Kaynak: plan_step._generate() (eski satır 505-534). Oradaki elle yazılmış
/// detectCityTransitions döngüsü [applyCityTransitions] ile birebir aynı işi
/// yapıyordu; burada tek çağrıya indirildi.
void fillTripDays(Trip t, {AppLang lang = AppLang.tr}) {
  final dests = [...t.preferences.destinations]
    ..sort((a, b) => a.order.compareTo(b.order));
  final generated = removeConsecutiveActivityDuplicates(
    generateItineraryFromTrip(t, lang: lang),
  );
  var days = fillEmptyDays(generated, dests, lang: lang);
  days = removeConsecutiveActivityDuplicates(days);
  // Alias güvenlik ağı bir günü seyrelttiyse aynı katalog kurallarıyla normal
  // bir alternatif doldur; ikinci geçiş de önceki gün kimliğini gözetir.
  days = fillEmptyDays(days, dests, lang: lang);
  days = removeConsecutiveActivityDuplicates(days);
  days = applyCityTransitions(days, dests, lang: lang);
  lockTimedEntries(days);
  t.days = days;
}

/// Saatli giriş öğelerini (teamLab, Disneyland, USJ) kilitler.
///
/// **Why burada:** Bu yerler ÜÇ ayrı yoldan gelebiliyor — gün şablonu,
/// yer havuzu (`_buildFromPlaces`) ve `fillEmptyDays`. Kilidi her üreticiye
/// ayrı ayrı eklemek er geç birini atlamak demek; tek huni olan
/// [fillTripDays] çıkışında normalize etmek garanti veriyor.
///
/// Kilit, rota optimizasyonunun (hava durumuna göre yeniden dizme dahil) bu
/// öğelerin saatini/gününü değiştirmesini engeller — bilet belirli bir saate
/// kesildiği için oynatmak onu geçersiz kılar.
void lockTimedEntries(List<DayPlan> days) {
  for (final day in days) {
    for (final item in day.items) {
      if (!isTimedEntryTitle(item.title)) continue;
      if (item.lockType == ActivityLockType.none) {
        item.lockType = ActivityLockType.ticketedEvent;
      }
      item
        ..canChangeTime = false
        ..canChangeDay = false;
    }
  }
}

// ---------------------------------------------------------------------------
// Sıfırdan plan
// ---------------------------------------------------------------------------

/// Şehir anahtarları + tarih aralığından TAM bir Trip üretir.
///
/// Yeni oluşturma akışının tek çağrısı. Senkron ve hızlı (~10-50 ms) —
/// yapay gecikme EKLENMEZ.
Trip buildTripFromCities({
  required List<String> cityKeys,
  required String startYmd,
  required String endYmd,
  Map<String, int>? dayOverrides,
  AppLang lang = AppLang.tr,
  String? originCity,
  String? originAirport,
  double? originLat,
  double? originLng,
  bool datesEstimated = false,
}) {
  var trip = createEmptyTrip();
  final dests = buildDestinations(
    cityKeys: cityKeys,
    startYmd: startYmd,
    endYmd: endYmd,
    dayOverrides: dayOverrides,
  );
  trip = syncTripFromDestinations(
    trip,
    originCity: originCity ?? '',
    originAirport: originAirport,
    originLat: originLat,
    originLng: originLng,
    destinations: dests,
    destinationFood: dests.map(defaultFoodPrefsForDestination).toList(),
    travelStart: startYmd,
    travelEnd: endYmd,
  );
  trip.preferences
    ..selectedCityIds = [...cityKeys]
    ..hasTicket = false
    ..datesEstimated = datesEstimated;
  fillTripDays(trip, lang: lang);
  return ensureTripPreferences(trip);
}

// ---------------------------------------------------------------------------
// Önizleme
// ---------------------------------------------------------------------------

/// Bir şehre kaç gün düştüğü — oluşturma akışının 2. ekranındaki önizleme.
class CityNights {
  const CityNights({
    required this.cityKey,
    required this.label,
    required this.emoji,
    required this.days,
  });
  final String cityKey;
  final String label;
  final String emoji;
  final int days;
}

/// Gün dağılımı önizlemesi.
///
/// ÖNEMLİ: Naif `departureDate - arrivalDate` farkı KULLANILMAZ. distributeDates
/// bitişik dilimlerde `dest[i].departureDate == dest[i+1].arrivalDate` üretir ve
/// [getDestinationForDate] çakışan günü sırada ÖNCE gelen şehre verir. Önizleme
/// gerçek üretimle aynı fonksiyonu kullanmazsa yalan söyler.
List<CityNights> previewCityDistribution(
  List<String> cityKeys,
  String startYmd,
  String endYmd, {
  Map<String, int>? dayOverrides,
}) {
  final dests = buildDestinations(
    cityKeys: cityKeys,
    startYmd: startYmd,
    endYmd: endYmd,
    dayOverrides: dayOverrides,
  );
  if (dests.isEmpty) return const [];
  final days = generateDaysBetween(startYmd, endYmd);
  final counts = <String, int>{};
  for (final d in days) {
    final dd = getDestinationForDate(dests, d.date);
    if (dd != null) counts[dd.id] = (counts[dd.id] ?? 0) + 1;
  }
  final out = <CityNights>[];
  for (var i = 0; i < dests.length; i++) {
    final d = dests[i];
    final key = i < cityKeys.length ? cityKeys[i] : '';
    final data = kCityData.where((c) => c.key == key).toList();
    out.add(CityNights(
      cityKey: key,
      label: d.city,
      emoji: data.isEmpty ? '📍' : data.first.emoji,
      days: counts[d.id] ?? 0,
    ));
  }
  return out;
}

/// "Tarih henüz belli değil" akıllı varsayılanı.
///
/// Şehir başına ~3 gün hedefler (5-14 gece aralığına kırpılır) ve
/// [kSuggestedRanges] içindeki gelecekteki ilk İYİ sezonun başlangıcını seçer.
/// Uygun sezon kalmadıysa bugünden 90 gün sonrasına düşer.
({String start, String end}) suggestDateRange({
  required int cityCount,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final nights = (cityCount * 3).clamp(5, 14);

  DateTime? start;
  for (final r in kSuggestedRanges) {
    if (r.tone != SeasonTone.good) continue;
    final s = DateTime.tryParse(r.startISO);
    if (s != null && s.isAfter(today)) {
      start = s;
      break;
    }
  }
  start ??= today.add(const Duration(days: 90));
  final end = start.add(Duration(days: nights));
  return (start: _ymd(start), end: _ymd(end));
}

// ---------------------------------------------------------------------------
// Uçuş bilgisi
// ---------------------------------------------------------------------------

/// Trip'te GERÇEK uçuş bilgisi var mı?
///
/// `outbound.isNotEmpty` YETMEZ: createEmptyTrip() city/airport'u boş 2 bacak
/// üretiyor, syncTripFromDestinations da buildRouteLegs ile boş şehirli bacak
/// üretebiliyor. Bu yüzden şehir VE havaalanı dolu bir bacak aranır.
bool tripHasFlightInfo(Trip t) => [
      ...t.flights.outbound,
      ...t.flights.returnLegs,
      ...t.flights.legs,
    ].any((l) => l.city.trim().isNotEmpty && l.airport.trim().isNotEmpty);
