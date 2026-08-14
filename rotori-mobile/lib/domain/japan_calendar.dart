/// Japonya saha takvimi: resmî tatiller, teishukubi (定休日) kapanış kuralları
/// ve sezonluk kalabalık dinamikleri.
///
/// Bu katman **saf** ve **offline**'dır: ağ çağrısı, `DateTime.now()` veya
/// rastgelelik içermez. Aynı tarih her zaman aynı sonucu verir; optimizer
/// determinizmi buna bağlıdır.
///
/// Kapsam sözleşmesi:
/// - Tatil hesabı 1980–2099 aralığı için geçerlidir (equinox yaklaşımı bu
///   aralıkta tanımlıdır). Aralık dışında tatil kümesi boş döner ve kapanış
///   kuralları "kayma yok" moduna düşer — sessiz yanlış cevap yerine
///   muhafazakâr davranış.
/// - Mekana özgü istisnalar (`ClosureRule.exceptionalClosedDates` /
///   `exceptionalOpenDates`) katalogdan gelir ve hesaplanan kuralı ezer.
library;

import 'minute_math.dart';

/// Tarihi yerel gün sınırına indirger. Takvim karşılaştırmaları saat/dakika
/// taşımamalıdır; aksi halde `==` eşitliği sessizce bozulur.
DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Resmî tatilin hangi mekanizmayla oluştuğu.
enum JapanHolidayKind {
  /// Kanunla sabit tarihli tatil (ör. 5 Mayıs Kodomo no Hi).
  statutory,

  /// Happy Monday sistemi — ayın n. Pazartesi'sine kaydırılmış tatil.
  happyMonday,

  /// Astronomik olarak hesaplanan gündönümü tatili (Shunbun / Shubun).
  equinox,

  /// 振替休日 — tatil Pazar'a denk geldiğinde ilk uygun iş gününe aktarılır.
  substitute,

  /// 国民の休日 — iki tatil arasında sıkışan tek iş günü.
  citizens,
}

class JapanHoliday {
  const JapanHoliday({
    required this.date,
    required this.id,
    required this.nameJa,
    required this.nameEn,
    required this.kind,
  });

  final DateTime date;
  final String id;
  final String nameJa;
  final String nameEn;
  final JapanHolidayKind kind;

  @override
  bool operator ==(Object other) =>
      other is JapanHoliday && other.date == date && other.id == id;

  @override
  int get hashCode => Object.hash(date, id);

  @override
  String toString() => 'JapanHoliday($id, ${date.toIso8601String()})';
}

/// Resmî tatil takvimi. Yıl bazında hesaplar ve önbelleğe alır.
class JapanPublicHolidayCalendar {
  JapanPublicHolidayCalendar();

  /// Equinox yaklaşımının tanımlı olduğu aralık.
  static const int minimumSupportedYear = 1980;
  static const int maximumSupportedYear = 2099;

  final Map<int, Map<DateTime, JapanHoliday>> _byYear = {};

  bool supportsYear(int year) =>
      year >= minimumSupportedYear && year <= maximumSupportedYear;

  Map<DateTime, JapanHoliday> holidaysInYear(int year) {
    if (!supportsYear(year)) return const {};
    return _byYear.putIfAbsent(year, () => _computeYear(year));
  }

  JapanHoliday? holidayOn(DateTime date) {
    final key = dateOnly(date);
    return holidaysInYear(key.year)[key];
  }

  bool isPublicHoliday(DateTime date) => holidayOn(date) != null;

  /// Resmî tatil **veya** hafta sonu. Kalabalık modeli ve otobüs trafik riski
  /// bunu kullanır; müze kapanış kayması ise yalnız `isPublicHoliday` kullanır
  /// — hafta sonu kaymayı tetiklemez.
  bool isNonWorkingDay(DateTime date) {
    final weekday = dateOnly(date).weekday;
    return weekday == DateTime.saturday ||
        weekday == DateTime.sunday ||
        isPublicHoliday(date);
  }

