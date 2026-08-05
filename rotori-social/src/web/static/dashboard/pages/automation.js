// =========================================================================
// pages/automation.js — Otomasyon (yayın slotları)
// =========================================================================
import { api, el, icons, typeBadge, countdownText, fmtDate, fmtTime,
         errorState, loadingState, toast, openModal } from '../lib.js?v=20260804-7';

const DAYS = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];  // launchd: 1..6,0
const DAY_TO_LAUNCHD = [1, 2, 3, 4, 5, 6, 0];  // index → launchd weekday

export async function renderAutomation(root, ctx) {
  root.innerHTML = '';
  const head = el('div', { class: 'page__head' },
    el('div', {},
      el('h1', { class: 'page__title' }, 'Otomasyon'),
      el('div', { class: 'page__subtitle' }, 'Onaylanan içerikler planlanan gün ve saatlerde otomatik yayınlanır.')),
    el('div', { class: 'page__actions' },
      el('button', { class: 'btn btn--primary', id: 'auto-save', onclick: () => save(), html: icons.check + '<span>Ayarları Kaydet</span>' })));
  root.append(head);

  const body = el('div', { class: 'stack' });
  body.append(loadingState(220));
  root.append(body);

  let data;
  let publishes;
  try {
    [data, publishes] = await Promise.all([
      api.automationState(),
      api.publishes(),
    ]);
  }
  catch (e) { body.innerHTML = ''; body.append(errorState(e.message, () => renderAutomation(root, ctx))); return; }

  // yerel düzenlenebilir kopya
  const cfg = JSON.parse(JSON.stringify(data.config));

  body.innerHTML = '';
  const slots = el('div', { class: 'grid-2' },
    slotCard('haber', 'Haber Slotu', 'Haber tipindeki içerikler otomatik yayınlanır.', cfg.news),
    slotCard('gorsel', 'Görsel Slotu', 'Görsel tipindeki içerikler otomatik yayınlanır.', cfg.topic));
  body.append(slots);

  // Bu hafta akışı + sıradaki
  const flow = el('div', { class: 'grid-2', style: 'grid-template-columns:1.6fr 1fr' });
  flow.append(weekFlow(data.timeline), nextCard(data.next_publish, data.timeline.now));
  body.append(flow);

  body.append(publishedList((publishes?.published || []).slice(0, 5)));
  body.append(publishLogCard(publishes));

  body.append(el('div', { class: 'foot-note', html:
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
