// =========================================================================
// pages/automation.js — Otomasyon (yayın slotları)
// =========================================================================
import { api, el, icons, typeBadge, countdownText, fmtDate, fmtTime,
         errorState, loadingState, toast, openModal } from '../lib.js?v=20260808-1';

const DAYS = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];  // launchd: 1..6,0
const DAY_TO_LAUNCHD = [1, 2, 3, 4, 5, 6, 0];  // index → launchd weekday
const FLOW_LIMIT = 5;
const FLOW_HORIZON_DAYS = 14;
const READY_LIBRARY_STATUSES = new Set(['approved', 'queued', 'scheduled', 'publishing', 'failed']);
const REPLACE_ELIGIBLE_STATUSES = new Set(['approved', 'queued', 'scheduled']);
const ADD_ELIGIBLE_STATUSES = new Set(['approved']);

const FLOW_META = {
  haber: {
    title: 'Mavi Haber Akışı',
    subtitle: 'Haber otomasyonu slotları (canlı takip)',
    action: 'Onaylı haber görseliyle değiştir',
  },
  gorsel: {
    title: 'Kırmızı Görsel Üretim Akışı',
    subtitle: 'Konu/görsel üretim slotları (canlı takip)',
    action: 'Onaylı görsel üretim kartıyla değiştir',
  },
};

const FLOW_KIND_TO_CONFIG = {
  haber: 'news',
  gorsel: 'topic',
};

export async function renderAutomation(root, ctx) {
  clearAutomationTimers(root);
  root.innerHTML = '';
  const head = el('div', { class: 'page__head' },
    el('div', {},
      el('h1', { class: 'page__title' }, 'Otomasyon'),
      el('div', { class: 'page__subtitle' }, 'Onaylanan içerikler planlanan gün ve saatlerde otomatik yayınlanır.')),
    el('div', { class: 'page__actions' },
      el('button', { class: 'btn btn--primary', id: 'auto-save', onclick: () => save(), html: icons.check + '<span>Ayarları Kaydet</span>' })));
  root.append(head);

  const tabbar = el('div', { class: 'automation-tabs' });
  const tabButtons = {
    flow: el('button', {
      class: 'automation-tab is-active',
      type: 'button',
      onclick: () => switchTab('flow'),
      html: `${icons.automation}<span>Flow Takibi</span>`,
    }),
    settings: el('button', {
      class: 'automation-tab',
      type: 'button',
      onclick: () => switchTab('settings'),
      html: `${icons.settings}<span>Slot Ayarları</span>`,
    }),
  };
  tabbar.append(tabButtons.flow, tabButtons.settings);
  root.append(tabbar);

  const body = el('div', { class: 'stack' });
  body.append(loadingState(220));
  root.append(body);

  let data;
  let publishes;
  let library;
  try {
    [data, publishes, library] = await Promise.all([
      api.automationState(),
      api.publishes(),
      api.library(),
    ]);
  }
  catch (e) { body.innerHTML = ''; body.append(errorState(e.message, () => renderAutomation(root, ctx))); return; }

  // yerel düzenlenebilir kopya
  const cfg = JSON.parse(JSON.stringify(data.config));
  const state = {
    nowIso: publishes?.now || data?.timeline?.now || null,
    publishes,
    library: Array.isArray(library?.items) ? library.items : [],
    config: cfg,
    pendingDispatch: new Set(),
    dispatchCooldown: new Map(),
  };

  root._automationState = state;

  const settingsPanel = el('section', { class: 'automation-panel', id: 'automation-settings-panel' });
  const flowPanel = el('section', { class: 'automation-panel', id: 'automation-flow-panel' });
  body.innerHTML = '';
  body.append(flowPanel, settingsPanel);

  renderSettingsPanel(settingsPanel, cfg);
  renderFlowPanel(flowPanel, state, root, ctx, { animateShift: false });

  switchTab('flow');
  startAutomationTimers(root, ctx, flowPanel, async (opts = {}) => {
    await refreshFlowData(flowPanel, root, ctx, opts);
  });

  async function save() {
    const btn = document.getElementById('auto-save');
    btn.disabled = true;
    try {
      const res = await api.automationConfigSet({ news: cfg.news, topic: cfg.topic });
      const scheduled = res.queue_sync?.scheduled || 0;
      const rescheduled = res.queue_sync?.rescheduled || 0;
      toast(scheduled || rescheduled
        ? `Ayarlar kaydedildi · ${scheduled + rescheduled} kartın yayın sırası güncellendi.`
        : 'Otomasyon ayarları kaydedildi.', 'ok');
      if (res.launchd && res.launchd.length) console.log('launchd:', res.launchd);
      await renderAutomation(root, ctx);
    } catch (e) { toast('Kayıt başarısız: ' + e.message, 'err'); btn.disabled = false; }
  }

  function switchTab(tab) {
    const showFlow = tab === 'flow';
    flowPanel.hidden = !showFlow;
    settingsPanel.hidden = showFlow;
    tabButtons.flow.classList.toggle('is-active', showFlow);
    tabButtons.settings.classList.toggle('is-active', !showFlow);
    const saveBtn = document.getElementById('auto-save');
    if (saveBtn) saveBtn.style.display = showFlow ? 'none' : 'inline-flex';
  }
}

