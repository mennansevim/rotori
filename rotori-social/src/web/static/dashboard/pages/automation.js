// =========================================================================
// pages/automation.js — Otomasyon (yayın slotları)
// =========================================================================
import { api, el, icons, typeBadge, countdownText, fmtDate, fmtTime,
         errorState, loadingState, toast, openModal, confirmModal } from '../lib.js?v=20260821-1';

const DAYS = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];  // launchd: 1..6,0
const fmtDayTime = (iso) => {
  if (!iso) return '';
  try {
    const d = new Date(iso);
    const day = DAYS[(d.getDay() + 6) % 7];  // JS getDay: 0=Paz, DAYS: 0=Pzt
    const time = d.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });
    return `${day} ${time}`;
  } catch { return ''; }
};
const DAY_TO_LAUNCHD = [1, 2, 3, 4, 5, 6, 0];  // index → launchd weekday
const FLOW_LIMIT = 5;
const READY_LIBRARY_STATUSES = new Set(['approved', 'queued', 'scheduled', 'publishing', 'failed']);
const REPLACE_ELIGIBLE_STATUSES = new Set(['approved', 'queued', 'scheduled']);
const ACTIVE_QUEUE_STATUSES = new Set(['pending', 'ready', 'uploading']);

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

const FLOW_TYPES = ['haber', 'gorsel'];
const LANE_CFG_KEYS = ['days', 'hour', 'minute', 'auto_publish'];
const clone = (value) => JSON.parse(JSON.stringify(value ?? {}));
const pad2 = (value) => String(Number(value) || 0).padStart(2, '0');

export async function renderAutomation(root, ctx, params) {
  const previousHistoryExpanded = Boolean(root._automationState?.historyExpanded);
  clearAutomationTimers(root);
  root.innerHTML = '';
  root.append(el('div', { class: 'page__head' },
    el('div', {},
      el('h1', { class: 'page__title' }, 'Otomasyon'),
      el('div', { class: 'page__subtitle' },
        'Her akışın yayın düzeni kendi kartının üstünde durur. Anahtarı kapatılan akış planlanmaz.'))));

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

  const state = {
    nowIso: publishes?.now || data?.timeline?.now || null,
    publishes,
    library: Array.isArray(library?.items) ? library.items : [],
    // config = sunucuda kayıtlı hâli; drafts = akış kartındaki düzenlenen kopya
    config: clone(data.config),
    drafts: {},
    savingLanes: new Set(),
    historyExpanded: previousHistoryExpanded,
    pendingDispatch: new Set(),
    dispatchCooldown: new Map(),
  };
  resetLaneDrafts(state);

  root._automationState = state;

  const flowPanel = el('section', { class: 'automation-panel', id: 'automation-flow-panel' });
  const historyPanel = el('section', { class: 'automation-panel', id: 'automation-history-panel' });
  body.innerHTML = '';
  body.append(flowPanel, historyPanel);

  renderFlowPanel(flowPanel, state, root, ctx, { animateShift: false });
  renderHistoryPanel(historyPanel, state, ctx);

  // Ayarlar ekranındaki "Yayın düzenini aç" kısayolu artık akış kartlarına iner.
  if (params?.tab === 'settings') highlightLaneConfigs(flowPanel);

  startAutomationTimers(root, ctx, flowPanel, async (opts = {}) => {
    await refreshFlowData(flowPanel, root, ctx, opts);
  });
}

/* ------------------------------------------------- Akış düzeni (lane config) */
function resetLaneDrafts(state) {
  state.drafts = {};
  FLOW_TYPES.forEach((type) => { state.drafts[type] = clone(laneBaseline(state, type)); });
}

function laneBaseline(state, type) {
  return state.config?.[FLOW_KIND_TO_CONFIG[type]] || {};
}

function laneDraft(state, type) {
  if (!state.drafts[type]) state.drafts[type] = clone(laneBaseline(state, type));
  return state.drafts[type];
}

function normalizeLaneValue(key, value) {
  if (key === 'days') return [...(value || [])].map(Number).sort((a, b) => a - b);
  if (key === 'auto_publish') return Boolean(value);
  return Number(value || 0);
}

