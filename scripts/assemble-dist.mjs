import { cpSync, mkdirSync, rmSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'dist');

if (existsSync(dist)) {
  rmSync(dist, { recursive: true });
}
mkdirSync(dist, { recursive: true });

cpSync(join(root, 'index.html'), join(dist, 'index.html'));
cpSync(join(root, 'data'), join(dist, 'data'), { recursive: true });

const viewerDist = join(root, 'apps/viewer/dist');
const plannerDist = join(root, 'apps/planner/dist');
const sitesWorker = join(root, 'sites/worker/index.js');

if (existsSync(viewerDist)) {
  cpSync(viewerDist, join(dist, 'viewer'), { recursive: true });
}
if (existsSync(plannerDist)) {
  cpSync(plannerDist, join(dist, 'planner'), { recursive: true });
}
if (existsSync(sitesWorker)) {
  mkdirSync(join(dist, 'server'), { recursive: true });
  cpSync(sitesWorker, join(dist, 'server/index.js'));
}

console.log('dist/ hazır: index.html, data/, viewer/, planner/, server/');
