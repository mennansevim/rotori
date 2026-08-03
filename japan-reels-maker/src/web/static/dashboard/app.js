// =========================================================================
// app.js — Router + sidebar + account · Japonya Rüyası İçerik Stüdyosu
// =========================================================================
import { api, el, icons } from './lib.js';
import { renderOverview } from './pages/overview.js';
import { renderCreate, openCreateModal } from './pages/create.js';
import { renderLibrary } from './pages/library.js';
import { renderAutomation } from './pages/automation.js';
import { renderPublishes } from './pages/publishes.js';
import { renderSettings } from './pages/settings.js';

const ROUTES = [
  { key: 'overview', label: 'Genel Bakış', icon: icons.overview, render: renderOverview },
  { key: 'create', label: 'İçerik Üret', icon: icons.create, render: renderCreate },
  { key: 'library', label: 'Kütüphane', icon: icons.library, render: renderLibrary },
  { key: 'automation', label: 'Otomasyon', icon: icons.automation, render: renderAutomation },
  { key: 'publishes', label: 'Yayınlar', icon: icons.publishes, render: renderPublishes },
  { key: 'settings', label: 'Ayarlar', icon: icons.settings, render: renderSettings },
];

const pageRoot = document.getElementById('page-root');
const nav = document.getElementById('nav');
let current = { key: 'overview', params: null };

// Route parse: "library:pending_approval" → { key:'library', params:{status/tab:'...'} }
function parseHash() {
  const raw = (location.hash || '#overview').slice(1);
  const [key, arg] = raw.split(':');
  const route = ROUTES.find((r) => r.key === key) || ROUTES[0];
  let params = null;
  if (arg) {
    if (route.key === 'library') params = { status: arg };
    else if (route.key === 'create') params = { tab: arg };
  }
  return { route, params };
}

const ctx = {
  navigate(to) { location.hash = '#' + to; },
  refresh() { renderCurrent(); },
  get serverNow() { return null; },
};

async function renderCurrent() {
  const { route, params } = parseHash();
  current = { key: route.key, params };
  // sidebar aktiflik
  nav.querySelectorAll('.nav__item').forEach((n) =>
    n.classList.toggle('is-active', n.dataset.key === route.key));
  document.getElementById('sidebar').classList.remove('is-open');
  window.scrollTo(0, 0);
  try {
    await route.render(pageRoot, ctx, params);
  } catch (e) {
    pageRoot.innerHTML = '';
    pageRoot.append(el('div', { class: 'page' },
      el('div', { class: 'state' },
        el('div', { class: 'state__title' }, 'Sayfa yüklenemedi'),
        el('div', { class: 'state__msg' }, e.message))));
    console.error(e);
  }
}

function buildNav() {
  nav.innerHTML = '';
  for (const r of ROUTES) {
    nav.append(el('button', {
      class: 'nav__item', dataset: { key: r.key },
      onclick: () => { if (r.key === 'create') openCreateModal(ctx, 'gorsel'); else ctx.navigate(r.key); },
      html: r.icon + `<span>${r.label}</span>`,
    }));
  }
}

async function loadAccount() {
  const dot = document.getElementById('acc-dot');
  const state = document.getElementById('acc-state');
  const name = document.getElementById('acc-name');
  try {
    const ig = await api.instagramStatus();
    if (ig.username) name.textContent = '@' + ig.username;
    if (ig.enabled) { dot.className = 'dot is-on'; state.textContent = 'Instagram · Bağlı'; }
    else { dot.className = 'dot is-off'; state.textContent = 'Instagram · Bağlantı yok'; }
  } catch {
    dot.className = 'dot is-off'; state.textContent = 'Durum alınamadı';
  }
}

// Mobil menü
document.getElementById('hamburger')?.addEventListener('click', () => {
  document.getElementById('sidebar').classList.toggle('is-open');
});

window.addEventListener('hashchange', renderCurrent);

buildNav();
loadAccount();
if (!location.hash) location.hash = '#overview';
renderCurrent();
