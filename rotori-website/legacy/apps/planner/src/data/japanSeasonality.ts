/** Japonya seyahatinde aylık kabaca koşullar — Welcome ekranı içeriği. */

export type SeasonTag =
  | 'sakura'
  | 'autumn'
  | 'tsuyu'
  | 'typhoon'
  | 'heat'
  | 'cold'
  | 'snow'
  | 'mild'
  | 'holiday';

export interface SeasonBadge {
  tag: SeasonTag;
  emoji: string;
  label: string;
  tone: 'good' | 'warn' | 'bad' | 'info';
}

export const BADGES: Record<SeasonTag, SeasonBadge> = {
  sakura: { tag: 'sakura', emoji: '🌸', label: 'Sakura', tone: 'good' },
  autumn: { tag: 'autumn', emoji: '🍁', label: 'Sonbahar yaprakları', tone: 'good' },
  tsuyu: { tag: 'tsuyu', emoji: '🌧️', label: 'Muson (tsuyu)', tone: 'bad' },
  typhoon: { tag: 'typhoon', emoji: '🌀', label: 'Tayfun riski', tone: 'bad' },
  heat: { tag: 'heat', emoji: '🥵', label: 'Aşırı sıcak & nem', tone: 'warn' },
  cold: { tag: 'cold', emoji: '🥶', label: 'Soğuk', tone: 'info' },
  snow: { tag: 'snow', emoji: '❄️', label: 'Kar (kuzey)', tone: 'info' },
  mild: { tag: 'mild', emoji: '🌤️', label: 'Hoş hava', tone: 'good' },
  holiday: { tag: 'holiday', emoji: '🎌', label: 'Yerel tatil — çok yoğun', tone: 'warn' },
};

export interface SeasonMonth {
  month: number;
  label: string;
  tags: SeasonTag[];
  note: string;
}

export const MONTHS: SeasonMonth[] = [
  { month: 1, label: 'Ocak', tags: ['cold', 'snow'], note: 'Kuzeyde kar, güneyde temiz hava. Yeni yıl haftası (1-3 Oca) yoğun ve birçok yer kapalı.' },
  { month: 2, label: 'Şubat', tags: ['cold', 'snow'], note: 'Sapporo kar festivali. Genelde sakin ve ucuz.' },
  { month: 3, label: 'Mart', tags: ['mild', 'sakura'], note: 'Son hafta sakura başlangıcı (Tokyo). Hızla doluyor.' },
  { month: 4, label: 'Nisan', tags: ['sakura', 'mild'], note: 'Sakura zirvesi ilk 2 hafta. Çok güzel ama çok kalabalık + pahalı.' },
  { month: 5, label: 'Mayıs', tags: ['mild', 'holiday'], note: 'Golden Week (29 Nis - 5 May) çok yoğun. Ortadan sonu en hoş dönem.' },
  { month: 6, label: 'Haziran', tags: ['tsuyu'], note: '2. haftadan itibaren tsuyu (muson) yağmurları. Önerilmez.' },
  { month: 7, label: 'Temmuz', tags: ['tsuyu', 'heat'], note: 'İlk yarı muson devam, ikinci yarı aşırı sıcak. Şehir gezmek zor.' },
  { month: 8, label: 'Ağustos', tags: ['heat', 'typhoon', 'holiday'], note: 'En sıcak & nemli ay. Obon (13-17 Ağu) yerel tatil — her yer dolu.' },
  { month: 9, label: 'Eylül', tags: ['typhoon', 'heat'], note: 'Tayfun sezonunun zirvesi. Hava aşağı doğru iyileşir.' },
  { month: 10, label: 'Ekim', tags: ['mild', 'autumn'], note: 'Hava harika, ilk sonbahar renkleri (kuzey). En önerilen aylardan.' },
  { month: 11, label: 'Kasım', tags: ['autumn', 'mild'], note: 'Sonbahar yapraklarının zirvesi. Serin, kuru, çok güzel.' },
  { month: 12, label: 'Aralık', tags: ['cold', 'holiday'], note: 'Şehirler ışıklı, sakin. 28 Ara - 4 Oca yeni yıl tatili — kalabalık & kapalılar.' },
];

export interface SuggestedRange {
  id: string;
  label: string;
  startISO: string;
  endISO: string;
  tone: 'good' | 'warn' | 'bad';
  badges: SeasonTag[];
  reason: string;
}

