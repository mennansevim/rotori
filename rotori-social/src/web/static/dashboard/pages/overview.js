// =========================================================================
// pages/overview.js — Backlog Board
// =========================================================================
import { api, el, icons, typeBadge, statusBadge, countdownText, fmtDate, fmtTime,
         errorState, loadingState, toast, confirmModal } from '../lib.js?v=20260804-7';
import { openContentModal } from '../modals.js';

const READY_STATUSES = new Set(['approved', 'queued', 'scheduled', 'publishing', 'failed']);
const DROP_LABELS = {
  draft: 'Bırak → Taslağa taşı',
  ready: 'Bırak → Yayına hazırla',
  published: 'Bırak → Instagram’da yayınla',
};

export async function renderOverview(root, ctx) {
  if (root._countdownTimer) clearInterval(root._countdownTimer);
  root.innerHTML = '';
  const head = el('div', { class: 'page__head board-head' },
    el('div', {},
      el('div', { class: 'eyebrow' }, 'Workspace / Backlog'),
      el('h1', { class: 'page__title' }, 'Board'),
      el('div', { class: 'page__subtitle', id: 'ov-date' }, 'İçerik akışını tek board üzerinde yönet.')));
  root.append(head);

  const body = el('div', { class: 'stack' });
  body.append(loadingState(260));
  root.append(body);

  let overview;
  let library;
  try {
    [overview, library] = await Promise.all([api.overview(), api.library()]);
  } catch (e) {
    body.innerHTML = '';
    body.append(errorState(e.message, () => renderOverview(root, ctx)));
    return;
  }

  document.getElementById('ov-date').textContent = `${overview.date_label || ''} · Europe/Istanbul`;
  body.innerHTML = '';

  const boardToolbar = el('div', { class: 'board-toolbar' },
    el('div', { class: 'board-toolbar__label' }, el('span', { html: icons.grip }), 'Drag cards to change status'),
    el('div', { class: 'board-toolbar__actions' },
      el('label', { class: 'board-search' }, el('span', { html: icons.search }),
        el('input', { id: 'board-search', type: 'search', placeholder: 'Search posts…', 'aria-label': 'Board içinde ara' })),
      el('button', { class: 'btn btn--ghost btn--sm', title: 'Yenile', onclick: () => ctx.refresh(), html: icons.refresh + '<span>Refresh</span>' })));
  body.append(boardToolbar);

  const board = el('div', { class: 'kanban-grid', id: 'kanban-grid' });
  const search = boardToolbar.querySelector('#board-search');
  const renderBoard = () => {
    const query = (search.value || '').trim().toLowerCase();
    board.innerHTML = '';
    const all = library.items || [];
    const columns = [
      { key: 'draft', title: 'Draft', tr: 'Taslak', tone: 'slate', items: all.filter((it) => ['draft', 'pending_approval'].includes(it.status)) },
      { key: 'ready', title: 'Ready for Publishing', tr: 'Yayına Hazır', tone: 'indigo', items: all.filter((it) => READY_STATUSES.has(it.status)) },
      { key: 'published', title: 'Published', tr: 'Yayınlandı', tone: 'green', items: all.filter((it) => it.status === 'published') },
    ];
    for (const column of columns) {
      const items = sortByPublishTime(column.items.filter((it) => !query || `${it.title} ${it.aciklama || ''} ${it.source || ''}`.toLowerCase().includes(query)));
      board.append(kanbanColumn(column, items, library.now, ctx, library.items));
    }
    updateCountdowns(board, library.now);
  };
  search.addEventListener('input', renderBoard);
  renderBoard();
  body.append(board);
  body.append(compactSummary(overview, library));
  root._countdownTimer = setInterval(() => {
    if (!root.contains(board)) {
      clearInterval(root._countdownTimer);
      root._countdownTimer = null;
      return;
    }
    updateCountdowns(board, library.now);
  }, 60_000);
}

function sortByPublishTime(items) {
  return [...items].sort((a, b) => {
    const aPublish = a.scheduled_at ? new Date(a.scheduled_at).getTime() : Number.POSITIVE_INFINITY;
    const bPublish = b.scheduled_at ? new Date(b.scheduled_at).getTime() : Number.POSITIVE_INFINITY;
    if (aPublish !== bPublish) return aPublish - bPublish;
    return new Date(b.created_at || 0).getTime() - new Date(a.created_at || 0).getTime();
  });
}

function updateCountdowns(scope, serverNow) {
  const serverTime = new Date(serverNow).getTime();
  const clockOffset = Number.isFinite(serverTime) ? serverTime - Date.now() : 0;
  const now = Date.now() + clockOffset;
  scope.querySelectorAll('[data-countdown-at]').forEach((node) => {
    node.textContent = countdownText(node.dataset.countdownAt, now);
    node.closest('.kanban-card__schedule')?.classList.toggle('is-overdue', new Date(node.dataset.countdownAt).getTime() < now);
  });
}

