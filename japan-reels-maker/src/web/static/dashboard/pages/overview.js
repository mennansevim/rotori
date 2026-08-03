// =========================================================================
// pages/overview.js — Genel Bakış
// =========================================================================
import { api, el, icons, typeBadge, countdownText, fmtDate, fmtTime,
         emptyState, errorState, loadingState, toast } from '../lib.js';
import { openContentModal } from '../modals.js';
import { openCreateModal } from './create.js';

function statCard(tint, icon, label, value, hint) {
  return el('div', { class: `stat stat--tint-${tint}` },
    el('div', { class: 'stat__icon', html: icon }),
    el('div', {},
      el('div', { class: 'stat__label' }, label),
      el('div', { class: 'stat__value' }, value),
      hint ? el('div', { class: 'stat__hint' }, hint) : null));
}

function timelineView(tl) {
  const grid = el('div', { class: 'timeline' });
  for (const day of tl.days) {
    const col = el('div', { class: `timeline__col ${day.is_today ? 'is-today' : ''}` },
      el('div', { class: 'timeline__day' }, day.day_name),
      el('div', { class: 'timeline__date' }, day.date_label));
    if (!day.items.length) {
      col.append(el('div', { class: 'timeline__empty' }, '—'));
    } else {
      for (const it of day.items) {
        col.append(el('div', { class: 'tl-item' },
          el('div', { class: 'tl-item__time' },
            el('span', { class: `tl-item__dot ${it.type}` }),
            it.time,
            el('span', { html: typeBadge(it.type), style: 'margin-left:auto' })),
          el('div', { class: 'tl-item__title' }, it.title),
          el('div', { class: 'tl-item__cd' }, it.countdown)));
      }
    }
    grid.append(col);
  }
  return grid;
}

