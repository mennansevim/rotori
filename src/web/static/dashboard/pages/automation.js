// =========================================================================
// pages/automation.js — Otomasyon (yayın slotları)
// =========================================================================
import { api, el, icons, typeBadge, countdownText, fmtDate, fmtTime,
         errorState, loadingState, toast } from '../lib.js?v=20260804-7';

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
  try { data = await api.automationState(); }
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
  return el('div', { class: `tl-item ${it.type}` },
    media,
    el('div', { class: 'tl-item__body' },
      el('div', { class: 'tl-item__time' }, el('span', { class: `tl-item__dot ${it.type}` }), it.time),
      el('div', { class: 'tl-item__title' }, it.title)));
}

function nextCard(next, now) {
  const box = el('div', { class: 'card' },
    el('div', { class: 'card__head' }, el('h3', {}, 'Sıradaki Yayın')));
  if (!next) {
    box.append(el('div', { class: 'card__body' }, el('p', { class: 'muted' }, 'Yayına hazır içerik bulunmuyor.')));
    return box;
  }
  box.append(el('div', { class: 'card__body' },
    el('div', { class: 'hstack', style: 'margin-bottom:12px' },
      el('span', { class: `slot-card__icon ${next.type}`, html: next.type === 'haber' ? icons.news : icons.image }),
      el('span', { html: typeBadge(next.type) })),
    el('div', { style: 'font-family:var(--serif);font-size:18px' }, next.title),
    el('div', { class: 'muted', style: 'font-size:12.5px;margin-top:6px' },
      `${fmtDate(next.scheduled_at)} · ${fmtTime(next.scheduled_at)}`),
    el('div', { class: 'divider' }),
    el('div', { class: 'metric__label' }, 'Yayına Kalan Süre'),
    el('div', { style: 'font-family:var(--serif);font-size:22px;color:var(--type-gorsel);margin-top:4px' },
      countdownText(next.scheduled_at, now)),
    el('div', { class: 'muted', style: 'font-size:11.5px;margin-top:4px' }, 'Otomatik olarak yayınlanacak')));
  return box;
}