function laneDirty(state, type) {
  const base = laneBaseline(state, type);
  const draft = laneDraft(state, type);
  return LANE_CFG_KEYS.some((key) => JSON.stringify(normalizeLaneValue(key, draft[key]))
    !== JSON.stringify(normalizeLaneValue(key, base[key])));
}

function anyLaneDirty(state) {
  return FLOW_TYPES.some((type) => laneDirty(state, type));
}

function laneActiveQueueCount(state, type) {
  const upcoming = Array.isArray(state.publishes?.upcoming) ? state.publishes.upcoming : [];
  return upcoming.filter((it) => (it.type || 'gorsel') === type
    && ACTIVE_QUEUE_STATUSES.has(it.queue_status)).length;
}

function highlightLaneConfigs(flowPanel) {
  const first = flowPanel.querySelector('.lane-cfg');
  if (!first) return;
  first.scrollIntoView({ behavior: 'smooth', block: 'center' });
  flowPanel.querySelectorAll('.lane-cfg').forEach((node) => {
    node.classList.add('is-highlight');
    setTimeout(() => node.classList.remove('is-highlight'), 2200);
  });
}

/**
 * Akış kartının üstündeki düzen şeridi: gün / saat / otomatik yayın.
 * Değişiklikler taslakta tutulur; "Kaydet" ile sunucuya gider.
 */
function laneConfigStrip(type, state, root, ctx) {
  const draft = laneDraft(state, type);
  const isWeeklyNews = type === 'haber';
  const disabled = state.savingLanes.has(type);
  const strip = el('div', { class: `lane-cfg lane-cfg--${type}` });
  const actions = el('div', { class: 'lane-cfg__actions' });

  const dayBtns = el('div', { class: 'daypicker' });
  const dayButtons = [];
  const refreshDayButtons = () => {
    dayButtons.forEach(({ button, weekday }) => {
      const on = (draft.days || []).includes(weekday);
      button.classList.toggle('is-on', on);
      button.classList.toggle(type, on);
      button.setAttribute('aria-pressed', String(on));
    });
  };
  DAYS.forEach((label, idx) => {
    const lw = DAY_TO_LAUNCHD[idx];
    const button = el('button', {
      type: 'button',
      disabled: disabled ? '' : null,
      onclick: () => {
        const conf = draft;
        const has = (conf.days || []).includes(lw);
        if (isWeeklyNews) {
          // Mavi haber akışı haftada tam bir kez çalışır; gün seçici radio
          // gibi davranır ve seçili günü ikinci kez tıklamak boş bırakmaz.
          conf.days = [lw];
        } else {
          conf.days = has ? conf.days.filter((d) => d !== lw) : [...(conf.days || []), lw];
        }
        refreshDayButtons();
        syncActions();
      },
    }, label);
    dayButtons.push({ button, weekday: lw });
    dayBtns.append(button);
  });
  refreshDayButtons();

  const timeInput = el('input', {
    class: 'input lane-cfg__time',
    type: 'time',
    disabled: disabled ? '' : null,
    value: `${pad2(draft.hour)}:${pad2(draft.minute)}`,
    onchange: (e) => {
      const [h, m] = String(e.target.value || '').split(':');
      draft.hour = Number(h) || 0;
      draft.minute = Number(m) || 0;
      syncActions();
    },
  });

  const autoPublish = el('input', {
    type: 'checkbox',
    disabled: disabled ? '' : null,
    checked: draft.auto_publish ? '' : null,
    onchange: (e) => { draft.auto_publish = e.target.checked; syncActions(); },
  });

  strip.append(
    el('div', { class: 'lane-cfg__group' },
      el('span', { class: 'lane-cfg__label' }, isWeeklyNews ? 'Haftalık gün' : 'Günler'),
      dayBtns),
    el('div', { class: 'lane-cfg__group' },
      el('span', { class: 'lane-cfg__label' }, 'Saat'),
      timeInput),
    el('label', { class: 'lane-cfg__group lane-cfg__check' },
      autoPublish,
      el('span', {}, 'Saati gelince otomatik yayınla')),
    actions);

  function syncActions() {
    const dirty = laneDirty(state, type);
    strip.classList.toggle('is-dirty', dirty);
    actions.innerHTML = '';
    if (!dirty) {
      actions.append(el('span', { class: 'lane-cfg__hint' },
        laneBaseline(state, type).enabled
          ? 'Düzen kayıtlı'
          : 'Akış kapalı — düzen kayıtlı'));
      return;
    }
    actions.append(
      el('span', { class: 'lane-cfg__dirty' }, 'Kaydedilmemiş düzen'),
      el('button', {
        class: 'btn btn--sm',
        type: 'button',
        onclick: () => {
          state.drafts[type] = clone(laneBaseline(state, type));
          renderFlowPanel(document.getElementById('automation-flow-panel'), state, root, ctx, {});
        },
      }, 'Vazgeç'),
      el('button', {
        class: 'btn btn--sm btn--primary',
        type: 'button',
        html: `${icons.check}<span>Kaydet</span>`,
        onclick: () => saveLane(type, state, root, ctx),
      }));
  }

  syncActions();
  return strip;
}

