import { defineConfig, loadEnv, type PluginOption } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';
import { resolve } from 'node:path';

async function readBody(req: NodeJS.ReadableStream): Promise<unknown> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

function apiDevPlugin(opts: { groqKey?: string }): PluginOption {
  return {
    name: 'api-dev-proxy',
    configureServer(server) {
      server.middlewares.use('/api/edit', async (req, res) => {
        if (req.method !== 'POST') {
          res.statusCode = 405;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ error: 'method-not-allowed' }));
          return;
        }
        try {
          const input = await readBody(req);
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
          const input = await readBody(req);
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
    },
  };
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, resolve(__dirname, '../..'), '');
  const groqKey = env.GROQ_API_KEY;
  return {
    base: '/viewer/',
    plugins: [
      apiDevPlugin({ groqKey }),
      react(),
      VitePWA({
        registerType: 'autoUpdate',
        manifest: {
          name: 'Japonya Seyahat Rehberi',
          short_name: 'JP Trip',
          theme_color: '#f5f5f7',
          background_color: '#f5f5f7',
          display: 'standalone',
          start_url: '/viewer/',
          icons: [{ src: 'favicon.svg', sizes: 'any', type: 'image/svg+xml', purpose: 'any' }],
        },
        workbox: {
          globPatterns: ['**/*.{js,css,html,ico,png,svg,json}'],
        },
      }),
    ],
    resolve: {
      alias: {
        '@japan-trip/shared': resolve(__dirname, '../../packages/shared/src/index.ts'),
      },
    },
    publicDir: 'public',
    server: {
      port: 5180,
      strictPort: false,
      fs: { allow: [resolve(__dirname, '../..')] },
    },
  };
});
