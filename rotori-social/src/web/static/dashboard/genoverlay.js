// =========================================================================
// genoverlay.js — Asenkron üretim akışı overlay'i (studio.html mimarisi)
//   openGenOverlay(title, sub)          → overlay'i aç
//   setGenStages(stages, active, done)  → aşama checklist + ilerleme çubuğu
//   genAppendLog(text)                  → canlı log satırı (otomatik aşama tespiti)
//   finishGenOverlay(ok, {file,onResult,outcome})
//   pollJobUntilDone(onLine)            → /api/status + /api/logs long-poll
// =========================================================================
import { api, el } from './lib.js?v=20260821-1';

// Aşama açıklamaları (alt satır metni)
const STAGE_DETAIL = {
  rss: 'Kaynaklardan güncel içerikler toplanıyor.',
  gate: 'Adaylar editöryel kalite kriterlerine göre değerlendiriliyor.',
  visual: 'İçeriğe uygun görsel hazırlanıyor.',
  render: 'Kart 1080×1350 formatında oluşturuluyor.',
  queue: 'Sonuç onay kuyruğuna kaydediliyor.',
  dl: 'Seçilen görsel güvenli biçimde indiriliyor.',
  save: 'Kart kütüphaneye kaydediliyor.',
};
const STAGE_RANK = { rss: 0, gate: 1, visual: 2, render: 3, queue: 4, dl: 0, save: 2 };

// Overlay durumu
let ui = null;               // DOM referansları
let stagesData = [];
let activeKey = null;
let startedAt = 0;
let elapsedTimer = null;
let logCount = 0;
let cancelRequested = false;

function buildOverlay() {
  const mark = el('div', { class: 'gen-mark', 'aria-hidden': 'true' }, '✦');
  const title = el('h2', { class: 'gen-title' }, 'İçerik üretiliyor');
  const sub = el('p', { class: 'gen-sub muted' }, 'İşlem tamamlandığında sonuç burada belirir.');
  const status = el('span', { class: 'gen-status' }, 'Çalışıyor');
  const bar = el('i', { class: 'gen-progress__bar' });
  const stagesBox = el('div', { class: 'gen-stages' });
  const spinner = el('span', { class: 'gen-spinner', 'aria-hidden': 'true' });
  const curTitle = el('strong', { class: 'gen-current__title' }, 'Hazırlanıyor');
  const curDetail = el('p', { class: 'gen-current__detail' }, 'İş akışı başlatılıyor.');
  const current = el('div', { class: 'gen-current' }, spinner,
    el('div', {}, el('span', { class: 'gen-current__label' }, 'Şu an yapılan'), curTitle, curDetail));
  const logCountEl = el('span', { class: 'gen-log__count' }, '0 kayıt');
  const elapsed = el('span', { class: 'gen-log__elapsed' }, 'Hazırlanıyor');
  const logHead = el('div', { class: 'gen-log__head' },
    el('span', {}, 'İşlem akışı'), el('span', {}, logCountEl, ' · ', elapsed));
  const log = el('div', { class: 'gen-log' });
  const cancelBtn = el('button', { class: 'btn btn--ghost', onclick: requestCancel }, 'İptal');
  const closeBtn = el('button', { class: 'btn btn--primary', disabled: '', hidden: '' }, 'Sonuç hazırlanıyor…');
  const actions = el('div', { class: 'gen-actions' }, cancelBtn, closeBtn);

  const card = el('div', { class: 'gen-card', role: 'dialog', 'aria-live': 'polite' },
    el('div', { class: 'gen-top' }, mark,
      el('div', { class: 'gen-head' }, title, sub), status),
    el('div', { class: 'gen-progress', 'aria-hidden': 'true' }, bar),
    stagesBox, current, logHead, log, actions);
  const overlay = el('div', { class: 'gen-overlay' }, card);
  (document.getElementById('modal-root') || document.body).append(overlay);

  ui = { overlay, title, sub, status, bar, stagesBox, spinner, curTitle, curDetail,
    logCountEl, elapsed, log, cancelBtn, closeBtn };
}