  Map<DateTime, JapanHoliday> _computeYear(int year) {
    final result = <DateTime, JapanHoliday>{};

    void put(JapanHoliday holiday) {
      // Aynı güne düşen iki tatilde ilk (kanunî) kayıt korunur; substitute ve
      // citizens türleri zaten dolu güne yazılmaz.
      result.putIfAbsent(holiday.date, () => holiday);
    }

    for (final entry in _fixedHolidays) {
      if (year < entry.fromYear || year > entry.untilYear) continue;
      put(JapanHoliday(
        date: DateTime(year, entry.month, entry.day),
        id: entry.id,
        nameJa: entry.nameJa,
        nameEn: entry.nameEn,
        kind: JapanHolidayKind.statutory,
      ));
    }

    for (final entry in _happyMondayHolidays) {
      if (year < entry.fromYear) continue;
      put(JapanHoliday(
        date: _nthWeekday(year, entry.month, DateTime.monday, entry.ordinal),
        id: entry.id,
        nameJa: entry.nameJa,
        nameEn: entry.nameEn,
        kind: JapanHolidayKind.happyMonday,
      ));
    }

    put(JapanHoliday(
      date: DateTime(year, 3, _vernalEquinoxDay(year)),
      id: 'shunbun-no-hi',
      nameJa: '春分の日',
      nameEn: 'Vernal Equinox Day',
      kind: JapanHolidayKind.equinox,
    ));
    put(JapanHoliday(
      date: DateTime(year, 9, _autumnalEquinoxDay(year)),
      id: 'shubun-no-hi',
      nameJa: '秋分の日',
      nameEn: 'Autumnal Equinox Day',
      kind: JapanHolidayKind.equinox,
    ));

    // 振替休日: Pazar'a düşen tatil, tatil olmayan ilk güne aktarılır.
    // Golden Week'te zincirleme kayma olabildiği için ileri doğru yürünür.
    final statutoryDates = result.keys.toList()..sort();
    for (final date in statutoryDates) {
      if (date.weekday != DateTime.sunday) continue;
      var candidate = date.add(const Duration(days: 1));
      while (result.containsKey(candidate)) {
        candidate = candidate.add(const Duration(days: 1));
      }
      put(JapanHoliday(
        date: candidate,
        id: 'furikae-kyujitsu',
        nameJa: '振替休日',
        nameEn: 'Substitute Holiday',
        kind: JapanHolidayKind.substitute,
      ));
    }

    // 国民の休日: iki tatil arasında kalan tek iş günü de tatildir
    // (pratikte Eylül "Silver Week" yıllarında oluşur).
    final withSubstitutes = result.keys.toList()..sort();
    for (final date in withSubstitutes) {
      final gap = date.add(const Duration(days: 1));
      final after = date.add(const Duration(days: 2));
      if (result.containsKey(gap) || !result.containsKey(after)) continue;
      if (gap.weekday == DateTime.sunday) continue;
      put(JapanHoliday(
        date: gap,
        id: 'kokumin-no-kyujitsu',
        nameJa: '国民の休日',
        nameEn: "Citizens' Holiday",
        kind: JapanHolidayKind.citizens,
      ));
    }

    return Map.unmodifiable(result);
  }

  static DateTime _nthWeekday(int year, int month, int weekday, int ordinal) {
    final first = DateTime(year, month, 1);
    final offset = (weekday - first.weekday + 7) % 7;
    return DateTime(year, month, 1 + offset + (ordinal - 1) * 7);
  }

  /// 1980–2099 için Japonya'da kullanılan standart yaklaşım.
  static int _vernalEquinoxDay(int year) => _equinoxDay(year, 20.8431);

  static int _autumnalEquinoxDay(int year) => _equinoxDay(year, 23.2488);

  static int _equinoxDay(int year, double base) {
    final delta = year - 1980;
    return (base + 0.242194 * delta - (delta ~/ 4)).floor();
  }
}

class _FixedHoliday {
  const _FixedHoliday(
    this.id,
    this.month,
    this.day,
    this.nameJa,
    this.nameEn, {
    this.fromYear = JapanPublicHolidayCalendar.minimumSupportedYear,
    this.untilYear = JapanPublicHolidayCalendar.maximumSupportedYear,
  });

  final String id;
  final int month;
  final int day;
  final String nameJa;
  final String nameEn;
  final int fromYear;
  final int untilYear;
}

class _HappyMondayHoliday {
  const _HappyMondayHoliday(
    this.id,
    this.month,
    this.ordinal,
    this.nameJa,
    this.nameEn, {
    this.fromYear = JapanPublicHolidayCalendar.minimumSupportedYear,
  });

  final String id;
  final int month;
  final int ordinal;
  final String nameJa;
  final String nameEn;
  final int fromYear;
}