/** Akış düzenini kaydet; kuyruk yeniden sıralanır ve ekran baştan kurulur. */
async function saveLane(type, state, root, ctx, patch = {}, options = {}) {
  if (state.savingLanes.has(type)) return false;
  const configKey = FLOW_KIND_TO_CONFIG[type];
  const payload = { ...laneDraft(state, type), ...patch };
  state.savingLanes.add(type);
  try {
    const res = await api.automationConfigSet({ [configKey]: payload });
    if (res?.config) state.config = clone(res.config);
    state.drafts[type] = clone(laneBaseline(state, type));
    toast(options.message || laneSaveMessage(res?.queue_sync || {}), 'ok');
    if (res?.launchd && res.launchd.length) console.log('launchd:', res.launchd);
    await renderAutomation(root, ctx);
    return true;
  } catch (e) {
    toast('Kayıt başarısız: ' + e.message, 'err');
    return false;
  } finally {
    state.savingLanes.delete(type);
  }
}

function laneSaveMessage(sync) {
  const moved = Number(sync.scheduled || 0) + Number(sync.rescheduled || 0);
  const dropped = Number(sync.unscheduled || 0);
  if (dropped) return `Yayın düzeni kaydedildi · ${dropped} içerik sıradan çıkarıldı.`;
  if (moved) return `Yayın düzeni kaydedildi · ${moved} içeriğin yayın sırası güncellendi.`;
  return 'Yayın düzeni kaydedildi.';
}

/** Akışı aç/kapat. Kapatma planlı içerikleri sıradan çıkardığı için onay ister. */
async function toggleLane(type, state, root, ctx, nextEnabled, checkbox) {
  const kind = type === 'haber' ? 'haber' : 'görsel';
  const draft = laneDraft(state, type);

  if (nextEnabled && type === 'haber' && (draft.days || []).length !== 1) {
    toast('Haber akışı için tek bir yayın günü seçmelisiniz.', 'err');
    checkbox.checked = false;
    return;
  }
  if (nextEnabled && !(draft.days || []).length) {
    toast('Akışı açmadan önce en az bir yayın günü seçin.', 'err');
    checkbox.checked = false;
    return;
  }

  if (!nextEnabled) {
    const affected = laneActiveQueueCount(state, type);
    const confirmed = await confirmModal({
      title: `${FLOW_META[type].title} kapatılsın mı?`,
      message: affected
        ? `${affected} planlı ${kind} içeriği yayın sırasından çıkarılacak. İçerikler silinmez; akışı yeniden açtığınızda sıraya geri alınır.`
        : `Onaylanan ${kind} içerikleri bundan sonra otomatik planlanmaz.`,
      confirmLabel: 'Akışı kapat',
      danger: true,
    });
    if (!confirmed) { checkbox.checked = true; return; }
  }

  checkbox.disabled = true;
  const ok = await saveLane(type, state, root, ctx, { enabled: nextEnabled }, {
    message: nextEnabled
      ? `${FLOW_META[type].title} açıldı; onaylı içerikler sıraya alınıyor.`
      : `${FLOW_META[type].title} kapatıldı.`,
  });
  if (!ok) {
    checkbox.checked = !nextEnabled;
    checkbox.disabled = false;
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
      el('div', { class: 'flow-hero__eyebrow' }, 'Otomatik yayın'),
      el('h3', { class: 'flow-hero__title' }, 'Yayın Planı'),
      el('p', { class: 'muted', style: 'margin:6px 0 0' },
        'En yakın yayın sağda görünür. Saati geldiğinde gönderim otomatik başlar ve sıra kendiliğinden ilerler.')),
    el('div', { class: 'flow-hero__meta' },
      el('span', { class: 'badge badge--muted' }, `Onaylı havuz: ${approvedPool.length}`),
      el('span', { class: 'badge badge--muted' }, `Aktif akış: ${activeFlowTypes.length}/${FLOW_TYPES.length}`),
      el('span', { class: 'badge badge--muted' }, `Saat: ${fmtTime(nowIso) || '—'}`))
  )));

  const flowStack = el('div', { class: 'flow-stack' });
  const anchors = {};

  // Kapalı akışlar da listede kalır: düzenini görüp anahtarla açabilmek için.
  FLOW_TYPES.forEach((type) => {
    const enabled = Boolean(laneBaseline(state, type).enabled);
    const flowData = enabled ? buildFlowData(upcoming, type) : null;
    anchors[type] = enabled ? flowData.anchor : null;
    flowStack.append(flowRow(type, flowData, approvedPool, nowIso, root, ctx, options, state));
  });
  panel.append(flowStack);

  state.anchors = anchors;
  root._flowClockOffsetMs = computeServerOffset(nowIso);
}

