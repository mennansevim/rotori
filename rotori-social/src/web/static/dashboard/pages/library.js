// =========================================================================
// pages/library.js — İçerik yaşam döngüsü: Taslak → Onaylandı → Yayınlandı
// =========================================================================
import { api, el, icons, typeBadge, fmtDate, fmtTime,
         emptyState, errorState, loadingState, toast, confirmModal } from '../lib.js?v=20260810-7';
import { openContentModal, regenerate } from '../modals.js?v=20260810-7';
import { openCreateModal } from './create.js?v=20260810-7';

const STAGES = {
  draft: {
    label: 'Taslak',
    eyebrow: '01 · Hazırlık',
    title: 'İncele ve onayla',
    description: 'Yeni üretilen içerikleri kontrol et, düzenle ve hazır olduğunda onayla.',
    statuses: new Set(['draft', 'pending_approval']),
    icon: icons.draft,
  },
  approved: {
    label: 'Onaylandı',
    eyebrow: '02 · Planlama',
    title: 'Otomasyona ekle',
    description: 'Onaylanan içerikleri tek tek ya da topluca uygun yayın slotlarına yerleştir.',
    statuses: new Set(['approved', 'queued', 'scheduled', 'publishing', 'failed']),
    icon: icons.check,
  },
  published: {
    label: 'Yayınlandı',
    eyebrow: '03 · Arşiv',
    title: 'Yayın geçmişi',
    description: 'Instagram’da yayınlanan içerikleri ayrı bir arşivde görüntüle.',
    statuses: new Set(['published']),
    icon: icons.send,
  },
};

export async function renderLibrary(root, ctx, params) {
  root.innerHTML = '';
  const requestedStage = params?.status;
  const state = {
    stage: Object.hasOwn(STAGES, requestedStage) ? requestedStage : 'draft',
    type: 'all',
    q: '',
    sort: 'new',
  };

  root.append(el('div', { class: 'page__head library-head' },
    el('div', {},
      el('div', { class: 'library-head__eyebrow' }, 'İçerik operasyonu'),
      el('h1', { class: 'page__title' }, 'Kütüphane'),
      el('div', { class: 'page__subtitle' },
        'İçerikleri üretimden yayına kadar tek ve anlaşılır bir akışta yönet.')),
    el('div', { class: 'page__actions' },
      el('button', {
        class: 'btn btn--primary',
        onclick: () => openCreateModal(ctx, 'gorsel'),
        html: icons.plus + '<span>Yeni İçerik</span>',
      }))));

  const stageNav = el('div', { class: 'library-stages', role: 'tablist', 'aria-label': 'İçerik aşamaları' });
  const stageIntro = el('section', { class: 'library-stage-intro' });
  const toolbar = el('div', { class: 'library-toolbar' });
  const gridWrap = el('div', { class: 'library-content' }, loadingState(320));
  root.append(stageNav, stageIntro, toolbar, gridWrap);

  let data;
  try {
    data = await api.library();
  } catch (e) {
    gridWrap.innerHTML = '';
    gridWrap.append(errorState(e.message, () => renderLibrary(root, ctx, params)));
    return;
  }

  const stageItems = (key) => data.items.filter((item) => STAGES[key].statuses.has(item.status));

  const rebuildStageNav = () => {
    stageNav.innerHTML = '';
    Object.entries(STAGES).forEach(([key, stage], index) => {
      const active = state.stage === key;
      stageNav.append(el('button', {
        class: `library-stage ${active ? 'is-active' : ''}`,
        role: 'tab',
        'aria-selected': String(active),
        onclick: () => {
          state.stage = key;
          rebuildStageNav();
          renderStageIntro();
          renderGrid();
        },
      },
      el('span', { class: 'library-stage__step' }, String(index + 1).padStart(2, '0')),
      el('span', { class: 'library-stage__icon', html: stage.icon }),
      el('span', { class: 'library-stage__copy' },
        el('strong', {}, stage.label),
        el('small', {}, stage.description.split('.')[0])),
      el('span', { class: 'library-stage__count' }, stageItems(key).length)));
    });
  };

  const renderStageIntro = () => {
    const stage = STAGES[state.stage];
    stageIntro.innerHTML = '';
    stageIntro.append(el('div', {},
      el('div', { class: 'library-stage-intro__eyebrow' }, stage.eyebrow),
      el('h2', {}, stage.title),
      el('p', {}, stage.description)));
    if (state.stage === 'approved') {
      stageIntro.append(el('button', {
        class: 'btn library-bulk-action',
        onclick: (event) => autoFillAll(ctx, event.currentTarget),
        html: icons.automation + '<span>Tümünü Otomasyona Ekle</span>',
      }));
    }
  };

  const renderToolbar = () => {
    toolbar.innerHTML = '';
    const search = el('div', { class: 'search library-search' },
      el('span', { html: icons.search }),
      el('input', {
        class: 'input',
        placeholder: 'Başlık veya açıklamada ara',
        value: state.q,
        oninput: (event) => { state.q = event.target.value; renderGrid(); },
      }));
    const type = el('select', {
      class: 'select',
      'aria-label': 'İçerik tipi',
      onchange: (event) => { state.type = event.target.value; renderGrid(); },
    },
    el('option', { value: 'all' }, 'Tüm içerik tipleri'),
    el('option', { value: 'gorsel' }, 'Görsel'),
    el('option', { value: 'haber' }, 'Haber'));
    const sort = el('select', {
      class: 'select',
      'aria-label': 'Sıralama',
      onchange: (event) => { state.sort = event.target.value; renderGrid(); },
    },
    el('option', { value: 'new' }, 'En yeni önce'),
    el('option', { value: 'old' }, 'En eski önce'));
    toolbar.append(search, el('div', { class: 'library-toolbar__filters' }, type, sort));
  };

  const filtered = () => {
    let items = stageItems(state.stage);
    if (state.type !== 'all') items = items.filter((item) => item.type === state.type);
    if (state.q.trim()) {
      const query = state.q.trim().toLocaleLowerCase('tr-TR');
      items = items.filter((item) =>
        `${item.title || ''} ${item.aciklama || ''} ${item.post_caption || ''}`
          .toLocaleLowerCase('tr-TR').includes(query));
    }
    return [...items].sort((a, b) => state.sort === 'new'
      ? String(b.created_at).localeCompare(String(a.created_at))
      : String(a.created_at).localeCompare(String(b.created_at)));
  };

  const renderGrid = () => {
    gridWrap.innerHTML = '';
    const items = filtered();
    if (!items.length) {
      const copy = emptyCopy(state.stage, Boolean(data.items.length), Boolean(state.q.trim()));
      gridWrap.append(emptyState(STAGES[state.stage].icon, copy.title, copy.message));
      return;
    }
    const grid = el('div', { class: 'library-grid' });
    items.forEach((item) => grid.append(contentCard(item, ctx)));
    gridWrap.append(grid);
  };

  rebuildStageNav();
  renderStageIntro();
  renderToolbar();
  renderGrid();
}

