# ARCHITECTURE.md — Güncel Mimari

> Kod değiştiğinde bu dosya **aynı PR'da** güncellenmelidir.
> Son revizyon: 2026-08-21 (manuel içerik kategorileri ve kategori bazlı üretim)

## 1. Yüksek seviye

Modüler dashboard varsayılan olarak `#overview` rotasında açılır. Sunum katmanı
kullanıcıya teknik modülleri değil şu görev sırasını gösterir:
`Genel Bakış → Kütüphane → Otomasyon → Aktivite → Ayarlar`. Genel Bakış yalnız
okuma ve yönlendirme yapar; yayın veya durum değişikliği başlatmaz. Anında yayın,
yeniden deneme ve hesap bağlantısını kesme gibi yüksek etkili işlemler modal
onayı olmadan API çağrısı yapmaz.

```
┌────────────────────────────────────────────────────────────────────────┐
│                            KULLANICI (tarayıcı)                          │
│                  https://api.rotori.app  (Cloudflare Tunnel)             │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │  https
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│  Raspberry Pi 5 — docker-compose service: rotori-social                 │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  uvicorn / FastAPI  (src/web/app.py, 8420 → host 3090)           │  │
│  │  ├─ StaticFiles: /static (index.html, manifest, Rotori icons)    │  │
│  │  ├─ StaticFiles: /media/backgrounds (Unsplash cache)             │  │
│  │  ├─ 67 REST route (bkz. §7)                                      │  │
│  │  ├─ JobManager (in-process job + canlı log bridge)               │  │
│  │  └─ Scheduler background thread (opsiyonel, config'e bağlı)      │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│  volumes: config.yaml:ro, data/, output/, assets/                      │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
     ┌─────────────────────────────┼───────────────────────────┐
     │                             │                            │
     ▼                             ▼                            ▼
┌─────────────┐          ┌──────────────────┐          ┌──────────────────┐
│  Ollama     │          │  Dify workflow   │          │  Dış servisler   │
│ (host Mac/  │          │ (Pi5 LAN)        │          │  OpenAI          │
│  Pi host)   │          │ 192.168.1.60     │          │  Instagram Graph │
│ llava:7b    │          │ :5001            │          │  Unsplash        │
│ qwen2.5:3b  │          │ reels_kurgu_...  │          │  TikTok          │
└─────────────┘          └──────────────────┘          │  RSS feeds       │
                                                       └──────────────────┘
```

## 2. Modül sınırları (`src/`)

```
┌───────────────────── SUNUM KATMANI ──────────────────────┐
│  src/web/app.py          FastAPI + endpoint sözleşmeleri │
│                          (63 route — 3'ü router'a taşındı)│
│  src/web/dependencies.py Runtime singleton'lar (cfg/manager)│
│  src/web/routers/                                        │
│    └─ system.py          /api/version, /api/status, /api/logs│
│  src/web/jobs.py         JobManager (thread + log bridge)│
│  src/web/static/         index.html (tek dosya SPA)      │
└────────────────────┬──────────────────────────────────────┘
                     │ çağırır
┌────────────────────▼──────── ORCHESTRATION ───────────────┐
│  batch_pipeline    prompt_pipeline    analyze_pipeline    │
│  news_automation   topic_automation   scheduler           │
└────────────────────┬──────────────────────────────────────┘
                     │ çağırır
┌────────────────────▼──────── STEP KATMANI ────────────────┐
│  step1_analyze  step2_group  step3_dify  step4_render     │
│  story_generator (kart pipeline'ı, ayrı hat)              │
└────────────────────┬──────────────────────────────────────┘
                     │ kullanır
┌────────────────────▼──────── SERVİS + IO ─────────────────┐
│  ollama_client   openai_client   downloader (Unsplash)    │
│  instagram_graph instagram_publisher tiktok_publisher     │
│  editorial (LLM prompt + kalite kapısı)                   │
│  labeling  suggestions  analytics  persona                │
│  utils/ffprobe  utils/logging  mac_notifier               │
└────────────────────┬──────────────────────────────────────┘
                     │ okur/yazar
┌────────────────────▼──────── DURUM (disk) ────────────────┐
│  config.yaml (secret) — src/config.py load_config()       │
│  data/metadata.csv, data/kurgu_planlari/*.json            │
│  data/scheduler_queue.json, data/automation_config.json   │
│  data/*_uploads.jsonl (log), data/instagram_session.json  │
│  output/reels/*.mp4, output/stories/*.jpg                 │
│  assets/story_backgrounds/, assets/fonts/, assets/topic_pool.json │
└────────────────────────────────────────────────────────────┘
```

