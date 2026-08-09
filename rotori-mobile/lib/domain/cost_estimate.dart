// Yıl bazlı, AI KULLANMAYAN maliyet tahmincisi. Japonya için kalem kalem
// (uçak, otel, yemek, tren, taksi, alışveriş, elektronik, gezi) min–max
// tahmini üretir. Birim maliyetler bir INI tablosundan (assets/data/
// unit_costs.ini) okunur — kullanıcı arka planda düzenleyebilir; tablo
// yüklenemezse gömülü [defaults] devreye girer.
//
// Saf Dart: Flutter import etmez (test edilebilir). Değerler JPY cinsindendir;
// TL'ye çeviri çağıran katmanda (bütçe ekranı) yapılır.

import 'dart:math' as math;

import 'types.dart';

/// Tahmini gider kategorileri (kullanıcının istediği kalemler).
enum CostCategory {
  flight,
  hotel,
  food,
  train,
  taxi,
  shopping,
  electronics,
  attractions,
}

/// Tek bir kategori için min–max JPY tahmini.
class CostLine {
  const CostLine({
    required this.category,
    required this.minJpy,
    required this.maxJpy,
  });

  final CostCategory category;
  final int minJpy;
  final int maxJpy;
}

/// Örnek birim fiyat (ör. bir ramen, Tokyo–Kyoto shinkansen). Tablodan okunur.
class ReferencePrice {
  const ReferencePrice(this.key, this.jpy);
  final String key;
  final int jpy;
}

/// Kalem kalem tahmin sonucu + kullanılan varsayımlar.
class CostEstimate {
  const CostEstimate({
    required this.lines,
    required this.totalMinJpy,
    required this.totalMaxJpy,
    required this.adults,
    required this.children,
    required this.days,
    required this.nights,
    required this.cityCount,
    required this.month,
    required this.oneWay,
    required this.year,
    required this.references,
  });

  final List<CostLine> lines;
  final int totalMinJpy;
  final int totalMaxJpy;
  final int adults;
  final int children;
  final int days;
  final int nights;
  final int cityCount;

  /// Gidiş ayı (1–12); 0 = bilinmiyor.
  final int month;
  final bool oneWay;
  final int year;
  final List<ReferencePrice> references;

  int get party => adults + children;
}

/// Birim maliyet tablosu — INI'den okunur, tümü JPY (aksi belirtilmedikçe).
class UnitCostTable {
  const UnitCostTable({
    required this.year,
    required this.flightAdultMin,
    required this.flightAdultMax,
    required this.flightChildMin,
    required this.flightChildMax,
    required this.flightOnewayFactor,
    required this.hotelNightMin,
    required this.hotelNightMax,
    required this.hotelExtraMin,
    required this.hotelExtraMax,
    required this.foodAdultMin,
    required this.foodAdultMax,
    required this.foodChildMin,
    required this.foodChildMax,
    required this.trainLocalDayMin,
    required this.trainLocalDayMax,
    required this.trainIntercityMin,
    required this.trainIntercityMax,
    required this.trainChildFactor,
    required this.taxiDayMin,
    required this.taxiDayMax,
    required this.shoppingAdultMin,
    required this.shoppingAdultMax,
    required this.shoppingChildMin,
    required this.shoppingChildMax,
    required this.electronicsGroupMin,
    required this.electronicsGroupMax,
    required this.attractionsAdultMin,
    required this.attractionsAdultMax,
    required this.attractionsChildMin,
    required this.attractionsChildMax,
    required this.highMonths,
    required this.highFactor,
    required this.defaultFactor,
    required this.references,
  });

  final int year;

  // Uçak — kişi başı gidiş-dönüş (TR<->JP, ekonomi).
  final int flightAdultMin;
  final int flightAdultMax;
  final int flightChildMin;
  final int flightChildMax;
  final double flightOnewayFactor;