function emptyCopy(stage, hasItems, searching) {
  if (searching) return { title: 'Aramayla eşleşen içerik yok', message: 'Farklı bir kelime deneyin veya aramayı temizleyin.' };
  if (stage === 'draft') return {
    title: 'Onay bekleyen taslak yok',
    message: hasItems ? 'Yeni üretilen içerikler burada görünecek.' : 'Yeni İçerik ile ilk taslağınızı oluşturun.',
  };
  if (stage === 'approved') return { title: 'Onaylanmış içerik yok', message: 'Taslaklardan birini onayladığınızda burada görünecek.' };
  return { title: 'Henüz yayınlanan içerik yok', message: 'Otomasyon gönderimi tamamlayınca içerik burada arşivlenecek.' };
}

function contentCard(item, ctx) {
  const thumb = item.url
    ? el('img', { src: item.url, alt: item.title, loading: 'lazy' })
    : el('div', { class: 'library-card__noimg', html: icons.image });
  const media = el('button', {
    class: 'library-card__media',
    type: 'button',
    'aria-label': `${item.title} içeriğini aç`,
    onclick: () => openContentModal(item, ctx),
  }, thumb,
  el('span', { class: 'library-card__type', html: typeBadge(item.type) }),
  el('span', { class: `library-card__state library-card__state--${stateTone(item)}` }, stateLabel(item)));

  const body = el('div', { class: 'library-card__body' },
    el('div', { class: 'library-card__title clamp-2', title: item.title }, item.title),
    item.aciklama
      ? el('p', { class: 'library-card__description clamp-2' }, item.aciklama)
      : null,
    el('div', { class: 'library-card__meta' },
      el('span', { html: icons.clock }),
      el('span', {}, `Oluşturuldu · ${fmtDate(item.created_at)}`)));

  if (item.scheduled_at) {
    body.append(el('div', { class: `library-card__schedule ${item.status === 'failed' ? 'is-failed' : ''}` },
      el('span', { class: 'library-card__schedule-icon', html: item.status === 'failed' ? icons.x : icons.calendar }),
      el('span', {},
        el('small', {}, item.status === 'failed' ? 'Yayın denemesi başarısız' : 'Otomasyonda'),
        el('strong', {}, `${fmtDate(item.scheduled_at)} · ${fmtTime(item.scheduled_at)}`)),
      item.countdown && item.status !== 'failed'
        ? el('em', {}, item.countdown)
        : null));
  }

  if (item.status === 'published') {
    const publishedAt = item.published?.uploaded_at;
    body.append(el('div', { class: 'library-card__published' },
      el('span', { html: icons.check }),
      el('span', {}, publishedAt ? `Yayınlandı · ${fmtDate(publishedAt)}` : 'Instagram’da yayınlandı')));
  }

  body.append(cardActions(item, ctx, thumb));
  return el('article', { class: `library-card library-card--${lifecycleStage(item)}` }, media, body);
}