function buildFlowData(upcoming, type) {
  const typed = [...upcoming]
    .filter((it) => (it.type || 'gorsel') === type)
    .filter((it) => ACTIVE_QUEUE_STATUSES.has(it.queue_status))
    .sort((a, b) => new Date(a.scheduled_at || 0).getTime() - new Date(b.scheduled_at || 0).getTime());

  // Aktif sıranın ilk beş kaydı gösterilir. Geçmiş failed/cancelled kayıtlar
  // logda kalır ama canlı sırayı ve sağdaki anchor kartını bloke etmez.
  const nearest = typed.slice(0, FLOW_LIMIT);
  const ordered = [...nearest].reverse(); // solda uzak tarih, sağda en yakın

  if (!ordered.length) {
    return {
      total: typed.length,
      hiddenFuture: 0,
      slots: [{
        _placeholder: 'empty',
        _type: type,
      }],
      anchor: null,
      compact: true,
      empty: true,
    };
  }

  const slots = [...ordered];
  if (ordered.length < FLOW_LIMIT) {
    slots.push({ _placeholder: 'add', _type: type });
  }

  return {
    total: typed.length,
    hiddenFuture: Math.max(0, typed.length - FLOW_LIMIT),
    slots,
    anchor: ordered.length ? ordered[ordered.length - 1] : null,
    compact: ordered.length < FLOW_LIMIT,
    empty: false,
  };
}

