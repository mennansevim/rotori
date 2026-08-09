// "Bunları da gör" — planın şehirlerinden henüz plana girmemiş öneriler.
//
// Eski wizard'da gezilecek yer seçimi Rota adımındaydı ve seçim plan
// ÜRETİMİNE girdi oluyordu. Yeni akışta plan 2 soruyla hazır geliyor; bu
// dosya aynı işlevi plan HAZIR OLDUKTAN SONRA sunar.
//
// Kritik fark: yerleştirme YENİDEN ÜRETİM DEĞİLDİR. Kullanıcının elle yaptığı
// düzenlemeler (taşınan, silinen, saati değiştirilen öğeler) korunmalı, o
// yüzden seçilen yer mevcut günlerdeki BOŞLUĞA yerleştirilir.

import 'city_places.dart';
import 'destination_profiles.dart' show getDestinationForDate;
import 'itinerary_generator.dart'
    show kDayEndMinutes, kDayStartMinutes, kDefaultActivityMinutes;
import 'japan_suggestions.dart';
import 'place_coords.dart' show resolvePlaceCoords;
import 'trip_factory.dart';
import 'types.dart';

/// Ardışık iki öğe arasında bırakılan en az geçiş süresi (dk).
const int _kTransitionMinutes = 15;

/// Yerleştirme denemesinde saat ızgarası adımı (dk).
const int _kSlotStep = 15;

/// Kısa ziyaret alt sınırı (dk). Üretilen planlar 09:00-20:00 arasını
/// neredeyse tamamen dolduruyor; tam süre (90 dk) sığmadığında yeri
/// reddetmek yerine daha kısa bir duraklama olarak sıkıştırırız — kullanıcı
/// zaten o yeri İSTEDİ. Bunun da altına inmeyiz, yoksa "5 dakikalık Gion"
/// gibi anlamsız kalemler çıkar.
const int _kMinVisitMinutes = 45;

String _cleanCity(String city) =>
    city.replaceAll(RegExp(r'\s*\(.*\)\s*$'), '').trim();

