import { useMemo } from 'react';
import { POPULAR_GEOFENCES, xpToLevel } from '@japan-trip/shared';
import type { Geofence, UserStats, VisitState } from '@japan-trip/shared';
import { ALL_BADGES } from '../utils/userStats';
import type { GeofencePermission } from '../hooks/useGeofence';
import { JAPAN_MAP_VIEWBOX, JAPAN_REGIONS } from '../data/japanMapPaths';

interface Props {
  stats: UserStats;
  visits: VisitState;
  permission: GeofencePermission;
  onStartTracking: () => void;
  onStopTracking: () => void;
}

function formatDwell(seconds: number): string {
  if (seconds < 60) return `${Math.round(seconds)} sn`;
  const mins = Math.round(seconds / 60);
  if (mins < 60) return `${mins} dk`;
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  return m ? `${h} sa ${m} dk` : `${h} sa`;
}

interface PinProps {
  fence: Geofence;
  earned: boolean;
  inProgress: boolean;
}

function Pin({ fence, earned, inProgress }: PinProps) {
  if (earned) {
    return (
      <g className="map-pin map-pin-earned">
        <circle cx={fence.mapX} cy={fence.mapY} r={13} className="map-pin-halo" />
        <circle cx={fence.mapX} cy={fence.mapY} r={5} className="map-pin-dot" />
        <text
          x={fence.mapX}
          y={fence.mapY - 12}
          textAnchor="middle"
          fontSize={10.5}
          fontWeight={600}
          className="map-pin-label"
        >
          {fence.emoji}
        </text>
      </g>
    );
  }
  if (inProgress) {
    return (
      <g className="map-pin map-pin-progress">
        <circle cx={fence.mapX} cy={fence.mapY} r={9} className="map-pin-halo" />
        <circle cx={fence.mapX} cy={fence.mapY} r={4} className="map-pin-dot" />
      </g>
    );
  }
  return (
    <g className="map-pin">
      <circle cx={fence.mapX} cy={fence.mapY} r={3.5} className="map-pin-dot" />
    </g>
  );
}

export function RewardMap({
  stats,
  visits,
  permission,
  onStartTracking,
  onStopTracking,
}: Props) {
  const earnedCount = useMemo(
    () => POPULAR_GEOFENCES.filter((f) => visits.records[f.id]?.completedAt).length,
    [visits],
  );
  const totalDwell = useMemo(
    () =>
      Object.values(visits.records).reduce(
        (sum, r) => sum + (r.totalDwellSeconds ?? 0),
        0,
      ),
    [visits],
  );
  const popularCoverage = Math.round(
    (earnedCount / Math.max(1, POPULAR_GEOFENCES.length)) * 100,
  );

  const { level, progress, nextThreshold } = xpToLevel(stats.xp);
  const activityEarned = new Set(stats.badgesEarned);

  const watching = permission === 'granted' || permission === 'requesting';

  return (
    <div className="reward-map">
      <header className="reward-map-head">
        <div className="reward-map-icon">🗾</div>
        <div className="reward-map-head-text">
          <h2>Keşif haritası</h2>
          <p>
            Level {level} · {earnedCount}/{POPULAR_GEOFENCES.length} nokta ·{' '}
            {stats.xp} XP
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

      <div className="reward-map-svg-wrap">
        <svg
          viewBox={JAPAN_MAP_VIEWBOX}
          xmlns="http://www.w3.org/2000/svg"
          role="img"
          aria-label="Japonya keşif haritası"
        >
          <g className="map-regions">
            {JAPAN_REGIONS.map((r) => (
              <g key={r.region} className={`map-region map-region-${r.region}`}>
                {r.prefs.map((p) => (
                  <path key={p.id} d={p.d} />
                ))}
              </g>
            ))}
          </g>

          <g className="map-region-labels">
            {JAPAN_REGIONS.map((r) => (
              <text
                key={r.region}
                x={r.labelPos[0]}
                y={r.labelPos[1]}
                textAnchor="middle"
              >
                {r.label}
              </text>
            ))}
          </g>

          <line
            className="map-inset-divider"
            x1="200"
            y1="470"
            x2="200"
            y2="548"
          />

          {POPULAR_GEOFENCES.map((f) => {
            const rec = visits.records[f.id];
            const earned = !!rec?.completedAt;
            const inProgress =
              !earned && (rec?.totalDwellSeconds ?? 0) > 0;
            return (
              <Pin key={f.id} fence={f} earned={earned} inProgress={inProgress} />
            );
          })}
        </svg>
      </div>

      <div className="reward-map-stats">
        <div className="reward-map-stat">
          <span>Kazanılan</span>
          <strong>{earnedCount} nokta</strong>
        </div>
        <div className="reward-map-stat">
          <span>Toplam süre</span>
          <strong>{formatDwell(totalDwell)}</strong>
        </div>
        <div className="reward-map-stat">
          <span>Popüler bölge</span>
          <strong>%{popularCoverage}</strong>
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
                  : '📍 Konum takibi kapalı'}
          </strong>
          <span>
            Bir noktayı 100 m yarıçapında en az 10 dakika gezmen gerekiyor.
            Sadece yoldan geçmek sayılmaz.
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

      <div className="reward-map-list">
        <div className="reward-map-list-title">📍 Popüler noktalar</div>
        <ul>
          {POPULAR_GEOFENCES.map((f) => {
            const rec = visits.records[f.id];
            const earned = !!rec?.completedAt;
            const dwell = rec?.totalDwellSeconds ?? 0;
            const pct = Math.min(
              100,
              Math.round((dwell / f.minDwellSeconds) * 100),
            );
            return (
              <li
                key={f.id}
                className={`reward-map-row${earned ? ' earned' : ''}`}
              >
                <span className="reward-map-row-emoji">{f.emoji}</span>
                <div className="reward-map-row-info">
                  <strong>{f.name}</strong>
                  <span className="reward-map-row-city">{f.city}</span>
                </div>
                <div className="reward-map-row-progress">
                  <div className="reward-map-row-bar">
                    <div
                      className="reward-map-row-bar-fill"
                      style={{ width: `${pct}%` }}
                    />
                  </div>
                  <span>
                    {earned
                      ? '✓ Kazanıldı'
                      : `${formatDwell(dwell)} / ${formatDwell(f.minDwellSeconds)}`}
                  </span>
                </div>
                <span className="reward-map-row-xp">+{f.xp} XP</span>
              </li>
            );
          })}
        </ul>
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
