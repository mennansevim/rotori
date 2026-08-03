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

if (existsSync(viewerDist)) {
  cpSync(viewerDist, join(dist, 'viewer'), { recursive: true });
}
if (existsSync(plannerDist)) {
  cpSync(plannerDist, join(dist, 'planner'), { recursive: true });
}

console.log('dist/ hazır: index.html, data/, viewer/, planner/');