  // Otel — oda/gece (2 kişilik taban) + ek kişi/gece.
  final int hotelNightMin;
  final int hotelNightMax;
  final int hotelExtraMin;
  final int hotelExtraMax;

  // Yemek — kişi başı/gün.
  final int foodAdultMin;
  final int foodAdultMax;
  final int foodChildMin;
  final int foodChildMax;

  // Tren — kişi başı taban (yerel) + şehirlerarası bacak başına.
  /// Şehir İÇİ ulaşım — GÜN BAŞINA. Eskiden gezi başına sabitti: 3 günlük
  /// gezi de 14 günlük gezi de aynı yerel ulaşım maliyetini alıyordu.
  /// Referans: metro bileti ¥210, günlük pass ¥800.
  final int trainLocalDayMin;
  final int trainLocalDayMax;

  /// Şehirlerarası BACAK BAŞINA. Referans: Tokyo–Kyoto Nozomi (rezerve)
  /// ¥14.170; Green Car ~¥19.000.
  final int trainIntercityMin;
  final int trainIntercityMax;
  final double trainChildFactor;


  // Taksi — grup/gün.
  final int taxiDayMin;
  final int taxiDayMax;

  // Alışveriş — kişi başı, tüm gezi.
  final int shoppingAdultMin;
  final int shoppingAdultMax;
  final int shoppingChildMin;
  final int shoppingChildMax;

  // Elektronik — grup toplam, tüm gezi (opsiyonel harcama).
  final int electronicsGroupMin;
  final int electronicsGroupMax;

  // Gezi/giriş — kişi başı/gün.
  final int attractionsAdultMin;
  final int attractionsAdultMax;
  final int attractionsChildMin;
  final int attractionsChildMax;

  // Mevsim çarpanı (otel + uçak).
  final Set<int> highMonths;
  final double highFactor;
  final double defaultFactor;

  final List<ReferencePrice> references;

  /// Gömülü varsayılan tablo — 2026 için gerçekçi Japonya ortalamaları (JPY).
  /// INI yüklenemezse veya bir alan eksikse taban değer budur.
  factory UnitCostTable.defaults() => const UnitCostTable(
        year: 2026,
        flightAdultMin: 95000,
        flightAdultMax: 175000,
        flightChildMin: 80000,
        flightChildMax: 150000,
        flightOnewayFactor: 0.62,
        hotelNightMin: 9000,
        hotelNightMax: 22000,
        hotelExtraMin: 2500,
        hotelExtraMax: 6000,
        foodAdultMin: 3000,
        foodAdultMax: 8000,
        foodChildMin: 1500,
        foodChildMax: 4500,
        trainLocalDayMin: 600,
        trainLocalDayMax: 1500,
        trainIntercityMin: 9000,
        trainIntercityMax: 15000,
        trainChildFactor: 0.5,
        taxiDayMin: 1200,
        taxiDayMax: 5000,
        shoppingAdultMin: 8000,
        shoppingAdultMax: 40000,
        shoppingChildMin: 4000,
        shoppingChildMax: 15000,
        electronicsGroupMin: 0,
        electronicsGroupMax: 60000,
        attractionsAdultMin: 1200,
        attractionsAdultMax: 4500,
        attractionsChildMin: 700,
        attractionsChildMax: 3000,
        highMonths: {3, 4, 5, 10, 11},
        highFactor: 1.15,
        defaultFactor: 1.0,
        references: [
          ReferencePrice('ramen', 1100),
          ReferencePrice('sushi_set', 2500),
          ReferencePrice('konbini_meal', 650),
          ReferencePrice('coffee', 500),
          ReferencePrice('subway_ride', 210),
          ReferencePrice('taxi_start', 500),
          ReferencePrice('shinkansen_tokyo_kyoto', 14170),
          ReferencePrice('hotel_night_family', 16000),
          ReferencePrice('day_pass', 800),
          ReferencePrice('museum', 1500),
        ],
      );

