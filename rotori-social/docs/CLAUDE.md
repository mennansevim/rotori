# CLAUDE.md — Kalıcı Proje Belleği

> Bu dosya nadiren değişir. Ürün vizyonu, konvansiyonlar ve ilkelerdir.
> Her yeni oturumda önce **bu dosya**, sonra `ARCHITECTURE.md`, `CURRENT_TASK.md`, `DECISIONS.md` okunur.

## 1. Proje amacı
Arşivdeki ~1000 Japonya videosu ve/veya haftalık RSS haber akışından **otomatik Instagram Reels/Story kartı** üreten, tek başına çalışan bir üretim + yayın hattı. Instagram kanal: **@japonyaruyasi**, TikTok cross-post opsiyonel.

## 2. Ürün vizyonu
- **Tek elden yayıncılık**: içerik seçimi, üretim, editöryal kalite kapısı, planlama ve yayın — hepsi tek dashboard'da.
- **Yerel + ucuz**: Ollama (llava/qwen) + MoviePy + Pillow ile dönmeli; buluta yalnızca Dify workflow, OpenAI editorial ve Instagram Graph API gerekir.
- **Belgesel ton**: kanal on-brand — sansasyon değil, pratik / kültürel / seyahat faydası (Tokyo Cheapo, evergreen konular, GPT editorial gate 30/50 puan).

## 3. Hedef kullanıcılar
- **Birincil**: proje sahibi (`mennansjapan` / `@japonyaruyasi`). Tek-kullanıcılı dashboard.
- **İkincil (ileride)**: küçük bir editör grubu (2-3 kişi) aynı Pi5'i paylaşabilir; oturum modeli yok, host tabanlı ağ güvenliği.

## 4. İş hedefleri
- Haftada minimum 2 Reels + 2 story kartı yayınlamak (güncel otomasyon gün/saatleri `data/automation_config.json` içinde tutulur).
- **Etki metriği**: analytics endpoint (`/api/analytics/overview`) — 30 günlük yayın frekansı, TikTok/Instagram kıyaslaması, hook A/B testi.
- Elle iş yükünü %90 azaltmak: kaynak videoyu seç → otomatik metadata + kurgu planı + render + caption + yayın kuyruğu.

## 5. Teknoloji yığını
| Katman | Seçim | Neden |
|---|---|---|
| Vision LLM | Ollama `llava:7b` | Yerel etiketleme, frame özeti |
| Text LLM (kurgu) | Dify workflow → Ollama `qwen2.5:3b` | Türkçe kurgu, deterministik parametreler |
| Text LLM (editorial) | OpenAI `gpt-4o-mini` | Kalite kapısı, caption, editorial system prompt |
| Render (video) | MoviePy 2.2.1 + ffmpeg | 9:16 Reels çıkışı |
| Render (kart) | PIL/Pillow 11-12 | 1080×1350 (4:5) story kartı |
| Web API | FastAPI + Uvicorn | `src/web/app.py`, 66 route |
| Frontend | Tek dosya SPA — `src/web/static/index.html` (~5.5k satır, vanilla JS + inline CSS) | Bağımlılık yok, PWA manifest |
| Feed | `feedparser` (Tokyo Cheapo, SoraNews24, Nippon.com, Japan Today) | Haber akışı |
| Publish | Instagram Graph API (birincil), `instagrapi` (yedek/draft), TikTok Content Posting API | Kanal @japonyaruyasi |
| Deploy | Docker Compose → Raspberry Pi 5 (ARM64) + Cloudflare Tunnel → `api.rotori.app` | 3090:8420 |
| Runtime | Python 3.11-slim | Uvicorn, TZ Europe/Istanbul |

