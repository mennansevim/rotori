import { useMemo } from 'react';
import { xpToLevel } from '@japan-trip/shared';
import type { Trip, UserStats, VisitState } from '@japan-trip/shared';
import { ALL_BADGES } from '../utils/userStats';
import type { GeofencePermission } from '../hooks/useGeofence';
import { getRouteCities, type CityData, type CityPlace } from '../data/cityPlaces';

interface Props {
  stats: UserStats;
  visits: VisitState;
  permission: GeofencePermission;
  onStartTracking: () => void;
  onStopTracking: () => void;
  trip: Trip;
}

const VB_W = 320;
const VB_H = 200;
const PAD = 30;

interface PlottedPlace {
  place: CityPlace;
  x: number;
  y: number;
}

/** Şehrin noktalarını lat/lng oranlarını koruyarak mini-kroki kutusuna yerleştirir. */
function plotPlaces(places: CityPlace[]): PlottedPlace[] {
  if (places.length === 0) return [];
  const meanLat = places.reduce((s, p) => s + p.lat, 0) / places.length;
  const k = Math.cos((meanLat * Math.PI) / 180); // boylam sıkışması düzeltmesi
  const pts = places.map((p) => ({ px: p.lng * k, py: p.lat }));
  const xs = pts.map((p) => p.px);
  const ys = pts.map((p) => p.py);
  const minX = Math.min(...xs);
  const maxX = Math.max(...xs);
  const minY = Math.min(...ys);
  const maxY = Math.max(...ys);
  const spanX = maxX - minX || 1e-6;
  const spanY = maxY - minY || 1e-6;
  const availW = VB_W - 2 * PAD;
  const availH = VB_H - 2 * PAD;
  const scale = Math.min(availW / spanX, availH / spanY);
  const drawW = spanX * scale;
  const drawH = spanY * scale;
  const offX = PAD + (availW - drawW) / 2;
  const offY = PAD + (availH - drawH) / 2;
  return places.map((place, i) => ({
    place,
    x: offX + (pts[i].px - minX) * scale,
    y: offY + (maxY - pts[i].py) * scale, // büyük enlem → yukarı (küçük y)
  }));
}

interface CityCardProps {
  city: CityData;
  visited: Set<string>;
  inProgress: Set<string>;
}

function CityCard({ city, visited, inProgress }: CityCardProps) {
  const plotted = useMemo(() => plotPlaces(city.places), [city]);
  const visitedCount = city.places.filter((p) => visited.has(p.id)).length;
  const pct = Math.round((visitedCount / Math.max(1, city.places.length)) * 100);

  return (
    <section className="city-explore">
      <header className="city-explore-head">
        <span className="city-explore-emoji" aria-hidden>
          {city.emoji}
        </span>
        <div className="city-explore-head-text">
          <h3>{city.label}</h3>
          <span className="city-explore-count">
            {visitedCount}/{city.places.length} gezildi
          </span>
        </div>
        <div className="city-explore-bar" aria-hidden>
          <div className="city-explore-bar-fill" style={{ width: `${pct}%` }} />
        </div>
      </header>

      <div className="city-map">
        <svg
          viewBox={`0 0 ${VB_W} ${VB_H}`}
          xmlns="http://www.w3.org/2000/svg"
          role="img"
          aria-label={`${city.label} keşif krokisi`}
        >
          <rect
            className="city-map-bg"
            x={4}
            y={4}
            width={VB_W - 8}
            height={VB_H - 8}
            rx={14}
          />
          {plotted.map(({ place, x, y }) => {
            const isVisited = visited.has(place.id);
            const isProgress = !isVisited && inProgress.has(place.id);
            return (
              <g
                key={place.id}
                className={`city-pin${isVisited ? ' visited' : ''}${
                  isProgress ? ' in-progress' : ''
                }`}
                aria-label={`${place.name}${isVisited ? ' (gezildi)' : ''}`}
              >
                <title>
                  {place.name}
                  {isVisited
                    ? ' — gezildi'
                    : isProgress
                      ? ' — ziyaret algılanıyor'
                      : ''}
                </title>
                <circle className="city-pin-halo" cx={x} cy={y} r={13} />
                <circle className="city-pin-dot" cx={x} cy={y} r={9} />
                <text
                  className="city-pin-glyph"
                  x={x}
                  y={y}
                  textAnchor="middle"
                  dominantBaseline="central"
                  fontSize={10}
                >
                  {isVisited ? '✓' : place.emoji}
                </text>
              </g>
            );
          })}
        </svg>
      </div>

      <ul className="city-place-list">
        {city.places.map((p) => {
          const isVisited = visited.has(p.id);
          const isProgress = !isVisited && inProgress.has(p.id);
          return (
            <li
              key={p.id}
              className={`city-place-chip${isVisited ? ' visited' : ''}${
                isProgress ? ' in-progress' : ''
              }`}
            >
              <span className="city-place-emoji" aria-hidden>
                {isVisited ? '✅' : p.emoji}
              </span>
              <span className="city-place-name">{p.name}</span>
              <span className="city-place-cat">
                {isVisited ? 'gezildi' : isProgress ? 'algılanıyor…' : p.category}
              </span>
            </li>
          );
        })}
      </ul>
    </section>
  );
}

