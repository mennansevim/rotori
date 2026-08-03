// =========================================================================
// pages/create.js — İçerik Üret (Görsel / Haber)
// Orijinal studio wizard mimarisi popup (modal) içinde birebir korunur.
//   Görsel Üret : 3 adım — Konu → Görsel seç → Metin + Kartı oluştur
//   Haber Üret  : RSS pipeline + otomatik yayın toggle
// =========================================================================
import { api, el, icons, toast, openModal } from '../lib.js';
import { openGenOverlay, setGenStages, genAppendLog, finishGenOverlay, pollJobUntilDone, closeGenOverlay } from '../genoverlay.js';

// -------------------------------------------------------------------------
// Popup: iki üretim modunu sekmeli modal içinde açar.
// -------------------------------------------------------------------------
export function openCreateModal(ctx, tab = 'gorsel') {
  let ctl;
  const done = () => { ctl && ctl.close(); };

  const content = el('div', { class: 'create-modal__content' });
  const tabbar = el('div', { class: 'tabbar' });
  const swap = (t) => {
    tabbar.querySelectorAll('.tab').forEach((b) => b.classList.toggle('is-active', b.dataset.t === t));
    content.innerHTML = '';
    content.append(t === 'haber' ? buildHaber(ctx, done) : buildGorsel(ctx, done));
  };
  for (const [t, label] of [['gorsel', 'Görsel Üret'], ['haber', 'Haber Üret']]) {
    tabbar.append(el('button', { class: 'tab', dataset: { t }, onclick: () => swap(t) }, label));
  }

  ctl = openModal({ title: 'İçerik Üret', wide: true, body: el('div', {}, tabbar, content) });
  swap(tab === 'haber' ? 'haber' : 'gorsel');
  return ctl;
}

// Route girişi (#create): hafif bir sayfa + popup açar (doğrudan URL/yenileme için).
export async function renderCreate(root, ctx, params) {
  root.innerHTML = '';
  const tab = (params && params.tab) || 'gorsel';

  const head = el('div', { class: 'page__head' },
    el('div', {},
      el('h1', { class: 'page__title' }, 'İçerik Üret'),
      el('div', { class: 'page__subtitle' }, 'Güncel Japonya haberinden kart ya da yazdığın konudan editöryel görsel.')),
    el('div', { class: 'page__actions' },
      el('button', { class: 'btn', onclick: () => ctx.navigate('library'), html: '<span>← Kütüphaneye Dön</span>' })));
  root.append(head);

  root.append(el('div', { class: 'card' }, el('div', { class: 'card__body vstack', style: 'gap:12px' },
    el('p', { class: 'muted', style: 'margin:0' }, 'Üretim penceresi açılmadıysa aşağıdan yeniden başlatabilirsiniz.'),
    el('div', { class: 'hstack' },
      el('button', { class: 'btn btn--primary', onclick: () => openCreateModal(ctx, 'gorsel'), html: icons.sparkle + '<span>Görsel Üret</span>' }),
      el('button', { class: 'btn', onclick: () => openCreateModal(ctx, 'haber'), html: icons.news + '<span>Haber Üret</span>' })))));

  openCreateModal(ctx, tab);
}