const List<_FixedHoliday> _fixedHolidays = [
  _FixedHoliday('ganjitsu', 1, 1, '元日', "New Year's Day"),
  _FixedHoliday('kenkoku-kinen', 2, 11, '建国記念の日', 'National Foundation Day'),
  _FixedHoliday('tenno-tanjobi', 2, 23, '天皇誕生日', "Emperor's Birthday",
      fromYear: 2020),
  // Heisei dönemi — 2018'e kadar 23 Aralık.
  _FixedHoliday('tenno-tanjobi-heisei', 12, 23, '天皇誕生日', "Emperor's Birthday",
      untilYear: 2018),
  _FixedHoliday('showa-no-hi', 4, 29, '昭和の日', 'Showa Day', fromYear: 2007),
  // 2007 öncesi 29 Nisan みどりの日'ydı; Golden Week penceresi değişmez.
  _FixedHoliday('midori-no-hi-legacy', 4, 29, 'みどりの日', 'Greenery Day',
      untilYear: 2006),
  _FixedHoliday('kenpo-kinenbi', 5, 3, '憲法記念日', 'Constitution Memorial Day'),
  _FixedHoliday('midori-no-hi', 5, 4, 'みどりの日', 'Greenery Day', fromYear: 2007),
  _FixedHoliday('kodomo-no-hi', 5, 5, 'こどもの日', "Children's Day"),
  _FixedHoliday('yama-no-hi', 8, 11, '山の日', 'Mountain Day', fromYear: 2016),
  _FixedHoliday('bunka-no-hi', 11, 3, '文化の日', 'Culture Day'),
  _FixedHoliday('kinro-kansha', 11, 23, '勤労感謝の日', 'Labour Thanksgiving Day'),
];

const List<_HappyMondayHoliday> _happyMondayHolidays = [
  _HappyMondayHoliday('seijin-no-hi', 1, 2, '成人の日', 'Coming of Age Day',
      fromYear: 2000),
  _HappyMondayHoliday('umi-no-hi', 7, 3, '海の日', 'Marine Day', fromYear: 2003),
  _HappyMondayHoliday('keiro-no-hi', 9, 3, '敬老の日', 'Respect for the Aged Day',
      fromYear: 2003),
  _HappyMondayHoliday('sports-no-hi', 10, 2, 'スポーツの日', 'Sports Day',
      fromYear: 2000),
];

/// Kapalı olan bir tarihin gerekçesi — UI'ın kullanıcıya dürüst açıklama
/// verebilmesi ve testlerin ayrımı doğrulayabilmesi için.
enum ClosureCause {
  /// Haftalık düzenli kapanış (ör. her Pazartesi).
  weeklyClosure,

  /// Pazartesi resmî tatil olduğu için kayan kapanış (Salı kapalı).
  shiftedClosure,

  /// Yıl sonu / yıl başı bakım kapanışı (年末年始).
  yearEndClosure,

  /// Katalogdan gelen mekana özgü istisna kapanış.
  exceptionalClosure,
}

class ClosureVerdict {
  const ClosureVerdict.open()
      : isClosed = false,
        cause = null,
        shiftedFrom = null;

  const ClosureVerdict.closed(this.cause, {this.shiftedFrom}) : isClosed = true;

  final bool isClosed;
  final ClosureCause? cause;

  /// `shiftedClosure` için kapanışı doğuran asıl düzenli kapanış günü.
  final DateTime? shiftedFrom;

  bool get isOpen => !isClosed;
}

/// Bir mekanın haftalık/yıllık kapanış sözleşmesi.
class ClosureRule {
  ClosureRule({
    Set<int> weeklyClosedWeekdays = const {},
    this.shiftsWhenClosureDayIsHoliday = true,
    this.observesYearEndClosure = true,
    this.yearEndClosureStartMonthDay = const (12, 29),
    this.yearEndClosureEndMonthDay = const (1, 3),
    Set<DateTime> exceptionalClosedDates = const {},
    Set<DateTime> exceptionalOpenDates = const {},
  })  : weeklyClosedWeekdays = Set.unmodifiable(weeklyClosedWeekdays),
        exceptionalClosedDates =
            Set.unmodifiable(exceptionalClosedDates.map(dateOnly)),
        exceptionalOpenDates =
            Set.unmodifiable(exceptionalOpenDates.map(dateOnly));

