// TypeScript packages/shared/src/cityTransfers.ts'in Dart karşılığı.
// Şehirler arası bilinen transferler + plan içinde şehir geçişi tespiti.

import '../core/l10n.dart';
import 'destination_profiles.dart';
import 'trip_factory.dart';
import 'types.dart';

class CityTransfer {
  const CityTransfer({
    required this.emoji,
    required this.mode,
    required this.duration,
    required this.fare,
    this.tip,
  });

  final String emoji;

  /// UI başlığı. Özel isimler (ör. "Shinkansen Nozomi") düz metindir;
  /// çevrilebilir mod adları i18n anahtarıdır (ör. "xfer.mode.localTrain").
  /// Gösterirken `L10n.resolve(mode, lang)` ile çözülür — anahtar değilse
  /// metin aynen döner.
  final String mode;

  /// Yaklaşık süre (ör. "2s 30dk")
  final String duration;

  /// Tek yön yaklaşık ücret (ör. "~14,000 ¥")
  final String fare;

  /// Plan içinde gösterilecek kısa ipucu — i18n anahtarı (ör. "xfer.tip.bus").
  /// Gösterirken `L10n.resolve(tip, lang)` ile çözülür.
  final String? tip;
}

const Map<String, CityTransfer> _transfers = {
  'tokyo|osaka': CityTransfer(
    emoji: '🚄',
    mode: 'Shinkansen Nozomi',
    duration: '2s 30dk',
    fare: '~14,720 ¥',
    tip: 'xfer.tip.tokyoOsaka',
  ),
  'tokyo|kyoto': CityTransfer(
    emoji: '🚄',
    mode: 'Shinkansen Nozomi',
    duration: '2s 15dk',
    fare: '~14,170 ¥',
    tip: 'xfer.tip.tokyoKyoto',
  ),
  'tokyo|hakone': CityTransfer(
    emoji: '🚆',
    mode: 'Odakyu Romance Car',
    duration: '1s 30dk',
    fare: '~2,470 ¥',
    tip: 'xfer.tip.tokyoHakone',
  ),
  'tokyo|nikko': CityTransfer(
    emoji: '🚆',
    mode: 'Tobu Limited Express Spacia',
    duration: '2s',
    fare: '~2,800 ¥',
  ),
  'tokyo|nagoya': CityTransfer(
    emoji: '🚄',
    mode: 'Shinkansen Nozomi',
    duration: '1s 40dk',
    fare: '~11,300 ¥',
  ),
  'osaka|kyoto': CityTransfer(
    emoji: '🚆',
    mode: 'JR Special Rapid',
    duration: '30dk',
    fare: '~580 ¥',
    tip: 'xfer.tip.osakaKyoto',
  ),
  'osaka|nara': CityTransfer(
    emoji: '🚆',
    mode: 'Kintetsu Limited Express',
    duration: '45dk',
    fare: '~1,140 ¥',
  ),
  'osaka|hiroshima': CityTransfer(
    emoji: '🚄',
    mode: 'Shinkansen Sakura/Nozomi',
    duration: '1s 25dk',
    fare: '~10,500 ¥',
  ),
  'kyoto|nara': CityTransfer(
    emoji: '🚆',
    mode: 'JR Nara Line',
    duration: '45dk',
    fare: '~720 ¥',
  ),
  'kyoto|osaka': CityTransfer(
    emoji: '🚆',
    mode: 'JR Special Rapid',
    duration: '30dk',
    fare: '~580 ¥',
  ),
  'nara|kyoto': CityTransfer(
    emoji: '🚆',
    mode: 'JR Nara Line',
    duration: '45dk',
    fare: '~720 ¥',
  ),
  'tokyo|fuji': CityTransfer(
    emoji: '🚌',
    mode: 'Highway Bus Shinjuku → Kawaguchiko',
    duration: '2s 15dk',
    fare: '~2,200 ¥',
  ),
};

String _normCity(String city) => city
    .toLowerCase()
    .replaceAll(RegExp(r'\s+\(.*?\)$'), '')
    .replaceAll(RegExp(r'[-_\s]+'), '')
    .trim();

/// İki şehir için bilinen transferi döndür (her iki yön de kabul edilir).
CityTransfer? lookupTransfer(String from, String to) {
  final a = _normCity(from);
  final b = _normCity(to);
  return _transfers['$a|$b'] ?? _transfers['$b|$a'];
}