function cardActions(item, ctx, thumb) {
  const actions = el('div', { class: 'library-card__actions' });
  if (['draft', 'pending_approval'].includes(item.status)) {
    actions.append(
      el('button', { class: 'btn btn--primary', onclick: () => approve(item, ctx), html: icons.check + '<span>Onayla</span>' }),
      el('button', { class: 'btn', onclick: () => openContentModal(item, ctx), html: icons.edit + '<span>Düzenle</span>' }));
  } else if (item.status === 'approved' || item.status === 'failed') {
    actions.append(
      el('button', {
        class: 'btn btn--primary',
        onclick: (event) => addToAutomation(item, ctx, event.currentTarget),
        html: icons.automation + `<span>${item.status === 'failed' ? 'Yeniden Planla' : 'Otomasyona Ekle'}</span>`,
      }),
      el('button', { class: 'btn', onclick: () => openContentModal(item, ctx), html: icons.edit + '<span>Düzenle</span>' }));
  } else if (['queued', 'scheduled', 'publishing'].includes(item.status)) {
    actions.append(
      el('button', { class: 'btn', onclick: () => ctx.navigate('automation'), html: icons.automation + '<span>Akışta Gör</span>' }),
      el('button', { class: 'btn', onclick: () => openContentModal(item, ctx), html: icons.eye + '<span>İncele</span>' }));
  } else if (item.status === 'published') {
    const link = item.published?.permalink;
    actions.append(link
      ? el('a', { class: 'btn btn--primary', href: link, target: '_blank', rel: 'noopener', html: icons.link + '<span>Instagram’da Aç</span>' })
      : el('button', { class: 'btn btn--primary', onclick: () => openContentModal(item, ctx), html: icons.eye + '<span>Görüntüle</span>' }));
  }
  actions.append(el('button', {
    class: 'btn btn--icon',
    'aria-label': 'Diğer işlemler',
    onclick: (event) => openRowMenu(event.currentTarget, item, ctx, thumb),
    html: icons.dots,
  }));
  return actions;
}

function lifecycleStage(item) {
  if (item.status === 'published') return 'published';
  if (['draft', 'pending_approval'].includes(item.status)) return 'draft';
  return 'approved';
}

function stateLabel(item) {
  const labels = {
    draft: 'Taslak', pending_approval: 'Taslak', approved: 'Onaylandı',
    queued: 'Otomasyonda', scheduled: 'Otomasyonda', publishing: 'Yayınlanıyor',
    failed: 'Planlama hatası', published: 'Yayınlandı',
  };
  return labels[item.status] || item.status_tr || item.status;
}

function stateTone(item) {
  if (item.status === 'published') return 'published';
  if (item.status === 'failed') return 'failed';
  if (['queued', 'scheduled', 'publishing'].includes(item.status)) return 'scheduled';
  if (item.status === 'approved') return 'approved';
  return 'draft';
}