  /// Hiçbir kapanışı olmayan mekan (park, kavşak, bölge).
  ClosureRule.alwaysOpen()
      : weeklyClosedWeekdays = const {},
        shiftsWhenClosureDayIsHoliday = false,
        observesYearEndClosure = false,
        yearEndClosureStartMonthDay = const (12, 29),
        yearEndClosureEndMonthDay = const (1, 3),
        exceptionalClosedDates = const {},
        exceptionalOpenDates = const {};

  /// `DateTime.monday` … `DateTime.sunday`.
  final Set<int> weeklyClosedWeekdays;

  /// Japon müze standardı: kapanış günü resmî tatile denk gelirse mekan açık
  /// kalır ve kapanış tatil olmayan ilk güne kayar.
  final bool shiftsWhenClosureDayIsHoliday;

  final bool observesYearEndClosure;
  final (int, int) yearEndClosureStartMonthDay;
  final (int, int) yearEndClosureEndMonthDay;

  final Set<DateTime> exceptionalClosedDates;
  final Set<DateTime> exceptionalOpenDates;

  bool get hasAnyClosure =>
      weeklyClosedWeekdays.isNotEmpty ||
      observesYearEndClosure ||
      exceptionalClosedDates.isNotEmpty;
}

/// Kapanış kurallarını takvimle birleştiren saf çözümleyici.
class ClosureResolver {
  ClosureResolver({JapanPublicHolidayCalendar? calendar})
      : calendar = calendar ?? JapanPublicHolidayCalendar();

  final JapanPublicHolidayCalendar calendar;

  /// Kayma araması için pencere. Ardışık tatil zinciri (Golden Week, Silver
  /// Week) en fazla bu kadar gün ileri iter.
  static const int _shiftLookaheadDays = 8;

  ClosureVerdict evaluate(ClosureRule rule, DateTime date) {
    final day = dateOnly(date);

    // Katalog istisnaları hesaplanan her şeyi ezer.
    if (rule.exceptionalOpenDates.contains(day)) {
      return const ClosureVerdict.open();
    }
    if (rule.exceptionalClosedDates.contains(day)) {
      return const ClosureVerdict.closed(ClosureCause.exceptionalClosure);
    }
    if (rule.observesYearEndClosure && _inYearEndWindow(rule, day)) {
      return const ClosureVerdict.closed(ClosureCause.yearEndClosure);
    }
    if (rule.weeklyClosedWeekdays.isEmpty) {
      return const ClosureVerdict.open();
    }

    // Kayma devre dışıysa haftalık kural birebir uygulanır.
    if (!rule.shiftsWhenClosureDayIsHoliday ||
        !calendar.supportsYear(day.year)) {
      return rule.weeklyClosedWeekdays.contains(day.weekday)
          ? const ClosureVerdict.closed(ClosureCause.weeklyClosure)
          : const ClosureVerdict.open();
    }

    // Holiday Shift: `day` yalnızca, kendisine kayan bir düzenli kapanış günü
    // varsa kapalıdır. Geriye doğru pencere taranır; böylece hem "Pazartesi
    // tatil → Pazartesi açık" hem "→ Salı kapalı" tek kuralla çıkar.
    for (var back = 0; back <= _shiftLookaheadDays; back++) {
      final origin = day.subtract(Duration(days: back));
      if (!rule.weeklyClosedWeekdays.contains(origin.weekday)) continue;
      final effective = _effectiveClosureDate(rule, origin);
      if (effective == day) {
        return back == 0
            ? const ClosureVerdict.closed(ClosureCause.weeklyClosure)
            : ClosureVerdict.closed(
                ClosureCause.shiftedClosure,
                shiftedFrom: origin,
              );
      }
    }
    return const ClosureVerdict.open();
  }

  bool isClosed(ClosureRule rule, DateTime date) =>
      evaluate(rule, date).isClosed;

  /// Düzenli kapanış günü tatile denk gelirse tatil olmayan ilk güne kayar.
  /// Kayılan gün başka bir düzenli kapanış gününe denk gelirse aynı gün
  /// sayılır (çift kapanış üretilmez).
  DateTime _effectiveClosureDate(ClosureRule rule, DateTime regularClosureDay) {
    if (!calendar.isPublicHoliday(regularClosureDay)) return regularClosureDay;
    var candidate = regularClosureDay.add(const Duration(days: 1));
    var guard = 0;
    while (calendar.isPublicHoliday(candidate) && guard < _shiftLookaheadDays) {
      candidate = candidate.add(const Duration(days: 1));
      guard++;
    }
    return candidate;
  }