## 6. Klasör yapısı (kaynak referansı — `ls`'den birebir)
```
rotori-social/
├── src/
│   ├── config.py                 # dataclass config loader — SchedulerCfg dahil 13 cfg
│   ├── step1_analyze.py          # llava vision → data/metadata.csv
│   ├── step2_group.py            # metadata → mekan grupları
│   ├── step3_dify.py             # Dify workflow → data/kurgu_planlari/*_final.json
│   ├── step4_render.py           # MoviePy → output/reels/*.mp4
│   ├── batch_pipeline.py         # tüm mekanlar için batch üretim
│   ├── prompt_pipeline.py        # tek prompttan ucuca pipeline
│   ├── story_generator.py        # 1080×1350 kart render (PIL)
│   ├── news_automation.py        # RSS + editorial gate → kart
│   ├── topic_automation.py       # evergreen topic pool → kart
│   ├── editorial.py              # GPT editorial prompt + kalite kapısı
│   ├── downloader.py             # Unsplash arka plan
│   ├── suggestions.py            # anasayfa "kaynak öner"
│   ├── analytics.py              # 30 günlük istatistik
│   ├── scheduler.py              # yayın kuyruğu + background thread
│   ├── instagram_graph.py        # Meta Graph API (resmi)
│   ├── instagram_publisher.py    # instagrapi (yedek, draft)
│   ├── tiktok_publisher.py       # TikTok Content Posting API
│   ├── ollama_client.py          # HTTP → localhost:11434
│   ├── openai_client.py          # OpenAI SDK wrapper
│   ├── persona.py                # kanal karakter prompt'u
│   ├── labeling.py               # etiket normalizasyon + skorlama
│   ├── analyze_pipeline.py       # step1+2 orchestrator
│   ├── reel_maker.py             # tek reel üret (batch olmadan)
│   ├── mac_notifier.py           # macOS notification (dev only)
│   ├── utils/{ffprobe,logging}.py
│   └── web/
│       ├── app.py                # 2490 satır FastAPI; router'larla toplam 66 route
│       ├── jobs.py               # subprocess/thread job manager + log bridge
│       └── static/{index.html,manifest.json,icons/rotori-icon-*.png}
├── config.yaml                   # SECRET'lı, gitignored — plaintext token/pw
├── config.yaml.example           # şablon
├── data/                         # runtime state (çoğu gitignored)
│   ├── metadata.csv              # step1 output
│   ├── kurgu_planlari/*.json     # step3 output
│   ├── automation_config.json    # haber/konu haftalık zamanlama
│   ├── scheduler_queue.json      # (varsa) yayın kuyruğu
│   ├── instagram_uploads.jsonl   # yayın log'u
│   └── news_automation/,topic_automation/,cleaned/
├── output/
│   ├── reels/*.mp4               # ana render çıktısı (gitignored)
│   ├── stories/*.jpg             # kart render (gitignored)
│   └── ready_to_publish/         # onaylananlar
├── assets/
│   ├── fonts/                    # Impact, Arial, DejaVu (Docker fallback)
│   ├── story_backgrounds/        # Unsplash cache
│   ├── topic_pool.json           # evergreen konu havuzu
│   └── logo_japonya_ruyasi.png
├── knowledge/                    # editöryel kurallar (LLM'e sunulur)
├── dify/reels_kurgu_planlayici.yml   # Dify DSL export
├── scripts/                      # pull_models, run_pipeline, run_web
├── docs/                         # BU KLASÖR — kalıcı bellek
├── Dockerfile, docker-compose.yml, deploy.sh
└── VERSION                       # semver, elle bump — footer badge'e basılır
```

## 7. Bağımlılıklar (requirements.txt — birebir)
- `requests`, `pyyaml`, `tqdm`, `pandas` — temel
- `moviepy>=2.2.1` (Pillow<12 pinliyor)
- `Pillow>=11,<12` (base) → Docker'da `--no-deps` ile 12.2'ye yükselir (instagrapi uyumu)
- `imageio-ffmpeg`, `numpy`
- `fastapi`, `uvicorn[standard]`, `python-multipart`
- `feedparser` — RSS
- `instagrapi` — sadece Docker'da (`--no-deps` iki aşamalı kurulum, bkz. `Dockerfile`)

## 8. Mimari ilkeler
1. **Tek yönlü veri akışı** — `raw video → step1 → step2 → step3 → step4 → output/reels`. Adımlar arası state yalnız disk (CSV/JSON), bellek paylaşımı yok.
2. **Her adım CLI + kütüphane** — `python -m src.step3_dify` doğrudan çalışır; `src/web/jobs.py` bunu subprocess veya callable olarak sarar.
3. **In-process job manager** — uzun işler `JobManager.start_callable/start_step`; canlı log akışı log handler bridge ile FastAPI'ye.
4. **Config = dataclass** — `src/config.py` her cfg için typed dataclass, `load_config()` YAML→nesne. Opsiyonel bölümler (`scheduler`, `tiktok`, `instagram`) `None` dönebilir; kullanıcı kodu `if cfg.scheduler` ile korunur.
5. **UI = tek dosya** — `index.html` ~5.5k satır tek dosya. `withLoading(btn, fn)` gibi utility'ler global, ES modül kullanılmıyor. Tarayıcı cache'i için sürüm anahtarı = git commit hash (footer).
6. **Idempotent yayın** — `instagram_uploads.jsonl` ve `scheduler_queue.json` dedup kaynak.