  /// INI metnini ayrıştırır; gömülü [defaults] üstüne yalnız var olan alanları
  /// yazar (kısmi/hatalı tablo güvenli düşer).
  factory UnitCostTable.parseIni(String text) =>
      UnitCostTable.fromSections(_parseSections(text));

  /// `section → {key: value}` haritasından tablo kurar (INI ve Supabase ortak
  /// yolu). Gömülü [defaults] üstüne yalnız var olan alanları yazar.
  factory UnitCostTable.fromSections(Map<String, Map<String, String>> map) {
    final d = UnitCostTable.defaults();

    int gi(String sec, String key, int fb) =>
        int.tryParse((map[sec]?[key] ?? '').trim()) ?? fb;
    double gd(String sec, String key, double fb) =>
        double.tryParse((map[sec]?[key] ?? '').trim().replaceAll(',', '.')) ??
        fb;

    Set<int> highMonths = d.highMonths;
    final rawMonths = map['season']?['high_months'];
    if (rawMonths != null && rawMonths.trim().isNotEmpty) {
      final parsed = <int>{};
      for (final part in rawMonths.split(',')) {
        final m = int.tryParse(part.trim());
        if (m != null && m >= 1 && m <= 12) parsed.add(m);
      }
      if (parsed.isNotEmpty) highMonths = parsed;
    }

    final refs = <ReferencePrice>[];
    final refSec = map['reference'];
    if (refSec != null) {
      refSec.forEach((k, v) {
        final j = int.tryParse(v.trim());
        if (j != null) refs.add(ReferencePrice(k, j));
      });
    }

    return UnitCostTable(
      year: gi('meta', 'year', d.year),
      flightAdultMin: gi('flight', 'adult_min', d.flightAdultMin),
      flightAdultMax: gi('flight', 'adult_max', d.flightAdultMax),
      flightChildMin: gi('flight', 'child_min', d.flightChildMin),
      flightChildMax: gi('flight', 'child_max', d.flightChildMax),
      flightOnewayFactor:
          gd('flight', 'oneway_factor', d.flightOnewayFactor),
      hotelNightMin: gi('hotel', 'night_min', d.hotelNightMin),
      hotelNightMax: gi('hotel', 'night_max', d.hotelNightMax),
      hotelExtraMin: gi('hotel', 'extra_person_min', d.hotelExtraMin),
      hotelExtraMax: gi('hotel', 'extra_person_max', d.hotelExtraMax),
      foodAdultMin: gi('food', 'adult_min', d.foodAdultMin),
      foodAdultMax: gi('food', 'adult_max', d.foodAdultMax),
      foodChildMin: gi('food', 'child_min', d.foodChildMin),
      foodChildMax: gi('food', 'child_max', d.foodChildMax),
      trainLocalDayMin: gi('train', 'local_day_min', d.trainLocalDayMin),
      trainLocalDayMax: gi('train', 'local_day_max', d.trainLocalDayMax),
      trainIntercityMin: gi('train', 'intercity_min', d.trainIntercityMin),
      trainIntercityMax: gi('train', 'intercity_max', d.trainIntercityMax),
      trainChildFactor: gd('train', 'child_factor', d.trainChildFactor),
      taxiDayMin: gi('taxi', 'day_min', d.taxiDayMin),
      taxiDayMax: gi('taxi', 'day_max', d.taxiDayMax),
      shoppingAdultMin: gi('shopping', 'adult_min', d.shoppingAdultMin),
      shoppingAdultMax: gi('shopping', 'adult_max', d.shoppingAdultMax),
      shoppingChildMin: gi('shopping', 'child_min', d.shoppingChildMin),
      shoppingChildMax: gi('shopping', 'child_max', d.shoppingChildMax),
      electronicsGroupMin:
          gi('electronics', 'group_min', d.electronicsGroupMin),
      electronicsGroupMax:
          gi('electronics', 'group_max', d.electronicsGroupMax),
      attractionsAdultMin:
          gi('attractions', 'adult_min', d.attractionsAdultMin),
      attractionsAdultMax:
          gi('attractions', 'adult_max', d.attractionsAdultMax),
      attractionsChildMin:
          gi('attractions', 'child_min', d.attractionsChildMin),
      attractionsChildMax:
          gi('attractions', 'child_max', d.attractionsChildMax),
      highMonths: highMonths,
      highFactor: gd('season', 'high_factor', d.highFactor),
      defaultFactor: gd('season', 'default_factor', d.defaultFactor),
      references: refs.isEmpty ? d.references : refs,
    );
  }
}

