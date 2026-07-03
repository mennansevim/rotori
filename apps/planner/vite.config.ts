import { defineConfig, loadEnv, type PluginOption } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';
import { resolve } from 'node:path';

/** /api/flight ve /api/itinerary için yerel dev proxy. */
function apiDevPlugin(opts: { aerodataboxKey?: string; groqKey?: string }): PluginOption {
  return {
    name: 'api-dev-proxy',
    configureServer(server) {
      server.middlewares.use('/api/flight', async (req, res) => {
        try {
          const { fetchFlight } = await import('../../tools/flightProvider.mjs');
          const url = new URL(req.url ?? '', 'http://localhost');
          const { status, body } = await fetchFlight(
            url.searchParams.get('number'),
            url.searchParams.get('date'),
            opts.aerodataboxKey,
            url.searchParams.get('callsign'),
          );
          res.statusCode = status;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify(body));
        } catch {
          res.statusCode = 500;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ error: 'dev-proxy-failed' }));
        }
      });

      server.middlewares.use('/api/itinerary', async (req, res) => {
        if (req.method !== 'POST') {
          res.statusCode = 405;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ error: 'method-not-allowed' }));
          return;
        }
        try {
          const chunks: Buffer[] = [];
          for await (const chunk of req) chunks.push(chunk as Buffer);
          const trip = JSON.parse(Buffer.concat(chunks).toString('utf8'));
          const { fetchItinerary } = await import('../../tools/itineraryProvider.mjs');
          const { status, body } = await fetchItinerary(trip, opts.groqKey);
          res.statusCode = status;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify(body));
        } catch {
          res.statusCode = 500;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ error: 'dev-proxy-failed' }));
        }
      });

      server.middlewares.use('/api/edit', async (req, res) => {
        if (req.method !== 'POST') {
          res.statusCode = 405;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ error: 'method-not-allowed' }));
          return;
        }
        try {
          const chunks: Buffer[] = [];
          for await (const chunk of req) chunks.push(chunk as Buffer);
          const input = JSON.parse(Buffer.concat(chunks).toString('utf8'));
          const { fetchEdit } = await import('../../tools/editProvider.mjs');
          const { status, body } = await fetchEdit(input, opts.groqKey);
          res.statusCode = status;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify(body));
        } catch {
          res.statusCode = 500;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ error: 'dev-proxy-failed' }));
        }
      });

      server.middlewares.use('/api/morning-summary', async (req, res) => {
        if (req.method !== 'POST') {
          res.statusCode = 405;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ error: 'method-not-allowed' }));
          return;
        }
        try {
          const chunks: Buffer[] = [];
          for await (const chunk of req) chunks.push(chunk as Buffer);
          const input = JSON.parse(Buffer.concat(chunks).toString('utf8'));
          const { fetchMorningSummary } = await import(
            '../../tools/morningSummaryProvider.mjs'
          );
          const { status, body } = await fetchMorningSummary(input, opts.groqKey);
          res.statusCode = status;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify(body));
        } catch {
          res.statusCode = 500;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ error: 'dev-proxy-failed' }));
        }
      });

      server.middlewares.use('/api/discover', async (req, res) => {
        try {
          const url = new URL(req.url ?? '', 'http://localhost');
          const { fetchDiscover } = await import('../../tools/discoverProvider.mjs');
          const { status, body } = await fetchDiscover(
            url.searchParams.get('city') ?? '',
            url.searchParams.get('country') ?? '',
            opts.groqKey,
          );
          res.statusCode = status;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify(body));
        } catch {
          res.statusCode = 500;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ error: 'dev-proxy-failed' }));
        }
      });

      server.middlewares.use('/api/ticket-ocr', async (req, res) => {
        if (req.method !== 'POST') {
          res.statusCode = 405;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ error: 'method-not-allowed' }));
          return;
        }
        try {
          const chunks: Buffer[] = [];
          for await (const chunk of req) chunks.push(chunk as Buffer);
          const input = JSON.parse(Buffer.concat(chunks).toString('utf8'));
          const { fetchTicketOcr } = await import('../../tools/ticketOcrProvider.mjs');
          const { status, body } = await fetchTicketOcr(input, opts.groqKey);
          res.statusCode = status;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify(body));
        } catch {
          res.statusCode = 500;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ error: 'dev-proxy-failed' }));
        }
      });
    },
  };
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, resolve(__dirname, '../..'), '');
  const aerodataboxKey = env.AERODATABOX_KEY || env.RAPIDAPI_KEY;
  const groqKey = env.GROQ_API_KEY;
  return {
  base: '/planner/',
  plugins: [
    apiDevPlugin({ aerodataboxKey, groqKey }),
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      workbox: {
        // Static asset cache (precache build çıktısı)
        globPatterns: ['**/*.{js,css,html,svg,png,ico,woff2}'],
        // Navigation isteklerinde offline fallback
        navigateFallback: '/planner/index.html',
        navigateFallbackDenylist: [/^\/api\//],
        runtimeCaching: [
          {
            // /api/* için network-first, başarısızsa cache fallback
            urlPattern: /\/api\//,
            handler: 'NetworkFirst',
            options: {
              cacheName: 'api-cache',
              networkTimeoutSeconds: 8,
              expiration: {
                maxEntries: 50,
                maxAgeSeconds: 24 * 60 * 60, // 1 gün
              },
            },
          },
          {
            // Wikipedia thumbnail vb. CDN görsellerini cache'le
            urlPattern: /^https:\/\/(upload\.wikimedia\.org|.*\.gstatic\.com)/,
            handler: 'CacheFirst',
            options: {
              cacheName: 'image-cache',
              expiration: {
                maxEntries: 200,
                maxAgeSeconds: 7 * 24 * 60 * 60, // 1 hafta
              },
            },
          },
        ],
      },
      manifest: {
        name: 'Japonya Seyahat Planlayıcı',
        short_name: 'JP Plan',
        theme_color: '#f5f5f7',
        background_color: '#f5f5f7',
        display: 'standalone',
        start_url: '/planner/',
        icons: [{ src: 'favicon.svg', sizes: 'any', type: 'image/svg+xml' }],
      },
    }),
  ],
  resolve: {
    alias: {
      '@japan-trip/shared': resolve(__dirname, '../../packages/shared/src/index.ts'),
    },
  },
  server: {
    host: true,
    port: 5174,
    strictPort: true,
    proxy: {
      '/viewer': {
        target: 'http://localhost:5180',
        changeOrigin: true,
      },
    },
  },
  };
});
