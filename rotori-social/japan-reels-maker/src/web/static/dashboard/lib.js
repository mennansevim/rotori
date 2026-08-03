// =========================================================================
// lib.js — API istemcisi, ikonlar, toast, modal, ortak yardımcılar
// =========================================================================

/* ----------------------------------------------------------------- API */
async function req(method, url, body) {
  const opts = { method, headers: {} };
  if (body !== undefined) {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(body);
  }
  const res = await fetch(url, opts);
  let data = null;
  const ct = res.headers.get('content-type') || '';
  if (ct.includes('application/json')) {
    data = await res.json().catch(() => null);
  }
  if (!res.ok) {
    const detail = (data && (data.detail || data.message)) || `HTTP ${res.status}`;
    const err = new Error(typeof detail === 'string' ? detail : JSON.stringify(detail));
    err.status = res.status;
    throw err;
  }
  return data;
}

export const api = {
  get: (u) => req('GET', u),
  post: (u, b) => req('POST', u, b),
  del: (u) => req('DELETE', u),
  // Toplu durum
  overview: () => req('GET', '/api/dashboard/overview'),
  library: () => req('GET', '/api/dashboard/library'),
  publishes: () => req('GET', '/api/dashboard/publishes'),
  automationState: () => req('GET', '/api/dashboard/automation'),
  // Onay akışı (mevcut endpoint'ler)
  approvalUpdate: (name, b) => req('POST', `/api/approval/update/${encodeURIComponent(name)}`, b),
  approvalMarkReady: (name) => req('POST', `/api/approval/mark_ready/${encodeURIComponent(name)}`),
  approvalReject: (name) => req('POST', `/api/approval/reject/${encodeURIComponent(name)}`),
  // Kuyruk
  autoFillReady: () => req('POST', '/api/scheduler/auto_fill_ready'),
  scheduleStory: (b) => req('POST', '/api/scheduler/schedule_story', b),
  dequeue: (id) => req('DELETE', `/api/scheduler/queue/${encodeURIComponent(id)}`),
  reschedule: (id, at) => req('POST', `/api/scheduler/reschedule/${encodeURIComponent(id)}`, { scheduled_at: at }),
  // Yayın
  publish: (name) => req('POST', `/api/instagram/publish/${encodeURIComponent(name)}`),
  // Story CRUD
  storyMeta: (name) => req('GET', `/api/story/meta/${encodeURIComponent(name)}`),
  storyUpdate: (name, b) => req('POST', `/api/story/update/${encodeURIComponent(name)}`, b),
  storyDelete: (name) => req('DELETE', `/api/story/${encodeURIComponent(name)}`),
  // Üretim
  aiFromText: (b) => req('POST', '/api/story/ai_from_text', b),
  aiFromImage: (b) => req('POST', '/api/story/ai_from_image', b),
  bgPreview: (b) => req('POST', '/api/backgrounds/preview', b),
  renderDirect: (b) => req('POST', '/api/story/render_direct', b),
  expandCaption: (b) => req('POST', '/api/story/expand_caption', b),
  // Otomasyon
  automationConfigGet: () => req('GET', '/api/automation/config'),
  automationConfigSet: (b) => req('POST', '/api/automation/config', b),
  automationRunNow: (b) => req('POST', '/api/automation/run_now', b),
  // Durum
  instagramStatus: () => req('GET', '/api/instagram/status'),
  jobStatus: () => req('GET', '/api/status'),
  jobLogs: (since = 0) => req('GET', `/api/logs?since=${encodeURIComponent(since)}`),
  jobCancel: () => req('POST', '/api/cancel'),
};

/* ------------------------------------------------------------- Yardımcılar */
export const el = (tag, attrs = {}, ...children) => {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null) continue;
    if (k === 'class') n.className = v;
    else if (k === 'html') n.innerHTML = v;
    else if (k.startsWith('on') && typeof v === 'function') n.addEventListener(k.slice(2), v);
    else if (k === 'dataset') Object.assign(n.dataset, v);
    else n.setAttribute(k, v);
  }
  for (const c of children.flat()) {
    if (c == null || c === false) continue;
    n.append(c.nodeType ? c : document.createTextNode(String(c)));
  }
  return n;
};

export const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

export const typeBadge = (type) =>
  type === 'haber'
    ? `<span class="badge badge--haber">Haber</span>`
    : `<span class="badge badge--gorsel">Görsel</span>`;