/// Basit INI ayrıştırıcı: `[section]` başlıkları + `key=value`; `;`/`#` yorum.
Map<String, Map<String, String>> _parseSections(String text) {
  final out = <String, Map<String, String>>{};
  var current = '';
  for (final rawLine in text.split('\n')) {
    var line = rawLine.trim();
    if (line.isEmpty) continue;
    if (line.startsWith(';') || line.startsWith('#')) continue;
    // Satır içi yorumu at (değerden sonra ; ...).
    final semi = line.indexOf(';');
    if (semi > 0) line = line.substring(0, semi).trim();
    if (line.startsWith('[') && line.endsWith(']')) {
      current = line.substring(1, line.length - 1).trim().toLowerCase();
      out.putIfAbsent(current, () => {});
      continue;
    }
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final key = line.substring(0, eq).trim().toLowerCase();
    final value = line.substring(eq + 1).trim();
    out.putIfAbsent(current, () => {})[key] = value;
  }
  return out;
}

/// Gidiş ayını 'YYYY-MM-DD' biçiminden çeker (0 = bilinmiyor).
int _monthOf(String date) {
  final parts = date.split('-');
  if (parts.length >= 2) {
    final m = int.tryParse(parts[1]);
    if (m != null && m >= 1 && m <= 12) return m;
  }
  return 0;
}

/// İki 'YYYY-MM-DD' arasındaki gün sayısı (dahil); ayrıştırılamazsa 0.
int _daysBetween(String start, String end) {
  try {
    final a = DateTime.parse(start);
    final b = DateTime.parse(end);
    final diff = b.difference(a).inDays;
    return diff >= 0 ? diff + 1 : 0;
  } catch (_) {
    return 0;
  }
}