/// Bir gün için "ana şehir" — önce öğelerdeki cityId, sonra destinasyon.
String? _dayDominantCity(DayPlan day, List<TripDestination> destinations) {
  for (final item in day.items) {
    if (item.cityId != null) return item.cityId;
  }
  return getDestinationForDate(destinations, day.date)?.city;
}

class CityTransitionSuggestion {
  const CityTransitionSuggestion({
    required this.fromDayNumber,
    required this.toDayNumber,
    required this.fromCity,
    required this.toCity,
    required this.transfer,
  });

  final int fromDayNumber;
  final int toDayNumber;
  final String fromCity;
  final String toCity;
  final CityTransfer transfer;
}

/// Plan günleri içinde ardışık şehir geçişlerini ve önerilen transfer biçimini bul.
List<CityTransitionSuggestion> detectCityTransitions(
  List<DayPlan> days,
  List<TripDestination> destinations,
) {
  final out = <CityTransitionSuggestion>[];
  final sorted = [...days]..sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
  String? prevCity;
  int? prevDay;
  for (final day in sorted) {
    final city = _dayDominantCity(day, destinations);
    if (city != null &&
        city.isNotEmpty &&
        prevCity != null &&
        _normCity(city) != _normCity(prevCity)) {
      final transfer = lookupTransfer(prevCity, city);
      if (transfer != null) {
        out.add(CityTransitionSuggestion(
          fromDayNumber: prevDay!,
          toDayNumber: day.dayNumber,
          fromCity: prevCity,
          toCity: city,
          transfer: transfer,
        ));
      }
    }
    if (city != null && city.isNotEmpty) {
      prevCity = city;
      prevDay = day.dayNumber;
    }
  }
  return out;
}

/// Verilen güne, başına şehir-arası transfer öğesi ekle ve o günün diğer
/// aktivitelerinin saatlerini transfere göre yeniden dağıt.
///
/// - Transfer 09:00'da kalkar (sabah yola çıkılır).
/// - Varış saati = kalkış + transfer süresi + 45 dk tampon (süre metninden
///   çözülür; çözülemezse ~3 saat varsayılır).
/// - Günün kalan öğeleri varıştan itibaren ~2 saat arayla yeniden zamanlanır —
///   böylece "önce yolculuk, sonra keşif" akışı ve çakışmasız saatler oluşur.
/// [lang] ile transfer mod adı ve ipucu (i18n anahtarları) o an seçili dile
/// çözülüp öğeye yazılır — böylece plana eklenen metin sabitlenir.
List<DayPlan> insertCityTransfer(
  List<DayPlan> days,
  int dayNumber,
  CityTransitionSuggestion suggestion, {
  AppLang lang = AppLang.tr,
}) {
  return days.map((d) {
    if (d.dayNumber != dayNumber) return d;
    final t = suggestion.transfer;
    const depMin = 9 * 60; // 09:00 kalkış
    final arrMin =
        (depMin + _transferDurationMin(t.duration) + 45).clamp(depMin + 60, 21 * 60);
    final transfer = TimelineItem(
      id: newItemId(dayNumber),
      title:
          '${t.emoji} ${suggestion.fromCity} → ${suggestion.toCity} • ${L10n.resolve(t.mode, lang)}',
      description: '${t.duration} · ${t.fare}',
      tips: t.tip == null ? null : L10n.resolve(t.tip!, lang),
      kind: TimelineItemKind.transport,
      time: _hhmm(depMin),
      scheduledTime: _hhmm(depMin),
      cityId: suggestion.toCity,
    );
    // Kalan aktiviteleri varış sonrası sıralı slotlara dağıt (30 dk'ya yuvarla).
    var slot = ((arrMin + 29) ~/ 30) * 30;
    final retimed = <TimelineItem>[];
    for (final it in d.items) {
      final s = slot.clamp(0, 22 * 60);
      retimed.add(it.copyWith(time: _hhmm(s), scheduledTime: _hhmm(s)));
      slot += 120;
    }
    return d.copyWith(items: [transfer, ...retimed]);
  }).toList();
}