**Bağımlılık kuralı**: yukarı → aşağı sadece. Aşağıdaki katman üstü import edemez.

## 3. Klasör sorumlulukları

| Klasör | Sorumluluk | Kalıcılık |
|---|---|---|
| `src/` | Tüm Python kaynağı | Git |
| `src/web/static/` | Frontend | Git |
| `data/` | Runtime state (metadata, plan, log, state.json) | Docker volume, gitignored |
| `output/reels/` | MoviePy render çıktısı | Docker volume, gitignored |
| `output/stories/` | PIL story kartı çıktısı | Docker volume, gitignored |
| `output/ready_to_publish/` | Onaylanmışlar (arşiv) | Docker volume |
| `assets/` | Font, arka plan, konu havuzu | Kısmen git (fonts, topic_pool, logo), story_backgrounds cache |
| `knowledge/` | LLM'e sunulan editöryel referans | Git |
| `dify/` | Dify DSL YAML | Git |
| `scripts/` | Yardımcı bash (pull_models, run_web) | Git |
| `docs/` | Bu dokümantasyon | Git |
| `bin/` | Kullanıcıya sunulan launcher (`open-widget.sh`) | Git |
| `content/` | Excel roadmap, brainstorm dokümanları | Git |

## 4. Ana veri hattı — Reels üretimi

```
   Video arşivi (paths.video_source_dir)
              │
              ▼
   [step1_analyze]  ── llava → data/metadata.csv (label, sahne_ogeleri, süre)
              │
              ▼
   [step2_group]    ── metadata → sahnelere göre mekan grupları
              │
              ▼
   [step3_dify]     ── Dify workflow (Ollama qwen) →
                      data/kurgu_planlari/{mekan}_final.json
                      ({kurgu_json, aciklama, hashtagler})
              │
              ▼
   [step4_render]   ── MoviePy 9:16 concat + overlay →
                      output/reels/{mekan}_{uid}.mp4
                      + eşleşen {stem}.txt (caption)
              │
              ▼
   [scheduler]      ── enqueue → data/scheduler_queue.json
   (opsiyonel)      ── process_due → auto_upload ? Graph API : status=ready
              │
              ▼
   Instagram Graph API → @japonyaruyasi
   (TikTok publisher paralel opsiyon)
```

## 5. İkinci veri hattı — Story kartı (haber/konu)

```
   ┌─ RSS (feedparser, Tokyo Cheapo + SoraNews24 + Nippon.com + Japan Today)
   │   │
   │   ▼
   │  [news_automation]  ── editorial gate (GPT, 30/50 puan)
   │                       ── seçim + Unsplash arama kelimesi
   │
   ├─ topic_pool (assets/topic_pool.json)
   │   │
   │   ▼
   │  [topic_automation] ── editorial prompt (aynı gate)
   │
   ▼
   [downloader] Unsplash → assets/story_backgrounds/*.jpg
   ▼
   [story_generator] PIL 1080×1350 →
      output/stories/{konu_slug}_{ts}.jpg
      + {stem}.txt (Instagram caption)
      + {stem}.json (sidecar: kaynak, hashtagler, hook, kart metni)
   ▼
   Onay kuyruğu → /api/approval/*
   Yayına Hazır → /api/story/mark_ready
   Instagram Graph API veya Drive senkron klasörü
```

### 5.1 Manuel içerik kategorileri

`Yeni İçerik → Haber Üret` akışında kullanıcı üst kategoriyi elle seçer:

| Slug | Arayüz etiketi | Üretim kaynağı |
|---|---|---|
| `guncel_haberler` | Güncel Haberler | RSS + editöryel AI puanı |
| `seyahat_hazirligi` | Japonya Yolculuğu | Kategoriye filtrelenmiş evergreen konu havuzu |
| `animeler` | Animeler | Kategoriye filtrelenmiş evergreen konu havuzu |
| `teknoloji` | Teknolojik Ürünler | Kategoriye filtrelenmiş evergreen konu havuzu |

Güncel Haberler seçildiğinde yalnız RSS adayları işlenir; diğer üç kategori
konu havuzundan uygun başlık seçer ve aynı editöryel AI kapısından geçer. Dört
akışın da görseli mevcut Unsplash aramasıyla otomatik bulunur, açıklama ve
kart metni mevcut `editorial` hattıyla otomatik yazılır. Üretilen sidecar
JSON'unda `content_category` ve `content_category_label` alanları tutulur;
Kütüphane bu alanla filtreleme yapabilir. `GET /api/content/categories`
arayüz sözleşmesindeki kategori listesini sağlar.

## 6a. İkinci frontend — `studio.html` (yeni, feature-flagged)

- **Kaynak paket**: `japonya-ruyasi-dashboard-design.zip` (DESIGN-SPEC.md + prototipi + referans ekranlar).
- **Serve**: `GET /studio` veya `GET /?ui=new` / `?ui=studio`. Default `/` hâlâ eski `index.html`.
- **Yapı**: tek dosya, `src/web/static/studio.html` (~1100 satır). Sidebar (238px koyu) + topbar (74px yapışkan) + 7 sayfa (Genel Bakış / AI Stüdyo / Takvim / Kütüphane / Yayın Kuyruğu / Analiz / Ayarlar).
- **Görsel dil**: paper #F2EFE7 zemin, mercan #E34332 aksan, Georgia display + Inter sans, 18-20px radius, editorial fotoğraf atlası (`japan-editorial-grid.png`, 300%×200% background-position).
- **Global helper'lar**: `apiFetch` (timeout + AbortController + ApiError), `withLoading`, `toast`, `openPage`, `_fmtDate`, `_sceneFor`.
- **Endpoint kullanım tablosu**: bkz. `docs/CURRENT_TASK.md`.
- **Responsive**: 1100px altında 4→2 sütun; 850px altında sidebar alt navigation bar'a döner; 560px altında search gizlenir, kartlar tek sütun.
- **Bugünün notu**: eski UI kaldırılmadı — feature flag ile paralel yaşıyor.

## 6b. Modüler dashboard — `static/dashboard/`

- `app.js` sayfa modüllerini yükler; ortak API istemcisi ve bileşen yardımcıları
  `lib.js` içindedir.
- Kütüphane ürün akışı yalnız üç ana aşama taşır: **Taslak → Onaylandı →
  Yayınlandı**. `queued`, `scheduled`, `publishing` ve `failed` teknik durumları
  Onaylandı aşamasının altında sunulur; kullanıcıya dördüncü bir aşama açmaz.
- Tek kart otomasyon eylemi `POST /api/scheduler/auto_fill_ready/{name}` ile
  yalnız seçilen onaylı dosyayı planlar. Toplu eylem mevcut
  `POST /api/scheduler/auto_fill_ready` endpoint'ini kullanır.
- Yayın geçmişi `GET /api/dashboard/library` yanıtındaki `published` durumundan
  türetilir; upload logu güncellendiğinde kart bir sonraki yenilemede Yayınlandı
  arşivinde görünür.
- **Otomasyon ekranı tek görünümdür** (sekme yok). Her akış kartı kendi yayın
  düzenini taşır: kart başlığında aç/kapat anahtarı, hemen altında `lane-cfg`
  şeridi (gün seçici + saat + otomatik yayın), sonra yayın slotları. Kapalı
  akış listeden düşmez; düzeni görünür kalır ve "Bu akış kapalı" bilgisi verir.
  Sayfanın en altında salt okunur **Yayın Geçmişi** kartı durur.
- Düzen değişiklikleri `state.drafts` içinde tutulur; `POST /api/automation/config`
  yalnız ilgili lane'in anahtarını (`news` veya `topic`) gönderir. 30 saniyelik
  otomatik yenileme, kaydedilmemiş düzen veya odaklı alan varken atlanır —
  kullanıcının yazdığı değer asla ezilmez.