function renderSettingsPanel(panel, cfg) {
  panel.innerHTML = '';
  const slots = el('div', { class: 'grid-2' },
    slotCard('haber', 'Haber Slotu', 'Haber tipindeki içerikler otomatik yayınlanır.', cfg.news),
    slotCard('gorsel', 'Görsel Slotu', 'Görsel tipindeki içerikler otomatik yayınlanır.', cfg.topic));
  panel.append(slots);
  panel.append(el('div', { class: 'foot-note', html:
    'Yayınlar yalnızca onaylandıktan sonra otomasyon kapsamına alınır.<br>Saatler <b>Europe/Istanbul (GMT+3)</b> zaman dilimine göre ayarlanmıştır.' }));

  function slotCard(kind, title, sub, conf) {
    const enabledToggle = el('input', { type: 'checkbox', checked: conf.enabled ? '' : null,
      onchange: (e) => { conf.enabled = e.target.checked; } });
    const timeInput = el('input', { class: 'input', type: 'time', style: 'max-width:130px',
      value: `${String(conf.hour).padStart(2, '0')}:${String(conf.minute).padStart(2, '0')}`,
      onchange: (e) => { const [h, m] = e.target.value.split(':'); conf.hour = +h; conf.minute = +m; } });
    const publishToggle = el('input', { type: 'checkbox', checked: conf.auto_publish ? '' : null,
      onchange: (e) => { conf.auto_publish = e.target.checked; } });

    const dayBtns = el('div', { class: 'daypicker' });
    DAYS.forEach((label, idx) => {
      const lw = DAY_TO_LAUNCHD[idx];
      const on = (conf.days || []).includes(lw);
      const b = el('button', { class: `${on ? 'is-on ' + kind : ''}`,
        'aria-pressed': on ? 'true' : 'false',
        onclick: () => {
          const has = conf.days.includes(lw);
          conf.days = has ? conf.days.filter((d) => d !== lw) : [...conf.days, lw];
          b.classList.toggle('is-on'); b.classList.toggle(kind);
          b.setAttribute('aria-pressed', String(!has));
        } }, label);
      dayBtns.append(b);
    });

    return el('div', { class: 'card slot-card' }, el('div', { class: 'card__body' },
      el('div', { class: 'slot-card__head', style: 'justify-content:space-between;margin-bottom:16px' },
        el('div', { class: 'hstack', style: 'align-items:flex-start' },
          el('div', { class: `slot-card__icon ${kind}`, html: kind === 'haber' ? icons.news : icons.image }),
          el('div', {}, el('div', { class: 'slot-card__title' }, title), el('div', { class: 'slot-card__sub' }, sub))),
        el('label', { class: 'switch' }, enabledToggle, el('span', { class: 'switch__track' }))),
      el('div', { class: 'slot-row' }, el('span', { class: 'slot-row__label' }, 'Günler'), dayBtns),
      el('div', { class: 'slot-row' }, el('span', { class: 'slot-row__label' }, 'Saat'), timeInput),
      el('div', { class: 'slot-row' }, el('span', { class: 'slot-row__label' }, 'Yayın'),
        el('label', { class: 'option', style: 'border:0;padding:0;background:none' }, publishToggle, 'Slot zamanı gelince otomatik yayınla')),
      el('p', { class: 'muted', style: 'font-size:11.5px;margin:14px 0 0' },
        `Onaylanan ${kind === 'haber' ? 'haber' : 'görsel'} içerikleri belirtilen gün ve saatte otomatik yayınlanır.`)));
  }
}

function renderFlowPanel(panel, state, root, ctx, options = {}) {
  const nowIso = state.nowIso;
  const upcoming = Array.isArray(state.publishes?.upcoming) ? state.publishes.upcoming : [];
  const approvedPool = state.library.filter((it) => READY_LIBRARY_STATUSES.has(it.status));
  const activeFlowTypes = activeFlowLaneTypes(state.config);

  panel.innerHTML = '';
  panel.append(el('div', { class: 'card flow-hero' }, el('div', { class: 'card__body flow-hero__body' },
    el('div', {},
      el('div', { class: 'flow-hero__eyebrow' }, 'Yeni Tasarım Sekmesi'),
      el('h3', { class: 'flow-hero__title' }, 'Canlı Yayın Akışı'),
      el('p', { class: 'muted', style: 'margin:6px 0 0' },
        'Sağdaki son kart canlı takip edilir. Saati gelince gönderim tetiklenir; başarılıysa sıra kayarak güncellenir.')),
    el('div', { class: 'flow-hero__meta' },
      el('span', { class: 'badge badge--muted' }, `Onaylı havuz: ${approvedPool.length}`),
      el('span', { class: 'badge badge--muted' }, `Aktif akış: ${activeFlowTypes.length}`),
      el('span', { class: 'badge badge--muted' }, `Saat: ${fmtTime(nowIso) || '—'}`))
  )));

  const flowStack = el('div', { class: 'flow-stack' });
  const anchors = {};

  if (!activeFlowTypes.length) {
    flowStack.append(el('div', { class: 'card' }, el('div', { class: 'card__body' },
      el('p', { class: 'muted', style: 'margin:0' },
        'Otomasyon akışları kapalı. Slot Ayarları sekmesinden haber veya görsel akışını açabilirsiniz.'))));
    panel.append(flowStack);
    panel.append(el('div', { class: 'foot-note', html:
      'Hata durumlarını soldaki <b>Logs</b> sekmesinden takip edebilirsiniz.<br>Flow kartına tıklayınca onaylı görsellerden seçip slotu replace edebilirsiniz.' }));
    state.anchors = anchors;
    root._flowClockOffsetMs = computeServerOffset(nowIso);
    return;
  }

  activeFlowTypes.forEach((type) => {
    const flowData = buildFlowData(upcoming, type, nowIso);
    anchors[type] = flowData.anchor;
    flowStack.append(flowRow(type, flowData, approvedPool, nowIso, root, ctx, options));
  });
  panel.append(flowStack);
  panel.append(el('div', { class: 'foot-note', html:
    'Hata durumlarını soldaki <b>Logs</b> sekmesinden takip edebilirsiniz.<br>Flow kartına tıklayınca onaylı görsellerden seçip slotu replace edebilirsiniz.' }));

  state.anchors = anchors;
  root._flowClockOffsetMs = computeServerOffset(nowIso);
}

