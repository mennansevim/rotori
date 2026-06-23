// Regenerates apps/viewer/src/data/japanMapPaths.ts from real prefecture geometry.
// Source: https://github.com/dataofjapan/land (japan.geojson, public domain).
// Projects with Mercator, splits Okinawa into an inset, simplifies with Douglas–Peucker,
// and prints projected mapX/mapY for each POI in packages/shared/src/geofence.ts.
// Run: node scripts/gen-japan-map.mjs
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');

const SOURCE_URL =
  'https://raw.githubusercontent.com/dataofjapan/land/master/japan.geojson';
const cachePath = path.join(os.tmpdir(), 'japan.geojson');

async function loadGeoJson() {
  if (fs.existsSync(cachePath)) return JSON.parse(fs.readFileSync(cachePath, 'utf8'));
  process.stdout.write(`Downloading ${SOURCE_URL} …\n`);
  const res = await fetch(SOURCE_URL);
  if (!res.ok) throw new Error(`Download failed: ${res.status}`);
  const text = await res.text();
  fs.writeFileSync(cachePath, text);
  return JSON.parse(text);
}

const gj = await loadGeoJson();

const REGION_BY_ID = {
  1: 'hokkaido',
  2: 'tohoku', 3: 'tohoku', 4: 'tohoku', 5: 'tohoku', 6: 'tohoku', 7: 'tohoku',
  8: 'kanto', 9: 'kanto', 10: 'kanto', 11: 'kanto', 12: 'kanto', 13: 'kanto', 14: 'kanto',
  15: 'chubu', 16: 'chubu', 17: 'chubu', 18: 'chubu', 19: 'chubu', 20: 'chubu', 21: 'chubu', 22: 'chubu', 23: 'chubu',
  24: 'kansai', 25: 'kansai', 26: 'kansai', 27: 'kansai', 28: 'kansai', 29: 'kansai', 30: 'kansai',
  31: 'chugoku', 32: 'chugoku', 33: 'chugoku', 34: 'chugoku', 35: 'chugoku',
  36: 'shikoku', 37: 'shikoku', 38: 'shikoku', 39: 'shikoku',
  40: 'kyushu', 41: 'kyushu', 42: 'kyushu', 43: 'kyushu', 44: 'kyushu', 45: 'kyushu', 46: 'kyushu',
  47: 'okinawa',
};

const VIEW_W = 760;
const VIEW_H = 560;

function mercator(lng, lat) {
  const x = (lng * Math.PI) / 180;
  const y = Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360));
  return [x, y];
}

function makeProjection(geo, box) {
  const [minX, minY] = mercator(geo.minLng, geo.minLat);
  const [maxX, maxY] = mercator(geo.maxLng, geo.maxLat);
  const sx = box.w / (maxX - minX);
  const sy = box.h / (maxY - minY);
  const s = Math.min(sx, sy);
  const offX = box.x + (box.w - s * (maxX - minX)) / 2;
  const offY = box.y + (box.h - s * (maxY - minY)) / 2;
  return ([lng, lat]) => {
    const [x, y] = mercator(lng, lat);
    return [offX + (x - minX) * s, offY + (maxY - y) * s];
  };
}

function ringCentroidLngLat(ring) {
  let lng = 0, lat = 0;
  for (const [x, y] of ring) { lng += x; lat += y; }
  return [lng / ring.length, lat / ring.length];
}

function eachRing(geom, cb) {
  if (geom.type === 'Polygon') {
    for (const ring of geom.coordinates) cb(ring);
  } else if (geom.type === 'MultiPolygon') {
    for (const poly of geom.coordinates) for (const ring of poly) cb(ring);
  }
}

function ringArea(ring) {
  let a = 0;
  for (let i = 0, n = ring.length; i < n; i++) {
    const [x1, y1] = ring[i];
    const [x2, y2] = ring[(i + 1) % n];
    a += x1 * y2 - x2 * y1;
  }
  return Math.abs(a) / 2;
}

function perpDist(p, a, b) {
  const [px, py] = p, [ax, ay] = a, [bx, by] = b;
  const dx = bx - ax, dy = by - ay;
  const len = dx * dx + dy * dy;
  if (len === 0) return Math.hypot(px - ax, py - ay);
  let t = ((px - ax) * dx + (py - ay) * dy) / len;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
}

function rdp(points, eps) {
  if (points.length < 3) return points;
  let maxD = 0, idx = 0;
  for (let i = 1; i < points.length - 1; i++) {
    const d = perpDist(points[i], points[0], points[points.length - 1]);
    if (d > maxD) { maxD = d; idx = i; }
  }
  if (maxD > eps) {
    const left = rdp(points.slice(0, idx + 1), eps);
    const right = rdp(points.slice(idx), eps);
    return left.slice(0, -1).concat(right);
  }
  return [points[0], points[points.length - 1]];
}