- Akışı kapatmak `sync_automation_slots` üzerinden o lane'in `pending/ready`
  girdilerini `cancelled` yapar; bu yüzden kapatma onay modalı etkilenen içerik
  sayısını söyler. Yeniden açıldığında `auto_fill_ready` kartları sıraya geri alır.
- Dashboard modülleri deploy/cache ayrımı için tek sürüm anahtarı kullanır
  (`20260810-7`).

## 6. Frontend akışı — `index.html`

- **Tek dosya**, 5532 satır. `<style>` inline, `<script>` inline. Bağımlılık: sadece Inter font (CDN preconnect).
- **Yapı**:
  - Sol sidebar: kullanıcı iş akışını izler — `Bugün / Hazırlık / Yayına Hazır / Otomasyon / İstatistikler`.
  - Mobil navigasyon: `Bugün / Hazırlık / Hazır / Otomasyon`; ekranın üstünde yapışkan dört eşit hedef.
  - `openWorkspace(view)` görünür iş adımını yönetir; mevcut `switchTab('today'|'cards'|'reels'|'growth')` iç uyumluluk katmanı olarak korunur.
  - Üst tab (gizli, JS uyumu için): 🏠 Bugün / 🎨 Kartlar / 🎬 Reels / 📈 Büyüme.
  - **Bugün panel** (default): üç karar noktası (İçerik hazırla / Onay bekleyenler / Yayın planı), üç operasyon durumu ve son üretilenler.
  - Kartlar paneli aynı DOM'u üç sade görünüme böler: `prep` üretim seçenekleri + taslaklar; `ready` onay kuyruğu; `automation` haftalık akış durumu + sıradaki gönderi.
  - Reels panel: Analiz, Batch, Prompt üret.
  - Büyüme panel: Analytics, Hook A/B, **Yayın Kuyruğu**, TikTok, Platform karşılaştırma.
  - Sağ alt sabit "Canlı Süreç" footer (`livelog-footer`, sürüklenebilir, collapse/expand).
- **Global JS utility'leri**:
  - `apiFetch(url, opts)` — **YENİ**: timeout + AbortController + hata normalizasyonu (`ApiError` sınıfı). JSON body kısayolu (`opts.json`).
  - `withLoading(btn, fn)` — buton spinner + disabled guard
  - `toast(text, kind, ms)` — sağ alt bildirim
  - `pollStatus()`, `pollLogs()` — 2.5s polling
  - `escapeHtml()`, `copyText()`, `openLightbox()`, `_timeAgo(ms)`
- **Poll döngüleri**: `/api/status` 2s, `/api/logs?since=<seq>` 1s (job varken), `/api/reels`, `/api/story/list`, `/api/scheduler/queue` ihtiyaç anında.
- **Bugün panel veri toplama**: `Promise.allSettled` ile 7 mevcut endpoint paralel — biri düşerse ilgili durum kartı `err` sınıfına gider, sayfa çökmez.
- **a11y**: `button:focus-visible` outline, `prefers-reduced-motion` desteği, `is-loading` global spinner sınıfı.

## 7. API katmanı — Route envanteri (`src/web/app.py`)

**Toplam 67 route**. Gruplar:

