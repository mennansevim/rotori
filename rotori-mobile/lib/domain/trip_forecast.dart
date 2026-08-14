/// Rota günü ↔ şehir ↔ hava tahmini eşleştirmesi.
///
/// Bir gezi çok şehirli olduğunda "hava durumu" tek bir yerin tahmini değildir:
/// 3. gün Tokyo, 5. gün Kyoto olabilir. Bu katman, planın gün listesini
/// destinasyon takvimiyle kesiştirip her güne **o gün bulunulan şehrin**
/// tahminini bağlar.
///
/// Katman **saf**tır: ağa çıkmaz, `DateTime.now()` okumaz. Tahminleri kim
/// getirirse getirsin (viewer'ın rozetleri veya hava ekranı) aynı fonksiyondan
/// geçer — böylece iki yüzey birbirinden sapamaz.
library;

import '../data/weather_service.dart';
import 'destination_profiles.dart';
import 'types.dart';

/// Rotanın bir gününün hava özeti.
class RouteDayForecast {
  const RouteDayForecast({
    required this.dayNumber,
    required this.date,
    required this.city,
    this.forecast,
    this.isCityChange = false,
  });

  final int dayNumber;

  /// ISO `yyyy-MM-dd`.
  final String date;

  /// O gün bulunulan şehir. Destinasyon çözülemezse boş.
  final String city;

  /// O şehrin o günkü tahmini. Veri yoksa (ağ hatası, ufuk dışı tarih) `null`.
  final DayForecast? forecast;

  /// Bu gün bir önceki güne göre şehir değişiyor mu? Listede ayraç göstermek
  /// için — "Kyoto'ya geçiş" satırı.
  final bool isCityChange;

  bool get hasForecast => forecast != null;
}

/// Tahminin **karar vermeye yetecek kadar** kesin sayıldığı ufuk (gün).
///
/// Open-Meteo 16 gün veri döndürür ama 7 günün ötesinde günlük kod/sıcaklık
/// tahminleri rota değiştirmeyi haklı çıkaracak kadar güvenilir değildir.
/// Kullanıcıya "havaya göre optimize et" demek, ancak tahmin tutacaksa
/// dürüsttür.
const int kForecastActionableHorizonDays = 7;

/// Bu tarih için hava tahminine dayanarak rota değişikliği önerilebilir mi?
///
/// Geçmiş günler `false` döner — olan havaya göre planı değiştirmek anlamsız.
/// [today] enjekte edilir; katman saf kalır ve test determinist olur.
bool isForecastActionable({
  required String dateIso,
  required DateTime today,
  int horizonDays = kForecastActionableHorizonDays,
}) {
  final parsed = DateTime.tryParse(dateIso);
  if (parsed == null) return false;
  final day = DateTime(parsed.year, parsed.month, parsed.day);
  final base = DateTime(today.year, today.month, today.day);
  final delta = day.difference(base).inDays;
  return delta >= 0 && delta <= horizonDays;
}

/// Aynı koordinatı iki kez çekmemek için destinasyonları tekilleştirir.
///
/// Dönen liste `TripDestination` sırasını korur; koordinatı olmayan
/// destinasyonlar elenir (tahmin çekilemez).
List<TripDestination> distinctForecastDestinations(
  List<TripDestination> destinations,
) {
  final sorted = [...destinations]..sort((a, b) => a.order.compareTo(b.order));
  final seen = <String>{};
  final out = <TripDestination>[];
  for (final d in sorted) {
    final lat = d.lat, lng = d.lng;
    if (lat == null || lng == null) continue;
    if (!seen.add('$lat,$lng')) continue;
    out.add(d);
  }
  return List.unmodifiable(out);
}