// =========================================================================
// GÖRSEL ÜRET — 3 adımlı wizard (studio.html birebir davranış)
// =========================================================================
function buildGorsel(ctx, onDone) {
  const state = { query: '', page: 1, results: [], selectedIdx: null, style: 'style2' };

  // ---- Sol: wizard ----
  // Adım göstergesi
  const steps = [
    el('div', { class: 'wiz__st is-current', dataset: { step: '1' } }, '1. Konu'),
    el('div', { class: 'wiz__st', dataset: { step: '2' } }, '2. Görsel seç'),
    el('div', { class: 'wiz__st', dataset: { step: '3' } }, '3. Metin'),
  ];
  const wiz = el('div', { class: 'wiz' }, ...steps);

  // --- Adım 1: Konu ---
  const topicInput = el('input', { class: 'input', maxlength: '60',
    placeholder: 'Örn. Fuji, ramen, teamLab, shinkansen, Kyoto sokakları',
    oninput: () => { topicCount.textContent = `${topicInput.value.length} / 60`; updatePreview(); } });
  const topicCount = el('span', { class: 'field__count' }, '0 / 60');
  const searchBtn = el('button', { class: 'btn btn--primary', onclick: () => doSearch(), html: icons.search + '<span>Görsel ara</span>' });
  const textOnlyBtn = el('button', { class: 'btn', title: 'Görsel seçmeden konudan başlık + açıklama üret',
    onclick: () => aiFromText(), html: icons.sparkle + '<span>Sadece metin üret</span>' });
  const step1 = el('div', { class: 'viz-step', dataset: { vizStep: '1' } },
    el('div', { class: 'field' },
      el('div', { class: 'hstack', style: 'justify-content:space-between' },
        el('label', { class: 'field__label' }, 'Konu veya arama kelimesi'), topicCount),
      topicInput),
    el('div', { class: 'hstack', style: 'margin-top:12px' }, searchBtn, textOnlyBtn));

  // --- Adım 2: Görsel seç ---
  const resetBtn = el('button', { class: 'btn btn--sm btn--ghost', onclick: () => resetWizard(), html: '↺ Yeni görsel' });
  const moreBtn = el('button', { class: 'btn btn--sm btn--ghost', style: 'color:var(--accent)', onclick: () => doMore(), html: 'Farklı 10 →' });
  const pickerGrid = el('div', { class: 'picker-grid' });
  const step2 = el('div', { class: 'viz-step', dataset: { vizStep: '2' }, hidden: '' },
    el('div', { class: 'hstack', style: 'justify-content:space-between;margin-bottom:10px' },
      el('label', { class: 'field__label', style: 'margin:0' }, 'Aramadan 10 sonuç — bir görsel seç'),
      el('div', { class: 'hstack', style: 'gap:10px' }, resetBtn, moreBtn)),
    pickerGrid);

  // --- Adım 3: Metin + kart oluştur ---
  const aciInput = el('textarea', { class: 'textarea', maxlength: '280',
    placeholder: 'AI ile üret veya manuel yaz — belgesel/ansiklopedik Türkçe, klişesiz.',
    oninput: () => { aciCount.textContent = `${aciInput.value.length} / 280`; updatePreview(); } });
  const aciCount = el('span', { class: 'field__count' }, '0 / 280');
  const capInput = el('textarea', { class: 'textarea',
    placeholder: 'Post açıklaması + hashtag\'ler (opsiyonel)',
    oninput: () => { capCount.textContent = `${capInput.value.length} karakter`; } });
  const capCount = el('span', { class: 'field__count' }, 'AI otomatik oluşturur · 0 karakter');
  const tagInput = el('input', { class: 'input', value: 'GEZİ DEFTERİ', placeholder: 'GEZİ DEFTERİ',
    oninput: () => updatePreview() });

  // Kart stili seçimi (style1 / style2)
  const styleChoice = (val, title, sub) => {
    const b = el('button', { type: 'button', class: `style-choice ${state.style === val ? 'is-active' : ''}`, dataset: { style: val },
      onclick: () => {
        state.style = val;
        stylePicker.querySelectorAll('.style-choice').forEach((x) => x.classList.toggle('is-active', x === b));
        toast(val === 'style2' ? 'Stil 2 seçildi — Japonya Rüyası' : 'Stil 1 seçildi — Editöryel', 'ok');
      } },
      el('span', { class: 'style-choice__t' }, el('strong', {}, title), el('small', {}, sub)));
    return b;
  };
  const stylePicker = el('div', { class: 'style-picker' },
    styleChoice('style1', 'Stil 1', 'Editöryel fotoğraf ve sade başlık'),
    styleChoice('style2', 'Stil 2', 'Japonya Rüyası wordmark tasarımı'));

  const regenBtn = el('button', { class: 'btn btn--sm btn--ghost', title: 'Seçili görsel varsa görselden, yoksa konudan metni yeniden üret',
    onclick: () => regenerateAciklama(), html: '↻ Açıklamayı yeniden üret' });
  const capBtn = el('button', { class: 'btn btn--sm btn--ghost', title: 'Instagram caption üret (açıklamaya göre)',
    onclick: () => aiCaption(false), html: '↻ Caption üret' });
  const backBtn = el('button', { class: 'btn', onclick: () => setStep(2), html: '← Görsel değiştir' });
  const renderBtn = el('button', { class: 'btn btn--primary', onclick: () => renderCard(), html: icons.send + '<span>Kartı oluştur</span>' });

  const step3 = el('div', { class: 'viz-step', dataset: { vizStep: '3' }, hidden: '' },
    el('div', { class: 'field' },
      el('div', { class: 'hstack', style: 'justify-content:space-between' },
        el('label', { class: 'field__label' }, 'Kart metni (kart üzerinde görünür)'), aciCount),
      aciInput),
    el('div', { class: 'field' },
      el('div', { class: 'hstack', style: 'justify-content:space-between' },
        el('label', { class: 'field__label' }, 'Instagram caption'), capCount),
      capInput),
    el('div', { class: 'grid-2', style: 'gap:14px' },
      el('div', { class: 'field', style: 'margin:0' },
        el('label', { class: 'field__label' }, 'Üst rozet'), tagInput),
      el('div', { class: 'field', style: 'margin:0' },
        el('label', { class: 'field__label' }, 'Kart stili'), stylePicker)),
    el('div', { class: 'field' },
      el('label', { class: 'field__label' }, 'Hızlı düzelt'),
      el('div', { class: 'hstack', style: 'flex-wrap:wrap' }, regenBtn, capBtn)),
    el('div', { class: 'hstack', style: 'justify-content:space-between;margin-top:6px' }, backBtn, renderBtn));

  const left = el('div', { class: 'stack' },
    el('div', { class: 'card' }, el('div', { class: 'card__body' }, wiz, step1, step2, step3)));

  // ---- Sağ: canlı telefon önizleme ----
  const prevKicker = el('div', { class: 'ig-preview__handle' }, 'JAPONYA RÜYASI');
  const prevTitle = el('div', { class: 'ig-preview__title' }, 'Bir fikirle başla.');
  const prevImg = el('img', { alt: 'önizleme' });
  const prevImgWrap = el('div', { class: 'ig-preview__img' }, prevImg);
  const prevBody = el('div', { class: 'ig-preview__caption' }, 'Sol taraftaki iki üretim yolundan birini seçerek başla.');
  const preview = el('div', { class: 'ig-preview' },
    el('div', { class: 'ig-preview__head' },
      el('div', { class: 'ig-preview__avatar' }, 'JR'),
      el('div', {}, el('div', { class: 'ig-preview__name' }, 'Japonya Rüyası'),
        el('div', { class: 'ig-preview__handle' }, '@japonyaruyasi'))),
    prevKicker, prevTitle, prevImgWrap, prevBody,
    el('div', { class: 'ig-preview__tags' }, '#Japonya #JaponyaRüyası'));
  const right = el('div', { class: 'stack' },
    el('div', { class: 'card' }, el('div', { class: 'card__head' }, el('h3', {}, 'Canlı Önizleme')),
      el('div', { class: 'card__body' }, preview)));

  const wrap = el('div', { class: 'grid-2' }, left, right);

  // ---- Yardımcılar ----
  function setStep(n) {
    steps.forEach((s) => {
      const v = Number(s.dataset.step);
      s.classList.toggle('is-current', v === n);
      s.classList.toggle('is-done', v < n);
    });
    [step1, step2, step3].forEach((s) => { s.hidden = Number(s.dataset.vizStep) !== n; });
  }
  function updatePreview() {
    const aci = aciInput.value.trim();
    const topic = topicInput.value.trim();
    const tag = tagInput.value.trim() || 'JAPONYA RÜYASI';
    prevTitle.textContent = topic ? topic.split(/[.,;]/)[0].slice(0, 60) : 'Bir fikirle başla.';
    prevBody.textContent = aci || (topic ? 'Metni AI ile üret veya kendin yaz.' : 'Sol taraftaki iki üretim yolundan birini seçerek başla.');
    prevKicker.textContent = tag.toUpperCase();
  }
  function resetWizard() {
    state.query = ''; state.page = 1; state.results = []; state.selectedIdx = null; state.style = 'style2';
    topicInput.value = ''; aciInput.value = ''; capInput.value = ''; tagInput.value = 'GEZİ DEFTERİ';
    topicCount.textContent = '0 / 60';
    aciCount.textContent = '0 / 280';
    capCount.textContent = 'AI otomatik oluşturur · 0 karakter';
    stylePicker.querySelectorAll('.style-choice').forEach((x) => x.classList.toggle('is-active', x.dataset.style === 'style2'));
    pickerGrid.innerHTML = '';
    prevImg.removeAttribute('src');
    setStep(1); updatePreview();
    toast('Alanlar sıfırlandı.', 'ok');
  }

  // ---- Görsel arama ----
  async function doSearch() {
    const q = topicInput.value.trim();
    if (q.length < 2) { toast('Önce en az 2 harflik bir arama kelimesi yaz.', 'err'); return; }
    state.query = q; state.page = 1; state.selectedIdx = null;
    setStep(2); await fetchPage();
  }
  async function doMore() { state.page += 1; await fetchPage(); }
  async function fetchPage() {
    pickerGrid.innerHTML = '';
    for (let i = 0; i < 10; i++) pickerGrid.append(el('div', { class: 'picker-thumb skeleton' }));
    try {
      const res = await api.bgPreview({ query: state.query, count: 10, page: state.page });
      state.results = res.results || [];
      renderPicker();
    } catch (e) {
      pickerGrid.innerHTML = '';
      pickerGrid.append(el('div', { class: 'muted', style: 'grid-column:1/-1' }, 'Arama başarısız: ' + e.message));
    }
  }
  function renderPicker() {
    pickerGrid.innerHTML = '';
    if (!state.results.length) {
      pickerGrid.append(el('div', { class: 'muted', style: 'grid-column:1/-1' }, 'Bu arama için sonuç yok.'));
      return;
    }
    state.results.forEach((r, i) => {
      const cell = el('button', { type: 'button', class: `picker-thumb ${state.selectedIdx === i ? 'is-selected' : ''}`,
        'aria-label': `Görsel ${i + 1}`, onclick: () => selectPicker(i) },
        el('img', { src: r.thumb || r.download_url, loading: 'lazy', alt: '' }),
        el('span', { class: 'picker-thumb__cred' }, r.photographer_name || r.photographer || 'Unsplash'),
        el('span', { class: 'picker-thumb__mark', 'aria-hidden': 'true' }, '✓'));
      pickerGrid.append(cell);
    });
  }
  function selectPicker(idx) {
    state.selectedIdx = idx;
    renderPicker();
    const item = state.results[idx];
    if (item) prevImg.src = item.download_url || item.thumb;
    setStep(3);
    if (!aciInput.value.trim()) aiFromImage();
  }

  // ---- AI metin üretimi ----
  async function aiFromImage() {
    const idx = state.selectedIdx;
    if (idx === null || !state.results[idx]) { toast('Önce bir görsel seç.', 'err'); return; }
    const item = state.results[idx];
    const url = item.download_url || item.thumb;
    regenBtn.disabled = true;
    try {
      const res = await api.aiFromImage({ image_url: url, konu: state.query });
      aciInput.value = (res.subtitle || res.aciklama || res.text || '').trim();
      aciCount.textContent = `${aciInput.value.length} / 280`;
      const title = res.title || res.baslik;
      if (title && (!tagInput.value || tagInput.value === 'GEZİ DEFTERİ')) tagInput.value = title.toUpperCase().slice(0, 24);
      updatePreview();
      await ensureAutoCaption();
      toast('✓ Görselden metin üretildi. Beğenmezsen elle düzenle.', 'ok');
    } catch (e) { toast('AI vision hatası: ' + e.message, 'err'); }
    finally { regenBtn.disabled = false; }
  }
  async function aiFromText() {
    const q = topicInput.value.trim();
    if (q.length < 2) { toast('Önce bir konu yaz.', 'err'); return; }
    if (step3.hidden) setStep(3);
    textOnlyBtn.disabled = true;
    try {
      const res = await api.aiFromText({ konu: q });
      aciInput.value = (res.subtitle || res.aciklama || res.text || '').trim();
      aciCount.textContent = `${aciInput.value.length} / 280`;
      const title = res.title || res.baslik;
      if (title && (!tagInput.value || tagInput.value === 'GEZİ DEFTERİ')) tagInput.value = title.toUpperCase().slice(0, 24);
      updatePreview();
      await ensureAutoCaption();
      toast('✓ Konudan metin üretildi. Şimdi bir görsel seç.', 'ok');
    } catch (e) { toast('AI text hatası: ' + e.message, 'err'); }
    finally { textOnlyBtn.disabled = false; }
  }
  function regenerateAciklama() { return state.selectedIdx === null ? aiFromText() : aiFromImage(); }

  async function generateCaption(silent) {
    const aci = aciInput.value.trim();
    const topic = topicInput.value.trim();
    if (!aci) { if (!silent) toast('Önce kart metnini üret veya yaz.', 'err'); return false; }
    const fallback = () => {
      const lead = topic ? `${topic}\n\n` : '';
      return `${lead}${aci}\n\n#Japonya #JaponyaRüyası #GeziNotları`;
    };
    try {
      const res = await api.expandCaption({ aciklama: aci, baslik: topic.slice(0, 60) });
      capInput.value = (res.caption || res.text || '').trim() || fallback();
    } catch (e) {
      capInput.value = fallback();
      if (!silent) toast('Caption hatası: ' + e.message, 'err');
    }
    capCount.textContent = `${capInput.value.length} karakter`;
    if (!silent && capInput.value) toast('✓ Instagram caption üretildi.', 'ok');
    return Boolean(capInput.value);
  }
  async function ensureAutoCaption() { return capInput.value.trim() ? true : generateCaption(true); }
  async function aiCaption(silent) { return generateCaption(silent); }

  // ---- Kart render ----
  async function renderCard() {
    const idx = state.selectedIdx;
    if (idx === null) { toast('Önce bir görsel seç.', 'err'); return; }
    const bg = state.results[idx];
    const aciklama = aciInput.value.trim();
    if (aciklama.length < 8) { toast('Kart metni en az 8 karakter olmalı.', 'err'); return; }
    await ensureAutoCaption();

    openGenOverlay('Kart oluşturuluyor', 'Seçili görsel + metnin render\'ı.');
    setGenStages([
      { key: 'dl', label: 'Görsel yükleniyor' },
      { key: 'render', label: 'PIL kart render' },
      { key: 'save', label: 'Kütüphaneye kayıt' },
    ], 'dl');
    genAppendLog('Seçili görsel indiriliyor…');
    try {
      const res = await api.renderDirect({
        query: state.query,
        background_url: bg.download_url || bg.regular_url,
        background_id: bg.id,
        photographer: bg.photographer || '',
        baslik: topicInput.value.trim(),
        aciklama,
        ust_tag: tagInput.value.trim() || 'GEZİ DEFTERİ',
        style: state.style,
        post_caption: capInput.value.trim(),
      });
      setGenStages(null, 'save', ['dl', 'render']);
      const file = res.file || res.name;
      genAppendLog(`✓ Kart oluşturuldu: ${file || '?'}`);
      finishGenOverlay(true, {
        file,
        onResult: () => { onDone && onDone(); ctx.navigate('library:pending_approval'); },
      });
    } catch (e) {
      genAppendLog('Hata: ' + e.message);
      finishGenOverlay(false, {});
      toast('Render hatası: ' + e.message, 'err');
    }
  }

  updatePreview();
  return wrap;
}