function compactSummary(overview, library) {
  const items = library.items || [];
  const draft = items.filter((it) => statusColumn(it.status) === 'draft').length;
  const ready = items.filter((it) => statusColumn(it.status) === 'ready').length;
  const published = items.filter((it) => statusColumn(it.status) === 'published').length;
  const next = overview.next_publish;
  return el('footer', { class: 'board-summary' },
    el('span', {}, el('b', {}, draft), ' draft'),
    el('span', {}, el('b', {}, ready), ' ready'),
    el('span', {}, el('b', {}, published), ' published'),
    el('span', { class: 'board-summary__next' }, next
      ? `Next: ${fmtDate(next.scheduled_at)} · ${fmtTime(next.scheduled_at)}`
      : 'Publishing queue empty'));
}

function kanbanColumn(column, items, serverNow, ctx, allItems) {
  const col = el('section', {
    class: `kanban-col kanban-col--${column.tone}`,
    dataset: { column: column.key, dropLabel: DROP_LABELS[column.key] },
  },
    el('div', { class: 'kanban-col__head' },
      el('div', {}, el('h2', {}, column.title), el('span', { class: 'kanban-col__tr' }, column.tr)),
      el('span', { class: 'kanban-count' }, items.length),
      column.key === 'draft'
        ? el('button', { class: 'kanban-add', title: 'Yeni post oluştur', onclick: () => document.getElementById('top-create')?.click(), html: icons.plus })
        : null),
    el('div', { class: 'kanban-col__body' }));
  const body = col.querySelector('.kanban-col__body');
  if (!items.length) body.append(el('div', { class: 'kanban-empty' }, el('span', { html: icons.inbox }), 'No posts here yet'));
  for (const it of items) body.append(kanbanCard(it, serverNow, ctx));
  col.addEventListener('dragover', (event) => {
    event.preventDefault();
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
    col.classList.add('is-drop-target');
  });
  col.addEventListener('dragleave', (event) => { if (!col.contains(event.relatedTarget)) col.classList.remove('is-drop-target'); });
  col.addEventListener('drop', async (event) => {
    event.preventDefault(); col.classList.remove('is-drop-target');
    const name = event.dataTransfer?.getData('text/plain');
    const item = allItems.find((candidate) => candidate.name === name);
    if (!item || column.key === statusColumn(item.status)) return;
    await moveItem(item, column.key, ctx);
  });
  return col;
}

async function moveItem(item, target, ctx) {
  try {
    if (target === 'ready') {
      await api.approvalMarkReady(item.name);
      toast('İçerik yayına hazır durumuna taşındı.', 'ok');
      ctx.refresh();
      return;
    }

    if (target === 'draft') {
      if (item.status === 'publishing') {
        toast('Yayın işlemi sürerken kart taslağa alınamaz.', 'err');
        return;
      }
      if (item.queue_entry_id) await api.dequeue(item.queue_entry_id);
      await api.storyUnmarkReady(item.name);
      toast('İçerik taslağa geri alındı.', 'ok');
      ctx.refresh();
      return;
    }

    if (target === 'published') {
      const ok = await confirmModal({
        title: 'Instagram’da yayınla',
        message: `“${item.title}” Instagram hesabında hemen yayınlanacak.`,
        confirmLabel: 'Şimdi Yayınla',
      });
      if (!ok) return;

      let prepared = false;
      if (statusColumn(item.status) === 'draft') {
        await api.approvalMarkReady(item.name);
        prepared = true;
      }
      try {
        await api.publish(item.name);
        toast('Instagram yayın işlemi başlatıldı. Onay gelince Published sütununa taşınacak.', 'ok');
      } catch (error) {
        if (prepared) {
          toast(`Kart yayına hazırlandı ancak Instagram gönderimi başlatılamadı: ${error.message}`, 'err');
          ctx.refresh();
          return;
        }
        throw error;
      }
      ctx.refresh();
    }
  } catch (error) {
    toast(error.message, 'err');
  }
}

function statusColumn(status) {
  if (status === 'published') return 'published';
  if (READY_STATUSES.has(status)) return 'ready';
  return 'draft';
}