function requestCancel() {
  cancelRequested = true;
  ui.cancelBtn.disabled = true;
  ui.status.textContent = 'Durduruluyor';
  ui.curTitle.textContent = 'İptal isteği gönderildi';
  ui.curDetail.textContent = 'Çalışan adım güvenli biçimde kapatılıyor…';
  genAppendLog('İptal isteği gönderildi; çalışan adım güvenli biçimde kapatılıyor.');
  api.jobCancel().catch(() => {});
}

export function openGenOverlay(title, sub) {
  if (!ui) buildOverlay();
  stagesData = []; activeKey = null; logCount = 0; cancelRequested = false;
  ui.title.textContent = title;
  ui.sub.textContent = sub || '';
  ui.status.textContent = 'Çalışıyor';
  ui.status.className = 'gen-status is-run';
  ui.bar.style.width = '0%';
  ui.stagesBox.innerHTML = '';
  ui.log.innerHTML = '';
  ui.logCountEl.textContent = '0 kayıt';
  ui.spinner.style.display = 'block';
  ui.curTitle.textContent = 'Hazırlanıyor';
  ui.curDetail.textContent = 'İş akışı başlatılıyor.';
  ui.cancelBtn.hidden = false; ui.cancelBtn.disabled = false;
  ui.closeBtn.hidden = true; ui.closeBtn.disabled = true;
  ui.closeBtn.textContent = 'Sonuç hazırlanıyor…';
  startedAt = Date.now();
  clearInterval(elapsedTimer);
  ui.elapsed.textContent = 'Çalışıyor · 0 sn';
  elapsedTimer = setInterval(() => {
    ui.elapsed.textContent = `Çalışıyor · ${Math.floor((Date.now() - startedAt) / 1000)} sn`;
  }, 1000);
  ui.overlay.classList.add('is-open');
}

export function closeGenOverlay() { ui && ui.overlay.classList.remove('is-open'); }

function rankOf(key) {
  const local = stagesData.findIndex((s) => s.key === key);
  return local >= 0 ? local : (STAGE_RANK[key] ?? 0);
}

export function setGenStages(stages, active, doneKeys) {
  if (stages) stagesData = stages;
  // Geriye doğru aşama atlamasını engelle
  if (active && activeKey && rankOf(active) < rankOf(activeKey)) return;
  if (active !== undefined) activeKey = active;
  const done = new Set(doneKeys || []);
  const activeStage = stagesData.find((s) => s.key === active);
  const completed = done.size + (activeStage && !done.has(active) ? 0.45 : 0);
  const pct = stagesData.length ? Math.min(100, Math.round((completed / stagesData.length) * 100)) : 0;
  ui.bar.style.width = pct + '%';
  if (activeStage) {
    ui.curTitle.textContent = activeStage.label;
    ui.curDetail.textContent = STAGE_DETAIL[activeStage.key] || 'İşlem devam ediyor.';
  }
  ui.stagesBox.innerHTML = '';
  for (const s of stagesData) {
    const isDone = done.has(s.key);
    const isActive = s.key === active;
    const cls = isDone ? 'is-done' : isActive ? 'is-active' : '';
    ui.stagesBox.append(el('div', { class: `gen-stage ${cls}` },
      el('span', { class: 'gen-stage__dot', 'aria-hidden': 'true' }, isDone ? '✓' : ''),
      el('b', {}, s.label),
      el('small', {}, isDone ? 'Tamamlandı' : isActive ? 'Şu an' : 'Sırada')));
  }
}

export function genAppendLog(line) {
  const text = String(line || '').trim();
  if (!text || !ui) return;
  const stamp = new Date().toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  const kind = /hata|başarısız|✖/i.test(text) ? 'is-err'
    : /uyarı|atlandı|⚠/i.test(text) ? 'is-warn'
    : /✓|✅|tamamlandı|hazır/i.test(text) ? 'is-ok' : '';
  const bullet = kind === 'is-ok' ? '✓' : kind === 'is-warn' ? '!' : '•';
  ui.log.append(el('div', { class: `gen-log__row ${kind}` },
    el('span', { class: 'gen-log__time' }, stamp),
    el('span', { class: 'gen-log__bullet' }, bullet),
    el('span', {}, text)));
  logCount += 1;
  ui.logCountEl.textContent = `${logCount} kayıt`;
  autoStageFromLog(text);
  ui.log.scrollTop = ui.log.scrollHeight;
}