function buildPaths(features, project, opts) {
  const { minAreaPx = 6, eps = 0.5, clip } = opts;
  const byRegion = {};
  for (const f of features) {
    const region = REGION_BY_ID[f.properties.id];
    const segments = [];
    eachRing(f.geometry, (ring) => {
      if (clip) {
        const [clng, clat] = ringCentroidLngLat(ring);
        if (clng < clip.minLng || clng > clip.maxLng || clat < clip.minLat || clat > clip.maxLat) return;
      }
      const projected = ring.map(project);
      if (ringArea(projected) < minAreaPx) return;
      let simplified = rdp(projected, eps);
      if (simplified.length < 3) return;
      simplified = simplified.map(([x, y]) => [Math.round(x * 10) / 10, Math.round(y * 10) / 10]);
      segments.push(simplified);
    });
    if (!segments.length) continue;
    const d = segments
      .map((seg) => 'M' + seg.map(([x, y]) => `${x} ${y}`).join('L') + 'Z')
      .join('');
    (byRegion[region] ??= []).push({ id: f.properties.id, d });
  }
  return byRegion;
}

const mainland = gj.features.filter((f) => REGION_BY_ID[f.properties.id] !== 'okinawa');
const okinawa = gj.features.filter((f) => REGION_BY_ID[f.properties.id] === 'okinawa');

const MAIN_GEO = { minLng: 128.4, maxLng: 146.1, minLat: 30.9, maxLat: 45.6 };
const MAIN_CLIP = { minLng: 127.8, maxLng: 146.5, minLat: 30.4, maxLat: 46.0 };
const OKI_GEO = { minLng: 127.4, maxLng: 128.4, minLat: 26.0, maxLat: 26.9 };
const OKI_CLIP = { minLng: 126.9, maxLng: 128.6, minLat: 25.8, maxLat: 27.0 };

const mainProj = makeProjection(MAIN_GEO, { x: 30, y: 20, w: VIEW_W - 60, h: VIEW_H - 90 });
const okiProj = makeProjection(OKI_GEO, { x: 40, y: VIEW_H - 95, w: 150, h: 78 });

const mainPaths = buildPaths(mainland, mainProj, { minAreaPx: 4, eps: 0.4, clip: MAIN_CLIP });
const okiPaths = buildPaths(okinawa, okiProj, { minAreaPx: 2, eps: 0.35, clip: OKI_CLIP });

const allPaths = { ...mainPaths };
for (const [r, list] of Object.entries(okiPaths)) {
  allPaths[r] = (allPaths[r] ?? []).concat(list);
}

const REGION_LABELS = {
  hokkaido: 'Hokkaido',
  tohoku: 'Tohoku',
  kanto: 'Kanto',
  chubu: 'Chubu',
  kansai: 'Kansai',
  chugoku: 'Chugoku',
  shikoku: 'Shikoku',
  kyushu: 'Kyushu',
  okinawa: 'Okinawa',
};

function centroidOfRegion(list) {
  let sx = 0, sy = 0, n = 0;
  for (const { d } of list) {
    const nums = d.match(/-?\d+(\.\d+)?/g).map(Number);
    for (let i = 0; i < nums.length; i += 2) { sx += nums[i]; sy += nums[i + 1]; n++; }
  }
  return [Math.round(sx / n), Math.round(sy / n)];
}

const regions = Object.entries(allPaths).map(([region, prefs]) => ({
  region,
  label: REGION_LABELS[region],
  labelPos: centroidOfRegion(prefs),
  prefs,
}));

const geofenceSrc = fs.readFileSync(path.join(root, 'packages/shared/src/geofence.ts'), 'utf8');
const fenceMatches = [...geofenceSrc.matchAll(/id:\s*'([^']+)'[\s\S]*?lat:\s*([\d.]+),\s*lng:\s*([\d.]+),/g)];
const poiProjections = fenceMatches.map((m) => {
  const [, id, latS, lngS] = m;
  const lat = Number(latS), lng = Number(lngS);
  const isOki = id.includes('okinawa') || id.includes('naha');
  const [x, y] = (isOki ? okiProj : mainProj)([lng, lat]);
  return { id, mapX: Math.round(x), mapY: Math.round(y) };
});

const header = `// AUTO-GENERATED by scripts/gen-japan-map.mjs — do not edit by hand.
// Source: dataofjapan/land (japan.geojson), projected + simplified.
export const JAPAN_MAP_VIEWBOX = '0 0 ${VIEW_W} ${VIEW_H}';

export interface JapanRegionShape {
  region: string;
  label: string;
  labelPos: [number, number];
  prefs: { id: number; d: string }[];
}

export const JAPAN_REGIONS: JapanRegionShape[] = ${JSON.stringify(regions)};
`;

fs.writeFileSync(path.join(root, 'apps/viewer/src/data/japanMapPaths.ts'), header);

console.log('Wrote apps/viewer/src/data/japanMapPaths.ts');
console.log('Regions:', regions.map((r) => `${r.region}(${r.prefs.length})`).join(', '));
console.log('\nPOI projected coords (update geofence.ts mapX/mapY):');
for (const p of poiProjections) console.log(`  ${p.id}: mapX=${p.mapX}, mapY=${p.mapY}`);