export function RewardMap({
  stats,
  visits,
  permission,
  onStartTracking,
  onStopTracking,
  trip,
}: Props) {
  const routeCities = useMemo(() => getRouteCities(trip), [trip]);

  // Gezildi durumu GPS ile belirlenir: bir noktada 10 dk+ kalınca otomatik tamamlanır.
  const { visited, inProgress } = useMemo(() => {
    const v = new Set<string>();
    const ip = new Set<string>();
    for (const [id, rec] of Object.entries(visits.records)) {
      if (rec?.completedAt) v.add(id);
      else if ((rec?.totalDwellSeconds ?? 0) > 0) ip.add(id);
    }
    return { visited: v, inProgress: ip };
  }, [visits]);

  const allPlaces = useMemo(
    () => routeCities.flatMap((c) => c.places),
    [routeCities],
  );
  const visitedCount = allPlaces.filter((p) => visited.has(p.id)).length;

  const { level, progress, nextThreshold } = xpToLevel(stats.xp);
  const activityEarned = new Set(stats.badgesEarned);
  const watching = permission === 'granted' || permission === 'requesting';

  return (
    <div className="reward-map">
      <header className="reward-map-head">
        <div className="reward-map-icon">🗺️</div>
        <div className="reward-map-head-text">
          <h2>Keşif haritası</h2>
          <p>
            {routeCities.length} şehir · {visitedCount}/{allPlaces.length} nokta
            gezildi · Level {level}
          </p>
        </div>
      </header>

      <div className="reward-map-progress">
        <div className="reward-map-progress-bar">
          <div
            className="reward-map-progress-fill"
            style={{ width: `${Math.round(progress * 100)}%` }}
          />
        </div>
        <div className="reward-map-progress-meta">
          <span>Level {level}</span>
          <span>{nextThreshold} XP sonraki seviyeye</span>
        </div>
      </div>

      {routeCities.length === 0 ? (
        <div className="city-explore-empty">
          <div className="city-explore-empty-icon">🧭</div>
          <p>
            Rotanda tanıdık bir şehir bulamadık. Planlayıcıda Tokyo, Kyoto, Osaka
            gibi şehirler eklersen keşif haritası burada belirir.
          </p>
        </div>
      ) : (
        <>
          <p className="city-explore-hint">
            Her şehrin popüler noktaları aşağıda. Konum takibi açıkken bir noktada
            10 dakikadan fazla kalırsan otomatik yeşillenir ve sana bildirim
            gelir. 📍
          </p>
          <div className="city-explore-list">
            {routeCities.map((city) => (
              <CityCard
                key={city.key}
                city={city}
                visited={visited}
                inProgress={inProgress}
              />
            ))}
          </div>
        </>
      )}

      <div className="reward-map-stats">
        <div className="reward-map-stat">
          <span>Gezilen</span>
          <strong>{visitedCount} nokta</strong>
        </div>
        <div className="reward-map-stat">
          <span>Toplam</span>
          <strong>{allPlaces.length} nokta</strong>
        </div>
        <div className="reward-map-stat">
          <span>Şehir</span>
          <strong>{routeCities.length}</strong>
        </div>
      </div>

      <div className="reward-map-tracking">
        <div className="reward-map-tracking-text">
          <strong>
            {permission === 'unsupported'
              ? '📵 Bu tarayıcı konum desteklemiyor'
              : permission === 'denied'
                ? '🔒 Konum izni reddedildi'
                : watching
                  ? '📡 Konum takibi açık'
                  : '📍 Konum takibini aç'}
          </strong>
          <span>
            Noktaların otomatik gezildi olması için konum takibi gerekir. Bir
            yerde 10 dk+ kalınca kendiliğinden yeşillenir ve bildirim alırsın.
            Batarya için sekme arka plandayken takip duraklatılır.
          </span>
        </div>
        {permission !== 'unsupported' && permission !== 'denied' && (
          <button
            type="button"
            className="reward-map-track-btn"
            onClick={watching ? onStopTracking : onStartTracking}
          >
            {watching ? 'Durdur' : 'Konumu izlemeye başla'}
          </button>
        )}
      </div>

      <div className="reward-map-activity">
        <div className="reward-map-list-title">🏅 Aktivite rozetleri</div>
        <p className="reward-map-activity-note">
          Bunlar manuel planlama/kullanım rozetleridir (GPS doğrulaması
          gerekmiyor).
        </p>
        <div className="badge-grid">
          {ALL_BADGES.map((b) => {
            const isEarned = activityEarned.has(b.id);
            return (
              <article
                key={b.id}
                className={`badge-card${isEarned ? ' earned' : ''}`}
              >
                <div className="badge-emoji" aria-hidden>
                  {b.emoji}
                </div>
                <div className="badge-title">{b.title}</div>
                <div className="badge-desc">
                  {isEarned ? b.description : b.hint}
                </div>
                {!isEarned && <div className="badge-locked">🔒 Kilitli</div>}
              </article>
            );
          })}
        </div>
      </div>
    </div>
  );
}