| Grup | Örnek | Sayı |
|---|---|---|
| Meta | `GET /api/version`, `GET /api/status`, `GET /api/logs` | 3 |
| Öneri/Analiz | `GET /api/suggestions`, `POST /api/analyze`, `POST /api/batch/generate` | 3 |
| Reels üretim | `POST /api/generate/prompt`, `POST /api/reels/make`, `GET /api/reels/generated`, `POST /api/reels/caption`, `POST /api/reels/drive-upload/{name}` | 6 |
| Story kartı | `POST /api/story/generate`, `POST /api/story/render_direct`, `GET /api/story/list`, `DELETE /api/story/{name}`, `POST /api/story/update/{name}`, `POST /api/story/mark_ready/{name}`, `POST /api/story/vary_text`, `POST /api/story/ai_*` | 12 |
| İçerik kategorileri | `GET /api/content/categories` | 1 |
| Arka plan | `POST /api/backgrounds/{download,preview,save}`, `GET /api/backgrounds/status`, `POST /api/story/upload_bg` | 5 |
| Onay kuyruğu | `GET /api/approval/list`, `POST /api/approval/{approve,reject,defer,update}/{name}` | 5 |
| Otomasyon | `GET/POST /api/automation/config`, `POST /api/automation/run_now`, `POST /api/news/run_now` | 4 |
| Instagram | `GET /api/instagram/status`, `POST /api/instagram/{publish,story-draft,draft,reset_session,logout}/{name}`, `GET /api/instagram/graph_status` | 7 |
| Scheduler | `GET/POST /api/scheduler/queue`, `DELETE /api/scheduler/queue/{id}`, `POST /api/scheduler/run` | 4 |
| TikTok | `GET /api/tiktok/status`, `POST /api/tiktok/{upload,refresh_token}` | 3 |
| Analytics | `GET /api/analytics/{overview,hooks,platforms}`, `POST /api/analytics/hooks/{plan}/impression` | 4 |
| Widget/PWA | `POST /api/widget/open`, `GET /` | 2 |
| Catch-all | `GET /{verify_file:path}` (Cloudflare/domain verification) | 1 |
| Reels onay | `GET /api/reels`, `POST /api/reels/{name}/{approve,reject}`, `POST /api/ready/{name}/unpublish` | 4 |
| Job kontrol | `POST /api/cancel` | 1 |

**Sözleşmeler**:
- İş kuralı hataları: `HTTPException(status_code=[400,404,409,500], detail="…")` — detail Türkçe.
- Başarı: `{"ok": true, ...}` veya doğrudan dict payload.
- Uzun işler: `JobManager` — endpoint sadece işi tetikler, `409 Conflict` başka iş çalışıyorsa; canlı sonuç `/api/status` + `/api/logs`.

## 8. Job Manager (`src/web/jobs.py`)

```
        POST /api/reels/make ──► manager.start_step(...)  veya
                                 manager.start_callable(...)
                                          │
                                          ▼
                             ┌────────────────────────┐
                             │  Thread (daemon)       │
                             │  subprocess veya       │
                             │  in-process callable   │
                             │                        │
                             │  emit(msg, level) ────►│──► state["logs"] (deque)
                             │  _EmitLogHandler       │    state["progress_line"]
                             │  logging köprüsü       │    state["job"] status
                             └────────────────────────┘
                                          │
                          GET /api/status,│/api/logs polling
                                          ▼
                                   Frontend footer
```

- **Tek-slot**: aynı anda tek job. İkinci iş → `RuntimeError` → `HTTPException 409`.
- **İptal**: `POST /api/cancel` → `cancel_event.set()` → step kodu düzenli aralıklarla `cancel.is_set()` kontrol eder.
- **Log bridge**: `step1..step4` loggerlarına `_EmitLogHandler` attach; ANSI ve tqdm progress satırları filtrelenir.

## 9. Config yükleme (`src/config.py`)

```
config.yaml (raw dict)
   │
   ▼
load_config()  ──►  Config(
                      paths=PathsCfg,
                      ollama=OllamaCfg,
                      dify=DifyCfg,
                      openai=OpenAICfg,
                      reels=ReelsCfg,
                      pilot=PilotCfg,
                      run=RunCfg,
                      instagram=InstagramCfg | None,
                      stories=StoriesCfg,
                      unsplash=UnsplashCfg | None,
                      drive_folder=str | None,
                      news=NewsCfg,
                      scheduler=SchedulerCfg | None,   ◄── opsiyonel bölüm
                      tiktok=TikTokCfg | None,          ◄── opsiyonel bölüm
                    )
```

**Opsiyonel bölümler**: `scheduler:`, `tiktok:`, `instagram:` config'de yoksa `None`. Kod bu değerleri `if cfg.X` ile korur; ilgili endpoint 404/400 dönmez, `enabled=false` state döner.

## 10. Scheduler (opsiyonel background thread)