function buildFlowData(upcoming, type, nowIso) {
  const typed = [...upcoming]
    .filter((it) => (it.type || 'gorsel') === type)
    .sort((a, b) => new Date(a.scheduled_at || 0).getTime() - new Date(b.scheduled_at || 0).getTime());

  const nowMs = parseNowMs(nowIso);
  const horizonEndMs = Number.isFinite(nowMs)
    ? nowMs + (FLOW_HORIZON_DAYS * 24 * 60 * 60 * 1000)
    : null;
  const nearStartMs = Number.isFinite(nowMs)
    ? nowMs - (6 * 60 * 60 * 1000)
    : null;

  const typedNear = typed.filter((it) => {
    if (it.publish_outcome === 'publishing' || it.publish_outcome === 'failed' || it.publish_outcome === 'manual') {
      return true;
    }
    if (!Number.isFinite(horizonEndMs) || !Number.isFinite(nearStartMs)) return true;
    const ms = new Date(it.scheduled_at || '').getTime();
    if (!Number.isFinite(ms)) return false;
    return ms >= nearStartMs && ms <= horizonEndMs;
  });

  const nearest = typedNear.slice(0, FLOW_LIMIT);
  const ordered = [...nearest].reverse(); // solda uzak tarih, sağda en yakın

  if (!ordered.length) {
    return {
      total: typed.length,
      totalNear: typedNear.length,
      hiddenFuture: Math.max(0, typed.length - typedNear.length),
      slots: [{
        _placeholder: typed.length ? 'quiet' : 'empty',
        _type: type,
      }],
      anchor: null,
      compact: true,
      empty: true,
    };
  }

  const visibleFilled = ordered.slice(0, 4);
  const slots = [...visibleFilled];

  return {
    total: typed.length,
    totalNear: typedNear.length,
    hiddenFuture: Math.max(0, typed.length - typedNear.length),
    slots,
    anchor: visibleFilled.length ? visibleFilled[visibleFilled.length - 1] : null,
    compact: visibleFilled.length < FLOW_LIMIT,
    empty: visibleFilled.length === 0,
  };
}

function flowRow(type, flowData, approvedPool, nowIso, root, ctx, options) {
  const meta = FLOW_META[type];
  const row = el('section', { class: 'card' });

  // Header
  row.append(el('div', { class: 'card__head' },
    el('div', {},
      el('h3', {}, meta.title),
      el('div', { class: 'muted', style: 'font-size:12px' }, meta.subtitle)),
    el('div', { class: 'hstack', style: 'gap:8px' },
      el('span', { html: typeBadge(type) }),
      el('span', { class: 'badge badge--muted' }, `${flowData.total} planlı`))));

  const body = el('div', { class: 'card__body' });
  const anchor = flowData.anchor;

  if (flowData.empty) {
    body.append(el('div', { class: 'empty-state', style: 'padding:24px' },
      el('p', { class: 'muted', style: 'margin:0 0 12px' }, 'Henüz planlı gönderi yok.'),
      el('button', { class: 'btn btn--primary', onclick: () => openAddToSlotPicker({ type, approvedPool, root, ctx }) },
        icons.plus + ' Onaylı İçerik Ekle')));
  } else {
    // Clean list of upcoming slots
    const list = el('div', { class: 'flow-list' });
    flowData.slots.forEach((slot) => {
      list.append(flowListItem(type, slot, anchor, approvedPool, nowIso, root, ctx));
    });
    body.append(list);

    // Add button at the bottom
    body.append(el('div', { style: 'margin-top:12px' },
      el('button', { class: 'btn btn--sm btn--primary', onclick: () => openAddToSlotPicker({ type, approvedPool, root, ctx }) },
        icons.plus + ' Onaylı İçerik Ekle')));

    // Info footer
    if (flowData.hiddenFuture > 0) {
      body.append(el('div', { class: 'muted', style: 'font-size:11px;margin-top:8px' },
        `+${flowData.hiddenFuture} içerik ileri tarihlerde planlandı`));
    }
  }

  row.append(body);
  return row;
}

function flowListItem(type, slot, anchor, approvedPool, nowIso, root, ctx) {
  const isAnchor = anchor && slot.entry_id === anchor.entry_id;
  const title = slot.title || 'Planlı gönderi';
  const pendingDispatch = Boolean(root._automationState?.pendingDispatch?.has(slot.entry_id));
  const seconds = parseDeltaSeconds(slot.scheduled_at, nowIso);
  const dispatching = shouldShowDispatching({ seconds, outcome: slot.publish_outcome, pending: pendingDispatch });
  const etaText = compactRemaining(slot.scheduled_at, nowIso, { outcome: slot.publish_outcome, pendingDispatch });
  const statusText = flowStatusText(slot, dispatching);

  const itemEl = el('div', {
    class: `flow-item ${isAnchor ? 'is-anchor' : ''}`,
    dataset: {
      entryId: slot.entry_id || '',
      scheduledAt: slot.scheduled_at || '',
      flowType: type,
    },
    onclick: () => openReplacePicker({ slot, type, approvedPool, root, ctx }),
  },
    el('div', { class: 'flow-item__time' },
      el('strong', {}, fmtDate(slot.scheduled_at)),
      el('span', {}, fmtTime(slot.scheduled_at))),
    el('div', { class: 'flow-item__thumb' },
      slot.url
        ? el('img', { src: slot.url, alt: title, loading: 'lazy' })
        : el('div', { class: 'flow-item__thumb-empty', html: icons.image })),
    el('div', { class: 'flow-item__body' },
      el('div', { class: 'flow-item__title' }, title),
      el('div', { class: 'flow-item__meta' },
        el('span', { class: `badge badge--${statusToneFromOutcome(slot.publish_outcome)}`, style: 'font-size:10px' }, statusText),
        el('span', {
          class: `flow-item__eta${dispatching ? ' is-dispatching' : ''}`,
          dataset: {
            scheduledAt: slot.scheduled_at || '',
            outcome: slot.publish_outcome || '',
            entryId: slot.entry_id || '',
          },
        }, etaText))),
    el('span', { class: 'flow-item__action' }, isAnchor ? 'Canlı' : 'Değiştir'));

  if (isAnchor) {
    itemEl.classList.add('is-live-anchor');
  }
  if (dispatching || pendingDispatch) {
    itemEl.classList.add('is-sending');
  }
  return itemEl;
}

