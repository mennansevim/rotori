// =========================================================================
// pages/library.js — Kütüphane
// =========================================================================
import { api, el, icons, typeBadge, statusBadge, countdownText, fmtDate, fmtTime,
         emptyState, errorState, loadingState, toast, confirmModal, openModal } from '../lib.js';
import { openContentModal, regenerate } from '../modals.js';
import { openCreateModal } from './create.js';

const STATUS_FILTERS = [
  ['all', 'Tümü'],
  ['ready', 'Yayına Hazır'],
  ['draft', 'Taslak'],
  ['published', 'Yayınlandı'],
];

export async function renderLibrary(root, ctx, params) {
  root.innerHTML = '';
  const state = { status: (params && params.status) || 'all', type: 'all', q: '', sort: 'new' };

  const head = el('div', { class: 'page__head' },
    el('div', {},
      el('h1', { class: 'page__title' }, 'Kütüphane'),
      el('div', { class: 'page__subtitle' }, 'Üretilen tüm içerikler burada yönetilir. Yayına almadan önce inceleyin.')),
    el('div', { class: 'page__actions' },
      el('button', { class: 'btn', onclick: () => ctx.navigate('automation'), html: icons.automation + '<span>Otomasyon</span>' }),
      el('button', { class: 'btn btn--primary', onclick: () => openCreateModal(ctx, 'gorsel'), html: icons.plus + '<span>İçerik Üret</span>' })));
  root.append(head);

  const filterbar = el('div', { class: 'filterbar' });
  root.append(filterbar);

  const layout = el('div', { class: 'lib-layout' });
  const gridWrap = el('div', {});
  const side = el('div', { class: 'stack' });
  layout.append(gridWrap, side);
  root.append(layout);

  gridWrap.append(loadingState(300));

  let data;
  try { data = await api.library(); }
  catch (e) { gridWrap.innerHTML = ''; gridWrap.append(errorState(e.message, () => renderLibrary(root, ctx, params))); return; }

  const rebuildFilters = () => {
    filterbar.innerHTML = '';
    for (const [key, label] of STATUS_FILTERS) {
      const count = key === 'all' ? data.counts.all
        : key === 'ready' ? data.counts.ready
        : data.counts[key] ?? 0;
      filterbar.append(el('button', {
        class: `chip ${state.status === key ? 'is-active' : ''}`,
        onclick: () => { state.status = key; renderGrid(); rebuildFilters(); },
      }, label, el('span', { class: 'chip__count' }, count)));
    }
    filterbar.append(el('span', { class: 'filterbar__spacer' }));
    // tip filtresi
    const typeSel = el('select', { class: 'select', onchange: (e) => { state.type = e.target.value; renderGrid(); } },
      el('option', { value: 'all' }, 'Tüm tipler'),
      el('option', { value: 'gorsel' }, 'Görsel'),
      el('option', { value: 'haber' }, 'Haber'));
    typeSel.value = state.type;
    // arama
    const searchBox = el('div', { class: 'search' },
      el('span', { html: icons.search }),
      el('input', { class: 'input', placeholder: 'Ara (başlık, açıklama…)', value: state.q,
        oninput: (e) => { state.q = e.target.value; renderGrid(); } }));
    const sortSel = el('select', { class: 'select', onchange: (e) => { state.sort = e.target.value; renderGrid(); } },
      el('option', { value: 'new' }, 'En yeni önce'),
      el('option', { value: 'old' }, 'En eski önce'));
    filterbar.append(searchBox, typeSel, sortSel);
  };

  const filtered = () => {
    let items = data.items.slice();
    if (state.status !== 'all') {
      if (state.status === 'ready') items = items.filter((i) => ['approved', 'queued', 'scheduled'].includes(i.status));
      else items = items.filter((i) => i.status === state.status);
    }
    if (state.type !== 'all') items = items.filter((i) => i.type === state.type);
    if (state.q.trim()) {
      const q = state.q.toLowerCase();
      items = items.filter((i) => (i.title + ' ' + (i.aciklama || '')).toLowerCase().includes(q));
    }
    items.sort((a, b) => state.sort === 'new'
      ? b.created_at.localeCompare(a.created_at)
      : a.created_at.localeCompare(b.created_at));
    return items;
  };

  const renderGrid = () => {
    gridWrap.innerHTML = '';
    const items = filtered();
    if (!items.length) {
      gridWrap.append(emptyState(icons.library,
        data.items.length ? 'Bu filtreyle eşleşen içerik yok.' : 'Henüz içerik oluşturulmadı.',
        data.items.length ? 'Filtreyi değiştirin veya aramayı temizleyin.' : 'İçerik Üret ile ilk kartınızı oluşturun.'));
      return;
    }
    const grid = el('div', { class: 'content-grid' });
    for (const it of items) grid.append(contentCard(it, ctx, data.now));
    gridWrap.append(grid);
  };

  const renderSide = () => {
    side.innerHTML = '';
    // Özet
    side.append(el('div', { class: 'card' },
      el('div', { class: 'card__head' }, el('h3', {}, 'Özet')),
      el('div', { class: 'card__body' },
        el('div', { class: 'stat-grid', style: 'grid-template-columns:1fr 1fr' },
          miniStat('green', icons.calendar, data.counts.ready, 'Yayına hazır'),
          miniStat('blue', icons.file, data.counts.all, 'Toplam içerik'),
          miniStat('red', icons.send, data.counts.published, 'Yayınlandı')))));
    // Kuyruk kısayolu
    side.append(el('div', { class: 'card' },
      el('div', { class: 'card__head' }, el('h3', {}, 'Sıraya Al')),
      el('div', { class: 'card__body vstack', style: 'gap:10px' },
        el('p', { class: 'muted', style: 'font-size:12.5px;margin:0' },
          'Yayına hazır tüm kartları otomasyon slotlarına göre haftaya dağıt.'),
        el('button', { class: 'btn btn--primary', style: 'width:100%',
          onclick: () => autoFill(ctx), html: icons.calendar + '<span>Tümünü Sıraya Al</span>' }))));
  };

  rebuildFilters();
  renderGrid();
  renderSide();
}