/// Gün listesini, destinasyon takvimini ve destinasyon başına çekilmiş
/// tahminleri birleştirir.
///
/// [forecastsByDestinationId] anahtarı `TripDestination.id`'dir. Bir gün için
/// tahmin yalnız **o günün destinasyonundan** okunur; böylece Kyoto gününe
/// Tokyo tahmini düşmez.
List<RouteDayForecast> buildRouteForecast({
  required List<DayPlan> days,
  required List<TripDestination> destinations,
  required Map<String, List<DayForecast>> forecastsByDestinationId,
}) {
  final sortedDays = [...days]..sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
  final out = <RouteDayForecast>[];
  String? previousCity;

  for (final day in sortedDays) {
    final dest = getDestinationForDate(destinations, day.date);
    final city = dest?.city ?? '';

    DayForecast? match;
    if (dest != null) {
      final list = forecastsByDestinationId[dest.id];
      if (list != null) {
        for (final f in list) {
          if (f.date == day.date) {
            match = f;
            break;
          }
        }
      }
    }

    out.add(RouteDayForecast(
      dayNumber: day.dayNumber,
      date: day.date,
      city: city,
      forecast: match,
      isCityChange:
          previousCity != null && city.isNotEmpty && city != previousCity,
    ));
    if (city.isNotEmpty) previousCity = city;
  }
  return List.unmodifiable(out);
}

/// `days` henüz üretilmemişse gün listesini gezi tarih aralığından türetir.
///
/// Ekranın rota-farkındalığını korur: her tarih için şehir yine destinasyon
/// takviminden çözülür. Aralık geçersizse boş liste döner.
List<RouteDayForecast> buildRouteForecastFromDateRange({
  required String startIso,
  required String endIso,
  required List<TripDestination> destinations,
  required Map<String, List<DayForecast>> forecastsByDestinationId,
}) {
  final start = DateTime.tryParse(startIso);
  final end = DateTime.tryParse(endIso);
  if (start == null || end == null || end.isBefore(start)) return const [];

  // Aşırı uzun aralıkta ekranı kilitlememek için üst sınır.
  const maximumDays = 40;
  final days = <DayPlan>[];
  var cursor = DateTime(start.year, start.month, start.day);
  final last = DateTime(end.year, end.month, end.day);
  var number = 1;
  while (!cursor.isAfter(last) && number <= maximumDays) {
    days.add(DayPlan(
      dayNumber: number,
      date: _isoDate(cursor),
      theme: '',
    ));
    cursor = cursor.add(const Duration(days: 1));
    number++;
  }
  return buildRouteForecast(
    days: days,
    destinations: destinations,
    forecastsByDestinationId: forecastsByDestinationId,
  );
}

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// Aynı şehirde geçen **ardışık** günlerin bloğu.
///
/// Ardışıklık bilinçli: Tokyo → Kyoto → Tokyo rotasında Tokyo iki ayrı blok
/// olarak görünür. Tek blokta birleştirmek, aradaki Kyoto günlerini gizleyip
/// takvimi yanlış anlatırdı.
class RouteCitySegment {
  RouteCitySegment({required this.city, required List<RouteDayForecast> days})
      : days = List.unmodifiable(days);

  final String city;
  final List<RouteDayForecast> days;

  String get startDate => days.first.date;
  String get endDate => days.last.date;
  int get dayCount => days.length;

  /// Blokta en az bir günün tahmini var mı?
  bool get hasAnyForecast => days.any((d) => d.hasForecast);
}

/// Gün satırlarını şehir başlıklarına göre gruplar.
///
/// Şehri çözülemeyen günler (destinasyon takvimi dışında) boş `city` ile kendi
/// bloğunda toplanır; sunum katmanı bunlara başlık basmamayı seçebilir.
List<RouteCitySegment> groupRouteForecastByCity(List<RouteDayForecast> rows) {
  final out = <RouteCitySegment>[];
  var buffer = <RouteDayForecast>[];
  String? current;

  void flush() {
    if (buffer.isEmpty) return;
    out.add(RouteCitySegment(city: current ?? '', days: buffer));
    buffer = <RouteDayForecast>[];
  }

  for (final row in rows) {
    if (current == null || row.city != current) {
      flush();
      current = row.city;
    }
    buffer.add(row);
  }
  flush();
  return List.unmodifiable(out);
}

/// Viewer'ın gün rozetleri için `date → forecast` haritası.
///
/// [buildRouteForecast] ile **aynı** eşleştirmeden türer; rozet ile hava
/// ekranının farklı şey göstermesi bu sayede yapısal olarak imkânsızdır.
Map<String, DayForecast> routeForecastByDate(List<RouteDayForecast> rows) => {
      for (final row in rows)
        if (row.forecast != null) row.date: row.forecast!,
    };