export async function renderOverview(root, ctx) {
  root.innerHTML = '';
  const head = el('div', { class: 'page__head' },
    el('div', {},
      el('h1', { class: 'page__title' }, 'Genel Bakış'),
      el('div', { class: 'page__subtitle', id: 'ov-date' }, '')),
    el('div', { class: 'page__actions' },
      el('button', { class: 'btn btn--primary', onclick: () => openCreateModal(ctx, 'gorsel'), html: icons.plus + '<span>Yeni İçerik</span>' })));
  root.append(head);

  const body = el('div', { class: 'stack' });
  body.append(loadingState(88));
  root.append(body);

  let data;
  try {
    data = await api.overview();
  } catch (e) {
    body.innerHTML = '';
    body.append(errorState(e.message, () => renderOverview(root, ctx)));
    return;
  }

  document.getElementById('ov-date').textContent = data.date_label;
  const c = data.counts;
  const next = data.next_publish;
  body.innerHTML = '';

  // Özet kartlar
  body.append(el('div', { class: 'stat-grid' },
    statCard('amber', icons.draft, 'Taslaklar', c.drafts, 'Devam eden içerikler'),
    statCard('red', icons.clock, 'Onay Bekleyen', c.pending_approval, 'Onayınızı bekleyen'),
    statCard('green', icons.calendar, 'Bu Hafta Yayın', c.week_publishes, 'Planlanan içerik'),
    statCard('blue', icons.clock, 'Sıradaki Yayın',
      next ? countdownText(next.scheduled_at, data.now) : '—',
      next ? `${fmtDate(next.scheduled_at)} · ${fmtTime(next.scheduled_at)}` : 'Kuyruk boş')));

  // Timeline
  body.append(el('div', { class: 'card' },
    el('div', { class: 'card__head' }, el('h3', {}, 'Bu Hafta Yayın Takvimi')),
    el('div', { style: 'padding:8px 12px' }, timelineView(data.timeline))));

  // Alt 3 kolon
  const cols = el('div', { class: 'grid-3' });

  // Onay bekleyenler
  const pendingCard = el('div', { class: 'card' },
    el('div', { class: 'card__head' },
      el('h3', {}, 'Onay Bekleyenler'),
      el('button', { class: 'btn btn--ghost btn--sm', onclick: () => ctx.navigate('library:pending_approval') }, 'Tümünü Gör')));
  const pendingBody = el('div', { class: 'card__body', style: 'padding-top:8px' });
  if (!data.pending_approval.length) {
    pendingBody.append(emptyState(icons.inbox, 'Onayınızı bekleyen içerik bulunmuyor.'));
  } else {
    const list = el('div', { class: 'rowlist' });
    for (const it of data.pending_approval) {
      list.append(el('div', { class: 'rowitem' },
        el('img', { class: 'rowitem__thumb', src: it.url, alt: it.title, loading: 'lazy' }),
        el('div', { class: 'rowitem__main' },
          el('div', { class: 'rowitem__title' }, it.title),
          el('div', { class: 'rowitem__sub', html: typeBadge(it.type) + '<span>Onay bekliyor</span>' })),
        el('div', { class: 'rowitem__actions' },
          el('button', { class: 'btn btn--sm', title: 'Önizle', onclick: () => openContentModal(it, ctx) , html: icons.eye }),
          el('button', { class: 'btn btn--sm btn--ok', title: 'Onayla', onclick: () => approveQuick(it, ctx), html: icons.check }),
          el('button', { class: 'btn btn--sm btn--danger', title: 'Reddet', onclick: () => rejectQuick(it, ctx), html: icons.x }))));
    }
    pendingBody.append(list);
  }
  pendingCard.append(pendingBody);

  // Yayına hazır sırası
  const readyCard = el('div', { class: 'card' },
    el('div', { class: 'card__head' },
      el('h3', {}, 'Yayına Hazır Sırası'),
      el('button', { class: 'btn btn--ghost btn--sm', onclick: () => ctx.navigate('publishes') }, 'Tümünü Gör')));
  const readyBody = el('div', { class: 'card__body', style: 'padding-top:8px' });
  if (!data.ready_queue.length) {
    readyBody.append(emptyState(icons.calendar, 'Yayına hazır içerik bulunmuyor.'));
  } else {
    const list = el('div', { class: 'rowlist' });
    for (const it of data.ready_queue) {
      list.append(el('div', { class: 'rowitem' },
        el('div', { class: 'orderbadge' }, it.order),
        el('div', { class: 'rowitem__main' },
          el('div', { class: 'rowitem__title' }, it.title),
          el('div', { class: 'rowitem__sub', html: typeBadge(it.type) + `<span>${fmtDate(it.scheduled_at)} · ${fmtTime(it.scheduled_at)}</span>` })),
        el('div', { class: 'rowitem__cd' }, it.countdown)));
    }
    readyBody.append(list);
  }
  readyCard.append(readyBody);

  // Hızlı işlemler
  const quickCard = el('div', { class: 'card' },
    el('div', { class: 'card__head' }, el('h3', {}, 'Hızlı İşlemler')),
    el('div', { class: 'card__body vstack', style: 'gap:10px' },
      quickAction(icons.sparkle, 'Görsel Üret', 'AI ile görsel taslağı oluştur', () => openCreateModal(ctx, 'gorsel')),
      quickAction(icons.news, 'Haber Üret', 'Haber metni oluştur ve düzenle', () => openCreateModal(ctx, 'haber')),
      quickAction(icons.library, 'Kütüphaneyi Aç', 'Tüm içeriklere göz at', () => ctx.navigate('library')),
      quickAction(icons.automation, 'Otomasyonu Düzenle', 'Yayın planlarını yönet', () => ctx.navigate('automation'))));

  cols.append(pendingCard, readyCard, quickCard);
  body.append(cols);
  body.append(el('div', { class: 'foot-note', html: 'Üret → Onayla → Sıraya Al → Yayınla<br><b>İçerik akışınız kontrolünüzde.</b>' }));
}

function quickAction(icon, title, sub, onclick) {
  return el('button', { class: 'quick', onclick },
    el('span', { class: 'quick__icon', html: icon }),
    el('span', {}, el('div', { class: 'quick__title' }, title), el('div', { class: 'quick__sub' }, sub)),
    el('span', { class: 'quick__chev', html: icons.chevron }));
}

async function approveQuick(it, ctx) {
  try {
    await api.approvalMarkReady(it.name);
    toast('İçerik yayına hazır sırasına alındı.', 'ok');
    ctx.refresh();
  } catch (e) { toast(e.message, 'err'); }
}
async function rejectQuick(it, ctx) {
  const { confirmModal } = await import('../lib.js');
  if (!(await confirmModal({ title: 'İçeriği reddet', message: `"${it.title}" reddedilecek ve silinecek. Bu işlem geri alınamaz.`, confirmLabel: 'Reddet', danger: true }))) return;
  try { await api.approvalReject(it.name); toast('İçerik reddedildi.', 'ok'); ctx.refresh(); }
  catch (e) { toast(e.message, 'err'); }
}