async function refreshFlowData(flowPanel, root, ctx, options = {}) {
  const state = root._automationState;
  if (!state) return;
  try {
    const [publishes, library, autoState] = await Promise.all([
      api.publishes(),
      api.library(),
      options.forceAll ? api.automationState() : Promise.resolve(null),
    ]);
    state.publishes = publishes;
    state.nowIso = publishes?.now || state.nowIso;
    state.library = Array.isArray(library?.items) ? library.items : state.library;
    if (autoState?.config) state.config = JSON.parse(JSON.stringify(autoState.config));
    if (options.forceAll && autoState) {
      // slot ayar paneli kaydetmeden sonra yeniden güncel kalsın
      const settingsPanel = document.getElementById('automation-settings-panel');
      if (settingsPanel) {
        const cfg = JSON.parse(JSON.stringify(autoState.config));
        renderSettingsPanel(settingsPanel, cfg);
      }
    }
    renderFlowPanel(flowPanel, state, root, ctx, { animateShift: Boolean(options.animateShift) });
  } catch (e) {
    const stack = flowPanel.querySelector('.flow-stack');
    if (stack) {
      stack.innerHTML = '';
      stack.append(errorState(e.message, () => refreshFlowData(flowPanel, root, ctx, options)));
    }
  }
}

function startAutomationTimers(root, ctx, flowPanel, refreshFlow) {
  root._flowTickTimer = setInterval(() => {
    tickFlowCountdowns(root);
    maybeDispatchDueAnchors(root, flowPanel, refreshFlow);
  }, 1000);

  root._flowPollTimer = setInterval(() => {
    if (!flowPanel.hidden) refreshFlow({ animateShift: false });
  }, 30000);
}

function clearAutomationTimers(root) {
  if (root._flowTickTimer) clearInterval(root._flowTickTimer);
  if (root._flowPollTimer) clearInterval(root._flowPollTimer);
  root._flowTickTimer = null;
  root._flowPollTimer = null;
}

function tickFlowCountdowns(root) {
  const offset = Number(root._flowClockOffsetMs || 0);
  const now = Date.now() + offset;
  const state = root._automationState;
  root.querySelectorAll('.flow-item__eta[data-scheduled-at]').forEach((node) => {
    const outcome = node.dataset.outcome || '';
    const entryId = node.dataset.entryId || '';
    const pendingDispatch = Boolean(entryId && state?.pendingDispatch?.has(entryId));
    const seconds = parseDeltaSeconds(node.dataset.scheduledAt, now);
    const dispatching = shouldShowDispatching({
      seconds,
      outcome,
      pending: pendingDispatch,
    });
    node.textContent = compactRemaining(node.dataset.scheduledAt, now, { outcome, pendingDispatch });
    node.classList.toggle('is-dispatching', dispatching);

    const slotNode = node.closest('.flow-item');
    slotNode?.classList.toggle('is-sending', dispatching || pendingDispatch);
    slotNode?.classList.toggle('is-near-due', !dispatching && Number.isFinite(seconds) && seconds > 0 && seconds <= 120);
  });
}

async function maybeDispatchDueAnchors(root, flowPanel, refreshFlow) {
  const state = root._automationState;
  if (!state || flowPanel.hidden) return;

  const anchors = Object.values(state.anchors || {}).filter(Boolean);
  if (!anchors.length) return;

  const now = Date.now() + Number(root._flowClockOffsetMs || 0);
  for (const anchor of anchors) {
    const entryId = anchor.entry_id;
    if (!entryId) continue;
    const targetMs = new Date(anchor.scheduled_at || '').getTime();
    if (!Number.isFinite(targetMs) || targetMs > now) continue;

    const cooldownUntil = state.dispatchCooldown.get(entryId) || 0;
    if (cooldownUntil > now) continue;
    if (state.pendingDispatch.has(entryId)) continue;

    state.pendingDispatch.add(entryId);
    state.dispatchCooldown.set(entryId, now + 90_000);
    const node = root.querySelector(`.flow-item[data-entry-id="${entryId}"]`);
    node?.classList.add('is-sending');
    node?.querySelector('.flow-item__eta')?.classList.add('is-dispatching');

    try {
      toast('Yayın saati geldi, gönderiliyor...', '');
      const result = await api.schedulerRunNow();
      const processed = Array.isArray(result?.items) ? result.items : [];
      const hit = processed.find((it) => it.id === entryId);

      if (hit?.status === 'done') {
        toast('Yayın saati geldi: gönderi Instagram akışına işlendi.', 'ok');
        await refreshFlow({ animateShift: true });
      } else if (hit?.status === 'failed') {
        toast('Yayın denemesi başarısız. Detayı alttaki log kartından izleyin.', 'err');
        await refreshFlow({ animateShift: false });
      } else if (hit?.status === 'ready') {
        toast('Slot işlendi; otomatik yayın kapalı olduğu için içerik manuel bekliyor.', '');
        await refreshFlow({ animateShift: false });
      } else {
        await refreshFlow({ animateShift: false });
      }
    } catch (e) {
      toast(`Otomatik gönderim tetiklenemedi: ${e.message}`, 'err');
    } finally {
      state.pendingDispatch.delete(entryId);
      node?.classList.remove('is-sending');
    }
  }
}

