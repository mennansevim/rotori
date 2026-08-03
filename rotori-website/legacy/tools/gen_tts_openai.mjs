#!/usr/bin/env node
// OpenAI TTS ile Japonca frazları .mp3 olarak asset üretir.
//
// Bir kere çalıştırılır → mp3'ler `mobile/assets/tts/ja/<id>.mp3` altına
// kaydedilir. Manifest zaten mevcut; script sadece eksik mp3'leri üretir
// (idempotent).
//
// Kullanım:
//   OPENAI_API_KEY=sk-... node tools/gen_tts_openai.mjs
//
// Opsiyonel env:
//   TTS_VOICE   → alloy|echo|fable|nova|onyx|shimmer (default: nova)
//   TTS_MODEL   → tts-1|tts-1-hd (default: tts-1-hd)
//   TTS_FORMAT  → mp3|opus|aac|flac|wav (default: mp3)
//   TTS_SPEED   → 0.25..4.0 (default: 0.95 — biraz yavaş, daha net)
//   FORCE       → 1 ise mevcut mp3'leri yeniden üret.

import fs from 'node:fs';
import path from 'node:path';

const KEY = process.env.OPENAI_API_KEY;
if (!KEY) {
  console.error('OPENAI_API_KEY environment değişkeni gerekli.');
  process.exit(1);
}

const ROOT = path.resolve(new URL('.', import.meta.url).pathname, '..');
const ASSET_DIR = path.join(ROOT, 'mobile', 'assets', 'tts', 'ja');
const MANIFEST_PATH = path.join(ASSET_DIR, 'manifest.json');

const manifest = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'));
const voice = process.env.TTS_VOICE || manifest.voice || 'nova';
const model = process.env.TTS_MODEL || manifest.model || 'tts-1-hd';
const format = process.env.TTS_FORMAT || 'mp3';
const speed = parseFloat(process.env.TTS_SPEED || '0.95');
const force = process.env.FORCE === '1';

console.log(`OpenAI TTS — voice=${voice} model=${model} format=${format} speed=${speed}`);
console.log(`Manifest: ${manifest.items.length} phrases`);

let created = 0;
let skipped = 0;
let failed = 0;

for (const item of manifest.items) {
  const dest = path.join(ASSET_DIR, `${item.id}.${format}`);
  if (!force && fs.existsSync(dest)) {
    skipped++;
    continue;
  }
  process.stdout.write(`[${created + skipped + failed + 1}/${manifest.items.length}] ${item.jp} … `);
  try {
    const res = await fetch('https://api.openai.com/v1/audio/speech', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        voice,
        input: item.jp,
        response_format: format,
        speed,
      }),
    });
    if (!res.ok) {
      const err = await res.text();
      console.log(`ERR ${res.status} — ${err.slice(0, 120)}`);
      failed++;
      continue;
    }
    const buf = Buffer.from(await res.arrayBuffer());
    fs.writeFileSync(dest, buf);
    console.log(`✓ ${(buf.length / 1024).toFixed(1)}KB`);
    created++;
  } catch (e) {
    console.log(`ERR ${e.message}`);
    failed++;
  }
}

// Manifest'i güncelle — kullanılan voice/model bilgisini yaz.
manifest.voice = voice;
manifest.model = model;
manifest.format = format;
manifest.speed = speed;
manifest.generatedAt = new Date().toISOString();
fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2) + '\n', 'utf8');

console.log(`\nDone. created=${created} skipped=${skipped} failed=${failed}`);
if (failed > 0) process.exit(1);
