// =========================================================================
// modals.js — İçerik önizleme + düzenleme + görseli yeniden oluştur
// =========================================================================
import { api, el, icons, typeBadge, statusBadge, esc, countdownText, fmtDate,
         fmtTime, openModal, confirmModal, toast } from './lib.js?v=20260810-8';

/**
 * İçerik önizleme + düzenleme modalı.
 * it: kütüphane/overview öğesi (name, url, type, status, title, aciklama,
 *     post_caption, ust_tag, scheduled_at ...)
 * ctx: { refresh, navigate, serverNow }
 */
export function openContentModal(it, ctx) {
  const isPending = it.status === 'pending_approval';
  const isDraft = it.status === 'draft';
  const canApprove = isPending || isDraft;
  const canPublish = ['approved', 'queued', 'scheduled', 'failed'].includes(it.status);

  // Düzenlenebilir alanlar (gerçek backend: aciklama + post_caption + ust_tag)
  const acikInput = el('textarea', { class: 'textarea', id: 'm-acik', maxlength: '280' }, it.aciklama || '');
  const capInput = el('textarea', { class: 'textarea', id: 'm-cap', style: 'min-height:120px' }, it.post_caption || '');
  const tagInput = el('input', { class: 'input', id: 'm-tag', value: it.ust_tag || 'GEZİ DEFTERİ' });
  let dirty = false;
  [acikInput, capInput, tagInput].forEach((n) => n.addEventListener('input', () => { dirty = true; }));

  const previewImg = el('img', { src: it.url, alt: it.title });

  const body = el('div', { class: 'grid-2', style: 'gap:24px' },
    // Sol: önizleme
    el('div', {},
      el('div', { class: 'ig-preview' },
        el('div', { class: 'ig-preview__head' },
          el('div', { class: 'ig-preview__avatar' }, 'JR'),
          el('div', {},
            el('div', { class: 'ig-preview__name' }, 'Japonya Rüyası'),
            el('div', { class: 'ig-preview__handle' }, '@japonyaruyasi'))),
        el('div', { class: 'ig-preview__img' }, previewImg)),
      el('div', { class: 'hstack', style: 'margin-top:12px;flex-wrap:wrap' },
        el('span', { html: typeBadge(it.type) }),
        el('span', { html: statusBadge(it.status) }),
        it.scheduled_at ? el('span', { class: 'muted', style: 'font-size:12px' },
          `${fmtDate(it.scheduled_at)} · ${fmtTime(it.scheduled_at)}`) : null)),
    // Sağ: düzenleme
    el('div', {},
      el('div', { class: 'field' },
        el('label', { class: 'field__label', for: 'm-tag' }, 'Üst Etiket'),
        tagInput),
      el('div', { class: 'field' },
        el('label', { class: 'field__label', for: 'm-acik' }, 'Kart Açıklaması'),
        acikInput),
      el('div', { class: 'field' },
        el('label', { class: 'field__label', for: 'm-cap' }, 'Instagram Caption'),
        capInput)));

  // Aksiyonlar
  const footer = [];
  footer.push(el('button', { class: 'btn', onclick: () => regenerate(it, ctx, previewImg) },
    el('span', { html: icons.refresh }), 'Görseli Yenile'));
  footer.push(el('span', { class: 'spacer', style: 'flex:1' }));

  const saveBtn = el('button', { class: 'btn btn--primary', onclick: () => save() },
    el('span', { html: icons.check }), 'Kaydet');
  footer.push(saveBtn);

  if (canApprove) {
    footer.push(el('button', { class: 'btn btn--ok', onclick: () => approve() },
      el('span', { html: icons.check }), 'Onayla'));
  }
  if (canPublish) {
    footer.push(el('button', { class: 'btn btn--accent', onclick: () => publishNow() },
      el('span', { html: icons.send }), 'Yayınla'));
  }

  const ctl = openModal({
    title: it.title, body, footer, wide: true,
    onClose: async () => {
      if (dirty) {
        // Kullanıcı kaydetmeden kapatıyorsa uyar
        const ok = await confirmModal({ title: 'Kaydedilmemiş değişiklik', message: 'Değişiklikler kaydedilmedi. Yine de kapatılsın mı?', confirmLabel: 'Kapat' });
        if (ok) ctx.refresh();
      }
    },
  });

  async function save() {
    const body = {
      aciklama: acikInput.value.trim(),
      post_caption: capInput.value.trim(),
      ust_tag: tagInput.value.trim() || 'GEZİ DEFTERİ',
    };
    saveBtn.disabled = true;
    try {
      if (isPending) await api.approvalUpdate(it.name, body);
      else await api.storyUpdate(it.name, body);
      dirty = false;
      toast('Değişiklikler kaydedildi.', 'ok');
      previewImg.src = it.url + '?t=' + Date.now(); // render güncellenmişse tazele
    } catch (e) { toast(e.message, 'err'); }
    finally { saveBtn.disabled = false; }
  }

  async function approve() {
    if (dirty) await save();
    try {
      await api.approvalMarkReady(it.name);
      toast('İçerik yayına hazır sırasına alındı.', 'ok');
      ctl.close(); ctx.refresh();
    } catch (e) { toast(e.message, 'err'); }
  }

  async function publishNow() {
    if (!(await confirmModal({ title: 'Şimdi yayınla', message: `"${it.title}" Instagram'da hemen yayınlanacak.`, confirmLabel: 'Yayınla' }))) return;
    try {
      await api.publish(it.name);
      toast('Yayın işlemi başlatıldı.', 'ok');
      ctl.close(); ctx.refresh();
    } catch (e) { toast(e.message, 'err'); }
  }
}

async function regenerate(it, ctx, imgNode) {
  if (!(await confirmModal({ title: 'Görseli yeniden oluştur', message: 'Kart görseli yeniden üretilecek. Metin alanları korunur. Devam edilsin mi?', confirmLabel: 'Yeniden Oluştur' }))) return;
  toast('Görsel yeniden oluşturuluyor…');
  try {
    // Kartın metnini koruyarak sadece görseli yenile: update endpoint aciklama
    // aynı kaldığında kartı mevcut bg ile yeniden render eder.
    const body = { aciklama: it.aciklama || '', post_caption: it.post_caption || '', ust_tag: it.ust_tag || 'GEZİ DEFTERİ' };
    if (it.status === 'pending_approval') await api.approvalUpdate(it.name, body);
    else await api.storyUpdate(it.name, body);
    if (imgNode) imgNode.src = it.url + '?t=' + Date.now();
    toast('Görsel güncellendi.', 'ok');
    return true;
  } catch (e) {
    toast('Görsel yenilenemedi, mevcut görsel korundu: ' + e.message, 'err');
    return false;
  }
}

export { regenerate };
