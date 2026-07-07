// apps/planner/src/data/japanSeasonality.ts birebir Dart portu.

enum SeasonTone { good, warn, bad, info }

class SeasonBadge {
  const SeasonBadge(this.tag, this.emoji, this.label, this.tone);
  final String tag;
  final String emoji;
  final String label;
  final SeasonTone tone;
}

const Map<String, SeasonBadge> kBadges = {
  'sakura': SeasonBadge('sakura', '🌸', 'Sakura', SeasonTone.good),
  'autumn': SeasonBadge('autumn', '🍁', 'Sonbahar yaprakları', SeasonTone.good),
  'tsuyu': SeasonBadge('tsuyu', '🌧️', 'Muson (tsuyu)', SeasonTone.bad),
  'typhoon': SeasonBadge('typhoon', '🌀', 'Tayfun riski', SeasonTone.bad),
  'heat': SeasonBadge('heat', '🥵', 'Aşırı sıcak & nem', SeasonTone.warn),
  'cold': SeasonBadge('cold', '🥶', 'Soğuk', SeasonTone.info),
  'snow': SeasonBadge('snow', '❄️', 'Kar (kuzey)', SeasonTone.info),
  'mild': SeasonBadge('mild', '🌤️', 'Hoş hava', SeasonTone.good),
  'holiday':
      SeasonBadge('holiday', '🎌', 'Yerel tatil — çok yoğun', SeasonTone.warn),
};

class SeasonMonth {
  const SeasonMonth(this.month, this.label, this.tags, this.note);
  final int month;
  final String label;
  final List<String> tags;
  final String note;
}

const List<SeasonMonth> kMonths = [
  SeasonMonth(1, 'Ocak', ['cold', 'snow'],
      'Kuzeyde kar, güneyde temiz hava. Yeni yıl haftası (1-3 Oca) yoğun ve birçok yer kapalı.'),
  SeasonMonth(2, 'Şubat', ['cold', 'snow'],
      'Sapporo kar festivali. Genelde sakin ve ucuz.'),
  SeasonMonth(3, 'Mart', ['mild', 'sakura'],
      'Son hafta sakura başlangıcı (Tokyo). Hızla doluyor.'),
  SeasonMonth(4, 'Nisan', ['sakura', 'mild'],
      'Sakura zirvesi ilk 2 hafta. Çok güzel ama çok kalabalık + pahalı.'),
  SeasonMonth(5, 'Mayıs', ['mild', 'holiday'],
      'Golden Week (29 Nis - 5 May) çok yoğun. Ortadan sonu en hoş dönem.'),
  SeasonMonth(6, 'Haziran', ['tsuyu'],
      '2. haftadan itibaren tsuyu (muson) yağmurları. Önerilmez.'),
  SeasonMonth(7, 'Temmuz', ['tsuyu', 'heat'],
      'İlk yarı muson devam, ikinci yarı aşırı sıcak. Şehir gezmek zor.'),
  SeasonMonth(8, 'Ağustos', ['heat', 'typhoon', 'holiday'],
      'En sıcak & nemli ay. Obon (13-17 Ağu) yerel tatil — her yer dolu.'),
  SeasonMonth(9, 'Eylül', ['typhoon', 'heat'],
      'Tayfun sezonunun zirvesi. Hava aşağı doğru iyileşir.'),
  SeasonMonth(10, 'Ekim', ['mild', 'autumn'],
      'Hava harika, ilk sonbahar renkleri (kuzey). En önerilen aylardan.'),
  SeasonMonth(11, 'Kasım', ['autumn', 'mild'],
      'Sonbahar yapraklarının zirvesi. Serin, kuru, çok güzel.'),
  SeasonMonth(12, 'Aralık', ['cold', 'holiday'],
      'Şehirler ışıklı, sakin. 28 Ara - 4 Oca yeni yıl tatili — kalabalık & kapalılar.'),
];

