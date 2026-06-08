/**
 * Faz 2 API stub — Raspberry Pi veya lokal geliştirme için minimal HTTP sunucu.
 * Üretimde nginx + bu servis veya tam API ile değiştirilebilir.
 */
import { createServer } from 'node:http';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tripSchema } from '../../../packages/shared/src/schema.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '../../..');
const tripsDir = join(root, 'data', 'trips');
const PORT = Number(process.env.PORT ?? 3920);

function readTrip(id: string) {
  const path = join(tripsDir, `${id}.json`);
  if (!existsSync(path)) return null;
  const raw = JSON.parse(readFileSync(path, 'utf8'));
  return tripSchema.parse(raw);
}

const server = createServer((req, res) => {
  const url = new URL(req.url ?? '/', `http://${req.headers.host}`);

  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, PUT, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // GET /api/flight?number=TK2638&date=2026-05-15
  if (req.method === 'GET' && url.pathname === '/api/flight') {
    void import('../../../tools/flightProvider.mjs').then(async ({ fetchFlight }) => {
      const { status, body } = await fetchFlight(
        url.searchParams.get('number'),
        url.searchParams.get('date'),
        undefined,
        url.searchParams.get('callsign'),
      );
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(body));
    });
    return;
  }

  // POST /api/itinerary — AI günlük rota (GROQ_API_KEY opsiyonel)
  if (req.method === 'POST' && url.pathname === '/api/itinerary') {
    const chunks: Buffer[] = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      void import('../../../tools/itineraryProvider.mjs').then(async ({ fetchItinerary }) => {
        let trip: unknown;
        try {
          trip = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        } catch {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'invalid-json' }));
          return;
        }
        const { status, body } = await fetchItinerary(trip, process.env.GROQ_API_KEY);
        res.writeHead(status, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(body));
      });
    });
    return;
  }

  // POST /api/edit — AI plan revizyonu (doğal dil)
  if (req.method === 'POST' && url.pathname === '/api/edit') {
    const chunks: Buffer[] = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      void import('../../../tools/editProvider.mjs').then(async ({ fetchEdit }) => {
        let input: unknown;
        try {
          input = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        } catch {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'invalid-json' }));
          return;
        }
        const { status, body } = await fetchEdit(input, process.env.GROQ_API_KEY);
        res.writeHead(status, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(body));
      });
    });
    return;
  }

  // POST /api/morning-summary — aktif gün için kısa Türkçe özet
  if (req.method === 'POST' && url.pathname === '/api/morning-summary') {
    const chunks: Buffer[] = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      void import('../../../tools/morningSummaryProvider.mjs').then(
        async ({ fetchMorningSummary }) => {
          let input: unknown;
          try {
            input = JSON.parse(Buffer.concat(chunks).toString('utf8'));
          } catch {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: 'invalid-json' }));
            return;
          }
          const { status, body } = await fetchMorningSummary(input, process.env.GROQ_API_KEY);
          res.writeHead(status, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify(body));
        },
      );
    });
    return;
  }

  // GET /api/trips/:id
  const getMatch = url.pathname.match(/^\/api\/trips\/([^/]+)$/);
  if (req.method === 'GET' && getMatch) {
    const trip = readTrip(getMatch[1]);
    if (!trip) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Trip not found' }));
      return;
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(trip));
    return;
  }

  // POST /api/trips — stub: not implemented (Faz 2 + auth)
  if (req.method === 'POST' && url.pathname === '/api/trips') {
    res.writeHead(501, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'POST /api/trips — Faz 2 (auth gerekli)' }));
    return;
  }

  // PUT /api/trips/:id — stub
  if (req.method === 'PUT' && getMatch) {
    res.writeHead(501, { 'Content-Type': 'application/json' });
    res.end(
      JSON.stringify({
        error: 'PUT /api/trips/:id — Faz 2 (PIN veya magic link)',
      }),
    );
    return;
  }

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(
    JSON.stringify({
      service: 'japan-trip-api',
      routes: [
        'GET /api/trips/:tripId',
        'POST /api/trips (501)',
        'PUT /api/trips/:tripId (501)',
      ],
      viewer: '/t/:tripId → statik viewer (nginx)',
      planner: '/plan/:tripId → statik planner (auth Faz 2)',
    }),
  );
});

server.listen(PORT, () => {
  console.log(`API stub http://localhost:${PORT}`);
});