function miniStat(tint, icon, value, label) {
  return el('div', { class: `stat stat--tint-${tint}`, style: 'padding:14px;gap:10px' },
    el('div', { class: 'stat__icon', style: 'width:34px;height:34px', html: icon }),
    el('div', {}, el('div', { class: 'stat__value', style: 'font-size:20px' }, value),
      el('div', { class: 'stat__hint' }, label)));
}

function contentCard(it, ctx, serverNow) {
  const thumbImg = it.url
    ? el('img', { src: it.url, alt: it.title, loading: 'lazy' })
    : el('div', { class: 'content-card__noimg', 'aria-hidden': 'true', html: icons.image });
  const menuBtn = el('button', { class: 'content-card__menu', 'aria-label': 'Diğer işlemler', html: icons.dots,
    onclick: (e) => { e.stopPropagation(); openRowMenu(e.currentTarget, it, ctx, thumbImg); } });
  const thumbWrap = el('div', { class: 'content-card__thumb', role: 'button', tabindex: '0',
    'aria-label': it.title + ' — önizle', title: 'Önizle',
    onclick: () => openContentModal(it, ctx),
    onkeydown: (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openContentModal(it, ctx); } } },
    thumbImg, menuBtn);

  const isPublished = it.status === 'published';
  const isPending = ['draft', 'pending_approval'].includes(it.status);
  const isReady = ['approved', 'queued', 'scheduled', 'failed'].includes(it.status);

  // Görünür aksiyon: en fazla 2. Birincil duruma göre değişir, ikincil hep Düzenle.
  // İkincil/destructive işlemler (Yenile, Reddet/Kaldır, Sil) üç nokta menüsünde.
  const actions = el('div', { class: 'content-card__actions' });
  if (isPending) {
    actions.append(
      el('button', { class: 'btn btn--sm btn--primary', onclick: () => approve(it, ctx), html: icons.check + '<span>Onayla</span>' }),
      el('button', { class: 'btn btn--sm', onclick: () => openContentModal(it, ctx), html: icons.edit + '<span>Düzenle</span>' }));
  } else if (isReady) {
    actions.append(
      el('button', { class: 'btn btn--sm btn--primary', onclick: () => publish(it, ctx), html: icons.send + '<span>Yayınla</span>' }),
      el('button', { class: 'btn btn--sm', onclick: () => openContentModal(it, ctx), html: icons.edit + '<span>Düzenle</span>' }));
  } else if (isPublished) {
    const link = it.published && it.published.permalink;
    actions.append(
      link
        ? el('a', { class: 'btn btn--sm', href: link, target: '_blank', rel: 'noopener', html: icons.link + '<span>Instagram</span>' })
        : el('button', { class: 'btn btn--sm', onclick: () => openContentModal(it, ctx), html: icons.eye + '<span>Görüntüle</span>' }),
      el('button', { class: 'btn btn--sm', onclick: () => openContentModal(it, ctx), html: icons.edit + '<span>Düzenle</span>' }));
  }
  // Üç nokta (ikincil menü) her kartta
  actions.append(el('button', { class: 'btn btn--sm btn--icon', 'aria-label': 'Diğer işlemler',
    onclick: (e) => { e.stopPropagation(); openRowMenu(e.currentTarget, it, ctx, thumbImg); }, html: icons.dots }));

  const body = el('div', { class: 'content-card__body' },
    el('div', { class: 'content-card__badges' },
      el('span', { html: typeBadge(it.type) }), el('span', { html: statusBadge(it.status) })),
    el('div', { class: 'content-card__title clamp-2', title: it.title }, it.title),
    el('div', { class: 'content-card__meta' },
      el('div', { class: 'row' }, el('span', { html: icons.clock }), 'Oluşturuldu: ' + fmtDate(it.created_at))));

  // Planlama bilgisi tek kompakt alanda
  if (it.scheduled_at) {
    body.append(el('div', { class: 'content-card__plan' },
      el('span', { html: icons.calendar }),
      el('span', {}, fmtDate(it.scheduled_at) + ' · ' + fmtTime(it.scheduled_at)),
      it.countdown ? el('span', { class: 'cd' }, it.countdown) : null));
  }

  body.append(actions);
  return el('div', { class: 'content-card' }, thumbWrap, body);
}