```
uvicorn startup
   │
   ▼
_start_scheduler()  ── if cfg.scheduler and cfg.scheduler.enabled
   │
   ▼
start_background_scheduler()  ── daemon thread, name="reels-scheduler"
   │
   ▼ (loop, check_interval_sn=60)
process_due(project_root, output_dir, cfg, auto_upload)
   │
   ├─► auto_upload=True  → instagram_publisher.upload_draft() → status='done'
   └─► auto_upload=False → status='ready' → kullanıcı UI'dan yayınlar
   │
   ▼
scheduler_queue.json (kalıcı)
```

**Not**: `config.yaml`'da `scheduler:` yoksa thread hiç başlamaz. UI, `/api/scheduler/queue` yanıtındaki `config_enabled` field'ından bunu tespit edip kullanıcıya YAML bloğu gösterir.

## 11. Otomasyon zamanlaması (haber + konu)

- `data/automation_config.json` — haftalık gün + saat. Mavi haber hattı tek
  haftalık günle sınırlıdır (güncel ayar: Çarşamba 23:21); konu/görsel hattı
  birden fazla haftalık gün kullanabilir.
- Dashboard canlı akışında yalnız aktif `pending/ready/uploading` kayıtlar
  sıralanır. `failed/cancelled` kayıtlar yayın logunda korunur ama sıradaki
  slotu ve canlı anchor kartını bloke etmez.
- **Ancak in-process cron yok**: bu iş şu an harici bir tetikleyiciye bağlı (crontab, launchd, Pi'de systemd timer veya UI'daki "▶ Şimdi çalıştır" butonu).
- **UI tetiği**: `POST /api/automation/run_now` (kind=news|topic) veya `POST /api/news/run_now`.

### 11.1 Toplu üretim dayanıklılığı (`_run_now_bulk`)

- Her tur **ayrı ayrı** `try/except` ile sarılır: bir turun exception atması
  bulk'u durdurmaz, "atlandı" satırına dönüşür ve üretim devam eder.
- Üst üste **3** hata → devre kesici (dış servis düşmüş olabilir). Hiç kart
  üretilemediyse ve sebep hataysa iş başarısız işaretlenir; aksi hâlde kısmi
  başarı **başarıdır** ve özet "`9/10 kart üretildi · 1 hata`" biçiminde raporlanır.
- `no_news` / `no_text` / `no_topic` / `disabled` → aday yok, erken sonlan.
  `no_image` bilinçli olarak bu listede **değildir**: Unsplash geçici boş
  dönebilir, sonraki tur başarılı olabilir.
- Görsel bulunamaması artık exception değil, `{"ok": False, "reason": "no_image"}`
  sonucudur (hem `news_automation` hem `topic_automation` içinde).

### 11.1b Görsel arama sorgusu zenginleştirme (`downloader.enrich_query`)

Stok fotoğraf arşivinde marka/tesis adı yoktur ve arayüz Türkçedir. Bu yüzden
hiçbir sorgu ham hâlde Unsplash'e gitmez; üç adımdan geçer:

1. **Marka/tesis → çekilebilir sahne** — `teamLab` → `immersive digital art
   installation dark room`, `USJ` → `theme park roller coaster`, `JR Pass` →
   `japanese train station platform`. En uzun anahtar kazanır
   (`teamlab planets` > `teamlab`).
2. **Türkçe → İngilizce** — gövde eşlemesiyle ekli sözcükler de çevrilir
   (`bahçesi` → `garden`, `sokakları` → `street`). Çevrilemeyen Türkçe sözcük
   (hâlâ çğıöşü taşıyan) sorguyu kirletmemesi için düşürülür.
3. **Japonya çıpası** — sorguda yer/ülke çıpası yoksa `japan` eklenir. Marka
   eşlemesi şehri yutarsa (`tokyo disneyland`) şehir geri konur. `fuji` bilinçli
   olarak çıpa sayılmaz (tek başına Fujifilm kameraları geliyor).

`build_search_queries` bundan kademeli bir liste üretir (spesifik → `japan
<ana kelime>` → `japan travel` → `japan`). `search_with_fallback` bu kademeyi
**biriktirerek** kullanır: spesifik sorgu az sonuç verirse (portrait filtresi
daralttığı için sık olur) grid daha genel sahneyle 10'a tamamlanır, en alakalı
üstte kalır. İstek kotası (50/saat) için en fazla **3** arama yapılır.