/** Today's date is 2026-06-15 — futureden başlayan, sıralı öneriler. */
export const SUGGESTED_RANGES: SuggestedRange[] = [
  {
    id: 'oct-2026',
    label: 'Ekim 2026 — Sonbahar başlangıcı',
    startISO: '2026-10-15',
    endISO: '2026-10-28',
    tone: 'good',
    badges: ['mild', 'autumn'],
    reason: 'Hava ideal, ilk sonbahar renkleri. Tayfun riski geçmiş.',
  },
  {
    id: 'nov-2026',
    label: 'Kasım 2026 — Yaprak zirvesi',
    startISO: '2026-11-08',
    endISO: '2026-11-21',
    tone: 'good',
    badges: ['autumn', 'mild'],
    reason: 'Kyoto & Tokyo sonbahar renklerinin en güzel olduğu dönem. Serin, kuru.',
  },
  {
    id: 'feb-2027',
    label: 'Şubat 2027 — Sakin & ucuz',
    startISO: '2027-02-08',
    endISO: '2027-02-21',
    tone: 'good',
    badges: ['cold', 'snow'],
    reason: 'Soğuk ama temiz. Otel fiyatları düşük, turist az. Sapporo kar festivali bonus.',
  },
  {
    id: 'sakura-2027',
    label: 'Mart-Nisan 2027 — Sakura',
    startISO: '2027-03-25',
    endISO: '2027-04-07',
    tone: 'warn',
    badges: ['sakura'],
    reason: 'Sakura zirvesi — çok güzel ama çok kalabalık. Otelleri 6 ay önceden ayır.',
  },
  {
    id: 'may-2027',
    label: 'Mayıs 2027 — Golden Week sonrası',
    startISO: '2027-05-10',
    endISO: '2027-05-23',
    tone: 'good',
    badges: ['mild'],
    reason: 'Golden Week bitmiş, hava hâlâ taze. En sakin ve hoş dönemlerden.',
  },
  {
    id: 'oct-2027',
    label: 'Ekim 2027 — Sonbahar',
    startISO: '2027-10-12',
    endISO: '2027-10-25',
    tone: 'good',
    badges: ['mild', 'autumn'],
    reason: 'Tekrar harika hava. Tayfun riski azalmış.',
  },
];

/** Önerilmeyen pencereler — kullanıcıya gösterilir, "neden" anlatılır. */
export interface AvoidRange {
  id: string;
  label: string;
  startISO: string;
  endISO: string;
  badges: SeasonTag[];
  reason: string;
}

export const AVOID_RANGES: AvoidRange[] = [
  {
    id: 'tsuyu-2026',
    label: 'Haziran 2. hafta - Temmuz ortası',
    startISO: '2026-06-15',
    endISO: '2026-07-20',
    badges: ['tsuyu'],
    reason: 'Tsuyu — neredeyse her gün yağmur. Şehir & açık hava gezisi zor.',
  },
  {
    id: 'obon-2026',
    label: 'Obon haftası (Ağustos)',
    startISO: '2026-08-13',
    endISO: '2026-08-17',
    badges: ['holiday', 'heat'],
    reason: 'Yerel tatil — trenler, oteller, restoranlar çok yoğun.',
  },
  {
    id: 'typhoon-2026',
    label: 'Eylül — tayfun zirvesi',
    startISO: '2026-09-01',
    endISO: '2026-09-30',
    badges: ['typhoon'],
    reason: 'Sezonun en riskli ayı. Uçuş & tren iptalleri sık görülür.',
  },
  {
    id: 'newyear-2027',
    label: 'Yeni yıl (28 Ara - 4 Oca)',
    startISO: '2026-12-28',
    endISO: '2027-01-04',
    badges: ['holiday', 'cold'],
    reason: 'Yerel tatil — birçok mağaza/restoran kapalı, tapınaklar tıka basa.',
  },
  {
    id: 'goldenweek-2027',
    label: 'Golden Week (Nisan sonu - Mayıs başı)',
    startISO: '2027-04-29',
    endISO: '2027-05-06',
    badges: ['holiday'],
    reason: 'Yılın en yoğun yerel tatil haftası. Otel fiyatları 2-3 katına çıkar.',
  },
];
