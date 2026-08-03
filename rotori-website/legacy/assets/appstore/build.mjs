#!/usr/bin/env node
// Rotori App Store screenshots — SVG → PNG @ 1290x2796
// Usage: node build.mjs

import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');
// Tanıtım sitesi rotori-website/ köküne taşındı; bu dosya legacy/assets/appstore altında.
const PREVIEW = join(__dirname, '..', '..', '..', 'appstore-preview.html');
const BUILD_DIR = join(__dirname, 'build');
const OUT_DIR = __dirname;
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

// App Store iPhone 6.7" Pro Max screenshot spec:
const W = 1290;
const H = 2796;

// Ekstrakt sahneleri (`<div class="scene">...</div>`) + endcard.
const html = await readFile(PREVIEW, 'utf-8');

const scenes = [];
const sceneRegex = /<div class="scene">([\s\S]*?)<\/div>\s*<!--/g;
let m;
while ((m = sceneRegex.exec(html)) !== null) {
  scenes.push(m[1].trim());
}
// Son sahne after all <!-- SCENE 5 --> --> </div> pattern kaybediyor; manual fallback:
if (scenes.length < 5) {
  const s5 = html.match(/<!-- SCENE 5[^>]*-->\s*<div class="scene">([\s\S]*?)<\/div>\s*<!-- END/);
  if (s5) scenes.push(s5[1].trim());
}

const endcardMatch = html.match(/<div class="endcard">([\s\S]*?)<\/div>\s*<\/div>/);
const endcard = endcardMatch ? endcardMatch[1].trim() : '';

console.log(`extracted ${scenes.length} scenes + endcard(${endcard.length}b)`);

// Ortak wrapper (1290x2796, tam ekran, siyah bg — SVG scale ile fill).
const wrapper = (title, content, isEndcard = false) => `<!doctype html>
<html><head><meta charset="utf-8"><title>${title}</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:${W}px;height:${H}px;background:#000;overflow:hidden;font-family:-apple-system,"SF Pro Text",system-ui,sans-serif}
.stage{position:relative;width:${W}px;height:${H}px;overflow:hidden;background:#050212}
${isEndcard ? `.stage{display:flex;flex-direction:column;align-items:center;justify-content:center;background:radial-gradient(circle at 50% 40%,#2E1966 0%,#0F0524 55%,#04010F 100%);color:#fff;text-align:center;padding:0 100px;gap:60px}
.stage .mark{font-size:400px;line-height:1;color:#FFC7DB;text-shadow:0 0 120px rgba(255,199,219,.4);font-family:serif;font-weight:700}
.stage .name{font-size:180px;font-weight:700;letter-spacing:-3px;background:linear-gradient(90deg,#FFC7DB 0%,#B8A8FF 50%,#FFB4C1 100%);-webkit-background-clip:text;background-clip:text;color:transparent}
.stage .tag{font-size:60px;color:#D6C8FA;opacity:.85;letter-spacing:1px}
.stage .cta{margin-top:40px;font-size:40px;color:#B8A8FF;opacity:.7;letter-spacing:12px}` :
`.stage svg{width:${W}px;height:${H}px;display:block}`}
</style>
</head>
<body><div class="stage">${content}</div></body></html>`;

// Sahne HTML dosyalarını yaz.
const names = ['01-hero', '02-plan', '03-discover', '04-meet', '05-offline'];
for (let i = 0; i < scenes.length && i < names.length; i++) {
  const path = join(BUILD_DIR, `${names[i]}.html`);
  await writeFile(path, wrapper(`Rotori ${names[i]}`, scenes[i]));
  console.log(`wrote ${path}`);
}
if (endcard) {
  const path = join(BUILD_DIR, `06-endcard.html`);
  await writeFile(path, wrapper('Rotori endcard', endcard, true));
  console.log(`wrote ${path}`);
}

// Chrome headless ile PNG'e çevir.
const filesToShoot = [
  ...names.map(n => ({ src: `${n}.html`, out: `${n}.png` })),
  { src: '06-endcard.html', out: '06-endcard.png' },
];

for (const { src, out } of filesToShoot) {
  const srcPath = join(BUILD_DIR, src);
  const outPath = join(OUT_DIR, out);
  console.log(`\nrendering ${src} → ${out}...`);
  await new Promise((resolve, reject) => {
    const args = [
      '--headless=new',
      '--disable-gpu',
      '--hide-scrollbars',
      '--force-device-scale-factor=1',
      `--window-size=${W},${H}`,
      `--screenshot=${outPath}`,
      '--default-background-color=00000000',
      '--virtual-time-budget=3000',
      `file://${srcPath}`,
    ];
    const p = spawn(CHROME, args, { stdio: 'inherit' });
    p.on('exit', (code) => code === 0 ? resolve() : reject(new Error(`chrome exit ${code}`)));
    p.on('error', reject);
  });
}

console.log('\n✅ all PNGs generated in', OUT_DIR);