const STATUS_BADGE = {
  draft: ['muted', 'Taslak'],
  pending_approval: ['warn', 'Onay bekliyor'],
  approved: ['ok', 'Onaylandı'],
  queued: ['ok', 'Kuyrukta'],
  scheduled: ['ok', 'Planlandı'],
  publishing: ['warn', 'Yayınlanıyor'],
  published: ['ok', 'Yayınlandı'],
  rejected: ['danger', 'Reddedildi'],
  failed: ['danger', 'Hata'],
};
export const statusBadge = (status) => {
  const [tone, label] = STATUS_BADGE[status] || ['muted', status];
  return `<span class="badge badge--${tone}">${esc(label)}</span>`;
};

export const fmtDate = (iso) => {
  if (!iso) return '—';
  try {
    const d = new Date(iso.length <= 10 ? iso + 'T00:00:00' : iso);
    return d.toLocaleDateString('tr-TR', { day: 'numeric', month: 'long', year: 'numeric' });
  } catch { return iso; }
};
export const fmtTime = (iso) => {
  if (!iso) return '';
  try { return new Date(iso).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' }); }
  catch { return ''; }
};

// Sunucu 'now'una göre canlı kalan süre metni (Europe/Istanbul offset hesabı sunucuda)
export const countdownText = (scheduledAt, serverNowIso) => {
  if (!scheduledAt) return '—';
  const target = new Date(scheduledAt).getTime();
  const now = serverNowIso ? new Date(serverNowIso).getTime() : Date.now();
  let secs = Math.floor((target - now) / 1000);
  if (secs < 0) return 'Yayın zamanı geçti';
  const d = Math.floor(secs / 86400); secs -= d * 86400;
  const h = Math.floor(secs / 3600); secs -= h * 3600;
  const m = Math.floor(secs / 60);
  if (d > 0) return `${d} gün ${h} saat kaldı`;
  if (h > 0) return `${h} saat ${m} dakika kaldı`;
  if (m > 0) return `${m} dakika kaldı`;
  return 'birazdan';
};

/* ------------------------------------------------------------- İkonlar */
const I = (p, extra = '') => `<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" ${extra}>${p}</svg>`;
export const icons = {
  overview: I('<rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/>'),
  create: I('<path d="M12 3v18M5 8l7-5 7 5M5 16l7 5 7-5"/>'),
  library: I('<path d="M4 6h16M4 12h16M4 18h10"/><rect x="3" y="3" width="18" height="18" rx="2"/>'),
  automation: I('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 3"/>'),
  publishes: I('<path d="M22 2 11 13M22 2l-7 20-4-9-9-4 20-7z"/>'),
  settings: I('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-2.7 1.1V21a2 2 0 1 1-4 0v-.1a1.6 1.6 0 0 0-2.7-1.1l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.6 1.6 0 0 0-1.1-2.7H3a2 2 0 1 1 0-4h.1a1.6 1.6 0 0 0 1.1-2.7l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 2.7-1.1V3a2 2 0 1 1 4 0v.1a1.6 1.6 0 0 0 2.7 1.1l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8 1.6 1.6 0 0 0 1.4.9H21a2 2 0 1 1 0 4h-.1a1.6 1.6 0 0 0-1.5.9z"/>'),
  draft: I('<path d="M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>'),
  clock: I('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'),
  calendar: I('<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>'),
  check: I('<path d="M20 6 9 17l-5-5"/>'),
  x: I('<path d="M18 6 6 18M6 6l12 12"/>'),
  eye: I('<path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7S1 12 1 12z"/><circle cx="12" cy="12" r="3"/>'),
  edit: I('<path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.1 2.1 0 0 1 3 3L12 15l-4 1 1-4z"/>'),
  refresh: I('<path d="M23 4v6h-6M1 20v-6h6"/><path d="M3.5 9a9 9 0 0 1 14.9-3.4L23 10M1 14l4.6 4.4A9 9 0 0 0 20.5 15"/>'),
  dots: I('<circle cx="12" cy="5" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="12" cy="19" r="1.5"/>'),
  search: I('<circle cx="11" cy="11" r="8"/><path d="M21 21l-4.3-4.3"/>'),
  plus: I('<path d="M12 5v14M5 12h14"/>'),
  sparkle: I('<path d="M12 3l1.9 5.1L19 10l-5.1 1.9L12 17l-1.9-5.1L5 10l5.1-1.9L12 3z"/>'),
  news: I('<path d="M4 22h16a2 2 0 0 0 2-2V4a2 2 0 0 0-2-2H8a2 2 0 0 0-2 2v16a2 2 0 0 1-2 2zm0 0a2 2 0 0 1-2-2v-9h4"/><path d="M18 14h-8M15 18h-5M10 6h8v4h-8V6z"/>'),
  image: I('<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="M21 15l-5-5L5 21"/>'),
  chevron: I('<path d="M9 18l6-6-6-6"/>'),
  trash: I('<path d="M3 6h18M8 6V4a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v2M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/>'),
  heart: I('<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1-1.1a5.5 5.5 0 0 0-7.8 7.8l1 1L12 21l7.8-7.6 1-1a5.5 5.5 0 0 0 0-7.8z"/>'),
  bookmark: I('<path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/>'),
  file: I('<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>'),
  send: I('<path d="M22 2 11 13M22 2l-7 20-4-9-9-4 20-7z"/>'),
  link: I('<path d="M10 13a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1 1"/><path d="M14 11a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1-1"/>'),
  inbox: I('<path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5 5h14l3 7v6a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2v-6z"/>'),
};

/* ------------------------------------------------------------- Toast */
export function toast(msg, kind = '') {
  const wrap = document.getElementById('toasts');
  const t = el('div', { class: `toast ${kind ? 'toast--' + kind : ''}` },
    el('span', { html: kind === 'ok' ? icons.check : kind === 'err' ? icons.x : icons.clock }),
    el('span', {}, msg));
  wrap.append(t);
  setTimeout(() => { t.style.opacity = '0'; setTimeout(() => t.remove(), 250); }, 3400);
}

/* ------------------------------------------------------------- Modal */
export function openModal({ title, body, footer, wide = false, onClose }) {
  const root = document.getElementById('modal-root');
  const close = () => { backdrop.remove(); document.removeEventListener('keydown', onKey); onClose && onClose(); };
  const onKey = (e) => { if (e.key === 'Escape') close(); };
  const modal = el('div', { class: `modal ${wide ? 'modal--wide' : ''}`, role: 'dialog', 'aria-modal': 'true' },
    el('div', { class: 'modal__head' },
      el('h3', { class: 'modal__title' }, title),
      el('button', { class: 'modal__close', 'aria-label': 'Kapat', onclick: close, html: icons.x })),
    el('div', { class: 'modal__body' }, body));
  if (footer) modal.append(el('div', { class: 'modal__foot' }, footer));
  const backdrop = el('div', { class: 'modal-backdrop', onclick: (e) => { if (e.target === backdrop) close(); } }, modal);
  root.append(backdrop);
  document.addEventListener('keydown', onKey);
  const focusable = modal.querySelector('input, textarea, button:not(.modal__close), select');
  focusable && focusable.focus();
  return { close, modal };
}

export function confirmModal({ title, message, confirmLabel = 'Onayla', danger = false }) {
  return new Promise((resolve) => {
    let ctl;
    const cancel = el('button', { class: 'btn', onclick: () => { ctl.close(); resolve(false); } }, 'Vazgeç');
    const ok = el('button', { class: `btn ${danger ? 'btn--danger' : 'btn--primary'}`, onclick: () => { ctl.close(); resolve(true); } }, confirmLabel);
    ctl = openModal({ title, body: el('p', { class: 'muted' }, message), footer: [cancel, ok], onClose: () => resolve(false) });
  });
}

/* --------------------------------------------------------- Boş/hata durumu */
export function emptyState(icon, title, msg) {
  return el('div', { class: 'state' },
    el('div', { class: 'state__icon', html: icon }),
    el('div', { class: 'state__title' }, title),
    msg ? el('div', { class: 'state__msg' }, msg) : null);
}
export function errorState(msg, onRetry) {
  const box = el('div', { class: 'state' },
    el('div', { class: 'state__icon', html: icons.x }),
    el('div', { class: 'state__title' }, 'Bir hata oluştu'),
    el('div', { class: 'state__msg' }, msg || 'Veri alınamadı.'));
  if (onRetry) box.append(el('button', { class: 'btn btn--sm', style: 'margin-top:12px', onclick: onRetry }, 'Tekrar Dene'));
  return box;
}
export function loadingState(h = 120) {
  return el('div', { class: 'skeleton', style: `height:${h}px;width:100%` });
}