  bool _inYearEndWindow(ClosureRule rule, DateTime day) {
    final (startMonth, startDay) = rule.yearEndClosureStartMonthDay;
    final (endMonth, endDay) = rule.yearEndClosureEndMonthDay;
    final afterStart = day.month > startMonth ||
        (day.month == startMonth && day.day >= startDay);
    final beforeEnd =
        day.month < endMonth || (day.month == endMonth && day.day <= endDay);
    // Pencere yıl sınırını aştığında (12/29 → 01/03) "veya" mantığı doğrudur.
    return startMonth > endMonth
        ? (afterStart || beforeEnd)
        : (afterStart && beforeEnd);
  }
}

/// Süre ve kalabalık davranışını değiştiren sezon.
enum CrowdSeason {
  normal,
  sakura,
  goldenWeek,
  obon,
  newYear,
  autumnFoliage,
}

/// Sezonluk yoğunluk modeli — `durationMinutes` ve yürüme sürelerini
/// çarpanla büyütür.
///
/// Çarpanlar tahmindir ve **yalnız** kalabalık kaynaklı yavaşlamayı temsil
/// eder; bilet/rezervasyon kısıtı değildir.
class JapanCrowdModel {
  JapanCrowdModel({JapanPublicHolidayCalendar? calendar})
      : calendar = calendar ?? JapanPublicHolidayCalendar();

  final JapanPublicHolidayCalendar calendar;

  /// Sakura zirvesi şehre göre kayar — Tokyo/Kyoto ~aynı, Sapporo çok geç.
  /// Gün-of-year aralığı olarak tutulur (artık yıl toleransı ±1 gün, kabul
  /// edilebilir).
  static const Map<String, (int, int)> _sakuraWindowMonthDay = {
    'tokyo': (322, 407),
    'kyoto': (325, 410),
    'osaka': (325, 410),
    'nara': (325, 410),
    'nagoya': (324, 409),
    'hiroshima': (324, 409),
    'kanazawa': (401, 415),
    'fukuoka': (320, 405),
    'sapporo': (429, 512),
  };

  static const (int, int) _defaultSakuraWindow = (325, 410);

  /// 紅葉 — sonbahar yaprakları; Kyoto'da tapınak kuyrukları katlanır.
  static const Map<String, (int, int)> _autumnWindowMonthDay = {
    'tokyo': (1120, 1210),
    'kyoto': (1115, 1205),
    'osaka': (1118, 1208),
    'nara': (1115, 1205),
    'nagoya': (1118, 1208),
    'kanazawa': (1105, 1125),
    'sapporo': (1005, 1025),
  };

  CrowdSeason seasonFor(DateTime date, {String? cityId}) {
    final day = dateOnly(date);
    final key = _monthDayKey(day);

    // Golden Week: 29 Nisan – 5 Mayıs çekirdek; 6 Mayıs dönüş yoğunluğu dahil.
    if (key >= 429 && key <= 506) return CrowdSeason.goldenWeek;
    if (key >= 1229 || key <= 103) return CrowdSeason.newYear;
    if (key >= 811 && key <= 817) return CrowdSeason.obon;

    final city = _normalizeCity(cityId);
    final sakura = _sakuraWindowMonthDay[city] ?? _defaultSakuraWindow;
    if (key >= sakura.$1 && key <= sakura.$2) return CrowdSeason.sakura;

    final autumn = _autumnWindowMonthDay[city];
    if (autumn != null && key >= autumn.$1 && key <= autumn.$2) {
      return CrowdSeason.autumnFoliage;
    }
    return CrowdSeason.normal;
  }

