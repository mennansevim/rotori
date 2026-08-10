// =========================================================================
// pages/overview.js — Demo kullanıcı için güvenli, karar odaklı ana sayfa
// =========================================================================
import { api, el, icons, fmtDate, fmtTime, typeBadge,
         errorState, loadingState } from '../lib.js?v=20260810-7';
import { openCreateModal } from './create.js?v=20260810-7';

export async function renderOverview(root, ctx) {
  root.innerHTML = '';
  const body = el('div', { class: 'overview-shell' }, loadingState(320));
  root.append(body);

  let overview;
  let library;
  let publishes;
  try {
    [overview, library, publishes] = await Promise.all([
      api.overview(), api.library(), api.publishes(),
    ]);
  } catch (error) {
    body.innerHTML = '';
    body.append(errorState(error.message, () => renderOverview(root, ctx)));
    return;
  }

  const items = Array.isArray(library?.items) ? library.items : [];
  const drafts = items.filter((item) => ['draft', 'pending_approval'].includes(item.status));
  const approved = items.filter((item) => ['approved', 'queued', 'scheduled', 'publishing', 'failed'].includes(item.status));
  const published = items.filter((item) => item.status === 'published');
  const failed = (publishes?.upcoming || []).filter((item) => item.status === 'failed');
  const next = overview?.next_publish;

  body.innerHTML = '';
  body.append(
    welcomeHeader(overview, ctx),
    actionStrip(drafts, approved, published, ctx),
    el('div', { class: 'overview-grid' },
      nextPublishCard(next, ctx),
      attentionCard(drafts, failed, ctx)),
    weeklyPlan(overview?.timeline, ctx),
  );
}

function welcomeHeader(overview, ctx) {
  const hour = new Date(overview?.now || Date.now()).getHours();
  const greeting = hour < 12 ? 'Günaydın' : hour < 18 ? 'İyi günler' : 'İyi akşamlar';
  return el('header', { class: 'overview-welcome' },
    el('div', {},
      el('div', { class: 'overview-welcome__eyebrow' }, overview?.now ? fmtDate(overview.now) : 'Bugün'),
      el('h1', {}, `${greeting}, Japonya Rüyası`),
      el('p', {}, 'Bugün neye odaklanmanız gerektiğini tek ekranda görün.')),
    el('button', {
      class: 'btn btn--primary overview-welcome__action',
      onclick: () => openCreateModal(ctx, 'gorsel'),
      html: icons.plus + '<span>Yeni içerik oluştur</span>',
    }));
}

function actionStrip(drafts, approved, published, ctx) {
  const stages = [
    { key: 'draft', step: '1', label: 'Taslak', value: drafts.length, hint: 'İncele ve onayla', icon: icons.draft, tone: 'amber' },
    { key: 'approved', step: '2', label: 'Onaylandı', value: approved.length, hint: 'Planla veya akışta gör', icon: icons.check, tone: 'indigo' },
    { key: 'published', step: '3', label: 'Yayınlandı', value: published.length, hint: 'Yayın arşivini aç', icon: icons.send, tone: 'green' },
  ];
  return el('section', { class: 'overview-stages', 'aria-label': 'İçerik yaşam döngüsü' },
    stages.map((stage) => el('button', {
      class: `overview-stage overview-stage--${stage.tone}`,
      onclick: () => ctx.navigate(`library:${stage.key}`),
    },
    el('span', { class: 'overview-stage__step' }, stage.step),
    el('span', { class: 'overview-stage__icon', html: stage.icon }),
    el('span', { class: 'overview-stage__copy' },
      el('strong', {}, stage.label), el('small', {}, stage.hint)),
    el('b', {}, stage.value),
    el('span', { class: 'overview-stage__arrow', html: icons.chevron }))));
}

