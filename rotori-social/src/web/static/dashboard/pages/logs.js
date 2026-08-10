// =========================================================================
// pages/logs.js — Yayın Logları
// =========================================================================
import { api, el, typeBadge, fmtDate, fmtTime, errorState, loadingState,
         emptyState, icons, toast, confirmModal } from '../lib.js?v=20260810-7';

export async function renderLogs(root, ctx) {
  root.innerHTML = '';

  const head = el('div', { class: 'page__head' },
    el('div', {},
      el('div', { class: 'eyebrow' }, 'Yayın sağlığı'),
      el('h1', { class: 'page__title' }, 'Aktivite'),
      el('div', { class: 'page__subtitle' }, 'Yayın sonuçlarını görün, dikkat gereken denemeleri güvenle yönetin.')),
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
  const upcoming = Array.isArray(publishes?.upcoming) ? publishes.upcoming : [];
  const published = Array.isArray(publishes?.published) ? publishes.published : [];
  const failed = upcoming.filter((item) => normalizeLogStatus(item.publish_outcome || item.status) === 'failed');
  body.append(el('div', { class: 'activity-summary' },
    activityStat('green', icons.check, published.length, 'Başarılı yayın'),
    activityStat(failed.length ? 'red' : 'green', failed.length ? icons.x : icons.check, failed.length, 'Dikkat gereken'),
    activityStat('indigo', icons.calendar, upcoming.length, 'Planlanan yayın')));
  body.append(publishLogCard(publishes, ctx));
}

function activityStat(tone, icon, value, label) {
  return el('div', { class: `activity-stat is-${tone}` },
    el('span', { html: icon }), el('div', {}, el('b', {}, value), el('small', {}, label)));
}

function publishLogCard(publishes, ctx) {
  const card = el('div', { class: 'card' },
    el('div', { class: 'card__head' },
      el('h3', {}, 'Son yayın hareketleri'),
      el('span', { class: 'badge badge--muted' }, 'En yeni önce')));

  const body = el('div', { class: 'card__body', style: 'padding-top:8px' });
  const upcoming = Array.isArray(publishes?.upcoming) ? publishes.upcoming : [];
  const published = Array.isArray(publishes?.published) ? publishes.published : [];

  const events = [];
  for (const it of upcoming) {
    const status = normalizeLogStatus(it.publish_outcome || it.status);
    const hasMeaningfulLog = ['failed', 'manual', 'overdue', 'publishing'].includes(status)
      || Boolean(it.last_attempt_at || it.last_result_at || it.failure_reason);
    if (!hasMeaningfulLog) continue;

    const ts = Date.parse(it.last_result_at || it.last_attempt_at || it.scheduled_at || '') || 0;
    const details = [`Plan: ${fmtDate(it.scheduled_at)} · ${fmtTime(it.scheduled_at)}`];
    if (it.last_attempt_at) details.push(`Son deneme: ${fmtDate(it.last_attempt_at)} · ${fmtTime(it.last_attempt_at)}`);
    const rawReason = it.failure_reason || '';
    events.push({
      ts,
      entryId: it.entry_id || '',
      scheduledAt: it.scheduled_at || '',
      title: it.title || 'Planlı yayın',
      type: it.type || 'gorsel',
      url: it.url,
      status,
      statusLabel: it.publish_outcome_tr || it.status_tr || 'Planlandı',
      details: details.join(' · '),
      friendlyReason: friendlyFailure(rawReason),
      rawReason,
      canRetry: status === 'failed' || status === 'overdue' || status === 'manual',
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
    body.append(emptyState(icons.file,
      'Henüz yayın deneme logu yok.',
      'Planlanan kartlar log ekranına düşmez. Yayın denemesi yapıldığında burada listelenir.'));
    card.append(body);
    return card;
  }

  const list = el('div', { class: 'rowlist' });
  for (const ev of events.slice(0, 24)) {
    const retryBtn = (ev.canRetry && ev.entryId)
      ? el('button', {
        class: 'btn btn--sm btn--ghost',
        type: 'button',
        onclick: async (event) => {
          const confirmed = await confirmModal({
            title: 'Yayını tekrar dene',
            message: `“${ev.title}” şimdi yeniden yayınlanmayı deneyecek.`,
            confirmLabel: 'Tekrar dene',
          });
          if (!confirmed) return;
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
              toast('Yayın denemesi başarılı.', 'ok');
              btn.textContent = 'Gönderildi';
            } else if (hit?.status === 'failed') {
              toast('Yayın denemesi tekrar başarısız oldu.', 'err');
              btn.textContent = 'Tekrar Dene';
            } else {
              toast('Yayın denemesi işlendi.', 'ok');
              btn.textContent = 'İşlendi';
            }
            ctx.refresh();
          } catch (err) {
            toast(err?.message || 'Yeniden deneme başlatılamadı.', 'err');
            btn.textContent = old || 'Tekrar Dene';
            btn.disabled = false;
          }
        },
      }, 'Tekrar dene')
      : el('div', { class: 'rowitem__cd muted', style: 'font-size:11px' }, 'Tamamlandı');

    const detailLine = el('div', { class: 'activity-row__details' },
      el('span', {}, ev.details));
    if (ev.friendlyReason) detailLine.append(el('strong', {}, ev.friendlyReason));
    if (ev.rawReason) detailLine.append(el('details', { class: 'activity-tech-detail' },
      el('summary', {}, 'Teknik ayrıntı'), el('code', {}, ev.rawReason)));

    list.append(el('div', { class: 'rowitem' },
      ev.url
        ? el('img', { class: 'rowitem__thumb', src: ev.url, alt: ev.title || '', loading: 'lazy' })
        : el('div', { class: 'rowitem__thumb' }),
      el('div', { class: 'rowitem__main' },
        el('div', { class: 'rowitem__title' }, ev.title),
        el('div', { class: 'rowitem__sub' },
          el('span', { html: typeBadge(ev.type) }),
          el('span', { class: `badge badge--${statusToneFromOutcome(ev.status)}` }, ev.statusLabel)),
        detailLine),
      retryBtn));
  }
  body.append(list);
  card.append(body);
  return card;
}

function friendlyFailure(reason) {
  if (!reason) return '';
  const value = String(reason).toLocaleLowerCase('tr-TR');
  if (value.includes('public url') || value.includes('http 404')) {
    return 'Görsel internete açılamadı. Dosya bağlantısını kontrol edip yeniden deneyin.';
  }
  if (value.includes('raise_for_status') || value.includes('stubresp')) {
    return 'Yayın servisi yanıtı tamamlayamadı. Yeniden deneyebilirsiniz.';
  }
  if (value.includes('token') || value.includes('oauth')) {
    return 'Instagram bağlantısının yenilenmesi gerekiyor.';
  }
  return 'Yayın denemesi tamamlanamadı. Teknik ayrıntıyı gerektiğinde açabilirsiniz.';
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

function normalizeLogStatus(status) {
  if (status === 'success') return 'success';
  if (status === 'failed') return 'failed';
  if (status === 'overdue') return 'overdue';
  if (status === 'manual') return 'manual';
  if (status === 'publishing' || status === 'uploading') return 'publishing';
  if (status === 'pending' || status === 'scheduled' || status === 'queued' || status === 'approved' || status === 'ready') return 'scheduled';
  return 'scheduled';
}