function openRowMenu(anchor, it, ctx, imgNode) {
  document.querySelectorAll('.dropdown-menu').forEach((m) => m.remove());
  const rect = anchor.getBoundingClientRect();
  const menu = el('div', { class: 'dropdown-menu', role: 'menu' });
  const item = (label, icon, onclick, danger = false) => el('button', {
    class: `dropdown-item ${danger ? 'is-danger' : ''}`, role: 'menuitem',
    onclick: () => { menu.remove(); onclick(); }, html: icon + `<span>${label}</span>` });

  menu.append(item('Önizle', icons.eye, () => openContentModal(it, ctx)));
  menu.append(item('Görseli yeniden oluştur', icons.refresh, async () => {
    const ok = await regenerate(it, ctx, imgNode); if (ok) ctx.refresh();
  }));
  if (['approved', 'queued', 'scheduled', 'failed'].includes(it.status) && it.queue_entry_id) {
    menu.append(item('Kuyruktan çıkar', icons.x, () => dequeueOrReject(it, ctx), true));
  }
  if (['draft', 'pending_approval'].includes(it.status)) {
    menu.append(item('Reddet', icons.x, () => reject(it, ctx), true));
  }
  menu.append(item('Sil', icons.trash, () => del(it, ctx), true));

  // konumlandır (sağ kenara hizala, taşmayı önle)
  document.body.append(menu);
  const mw = menu.offsetWidth || 190;
  let left = rect.right - mw;
  let top = rect.bottom + 4;
  if (left < 8) left = 8;
  if (top + menu.offsetHeight > window.innerHeight - 8) top = rect.top - menu.offsetHeight - 4;
  menu.style.left = left + 'px';
  menu.style.top = top + 'px';
  const off = (e) => { if (!menu.contains(e.target)) { menu.remove(); document.removeEventListener('click', off); } };
  setTimeout(() => document.addEventListener('click', off), 0);
  const first = menu.querySelector('.dropdown-item');
  first && first.focus();
}

async function approve(it, ctx) {
  try { await api.approvalMarkReady(it.name); toast('Yayına hazır sırasına alındı.', 'ok'); ctx.refresh(); }
  catch (e) { toast(e.message, 'err'); }
}
async function reject(it, ctx) {
  if (!(await confirmModal({ title: 'İçeriği reddet', message: `"${it.title}" reddedilecek ve silinecek.`, confirmLabel: 'Reddet', danger: true }))) return;
  try { await api.approvalReject(it.name); toast('İçerik reddedildi.', 'ok'); ctx.refresh(); }
  catch (e) { toast(e.message, 'err'); }
}
async function publish(it, ctx) {
  if (!(await confirmModal({ title: 'Şimdi yayınla', message: `"${it.title}" Instagram'da yayınlanacak.`, confirmLabel: 'Yayınla' }))) return;
  try { await api.publish(it.name); toast('Yayın başlatıldı.', 'ok'); ctx.refresh(); }
  catch (e) { toast(e.message, 'err'); }
}
async function dequeueOrReject(it, ctx) {
  if (!(await confirmModal({ title: 'Kuyruktan kaldır', message: `"${it.title}" yayın kuyruğundan çıkarılacak.`, confirmLabel: 'Kaldır', danger: true }))) return;
  try {
    if (it.queue_entry_id) await api.dequeue(it.queue_entry_id);
    toast('Kuyruktan çıkarıldı.', 'ok'); ctx.refresh();
  } catch (e) { toast(e.message, 'err'); }
}
async function del(it, ctx) {
  if (!(await confirmModal({ title: 'İçeriği sil', message: `"${it.title}" kalıcı olarak silinecek.`, confirmLabel: 'Sil', danger: true }))) return;
  try { await api.storyDelete(it.name); toast('İçerik silindi.', 'ok'); ctx.refresh(); }
  catch (e) { toast(e.message, 'err'); }
}
async function autoFill(ctx) {
  try {
    const r = await api.autoFillReady();
    toast(`${r.scheduled} içerik sıraya alındı.`, 'ok');
    ctx.refresh();
  } catch (e) { toast(e.message, 'err'); }
}