function nextPublishCard(next, ctx) {
  const card = el('section', { class: 'card overview-next' },
    el('div', { class: 'overview-panel-head' },
      el('div', {}, el('span', { class: 'overview-panel-kicker' }, 'Sıradaki adım'), el('h2', {}, 'Sıradaki yayın')),
      el('button', { class: 'btn btn--ghost btn--sm', onclick: () => ctx.navigate('automation'), html: 'Planı aç ' + icons.chevron })));
  if (!next) {
    card.append(el('div', { class: 'overview-empty' },
      el('span', { html: icons.calendar }),
      el('strong', {}, 'Planlanmış yayın yok'),
      el('p', {}, 'Onaylanan bir içeriği otomasyona eklediğinizde burada görünür.'),
      el('button', { class: 'btn', onclick: () => ctx.navigate('library:approved') }, 'Onaylananları aç')));
    return card;
  }
  card.append(el('div', { class: 'overview-next__body' },
    next.url
      ? el('img', { src: next.url, alt: next.title, loading: 'lazy' })
      : el('div', { class: 'overview-next__placeholder', html: icons.image }),
    el('div', { class: 'overview-next__copy' },
      el('span', { html: typeBadge(next.type) }),
      el('h3', {}, next.title),
      el('p', {}, `${fmtDate(next.scheduled_at)} · ${fmtTime(next.scheduled_at)}`),
      el('strong', {}, next.countdown || 'Gönderim hazırlanıyor'),
      next.failure_reason
        ? el('span', { class: 'overview-next__warning' }, friendlyFailure(next.failure_reason))
        : null)));
  return card;
}

function attentionCard(drafts, failed, ctx) {
  const rows = [
    {
      icon: icons.draft,
      tone: 'amber',
      value: drafts.length,
      title: 'İncelenecek taslak',
      hint: drafts.length ? 'İçerikleri kontrol edip onaylayın.' : 'Bekleyen taslak yok.',
      action: () => ctx.navigate('library:draft'),
    },
    {
      icon: icons.x,
      tone: failed.length ? 'red' : 'green',
      value: failed.length,
      title: 'Dikkat gereken yayın',
      hint: failed.length ? 'Başarısız denemeleri inceleyin.' : 'Yayın akışı sağlıklı.',
      action: () => ctx.navigate('logs'),
    },
  ];
  return el('section', { class: 'card overview-attention' },
    el('div', { class: 'overview-panel-head' },
      el('div', {}, el('span', { class: 'overview-panel-kicker' }, 'Kontrol listesi'), el('h2', {}, 'Bugün dikkat edin'))),
    el('div', { class: 'overview-attention__list' }, rows.map((row) => el('button', {
      class: 'overview-attention__row', onclick: row.action,
    },
    el('span', { class: `overview-attention__icon is-${row.tone}`, html: row.icon }),
    el('span', { class: 'overview-attention__copy' }, el('strong', {}, row.title), el('small', {}, row.hint)),
    el('b', {}, row.value),
    el('span', { html: icons.chevron })))));
}

function weeklyPlan(timeline, ctx) {
  const days = Array.isArray(timeline?.days) ? timeline.days : [];
  return el('section', { class: 'card overview-week' },
    el('div', { class: 'overview-panel-head' },
      el('div', {}, el('span', { class: 'overview-panel-kicker' }, 'Europe/Istanbul'), el('h2', {}, 'Bu haftanın yayın planı')),
      el('button', { class: 'btn btn--ghost btn--sm', onclick: () => ctx.navigate('automation'), html: 'Otomasyonu aç ' + icons.chevron })),
    el('div', { class: 'overview-week__days' }, days.map((day) => el('div', { class: `overview-day ${day.is_today ? 'is-today' : ''}` },
      el('div', { class: 'overview-day__head' }, el('strong', {}, day.day_name), el('small', {}, shortDate(day.date))),
      day.items?.length
        ? el('div', { class: 'overview-day__items' }, day.items.slice(0, 2).map((item) => el('div', { class: `overview-day__item is-${item.type}` },
          el('time', {}, item.time), el('span', { class: 'clamp-1' }, item.title))))
        : el('span', { class: 'overview-day__empty' }, 'Boş')))));
}

function shortDate(value) {
  if (!value) return '';
  try {
    return new Date(`${value}T00:00:00`).toLocaleDateString('tr-TR', { day: 'numeric', month: 'short' });
  } catch { return value; }
}

function friendlyFailure(reason) {
  const text = String(reason || '').toLocaleLowerCase('tr-TR');
  if (text.includes('public url') || text.includes('http 404')) return 'Görsel erişimi kontrol edilmeli.';
  return 'Yayın ayrıntısı kontrol edilmeli.';
}