// Log metninden aşama ilerlemesini tahmin et (haber pipeline)
function autoStageFromLog(text) {
  const l = text.toLowerCase();
  if (/(tokyo cheapo|soranews24|nippon\.com|japan today|japan times|rss|feed|haber toplandı|kaynak)/i.test(text)) {
    if (/tamamlandı|toplandı|seçilen haber/i.test(text)) setGenStages(null, 'rss', []);
    return;
  }
  if (/editor|editöryel|puan|kalite|gate|gpt/.test(l)) setGenStages(null, 'gate', ['rss']);
  else if (/unsplash|arka plan|görsel/.test(l)) setGenStages(null, 'visual', ['rss', 'gate']);
  else if (/render|kart/.test(l)) setGenStages(null, 'render', ['rss', 'gate', 'visual']);
  else if (/onay|pending|düş/.test(l)) setGenStages(null, 'queue', ['rss', 'gate', 'visual', 'render']);
}

export function finishGenOverlay(ok, { file = null, onResult = null, outcome = 'error' } = {}) {
  clearInterval(elapsedTimer);
  if (ok && stagesData.length) setGenStages(null, null, stagesData.map((s) => s.key));
  else setGenStages(null, null, []);
  const elapsed = Math.max(1, Math.floor((Date.now() - startedAt) / 1000));
  const cancelled = outcome === 'cancelled';
  ui.elapsed.textContent = ok ? `Tamamlandı · ${elapsed} sn` : `Durduruldu · ${elapsed} sn`;
  ui.status.textContent = ok ? 'Tamamlandı' : cancelled ? 'Durduruldu' : 'Başarısız';
  ui.status.className = 'gen-status ' + (ok ? 'is-ok' : cancelled ? 'is-warn' : 'is-err');
  ui.spinner.style.display = 'none';
  ui.curTitle.textContent = ok ? 'İşlem tamamlandı' : cancelled ? 'İşlem durduruldu' : 'İşlem tamamlanamadı';
  ui.curDetail.textContent = ok ? 'Sonuç bir sonraki adıma hazır.'
    : cancelled ? 'İşlem kullanıcı tarafından durduruldu.' : 'Ayrıntılar işlem akışında tutuldu.';
  ui.title.textContent = ok ? '✓ Hazır' : cancelled ? 'İşlem durduruldu' : 'İşlem başarısız';
  ui.sub.textContent = ok ? (file ? `Sonuç: ${file}` : 'Sonuç kaydedildi.')
    : cancelled ? 'Yeni bir işlem başlatabilirsiniz.' : 'Ayrıntı için log\'a bak.';
  ui.cancelBtn.hidden = true;
  ui.closeBtn.hidden = false;
  ui.closeBtn.disabled = false;
  ui.closeBtn.textContent = ok && onResult ? 'Sonucu gör' : 'Kapat';
  ui.closeBtn.onclick = () => { closeGenOverlay(); if (ok && onResult) onResult(file); };
}

// Job manager poll — /api/status.job durumu done|error olana kadar
export async function pollJobUntilDone(onLine) {
  let lastLine = '';
  let logSeq = 0;
  let baseline = false;
  for (let i = 0; i < 120; i++) {           // ~6 dk max
    await new Promise((r) => setTimeout(r, 3000));
    try {
      const s = await api.jobStatus();
      if (!s || !s.job) { onLine && onLine('İş durumu henüz alınamadı; yeniden deneniyor…', s); continue; }
      if (!baseline) { logSeq = Number(s.job.log_seq || 0); baseline = true; }
      const logState = await api.jobLogs(logSeq);
      if (logState) {
        for (const entry of (logState.entries || [])) {
          if (entry.text) onLine && onLine(entry.text, s);
        }
        logSeq = logState.seq || logSeq;
      }
      const line = (logState && logState.progress_line) || '';
      if (line && line !== lastLine) { onLine && onLine(line, s); lastLine = line; }
      if (s.job.running && i > 0 && i % 4 === 0) {
        onLine && onLine('İşlem devam ediyor; kalite kontrolü ve üretim adımları sürüyor…', s);
      }
      if (s.job.error) { onLine && onLine(String(s.job.error || 'Hata'), s); return false; }
      if (!s.job.running && s.job.finished_at) return !cancelRequested;
    } catch (_e) { /* geçici ağ hatası — tekrar dene */ }
  }
  return false;
}
