// =========================================================================
// pages/settings.js — Hesap ve güvenli sistem ayarları
// =========================================================================
import { api, el, icons, errorState, loadingState, toast, confirmModal } from '../lib.js?v=20260810-6';

export async function renderSettings(root, ctx) {
  root.innerHTML = '';
  root.append(el('div', { class: 'page__head settings-head' },
    el('div', {},
      el('div', { class: 'eyebrow' }, 'Hesap ve çalışma alanı'),
      el('h1', { class: 'page__title' }, 'Ayarlar'),
      el('div', { class: 'page__subtitle' }, 'Bağlantı durumunu ve yayın düzenini tek yerden kontrol edin.'))));

  const body = el('div', { class: 'settings-shell' }, loadingState(180));
  root.append(body);

  let ig;
  let graph;
  let automation;
  try {
    [ig, graph, automation] = await Promise.all([
      api.instagramStatus(),
      api.get('/api/instagram/graph_status').catch(() => ({})),
      api.automationConfigGet().catch(() => ({})),
    ]);
  } catch (error) {
    body.innerHTML = '';
    body.append(errorState(error.message, () => renderSettings(root, ctx)));
    return;
  }

  const connected = Boolean(ig?.enabled);
  const graphOk = Boolean(graph?.ok || graph?.valid || graph?.is_valid);
  const username = ig?.username ? `@${ig.username}` : '@japonyaruyasi';
  const activeFlows = [automation?.news?.enabled, automation?.topic?.enabled].filter(Boolean).length;

  body.innerHTML = '';
  body.append(
    el('section', { class: 'card settings-account-card' },
      el('div', { class: 'settings-account-card__main' },
        el('div', { class: 'settings-account-card__avatar' }, 'JR'),
        el('div', {},
          el('span', { class: 'settings-account-card__label' }, 'Instagram hesabı'),
          el('h2', {}, username),
          el('p', {}, connected
            ? (graphOk ? 'Bağlantı sağlıklı · Yayınlamaya hazır' : 'Hesap bağlı · Yayın bağlantısı kontrol ediliyor')
            : 'Instagram bağlantısı kurulmamış'))),
      el('div', { class: 'settings-account-card__status' },
        el('span', { class: `settings-status-dot ${connected ? 'is-on' : ''}` }),
        el('strong', {}, connected ? 'Bağlı' : 'Bağlantı yok'),
        el('button', { class: 'btn btn--ghost btn--sm', onclick: () => refreshConnection(), html: icons.refresh + '<span>Durumu yenile</span>' }))),
    el('div', { class: 'settings-grid' },
      infoCard('Yayın düzeni', icons.calendar,
        activeFlows ? `${activeFlows} otomatik akış etkin` : 'Otomatik akışlar kapalı',
        'Yayın günlerini ve saatlerini Otomasyon ekranından değiştirebilirsiniz.',
        'Yayın düzenini aç', () => ctx.navigate('automation:settings')),
      infoCard('Saat dilimi', icons.clock,
        'Europe/Istanbul · GMT+03:00',
        'Tüm planlama ve geri sayımlar bu saat dilimine göre hesaplanır.'),
      infoCard('Yayın bağlantısı', icons.link,
        graphOk ? 'Instagram yayın servisi hazır' : 'Bağlantı doğrulaması gerekli',
        graphOk
          ? 'Kartlar planlanan zamanda güvenli yayın akışına gönderilir.'
          : 'Bağlantı ayrıntısını yenileyip tekrar kontrol edin.'),
      infoCard('İçerik çalışma alanı', icons.library,
        'Japonya Rüyası',
        'Taslak, onay ve yayın geçmişi aynı çalışma alanında tutulur.',
        'Kütüphaneyi aç', () => ctx.navigate('library'))),
    el('details', { class: 'settings-danger' },
      el('summary', {}, 'Gelişmiş hesap işlemleri'),
      el('div', { class: 'settings-danger__body' },
        el('div', {}, el('strong', {}, 'Instagram bağlantısını kes'),
          el('p', {}, 'Otomatik yayın durur; mevcut içerikler ve yayın geçmişi silinmez.')),
        el('button', { class: 'btn btn--danger', onclick: () => disconnect() }, 'Bağlantıyı kes'))),
  );

  async function refreshConnection() {
    try {
      await api.instagramStatus();
      toast('Bağlantı durumu yenilendi.', 'ok');
      renderSettings(root, ctx);
    } catch (error) { toast(error.message, 'err'); }
  }

  async function disconnect() {
    const confirmed = await confirmModal({
      title: 'Instagram bağlantısını kes',
      message: `${username} hesabının yayın bağlantısı kapatılacak. İçerikler silinmez.`,
      confirmLabel: 'Bağlantıyı kes',
      danger: true,
    });
    if (!confirmed) return;
    try {
      await api.post('/api/instagram/logout');
      toast('Instagram bağlantısı kesildi.', 'ok');
      renderSettings(root, ctx);
    } catch (error) { toast(error.message, 'err'); }
  }
}

function infoCard(title, icon, value, description, actionLabel, action) {
  const card = el('section', { class: 'card settings-info-card' },
    el('span', { class: 'settings-info-card__icon', html: icon }),
    el('div', { class: 'settings-info-card__copy' },
      el('span', {}, title), el('strong', {}, value), el('p', {}, description)));
  if (actionLabel && action) {
    card.append(el('button', { class: 'btn btn--ghost btn--sm', onclick: action, html: `${actionLabel} ${icons.chevron}` }));
  }
  return card;
}
