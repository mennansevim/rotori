import { useEffect, useMemo, useState } from 'react';
import {
  getActiveDayIndex,
  getRouteLegs,
  ensureTripGuide,
  ensureTripDestinations,
  ensureTripPreferences,
  tripSchema,
  formatRouteChain,
  tripPhase,
} from '@japan-trip/shared';
import type { Trip } from '@japan-trip/shared';
import { CountdownBar } from './components/CountdownBar';
import { DayCard } from './components/DayCard';
import { TripGuideSections } from './components/TripGuideSections';
import { SettingsDrawer, type ThemeId } from './components/SettingsDrawer';
import { QuickReference } from './components/QuickReference';
import { Pusula } from './components/Pusula';
import { PreJapanGuide } from './components/PreJapanGuide';
import { EditModal } from './components/EditModal';
import { MorningSummary } from './components/MorningSummary';
import { WeatherStrip } from './components/WeatherStrip';
import { CalendarView } from './components/CalendarView';
import { RewardsPanel } from './components/RewardsPanel';
import { CommunityBeta } from './components/CommunityBeta';
import {
  loadStats,
  saveStats,
  recordAction,
  evaluatePassive,
  setCommunity as applyCommunity,
} from './utils/userStats';
import type { UserStats, BadgeDefinition } from '@japan-trip/shared';

const VALID_THEMES: ThemeId[] = ['japan-dark', 'apple-light', 'sakura-soft'];
const DEFAULT_THEME: ThemeId = 'japan-dark';

type DayView = 'flow' | 'calendar';
const VALID_DAY_VIEWS: DayView[] = ['flow', 'calendar'];

function loadStoredDayView(username: string): DayView {
  if (typeof window === 'undefined') return 'flow';
  const raw = localStorage.getItem(`viewer:dayView:${username}`);
  if (raw && (VALID_DAY_VIEWS as string[]).includes(raw)) return raw as DayView;
  return 'flow';
}

function getUsername(): string {
  if (typeof window === 'undefined') return 'default';
  const params = new URLSearchParams(window.location.search);
  const u = params.get('u') || params.get('trip');
  if (u && /^[a-zA-Z0-9_-]{1,32}$/.test(u)) return u;
  const stored = localStorage.getItem('trip:lastUser');
  if (stored && /^[a-zA-Z0-9_-]{1,32}$/.test(stored)) return stored;
  return 'default';
}

function loadStoredTheme(): ThemeId {
  if (typeof window === 'undefined') return DEFAULT_THEME;
  const v = localStorage.getItem('viewer:theme');
  if (v && (VALID_THEMES as string[]).includes(v)) return v as ThemeId;
  return DEFAULT_THEME;
}

function loadTrip(username: string): Trip | null {
  if (typeof window === 'undefined') return null;
  // Önce kullanıcı bazlı aktif
  const candidates = [
    `trip:active:${username}`,
    // Legacy global key
    'trip:draft:active',
  ];
  // Ayrıca slug bazlı `trip:user:${username}:*` keylerini de tarayabiliriz
  for (const key of candidates) {
    const raw = localStorage.getItem(key);
    if (!raw) continue;
    try {
      return ensureTripGuide(
        ensureTripPreferences(ensureTripDestinations(tripSchema.parse(JSON.parse(raw)))),
      );
    } catch {
      /* ignore */
    }
  }
  return null;
}

function dayCount(trip: Trip): number {
  return trip.days?.length ?? 0;
}

function totalNights(trip: Trip): number {
  return (trip.hotels ?? []).reduce((s, h) => {
    try {
      const diff = new Date(h.checkOut).getTime() - new Date(h.checkIn).getTime();
      return s + Math.max(0, Math.round(diff / 86400000));
    } catch {
      return s;
    }
  }, 0);
}

function formatDate(s: string): string {
  if (!s) return '';
  try {
    const d = new Date(s);
    return d.toLocaleDateString('tr-TR', { day: 'numeric', month: 'long', year: 'numeric' });
  } catch {
    return s;
  }
}

