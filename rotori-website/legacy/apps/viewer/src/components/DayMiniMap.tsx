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
}

export function DayMiniMap({ points, width = 320, height = 200 }: Props) {
  const bbox = useMemo(() => boundsOf(points), [points]);
  if (!points.length || !bbox) return null;

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
      aria-label="Gün rotası"
    >
      <rect x={0} y={0} width={width} height={height} className="day-map-bg" />
      {projected.length > 1 && <path d={pathD} className="day-map-route" fill="none" />}
      {projected.map((p, i) => (
        <g key={p.id}>
          <circle cx={p.x} cy={p.y} r={8} className="day-map-pin-dot" />
          <text x={p.x} y={p.y + 3} className="day-map-pin-num" textAnchor="middle">
            {i + 1}
          </text>
        </g>
      ))}
    </svg>
  );
}
