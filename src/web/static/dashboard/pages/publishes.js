// =========================================================================
// pages/publishes.js — Yayınlar (yaklaşan + yayınlanan)
// =========================================================================
import { api, el, icons, typeBadge, statusBadge, countdownText, fmtDate, fmtTime,
         emptyState, errorState, loadingState, toast, confirmModal, openModal } from '../lib.js';
import { openCreateModal } from './create.js';

export async function renderPublishes(root, ctx) {
  root.innerHTML = '';
  const head = el('div', { class: 'page__head' },
    el('div', {},
      el('h1', { class: 'page__title' }, 'Yayınlar'),
      el('div', { class: 'page__subtitle' }, 'Planlanan ve yayınlanan içeriklerin takibi.')),
    el('div', { class: 'page__actions' },
      el('button', { class: 'btn btn--primary', onclick: () => openCreateModal(ctx, 'gorsel'), html: icons.plus + '<span>Yeni İçerik</span>' })));
  root.append(head);

  const body = el('div', { class: 'stack' });
  body.append(loadingState(120));
  root.append(body);

  let data;
  try { data = await api.publishes(); }
  catch (e) { body.innerHTML = ''; body.append(errorState(e.message, () => renderPublishes(root, ctx))); return; }

  body.innerHTML = '';
  const now = data.now;

  // Özet
  const nextUp = data.upcoming.find((u) => u.status === 'scheduled') || data.upcoming[0];
  body.append(el('div', { class: 'stat-grid' },
    stat('green', icons.calendar, 'Bu Hafta', weekCount(data.timeline), 'yayın planlandı'),
    stat('blue', icons.clock, 'Sıradaki Yayın', nextUp ? countdownText(nextUp.scheduled_at, now) : '—', nextUp ? `${fmtDate(nextUp.scheduled_at)} · ${fmtTime(nextUp.scheduled_at)}` : 'Kuyruk boş'),
    stat('amber', icons.file, 'Yayınlanan', data.published.length, 'içerik yayınlandı'),
    stat('red', icons.send, 'Yaklaşan', data.upcoming.length, 'içerik kuyrukta')));

  const cols = el('div', { class: 'grid-2' });

  // Yaklaşan
  const upCard = el('div', { class: 'card' },
    el('div', { class: 'card__head' }, el('h3', {}, 'Yaklaşan Yayınlar')));
  const upBody = el('div', { class: 'card__body', style: 'padding-top:6px' });
  if (!data.upcoming.length) upBody.append(emptyState(icons.calendar, 'Yayına hazır içerik bulunmuyor.'));
  else {
    const list = el('div', { class: 'rowlist' });
    for (const it of data.upcoming) list.append(upcomingRow(it, ctx, now));
    upBody.append(list);
  }
  upCard.append(upBody);

  // Yayınlanan
  const pubCard = el('div', { class: 'card' },
    el('div', { class: 'card__head' }, el('h3', {}, 'Yayınlananlar')));
  const pubBody = el('div', { class: 'card__body', style: 'padding-top:6px' });
  if (!data.published.length) pubBody.append(emptyState(icons.send, 'Henüz yayınlanan içerik yok.'));
  else {
    const list = el('div', { class: 'rowlist' });
    for (const it of data.published) list.append(publishedRow(it, data.metrics_available));
    pubBody.append(list);
  }
  pubCard.append(pubBody);

  cols.append(upCard, pubCard);
  body.append(cols);
}

function stat(tint, icon, label, value, hint) {
  return el('div', { class: `stat stat--tint-${tint}` },
    el('div', { class: 'stat__icon', html: icon }),
    el('div', {}, el('div', { class: 'stat__label' }, label),
      el('div', { class: 'stat__value', style: 'font-size:20px' }, value),
      el('div', { class: 'stat__hint' }, hint)));
}
function weekCount(tl) { return tl.days.reduce((n, d) => n + d.items.length, 0); }