function formatDateShort(s: string): string {
  if (!s) return '';
  try {
    const d = new Date(s);
    return d.toLocaleDateString('tr-TR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
  } catch {
    return s;
  }
}

export default function App() {
  const username = useMemo(() => getUsername(), []);
  const [trip, setTrip] = useState<Trip | null>(null);
  const [expanded, setExpanded] = useState<Record<number, boolean>>({});
  const [theme, setTheme] = useState<ThemeId>(loadStoredTheme);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [editOpen, setEditOpen] = useState(false);
  const [toast, setToast] = useState<string | null>(null);
  const [morningDismissed, setMorningDismissed] = useState<string | null>(null);
  const [editInitial, setEditInitial] = useState<{ instruction?: string; weather?: string } | null>(
    null,
  );
  const [stats, setStats] = useState<UserStats>(() => loadStats(username));
  const [badgeToast, setBadgeToast] = useState<BadgeDefinition | null>(null);
  const [dayView, setDayViewState] = useState<DayView>(() => loadStoredDayView(username));

  const setDayView = (v: DayView) => {
    setDayViewState(v);
    try {
      localStorage.setItem(`viewer:dayView:${username}`, v);
    } catch {
      /* ignore */
    }
  };

  const announceBadges = (badges: BadgeDefinition[]) => {
    if (badges.length === 0) return;
    setBadgeToast(badges[0]);
    window.setTimeout(() => setBadgeToast((b) => (b === badges[0] ? null : b)), 4500);
  };

  const updateStats = (next: UserStats, newBadges: BadgeDefinition[]) => {
    setStats(next);
    saveStats(username, next);
    announceBadges(newBadges);
  };

  const persistTrip = (next: Trip) => {
    setTrip(next);
    try {
      localStorage.setItem(`trip:active:${username}`, JSON.stringify(next));
    } catch {
      /* ignore quota errors */
    }
  };

  const showToast = (msg: string) => {
    setToast(msg);
    window.setTimeout(() => setToast((m) => (m === msg ? null : m)), 4200);
  };

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('viewer:theme', theme);
  }, [theme]);

  useEffect(() => {
    const t = loadTrip(username);
    setTrip(t);
    try {
      const k = `viewer:morning-dismissed:${username}`;
      setMorningDismissed(localStorage.getItem(k));
    } catch {
      /* ignore */
    }
    if (t) {
      const initial = loadStats(username);
      // İlk plan açılışında "plan-created" sayacını da yükselt (idempotent).
      if ((initial.actionCounts['plan-created'] ?? 0) === 0) {
        const { next, newBadges } = recordAction(initial, 'plan-created', t);
        updateStats(next, newBadges);
      } else {
        const { next, newBadges } = evaluatePassive(initial, t);
        updateStats(next, newBadges);
      }
    }
    // updateStats stable enough; suppress dep warning
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [username]);

  const activeIndex = useMemo(
    () => (trip ? getActiveDayIndex(trip.days, trip.timezone) : 0),
    [trip],
  );

  useEffect(() => {
    if (!trip) return;
    // Sadece aktif gün varsayılan açık; diğerleri kapalı.
    const dayNum = trip.days[activeIndex]?.dayNumber;
    if (dayNum != null) {
      setExpanded({ [dayNum]: true });
    }
  }, [trip, activeIndex]);

  if (!trip) {
    return (
      <>
        <CountdownBar
          trip={{
            id: 'empty', slug: 'empty', title: 'Yeni plan',
            timezone: 'UTC', tripStart: '', tripEnd: '',
            flights: { outbound: [], return: [] },
            hotels: [], tickets: [],
            preferences: {
              travelDates: { start: '', end: '' },
              mustSee: [], foodLikes: [], foodDislikes: [],
              pace: 'moderate',
            },
            days: [],
          }}
          onOpenSettings={() => setSettingsOpen(true)}
          username={username}
        />
        <div className="empty-state">
          <h2>Henüz bir plan yok</h2>
          <p>
            Planlayıcıya geçip kendi seyahatini oluşturabilirsin. Plan oluşturduğunda{' '}
            <code>?u={username}</code> bağlantınla burada görünür.
          </p>
          <a className="btn" href={`/planner/?u=${encodeURIComponent(username)}`}>
            🎌 Planlayıcıyı aç
          </a>
        </div>
      </>
    );
  }

  const phase = (trip.tripStart && trip.tripEnd) ? tripPhase(trip.tripStart, trip.tripEnd) : 'before';
  const days = trip.days ?? [];
  const routeChain = getRouteLegs(trip);
  const totalDays = dayCount(trip);
  const nights = totalNights(trip);

  const outbound = trip.flights?.outbound?.[0];
  const ret = trip.flights?.return?.[0];

  const dests = (trip.preferences.destinations ?? []).slice().sort((a, b) => a.order - b.order);

  return (
    <>
      <CountdownBar
        trip={trip}
        onOpenSettings={() => setSettingsOpen(true)}
        username={username}
      />

      <header className="header">
        {(totalDays > 0 || nights > 0) && (
          <div className="header-badge">
            <span>✈️</span>
            <span>
              {totalDays} Gün{nights > 0 ? ` · ${nights} Gece` : ''}
            </span>
          </div>
        )}
        <h1>{trip.title || 'İsimsiz Seyahat'}</h1>
        {trip.subtitle && <p className="header-subtitle">{trip.subtitle}</p>}
        {!trip.subtitle && routeChain.length > 0 && (
          <p className="header-subtitle">{formatRouteChain(routeChain)}</p>
        )}

        {(outbound || ret) && (
          <div className="flight-info">
            {outbound && (
              <div className="flight-route">
                <div>
                  <div className="city">{outbound.city} ({outbound.airport})</div>
                  <div className="date">{formatDateShort(outbound.dateTime)}</div>
                </div>
                <span className="arrow">→</span>
                <div>
                  <div className="city">{dests[0]?.city || dests[0]?.countryName || '—'}</div>
                  <div className="date">{formatDate(trip.tripStart)}</div>
                </div>
              </div>
            )}
            {ret && (
              <div className="flight-route">
                <div>
                  <div className="city">{ret.city} ({ret.airport})</div>
                  <div className="date">{formatDateShort(ret.dateTime)}</div>
                </div>
                <span className="arrow">→</span>
                <div>
                  <div className="city">{outbound?.city || 'Eve dönüş'}</div>
                  <div className="date">{formatDate(trip.tripEnd)}</div>
                </div>
              </div>
            )}
          </div>
        )}
      </header>

      {(totalDays > 0 || nights > 0 || trip.tickets.length > 0) && (
        <div className="stats-bar">
          {nights > 0 && (
            <div className="stat-card">
              <div className="stat-icon">🏨</div>
              <div className="stat-value">{nights}</div>
              <div className="stat-label">Gece Konaklama</div>
            </div>
          )}
          {dests.slice(0, 3).map((d) => {
            // O destinasyona ait gece sayısı
            const cityNights = (trip.hotels ?? [])
              .filter((h) => (h.city || '').toLowerCase().includes((d.city || '').toLowerCase()))
              .reduce((s, h) => {
                try {
                  return s + Math.max(0, Math.round((new Date(h.checkOut).getTime() - new Date(h.checkIn).getTime()) / 86400000));
                } catch {
                  return s;
                }
              }, 0);
            if (cityNights === 0) return null;
            return (
              <div className="stat-card" key={d.id}>
                <div className="stat-icon">📍</div>
                <div className="stat-value">{cityNights}</div>
                <div className="stat-label">{d.city || d.countryName}</div>
              </div>
            );
          })}
          {trip.tickets.length > 0 && (
            <div className="stat-card">
              <div className="stat-icon">🎫</div>
              <div className="stat-value">{trip.tickets.length}</div>
              <div className="stat-label">Bilet</div>
            </div>
          )}
          {totalDays > 0 && (
            <div className="stat-card">
              <div className="stat-icon">📅</div>
              <div className="stat-value">{totalDays}</div>
              <div className="stat-label">Toplam Gün</div>
            </div>
          )}
        </div>
      )}

      {(() => {
        const activeDay = days[activeIndex];
        if (!activeDay || phase !== 'during') return null;
        const localHour = (() => {
          try {
            return Number(
              new Intl.DateTimeFormat('en-US', {
                timeZone: trip.timezone,
                hour: '2-digit',
                hour12: false,
              }).format(new Date()),
            );
          } catch {
            return new Date().getHours();
          }
        })();
        const inMorningWindow = localHour >= 6 && localHour < 12;
        const dismissKey = `${activeDay.dayNumber}:${activeDay.date}`;
        const isDismissed = morningDismissed === dismissKey;
        if (!inMorningWindow || isDismissed) return null;
        return (
          <main className="app-container app-container-banner">
            <MorningSummary
              day={activeDay}
              prefs={trip.preferences}
              visible
              onEdit={() => {
                setEditOpen(true);
              }}
              onDismiss={() => {
                setMorningDismissed(dismissKey);
                try {
                  localStorage.setItem(`viewer:morning-dismissed:${username}`, dismissKey);
                } catch {
                  /* ignore */
                }
              }}
            />
          </main>
        );
      })()}

      <main className="app-container">
        {days.length > 0 ? (
          <section className="section">
            <div className="section-header">
              <div className="section-icon">🗓️</div>
              <div>
                <h2 className="section-title">Günlük Plan</h2>
                <div className="section-subtitle">Gün üstüne tıklayınca açılır</div>
              </div>
              {phase === 'before' && (
                <span className="section-badge">{totalDays} gün</span>
              )}
              <div className="day-view-toggle" role="tablist" aria-label="Görünüm">
                <button
                  type="button"
                  role="tab"
                  aria-selected={dayView === 'flow'}
                  className={`day-view-btn${dayView === 'flow' ? ' active' : ''}`}
                  onClick={() => setDayView('flow')}
                >
                  📋 Akış
                </button>
                <button
                  type="button"
                  role="tab"
                  aria-selected={dayView === 'calendar'}
                  className={`day-view-btn${dayView === 'calendar' ? ' active' : ''}`}
                  onClick={() => setDayView('calendar')}
                >
                  📅 Takvim
                </button>
              </div>
            </div>

            <WeatherStrip
              trip={trip}
              activeDayNumber={days[activeIndex]?.dayNumber ?? null}
              onReplan={(instruction, weather) => {
                setEditInitial({ instruction, weather });
                setEditOpen(true);
                const { next, newBadges } = recordAction(stats, 'weather-replan', trip);
                updateStats(next, newBadges);
              }}
            />

            {dayView === 'calendar' ? (
              <CalendarView
                days={days}
                activeDayNumber={days[activeIndex]?.dayNumber ?? null}
                onSelectDay={(dn) => {
                  setDayView('flow');
                  setExpanded((e) => ({ ...e, [dn]: true }));
                  window.setTimeout(() => {
                    const el = document.querySelector(`[data-date="${days.find((d) => d.dayNumber === dn)?.date}"]`);
                    el?.scrollIntoView({ behavior: 'smooth', block: 'start' });
                  }, 80);
                }}
              />
            ) : (
              days.map((day, i) => (
                <DayCard
                  key={day.dayNumber}
                  day={day}
                  trip={trip}
                  expanded={!!expanded[day.dayNumber]}
                  isActive={i === activeIndex}
                  isPast={i < activeIndex}
                  onToggle={() =>
                    setExpanded((e) => ({ ...e, [day.dayNumber]: !e[day.dayNumber] }))
                  }
                />
              ))
            )}
          </section>
        ) : (
          <div className="empty-state">
            <h2>Plan günleri henüz oluşturulmamış</h2>
            <p>Planlayıcıdan tarihleri seç, AI ile rota üret.</p>
            <a className="btn" href={`/planner/?u=${encodeURIComponent(username)}`}>
              Planlayıcıyı aç →
            </a>
          </div>
        )}

        <PreJapanGuide />
        <QuickReference trip={trip} />
        <Pusula trip={trip} />
        <RewardsPanel stats={stats} />
        <CommunityBeta
          trip={trip}
          community={stats.community}
          onJoin={(c) => {
            const { next, newBadges } = applyCommunity(stats, c, trip);
            const { next: withXp, newBadges: extraBadges } = recordAction(
              next,
              'community-joined',
              trip,
            );
            updateStats(withXp, [...newBadges, ...extraBadges]);
            showToast(`✓ ${c.cityRoom} ${c.month} odası tercihin kaydedildi.`);
          }}
        />
        <TripGuideSections trip={trip} />
      </main>

      <footer className="viewer-footer">
        <div style={{ marginBottom: 8 }}>🗾 🌸 ⛩️ 🍣 🚄</div>
        <div>
          {trip.title} · Kullanıcı: <strong>{username}</strong>
        </div>
        <div style={{ marginTop: 8 }}>
          <a href={`/planner/?u=${encodeURIComponent(username)}`}>Planlayıcı</a>
          ·
          <a href="/">Klasik rehber</a>
        </div>
      </footer>

      <SettingsDrawer
        open={settingsOpen}
        theme={theme}
        username={username}
        trip={trip}
        onTheme={setTheme}
        onClose={() => setSettingsOpen(false)}
      />

      {days.length > 0 && (
        <button
          type="button"
          className="edit-fab"
          onClick={() => setEditOpen(true)}
          aria-label="AI ile düzenle"
          title="AI ile düzenle"
        >
          <span className="edit-fab-emoji">✨</span>
          <span className="edit-fab-text">Düzenle</span>
        </button>
      )}

      {editOpen && (
        <EditModal
          trip={trip}
          activeDayNumber={days[activeIndex]?.dayNumber ?? null}
          initialInstruction={editInitial?.instruction}
          initialWeather={editInitial?.weather}
          onClose={() => {
            setEditOpen(false);
            setEditInitial(null);
          }}
          onApply={({ summary, days: newDays }) => {
            const updatedTrip = { ...trip, days: newDays };
            persistTrip(updatedTrip);
            setEditOpen(false);
            setEditInitial(null);
            showToast(summary ? `✓ ${summary}` : '✓ Plan güncellendi.');
            const { next, newBadges } = recordAction(stats, 'edit-used', updatedTrip);
            updateStats(next, newBadges);
          }}
        />
      )}

      {toast && <div className="viewer-toast">{toast}</div>}

      {badgeToast && (
        <div className="badge-toast" role="status" aria-live="polite">
          <span className="badge-toast-emoji">{badgeToast.emoji}</span>
          <div>
            <strong>Rozet kazandın: {badgeToast.title}</strong>
            <p>{badgeToast.description}</p>
          </div>
        </div>
      )}
    </>
  );
}