## 9. Kodlama konvansiyonları
- **Python**: `from __future__ import annotations` her modülde; type hints ana kamu API'lerinde; dataclass tercih edilir.
- **Modüller**: fonksiyon-öncelikli. Sınıflar sadece durum tutmak gerekiyorsa (`JobManager`, `OllamaClient`).
- **İç import sırası**: stdlib → 3rd party → `src.*`. `src` içi importlar tam yol (`from src.config import Config`).
- **Loglama**: `src.utils.logging.get_logger("modül_adı")`. `print()` yok.
- **Türkçe yorumlar** — bilinçli tercih: mimar Türkçe düşünüyor, çok satırlı module docstring'ler Türkçe kısa özet.
- **Emoji log seviyeleri**: `✓` ok, `✖` err, `⚠` warn, `⏳` progress, `📥` download, `📤` publish.
- **Buton stilleri (frontend)**: `button.primary`, `button.ghost`, `button.danger`, `button.sm`, `button.ig`, `.story-btn`, `.action-card`. Loading state = `is-loading` class (global helper).

## 10. İsimlendirme
- **Reel dosya adı**: `<mekan_slug>_<uid>.mp4` (bkz. `docs/isimlendirme_rehberi.md`).
- **Kurgu planı**: `<mekan_slug>_final.json` (`kurgu_json` içeriği + `aciklama`, `hashtagler`, `mekan_etiketi`).
- **Story kartı**: `<konu_slug>_<timestamp>.jpg` + eşleşen `.txt` (Instagram caption) + `.json` (sidecar meta).
- **API route**: `/api/<kaynak>/<eylem>` — `/api/story/generate`, `/api/reels/make`, `/api/scheduler/queue`. Path param'da isim = dosya adı (URL-escaped).

## 11. Durum yönetimi
- **Disk** birinci ve yalnız kaynak: `data/*.csv`, `data/*.json`, `data/*.jsonl`, `output/**`.
- **Bellek**: `JobManager.state` (job durumu, canlı log tamponu), `_src_cache` (dosya sayımı, 60s TTL) — hepsi in-process, restart'ta kaybolur, tekrar disk'ten hesaplanır.
- **Yayın log'u**: `instagram_uploads.jsonl`, `tiktok_uploads.jsonl` (append-only, JSON Lines).
- **Otomasyon durumu**: `data/news_automation/state.json`, `data/topic_automation/state.json` — dedup için kullanılan haberler/konular.