function flowRow(type, flowData, approvedPool, nowIso, root, ctx, options, state) {
  const meta = FLOW_META[type];
  const laneConfig = laneBaseline(state, type);
  const enabled = Boolean(laneConfig.enabled);
  const saving = state.savingLanes.has(type);
  const row = el('section', { class: `card flow-row flow-row--${type} ${enabled ? '' : 'is-off'}` });

  const enableToggle = el('input', {
    type: 'checkbox',
    checked: enabled ? '' : null,
    disabled: saving ? '' : null,
    'aria-label': `${meta.title} otomasyonu`,
    onchange: (e) => toggleLane(type, state, root, ctx, e.target.checked, e.target),
  });

  const head = el('div', { class: 'card__head flow-row__head' },
    el('div', {},
      el('h3', {}, meta.title),
      el('div', { class: 'flow-row__sub' }, meta.subtitle)),
    el('div', { class: 'hstack flow-row__head-meta' },
      el('span', { html: typeBadge(type) }),
      el('span', { class: 'badge badge--muted' }, cadenceLabel(laneConfig)),
      enabled
        ? el('span', { class: 'badge badge--muted' }, `Sırada ${flowData.total} içerik`)
        : null,
      el('label', { class: 'lane-switch' },
        el('span', { class: 'lane-switch__text' }, enabled ? 'Açık' : 'Kapalı'),
        el('span', { class: 'switch' }, enableToggle, el('span', { class: 'switch__track' })))));

  // Akış kapalıysa kart yalnızca düzen şeridini ve açıklamayı gösterir.
  if (!enabled) {
    row.append(head, el('div', { class: 'card__body flow-row__body' },
      laneConfigStrip(type, state, root, ctx),
      el('div', { class: 'flow-row__off' },
        el('span', { class: 'flow-row__off-icon', html: type === 'haber' ? icons.news : icons.image }),
        el('strong', {}, 'Bu akış kapalı'),
        el('span', { class: 'muted' },
          `Onaylanan ${type === 'haber' ? 'haber' : 'görsel'} içerikleri planlanmaz. Gün ve saati ayarlayıp yukarıdaki anahtarla açabilirsiniz.`))));
    return row;
  }

  const trackClasses = ['flow-track'];
  if (options.animateShift) trackClasses.push('is-shift');
  if (flowData.compact) trackClasses.push('is-compact');
  if (flowData.empty) trackClasses.push('is-empty');
  const track = el('div', { class: trackClasses.join(' ') });
  const anchor = flowData.anchor;
  flowData.slots.forEach((slot) => {
    track.append(flowSlot(type, slot, slot && anchor && slot.entry_id === anchor.entry_id,
      approvedPool, nowIso, root, ctx));
  });

  const nowSendBtn = anchor
    ? el('button', {
      class: 'btn btn--sm btn--ghost flow-row__send-btn',
      type: 'button',
      html: `${icons.send}<span>Şimdi yayınla</span>`,
      onclick: async (event) => {
        event.preventDefault();
        event.stopPropagation();
        const confirmed = await confirmModal({
          title: 'Şimdi yayınla',
          message: `“${anchor.title || 'Sıradaki içerik'}” planlanan saati beklemeden Instagram’a gönderilecek.`,
          confirmLabel: 'Şimdi yayınla',
        });
        if (!confirmed) return;
        const btn = event.currentTarget;
        const oldHtml = btn.innerHTML;
        btn.disabled = true;
        btn.innerHTML = `${icons.clock}<span>Gönderiliyor...</span>`;
        try {
          await manualDispatchSlot(anchor, root, ctx);
        } finally {
          btn.disabled = false;
          btn.innerHTML = oldHtml;
        }
      },
    })
    : null;

  row.append(head, el('div', { class: 'card__body flow-row__body' },
    laneConfigStrip(type, state, root, ctx), track,
    el('div', { class: 'flow-row__legend' },
      el('div', { class: 'flow-row__legend-main' },
        el('span', {}, (flowData.hiddenFuture || 0) > 0
          ? `Sonraki ${flowData.hiddenFuture} içerik sırada bekliyor. Kartı seçerek içeriği değiştirebilirsiniz.`
          : 'Bir kartı seçerek planlanan içeriği değiştirebilirsiniz.'),
        anchor ? el('span', { class: 'flow-row__live' }, `Canlı takip: ${anchor.title || 'Sıradaki gönderi'}`) : null),
      el('div', { class: 'flow-row__legend-actions' }, nowSendBtn))));
  return row;
}