/// [trip] için birim tablodan kalem kalem min–max JPY tahmini üretir.
CostEstimate estimateTripCost(Trip trip, UnitCostTable table) {
  final prefs = trip.preferences;

  final party = math.max(1, prefs.partySize ?? 1);
  var children = (prefs.childrenCount ?? 0);
  if (children < 0) children = 0;
  if (children >= party) children = party - 1;
  final adults = math.max(1, party - children);

  var days = trip.days.length;
  if (days == 0) days = _daysBetween(prefs.travelDates.start, prefs.travelDates.end);
  days = math.max(1, days);
  final nights = math.max(1, days - 1);

  final cities = prefs.selectedCityIds.isNotEmpty
      ? prefs.selectedCityIds.length
      : (prefs.destinations.isNotEmpty ? prefs.destinations.length : 1);
  final cityCount = math.max(1, cities);
  final intercityLegs = math.max(0, cityCount - 1);

  final month = _monthOf(prefs.travelDates.start);
  final seasonFactor =
      table.highMonths.contains(month) ? table.highFactor : table.defaultFactor;

  final oneWay = trip.flights.returnLegs.isEmpty ||
      (prefs.tripType?.toLowerCase().trim() == 'oneway');
  final flightFactor = oneWay ? table.flightOnewayFactor : 1.0;
  final extraPersons = math.max(0, party - 2);

  int r(double v) => v.round();

  // Uçak — kişi başı, mevsim + gidiş/dönüş çarpanı.
  final flightMin = r((adults * table.flightAdultMin +
          children * table.flightChildMin) *
      flightFactor *
      seasonFactor);
  final flightMax = r((adults * table.flightAdultMax +
          children * table.flightChildMax) *
      flightFactor *
      seasonFactor);

  // Otel — oda/gece × gece × mevsim.
  final hotelMin = r((table.hotelNightMin + table.hotelExtraMin * extraPersons) *
      nights *
      seasonFactor);
  final hotelMax = r((table.hotelNightMax + table.hotelExtraMax * extraPersons) *
      nights *
      seasonFactor);

  // Yemek — kişi başı × gün.
  final foodMin =
      (adults * table.foodAdultMin + children * table.foodChildMin) * days;
  final foodMax =
      (adults * table.foodAdultMax + children * table.foodChildMax) * days;

  // Tren — GÜNLÜK yerel ulaşım + şehirlerarası bacaklar; çocuk indirimi.
  //
  // JR Pass HESABA KATILMAZ. 2023 zammından sonra (7 gün ¥50.000) tipik
  // Tokyo–Kyoto–Osaka rotalarında noktadan noktaya bilet daha ucuz; pass
  // varsayımı tahmini şişiriyordu.
  final trainAdultMinRaw =
      table.trainLocalDayMin * days + table.trainIntercityMin * intercityLegs;
  final trainAdultMaxRaw =
      table.trainLocalDayMax * days + table.trainIntercityMax * intercityLegs;
  final trainAdultMin = trainAdultMinRaw;
  final trainAdultMax = trainAdultMaxRaw;
  final trainMin = r(adults * trainAdultMin +
      children * trainAdultMin * table.trainChildFactor);
  final trainMax = r(adults * trainAdultMax +
      children * trainAdultMax * table.trainChildFactor);

  // Taksi — grup × gün.
  final taxiMin = table.taxiDayMin * days;
  final taxiMax = table.taxiDayMax * days;

  // Alışveriş — kişi başı, tüm gezi.
  final shoppingMin =
      adults * table.shoppingAdultMin + children * table.shoppingChildMin;
  final shoppingMax =
      adults * table.shoppingAdultMax + children * table.shoppingChildMax;

  // Elektronik — grup toplam.
  final electronicsMin = table.electronicsGroupMin;
  final electronicsMax = table.electronicsGroupMax;

  // Gezi/giriş — kişi başı × gün.
  final attractionsMin =
      (adults * table.attractionsAdultMin + children * table.attractionsChildMin) *
          days;
  final attractionsMax =
      (adults * table.attractionsAdultMax + children * table.attractionsChildMax) *
          days;

  final lines = <CostLine>[
    CostLine(category: CostCategory.flight, minJpy: flightMin, maxJpy: flightMax),
    CostLine(category: CostCategory.hotel, minJpy: hotelMin, maxJpy: hotelMax),
    CostLine(category: CostCategory.food, minJpy: foodMin, maxJpy: foodMax),
    CostLine(category: CostCategory.train, minJpy: trainMin, maxJpy: trainMax),
    CostLine(category: CostCategory.taxi, minJpy: taxiMin, maxJpy: taxiMax),
    CostLine(
        category: CostCategory.shopping, minJpy: shoppingMin, maxJpy: shoppingMax),
    CostLine(
        category: CostCategory.electronics,
        minJpy: electronicsMin,
        maxJpy: electronicsMax),
    CostLine(
        category: CostCategory.attractions,
        minJpy: attractionsMin,
        maxJpy: attractionsMax),
  ];

  var totalMin = 0;
  var totalMax = 0;
  for (final l in lines) {
    totalMin += l.minJpy;
    totalMax += l.maxJpy;
  }

  return CostEstimate(
    lines: lines,
    totalMinJpy: totalMin,
    totalMaxJpy: totalMax,
    adults: adults,
    children: children,
    days: days,
    nights: nights,
    cityCount: cityCount,
    month: month,
    oneWay: oneWay,
    year: table.year,
    references: table.references,
  );
}