## 12. Hata yönetimi felsefesi
- **API katmanı**: iş kuralı hataları `HTTPException(400/404/409/500)` + Türkçe `detail`.
- **Job katmanı**: `try/except` her uzun işi sarar; hata `manager.state["error"]` ve toast'a düşer.
- **Editorial gate**: 30/50 puan altı = retry, timeout `NEWS_GATE_TIMEOUT_SEC` env (default 300s).
- **Config eksikse graceful**: `cfg.scheduler=None`, `cfg.tiktok=None`, `cfg.instagram=None` durumları hepsi tolere edilmeli; UI ilgili butonu disable etmeli, endpoint 400 dönmemeli.
- **Prompt injection** yok — LLM çıktıları her zaman JSON schema ile parse (`kurgu_json` şeması editorial gate'ten geçer).

## 13. Performans hedefleri
- **Step1 (llava)**: ~15-20s/frame (Ollama Mac M-serisi), toplu 60-90 dk / 100 video.
- **Step3 (Dify)**: ~5-15s/plan, concurrency 2.
- **Step4 (render)**: ~30-60s/reel (9:16, ~15s).
- **Web sayfa boyutu**: `index.html` tek dosya <500KB, ilk boyanma <500ms.
- **Background scheduler**: 60s check interval; günde max 2 post default.

## 14. Güvenlik kuralları
- **`config.yaml` gitignored** — plain-text token/password/sessionid içerir. Repo'ya asla girmez.
- **`config.yaml.example`** placeholder değerlerle takip edilir (`YOUR_*`, `sk-YOUR_*`).
- **Docker volume `:ro`** — container config'i değiştiremez.
- **Cloudflare Tunnel** ön yüzü, public 3090 port yok. İçeride sadece Pi LAN.
- **Session/2FA**: Instagram username/password + TOTP secret + fallback `sessionid` cookie. `data/instagram_session.json` cache'lenir, gitignored.
- **Dosya yükleme**: `POST /api/story/upload_bg` sadece resim MIME, boyut sınırı FastAPI default.

## 15. Tasarım felsefesi
- **Dark mode default**: `--bg #0b0d12`, aksan `#ff3860` (Japon bayrağı kırmızısı türevi).
- **Bilgi yoğun ama sakin** — kart grid'i (Otomasyon Merkezi), sağ sabit "Canlı Süreç" footer'ı.
- **Butonlar durum konuşur**: disabled + tooltip her zaman hangi config eksik açıklar (`title="config.yaml → instagram bölümünü doldur"`).
- **Navigasyon iş akışını konuşur**: ana menü teknik modüller yerine `Bugün → Hazırlık → Yayına Hazır → Otomasyon` sırasını izler; ayrıntılar ilgili görünüm içinde kalır.
- **Türkçe UI, İngilizce yalnız 3rd-party etiketlerinde** (Instagram, TikTok, Drive).
- **PWA**: manifest + ortak Rotori app icon ailesi; iOS ana ekrandan Rotori Social olarak açılır.

## 16. Definition of Done
Bir özellik "bitti" sayılır ise:
1. **Kaynak kodu commit'lendi** — küçük, tanımlanabilir mesajla (Türkçe, imperatif).
2. **Config gerektiriyorsa `config.yaml.example` güncellendi.**
3. **UI değişikliği varsa hem golden path hem "config yok" senaryosu manuel test edildi** (button loading, toast, disable state).
4. **`docs/ARCHITECTURE.md` etkilendiyse aynı PR'da güncellendi.**
5. **`docs/DECISIONS.md`'e mimari karar eklendi** (yeni bağımlılık, endpoint sözleşmesi, iş kuralı).
6. **`docs/CURRENT_TASK.md`** kapatıldı.
7. **Docker deploy edilecekse**: `deploy.sh` çalıştırıldı ve `curl https://api.rotori.app/api/version` beklenen VERSION'ı döndü.
8. **Secret sızmadı**: `git diff` review, `config.yaml` staged değil.

## 17. Deploy pipeline
- **Yerel Mac dev**: `.venv/bin/uvicorn src.web.app:app --reload --port 8000` (dev).
- **Prod Pi5**: `cd ~/rotori-app/rotori-social && ./deploy.sh` — git commit env → `docker-compose build && up -d`. Container `rotori-social:3090` → Cloudflare Tunnel → `api.rotori.app`.
- **Persist edilen volumeler**: `config.yaml:ro`, `data/`, `output/`, `assets/`.
- **VERSION**: elle `VERSION` dosyası bump, `BUILD_INFO` deploy sırasında yazılır (commit hash + tarih).

## 18. Dış bağımlılıklar
- **Ollama**: `localhost:11434` (Mac dev), container'dan `host.docker.internal:11434` (Pi5'te de host'ta).
- **Dify**: `http://192.168.1.60:5001` (Pi5 LAN), workflow app-key config'de.
- **OpenAI**: `api.openai.com`.
- **Instagram Graph**: `graph.instagram.com` + `graph.facebook.com`.
- **Unsplash**: `api.unsplash.com` (Free tier 50 req/hr).
- **TikTok**: `open.tiktokapis.com/v2/`.

## 19. Referans dokümanlar (repo içi)
- [ARCHITECTURE.md](ARCHITECTURE.md) — güncel mimari
- [CURRENT_TASK.md](CURRENT_TASK.md) — bugünkü iş
- [DECISIONS.md](DECISIONS.md) — mimari karar log'u
- [docs/isimlendirme_rehberi.md](isimlendirme_rehberi.md) — dosya/slug kuralları
- [../README.md](../README.md) — dış kullanıcı kurulumu
- [../knowledge/japonya_tuyolar.md](../knowledge/japonya_tuyolar.md) — LLM'e verilen editöryel referans
