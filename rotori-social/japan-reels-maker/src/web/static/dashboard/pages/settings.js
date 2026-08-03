// =========================================================================
// pages/settings.js — Ayarlar
// =========================================================================
import { api, el, icons, errorState, loadingState, toast } from '../lib.js';

export async function renderSettings(root, ctx) {
  root.innerHTML = '';
  const head = el('div', { class: 'page__head' },
    el('div', {},
      el('h1', { class: 'page__title' }, 'Ayarlar'),
      el('div', { class: 'page__subtitle' }, 'Instagram hesabı ve genel yayın tercihleri.')));
  root.append(head);

  const body = el('div', { class: 'stack' });
  body.append(loadingState(120));
  root.append(body);

  let ig, graph;
  try {
    [ig, graph] = await Promise.all([
      api.instagramStatus(),
      api.get('/api/instagram/graph_status').catch(() => ({})),
    ]);
  } catch (e) { body.innerHTML = ''; body.append(errorState(e.message, () => renderSettings(root, ctx))); return; }

  body.innerHTML = '';
  const connected = !!(ig && ig.enabled);
  const graphOk = !!(graph && (graph.ok || graph.valid || graph.is_valid));

  // Instagram hesabı
  body.append(el('div', { class: 'card' },
    el('div', { class: 'card__head' }, el('h3', {}, 'Instagram Hesabı')),
    el('div', { class: 'card__body' },
      el('div', { class: 'hstack', style: 'justify-content:space-between' },
        el('div', { class: 'hstack' },
          el('div', { class: 'account__avatar', style: 'width:44px;height:44px;border-radius:8px' }, 'JR'),
          el('div', {},
            el('div', { style: 'font-weight:700;font-size:15px' }, ig.username ? '@' + ig.username : '@japonyaruyasi'),
            el('div', { class: 'hstack', style: 'gap:6px;margin-top:2px' },
              el('span', { class: `dot ${connected ? 'is-on' : 'is-off'}` }),
              el('span', { class: 'muted', style: 'font-size:12px' },
                connected ? (graphOk ? 'Bağlı · Graph API aktif' : 'Bağlı') : 'Bağlantı yok')))),
        el('div', { class: 'hstack' },
          el('button', { class: 'btn', onclick: () => refreshConn(), html: icons.refresh + '<span>Bağlantıyı Yenile</span>' }),
          el('button', { class: 'btn btn--danger', onclick: () => disconnect() }, 'Bağlantıyı Kes'))),
      el('div', { class: 'divider' }),
      el('p', { class: 'muted', style: 'font-size:12.5px;margin:0' },
        'Yayınlama için Instagram Graph API (Business Login) kullanılır. Token ve public URL ayarları config.yaml üzerinden yönetilir.'))));

  // Genel
  const tzSelect = el('select', { class: 'select' },
    el('option', { value: 'Europe/Istanbul', selected: '' }, 'Europe/Istanbul (GMT+03:00)'));
  const defaultBehavior = el('select', { class: 'select' },
    el('option', { value: 'manual' }, 'Onaydan sonra sıraya al (manuel yayın)'),
    el('option', { value: 'auto' }, 'Slot zamanında otomatik yayınla'));

  body.append(el('div', { class: 'card' },
    el('div', { class: 'card__head' }, el('h3', {}, 'Genel')),
    el('div', { class: 'card__body' },
      el('div', { class: 'field' }, el('label', { class: 'field__label' }, 'Saat Dilimi'), tzSelect),
      el('div', { class: 'field', style: 'margin-bottom:0' },
        el('label', { class: 'field__label' }, 'Varsayılan Yayın Davranışı'), defaultBehavior),
      el('p', { class: 'muted', style: 'font-size:11.5px;margin:14px 0 0' },
        'Tüm planlama hesaplamaları Europe/Istanbul saat dilimine göre yapılır.'))));

  async function refreshConn() {
    try { await api.instagramStatus(); toast('Bağlantı durumu yenilendi.', 'ok'); renderSettings(root, ctx); }
    catch (e) { toast(e.message, 'err'); }
  }
  async function disconnect() {
    const { confirmModal } = await import('../lib.js');
    if (!(await confirmModal({ title: 'Bağlantıyı kes', message: 'Instagram oturumu sonlandırılacak.', confirmLabel: 'Bağlantıyı Kes', danger: true }))) return;
    try { await api.post('/api/instagram/logout'); toast('Bağlantı kesildi.', 'ok'); renderSettings(root, ctx); }
    catch (e) { toast(e.message, 'err'); }
  }
}