function openRowMenu(anchor, item, ctx, imageNode) {
  document.querySelectorAll('.dropdown-menu').forEach((menu) => menu.remove());
  const rect = anchor.getBoundingClientRect();
  const menu = el('div', { class: 'dropdown-menu', role: 'menu' });
  const menuItem = (label, icon, onclick, danger = false) => el('button', {
    class: `dropdown-item ${danger ? 'is-danger' : ''}`,
    role: 'menuitem',
    onclick: () => { menu.remove(); onclick(); },
    html: icon + `<span>${label}</span>`,
  });
  menu.append(menuItem('Önizle', icons.eye, () => openContentModal(item, ctx)));
  if (item.status !== 'published') {
    menu.append(menuItem('Görseli yeniden oluştur', icons.refresh, async () => {
      const changed = await regenerate(item, ctx, imageNode);
      if (changed) ctx.refresh();
    }));
  }
  if (item.queue_entry_id && ['queued', 'scheduled', 'publishing', 'failed'].includes(item.status)) {
    menu.append(menuItem('Otomasyondan çıkar', icons.x, () => dequeue(item, ctx), true));
  }
  if (['draft', 'pending_approval'].includes(item.status)) {
    menu.append(menuItem('Reddet', icons.x, () => reject(item, ctx), true));
  }
  menu.append(menuItem('Sil', icons.trash, () => remove(item, ctx), true));

  document.body.append(menu);
  const width = menu.offsetWidth || 200;
  const left = Math.max(8, Math.min(rect.right - width, window.innerWidth - width - 8));
  const top = rect.bottom + menu.offsetHeight > window.innerHeight - 8
    ? rect.top - menu.offsetHeight - 4
    : rect.bottom + 4;
  menu.style.left = `${left}px`;
  menu.style.top = `${top}px`;
  const close = (event) => {
    if (!menu.contains(event.target)) {
      menu.remove();
      document.removeEventListener('click', close);
    }
  };
  setTimeout(() => document.addEventListener('click', close), 0);
  menu.querySelector('.dropdown-item')?.focus();
}

async function approve(item, ctx) {
  try {
    await api.approvalMarkReady(item.name);
    toast('İçerik onaylandı.', 'ok');
    ctx.refresh();
  } catch (error) { toast(error.message, 'err'); }
}

async function addToAutomation(item, ctx, button) {
  const oldHtml = button.innerHTML;
  button.disabled = true;
  button.innerHTML = icons.clock + '<span>Planlanıyor…</span>';
  try {
    const result = await api.autoFillReadyItem(item.name);
    toast(result.scheduled ? 'İçerik otomasyona eklendi.' : result.message, result.scheduled ? 'ok' : '');
    ctx.refresh();
  } catch (error) {
    toast(error.message, 'err');
    button.disabled = false;
    button.innerHTML = oldHtml;
  }
}

async function autoFillAll(ctx, button) {
  const oldHtml = button.innerHTML;
  button.disabled = true;
  button.innerHTML = icons.clock + '<span>Planlanıyor…</span>';
  try {
    const result = await api.autoFillReady();
    toast(result.scheduled ? `${result.scheduled} içerik otomasyona eklendi.` : result.message, result.scheduled ? 'ok' : '');
    ctx.refresh();
  } catch (error) {
    toast(error.message, 'err');
    button.disabled = false;
    button.innerHTML = oldHtml;
  }
}

async function dequeue(item, ctx) {
  const confirmed = await confirmModal({
    title: 'Otomasyondan çıkar',
    message: `“${item.title}” yayın planından çıkarılacak.`,
    confirmLabel: 'Çıkar',
    danger: true,
  });
  if (!confirmed) return;
  try {
    await api.dequeue(item.queue_entry_id);
    toast('İçerik otomasyondan çıkarıldı.', 'ok');
    ctx.refresh();
  } catch (error) { toast(error.message, 'err'); }
}

async function reject(item, ctx) {
  const confirmed = await confirmModal({
    title: 'Taslağı reddet',
    message: `“${item.title}” reddedilecek ve silinecek.`,
    confirmLabel: 'Reddet',
    danger: true,
  });
  if (!confirmed) return;
  try {
    await api.approvalReject(item.name);
    toast('Taslak reddedildi.', 'ok');
    ctx.refresh();
  } catch (error) { toast(error.message, 'err'); }
}

async function remove(item, ctx) {
  const confirmed = await confirmModal({
    title: 'İçeriği sil',
    message: `“${item.title}” kalıcı olarak silinecek.`,
    confirmLabel: 'Sil',
    danger: true,
  });
  if (!confirmed) return;
  try {
    await api.storyDelete(item.name);
    toast('İçerik silindi.', 'ok');
    ctx.refresh();
  } catch (error) { toast(error.message, 'err'); }
}