function flowSlot(type, slot, isAnchor, approvedPool, nowIso, root, ctx) {
  if (slot && slot._placeholder) {
    return flowPlaceholderSlot(type, slot._placeholder, ctx, root);
  }

  const title = slot.title || 'Planlı gönderi';
  const pendingDispatch = Boolean(root._automationState?.pendingDispatch?.has(slot.entry_id));
  const seconds = parseDeltaSeconds(slot.scheduled_at, nowIso);
  const dispatching = shouldShowDispatching({
    seconds,
    outcome: slot.publish_outcome,
    pending: pendingDispatch,
  });
  const etaText = compactRemaining(slot.scheduled_at, nowIso, {
    outcome: slot.publish_outcome,
    pendingDispatch,
  });
  const statusText = flowStatusText(slot, dispatching);

  const btn = el('button', {
    class: `flow-slot flow-slot--${type} ${isAnchor ? 'is-anchor' : ''}`,
    type: 'button',
    dataset: {
      entryId: slot.entry_id || '',
      scheduledAt: slot.scheduled_at || '',
      flowType: type,
    },
    onclick: async () => {
      await openReplacePicker({ slot, type, approvedPool, root, ctx });
    },
  },
  el('div', { class: 'flow-slot__media' },
    slot.url
      ? el('img', { src: slot.url, alt: title, class: 'flow-slot__img', loading: 'lazy' })
      : el('div', { class: 'flow-slot__img flow-slot__img--empty', html: icons.image })),
  el('div', { class: 'flow-slot__overlay' },
    el('div', { class: 'flow-slot__top' },
      el('span', { class: 'flow-slot__time' }, fmtDayTime(slot.scheduled_at) || '—'),
      el('span', { class: `badge badge--${statusToneFromOutcome(slot.publish_outcome)}` }, statusText)),
    el('div', { class: 'flow-slot__title clamp-2' }, title),
    el('div', { class: 'flow-slot__bottom' },
      el('span', {
        class: `flow-slot__eta${dispatching ? ' is-dispatching' : ''}`,
        dataset: {
          scheduledAt: slot.scheduled_at || '',
          outcome: slot.publish_outcome || '',
          entryId: slot.entry_id || '',
        },
      }, etaText),
      el('span', { class: 'flow-slot__action' }, 'Değiştir'))));

  if (isAnchor) {
    btn.classList.add('is-live-anchor');
    btn.append(el('span', { class: 'flow-slot__live-badge' }, 'Canlı'));
  }
  if (dispatching || pendingDispatch) {
    btn.classList.add('is-sending');
  }
  if (!dispatching && Number.isFinite(seconds) && seconds > 0 && seconds <= 120) {
    btn.classList.add('is-near-due');
  }
  return btn;
}

function flowPlaceholderSlot(type, mode, ctx, root) {
  const kind = type === 'haber' ? 'haber' : 'görsel';
  const isEmpty = mode === 'empty';
  const isQuiet = mode === 'quiet';
  const title = isEmpty
    ? `Henüz planlı ${kind} slotu yok`
    : isQuiet
      ? `Bu akışta yakın vadede planlı ${kind} slotu yok`
    : `${kind[0].toUpperCase()}${kind.slice(1)} akışında boş yer var`;
  const subtitle = isEmpty
    ? 'Kütüphanede onaylayıp otomasyona ekleyin.'
    : isQuiet
      ? 'Bu akışta yakın vadeli bir yayın bulunmuyor.'
      : 'Onaylı içeriklerle sırayı hızlıca doldurabilirsiniz.';

  return el('button', {
    class: `flow-slot flow-slot--cta ${isEmpty ? 'is-empty' : (isQuiet ? 'is-empty' : 'is-add')}`,
    type: 'button',
    onclick: () => {
      if (!isEmpty && !isQuiet) {
        openAddToFlowPicker({ type, root, ctx });
      } else if (!isQuiet) {
        ctx.navigate('library');
      }
    },
  },
  el('span', { class: 'flow-slot__cta-icon', html: icons.plus }),
  el('strong', { class: 'flow-slot__cta-title' }, title),
  el('span', { class: 'flow-slot__cta-sub' }, subtitle),
  el('span', { class: 'flow-slot__cta-link' }, (!isEmpty && !isQuiet) ? 'İçerik seç' : 'Kütüphaneye git'));
}

function cadenceLabel(conf) {
  const days = Array.isArray(conf?.days) ? conf.days : [];
  const labels = days
    .map((weekday) => DAYS[DAY_TO_LAUNCHD.indexOf(Number(weekday))])
    .filter(Boolean);
  const hour = String(Number(conf?.hour ?? 0)).padStart(2, '0');
  const minute = String(Number(conf?.minute ?? 0)).padStart(2, '0');
  if (!labels.length) return 'Yayın günü seçilmedi';
  return `Haftada ${labels.length} · ${labels.join(', ')} ${hour}:${minute}`;
}