`POST /api/backgrounds/preview` yanıtına `effective_query` ve `tried` eklendi
(additive, sözleşme bozulmadı); dashboard bunu `picker-query-note` şeridinde
gösterir — kullanıcı ne arandığını görür ve gerekirse kendi terimini yazar.
`news_automation._pick_image` de aynı `build_search_queries`'i kullanır, böylece
LLM'den marka adı sızsa bile çekilebilir sahneye çevrilir.

**Ölçüm**: `teamlabs` ham hâlde 3 alakasız sonuç (saat kulesi, portre);
zenginleştirilmiş sorgu 2068 sonuç ve gerçek ışık enstalasyonu fotoğrafları.

### 11.2 Konu tekrarını engelleyen dedup

- **Dört anahtar/kayıt** (`news_automation._dedup_keys`): link id, başlık-link
  şeması, normalize başlık (`t:` önekli), eski `topic_automation` şeması.
  Herhangi biri state'te varsa aday kullanılmış sayılır → aynı konu farklı
  kaynaktan gelse de yakalanır. Normalizasyon Türkçe i/I/İ/ı varyantlarını tek
  harfe indirir ("KONBINI" = "Konbini").
- `used_ids` **sıra korunarak** saklanır (`_ordered_used`); eskiden `list(set)[-CAP:]`
  yazıldığı için cap dolduğunda hangi kaydın düştüğü belirsizdi. `_USED_CAP=800`
  (≈ son 200 içerik, kayıt başına 4 anahtar).
- **Cooldown** (`news_automation.eligible_topics`): havuz tükendiğinde konular
  sessizce yeniden açılmaz. Yalnız `topic_cooldown_days` (varsayılan 45) süresi
  dolan konular, **en eski kullanılan önce** yarışa döner; hiçbiri uygun değilse
  evergreen fazı açık bir uyarıyla atlanır. `topic_automation._pick_topic` aynı
  fonksiyonu kullanır.
- `assets/topic_pool.json` — 57 konu; manzara konularının yanında ulaşım,
  konaklama, tema parkı (USJ / Disneyland / DisneySea / teamLab) ve pratik
  ziyaretçi kuralları başlıkları vardır. Görsel sorguları **marka adı içermez**
  (stok fotoğrafta bulunmaz); testle kilitlidir.

## 12. Kimlik doğrulama
- **Şu an**: yok. Cloudflare Tunnel'a public erişim. LAN + tunnel yeterli sayılıyor (tek kullanıcı).
- **Instagram**: kanal token'ları `config.yaml`'da; Graph API `graph_token` + `ig_user_id`, instagrapi için `username/password/totp_secret/sessionid`.
- **TikTok**: OAuth2 access_token + refresh_token; `POST /api/tiktok/refresh_token` ile yenilenir.

## 13. Yerel depolama & offline destek
- **Uygulama data'sı**: tümü disk. Docker volume ile Pi restart'ında kaybolmaz.
- **Frontend**: PWA manifest + ortak Rotori favicon/apple-touch-icon ailesi. Ancak service worker YOK — offline kullanım tasarlanmamış (kanal içeriği yayın için internet zaten şart).

## 14. Deploy mimarisi

- `deploy.sh` her çalışmada UTC tabanlı benzersiz `DEPLOY_ID` üretir. Docker
  build'i bunu `BUILD_INFO` içine yazar; `/api/version` SemVer build metadata
  biçiminde örneğin `v1.0.2+20260809.230000` döndürür.
- Dashboard statik JavaScript/CSS yanıtları `no-cache, no-store,
  must-revalidate` başlığı taşır; yeni deploy eski tarayıcı veya CDN dosyasıyla
  açılmaz.

