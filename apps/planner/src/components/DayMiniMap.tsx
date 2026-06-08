import { useMemo } from 'react';
import { boundsOf, projectInBounds, type GeoPoint } from '@japan-trip/shared';

export interface MapPoint extends GeoPoint {
  id: string;
  label: string;
}

interface Props {
  points: MapPoint[];
  width?: number;
  height?: number;
  compact?: boolean;
}

export function DayMiniMap({ points, width = 360, height = 300, compact }: Props) {
  const bbox = useMemo(() => boundsOf(points), [points]);

  if (!points.length || !bbox) {
    return (
      <div className="day-map-empty">
        <span>🗺️</span>
        <p>Konumlu yer ekleyin; harita burada görünecek.</p>
      </div>
    );
  }

  const projected = points.map((p) => ({
    ...p,
    ...projectInBounds(p, bbox, { width, height }),
  }));

  const pathD = projected
    .map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x.toFixed(1)} ${p.y.toFixed(1)}`)
    .join(' ');

  return (
    <svg
      viewBox={`0 0 ${width} ${height}`}
      className="day-map-svg"
      preserveAspectRatio="xMidYMid meet"
      role="img"
      aria-label="Gün rotası haritası"
    >
      <rect x={0} y={0} width={width} height={height} className="day-map-bg" />
      {projected.length > 1 && <path d={pathD} className="day-map-route" fill="none" />}
      {projected.map((p, i) => (
        <g key={p.id} className="day-map-pin">
          <circle cx={p.x} cy={p.y} r={compact ? 7 : 10} className="day-map-pin-dot" />
          <text x={p.x} y={p.y + (compact ? 3 : 4)} className="day-map-pin-num" textAnchor="middle">
            {i + 1}
          </text>
          {!compact && (
            <text x={p.x} y={p.y - 14} className="day-map-pin-label" textAnchor="middle">
              {p.label.length > 18 ? `${p.label.slice(0, 17)}…` : p.label}
            </text>
          )}
        </g>
      ))}
    </svg>
  );
}