async function openAddToFlowPicker({ type, root, ctx }) {
  const state = root._automationState;
  const library = Array.isArray(state?.library) ? state.library : [];
  const kind = type === 'haber' ? 'Haber' : 'Görsel';
  const pool = library
    .filter((it) => (it.type || 'gorsel') === type)
    .filter((it) => ['approved', 'failed'].includes(it.status))
    .map((it) => ({ ...it, _assetName: resolveAssetName(it) }))
    .filter((it) => it._assetName)
    .sort((a, b) => new Date(b.created_at || 0).getTime() - new Date(a.created_at || 0).getTime());

  if (!pool.length) {
    toast(`${kind} için uygun onaylı içerik bulunamadı. Önce kütüphanede onaylayın.`, 'err');
    return;
  }

  let selected = null;
  let locking = false;
  const picker = el('div', { class: 'flow-picker-grid' });
  const tiles = [];
  pool.forEach((item) => {
    const tile = el('button', {
      class: 'flow-picker-item',
      type: 'button',
      onclick: async () => {
        if (locking) return;
        locking = true;
        tile.classList.add('is-selected');
        tile.style.opacity = '0.6';
        try {
          await api.autoFillReadyItem(item._assetName);
          toast('İçerik akışa eklendi.', 'ok');
          modalCtl.close();
          await refreshFlowData(document.getElementById('automation-flow-panel'), root, ctx, { animateShift: true });
        } catch (e) {
          toast(`Ekleme başarısız: ${e.message}`, 'err');
          locking = false;
          tile.style.opacity = '';
        }
      },
    },
    item.url
      ? el('img', { src: item.url, alt: item.title || item.name, loading: 'lazy' })
      : el('div', { class: 'flow-picker-empty', html: icons.image }),
    el('div', { class: 'flow-picker-item__meta' },
      el('strong', { class: 'clamp-1' }, item.title || item.name),
      el('small', {}, fmtDate(item.created_at))));
    tiles.push(tile);
    picker.append(tile);
  });

  const body = el('div', { class: 'stack', style: 'gap:12px' },
    el('p', { class: 'muted', style: 'margin:0' },
      `${kind} akışına eklemek için bir içerik seçin (otomatik eklenir).`),
    picker);

  const footer = [
    el('button', { class: 'btn', onclick: () => modalCtl.close() }, 'Vazgeç'),
  ];

  const modalCtl = openModal({
    title: `Akışa Ekle · ${kind}`,
    body,
    footer,
    wide: true,
  });
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
    if (autoState?.config) {
      state.config = clone(autoState.config);
      // Kullanıcının kaydedilmemiş düzeni varsa sunucu kopyası onu ezmez.
      FLOW_TYPES.forEach((type) => {
        if (!laneDirty(state, type)) state.drafts[type] = clone(laneBaseline(state, type));
      });
    }
    renderFlowPanel(flowPanel, state, root, ctx, { animateShift: Boolean(options.animateShift) });
    const historyPanel = document.getElementById('automation-history-panel');
    if (historyPanel) renderHistoryPanel(historyPanel, state, ctx);
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
    const state = root._automationState;
    // Düzen şeridi akış kartının içinde olduğu için otomatik yenileme,
    // kaydedilmemiş bir düzeni veya odaklanmış bir alanı asla ezmez.
    if (state && (anyLaneDirty(state) || state.savingLanes.size)) return;
    if (document.activeElement?.closest?.('.lane-cfg')) return;
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
  root.querySelectorAll('.flow-slot__eta[data-scheduled-at]').forEach((node) => {
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

    const slotNode = node.closest('.flow-slot');
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
    const node = root.querySelector(`.flow-slot[data-entry-id="${entryId}"]`);
    node?.classList.add('is-sending');
    node?.querySelector('.flow-slot__eta')?.classList.add('is-dispatching');

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
  const node = root.querySelector(`.flow-slot[data-entry-id="${entryId}"]`);
  node?.classList.add('is-sending');
  node?.querySelector('.flow-slot__eta')?.classList.add('is-dispatching');
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
      toast('Gönderim denemesi başarısız. Ayrıntıyı Aktivite ekranında görebilirsiniz.', 'err');
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

async function openReplacePicker({ slot, type, approvedPool, root, ctx }) {
  if (!slot?.entry_id) {
    toast('Bu yayın kartı şu anda değiştirilemiyor.', 'err');
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

  let locking = false;
  const picker = el('div', { class: 'flow-picker-grid' });
  const tiles = [];
  pool.forEach((item) => {
    const tile = el('button', {
      class: 'flow-picker-item',
      type: 'button',
      onclick: async () => {
        if (locking) return;
        locking = true;
        tile.classList.add('is-selected');
        tile.style.opacity = '0.6';
        try {
          const res = await api.schedulerReplaceAsset(slot.entry_id, { asset_name: item._assetName });
          toast(res?.swapped_with
            ? 'Slot değiştirildi ve swap yapıldı.'
            : 'Slot görseli başarıyla değiştirildi.', 'ok');
          modalCtl.close();
          await refreshFlowData(document.getElementById('automation-flow-panel'), root, ctx, { animateShift: true });
        } catch (e) {
          toast(`Değiştirme başarısız: ${e.message}`, 'err');
          locking = false;
          tile.style.opacity = '';
          tile.classList.remove('is-selected');
        }
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

  const body = el('div', { class: 'stack', style: 'gap:12px' },
    el('p', { class: 'muted', style: 'margin:0' },
      'Bu yayın kartını değiştirmek için onaylanmış bir içerik seçin. İçerik başka bir aktif yayındaysa sistem yerlerini güvenle değiştirir.'),
    picker);

  const footer = [
    el('button', { class: 'btn', onclick: () => modalCtl.close() }, 'Vazgeç'),
  ];

  const modalCtl = openModal({
    title: 'Planlanan İçeriği Değiştir',
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

  // Tarih + saat göster (örn: "12 Ağu 20:00")
  return fmtDayDate(scheduledAt);
}

function fmtDayDate(iso) {
  if (!iso) return '—';
  try {
    const d = new Date(iso);
    const day = d.getDate();
    const months = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
    const month = months[d.getMonth()];
    const time = d.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });
    return `${day} ${month} ${time}`;
  } catch { return '—'; }
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

const HISTORY_PREVIEW_LIMIT = 5;

/** Yayın geçmişi — akış kartlarının altında, salt okunur arşiv. */
function renderHistoryPanel(panel, state, ctx) {
  const items = Array.isArray(state.publishes?.published) ? state.publishes.published : [];
  panel.innerHTML = '';
  panel.append(publishedList(items, state, ctx));
  panel.append(el('div', { class: 'foot-note', html:
    'Hata durumlarını <b>Aktivite</b> ekranından takip edebilirsiniz.<br>Bir yayın kartına tıklayarak içeriği güvenle değiştirebilirsiniz.' }));
}

function publishedList(items, state, ctx) {
  const expanded = Boolean(state?.historyExpanded);
  const visible = expanded ? items : items.slice(0, HISTORY_PREVIEW_LIMIT);
  const card = el('section', { class: 'card flow-history' },
    el('div', { class: 'card__head' },
      el('div', {},
        el('h3', {}, 'Yayın Geçmişi'),
        el('div', { class: 'flow-row__sub' }, 'Instagram’a gönderilmiş içerikler')),
      el('div', { class: 'hstack' },
        el('span', { class: 'badge badge--muted' }, `${items.length} yayın`),
        ctx ? el('button', {
          class: 'btn btn--sm btn--ghost',
          type: 'button',
          onclick: () => ctx.navigate('library:published'),
          html: `<span>Kütüphanede aç</span>${icons.chevron}`,
        }) : null)));

  const body = el('div', { class: 'card__body', style: 'padding-top:8px' });
  if (!items.length) {
    body.append(el('p', { class: 'muted', style: 'margin:0' },
      'Henüz yayınlanan içerik bulunmuyor. İlk otomatik gönderimden sonra burada listelenir.'));
    card.append(body);
    return card;
  }

  const list = el('div', { class: 'rowlist' });
  for (const it of visible) {
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

  if (items.length > HISTORY_PREVIEW_LIMIT && state) {
    body.append(el('div', { class: 'flow-history__more' },
      el('button', {
        class: 'btn btn--sm btn--ghost',
        type: 'button',
        onclick: () => {
          state.historyExpanded = !state.historyExpanded;
          const panel = document.getElementById('automation-history-panel');
          if (panel) renderHistoryPanel(panel, state, ctx);
        },
      }, expanded
        ? 'Daha az göster'
        : `Tüm geçmişi göster (${items.length - HISTORY_PREVIEW_LIMIT} kayıt daha)`)));
  }

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