/// Tespit edilen tüm şehir geçişlerini günlere ekler (idempotent —
/// zaten transfer olan güne yeniden eklemez). planner._generate ve demo
/// aynı pipeline'ı kullanır.
List<DayPlan> applyCityTransitions(
  List<DayPlan> days,
  List<TripDestination> destinations, {
  AppLang lang = AppLang.tr,
}) {
  var out = days;
  for (final s in detectCityTransitions(out, destinations)) {
    final target = out.where((d) => d.dayNumber == s.toDayNumber);
    if (target.isEmpty) continue;
    if (hasExistingTransferTo(target.first, s.toCity)) continue;
    out = insertCityTransfer(out, s.toDayNumber, s, lang: lang);
  }
  return out;
}

/// "2s 15dk" / "2h 15m" / "8+ saat" / "Yaklaşık 2-3 saat" gibi süre metninden
/// dakika çıkarır. Çözülemezse 180 dk (~3 saat) varsayar.
int _transferDurationMin(String d) {
  final l = d.toLowerCase();
  final h = RegExp(r'(\d+)[+\s]*(?:saat|sa|s|hr|h)').firstMatch(l);
  final m = RegExp(r'(\d+)\s*(?:dk|dak|min|m)\b').firstMatch(l);
  final total = (h != null ? int.parse(h.group(1)!) * 60 : 0) +
      (m != null ? int.parse(m.group(1)!) : 0);
  return total > 0 ? total : 180;
}

String _hhmm(int min) {
  final h = (min ~/ 60).clamp(0, 23);
  final m = min % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Ulaşım modu kimliği (picker sonucu). API stringleri sabit — enum yerine
/// String kullanıyoruz ki UI serialize/kompare basit kalsın.
const List<String> kTransportModes = [
  'shinkansen',
  'train',
  'bus',
  'car',
];

/// Verilen ulaşım modu için jenerik bir `CityTransfer` üretir.
/// (Bilinen çift olmasa da picker'dan seçilen bir moda geçmek için kullanılır.)
CityTransfer transferForMode(String mode) {
  switch (mode) {
    case 'train':
      return const CityTransfer(
        emoji: '🚆',
        mode: 'xfer.mode.localTrain',
        duration: 'Değişken',
        fare: 'Ucuz',
        tip: 'xfer.tip.train',
      );
    case 'bus':
      return const CityTransfer(
        emoji: '🚌',
        mode: 'xfer.mode.overnightBus',
        duration: '8+ saat',
        fare: 'Ekonomik',
        tip: 'xfer.tip.bus',
      );
    case 'car':
      return const CityTransfer(
        emoji: '🚗',
        mode: 'xfer.mode.rentalCar',
        duration: 'Değişken',
        fare: 'Yakıt + kira',
        tip: 'xfer.tip.car',
      );
    case 'shinkansen':
    default:
      return const CityTransfer(
        emoji: '🚄',
        mode: 'Shinkansen Nozomi',
        duration: 'Yaklaşık 2-3 saat',
        fare: '~10-15,000 ¥',
        tip: 'xfer.tip.shinkansen',
      );
  }
}

/// Seçilen mode + şehir/gün bilgileriyle yeni bir `CityTransitionSuggestion` üretir.
CityTransitionSuggestion suggestionForMode(
  String mode,
  String fromCity,
  String toCity,
  int fromDayNumber,
  int toDayNumber,
) {
  // Shinkansen için bilinen çift varsa (Tokyo→Osaka gibi) gerçek süre/ücreti
  // koru — sadece tip'i mode ile hizala.
  if (mode == 'shinkansen') {
    final known = lookupTransfer(fromCity, toCity);
    if (known != null) {
      return CityTransitionSuggestion(
        fromDayNumber: fromDayNumber,
        toDayNumber: toDayNumber,
        fromCity: fromCity,
        toCity: toCity,
        transfer: known,
      );
    }
  }
  return CityTransitionSuggestion(
    fromDayNumber: fromDayNumber,
    toDayNumber: toDayNumber,
    fromCity: fromCity,
    toCity: toCity,
    transfer: transferForMode(mode),
  );
}

/// Aynı transferin bu güne zaten eklendiğini kontrol et.
bool hasExistingTransferTo(DayPlan day, String toCity) {
  final norm = _normCity(toCity);
  return day.items.any(
    (it) =>
        it.kind == TimelineItemKind.transport &&
        it.title.toLowerCase().contains('→') &&
        it.title.toLowerCase().contains(norm),
  );
}
