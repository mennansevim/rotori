// =========================================================================
// pages/logs.js — Yayın Logları
// =========================================================================
import { api, el, typeBadge, fmtDate, fmtTime, errorState, loadingState } from '../lib.js?v=20260805-8';

export async function renderLogs(root, ctx) {
  root.innerHTML = '';

  const head = el('div', { class: 'page__head' },
    el('div', {},
      el('h1', { class: 'page__title' }, 'Logs'),
      el('div', { class: 'page__subtitle' }, 'Yayın geçmişi ve son otomasyon sonuçları.')),
    el('div', { class: 'page__actions' },
      el('button', { class: 'btn btn--ghost', type: 'button', onclick: () => ctx.refresh() }, 'Yenile')));
  root.append(head);

  const body = el('div', { class: 'stack' });
  body.append(loadingState(220));
  root.append(body);

  let publishes;
  try {
    publishes = await api.publishes();
  } catch (e) {
    body.innerHTML = '';
    body.append(errorState(e.message, () => renderLogs(root, ctx)));
    return;
  }

  body.innerHTML = '';
  body.append(publishLogCard(publishes, ctx));
}

function publishLogCard(publishes, ctx) {
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
      entryId: it.entry_id || '',
      scheduledAt: it.scheduled_at || '',
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
  for (const ev of events.slice(0, 24)) {
    const retryBtn = (ev.status === 'failed' && ev.entryId)
      ? el('button', {
        class: 'btn btn--sm btn--ghost',
        type: 'button',
        onclick: async (event) => {
          const btn = event.currentTarget;
          const old = btn.textContent;
          btn.disabled = true;
          btn.textContent = 'Gönderiliyor...';
          try {
            await api.reschedule(ev.entryId, ev.scheduledAt || localIsoNoTz(Date.now() - 1000));
            const result = await api.schedulerRunNow();
            const items = Array.isArray(result?.items) ? result.items : [];
            const hit = items.find((it) => it.id === ev.entryId);
            if (hit?.status === 'done') {
              btn.textContent = 'Gönderildi';
            } else if (hit?.status === 'failed') {
              btn.textContent = 'Tekrar Dene';
            } else {
              btn.textContent = 'İşlendi';
            }
            ctx.refresh();
          } catch {
            btn.textContent = old || 'Tekrar Dene';
            btn.disabled = false;
          }
        },
      }, 'Şimdi Gönder')
      : el('div', { class: 'rowitem__cd muted', style: 'font-size:11px' }, 'Log');

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
      retryBtn));
  }
  body.append(list);
  card.append(body);
  return card;
}

function localIsoNoTz(ms) {
  const d = new Date(ms);
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
    + `T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

function statusToneFromOutcome(outcome) {
  if (outcome === 'success') return 'ok';
  if (outcome === 'failed') return 'danger';
  if (outcome === 'overdue' || outcome === 'manual' || outcome === 'publishing') return 'warn';
  return 'muted';
}