class SuggestedRange {
  const SuggestedRange(this.id, this.label, this.startISO, this.endISO,
      this.tone, this.badges, this.reason);
  final String id;
  final String label;
  final String startISO;
  final String endISO;
  final SeasonTone tone;
  final List<String> badges;
  final String reason;
}

const List<SuggestedRange> kSuggestedRanges = [
  SuggestedRange(
      'oct-2026',
      'Ekim 2026 — Sonbahar başlangıcı',
      '2026-10-15',
      '2026-10-28',
      SeasonTone.good,
      ['mild', 'autumn'],
      'Hava ideal, ilk sonbahar renkleri. Tayfun riski geçmiş.'),
  SuggestedRange(
      'nov-2026',
      'Kasım 2026 — Yaprak zirvesi',
      '2026-11-08',
      '2026-11-21',
      SeasonTone.good,
      ['autumn', 'mild'],
      'Kyoto & Tokyo sonbahar renklerinin en güzel olduğu dönem. Serin, kuru.'),
  SuggestedRange(
      'feb-2027',
      'Şubat 2027 — Sakin & ucuz',
      '2027-02-08',
      '2027-02-21',
      SeasonTone.good,
      ['cold', 'snow'],
      'Soğuk ama temiz. Otel fiyatları düşük, turist az. Sapporo kar festivali bonus.'),
  SuggestedRange(
      'sakura-2027',
      'Mart-Nisan 2027 — Sakura',
      '2027-03-25',
      '2027-04-07',
      SeasonTone.warn,
      ['sakura'],
      'Sakura zirvesi — çok güzel ama çok kalabalık. Otelleri 6 ay önceden ayır.'),
  SuggestedRange(
      'may-2027',
      'Mayıs 2027 — Golden Week sonrası',
      '2027-05-10',
      '2027-05-23',
      SeasonTone.good,
      ['mild'],
      'Golden Week bitmiş, hava hâlâ taze. En sakin ve hoş dönemlerden.'),
  SuggestedRange(
      'oct-2027',
      'Ekim 2027 — Sonbahar',
      '2027-10-12',
      '2027-10-25',
      SeasonTone.good,
      ['mild', 'autumn'],
      'Tekrar harika hava. Tayfun riski azalmış.'),
];

class AvoidRange {
  const AvoidRange(this.id, this.label, this.startISO, this.endISO, this.badges,
      this.reason);
  final String id;
  final String label;
  final String startISO;
  final String endISO;
  final List<String> badges;
  final String reason;
}

const List<AvoidRange> kAvoidRanges = [
  AvoidRange(
      'tsuyu-2026',
      'Haziran 2. hafta - Temmuz ortası',
      '2026-06-15',
      '2026-07-20',
      ['tsuyu'],
      'Tsuyu — neredeyse her gün yağmur. Şehir & açık hava gezisi zor.'),
  AvoidRange(
      'obon-2026',
      'Obon haftası (Ağustos)',
      '2026-08-13',
      '2026-08-17',
      ['holiday', 'heat'],
      'Yerel tatil — trenler, oteller, restoranlar çok yoğun.'),
  AvoidRange(
      'typhoon-2026',
      'Eylül — tayfun zirvesi',
      '2026-09-01',
      '2026-09-30',
      ['typhoon'],
      'Sezonun en riskli ayı. Uçuş & tren iptalleri sık görülür.'),
  AvoidRange(
      'newyear-2027',
      'Yeni yıl (28 Ara - 4 Oca)',
      '2026-12-28',
      '2027-01-04',
      ['holiday', 'cold'],
      'Yerel tatil — birçok mağaza/restoran kapalı, tapınaklar tıka basa.'),
  AvoidRange(
      'goldenweek-2027',
      'Golden Week (Nisan sonu - Mayıs başı)',
      '2027-04-29',
      '2027-05-06',
      ['holiday'],
      'Yılın en yoğun yerel tatil haftası. Otel fiyatları 2-3 katına çıkar.'),
];
