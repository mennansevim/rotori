/**
 * index.html içindeki .day-card bloklarını JSON'a çıkarır.
 * Kullanım: npm run migrate
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tripSchema } from '../packages/shared/src/schema.js';
import { parseStepsFromText } from '../packages/shared/src/dates.js';
import type { DayPlan, TimelineItem, Trip } from '../packages/shared/src/types.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const htmlPath = join(root, 'index.html');
const outDir = join(root, 'data', 'trips');
const outPath = join(outDir, 'sevimm-japan-2026.json');

const html = readFileSync(htmlPath, 'utf8');

const MONTHS: Record<string, string> = {
  Ocak: '01',
  Şubat: '02',
  Mart: '03',
  Nisan: '04',
  Mayıs: '05',
  Haziran: '06',
  Temmuz: '07',
  Ağustos: '08',
  Eylül: '09',
  Ekim: '10',
  Kasım: '11',
  Aralık: '12',
};

function parseTurkishDate(text: string): string | null {
  const m = text.match(/(\d{1,2})\s+(\w+)\s+2026/);
  if (!m) return null;
  const day = m[1].padStart(2, '0');
  const month = MONTHS[m[2]];
  if (!month) return null;
  return `2026-${month}-${day}`;
}

function stripHtml(s: string): string {
  return s
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&nbsp;/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function extractDays(source: string): DayPlan[] {
  const cardRe =
    /<!-- Day \d+[^>]*-->\s*<div class="day-card"[^>]*data-date="([^"]+)"[^>]*>([\s\S]*?)(?=<!-- Day \d+|<\/section>)/g;
  const days: DayPlan[] = [];
  let match: RegExpExecArray | null;
  let dayNum = 0;

  while ((match = cardRe.exec(source)) !== null) {
    dayNum += 1;
    const [, dataDate, block] = match;
    const themeM = block.match(/class="day-theme">([^<]+)/);
    const dateM = block.match(/class="day-date">([^<]+)/);
    const theme = themeM ? stripHtml(themeM[1]) : `Gün ${dayNum}`;
    const date = dataDate || (dateM ? parseTurkishDate(dateM[1]) : null) || '';

    const tags: string[] = [];
    const tagRe = /class="tag[^"]*">([^<]+)/g;
    let tm: RegExpExecArray | null;
    while ((tm = tagRe.exec(block)) !== null) {
      tags.push(stripHtml(tm[1]));
    }

    const routeM = block.match(/class="day-route-link" href="([^"]+)"/);
    const stepsM = block.match(/class="day-steps-est"[^>]*>([\s\S]*?)<\/span>/);
    let stepsEstimate: number | undefined;
    let stepsEstimateMax: number | undefined;
    if (stepsM) {
      const parsed = parseStepsFromText(stripHtml(stepsM[1]));
      stepsEstimate = parsed.min;
      stepsEstimateMax = parsed.max;
    }

    const items: TimelineItem[] = [];
    const itemRe =
      /<div class="timeline-item">([\s\S]*?)<\/div>\s*(?=<div class="timeline-item">|<div class="highlight-card">|<\/div>\s*<\/div>\s*<\/div>\s*<\/div>\s*<\/div>)/g;
    let im: RegExpExecArray | null;
    let itemIdx = 0;
    while ((im = itemRe.exec(block)) !== null) {
      const chunk = im[1];
      const timeM = chunk.match(/class="timeline-time">([^<]+)/);
      const titleM = chunk.match(/class="timeline-title">(?:<a[^>]*>)?([^<]+)/);
      const descM = chunk.match(/class="timeline-desc">([\s\S]*?)<\/div>/);
      const mapM = chunk.match(/class="timeline-title"><a href="([^"]+)"/);
      const tipsM = chunk.match(/class="timeline-tips">([\s\S]*?)<\/p>/);
      if (!titleM) continue;
      itemIdx += 1;
      items.push({
        id: `d${dayNum}-i${itemIdx}`,
        time: timeM ? stripHtml(timeM[1]) : undefined,
        title: stripHtml(titleM[1]),
        description: descM ? stripHtml(descM[1]) : undefined,
        mapUrl: mapM?.[1],
        tips: tipsM ? stripHtml(tipsM[1]) : undefined,
      });
    }

    const highlights: { title: string; body: string }[] = [];
    const hiRe =
      /<div class="highlight-card">\s*<h4>([^<]+)<\/h4>\s*<p>([\s\S]*?)<\/p>/g;
    let hm: RegExpExecArray | null;
    while ((hm = hiRe.exec(block)) !== null) {
      highlights.push({
        title: stripHtml(hm[1]),
        body: stripHtml(hm[2]),
      });
    }

    days.push({
      dayNumber: dayNum,
      date,
      theme,
      tags,
      stepsEstimate,
      stepsEstimateMax,
      taxiRecommended: theme.toLowerCase().includes('disney'),
      route: routeM ? { mapsUrl: routeM[1].replace(/&amp;/g, '&') } : undefined,
      items,
      highlights: highlights.length ? highlights : undefined,
    });
  }

  return days;
}

const extractedDays = extractDays(html);

const baseTrip: Trip = {
  id: 'sevimm-japan-2026',
  slug: 'sevimm-japan-2026',
  title: '日本 2026',
  subtitle: "Tokyo'dan Osaka'ya unutulmaz bir Japonya macerası",
  timezone: 'Asia/Tokyo',
  tripStart: '2026-05-13T16:00:00+03:00',
  tripEnd: '2026-05-27T06:15:00+03:00',
  flights: {
    outbound: [
      { city: 'İstanbul', airport: 'IST', dateTime: '2026-05-13T16:00:00+03:00' },
      { city: 'Tokyo', airport: 'HND', dateTime: '2026-05-14T19:45:00+09:00' },
    ],
    return: [
      { city: 'Osaka', airport: 'KIX', dateTime: '2026-05-26T14:40:00+09:00' },
      { city: 'İstanbul', airport: 'IST', dateTime: '2026-05-27T06:15:00+03:00' },
    ],
  },
  hotels: [
    {
      id: 'tokyo-ikebukuro',
      city: 'Tokyo',
      name: 'Hotel Grand City Ikebukuro',
      checkIn: '2026-05-14',
      checkOut: '2026-05-20',
      addressJa: 'ホテルグランドシティ池袋',
    },
    {
      id: 'osaka-namba',
      city: 'Osaka',
      name: 'Namba area hotel',
      checkIn: '2026-05-20',
      checkOut: '2026-05-26',
    },
  ],
  tickets: [
    {
      id: 'skytree',
      kind: 'attraction',
      label: 'Tokyo Skytree',
      visitDate: '2026-05-15',
      bookingOpens: '2026-04-15',
      purchased: true,
      emoji: '🗼',
    },
    {
      id: 'disney',
      kind: 'theme-park',
      label: 'Tokyo Disneyland',
      visitDate: '2026-05-19',
      purchased: true,
      emoji: '🏰',
    },
    {
      id: 'teamlab',
      kind: 'museum',
      label: 'teamLab Planets',
      visitDate: '2026-05-17',
      purchased: true,
      emoji: '🪐',
    },
    {
      id: 'usj',
      kind: 'theme-park',
      label: 'Universal Studios Japan',
      visitDate: '2026-05-21',
      purchased: true,
      emoji: '🎢',
    },
    {
      id: 'shinkansen',
      kind: 'train',
      label: 'Shinkansen Tokyo → Osaka',
      visitDate: '2026-05-20',
      purchased: false,
      url: 'https://smart-ex.jp/en/',
      emoji: '🚄',
    },
  ],
  preferences: {
    travelDates: { start: '2026-05-14', end: '2026-05-26' },
    mustSee: [
      'Meiji Jingu',
      'Senso-ji',
      'Tokyo Skytree',
      'Fushimi Inari',
      'Nara geyikleri',
      'Dotonbori',
    ],
    foodLikes: ['ramen', 'sushi', 'takoyaki', 'matcha'],
    foodDislikes: [],
    dietary: [],
    mealBudgetJpyPerPerson: 2500,
    planMeals: true,
    maxStepsPerDay: 16000,
    pace: 'moderate',
    partySize: 2,
  },
  deadlines: {
    shinkansenBooking: '2026-04-20T00:00:00+03:00',
    skytreeVisit: '2026-05-15T23:59:59+09:00',
    skytreeBookingOpens: '2026-04-15T00:00:00+09:00',
  },
  days: extractedDays.length >= 13 ? extractedDays : [],
};

if (baseTrip.days.length < 13) {
  console.warn(
    `Uyarı: yalnızca ${baseTrip.days.length} gün çıkarıldı; mevcut JSON korunuyor veya elle tamamlayın.`,
  );
}

const parsed = tripSchema.safeParse(baseTrip);
if (!parsed.success) {
  console.error(parsed.error.format());
  process.exit(1);
}

mkdirSync(outDir, { recursive: true });
writeFileSync(outPath, JSON.stringify(parsed.data, null, 2), 'utf8');
console.log(`Yazıldı: ${outPath} (${parsed.data.days.length} gün)`);