// =========================================================================
// HABER ÜRET — RSS pipeline (studio.html birebir davranış)
// =========================================================================
function buildHaber(ctx, onDone) {
  const autoPublish = el('input', { type: 'checkbox' });
  const runBtn = el('button', { class: 'btn btn--primary', onclick: () => run() },
    el('span', { html: icons.news }), 'Haberden kart üret');

  const logBox = el('div', { style: 'font-size:12.5px;color:var(--ink-soft);min-height:60px' },
    el('span', { class: 'muted' },
      'Tokyo Cheapo, SoraNews24, Nippon.com, Japan Today RSS akışlarından son 48 saatin haberleri taranır; ' +
      'her aday GPT editorial gate\'ten (30/50 puan) geçirilir; kazanan haberden Japonya Rüyası tonunda ' +
      '1080×1350 kart + Instagram caption üretilir. Kart Onay Bekliyor sütununa düşer.'));

  const wiz = el('div', { class: 'wiz' },
    el('div', { class: 'wiz__st is-current' }, '1. RSS tara'),
    el('div', { class: 'wiz__st' }, '2. Editöryel gate'),
    el('div', { class: 'wiz__st' }, '3. Görsel + render'),
    el('div', { class: 'wiz__st' }, '4. Onay bekliyor'));

  const wrap = el('div', { class: 'grid-2' },
    el('div', { class: 'card' }, el('div', { class: 'card__body' },
      wiz,
      el('p', { class: 'muted', style: 'font-size:12.5px;margin:4px 0 14px' },
        'Haber otomasyonu pipeline\'ı — mevcut algoritma değişmedi.'),
      el('label', { class: 'option', style: 'margin-bottom:16px' }, autoPublish,
        'Otomatik yayınla (kapalı: kart onay bekler · açık: gate geçince direkt Instagram — önerilmez)'),
      el('div', { class: 'hstack' }, runBtn))),
    el('div', { class: 'card' },
      el('div', { class: 'card__head' }, el('h3', {}, 'Nasıl Çalışır?')),
      el('div', { class: 'card__body' }, logBox)));

  async function run() {
    // Üretim penceresini kapatıp asenkron akış overlay'ini aç
    onDone && onDone();
    openGenOverlay('Japon haber üretiliyor', 'RSS → editöryel gate → görsel → render → onay bekliyor.');
    setGenStages([
      { key: 'rss', label: 'RSS akışları taranıyor' },
      { key: 'gate', label: 'Editöryel gate (GPT 30/50)' },
      { key: 'visual', label: 'Unsplash görseli seçiliyor' },
      { key: 'render', label: '1080×1350 kart render' },
      { key: 'queue', label: 'Onay bekliyor\'a düşürülüyor' },
    ], 'rss');
    let resultFile = null;
    try {
      await api.automationRunNow({ kind: 'news', auto_publish: autoPublish.checked, topic: '', query: '' });
      const ok = await pollJobUntilDone((line) => {
        if (!line) return;
        genAppendLog(line);
        const m = line.match(/(?:haber|konu):\s*([^\s]+\.jpg)/i);
        if (m) resultFile = m[1];
      });
      if (ok) {
        setGenStages(null, null, ['rss', 'gate', 'visual', 'render', 'queue']);
        finishGenOverlay(true, {
          file: resultFile || 'haber',
          onResult: () => ctx.navigate('library:pending_approval'),
        });
      } else {
        finishGenOverlay(false, { outcome: 'error' });
      }
    } catch (e) {
      genAppendLog('Hata: ' + e.message);
      finishGenOverlay(false, { outcome: 'error' });
      toast('Haber üretimi başarısız: ' + e.message, 'err');
    }
  }

  return wrap;
}
