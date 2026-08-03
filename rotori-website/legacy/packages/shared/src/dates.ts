export function formatDateInTimeZone(date: Date, timeZone: string): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const y = parts.find((p) => p.type === 'year')?.value ?? '0000';
  const m = parts.find((p) => p.type === 'month')?.value ?? '01';
  const d = parts.find((p) => p.type === 'day')?.value ?? '01';
  return `${y}-${m}-${d}`;
}

export function parseStepsFromText(text: string): {
  min?: number;
  max?: number;
} {
  const nums = [...text.matchAll(/([\d.]+)\s*(?:–|-)?\s*([\d.]+)?/g)]
    .flatMap((m) => [m[1], m[2]].filter(Boolean))
    .map((n) => Number(n.replace(/\./g, '')));
  const cleaned = nums.filter((n) => n >= 1000 && n <= 50000);
  if (!cleaned.length) return {};
  return {
    min: Math.min(...cleaned),
    max: cleaned.length > 1 ? Math.max(...cleaned) : undefined,
  };
}

export function getActiveDayIndex(days: { date: string }[], timeZone: string): number {
  const today = formatDateInTimeZone(new Date(), timeZone);
  const sorted = [...days].sort((a, b) => a.date.localeCompare(b.date));
  const exact = sorted.findIndex((d) => d.date === today);
  if (exact >= 0) return exact;
  const future = sorted.findIndex((d) => d.date >= today);
  return future >= 0 ? future : sorted.length - 1;
}

export function tripPhase(
  tripStart: string,
  tripEnd: string,
  now = new Date(),
): 'before' | 'during' | 'after' {
  const start = new Date(tripStart);
  const end = new Date(tripEnd);
  if (now < start) return 'before';
  if (now > end) return 'after';
  return 'during';
}