function kanbanCard(it, serverNow, ctx) {
  const canDrag = it.status !== 'published';
  let suppressClick = false;
  const card = el('article', {
    class: `kanban-card kanban-card--${it.type === 'haber' ? 'haber' : 'gorsel'} ${canDrag ? 'is-draggable' : ''}`,
    draggable: canDrag ? 'true' : 'false',
    dataset: { cardName: it.name, status: it.status, publishAt: it.scheduled_at || '' },
    'aria-grabbed': 'false',
  });
  const thumb = it.url
    ? el('img', { class: 'kanban-card__thumb', src: it.url, alt: it.title, loading: 'lazy' })
    : el('div', { class: 'kanban-card__thumb kanban-card__thumb--empty', html: icons.image });
  const actions = el('div', { class: 'kanban-card__actions' },
    el('button', { class: 'kanban-action', title: 'Düzenle', onclick: (event) => { event.stopPropagation(); openContentModal(it, ctx); }, html: icons.edit }),
    el('button', { class: 'kanban-action', title: 'Sil', onclick: async (event) => { event.stopPropagation(); await deleteItem(it, ctx); }, html: icons.trash }));
  const schedule = it.scheduled_at
    ? el('span', { class: `kanban-card__schedule${it.seconds_until < 0 ? ' is-overdue' : ''}`, title: `${fmtDate(it.scheduled_at)} · ${fmtTime(it.scheduled_at)}` },
      el('span', { class: 'kanban-card__clock', html: icons.clock }),
      el('span', { class: 'kanban-card__countdown', dataset: { countdownAt: it.scheduled_at } }, it.countdown || countdownText(it.scheduled_at, serverNow)))
    : el('span', { class: 'kanban-card__schedule is-unscheduled' }, 'Planlanmadı');
  card.append(
    el('div', { class: 'kanban-card__media' }, thumb, el('span', { class: 'kanban-card__type', html: typeBadge(it.type) }), actions),
    el('div', { class: 'kanban-card__content' },
      el('div', { class: 'kanban-card__title' }, it.title),
      el('div', { class: 'kanban-card__meta' },
        el('span', { html: statusBadge(it.status) }),
        el('span', {}, it.scheduled_at ? `${fmtDate(it.scheduled_at)} · ${fmtTime(it.scheduled_at)}` : fmtDate(it.created_at)))),
    el('div', { class: 'kanban-card__foot' },
      el('span', { class: 'kanban-author' }, 'JR'),
      schedule,
      el('span', { class: 'kanban-grip', title: canDrag ? 'Sürükle' : 'Yayınlandı', html: icons.grip })));
  card.addEventListener('click', () => {
    if (suppressClick) { suppressClick = false; return; }
    openContentModal(it, ctx);
  });
  if (canDrag) {
    card.addEventListener('dragstart', (event) => {
      card.classList.add('is-dragging');
      card.setAttribute('aria-grabbed', 'true');
      document.body.classList.add('is-board-dragging');
      event.dataTransfer?.setData('text/plain', it.name);
    });
    card.addEventListener('dragend', () => {
      card.classList.remove('is-dragging');
      card.setAttribute('aria-grabbed', 'false');
      document.body.classList.remove('is-board-dragging');
      document.querySelectorAll('.kanban-col.is-drop-target').forEach((node) => node.classList.remove('is-drop-target'));
    });
    installPointerDrag(card, it, ctx, () => {
      suppressClick = true;
      setTimeout(() => { suppressClick = false; }, 0);
    });
  }
  return card;
}

function installPointerDrag(card, item, ctx, suppressNextClick) {
  const handle = card.querySelector('.kanban-grip');
  if (!handle) return;

  handle.addEventListener('pointerdown', (start) => {
    if (start.button != null && start.button !== 0) return;
    start.preventDefault();
    start.stopPropagation();

    const origin = { x: start.clientX, y: start.clientY };
    let active = false;
    let ghost = null;
    let target = null;
    handle.setPointerCapture?.(start.pointerId);

    const clearTarget = () => {
      target?.classList.remove('is-drop-target');
      target = null;
    };
    const cleanup = () => {
      handle.removeEventListener('pointermove', move);
      handle.removeEventListener('pointerup', finish);
      handle.removeEventListener('pointercancel', cancel);
      handle.releasePointerCapture?.(start.pointerId);
      clearTarget();
      ghost?.remove();
      card.classList.remove('is-dragging');
      document.body.classList.remove('is-board-dragging');
    };
    const move = (event) => {
      if (event.pointerId !== start.pointerId) return;
      const distance = Math.hypot(event.clientX - origin.x, event.clientY - origin.y);
      if (!active && distance < 6) return;
      if (!active) {
        active = true;
        const rect = card.getBoundingClientRect();
        ghost = card.cloneNode(true);
        ghost.className = 'kanban-card kanban-drag-ghost';
        ghost.setAttribute('aria-hidden', 'true');
        ghost.style.width = `${rect.width}px`;
        document.body.append(ghost);
        card.classList.add('is-dragging');
        document.body.classList.add('is-board-dragging');
      }
      ghost.style.left = `${event.clientX + 12}px`;
      ghost.style.top = `${event.clientY + 12}px`;
      const next = document.elementFromPoint(event.clientX, event.clientY)?.closest('.kanban-col');
      if (next !== target) {
        clearTarget();
        target = next;
        target?.classList.add('is-drop-target');
      }
    };
    const finish = (event) => {
      if (event.pointerId !== start.pointerId) return;
      const destination = target?.dataset.column;
      const changed = active && destination && destination !== statusColumn(item.status);
      cleanup();
      if (active) suppressNextClick();
      if (changed) void moveItem(item, destination, ctx);
    };
    const cancel = (event) => {
      if (event.pointerId !== start.pointerId) return;
      cleanup();
    };

    handle.addEventListener('pointermove', move);
    handle.addEventListener('pointerup', finish);
    handle.addEventListener('pointercancel', cancel);
  });
}

async function deleteItem(it, ctx) {
  if (!(await confirmModal({ title: 'İçeriği sil', message: `"${it.title}" kalıcı olarak silinecek.`, confirmLabel: 'Sil', danger: true }))) return;
  try { await api.storyDelete(it.name); toast('İçerik silindi.', 'ok'); ctx.refresh(); }
  catch (e) { toast(e.message, 'err'); }
}