async function manualDispatchSlot(slot, root, ctx) {
  const entryId = slot?.entry_id;
  if (!entryId) {
    toast('Bu slot için gönderim yapılamıyor (queue id yok).', 'err');
    return;
  }

  const flowPanel = document.getElementById('automation-flow-panel');
  const state = root._automationState;
  if (!state || !flowPanel) return;

  if (state.pendingDispatch.has(entryId)) {
    toast('Bu slot için gönderim zaten devam ediyor.', '');
    return;
  }

  const offset = Number(root._flowClockOffsetMs || 0);
  const serverNowMs = Date.now() + offset;
  const scheduledMs = new Date(slot.scheduled_at || '').getTime();
  const retryAt = Number.isFinite(scheduledMs) && scheduledMs <= serverNowMs
    ? slot.scheduled_at
    : localIsoNoTz(serverNowMs - 1000);

  state.pendingDispatch.add(entryId);
  const node = root.querySelector(`.flow-item[data-entry-id="${entryId}"]`);
  node?.classList.add('is-sending');
  node?.querySelector('.flow-item__eta')?.classList.add('is-dispatching');
  try {
    toast('Gönderi hazırlanıyor, şimdi gönderiliyor...', '');
    await api.reschedule(entryId, retryAt);
    const result = await api.schedulerRunNow();
    const processed = Array.isArray(result?.items) ? result.items : [];
    const hit = processed.find((it) => it.id === entryId);

    if (hit?.status === 'done') {
      toast('Şimdi gönderildi: içerik Instagram akışına işlendi.', 'ok');
      await refreshFlowData(flowPanel, root, ctx, { animateShift: true });
    } else if (hit?.status === 'failed') {
      toast('Gönderim denemesi başarısız. Detayı Logs ekranında görebilirsiniz.', 'err');
      await refreshFlowData(flowPanel, root, ctx, { animateShift: false });
    } else if (hit?.status === 'ready') {
      toast('Slot işlendi; otomatik yayın kapalı olduğu için manuel bekliyor.', '');
      await refreshFlowData(flowPanel, root, ctx, { animateShift: false });
    } else {
      toast('Gönderim tetiklendi, durum yenileniyor.', '');
      await refreshFlowData(flowPanel, root, ctx, { animateShift: false });
    }
  } catch (e) {
    toast(`Şimdi gönder hatası: ${e.message}`, 'err');
  } finally {
    state.pendingDispatch.delete(entryId);
    node?.classList.remove('is-sending');
  }
}