```
       Developer Mac (kod düzenleme)
             │  git push
             ▼
       GitHub monorepo main branch
       (mennansevim/japan-trip)
             │  Pi5 SSH: git pull
             ▼
       Pi5:  ~/rotori-app/rotori-social/deploy.sh
             ├─ export GIT_COMMIT + BUILD_DATE
             ├─ docker-compose build --pull
             └─ docker-compose up -d
                     │
                     ▼
             container: rotori-social
             /app/config.yaml (mounted RO)
             /app/data (mounted)
             /app/output (mounted)
             /app/assets (mounted)
                     │
             Cloudflare Tunnel
                     │
             https://api.rotori.app
```

Not: Geriye uyumluluk için Pi'de `~/rotori-social` yolu symlink olarak
`~/rotori-app/rotori-social` dizinine işaret eder.

## 15. Test mimarisi
- **Contract testleri (2026-07-30 itibariyle)** — `tests/` altında pytest + FastAPI TestClient. Kurulum: `pip install -r requirements-dev.txt`.
  - `tests/conftest.py` — TestClient fixture; Ollama HTTP çağrıları monkeypatch ile stub'lanır (gerçek localhost:11434'e çıkmaz).
  - `tests/test_contracts_system.py` — `/api/version`, `/api/status`, `/api/logs` sözleşme kilidi (6 test).
  - `tests/test_contracts_scheduler.py` — `/api/scheduler/queue` enrichment field'ları + `/api/scheduler/run` (2 test).
- **Test kuralı**: hiçbir test gerçek Ollama/OpenAI/Instagram/TikTok/Unsplash çağırmaz.
- **Sonraki hedef**: her router split PR'ında ilgili route grubu için contract test eklenir.

## 16. Yakın zamandaki mimari değişiklikler (git log güncel)
- **95e059e** — "İçeriği Göster": kart oranı 4:5, modal önizleme
- **4f9800e** — `DELETE /api/story/{name}` endpoint'i + UI silme; "Üretilen Kartlar" section'ı kaldırıldı (otomasyon merkezine taşındı)
- **de78294** — Otomasyon Merkezi: sıradaki gönderi yoksa gizle
- **4ce2b35** — Widget: default URL public, secret gitignore
- **f94804f** — Growth features paketi: scheduler + analytics + TikTok publisher + hook A/B
- **7912387** — Docker deployment (Pi5/ARM64) + cross-platform font fallback
- **68ee4c2** — PWA manifest + icon

## 17. Bilinen mimari borçlar
1. **`src/web/app.py` 63 route (2490 satır, azaltılıyor)** — strangler pattern başladı; her PR küçük bir router grubu taşıyor. Sıra: `scheduler.py`, `analytics.py`, `stories.py`, `reels.py`, `approvals.py`, `automation.py`, `publishing.py`.
2. **`index.html` 5.5k+ satır** — build tool'u yok. Bileşen ayırmak istersek migrate maliyeti yüksek. Bugünün ilkesi: **inline'da kal**; ortak utility'ler (`apiFetch`, `withLoading`, `toast`, `openWorkspace`) çıkarıldı.
3. **Otomasyon cron'u dış tetikleyiciye bağımlı** — UI zamanı yönetmiyor. Ya scheduler benzeri thread eklemek ya harici systemd timer'ı belgelemek gerekiyor.
4. **Test kapsaması sınırlı** — sadece system + scheduler contract'ları. Editorial gate skorlaması, path traversal, JobManager davranışları henüz test edilmedi.
5. **Secret rotasyonu manuel** — Instagram Graph token 60 gün, TikTok access_token 24 saat. UI'da otomatik yenileme (Graph token için 746b7f2 commit'inde) başladı, TikTok için endpoint var ama zamanlanmadı.
6. **Kimlik doğrulama YOK** — Cloudflare Tunnel `api.rotori.app` public. Cloudflare Access veya uygulama seviyesinde middleware acilen belgelenmeli. Kritik risk (Karar 4 gündemde).
7. **Scheduler `_save_queue` atomic değil** — `_LOCK` intra-process korur; proses crash → yarım JSON. `.tmp + rename` pattern'e geçirilmeli (news_automation.py:61'deki pattern zaten örnek).
8. **`scheduler_enqueue`/`tiktok_upload`**'da `_safe_reel_path` kullanılmıyor — orta seviye path traversal riski, düzeltilmeli.