function upcomingRow(it, ctx, now) {
  const actions = el('div', { class: 'rowitem__actions' });
  if (it.status === 'failed') {
    actions.append(el('button', { class: 'btn btn--sm btn--accent', title: 'Tekrar dene',
      onclick: () => retry(it, ctx), html: icons.refresh }));
  }
  actions.append(
    el('button', { class: 'btn btn--sm', title: 'Tarihi düzenle', onclick: () => editSchedule(it, ctx), html: icons.calendar }),
    el('button', { class: 'btn btn--sm btn--danger', title: 'Kuyruktan çıkar', onclick: () => remove(it, ctx), html: icons.x }));

  const sub = el('div', { class: 'rowitem__sub', html: typeBadge(it.type) });
  sub.append(el('span', {}, `${fmtDate(it.scheduled_at)} · ${fmtTime(it.scheduled_at)}`),
    el('span', { html: statusBadge(it.status) }));
  if (it.status === 'failed' && it.error)
    sub.append(el('span', { class: 'badge badge--danger', title: String(it.error) }, 'Hata: ' + shortErr(it.error)));

  return el('div', { class: 'rowitem' },
    it.url ? el('img', { class: 'rowitem__thumb', src: it.url, alt: it.title, loading: 'lazy' })
           : el('div', { class: 'rowitem__thumb' }),
    el('div', { class: 'rowitem__main' }, el('div', { class: 'rowitem__title' }, it.title), sub),
    el('div', { class: 'rowitem__cd' }, it.countdown),
    actions);
}

function publishedRow(it, metricsAvailable) {
  const right = el('div', { class: 'hstack', style: 'gap:18px' });
  if (it.metrics) {
    right.append(
      metric(icons.heart, it.metrics.likes ?? '—', 'Beğeni'),
      metric(icons.eye, it.metrics.reach ?? '—', 'Erişim'),
      metric(icons.bookmark, it.metrics.saves ?? '—', 'Kaydetme'));
  } else {
    right.append(el('span', { class: 'muted', style: 'font-size:12px' }, 'Veri henüz alınamadı'));
  }
  const sub = el('div', { class: 'rowitem__sub', html: typeBadge(it.type) });
  sub.append(el('span', {}, it.uploaded_at ? fmtDate(it.uploaded_at) + ' · ' + fmtTime(it.uploaded_at) : ''));
  if (it.permalink) sub.append(el('a', { href: it.permalink, target: '_blank', class: 'hstack', style: 'gap:3px', html: icons.link + '<span>Instagram</span>' }));

  return el('div', { class: 'rowitem' },
    it.url ? el('img', { class: 'rowitem__thumb', src: it.url, alt: it.title, loading: 'lazy' })
           : el('div', { class: 'rowitem__thumb' }),
    el('div', { class: 'rowitem__main' }, el('div', { class: 'rowitem__title' }, it.title), sub),
    right);
}

function metric(icon, val, label) {
  return el('div', { class: 'metric' },
    el('div', { class: 'metric__val hstack', style: 'gap:4px;justify-content:center' }, el('span', { html: icon }), String(val)),
    el('div', { class: 'metric__label' }, label));
}
function shortErr(e) { const s = typeof e === 'string' ? e : JSON.stringify(e); return s.length > 40 ? s.slice(0, 40) + '…' : s; }

async function retry(it, ctx) {
  try { await api.reschedule(it.entry_id, it.scheduled_at); toast('Tekrar kuyruğa alındı.', 'ok'); ctx.refresh(); }
  catch (e) { toast(e.message, 'err'); }
}
async function remove(it, ctx) {
  if (!(await confirmModal({ title: 'Kuyruktan çıkar', message: `"${it.title}" yayın kuyruğundan çıkarılacak.`, confirmLabel: 'Çıkar', danger: true }))) return;
  try { await api.dequeue(it.entry_id); toast('Kuyruktan çıkarıldı.', 'ok'); ctx.refresh(); }
  catch (e) { toast(e.message, 'err'); }
}
function editSchedule(it, ctx) {
  const input = el('input', { class: 'input', type: 'datetime-local', style: 'width:100%',
    value: (it.scheduled_at || '').slice(0, 16) });
  let ctl;
  const cancel = el('button', { class: 'btn', onclick: () => ctl.close() }, 'Vazgeç');
  const save = el('button', { class: 'btn btn--primary', onclick: async () => {
    const v = input.value; if (!v) { toast('Tarih seçin.', 'err'); return; }
    try { await api.reschedule(it.entry_id, v.length === 16 ? v + ':00' : v); toast('Yayın zamanı güncellendi.', 'ok'); ctl.close(); ctx.refresh(); }
    catch (e) { toast(e.message, 'err'); }
  } }, 'Kaydet');
  ctl = openModal({ title: 'Yayın Zamanını Düzenle',
    body: el('div', { class: 'field' }, el('label', { class: 'field__label' }, 'Planlanan Tarih ve Saat'), input),
    footer: [cancel, save] });
}