  /// Etkinlik süresine uygulanacak çarpan.
  ///
  /// Brief'in kuralı: Golden Week veya Sakura + (Kyoto|Tokyo) + popüler
  /// tapınak/park → ×1.25. Diğer sezon/şehir/kategori bileşimleri daha
  /// ölçülü çarpanlar alır; kalabalıktan etkilenmeyen kategoriler ×1.0.
  double durationMultiplier({
    required DateTime date,
    String? cityId,
    CrowdSensitivity sensitivity = CrowdSensitivity.moderate,
  }) {
    if (sensitivity == CrowdSensitivity.none) return 1;
    final season = seasonFor(date, cityId: cityId);
    if (season == CrowdSeason.normal) {
      // Hafta sonu ve resmî tatiller tek başına küçük bir yavaşlama yaratır.
      if (sensitivity == CrowdSensitivity.high &&
          calendar.isNonWorkingDay(date)) {
        return 1.10;
      }
      return 1;
    }

    final peakCity = _isPeakCity(cityId);
    final base = switch (season) {
      CrowdSeason.goldenWeek => peakCity ? 1.25 : 1.18,
      CrowdSeason.sakura => peakCity ? 1.25 : 1.15,
      CrowdSeason.autumnFoliage => peakCity ? 1.20 : 1.12,
      CrowdSeason.newYear => peakCity ? 1.20 : 1.12,
      CrowdSeason.obon => 1.15,
      CrowdSeason.normal => 1.0,
    };

    final scaled = switch (sensitivity) {
      CrowdSensitivity.high => base,
      CrowdSensitivity.moderate => 1 + (base - 1) * 0.6,
      CrowdSensitivity.none => 1.0,
    };
    return double.parse(scaled.toStringAsFixed(4));
  }

  /// Kalabalık dönemde istasyon ve cadde yürüyüşü de yavaşlar.
  double walkingMultiplier({required DateTime date, String? cityId}) {
    final season = seasonFor(date, cityId: cityId);
    return switch (season) {
      CrowdSeason.normal => 1.0,
      CrowdSeason.obon => 1.05,
      CrowdSeason.newYear => 1.08,
      CrowdSeason.autumnFoliage => 1.08,
      CrowdSeason.sakura => _isPeakCity(cityId) ? 1.12 : 1.08,
      CrowdSeason.goldenWeek => _isPeakCity(cityId) ? 1.15 : 1.10,
    };
  }

  static bool _isPeakCity(String? cityId) {
    final city = _normalizeCity(cityId);
    return city == 'tokyo' || city == 'kyoto';
  }

  static String _normalizeCity(String? cityId) =>
      (cityId ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

  static int _monthDayKey(DateTime day) => day.month * 100 + day.day;
}

/// Bir aktivitenin kalabalıktan ne kadar etkilendiği.
///
/// Tapınak/park/gözlem terası kuyruk ve akış darboğazı yaşar; kapalı rezerve
/// müze ya da otel içi deneyim yaşamaz.
enum CrowdSensitivity { none, moderate, high }

/// Kategori adından duyarlılık türetir. Katalog açık değer vermediğinde
/// kullanılan muhafazakâr varsayılan.
CrowdSensitivity crowdSensitivityForCategory(String? category) {
  final value = (category ?? '').toLowerCase();
  if (value.isEmpty) return CrowdSensitivity.moderate;
  // Tam gün tema parkı süreleri zaten kuyrukları ve park içi dolaşımı içeren
  // ziyaret bütçeleridir. Bunları açık hava "park" kategorisi gibi yüksek
  // çarpmak aynı kalabalığı iki kez sayıp bütün günü uygulanamaz yapar.
  const alreadyBudgeted = [
    'themepark',
    'theme park',
    'tema parkı',
    'tema parki'
  ];
  if (alreadyBudgeted.any(value.contains)) return CrowdSensitivity.none;
  const high = [
    'temple',
    'shrine',
    'park',
    'garden',
    'view',
    'observation',
    'tapınak',
    'tapinak',
    'park',
    'bahçe',
    'bahce',
    'manzara',
  ];
  const none = ['hotel', 'transport', 'otel', 'ulaşım', 'ulasim', 'lounge'];
  if (high.any(value.contains)) return CrowdSensitivity.high;
  if (none.any(value.contains)) return CrowdSensitivity.none;
  return CrowdSensitivity.moderate;
}

/// Uygulama içi tekil örnekler — takvim hesabı yıl bazında önbelleklenir ve
/// saf olduğu için paylaşılabilir.
final JapanPublicHolidayCalendar kJapanHolidayCalendar =
    JapanPublicHolidayCalendar();
final ClosureResolver kJapanClosureResolver =
    ClosureResolver(calendar: kJapanHolidayCalendar);
final JapanCrowdModel kJapanCrowdModel =
    JapanCrowdModel(calendar: kJapanHolidayCalendar);

/// Sezon çarpanını dakikaya uygular. Yuvarlama kuralı [scaleMinutes]'te
/// merkezîdir — kalabalık tahmininde iyimserlik saha hatası üretir.
int applyCrowdMultiplier(int minutes, double multiplier) =>
    scaleMinutes(minutes, multiplier);