function localIsoNoTz(ms) {
  const d = new Date(ms);
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
    + `T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

async function openAddToSlotPicker({ type, approvedPool, root, ctx }) {
  const pool = approvedPool
    .filter((it) => (it.type || 'gorsel') === type)
    .map((it) => ({ ...it, _assetName: resolveAssetName(it) }))
    .filter((it) => it._assetName && ADD_ELIGIBLE_STATUSES.has(it.status))
    .sort((a, b) => new Date(b.created_at || 0).getTime() - new Date(a.created_at || 0).getTime());

  if (!pool.length) {
    toast('Bu akış için onaylı içerik bulunamadı. Önce kütüphanede bir içeriği onaylayın.', 'err');
    return;
  }

  let selected = null;
  const picker = el('div', { class: 'flow-picker-grid' });
  const tiles = [];
  pool.forEach((item) => {
    const tile = el('button', {
      class: 'flow-picker-item',
      type: 'button',
      onclick: () => {
        selected = item;
        tiles.forEach((t) => t.classList.remove('is-selected'));
        tile.classList.add('is-selected');
        addBtn.disabled = false;
      },
    },
    item.url
      ? el('img', { src: item.url, alt: item.title || item.name, loading: 'lazy' })
      : el('div', { class: 'flow-picker-empty', html: icons.image }),
    el('div', { class: 'flow-picker-item__meta' },
      el('strong', { class: 'clamp-1' }, item.title || item.name),
      el('small', {}, `${fmtDate(item.created_at)} · ${typeBadge(item.type)}`)));
    tiles.push(tile);
    picker.append(tile);
  });

  const addBtn = el('button', {
    class: 'btn btn--primary',
    disabled: 'disabled',
    onclick: async () => {
      if (!selected) return;
      addBtn.disabled = true;
      addBtn.classList.add('is-loading');
      try {
        await api.autoFillReady();
        toast('İçerik otomasyon sırasına eklendi.', 'ok');
        modalCtl.close();
        const flowPanel = document.getElementById('automation-flow-panel');
        if (flowPanel) await refreshFlowData(flowPanel, root, ctx, { animateShift: true });
      } catch (e) {
        toast(`Ekleme başarısız: ${e.message}`, 'err');
        addBtn.disabled = false;
      } finally {
        addBtn.classList.remove('is-loading');
      }
    },
  }, 'Seçilenle Slotu Doldur');

  const body = el('div', { class: 'stack', style: 'gap:12px' },
    el('p', { class: 'muted', style: 'margin:0' },
      `Onaylı ${type === 'haber' ? 'haber' : 'görsel'} içeriklerinden seçip boş slotu doldurabilirsiniz.`),
    picker);

  const footer = [
    el('button', { class: 'btn', onclick: () => modalCtl.close() }, 'Vazgeç'),
    addBtn,
  ];

  const modalCtl = openModal({
    title: `Boş Slotu Doldur · ${type === 'haber' ? 'Haber' : 'Görsel'}`,
    body,
    footer,
    wide: true,
  });
}

async function openReplacePicker({ slot, type, approvedPool, root, ctx }) {
  if (!slot?.entry_id) {
    toast('Bu slot için replace yapılamıyor (queue id yok).', 'err');
    return;
  }

  const pool = approvedPool
    .filter((it) => (it.type || 'gorsel') === type)
    .map((it) => ({ ...it, _assetName: resolveAssetName(it) }))
    .filter((it) => it._assetName && REPLACE_ELIGIBLE_STATUSES.has(it.status))
    .sort((a, b) => new Date(b.created_at || 0).getTime() - new Date(a.created_at || 0).getTime());

  if (!pool.length) {
    toast('Bu akış için yayına uygun görsel bulunamadı.', 'err');
    return;
  }

  let selected = null;
  const picker = el('div', { class: 'flow-picker-grid' });
  const tiles = [];
  pool.forEach((item) => {
    const tile = el('button', {
      class: 'flow-picker-item',
      type: 'button',
      onclick: () => {
        selected = item;
        tiles.forEach((t) => t.classList.remove('is-selected'));
        tile.classList.add('is-selected');
        replaceBtn.disabled = false;
      },
    },
    item.url
      ? el('img', { src: item.url, alt: item.title || item.name, loading: 'lazy' })
      : el('div', { class: 'flow-picker-empty', html: icons.image }),
    el('div', { class: 'flow-picker-item__meta' },
      el('strong', { class: 'clamp-1' }, item.title || item.name),
      el('small', {}, `${fmtDate(item.scheduled_at || item.created_at)} · ${fmtTime(item.scheduled_at || item.created_at)}`)));
    tiles.push(tile);
    picker.append(tile);
  });

  const replaceBtn = el('button', {
    class: 'btn btn--primary',
    disabled: 'disabled',
    onclick: async () => {
      if (!selected) return;
      replaceBtn.disabled = true;
      replaceBtn.classList.add('is-loading');
      try {
        const res = await api.schedulerReplaceAsset(slot.entry_id, { asset_name: selected._assetName });
        toast(res?.swapped_with
          ? 'Slot değiştirildi ve aktif kuyruk girdisiyle swap yapıldı.'
          : 'Slot görseli başarıyla değiştirildi.', 'ok');
        modalCtl.close();
        await refreshFlowData(document.getElementById('automation-flow-panel'), root, ctx, { animateShift: true });
      } catch (e) {
        toast(`Replace başarısız: ${e.message}`, 'err');
        replaceBtn.disabled = false;
      } finally {
        replaceBtn.classList.remove('is-loading');
      }
    },
  }, 'Seçilenle Replace Et');

  const body = el('div', { class: 'stack', style: 'gap:12px' },
    el('p', { class: 'muted', style: 'margin:0' },
      'Bu slotu seçtiğiniz yayına uygun görselle değiştirebilirsiniz. Aynı görsel başka aktif slotta ise sistem swap yapar.'),
    picker);

  const footer = [
    el('button', { class: 'btn', onclick: () => modalCtl.close() }, 'Vazgeç'),
    replaceBtn,
  ];

  const modalCtl = openModal({
    title: 'Onaylı Görsel Seç · Replace',
    body,
    footer,
    wide: true,
  });
}

function computeServerOffset(nowIso) {
  if (!nowIso) return 0;
  const serverMs = new Date(nowIso).getTime();
  if (!Number.isFinite(serverMs)) return 0;
  return serverMs - Date.now();
}

function resolveAssetName(item) {
  return String(item?.name || item?.asset_name || item?.story_name || '').trim();
}

function compactRemaining(scheduledAt, nowRef, options = {}) {
  const outcome = String(options.outcome || '');
  const pendingDispatch = Boolean(options.pendingDispatch);

  if (outcome === 'manual') return 'Manuel yayın';
  if (outcome === 'failed') return 'Tekrar denenecek';

  const secs = parseDeltaSeconds(scheduledAt, nowRef);
  if (!Number.isFinite(secs)) return '—';

  if (shouldShowDispatching({ seconds: secs, outcome, pending: pendingDispatch })) {
    return 'Gönderiliyor...';
  }

  let remain = secs;
  if (remain <= 15) return 'Birazdan';
  const day = Math.floor(remain / 86400);
  remain -= day * 86400;
  const hour = Math.floor(remain / 3600);
  remain -= hour * 3600;
  const min = Math.floor(remain / 60);
  const sec = remain - (min * 60);
  if (day > 0) return `${day} gün sonra`;
  if (hour > 0) return `${hour} saat sonra`;
  if (min > 0) return `${min} dk sonra`;
  return `${Math.max(1, sec)} sn sonra`;
}

function parseDeltaSeconds(scheduledAt, nowRef) {
  if (!scheduledAt) return null;
  const target = new Date(scheduledAt).getTime();
  const now = typeof nowRef === 'number'
    ? nowRef
    : (nowRef ? new Date(nowRef).getTime() : Date.now());
  if (!Number.isFinite(target) || !Number.isFinite(now)) return null;
  return Math.floor((target - now) / 1000);
}

function parseNowMs(nowRef) {
  if (!nowRef) return Date.now();
  if (typeof nowRef === 'number') return nowRef;
  const ms = new Date(nowRef).getTime();
  return Number.isFinite(ms) ? ms : Date.now();
}

function activeFlowLaneTypes(config) {
  const out = [];
  ['haber', 'gorsel'].forEach((type) => {
    const key = FLOW_KIND_TO_CONFIG[type];
    if (!key) return;
    const lane = config?.[key];
    if (lane?.enabled) out.push(type);
  });
  return out;
}

function shouldShowDispatching({ seconds, outcome, pending }) {
  if (pending) return true;
  if (outcome === 'publishing') return true;
  if (outcome === 'failed' || outcome === 'manual' || outcome === 'success') return false;
  return Number.isFinite(seconds) && seconds <= 0;
}

function flowStatusText(slot, dispatching) {
  if (slot?.publish_outcome === 'manual') return slot.publish_outcome_tr || 'Manuel yayın gerekli';
  if (slot?.publish_outcome === 'failed') return slot.publish_outcome_tr || 'Başarısız';
  if (dispatching) return 'Gönderiliyor';
  return slot?.publish_outcome_tr || slot?.status_tr || 'Planlandı';
}

function weekFlow(tl) {
  const grid = el('div', { class: 'timeline' });
  let total = 0;
  for (const day of tl.days) {
    total += day.items.length;
    const col = el('div', { class: `timeline__col ${day.is_today ? 'is-today' : ''}` },
      el('div', { class: 'timeline__day' }, day.day_name),
      el('div', { class: 'timeline__date' }, day.date_label));
    if (!day.items.length) col.append(el('div', { class: 'timeline__empty' }, '—'));
    else for (const it of day.items) col.append(timelineItem(it));
    grid.append(col);
  }
  return el('div', { class: 'card' },
    el('div', { class: 'card__head' },
      el('h3', {}, 'Bu Hafta Yayın Akışı'),
      el('span', { class: 'badge badge--muted' }, `Bu hafta ${total} yayın`)),
    el('div', { style: 'padding:8px 12px' }, grid));
}

function timelineItem(it) {
  const media = el('div', { class: 'tl-item__media' },
    el('span', { class: 'tl-item__placeholder', html: icons.image }));
  if (it.url) {
    const img = el('img', {
      class: 'tl-item__thumb', src: it.url, alt: '', loading: 'lazy',
      onerror: () => img.remove(),
    });
    media.prepend(img);
  }
  const card = el('div', {
    class: `tl-item ${it.type} is-clickable`,
    role: 'button',
    tabindex: '0',
    onclick: () => openPreview(it),
    onkeydown: (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        openPreview(it);
      }
    },
  },
    media,
    el('div', { class: 'tl-item__body' },
      el('div', { class: 'tl-item__time' }, el('span', { class: `tl-item__dot ${it.type}` }), it.time),
      el('div', { class: 'tl-item__title' }, it.title)));
  return card;
}

function nextCard(next, now) {
  const box = el('div', { class: 'card' },
    el('div', { class: 'card__head' }, el('h3', {}, 'Sıradaki Yayın')));
  if (!next) {
    box.append(el('div', { class: 'card__body' }, el('p', { class: 'muted' }, 'Yayına hazır içerik bulunmuyor.')));
    return box;
  }
  const remainingText = countdownText(next.scheduled_at, now);
  const outcomeTone = statusToneFromOutcome(next.publish_outcome);
  const outcomeLabel = next.publish_outcome_tr || (next.status_tr || 'Planlandı');
  const preview = next.url
    ? el('img', {
      src: next.url,
      alt: next.title || 'Sıradaki yayın görseli',
      class: 'next-preview__img',
      loading: 'lazy',
    })
    : el('div', { class: 'next-preview__placeholder', html: icons.image });

  box.append(el('div', { class: 'card__body' },
    el('button', { class: 'next-preview', type: 'button', onclick: () => openPreview(next) },
      preview,
      el('span', { class: 'next-preview__countdown' }, remainingText)),
    el('div', { class: 'hstack', style: 'margin-bottom:12px' },
      el('span', { class: `slot-card__icon ${next.type}`, html: next.type === 'haber' ? icons.news : icons.image }),
      el('span', { html: typeBadge(next.type) }),
      el('span', { class: `badge badge--${outcomeTone}` }, outcomeLabel)),
    el('div', { style: 'font-family:var(--serif);font-size:18px' }, next.title),
    el('div', { class: 'muted', style: 'font-size:12.5px;margin-top:6px' },
      `${fmtDate(next.scheduled_at)} · ${fmtTime(next.scheduled_at)}`),
    next.last_attempt_at
      ? el('div', { class: 'muted', style: 'font-size:11.5px;margin-top:4px' },
        `Son deneme: ${fmtDate(next.last_attempt_at)} · ${fmtTime(next.last_attempt_at)}`)
      : null,
    next.failure_reason
      ? el('div', { class: 'badge badge--danger', style: 'margin-top:8px;display:inline-flex' },
        `Neden: ${next.failure_reason}`)
      : null,
    el('div', { class: 'divider' }),
    el('div', { class: 'metric__label' }, 'Yayına Kalan Süre'),
    el('div', { style: 'font-family:var(--serif);font-size:22px;color:var(--type-gorsel);margin-top:4px' },
      remainingText),
    el('div', { class: 'muted', style: 'font-size:11.5px;margin-top:4px' }, 'Otomatik olarak yayınlanacak')));
  return box;
}

function publishedList(items) {
  const card = el('div', { class: 'card' },
    el('div', { class: 'card__head' },
      el('h3', {}, 'Son Yayınlanan 5 İçerik'),
      el('span', { class: 'badge badge--muted' }, `${items.length} kayıt`)));

  const body = el('div', { class: 'card__body', style: 'padding-top:8px' });
  if (!items.length) {
    body.append(el('p', { class: 'muted', style: 'margin:0' }, 'Henüz yayınlanan içerik bulunmuyor.'));
    card.append(body);
    return card;
  }

  const list = el('div', { class: 'rowlist' });
  for (const it of items) {
    const row = el('button', {
      class: 'rowitem rowitem--clickable',
      type: 'button',
      onclick: () => openPreview(it),
    },
    it.url
      ? el('img', { class: 'rowitem__thumb', src: it.url, alt: it.title || '', loading: 'lazy' })
      : el('div', { class: 'rowitem__thumb' }),
    el('div', { class: 'rowitem__main' },
      el('div', { class: 'rowitem__title' }, it.title || 'Yayınlanan içerik'),
      el('div', { class: 'rowitem__sub' },
        el('span', { html: typeBadge(it.type || 'gorsel') }),
        el('span', { class: 'badge badge--ok' }, it.publish_outcome_tr || 'Başarılı'),
        el('span', {}, `${fmtDate(it.uploaded_at)} · ${fmtTime(it.uploaded_at)}`))),
    el('div', { class: 'rowitem__cd muted', style: 'font-size:11px' }, 'Önizle'));
    list.append(row);
  }
  body.append(list);
  card.append(body);
  return card;
}

function publishLogCard(publishes) {
  const card = el('div', { class: 'card' },
    el('div', { class: 'card__head' },
      el('h3', {}, 'Yayın Logu (Son Durumlar)'),
      el('span', { class: 'badge badge--muted' }, 'Başarılı / Başarısız / Tarih')));

  const body = el('div', { class: 'card__body', style: 'padding-top:8px' });
  const upcoming = Array.isArray(publishes?.upcoming) ? publishes.upcoming : [];
  const published = Array.isArray(publishes?.published) ? publishes.published : [];

  const events = [];
  for (const it of upcoming) {
    const ts = Date.parse(it.last_result_at || it.last_attempt_at || it.scheduled_at || '') || 0;
    const details = [`Plan: ${fmtDate(it.scheduled_at)} · ${fmtTime(it.scheduled_at)}`];
    if (it.last_attempt_at) details.push(`Son deneme: ${fmtDate(it.last_attempt_at)} · ${fmtTime(it.last_attempt_at)}`);
    if (it.failure_reason) details.push(`Neden: ${it.failure_reason}`);
    events.push({
      ts,
      title: it.title || 'Planlı yayın',
      type: it.type || 'gorsel',
      url: it.url,
      status: it.publish_outcome || it.status,
      statusLabel: it.publish_outcome_tr || it.status_tr || 'Planlandı',
      details: details.join(' · '),
    });
  }
  for (const it of published) {
    const ts = Date.parse(it.uploaded_at || '') || 0;
    events.push({
      ts,
      title: it.title || 'Yayınlanan içerik',
      type: it.type || 'gorsel',
      url: it.url,
      status: 'success',
      statusLabel: it.publish_outcome_tr || 'Başarılı',
      details: `Yayınlandı: ${fmtDate(it.uploaded_at)} · ${fmtTime(it.uploaded_at)}`,
    });
  }

  events.sort((a, b) => b.ts - a.ts);
  if (!events.length) {
    body.append(el('p', { class: 'muted', style: 'margin:0' },
      'Henüz log kaydı bulunmuyor. İlk yayın denemesiyle burada durum satırları görünecek.'));
    card.append(body);
    return card;
  }

  const list = el('div', { class: 'rowlist' });
  for (const ev of events.slice(0, 12)) {
    list.append(el('div', { class: 'rowitem' },
      ev.url
        ? el('img', { class: 'rowitem__thumb', src: ev.url, alt: ev.title || '', loading: 'lazy' })
        : el('div', { class: 'rowitem__thumb' }),
      el('div', { class: 'rowitem__main' },
        el('div', { class: 'rowitem__title' }, ev.title),
        el('div', { class: 'rowitem__sub' },
          el('span', { html: typeBadge(ev.type) }),
          el('span', { class: `badge badge--${statusToneFromOutcome(ev.status)}` }, ev.statusLabel),
          el('span', {}, ev.details))),
      el('div', { class: 'rowitem__cd muted', style: 'font-size:11px' }, 'Log')));
  }
  body.append(list);
  card.append(body);
  return card;
}

function statusToneFromOutcome(outcome) {
  if (outcome === 'success') return 'ok';
  if (outcome === 'failed') return 'danger';
  if (outcome === 'overdue' || outcome === 'manual' || outcome === 'publishing') return 'warn';
  return 'muted';
}

function openPreview(item) {
  const title = item?.title || 'İçerik önizleme';
  const image = item?.url
    ? el('img', {
      class: 'automation-preview__img',
      src: item.url,
      alt: title,
      loading: 'lazy',
    })
    : el('div', { class: 'automation-preview__empty', html: icons.image });

  const meta = el('div', { class: 'vstack', style: 'gap:8px;margin-top:12px' },
    el('div', { class: 'hstack', style: 'justify-content:space-between;align-items:flex-start' },
      el('strong', { style: 'font-size:14px;line-height:1.35' }, title),
      el('span', { html: typeBadge(item?.type || 'gorsel') })),
    item?.scheduled_at
      ? el('div', { class: 'muted', style: 'font-size:12.5px' }, `${fmtDate(item.scheduled_at)} · ${fmtTime(item.scheduled_at)}`)
      : null,
    item?.uploaded_at
      ? el('div', { class: 'muted', style: 'font-size:12.5px' }, `Yayınlandı: ${fmtDate(item.uploaded_at)} · ${fmtTime(item.uploaded_at)}`)
      : null);

  openModal({
    title: 'İçerik Önizleme',
    body: el('div', { class: 'vstack', style: 'gap:0' }, image, meta),
    wide: true,
  });
}
