import type { DayPlan } from '@japan-trip/shared';

interface Props {
  days: DayPlan[];
  activeDayNumber: number | null;
  onSelectDay: (dayNumber: number) => void;
}

const WEEKDAYS = ['PZT', 'SAL', 'ÇAR', 'PER', 'CUM', 'CMT', 'PAZ'];

function dayOfWeekMondayBased(iso: string): number {
  const d = new Date(iso + 'T12:00:00');
  const js = d.getDay(); // 0=Sunday
  return (js + 6) % 7;
}

function monthLabel(iso: string): string {
  const d = new Date(iso + 'T12:00:00');
  return d.toLocaleDateString('tr-TR', { month: 'long', year: 'numeric' });
}

interface CalendarCell {
  date: string;
  day?: DayPlan;
  inMonth: boolean;
  isFiller: boolean;
}

function buildWeeks(days: DayPlan[]): { month: string; cells: CalendarCell[] }[] {
  if (days.length === 0) return [];
  const sorted = [...days].sort((a, b) => a.date.localeCompare(b.date));
  const byDate = new Map(sorted.map((d) => [d.date, d]));
  const start = sorted[0].date;
  const end = sorted[sorted.length - 1].date;

  // Trip ay/yıl gruplandırması yerine sade haftalık tablo:
  // baş haftanın pazartesisinden son haftanın pazarına kadar.
  const startDate = new Date(start + 'T12:00:00');
  const endDate = new Date(end + 'T12:00:00');
  const startWeekStart = new Date(startDate);
  startWeekStart.setDate(startWeekStart.getDate() - dayOfWeekMondayBased(start));
  const endWeekEnd = new Date(endDate);
  endWeekEnd.setDate(endWeekEnd.getDate() + (6 - dayOfWeekMondayBased(end)));

  const groups: { month: string; cells: CalendarCell[] }[] = [];
  let currentGroupKey = '';
  let currentCells: CalendarCell[] = [];

  for (
    let cur = new Date(startWeekStart);
    cur <= endWeekEnd;
    cur.setDate(cur.getDate() + 1)
  ) {
    const iso = cur.toISOString().slice(0, 10);
    const monthKey = iso.slice(0, 7);
    if (monthKey !== currentGroupKey) {
      if (currentCells.length > 0) groups.push({ month: monthLabel(currentCells[0].date), cells: currentCells });
      currentGroupKey = monthKey;
      currentCells = [];
    }
    const day = byDate.get(iso);
    currentCells.push({
      date: iso,
      day,
      inMonth: iso >= start && iso <= end,
      isFiller: !day,
    });
  }
  if (currentCells.length > 0) groups.push({ month: monthLabel(currentCells[0].date), cells: currentCells });

  return groups;
}

function themeEmoji(theme: string | undefined): string {
  if (!theme) return '·';
  const m = theme.match(/^(\p{Emoji}|\p{Emoji_Presentation}|[\p{Emoji}‍]+)/u);
  return m ? m[1] : theme.slice(0, 1);
}

export function CalendarView({ days, activeDayNumber, onSelectDay }: Props) {
  const groups = buildWeeks(days);

  if (groups.length === 0) return null;

  return (
    <div className="calendar-view">
      {groups.map((group) => (
        <div key={group.month} className="calendar-month">
          <div className="calendar-month-title">{group.month}</div>
          <div className="calendar-grid calendar-grid-head">
            {WEEKDAYS.map((w) => (
              <div key={w} className="calendar-head-cell">
                {w}
              </div>
            ))}
          </div>
          <div className="calendar-grid">
            {group.cells.map((cell, i) => {
              const day = cell.day;
              const dayN = day?.dayNumber;
              const isActive = dayN != null && dayN === activeDayNumber;
              const dayOfMonth = Number(cell.date.slice(-2));
              return (
                <button
                  key={i}
                  type="button"
                  className={`calendar-cell${day ? ' has-day' : ' empty'}${
                    isActive ? ' active' : ''
                  }`}
                  disabled={!day}
                  onClick={() => day && onSelectDay(day.dayNumber)}
                  title={day?.theme}
                >
                  <div className="calendar-cell-head">
                    <span className="calendar-date">{dayOfMonth}</span>
                    {day && <span className="calendar-day-num">G{day.dayNumber}</span>}
                  </div>
                  {day && (
                    <>
                      <div className="calendar-emoji" aria-hidden>
                        {themeEmoji(day.theme)}
                      </div>
                      <div className="calendar-theme">
                        {(day.theme || '').replace(/^(\p{Emoji}|\p{Emoji_Presentation}|[\p{Emoji}‍]+)\s*/u, '')}
                      </div>
                      {day.tags?.length > 0 && (
                        <div className="calendar-tags">
                          {day.tags.slice(0, 2).map((t) => (
                            <span key={t}>{t}</span>
                          ))}
                        </div>
                      )}
                    </>
                  )}
                </button>
              );
            })}
          </div>
        </div>
      ))}
    </div>
  );
}