int? _toMin(String? t) {
  if (t == null || !t.contains(':')) return null;
  final p = t.split(':');
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

String _toHhmm(int min) => '${(min ~/ 60).toString().padLeft(2, '0')}:'
    '${(min % 60).toString().padLeft(2, '0')}';

int _durationOf(TimelineItem i) =>
    i.durationMin ?? (i.kind == TimelineItemKind.meal ? 45 : 90);

/// Bu yer plandaki herhangi bir günde zaten var mı?
bool _alreadyInPlan(Trip trip, PlaceSuggestion p) {
  final name = p.name.toLowerCase();
  for (final d in trip.days) {
    for (final i in d.items) {
      if (i.title.toLowerCase().contains(name)) return true;
    }
  }
  return false;
}

/// Planın şehirlerinden, plana HENÜZ girmemiş öneri yerler.
///
/// Havuz: `kJapanPopular` + `city_places.dart` — ikisi de yalnızca planın
/// destinasyon şehirleriyle sınırlanır (Kyoto planına Sapporo önerilmez).
/// Sıralama: küratörlü puan (yoksa kategoriye göre nötr), sonra isim —
/// böylece aynı plan için liste KARARLI kalır.
List<PlaceSuggestion> missingHighlights(Trip trip, {int limit = 12}) {
  final cities = <String>{
    for (final d in trip.preferences.destinations)
      if (d.city.trim().isNotEmpty) _cleanCity(d.city).toLowerCase(),
  };
  if (cities.isEmpty) return const [];

  final pool = <String, PlaceSuggestion>{};

  void add(PlaceSuggestion p) {
    if (!cities.contains(_cleanCity(p.city).toLowerCase())) return;
    pool.putIfAbsent(p.name.toLowerCase(), () => p);
  }

  for (final p in kJapanPopular) {
    add(p);
  }
  // city_places.dart kayıtları PlaceSuggestion değil — dönüştür.
  for (final c in kCityData) {
    if (!cities.contains(c.label.toLowerCase())) continue;
    for (final cp in c.places) {
      add(PlaceSuggestion(
        id: 'cp-${cp.name.toLowerCase().replaceAll(' ', '-')}',
        name: cp.name,
        city: c.label,
        emoji: cp.emoji,
        category: 'fun',
        typicalSteps: 9000,
      ));
    }
  }

  final out = pool.values.where((p) => !_alreadyInPlan(trip, p)).toList()
    ..sort((a, b) {
      final ra = a.rating ?? 0;
      final rb = b.rating ?? 0;
      if (ra != rb) return rb.compareTo(ra);
      return a.name.compareTo(b.name);
    });

  return out.length <= limit ? out : out.sublist(0, limit);
}

/// [addHighlightsToPlan] sonucu.
class HighlightPlacement {
  const HighlightPlacement({required this.placed, required this.unplaced});

  /// Plana yerleştirilen yerler → hangi gün numarasına.
  final Map<String, int> placed;

  /// Gün doluluğu / çalışma saati yüzünden yerleştirilemeyenler.
  final List<PlaceSuggestion> unplaced;

  bool get allPlaced => unplaced.isEmpty;
}

/// Seçilen yerleri plana EKLER — mevcut öğelere dokunmadan.
///
/// Her yer, kendi şehrinin günleri arasında boşluğu olan İLK güne konur:
///  • 09:00-20:00 planlama penceresi,
///  • yerin kendi çalışma saati (`visitWindow`),
///  • komşu öğelerle 15 dk geçiş tamponu
/// üçü birden sağlanmalıdır. Hiçbir güne sığmayan yer [HighlightPlacement.
/// unplaced] içinde döner — sessizce yutulmaz, çağıran kullanıcıya söyler.
///
/// Seçilenler ayrıca `preferences.mustSee`'ye yazılır: plan ileride yeniden
/// üretilirse (şehir/tarih değişimi) bu tercihler generator'a girdi olur.
HighlightPlacement addHighlightsToPlan(
  Trip trip,
  List<PlaceSuggestion> places,
) {
  final placed = <String, int>{};
  final unplaced = <PlaceSuggestion>[];

  final dests = [...trip.preferences.destinations]
    ..sort((a, b) => a.order.compareTo(b.order));

  for (final place in places) {
    final target = _placeInFirstFittingDay(trip, dests, place);
    if (target == null) {
      unplaced.add(place);
      continue;
    }
    placed[place.name] = target;
  }

  // Yerleştirilebilenleri tercih olarak da kaydet — ileride yeniden üretim
  // olursa generator bunları +100 puanla öne alır.
  for (final p in places) {
    if (!placed.containsKey(p.name)) continue;
    if (!trip.preferences.mustSee.contains(p.name)) {
      trip.preferences.mustSee.add(p.name);
    }
  }

  return HighlightPlacement(placed: placed, unplaced: unplaced);
}

/// [place]'i şehrine ait ilk uygun güne yerleştirir; başarılıysa gün numarası.
int? _placeInFirstFittingDay(
  Trip trip,
  List<TripDestination> dests,
  PlaceSuggestion place,
) {
  final placeCity = _cleanCity(place.city).toLowerCase();
  final full = place.durationMin ?? kDefaultActivityMinutes;
  final (winStart, winEnd) = place.visitWindow(kDayStartMinutes, kDayEndMinutes);

  // Bu yerin şehrine ait, dokunulabilir günler (varış/dönüş günü uçuşa bağlı).
  final candidates = <DayPlan>[];
  for (final day in trip.days) {
    final dest = getDestinationForDate(dests, day.date);
    final dayCity = _cleanCity(dest?.city ?? '').toLowerCase();
    if (dayCity.isEmpty || dayCity != placeCity) continue;
    if (day.dayNumber == 1 || day.dayNumber == trip.days.length) continue;
    candidates.add(day);
  }
  if (candidates.isEmpty) return null;

  // İki tur: önce tam süreyle (rahat gün bulunsun), sığmazsa kısaltılmış.
  // Üretilen planlar 09:00-20:00'yi neredeyse tamamen dolduruyor; tek turda
  // tam süre arasak kullanıcının seçtiği yer neredeyse hep reddedilirdi.
  for (final duration in [full, _kMinVisitMinutes]) {
    if (duration > full) continue;
    for (final day in candidates) {
      final dest = getDestinationForDate(dests, day.date);
      final slot = _findFreeSlot(day.items, winStart, winEnd, duration);
      if (slot == null) continue;

      // Koordinat: haritada görünsün ve rota optimizasyonuna girebilsin diye
      // ŞİMDİ çözülür. Aksi halde eklenen yer koordinatsız kalıyor ve
      // optimizasyon onu "konumu yok" diye eleyip sessizce dışarıda bırakıyor.
      final coords = resolvePlaceCoords(place.name, cityKey: dest?.city);

      day.items.add(TimelineItem(
        id: newItemId(day.dayNumber),
        title: '${place.emoji} ${place.name}',
        description: '${place.city} · ${place.category}',
        kind: TimelineItemKind.activity,
        time: _toHhmm(slot),
        scheduledTime: _toHhmm(slot),
        durationMin: duration,
        lat: coords?.lat,
        lng: coords?.lng,
        cityId: dest?.city,
        mapUrl: 'https://www.google.com/maps/search/?api=1&query='
            '${Uri.encodeComponent('${place.name} ${_cleanCity(place.city)}')}',
        lockType: isTimedEntryTitle(place.name)
            ? ActivityLockType.ticketedEvent
            : ActivityLockType.none,
        canChangeTime: !isTimedEntryTitle(place.name),
        canChangeDay: !isTimedEntryTitle(place.name),
      ));
      // Kronolojik sırayı koru — viewer öğeleri liste sırasında gösteriyor.
      day.items.sort((a, b) {
        final ta = _toMin(a.time ?? a.scheduledTime) ?? 1 << 20;
        final tb = _toMin(b.time ?? b.scheduledTime) ?? 1 << 20;
        return ta.compareTo(tb);
      });
      return day.dayNumber;
    }
  }
  return null;
}

/// [items] arasında [duration] dakikalık boşluk arar; bulursa başlangıç dk.
int? _findFreeSlot(
  List<TimelineItem> items,
  int winStart,
  int winEnd,
  int duration,
) {
  // Izgarayı 30 dk adımlarla tara — ilk çakışmayan başlangıcı döndür.
  for (var start = winStart; start + duration <= winEnd; start += _kSlotStep) {
    final end = start + duration;
    var collides = false;
    for (final it in items) {
      final os = _toMin(it.time ?? it.scheduledTime);
      if (os == null) continue;
      final oe = os + _durationOf(it);
      // Geçiş tamponuyla birlikte örtüşme kontrolü.
      if (start < oe + _kTransitionMinutes &&
          os < end + _kTransitionMinutes) {
        collides = true;
        break;
      }
    }
    if (!collides) return start;
  }
  return null;
}
