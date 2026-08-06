from __future__ import annotations

import json
import shutil
import time
from pathlib import Path
from threading import Event
from typing import Any, Callable
from urllib.parse import quote

import requests
from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from src.config import Config, load_config
from src.utils.logging import get_logger
from src.web import dependencies as deps
from src.web.jobs import JobManager
from src.web.routers import dashboard as dashboard_router
from src.web.routers import system as system_router

log = get_logger("web")

VIDEO_EXT = {".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm"}

cfg: Config = load_config()
manager = JobManager(cfg.project_root)

# Router'lar bu iki singleton'a dependencies modülü üzerinden erişir.
# Bkz. docs/DECISIONS.md — Karar 6 (strangler pattern router split).
deps.set_runtime(cfg, manager)

STATIC_DIR = Path(__file__).resolve().parent / "static"

app = FastAPI(title="Japan Reels Maker", docs_url=None, redoc_url=None)

# system.py: /api/version, /api/status, /api/logs — sözleşmesi contract test
# ile kilitlidir (tests/test_contracts_system.py).
app.include_router(system_router.router)

# dashboard.py: /api/dashboard/* — yeni tasarım UI'ının okuduğu toplu durum.
# Salt-okunur aggregation; yazma işlemleri mevcut endpoint'lerden yürür.
app.include_router(dashboard_router.router)


# Üretilen medya + kareler (StaticFiles HTTP Range destekler → video seek çalışır)
app.mount("/media/reels", StaticFiles(directory=str(cfg.paths.output_dir)), name="reels")
app.mount("/media/ready", StaticFiles(directory=str(cfg.paths.ready_dir)), name="ready")
app.mount("/media/frames", StaticFiles(directory=str(cfg.paths.frames_dir)), name="frames")
if cfg.stories:
    app.mount("/media/stories", StaticFiles(directory=str(cfg.stories.output_dir)), name="stories")
    # pending_approval klasörünü baştan yarat — mount öncesi olması lazım
    (cfg.stories.output_dir / "pending_approval").mkdir(parents=True, exist_ok=True)
    if cfg.stories.backgrounds_dir:
        cfg.stories.backgrounds_dir.mkdir(parents=True, exist_ok=True)
        app.mount("/media/backgrounds",
                  StaticFiles(directory=str(cfg.stories.backgrounds_dir)),
                  name="backgrounds")
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


# ---------------------------------------------------------------------------
# Startup: scheduler background thread
# ---------------------------------------------------------------------------
@app.on_event("startup")
def _start_scheduler() -> None:
    if cfg.scheduler and cfg.scheduler.enabled:
        from src import scheduler as sched_mod
        sched_mod.start_background_scheduler(
            project_root=cfg.project_root,
            output_dir=cfg.paths.output_dir,
            cfg_any=cfg,
            queue_file=cfg.scheduler.queue_file,
            auto_upload=cfg.scheduler.auto_upload,
            check_interval_sn=cfg.scheduler.check_interval_sn,
        )
        log.info("Reels Scheduler başlatıldı ✓")



# NOT: _source_video_count / _metadata_count / _glob_count / _ollama_ok
# yardımcıları ve /api/status, /api/logs, /api/version endpoint'leri
# src/web/routers/system.py'ye taşındı. Sözleşme aynen aynıdır.


# ---------------- modeller ----------------
class PromptOverrides(BaseModel):
    cta: str = ""
    baslik: str = ""
    hashtagler: str = ""  # boşlukla ayrılmış tag listesi


class PromptRequest(BaseModel):
    prompt: str = Field(..., min_length=3)
    hook: str = ""
    sure_modu: str = "orta"  # kisa | orta | uzun
    overrides: PromptOverrides = Field(default_factory=PromptOverrides)


class AnalyzeRequest(BaseModel):
    enrich: bool = True   # sahne özetlerini de üret


class BatchRequest(BaseModel):
    limit: int | None = None
    overwrite: bool = False


class StoryRequest(BaseModel):
    konu: str = Field(..., min_length=5)
    count: int = 3


class BackgroundDownloadRequest(BaseModel):
    query: str = ""       # boşsa config queries; doluysa sadece bu sorgu
    count: int = 8        # tek sorgu modunda kaç görsel


class BackgroundPreviewRequest(BaseModel):
    query: str = Field(..., min_length=2)
    count: int = 10
    page: int = 1     # Unsplash search sayfası (Farklı Sonuçlar için)


class BackgroundSaveRequest(BaseModel):
    query: str = Field(..., min_length=2)
    items: list[dict[str, Any]] = Field(..., min_length=1)


class RenderFromSelectionRequest(BaseModel):
    query: str = ""            # dosya adı slug için (opsiyonel)
    background_url: str        # Unsplash regular URL
    background_id: str         # Unsplash photo ID (cache anahtarı)
    photographer: str = ""     # attribution
    baslik: str = ""           # başlık alanı UI'dan kaldırıldı — opsiyonel
    aciklama: str = Field(..., min_length=5, max_length=280)
    ust_tag: str = "GEZİ DEFTERİ"   # sol üst köşedeki küçük sarı rozet
    post_caption: str = ""     # Instagram post caption — üretilirse JPG yanına
                                #   aynı basename ile .txt olarak kaydedilir
    vurgu_kelimeler: list[str] = []   # (yeni tasarımda kullanılmıyor — bwd compat)
    style: str = "style2"            # style1: yeni editöryel · style2: eski wordmark


class AICaptionRequest(BaseModel):
    konu: str = Field(..., min_length=2)
    mode: str = "subtitle"   # "title" | "subtitle"


class ReelsCaptionRequest(BaseModel):
    konu: str = Field(..., min_length=2)          # video konusu, örn "Nara geyikleri"
    ton: str = "samimi"                            # samimi | merak | bilgi
    ekstra: str = ""                               # kullanıcının eklemek istediği detay


class ExpandCaptionRequest(BaseModel):
    aciklama: str = Field(..., min_length=8)
    baslik: str = ""


class StoryUpdateRequest(BaseModel):
    aciklama: str = Field(..., min_length=5, max_length=280)
    ust_tag: str = "GEZİ DEFTERİ"
    post_caption: str = ""


class VaryTextRequest(BaseModel):
    text: str = Field(..., min_length=8)


class AIFromImageRequest(BaseModel):
    image_url: str = Field(..., min_length=8)   # public URL veya data: URI
    konu: str = ""   # kullanıcının arattığı kelime — vision bu konuya odaklanır


class AIFromTextRequest(BaseModel):
    konu: str = Field(..., min_length=2, max_length=200)   # kullanıcının yazdığı konu


# ---------------- endpoint'ler ----------------
@app.get("/")
def index(request: Request) -> FileResponse:
    """Ana sayfa: yeni İçerik Stüdyosu dashboard'u.

    `?view=widget` ile açılırsa eski Stüdyo arayüzü (studio.html) döner —
    masaüstü widget'ı bu moda bağlıdır, bozulmaması için korunur.
    """
    if request.query_params.get("view") == "widget":
        return FileResponse(
            str(STATIC_DIR / "studio.html"),
            headers={"Cache-Control": "no-cache, no-store, must-revalidate",
                     "Pragma": "no-cache", "Expires": "0"},
        )
    return FileResponse(
        str(STATIC_DIR / "dashboard" / "index.html"),
        headers={"Cache-Control": "no-cache, no-store, must-revalidate",
                 "Pragma": "no-cache", "Expires": "0"},
    )


@app.get("/studio")
def studio_index() -> FileResponse:
    """Eski Stüdyo arayüzü — widget + geriye dönük uyumluluk için tutuluyor."""
    return FileResponse(
        str(STATIC_DIR / "studio.html"),
        headers={"Cache-Control": "no-cache"},
    )


# /api/status → src/web/routers/system.py


@app.post("/api/generate/prompt")
def generate_prompt(req: PromptRequest) -> dict[str, Any]:
    prompt = req.prompt.strip()
    if not prompt:
        raise HTTPException(status_code=400, detail="prompt gerekli.")
    if req.sure_modu not in ("kisa", "orta", "uzun"):
        raise HTTPException(status_code=400, detail="sure_modu: kisa|orta|uzun")

    from src import prompt_pipeline

    label_ozet = prompt[:60] + ("…" if len(prompt) > 60 else "")

    def target(emit: Callable[..., None], cancel: Event) -> None:
        prompt_pipeline.run_from_prompt(
            cfg=cfg,
            prompt=prompt,
            hook=req.hook,
            sure_modu=req.sure_modu,
            overrides=req.overrides.model_dump(),
            emit=emit,
            cancel=cancel,
        )

    try:
        manager.start_callable(f"Prompt Reels: {label_ozet}", target)
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"ok": True, "job": manager.state}


@app.get("/api/suggestions")
def suggestions() -> dict[str, Any]:
    """Mevcut arşiv videolarına göre hazır Reels fikirleri döndür."""
    from src.suggestions import build_suggestions
    return {"suggestions": build_suggestions(cfg)}


@app.post("/api/analyze")
def analyze(req: AnalyzeRequest) -> dict[str, Any]:
    """Yeni video keşfi + etiketleme + (opsiyonel) sahne özeti üretimi."""
    from src import analyze_pipeline

    def target(emit: Callable[..., None], cancel_ev: Event) -> None:
        analyze_pipeline.run_analyze(cfg, emit, cancel_ev, enrich=req.enrich)

    label = "Videoları Analiz Et" + (" (sahne özetiyle)" if req.enrich else "")
    try:
        manager.start_callable(label, target)
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"ok": True, "job": manager.state}


@app.post("/api/story/generate")
def story_generate(req: StoryRequest) -> dict[str, Any]:
    """Konudan 3 farklı Instagram Story kartı üret. GPT + PIL, senkron çalışır
    (~5sn) — küçük iş, JobManager gerekmez."""
    if cfg.stories is None:
        raise HTTPException(status_code=400, detail="stories config yok.")
    if cfg.openai is None:
        raise HTTPException(status_code=400,
                            detail="OpenAI key gerekli. config.yaml → openai.api_key.")

    from src import story_generator
    try:
        cards = story_generator.run_story_generation(cfg, req.konu, count=req.count)
    except (RuntimeError, ValueError) as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    # her kartın URL'sini oluştur
    for c in cards:
        c["url"] = f"/media/stories/{quote(c['file'])}"
    return {"ok": True, "cards": cards, "konu": req.konu}


@app.post("/api/backgrounds/download")
def backgrounds_download(req: BackgroundDownloadRequest = BackgroundDownloadRequest()) -> dict[str, Any]:
    """Unsplash'ten görsel indirir.
    query verilirse: sadece o sorgu için count adet.
    query boş: config.unsplash.queries listesi × per_query."""
    if cfg.unsplash is None:
        raise HTTPException(status_code=400,
                            detail="Unsplash config yok. config.yaml → unsplash.access_key doldur.")
    if cfg.stories is None or cfg.stories.backgrounds_dir is None:
        raise HTTPException(status_code=400,
                            detail="stories.backgrounds_dir yok.")

    from src import downloader

    def target(emit: Callable[..., None], cancel_ev: Event) -> None:
        downloader.download_backgrounds(cfg, emit, cancel_ev,
                                        custom_query=req.query,
                                        custom_count=req.count if req.query else None)

    label = f"Unsplash: '{req.query}'" if req.query else "Unsplash toplu indirici"
    try:
        manager.start_callable(label, target)
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"ok": True, "job": manager.state}


@app.post("/api/backgrounds/preview")
def backgrounds_preview(req: BackgroundPreviewRequest) -> dict[str, Any]:
    """Sorguya göre 10 görsel URL'i döndür (indirmez, kullanıcı modal'da seçsin)."""
    if cfg.unsplash is None:
        raise HTTPException(status_code=400, detail="Unsplash config yok.")
    from src import downloader
    try:
        results = downloader.search_only(cfg, req.query, count=req.count, page=req.page)
    except requests.HTTPError as exc:
        raise HTTPException(status_code=exc.response.status_code,
                            detail=f"Unsplash hatası: {exc.response.text[:200]}") from exc
    except requests.RequestException as exc:
        raise HTTPException(status_code=502, detail=f"Unsplash erişim hatası: {exc}") from exc
    return {"query": req.query, "results": results}


@app.post("/api/backgrounds/save")
def backgrounds_save(req: BackgroundSaveRequest) -> dict[str, Any]:
    """Modal'da kullanıcının seçtiği görselleri assets/story_backgrounds'a indir."""
    if cfg.unsplash is None:
        raise HTTPException(status_code=400, detail="Unsplash config yok.")
    if cfg.stories is None or cfg.stories.backgrounds_dir is None:
        raise HTTPException(status_code=400, detail="stories.backgrounds_dir yok.")

    from src import downloader

    def target(emit: Callable[..., None], cancel_ev: Event) -> None:
        downloader.download_selected(cfg, req.query, req.items, emit, cancel_ev)

    try:
        manager.start_callable(f"Unsplash seçim indir: '{req.query}' × {len(req.items)}", target)
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"ok": True, "job": manager.state}


@app.get("/api/backgrounds/status")
def backgrounds_status() -> dict[str, Any]:
    """Kaç arka plan görseli var, Unsplash config'i aktif mi?"""
    count = 0
    if cfg.stories and cfg.stories.backgrounds_dir and cfg.stories.backgrounds_dir.exists():
        exts = {".jpg", ".jpeg", ".png", ".webp"}
        count = sum(1 for p in cfg.stories.backgrounds_dir.iterdir()
                    if p.is_file() and p.suffix.lower() in exts)
    return {
        "count": count,
        "unsplash_enabled": cfg.unsplash is not None,
        "queries": cfg.unsplash.queries if cfg.unsplash else [],
    }


# === Ortak Türkçe üslup kılavuzu (few-shot) ===
# Kart metni üreten tüm prompt'lara (ai_caption / vision / vary) enjekte edilir.
# Amaç: ansiklopedik/belgesel, klişesiz, genel-bilgi verici, kusursuz Türkçe.
_TR_STYLE = (
    "DİL VE ÜSLUP KILAVUZU (mutlaka uygula):\n"
    "- Ansiklopedik/belgesel Türkçe: nesnel, akıcı, kusursuz dilbilgisi ve "
    "doğal cümle kurulumu. Çeviri kokan, devrik veya bozuk cümle YOK.\n"
    "- 3. şahıs, GENEL BİLGİ kipi: '…dır', '…olarak bilinir', '…kabul edilir', "
    "'…yer alır', '…kullanılır', '…dayanır'.\n"
    "- Her cümle tek bir net fikir taşısın; kısa-orta uzunluk. Bağlaç yığma yok.\n"
    "- SOMUT bilgi ver: nesnenin ne olduğu, nerede bulunduğu, işlevi, tarihsel "
    "veya kültürel bağlamı. 'Ne' ve 'neden'i açıkla; genel geçer laf etme.\n"
    "- KLİŞE/PAZARLAMA dili KESİN YASAK. Şu ifadeleri KULLANMA: 'büyüleyici', "
    "'eşsiz', 'muhteşem', 'göz kamaştırıcı', 'unutulmaz', 'huzur dolu', "
    "'dinginlik sunar', 'atmosfer sunar', 'ziyaretçileri kendine çeker', "
    "'keşfetmeye değer', 'adeta'. Sıfat yığma, duygu sömürme yok.\n"
    "- 2. şahıs/emir YASAK: 'siz', 'yapın', 'gidin', 'unutmayın', 'görmelisiniz'.\n"
    "- Uydurma sayı/tarih/özel isim YASAK; emin değilsen genel ifade kullan.\n\n"
    "İYİ örnekler (BU kalite ve tonu hedefle):\n"
    "✓ Torii kapıları, Şinto tapınaklarının girişini işaretler ve kutsal alanı "
    "dünyevi alandan ayırır.\n"
    "✓ Konbini adı verilen 24 saat açık marketler, Japonya'da alışverişin yanı "
    "sıra fatura ödeme ve kargo gönderme gibi işlemlerin de yapıldığı yerlerdir.\n"
    "✓ Zen bahçeleri, çakıl ve kayalarla oluşturulan soyut düzenlemeleriyle "
    "Budist meditasyon geleneğine dayanır.\n"
    "✓ Shinkansen, Japonya'nın yüksek hızlı tren ağıdır ve şehirlerarası "
    "ulaşımın önemli bir bölümünü karşılar.\n"
    "✓ Kimono, geleneksel Japon giysisidir; deseni ve kumaşı giyen kişinin "
    "yaşına, medeni durumuna ve mevsime göre değişir.\n\n"
    "KÖTÜ örnekler (bu tondan KESİNLİKLE KAÇIN):\n"
    "✗ Japon şehirlerinin gece manzaraları büyüleyici bir atmosfer sunar. "
    "(içi boş klişe, bilgi yok)\n"
    "✗ Bu eşsiz deneyim sizi kendine hayran bırakacak. (pazarlama + 2. şahıs)\n"
    "✗ Huzurun tadını çıkarabileceğiniz muhteşem bir yer. (klişe + 2. şahıs)"
)


_AI_CAPTION_SYSTEM = (
    "Sen @japonyaruyasi Instagram kanalı için hap bilgi kartı metinleri üreten "
    "bir editörsün. Yazıların bir ansiklopedi maddesi veya belgesel anlatımı "
    "gibi nesnel, akıcı ve bilgilendiricidir. Türkçen kusursuzdur. Kullanıcıya "
    "seslenmez, öğüt/emir vermez, pazarlama/klişe dili kullanmazsın. Uydurma "
    "sayı/tarih/fiyat YASAK. Yanıt SADECE istenen metin — açıklama, tırnak YOK."
)


def _ai_caption_prompt(konu: str, mode: str) -> str:
    if mode == "title":
        return (
            f"Konu: {konu}\n\n"
            "Bu konuya uygun bir Instagram Story BAŞLIĞI üret.\n"
            "Kurallar:\n"
            "- MAX 4 KELİME\n"
            "- Büyük harflerle (UPPERCASE)\n"
            "- Vurucu, konuyu tanıtan (Impact font tarzı)\n"
            "- Türkçe, belgesel etiket tonunda — emir kipi (yapın/yemeyin) YASAK\n"
            "- Örnek: 'FUSHIMI İNARİ TAPINAĞI', 'JAPONYA'DA MENOPOZ', "
            "'SHINKANSEN'İN SIRRI', 'KONBINI KÜLTÜRÜ'\n\n"
            "Yalnızca başlık metnini yaz, başka bir şey yazma."
        )
    # subtitle → kartın ana metni
    return (
        f"KONU: {konu}\n\n"
        "Bu konu hakkında, bir Instagram bilgi kartının ana metnini yaz.\n\n"
        f"{_TR_STYLE}\n\n"
        "BİÇİM (kesin sınır):\n"
        "- EN FAZLA 2 cümle. 3. cümleyi ASLA yazma.\n"
        "- Toplam en fazla 28 kelime. Uzun paragraf YOK.\n"
        "- Konuyu tanıt + en çarpıcı SOMUT bilgiyi ver (ne olduğu, işlevi, "
        "kültürel/tarihsel bağlamı). Şehir/örnek listeleme yapma.\n"
        "- Emoji YOK (kart üstüne yerleşecek).\n\n"
        "Yalnızca metni yaz — başlık, tırnak, etiket veya prefix EKLEME."
    )


@app.post("/api/story/ai_caption")
def story_ai_caption(req: AICaptionRequest) -> dict[str, Any]:
    """Bir konudan Japon gezi rehberi tonunda başlık veya alt açıklama üret."""
    if cfg.openai is None:
        raise HTTPException(status_code=400,
                            detail="OpenAI key gerekli. config.yaml → openai.api_key.")
    mode = req.mode if req.mode in ("title", "subtitle") else "subtitle"

    from src.openai_client import OpenAIClient
    oai = OpenAIClient.from_config(cfg)
    if oai is None:
        raise HTTPException(status_code=400, detail="OpenAI client oluşturulamadı.")

    try:
        text = oai.chat_text(
            _AI_CAPTION_SYSTEM,
            _ai_caption_prompt(req.konu, mode),
            temperature=0.7,
            max_tokens=120 if mode == "subtitle" else 40,
        )
    except (RuntimeError, ValueError) as exc:
        raise HTTPException(status_code=502, detail=f"OpenAI hatası: {exc}") from exc

    # temiz normalize: tırnak, emoji, prefix "Başlık:" gibi kalıntılar
    text = text.strip().strip('"').strip("'").strip()
    # "başlık:", "alt açıklama:" gibi label kalıntıları
    for prefix in ("başlık:", "alt açıklama:", "açıklama:", "title:", "subtitle:"):
        if text.lower().startswith(prefix):
            text = text[len(prefix):].strip()
    if mode == "title":
        # Türkçe-aware uppercase: 'i'yi 'İ' yapmak için .upper()'dan önce dönüştür
        text = text.replace("i", "İ").replace("ı", "I").upper()

    return {"text": text, "mode": mode}


_EXPAND_CAPTION_SYSTEM = (
    "Sen @japonyaruyasi Instagram kanalı için belgesel/ansiklopedik tonda post "
    "caption'ı yazan bir editörsün. Bir hook metnini objektif ve bilgilendirici "
    "bir Instagram açıklamasına genişletirsin. Türkçen kusursuz ve akıcıdır; "
    "her madde SOMUT bilgi taşır. Klişe/pazarlama dili ('büyüleyici', 'eşsiz', "
    "'muhteşem', 'atmosfer sunar'), emir/rica ve 2. şahıs hitap KULLANMAZSIN. "
    "Uydurma sayı/tarih/fiyat YASAK — bilmediğini yazma."
)


def _expand_caption_prompt(baslik: str, aciklama: str) -> str:
    baslik_line = f"Kart başlığı: {baslik.strip()}\n" if baslik.strip() else ""
    return (
        f"{baslik_line}"
        f"Kart alt açıklaması (kısa hook):\n\"{aciklama.strip()}\"\n\n"
        "Bunu Instagram post CAPTION'ına genişlet. TON: BELGESEL / ENFORMATİF.\n\n"
        "FORMAT:\n"
        "1. AÇILIŞ (1 cümle): konuyu tanıtan objektif fact + 1-2 emoji.\n"
        "   Örnek: '🇯🇵 Fushimi Inari-taisha, Kyoto'nun güneyinde 1300 yıllık bir Şinto tapınağıdır.'\n"
        "2. DETAYLAR (3-5 madde): her satır emoji ile başlar (🗾 🍜 ⛩️ 🚄 🎋 "
        "🌸 💴 🎌 vb.), 1 kısa cümle. Her madde SOMUT BİLGİ (tarih, coğrafya, "
        "kültürel gözlem, karşılaştırma, istatistik).\n"
        "3. KAPANIŞ (1 cümle): kısa call-to-action — 'Kaydet 📌', 'Detay için "
        "takipte kal 🇯🇵' gibi Instagram engagement mekaniği. Öğüt YOK.\n"
        "4. Boş satır, sonra 10-15 hashtag Türkçe/İngilizce karışık: #japonya "
        "#japan #tokyo #kyoto #geziblog #japantravel #japangram #discoverjapan vb.\n\n"
        "KESİN YASAK — bu tondan KAÇIN:\n"
        "- Emir/rica: 'yapın', 'yemeyin', 'unutmayın', 'saygı gösterin', "
        "'sessiz kalın', 'yanınıza alın', 'ziyaret ederken şuna dikkat edin'\n"
        "- 2. şahıs hitap ('sizden beklenir', 'yapmalısınız')\n"
        "- Didaktik/rehber ton ('…önemlidir', '…gerekir', '…nezaketsizliktir')\n"
        "- Kültür/saygı öğüdü (bu bir belgesel — turist rehberi değil)\n\n"
        "İSTENEN (örnek — Fushimi Inari):\n"
        "🇯🇵 Fushimi Inari-taisha, Kyoto'nun güneyinde 1300 yıllık bir Şinto tapınağıdır.\n\n"
        "⛩️ Dağ yamacında yaklaşık 10.000 vermilion torii kapısı sıralanır; her biri bir bağışçının adını taşır.\n"
        "🦊 Tapınak Inari kami'sine adanmıştır — habercisi tilki olarak kabul edilir.\n"
        "🥁 Şubatta düzenlenen Hatsu-uma festivali, yerel çiftçilerin hasat şükranına dayanır.\n"
        "🥾 Zirve 233 metrededir; tam tur yaklaşık 2 saat sürer.\n"
        "🌸 Ziyaretçi yoğunluğu sabahın erken saatlerinde en düşüktür.\n\n"
        "Kaydet 📌 — Kyoto listesi için.\n\n"
        "#japonya #japan #kyoto #fushimiinari #shinto #torii #japantravel #japangram #discoverjapan #geziblog\n\n"
        "TOPLAM 500-1500 karakter. Sade metin — markdown başlığı YOK, sadece "
        "emoji + düz satır + hashtag. 'İşte caption:' gibi prefix YASAK."
    )


_AI_VISION_SYSTEM = (
    "Sen @japonyaruyasi Instagram kanalı için görsel analiz eden bir editörsün. "
    "Verilen fotoğrafı (Japonya ile ilgili — tapınak, sokak, yemek, manzara, "
    "kültür, teknoloji vs.) inceleyip, görselle uyumlu bir Story kartı için "
    "başlık ve alt açıklama önerirsin. TON: BELGESEL — 3. şahıs, öğretici "
    "değil, hitap yok. Uydurma sayı/tarih/spesifik isim YASAK — bilmediğini "
    "yazma. Yanıt YALNIZCA istenen JSON — açıklama, prefix, markdown YOK."
)


def _ai_vision_prompt(konu: str = "") -> str:
    konu = (konu or "").strip()
    # "japan" öneki arama için ekleniyor; asıl konu odağı bu (japan'ı at)
    konu_odak = konu
    for pre in ("japan ", "japonya "):
        if konu_odak.lower().startswith(pre):
            konu_odak = konu_odak[len(pre):].strip()
    if konu_odak:
        odak_blok = (
            f"ÖNEMLİ — KONU ODAĞI: Kullanıcı '{konu_odak}' aradı ve bu görseli "
            f"seçti. Görselde birden fazla öğe olabilir (örn. hem dağ hem tren), "
            f"AMA senin üreteceğin metin MUTLAKA '{konu_odak}' konusu hakkında "
            f"olmalı. Görseli, bu konuyu desteklemek için yorumla; görselde "
            f"başka baskın bir öğe olsa bile ONA KAYMA. Konu Japonya "
            f"bağlamındadır.\n\n"
        )
    else:
        odak_blok = ""
    return (
        "Bu fotoğrafı analiz et (Japonya ile ilgili).\n\n"
        f"{odak_blok}"
        "Konuya uygun bir Instagram Story kartı için başlık + açıklama öner.\n\n"
        "ÇIKTI FORMATI: sadece JSON objesi\n"
        '  {"baslik": "...", "aciklama": "..."}\n\n'
        "BAŞLIK (baslik) kuralları:\n"
        "- MAX 4 kelime, KONU ODAĞINI yansıtan, vurucu (JSON'da normal case).\n"
        "- Klişe/emir YASAK. Örnek: 'Kırmızı Kapılar', 'Shibuya Kavşağı', "
        "'Konbini Kültürü', 'Sakura Zamanı'.\n\n"
        "AÇIKLAMA (aciklama) — kartın ana metni. EN FAZLA 2 cümle, toplam max "
        "28 kelime (3. cümle YOK, uzun paragraf YOK). KONU ODAĞINA dair SOMUT "
        "bilgi ver (ne olduğu, işlevi, kültürel bağlamı). Üslup kılavuzuna "
        "BİREBİR uy:\n\n"
        f"{_TR_STYLE}\n\n"
        f"{_TR_STYLE}\n\n"
        "Görselde emin olamadığın spesifik isim/sayı UYDURMA — genel öğelerden "
        "yola çık. Emoji YOK.\n\n"
        "ÇIKTI ÖRNEKLERİ:\n"
        "(kırmızı torii kapıları görseli):\n"
        '  {"baslik": "Kırmızı Kapılar", "aciklama": "Torii kapıları, Şinto '
        "tapınaklarının girişini işaretler ve kutsal alanı dünyevi alandan "
        'ayırır."}\n'
        "(kalabalık yaya kavşağı görseli):\n"
        '  {"baslik": "Kavşak Ritmi", "aciklama": "Japon şehirlerindeki yaya '
        "kavşakları, tüm yönlere aynı anda yeşil yanan sinyal düzeniyle "
        'çalışır."}\n\n'
        "Yalnızca JSON döndür — hiçbir prefix/açıklama/markdown ekleme."
    )


_AI_TEXT_SYSTEM = (
    "Sen @japonyaruyasi Instagram kanalı için konu tabanlı editörsün. Kullanıcının "
    "yazdığı Japonya konusuna uygun bir Story kartı için başlık ve alt açıklama "
    "önerirsin. TON: BELGESEL — 3. şahıs, öğretici değil, hitap yok. Uydurma sayı/"
    "tarih/spesifik isim YASAK. Yanıt YALNIZCA istenen JSON."
)


def _ai_text_prompt(konu: str) -> str:
    konu = (konu or "").strip()
    for pre in ("japan ", "japonya "):
        if konu.lower().startswith(pre):
            konu = konu[len(pre):].strip()
    return (
        f"KONU: {konu}\n\n"
        "Bu konu için bir Instagram Story kartı başlık + açıklama üret.\n\n"
        "ÇIKTI FORMATI: sadece JSON objesi\n"
        '  {"baslik": "...", "aciklama": "..."}\n\n'
        "BAŞLIK (baslik) kuralları:\n"
        "- MAX 4 kelime, konuyu yansıtan, vurucu.\n"
        "- Klişe/emir YASAK. Örnek: 'Kırmızı Kapılar', 'Konbini Kültürü', "
        "'Sakura Zamanı'.\n\n"
        "AÇIKLAMA (aciklama) — kartın ana metni. EN FAZLA 2 cümle, toplam max "
        "28 kelime. Konuya dair SOMUT bilgi ver (ne olduğu, işlevi, kültürel "
        "bağlamı). Üslup kılavuzuna BİREBİR uy:\n\n"
        f"{_TR_STYLE}\n\n"
        "Emin olmadığın spesifik isim/sayı UYDURMA. Emoji YOK.\n\n"
        "Yalnızca JSON döndür — hiçbir prefix/açıklama/markdown ekleme."
    )


@app.post("/api/story/ai_from_text")
def story_ai_from_text(req: AIFromTextRequest) -> dict[str, Any]:
    """Sadece konu metninden (vision'suz) GPT ile başlık + açıklama üretir.
    Kullanıcı görsel seçmeden de konu yazıp AI önerisi alabilsin diye."""
    if cfg.openai is None:
        raise HTTPException(status_code=400,
                            detail="OpenAI key gerekli. config.yaml → openai.api_key.")

    from src.openai_client import OpenAIClient
    oai = OpenAIClient.from_config(cfg)
    if oai is None:
        raise HTTPException(status_code=400, detail="OpenAI client oluşturulamadı.")

    try:
        out = oai.chat_json(
            _AI_TEXT_SYSTEM,
            _ai_text_prompt(req.konu),
            temperature=0.7,
            max_tokens=250,
        )
    except (RuntimeError, ValueError) as exc:
        raise HTTPException(status_code=502, detail=f"OpenAI hatası: {exc}") from exc

    title = (out.get("baslik") or "").strip().strip('"').strip("'").strip()
    subtitle = (out.get("aciklama") or "").strip().strip('"').strip("'").strip()
    if not title and not subtitle:
        raise HTTPException(status_code=502, detail="AI boş yanıt döndürdü")
    return {"title": title, "subtitle": subtitle}


@app.post("/api/story/ai_from_image")
def story_ai_from_image(req: AIFromImageRequest) -> dict[str, Any]:
    """Verilen görseli GPT-4o vision ile analiz eder, başlık + alt açıklama önerir.
    Uzak URL'yi bizim sunucumuz indirip base64 data URI olarak OpenAI'ye
    gönderir — OpenAI bazı CDN'lere erişemediği için (401/403/timeout) daha
    güvenilir."""
    if cfg.openai is None:
        raise HTTPException(status_code=400,
                            detail="OpenAI key gerekli. config.yaml → openai.api_key.")

    from src.openai_client import OpenAIClient
    oai = OpenAIClient.from_config(cfg)
    if oai is None:
        raise HTTPException(status_code=400, detail="OpenAI client oluşturulamadı.")

    # Görseli fetch et → base64 data URI
    src_url = req.image_url
    if src_url.startswith("data:"):
        data_uri = src_url
    elif src_url.startswith("/media/backgrounds/") or src_url.startswith("/media/stories/"):
        # Yerel dosya — diskten oku (HTTP round-trip'e gerek yok, göreli
        # URL zaten requests.get ile fetch edilemez).
        import base64
        import mimetypes
        if src_url.startswith("/media/backgrounds/"):
            root = cfg.stories.backgrounds_dir if cfg.stories else None
            rel = src_url[len("/media/backgrounds/"):]
        else:
            root = cfg.stories.output_dir if cfg.stories else None
            rel = src_url[len("/media/stories/"):]
        if root is None:
            raise HTTPException(status_code=400, detail="stories config yok")
        from urllib.parse import unquote
        local_path = (root / unquote(rel)).resolve()
        try:
            local_path.relative_to(root.resolve())
        except ValueError:
            raise HTTPException(status_code=400, detail="Geçersiz yol")
        if not local_path.exists():
            raise HTTPException(status_code=404,
                                detail=f"Yerel görsel bulunamadı: {local_path.name}")
        mime = mimetypes.guess_type(str(local_path))[0] or "image/jpeg"
        b64 = base64.b64encode(local_path.read_bytes()).decode("ascii")
        data_uri = f"data:{mime};base64,{b64}"
    else:
        import base64
        import requests as _req
        try:
            r = _req.get(src_url, timeout=15,
                         headers={"User-Agent": "japan-reels-maker/1.0"})
            r.raise_for_status()
        except _req.RequestException as exc:
            raise HTTPException(status_code=502,
                                detail=f"Görsel indirilemedi: {exc}") from exc
        mime = r.headers.get("Content-Type", "image/jpeg").split(";")[0].strip()
        if not mime.startswith("image/"):
            mime = "image/jpeg"
        b64 = base64.b64encode(r.content).decode("ascii")
        data_uri = f"data:{mime};base64,{b64}"

    try:
        out = oai.chat_vision_json(
            _AI_VISION_SYSTEM,
            _ai_vision_prompt(req.konu),
            image_url=data_uri,
            # detail="low": görsel tek 512px bloğa indirilir → sabit ~2833
            # image token (gpt-4o-mini). high/auto'ya göre ~10x ucuz. Story
            # kartı için sahne tanıma (torii/dağ/sokak/yemek) fazlasıyla yeter.
            detail="low",
            temperature=0.6,
            max_tokens=400,
        )
    except (RuntimeError, ValueError) as exc:
        raise HTTPException(status_code=502, detail=f"OpenAI hatası: {exc}") from exc

    title = (out.get("baslik") or "").strip().strip('"').strip("'").strip()
    subtitle = (out.get("aciklama") or "").strip().strip('"').strip("'").strip()
    if not title and not subtitle:
        raise HTTPException(status_code=502, detail="AI boş yanıt döndürdü")
    return {"title": title, "subtitle": subtitle}


@app.post("/api/story/expand_caption")
def story_expand_caption(req: ExpandCaptionRequest) -> dict[str, Any]:
    """Kart alt açıklamasını Instagram POST caption'ına genişlet (emoji +
    madde + hashtag)."""
    if cfg.openai is None:
        raise HTTPException(status_code=400,
                            detail="OpenAI key gerekli. config.yaml → openai.api_key.")

    from src.openai_client import OpenAIClient
    oai = OpenAIClient.from_config(cfg)
    if oai is None:
        raise HTTPException(status_code=400, detail="OpenAI client oluşturulamadı.")

    try:
        text = oai.chat_text(
            _EXPAND_CAPTION_SYSTEM,
            _expand_caption_prompt(req.baslik, req.aciklama),
            temperature=0.8,
            max_tokens=900,
        )
    except (RuntimeError, ValueError) as exc:
        raise HTTPException(status_code=502, detail=f"OpenAI hatası: {exc}") from exc

    text = text.strip().strip('"').strip("'").strip()
    # olası prefix'ler
    for prefix in ("caption:", "post caption:", "instagram:", "işte caption:"):
        if text.lower().startswith(prefix):
            text = text[len(prefix):].strip()
    return {"text": text, "chars": len(text)}


_ALLOWED_UPLOAD_MIME = {"image/jpeg", "image/jpg", "image/png", "image/webp", "image/heic", "image/heif"}


@app.post("/api/story/upload_bg")
async def story_upload_bg(
    file: UploadFile = File(...),
    query: str = Form(""),
) -> dict[str, Any]:
    """Kullanıcının kendi görselini backgrounds_dir'a kaydeder. Dönen payload
    picker-item şeması ile aynıdır (id/download_url/preview_url/thumb) — frontend
    onu Unsplash sonuçları gibi işleyebilir."""
    if cfg.stories is None or cfg.stories.backgrounds_dir is None:
        raise HTTPException(status_code=400, detail="stories.backgrounds_dir yok")

    mime = (file.content_type or "").lower()
    if mime and mime not in _ALLOWED_UPLOAD_MIME:
        raise HTTPException(status_code=400,
                            detail=f"Desteklenmeyen dosya tipi: {mime}. Sadece JPG/PNG/WEBP.")

    from src import story_generator

    raw = await file.read()
    if not raw:
        raise HTTPException(status_code=400, detail="Boş dosya")
    if len(raw) > 25 * 1024 * 1024:
        raise HTTPException(status_code=400,
                            detail=f"Dosya çok büyük ({len(raw)//(1024*1024)} MB, maks 25 MB)")

    import hashlib
    from io import BytesIO
    try:
        from PIL import Image
    except ImportError as exc:
        raise HTTPException(status_code=500, detail=f"Pillow yok: {exc}") from exc

    try:
        img = Image.open(BytesIO(raw))
        img.verify()
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Görsel açılamadı: {exc}") from exc

    digest = hashlib.sha1(raw).hexdigest()[:12]
    bg_id = f"upload-{digest}"
    slug_q = story_generator._slugify(query or "upload")
    bg_dir = cfg.stories.backgrounds_dir
    bg_dir.mkdir(parents=True, exist_ok=True)
    bg_path = bg_dir / f"unsplash-{slug_q}-{bg_id}.jpg"

    if not bg_path.exists():
        try:
            img2 = Image.open(BytesIO(raw))
            if img2.mode not in ("RGB", "L"):
                img2 = img2.convert("RGB")
            max_side = 2400
            w, h = img2.size
            if max(w, h) > max_side:
                if w >= h:
                    new_w = max_side
                    new_h = int(h * (max_side / w))
                else:
                    new_h = max_side
                    new_w = int(w * (max_side / h))
                img2 = img2.resize((new_w, new_h), Image.LANCZOS)
            img2.save(bg_path, format="JPEG", quality=90, optimize=True)
        except Exception as exc:
            raise HTTPException(status_code=500, detail=f"Kaydetme hatası: {exc}") from exc

    thumb_url = f"/media/backgrounds/{quote(bg_path.name)}"
    return {
        "ok": True,
        "id": bg_id,
        "download_url": thumb_url,
        "preview_url": thumb_url,
        "thumb": thumb_url,
        "photographer": "kullanıcı",
        "photographer_name": "Yüklenen",
        "photographer_url": "",
        "query": query,
        "width": img.width if hasattr(img, "width") else 0,
        "height": img.height if hasattr(img, "height") else 0,
    }


@app.post("/api/story/render_direct")
def story_render_direct(req: RenderFromSelectionRequest) -> dict[str, Any]:
    """Seçilen bir Unsplash görseli + kullanıcının başlık/açıklamasıyla
    direkt tek kart render eder — GPT çağırmaz."""
    if cfg.stories is None:
        raise HTTPException(status_code=400, detail="stories config yok.")

    from src import story_generator

    try:
        out = story_generator.render_from_url(
            cfg,
            bg_url=req.background_url,
            bg_id=req.background_id,
            bg_query=req.query or "custom",
            baslik=req.baslik,
            aciklama=req.aciklama,
            vurgu=None,
            photographer=req.photographer,
            ust_tag=req.ust_tag or "GEZİ DEFTERİ",
            style=req.style if req.style in ("style1", "style2") else "style2",
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Render hatası: {exc}") from exc

    # Post caption verilmişse JPG yanına .txt olarak kaydet — Instagram
    # upload'ta hazır kullanılır.
    caption_file: str | None = None
    if req.post_caption and req.post_caption.strip():
        cap_path = out.with_suffix(".txt")
        try:
            cap_path.write_text(req.post_caption.strip(), encoding="utf-8")
            caption_file = cap_path.name
        except OSError as exc:
            log.warning(f"caption .txt kaydedilemedi: {exc}")

    # Sidecar JSON — kartı sonradan DÜZENLEYEBİLMEK için kaynak veriyi sakla
    slug_q = story_generator._slugify(req.query or "custom")
    bg_local = f"unsplash-{slug_q}-{req.background_id}.jpg"
    _write_story_meta(out, {
        "background_url": req.background_url,
        "background_id": req.background_id,
        "query": req.query,
        "baslik": req.baslik,
        "photographer": req.photographer,
        "source": "manuel",
        "bg_local": bg_local,
        "aciklama": req.aciklama,
        "ust_tag": req.ust_tag or "GEZİ DEFTERİ",
        "style": req.style if req.style in ("style1", "style2") else "style2",
        "post_caption": (req.post_caption or "").strip(),
    })

    # Yeni üretilen her kart doğrudan ilk yayın aşamasına düşer:
    # Onay bekliyor. Eski top-level taslaklar UI'da geriye dönük desteklenir.
    pending_out = _story_pending_dir() / out.name
    try:
        out.rename(pending_out)
        for suf in (".txt", ".json"):
            sidecar = out.with_suffix(suf)
            if sidecar.exists():
                sidecar.rename(pending_out.with_suffix(suf))
        out = pending_out
    except OSError as exc:
        raise HTTPException(status_code=500,
                            detail=f"Onay kuyruğuna taşınamadı: {exc}") from exc

    return {
        "ok": True,
        "file": out.name,
        "url": f"/media/stories/pending_approval/{quote(out.name)}",
        "baslik": req.baslik,
        "aciklama": req.aciklama,
        "caption_file": caption_file,
    }


def _write_story_meta(jpg_path: Path, meta: dict[str, Any]) -> None:
    """Kart JPG'sinin yanına .json sidecar yaz — düzenleme için kaynak veri."""
    try:
        jpg_path.with_suffix(".json").write_text(
            json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    except OSError as exc:
        log.warning(f"story meta sidecar yazılamadı: {exc}")


def _find_story_jpg(name: str) -> tuple[Path, bool] | None:
    """Kartı top-level, pending_approval/ veya ready/ altında bul.
    (jpg_path, is_ready) döner. pending_approval içinde bulunursa is_ready=False."""
    if cfg.stories is None:
        return None
    top = cfg.stories.output_dir / name
    if top.exists():
        return top, False
    pnd = cfg.stories.output_dir / "pending_approval" / name
    if pnd.exists():
        return pnd, False
    rdy = cfg.stories.output_dir / "ready" / name
    if rdy.exists():
        return rdy, True
    return None


def _story_ready_dir() -> Path:
    """Yayına hazır işaretlenmiş story kartlarının klasörü."""
    if cfg.stories is None:
        raise HTTPException(status_code=400, detail="stories config yok.")
    d = cfg.stories.output_dir / "ready"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _story_pending_dir() -> Path:
    """Otomasyonun ürettiği + onay bekleyen kart klasörü."""
    if cfg.stories is None:
        raise HTTPException(status_code=400, detail="stories config yok.")
    d = cfg.stories.output_dir / "pending_approval"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _safe_story_name(name: str) -> str:
    """Path traversal koruması — sadece basename, JPG uzantısı zorunlu."""
    if "/" in name or "\\" in name or ".." in name:
        raise HTTPException(status_code=400, detail="Geçersiz dosya adı.")
    if not name.lower().endswith(".jpg"):
        raise HTTPException(status_code=400, detail="Sadece .jpg dosyaları.")
    return name


@app.get("/api/story/list")
def story_list() -> dict[str, Any]:
    """Üretilmiş tüm story kartlarını en yeniye göre listele + durumları:
    ready (yayına hazır klasöründe mi) + draft (Instagram'a gönderilmiş mi)."""
    if cfg.stories is None or not cfg.stories.output_dir.exists():
        return {"cards": []}

    ready_dir = cfg.stories.output_dir / "ready"

    # Instagram upload log'undan gönderilenler
    from src import instagram_publisher as ig
    uploads = ig.read_upload_log(cfg) if cfg.instagram is not None else {}

    def _card_source(jpg: Path) -> str:
        """Kartın kaynağı: 'haber' (otomasyon) | 'manuel'. Sidecar .json'dan."""
        sc = jpg.with_suffix(".json")
        if sc.exists():
            try:
                if json.loads(sc.read_text(encoding="utf-8")).get("auto_generated"):
                    return "haber"
            except (OSError, ValueError):
                pass
        return "manuel"

    cards = []
    # 1) ready/ altındaki (yayına hazır — henüz yayınlanmadıysa listede,
    #    yayınlandıysa ayrı "published" listesine gider)
    if ready_dir.exists():
        for p in ready_dir.glob("*.jpg"):
            stem = p.stem
            up = uploads.get(stem)
            cards.append({
                "file": p.name,
                "url": f"/media/stories/ready/{quote(p.name)}",
                "mtime": p.stat().st_mtime,
                "ready": True,
                "published": bool(up),
                "media_id": (up or {}).get("media_id"),
                "uploaded_at": (up or {}).get("uploaded_at"),
                "draft": bool(up),   # bwd compat
                "draft_info": up,
                "has_caption": p.with_suffix(".txt").exists(),
                "source": _card_source(p),
            })
    # 2) top-level (henüz hazır işaretlenmemiş)
    for p in cfg.stories.output_dir.glob("*.jpg"):
        stem = p.stem
        up = uploads.get(stem)
        cards.append({
            "file": p.name,
            "url": f"/media/stories/{quote(p.name)}",
            "mtime": p.stat().st_mtime,
            "ready": False,
            "published": bool(up),
            "media_id": (up or {}).get("media_id"),
            "uploaded_at": (up or {}).get("uploaded_at"),
            "draft": bool(up),
            "draft_info": up,
            "has_caption": p.with_suffix(".txt").exists(),
            "source": _card_source(p),
        })

    cards.sort(key=lambda c: c["mtime"], reverse=True)
    return {"cards": cards}


@app.post("/api/story/drive-upload/{name}")
def story_drive_upload(name: str) -> dict[str, Any]:
    """Kart JPG'sini (+ varsa caption .txt) config'deki Drive senkron klasörüne
    kopyalar. Drive Desktop / OneDrive vb. buluta otomatik yükler."""
    name = _safe_story_name(name)
    if cfg.drive_folder is None:
        raise HTTPException(
            status_code=400,
            detail="Drive klasörü ayarlı değil. config.yaml → drive.folder alanına "
                   "yerel senkron klasör yolunu yaz (Google Drive Desktop klasörü).")
    found = _find_story_jpg(name)
    if found is None:
        raise HTTPException(status_code=404, detail="Kart bulunamadı.")
    jpg, _is_ready = found

    dest_dir = cfg.drive_folder
    try:
        dest_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise HTTPException(
            status_code=400,
            detail=f"Drive klasörü oluşturulamadı/erişilemedi: {dest_dir} ({exc}). "
                   "Yol doğru mu ve Drive Desktop çalışıyor mu?") from exc
    if not dest_dir.is_dir():
        raise HTTPException(status_code=400,
                            detail=f"Drive klasörü bulunamadı: {dest_dir}")

    copied = []
    try:
        shutil.copy2(jpg, dest_dir / jpg.name)
        copied.append(jpg.name)
        txt = jpg.with_suffix(".txt")
        if txt.exists():
            shutil.copy2(txt, dest_dir / txt.name)
            copied.append(txt.name)
    except OSError as exc:
        raise HTTPException(status_code=500,
                            detail=f"Kopyalama hatası: {exc}") from exc

    log.info(f"  Drive'a kopyalandı: {copied} → {dest_dir}")
    return {"ok": True, "copied": copied, "dest": str(dest_dir)}


# ---------------- Reels (OpusClip-tarzı 9:16 reframe) ----------------
class ReelMakeRequest(BaseModel):
    video: str = Field(..., min_length=1)      # kaynak video dosya adı
    max_sn: int = 60                            # hedef süre (üst sınır)


@app.get("/api/reels/sources")
def reels_sources() -> dict[str, Any]:
    """JAPAN REELS klasöründeki kaynak videoları listele (thumb + süre)."""
    from src import reel_maker
    try:
        return {"videos": reel_maker.list_source_videos(cfg)}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Kaynak listelenemedi: {exc}") from exc


@app.get("/api/reels/generated")
def reels_generated() -> dict[str, Any]:
    """Üretilmiş reels'leri listele (output/reels)."""
    from src import reel_maker
    return {"reels": reel_maker.list_generated(cfg)}


@app.post("/api/reels/make")
def reels_make(req: ReelMakeRequest) -> dict[str, Any]:
    """Kaynak videodan 9:16 dikey reel üret — arka plan job; footer'da canlı log."""
    def target(emit: Callable[..., None], cancel_ev: Event) -> None:
        from src import reel_maker
        reel_maker.make_reel(cfg, req.video, req.max_sn, emit, cancel_ev)
    try:
        manager.start_callable(f"Reel: {req.video[:40]}", target)
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"ok": True}


@app.post("/api/reels/drive-upload/{name}")
def reels_drive_upload(name: str) -> dict[str, Any]:
    """Reel mp4'ünü (+varsa .txt) Drive senkron klasörüne kopyala."""
    if "/" in name or "\\" in name or ".." in name or not name.lower().endswith(".mp4"):
        raise HTTPException(status_code=400, detail="Geçersiz dosya adı.")
    if cfg.drive_folder is None:
        raise HTTPException(status_code=400,
                            detail="Drive klasörü ayarlı değil (config.yaml → drive.folder).")
    mp4 = cfg.paths.output_dir / name
    if not mp4.exists():
        raise HTTPException(status_code=404, detail="Reel bulunamadı.")
    dest = cfg.drive_folder
    try:
        dest.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise HTTPException(status_code=400, detail=f"Drive klasörü erişilemedi: {exc}") from exc
    copied = []
    for f in (mp4, mp4.with_suffix(".txt")):
        if f.exists():
            try:
                shutil.copy2(f, dest / f.name)
                copied.append(f.name)
            except OSError as exc:
                log.warning(f"  reel Drive kopyalama hatası ({f.name}): {exc}")
    return {"ok": True, "copied": copied}


@app.get("/api/instagram/graph_status")
def instagram_graph_status() -> dict[str, Any]:
    """Instagram Graph API token durumu (config debug ekranı için)."""
    from src import instagram_graph as ig
    return ig.debug_token(cfg)


# =============================================================================
# Onay Bekleyen (Pending Approval) — Otomasyonun ürettiği postlar önce buraya
# düşer, kullanıcı widget veya web UI'dan inceler → Onayla ve Yayınla veya Reddet.
# =============================================================================


@app.get("/api/approval/list")
def approval_list() -> dict[str, Any]:
    """Onay bekleyen kartların listesi. Her item: name/url/aciklama/post_caption/
    ust_tag/generated_at."""
    if cfg.stories is None:
        return {"items": [], "count": 0}
    pending_dir = cfg.stories.output_dir / "pending_approval"
    if not pending_dir.exists():
        return {"items": [], "count": 0}
    items = []
    for jpg in sorted(pending_dir.glob("*.jpg"), key=lambda p: p.stat().st_mtime, reverse=True):
        meta_path = jpg.with_suffix(".json")
        cap_path = jpg.with_suffix(".txt")
        meta: dict[str, Any] = {}
        if meta_path.exists():
            try:
                meta = json.loads(meta_path.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                pass
        post_caption = ""
        if cap_path.exists():
            try:
                post_caption = cap_path.read_text(encoding="utf-8")
            except OSError:
                pass
        items.append({
            "name": jpg.name,
            "url": f"/media/stories/pending_approval/{quote(jpg.name)}",
            "aciklama": meta.get("aciklama", ""),
            "post_caption": post_caption,
            "ust_tag": meta.get("ust_tag", "GEZİ DEFTERİ"),
            "source": meta.get("source", meta.get("source_topic", "otomasyon")),
            "generated_at": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(jpg.stat().st_mtime)),
            "size_kb": jpg.stat().st_size // 1024,
        })
    return {"items": items, "count": len(items)}


class ApprovalUpdateRequest(BaseModel):
    aciklama: str = Field(..., min_length=5, max_length=280)
    post_caption: str = ""
    ust_tag: str = "GEZİ DEFTERİ"


@app.post("/api/approval/update/{name}")
def approval_update(name: str, req: ApprovalUpdateRequest) -> dict[str, Any]:
    """Onay bekleyen kartın metin alanlarını güncelle (kart yeniden render EDİLMEZ
    — sadece caption/aciklama sidecar günceller; kart görseli aynı kalır)."""
    name = _safe_story_name(name)
    pending_dir = _story_pending_dir()
    jpg = pending_dir / name
    if not jpg.exists():
        raise HTTPException(status_code=404, detail="Kart onay listesinde değil.")

    # sidecar meta
    meta_path = jpg.with_suffix(".json")
    meta: dict[str, Any] = {}
    if meta_path.exists():
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            pass
    meta["aciklama"] = req.aciklama.strip()
    meta["ust_tag"] = (req.ust_tag or "GEZİ DEFTERİ").strip()
    meta["post_caption"] = (req.post_caption or "").strip()
    _write_story_meta(jpg, meta)

    # caption .txt
    cap_path = jpg.with_suffix(".txt")
    try:
        if req.post_caption.strip():
            cap_path.write_text(req.post_caption.strip(), encoding="utf-8")
        elif cap_path.exists():
            cap_path.unlink()
    except OSError as exc:
        raise HTTPException(status_code=500, detail=f"Caption yazılamadı: {exc}") from exc

    # Görsel yeniden render — aciklama değiştiyse kart üstündeki metin de değişsin
    if cfg.stories is not None and meta.get("bg_local"):
        try:
            from src import story_generator
            bg_local = meta.get("bg_local", "")
            bg_path = cfg.stories.backgrounds_dir / bg_local if bg_local else None
            if bg_path and bg_path.exists():
                kart = {
                    "baslik": meta.get("baslik", ""),
                    "aciklama": meta["aciklama"],
                    "ust_tag": meta["ust_tag"],
                }
                style = meta.get("style", "style2")
                if style == "style1":
                    story_generator.render_card_style1(
                        cfg, kart, bg_path, jpg, bg_query=meta.get("query", "")
                    )
                else:
                    # Sidecar'ı olmayan eski kartlar da eski tasarımda kalır.
                    story_generator.render_card(cfg, kart, bg_path, jpg)
        except Exception as exc:
            log.warning(f"onay-güncelleme render başarısız: {exc}")

    return {"ok": True, "name": name}


@app.post("/api/approval/mark_ready/{name}")
def approval_mark_ready(name: str) -> dict[str, Any]:
    """Onay bekleyen kartı Yayına Hazır aşamasına taşı; yayınlama yapma.

    Eski top-level taslaklar da geriye dönük olarak aynı endpoint ile ready/
    klasörüne alınabilir.
    """
    name = _safe_story_name(name)
    if cfg.stories is None:
        raise HTTPException(status_code=400, detail="stories config yok.")

    pending = _story_pending_dir() / name
    legacy = cfg.stories.output_dir / name
    src = pending if pending.exists() else legacy
    dst = _story_ready_dir() / name
    if not src.exists():
        if dst.exists():
            return {"ok": True, "already_ready": True,
                    "queue_sync": _auto_fill_ready_impl()}
        raise HTTPException(status_code=404, detail="Onay bekleyen kart bulunamadı.")

    try:
        src.rename(dst)
        for suf in (".txt", ".json"):
            sidecar = src.with_suffix(suf)
            if sidecar.exists():
                sidecar.rename(dst.with_suffix(suf))
    except OSError as exc:
        raise HTTPException(status_code=500,
                            detail=f"Yayına Hazır'a taşınamadı: {exc}") from exc
    return {"ok": True, "path": str(dst.relative_to(cfg.project_root)),
            "queue_sync": _auto_fill_ready_impl()}


@app.post("/api/approval/approve/{name}")
def approval_approve(name: str) -> dict[str, Any]:
    """Onayla → ready/'ye taşı → Instagram Graph API ile yayınla."""
    name = _safe_story_name(name)
    if cfg.instagram is None or not (cfg.instagram.graph_token and cfg.instagram.ig_user_id):
        raise HTTPException(status_code=400,
                            detail="Instagram Graph API ayarlı değil.")
    base = (cfg.instagram.public_base_url or "").strip().rstrip("/")
    if not base:
        raise HTTPException(status_code=400,
                            detail="public_base_url boş. config.yaml → instagram.public_base_url")

    pending_dir = _story_pending_dir()
    ready_dir = _story_ready_dir()
    src_jpg = pending_dir / name
    if not src_jpg.exists():
        raise HTTPException(status_code=404, detail="Kart onay listesinde değil.")

    dst_jpg = ready_dir / name
    try:
        src_jpg.rename(dst_jpg)
        for suf in (".txt", ".json"):
            s = src_jpg.with_suffix(suf)
            if s.exists():
                s.rename(dst_jpg.with_suffix(suf))
    except OSError as exc:
        raise HTTPException(status_code=500,
                            detail=f"ready/'ye taşınamadı: {exc}") from exc

    image_url = f"{base}/media/stories/ready/{quote(name)}"
    cap_path = dst_jpg.with_suffix(".txt")
    caption = cap_path.read_text(encoding="utf-8") if cap_path.exists() else ""

    from src import instagram_graph
    try:
        res = instagram_graph.publish_image(cfg, image_url, caption)
    except Exception as exc:
        # Yayın başarısız → kartı geri pending'e döndürme (dosya ready'de kalsın,
        # kullanıcı elle "Instagram'a Yayınla" ile tekrar deneyebilir)
        raise HTTPException(status_code=502, detail=f"Yayın hatası: {exc}") from exc

    # uploads_log'a yaz
    rec = {"name": dst_jpg.stem, "media_id": res["id"],
           "container_id": res["container_id"],
           "uploaded_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
           "method": "graph_approval"}
    try:
        log_path = cfg.project_root / cfg.instagram.uploads_log
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except OSError as exc:
        log.warning(f"uploads_log yazılamadı: {exc}")

    return {"ok": True, "media_id": res["id"], "image_url": image_url}


@app.post("/api/approval/reject/{name}")
def approval_reject(name: str) -> dict[str, Any]:
    """Reddet → pending kartı + yan dosyalarını sil (geri döndürülemez)."""
    name = _safe_story_name(name)
    pending_dir = _story_pending_dir()
    jpg = pending_dir / name
    if not jpg.exists():
        raise HTTPException(status_code=404, detail="Kart onay listesinde değil.")
    deleted = []
    try:
        for path in (jpg, jpg.with_suffix(".txt"), jpg.with_suffix(".json")):
            if path.exists():
                path.unlink()
                deleted.append(path.name)
    except OSError as exc:
        raise HTTPException(status_code=500,
                            detail=f"Silme hatası: {exc}") from exc
    return {"ok": True, "deleted": deleted}


@app.post("/api/approval/defer/{name}")
def approval_defer(name: str) -> dict[str, Any]:
    """Şimdilik yayınlama → pending'den top-level'a taşı. Normal manuel akışa döner
    (dashboard'da 'Onayla ve Yayınla' butonu ile sonradan yayınlanabilir)."""
    name = _safe_story_name(name)
    if cfg.stories is None:
        raise HTTPException(status_code=400, detail="stories config yok")
    src = cfg.stories.output_dir / "pending_approval" / name
    if not src.exists():
        raise HTTPException(status_code=404, detail="Kart onay listesinde değil.")
    dst = cfg.stories.output_dir / name
    try:
        src.rename(dst)
        for suf in (".txt", ".json"):
            s = src.with_suffix(suf)
            if s.exists():
                s.rename(dst.with_suffix(suf))
    except OSError as exc:
        raise HTTPException(status_code=500,
                            detail=f"Taşıma hatası: {exc}") from exc
    return {"ok": True, "name": name}


@app.post("/api/widget/open")
def widget_open() -> dict[str, Any]:
    """Chrome/Brave/Edge app-mode ile masaüstünde widget penceresi açar.
    URL: local host + ?view=widget. Backend script'i tetikler, arka planda
    çalıştırır — request beklemez."""
    import subprocess

    script = cfg.project_root / "bin" / "open-widget.sh"
    if not script.exists():
        raise HTTPException(status_code=500,
                            detail=f"Widget script bulunamadı: {script}")

    # widget URL — public_base_url varsa onu tercih et (uzaktan çalışsa da açılır)
    base = ""
    if cfg.instagram and cfg.instagram.public_base_url:
        base = cfg.instagram.public_base_url.strip().rstrip("/")
    url = f"{base or 'http://localhost:8000'}/?view=widget"

    try:
        # start_new_session=True — child process bağımsız; server restart etse
        # bile widget açık kalır
        subprocess.Popen(["bash", str(script), url],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    except OSError as exc:
        raise HTTPException(status_code=500,
                            detail=f"Widget açılamadı: {exc}") from exc
    return {"ok": True, "url": url}


@app.post("/api/instagram/publish/{name}")
def instagram_publish(name: str) -> dict[str, Any]:
    """Yayına Hazır kartı resmi Graph API ile Instagram'a yayınlar.
    Foto public HTTPS URL olarak Instagram sunucularına aktarılır — bu yüzden
    cfg.instagram.public_base_url zorunlu."""
    name = _safe_story_name(name)
    if cfg.instagram is None or not (cfg.instagram.graph_token and cfg.instagram.ig_user_id):
        raise HTTPException(status_code=400,
                            detail="Instagram Graph API ayarlı değil (config.yaml → "
                                   "instagram.graph_token + ig_user_id).")
    base = (cfg.instagram.public_base_url or "").strip().rstrip("/")
    if not base:
        raise HTTPException(status_code=400,
                            detail="public_base_url boş. Instagram, foto'yu public "
                                   "HTTPS URL'den çeker. Cloudflare tunnel çalıştır ve "
                                   "verdiği URL'yi config.yaml → instagram.public_base_url'e yaz.")

    # Yayına Hazır klasöründeki JPG'yi bul
    jpg = cfg.stories.output_dir / "ready" / name if cfg.stories else None
    if not (jpg and jpg.exists()):
        raise HTTPException(status_code=404,
                            detail="Kart 'Yayına Hazır'da değil. Önce 'Yayına Hazır Yap' yap.")

    # Zaten yayınlanmış mı?
    from src import instagram_publisher as ig_pub
    existing = ig_pub.read_upload_log(cfg).get(jpg.stem)
    if existing:
        raise HTTPException(status_code=409,
                            detail=f"Bu kart zaten yayınlanmış (media_id={existing.get('media_id')})")

    image_url = f"{base}/media/stories/ready/{quote(name)}"
    # caption
    txt = jpg.with_suffix(".txt")
    caption = txt.read_text(encoding="utf-8") if txt.exists() else ""

    def target(emit: Callable[..., None], cancel_ev: Event) -> None:
        from src import instagram_graph
        emit(f"📤 Instagram'a yayınlanıyor: {name}", "info")
        emit(f"  görsel URL: {image_url}", "log")
        try:
            res = instagram_graph.publish_image(cfg, image_url, caption)
        except instagram_graph.GraphError as exc:
            emit(f"✖ Yayın hatası: {exc}", "error")
            raise
        # uploads_log'a yaz — UI'da 'Taslakta/Yayında' rozeti için
        import json as _json
        rec = {"name": jpg.stem, "media_id": res["id"],
               "container_id": res["container_id"],
               "uploaded_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
               "method": "graph"}
        try:
            log_path = cfg.project_root / cfg.instagram.uploads_log
            log_path.parent.mkdir(parents=True, exist_ok=True)
            with log_path.open("a", encoding="utf-8") as f:
                f.write(_json.dumps(rec, ensure_ascii=False) + "\n")
        except OSError as exc:
            log.warning(f"uploads_log yazılamadı: {exc}")
        emit(f"✅ Yayınlandı! media_id={res['id']}", "info")

    try:
        manager.start_callable(f"Instagram yayın: {name[:40]}", target)
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"ok": True, "image_url": image_url}


_AUTO_CFG_PATH = "data/automation_config.json"
# launchd Weekday: 0=Pazar, 1=Pazartesi, …, 6=Cumartesi
_DEFAULT_AUTO_CFG = {
    "news":  {"enabled": False, "days": [1, 4], "hour": 9,  "minute": 0, "auto_publish": False},
    "topic": {"enabled": False, "days": [2, 5], "hour": 12, "minute": 0, "auto_publish": False},
}


def _load_auto_cfg() -> dict[str, Any]:
    p = cfg.project_root / _AUTO_CFG_PATH
    if p.exists():
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
            for k, v in _DEFAULT_AUTO_CFG.items():
                item = data.setdefault(k, v.copy())
                # eski şema (interval_days) → yeni şemaya (days array) geçiş
                if "days" not in item:
                    item["days"] = v["days"]
                item.setdefault("minute", 0)
                item.setdefault("hour", v["hour"])
                item.setdefault("auto_publish", False)
                item.setdefault("enabled", False)
            return data
        except (OSError, ValueError):
            pass
    return {k: v.copy() for k, v in _DEFAULT_AUTO_CFG.items()}


def _save_auto_cfg(data: dict[str, Any]) -> None:
    p = cfg.project_root / _AUTO_CFG_PATH
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(p)


def _sync_launchd(auto: dict[str, Any]) -> list[str]:
    """Automation config'e göre launchd plist'lerini yeniden yaz + reload.
    Her aktif iş için ayrı plist; kapalı olan silinir. Notlar döner."""
    import subprocess
    notes = []
    la_dir = Path.home() / "Library" / "LaunchAgents"
    la_dir.mkdir(parents=True, exist_ok=True)
    py = shutil.which("python3") or "/usr/bin/python3"
    # venv python'u tercih et
    venv_py = cfg.project_root / ".venv" / "bin" / "python"
    if venv_py.exists():
        py = str(venv_py)

    jobs = {
        "news":  {"label": "com.japonyaruyasi.news",
                  "module": "src.news_automation",
                  "log": "data/news_automation/run.log"},
        "topic": {"label": "com.japonyaruyasi.topic",
                  "module": "src.topic_automation",
                  "log": "data/topic_automation/run.log"},
    }
    for kind, meta in jobs.items():
        plist = la_dir / f"{meta['label']}.plist"
        conf = auto.get(kind) or {}
        # önce mevcut varsa unload
        if plist.exists():
            try:
                subprocess.run(["launchctl", "unload", str(plist)],
                               capture_output=True, timeout=8)
            except (OSError, subprocess.SubprocessError):
                pass
        if not conf.get("enabled"):
            if plist.exists():
                plist.unlink(missing_ok=True)
                notes.append(f"{kind}: kaldırıldı (kapalı)")
            continue

        # Gün seçimi (0=Pzr, 1=Pzt, ...) + saat + dakika
        days = [int(d) for d in (conf.get("days") or []) if 0 <= int(d) <= 6]
        if not days:
            notes.append(f"{kind}: gün seçilmedi (aktif ama plist yazılmadı)")
            plist.unlink(missing_ok=True)
            continue
        hour = max(0, min(23, int(conf.get("hour", 9))))
        minute = max(0, min(59, int(conf.get("minute", 0))))
        args = [py, "-m", meta["module"]]
        if conf.get("auto_publish"):
            args.append("--publish")
        log_path = cfg.project_root / meta["log"]
        log_path.parent.mkdir(parents=True, exist_ok=True)
        # Her seçili gün için bir StartCalendarInterval entry — launchd birden
        # fazla entry'yi OR olarak değerlendirir (hepsi eşleşince tetiklenir).
        cal_entries = "".join(
            f"<dict><key>Weekday</key><integer>{d}</integer>"
            f"<key>Hour</key><integer>{hour}</integer>"
            f"<key>Minute</key><integer>{minute}</integer></dict>"
            for d in sorted(set(days))
        )
        content = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>{meta['label']}</string>
  <key>ProgramArguments</key>
  <array>{"".join(f"<string>{a}</string>" for a in args)}</array>
  <key>WorkingDirectory</key><string>{cfg.project_root}</string>
  <key>StartCalendarInterval</key>
  <array>{cal_entries}</array>
  <key>RunAtLoad</key><false/>
  <key>StandardOutPath</key><string>{log_path}</string>
  <key>StandardErrorPath</key><string>{log_path}</string>
</dict>
</plist>
"""
        plist.write_text(content, encoding="utf-8")
        try:
            subprocess.run(["launchctl", "load", str(plist)],
                           capture_output=True, timeout=8)
            day_names = "PztSalÇarPerCumCmtPzr"   # index'e göre TR kısa (0=Pzr için ayrı)
            tr = {0:"Pzr",1:"Pzt",2:"Sal",3:"Çar",4:"Per",5:"Cum",6:"Cmt"}
            when = ", ".join(tr[d] for d in sorted(set(days)))
            notes.append(f"{kind}: aktif · {when} @ {hour:02d}:{minute:02d} · "
                         f"auto_publish={conf.get('auto_publish', False)}")
        except (OSError, subprocess.SubprocessError) as exc:
            notes.append(f"{kind}: plist yazıldı ama launchctl load hata verdi: {exc}")
    return notes


@app.get("/api/automation/config")
def automation_config_get() -> dict[str, Any]:
    return _load_auto_cfg()


class AutomationConfigRequest(BaseModel):
    news: dict[str, Any] = Field(default_factory=dict)
    topic: dict[str, Any] = Field(default_factory=dict)


@app.post("/api/automation/config")
def automation_config_post(req: AutomationConfigRequest) -> dict[str, Any]:
    data = _load_auto_cfg()
    for k in ("news", "topic"):
        incoming = getattr(req, k) or {}
        for key in ("enabled", "days", "hour", "minute", "auto_publish"):
            if key in incoming:
                data[k][key] = incoming[key]
    _save_auto_cfg(data)
    notes = _sync_launchd(data)
    from src import scheduler as sched_mod
    queue_file = cfg.scheduler.queue_file if cfg.scheduler else "data/scheduler_queue.json"
    slot_sync = sched_mod.sync_automation_slots(cfg.project_root, data, queue_file)
    queue_sync = _auto_fill_ready_impl()
    queue_sync.update(slot_sync)
    return {"ok": True, "config": data, "launchd": notes, "queue_sync": queue_sync}


class RunNowRequest(BaseModel):
    kind: str = "news"       # 'news' | 'topic'
    auto_publish: bool = False  # compatibility: run_now bunu yok sayar
    topic: str = ""          # (sadece kind=topic) özel konu başlığı — boşsa havuzdan rastgele
    query: str = ""          # (opsiyonel) özel Unsplash görsel arama sorgusu
    count: int = 1            # tek seferde kaç içerik üretilecek (bulk)


class NewsRunNowRequest(BaseModel):
    count: int = 1


def _normalized_bulk_count(raw: int | None) -> int:
    """Run-now bulk adedini güvenli aralıkta normalize et."""
    try:
        n = int(raw or 1)
    except (TypeError, ValueError):
        n = 1
    return max(1, min(20, n))


def _run_now_bulk(
    kind: str,
    count: int,
    forced_auto_publish: bool,
    topic: str,
    query: str,
    emit: Callable[..., None],
    cancel_ev: Event,
) -> None:
    """News/Topic run_now için tek iş içinde ardışık bulk üretim akışı."""
    label = "Haber" if kind == "news" else "Konu"
    ok_count = 0
    attempted = 0

    emit(f"{label} otomasyonu başladı (adet={count}, auto_publish={forced_auto_publish})", "info")

    for idx in range(1, count + 1):
        if cancel_ev.is_set():
            emit(f"⏹ [{idx}/{count}] Kullanıcı iptal etti, bulk durduruldu.", "warn")
            break

        emit(f"▶ [{idx}/{count}] {label} üretimi başlıyor", "info")
        attempted += 1

        if kind == "news":
            from src import news_automation

            emit("① RSS kaynaklarına bağlanılıyor — son 48 saat taranacak.", "info")
            emit("② Haber adayları toplanıyor; erişilemeyen akışlar atlanabilir.", "log")
            res = news_automation.run_once_with_publish(
                cfg, auto_publish=forced_auto_publish
            )
        else:
            from src import topic_automation

            override = None
            if topic.strip():
                override = {"title": topic.strip(), "query": query.strip() or topic.strip()}
                emit(f"  Özel konu: {topic.strip()}", "log")
            res = topic_automation.run_once(
                cfg,
                auto_publish=forced_auto_publish,
                topic_override=override,
            )

        if res.get("ok"):
            ok_count += 1
            mid = res.get("published_media_id")
            emit(
                f"✅ [{idx}/{count}] {label}: {res.get('file', '?')}"
                + (f" · yayınlandı (media_id={mid})" if mid else ""),
                "info",
            )
            continue

        emit(
            f"⚠ [{idx}/{count}] {label} atlandı: {res.get('reason', 'bilinmiyor')}"
            + (f" — {res.get('detail')}" if res.get('detail') else ""),
            "warn",
        )
        for satir in res.get("fails", []):
            emit(f"   {satir}", "warn")

        # Aday kalmadıysa gereksiz tekrar deneme yapma.
        if res.get("reason") in {"no_news", "no_text"}:
            emit("⏭ Uygun aday kalmadı; bulk erken sonlandırıldı.", "warn")
            break

    emit(
        f"📦 Bulk tamamlandı: {ok_count}/{attempted} başarılı"
        + (f" (hedef {count})" if attempted != count else ""),
        "info",
    )


@app.post("/api/automation/run_now")
def automation_run_now(req: RunNowRequest) -> dict[str, Any]:
    """Bir otomasyon işini elle bir kez tetikle (footer'da canlı log)."""
    kind = req.kind if req.kind in ("news", "topic") else "news"
    count = _normalized_bulk_count(req.count)
    label = "📰 Haber" if kind == "news" else "🎨 Konu"
    forced_auto_publish = False

    def target(emit: Callable[..., None], cancel_ev: Event) -> None:
        _run_now_bulk(
            kind=kind,
            count=count,
            forced_auto_publish=forced_auto_publish,
            topic=req.topic,
            query=req.query,
            emit=emit,
            cancel_ev=cancel_ev,
        )

    try:
        manager.start_callable(f"{label} — elle tetik ×{count}", target)
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {
        "ok": True,
        "kind": kind,
        "auto_publish": forced_auto_publish,
        "count": count,
    }


@app.post("/api/news/run_now")
def news_run_now(req: NewsRunNowRequest = NewsRunNowRequest()) -> dict[str, Any]:
    """Backward-compat: eski buton hâlâ çalışsın (auto_publish=False)."""
    count = _normalized_bulk_count(req.count)

    def target(emit: Callable[..., None], cancel_ev: Event) -> None:
        _run_now_bulk(
            kind="news",
            count=count,
            forced_auto_publish=False,
            topic="",
            query="",
            emit=emit,
            cancel_ev=cancel_ev,
        )

    try:
        manager.start_callable(f"Haberden kart üret ×{count}", target)
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"ok": True, "count": count}


@app.get("/api/story/meta/{name}")
def story_meta(name: str) -> dict[str, Any]:
    """Kartın kaynak verisini döndür (düzenleme formu için). Sidecar .json
    varsa ondan; yoksa .txt'ten post_caption fallback."""
    name = _safe_story_name(name)
    found = _find_story_jpg(name)
    if found is None:
        raise HTTPException(status_code=404, detail="Kart bulunamadı.")
    jpg, is_ready = found
    meta: dict[str, Any] = {}
    sc = jpg.with_suffix(".json")
    if sc.exists():
        try:
            meta = json.loads(sc.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            meta = {}
    if not meta.get("post_caption"):
        txt = jpg.with_suffix(".txt")
        if txt.exists():
            try:
                meta["post_caption"] = txt.read_text(encoding="utf-8")
            except OSError:
                pass
    meta.setdefault("ust_tag", "GEZİ DEFTERİ")
    meta.setdefault("aciklama", "")
    meta.setdefault("post_caption", "")
    # eski kart (sidecar yok) → bg bilgisi eksik, düzenlenemez uyarısı için
    meta["editable"] = bool(meta.get("bg_local") or meta.get("background_url"))
    # Görsel URL — modal'da preview için (dizine göre değişir: top / ready / pending)
    if cfg.stories:
        try:
            rel = jpg.relative_to(cfg.stories.output_dir)
            url = "/media/stories/" + "/".join(quote(p) for p in rel.parts)
        except ValueError:
            url = f"/media/stories/{quote(name)}"
    else:
        url = f"/media/stories/{quote(name)}"
    mtime = int(jpg.stat().st_mtime) if jpg.exists() else 0
    return {"ok": True, "name": name, "ready": is_ready, "url": url,
            "mtime": mtime, "meta": meta}


@app.delete("/api/story/{name}")
def story_delete(name: str) -> dict[str, Any]:
    """Kartı VE TÜM AYAK İZLERİNİ sil (geri döndürülemez):
    - output/stories/<name>.{jpg,txt,json}
    - output/stories/ready/<name>.{jpg,txt,json}
    - output/stories/pending_approval/<name>.{jpg,txt,json}
    - data/instagram_uploads.jsonl'de bu kart için kayıt varsa çıkar

    Not: assets/story_backgrounds/'daki cache görseli SİLİNMEZ (başka kartlar
    aynı bg'yi kullanmış olabilir). Yayınlanmış (media_id var) kart Instagram'dan
    silinmez, sadece yerel iz kalkar — hesap sahibi elle Instagram'dan silmeli."""
    name = _safe_story_name(name)
    if cfg.stories is None:
        raise HTTPException(status_code=400, detail="stories config yok.")

    stem = Path(name).stem
    deleted: list[str] = []
    for base_dir in (
        cfg.stories.output_dir,
        cfg.stories.output_dir / "ready",
        cfg.stories.output_dir / "pending_approval",
    ):
        for suf in (".jpg", ".txt", ".json"):
            p = base_dir / f"{stem}{suf}"
            if p.exists():
                try:
                    p.unlink()
                    try:
                        deleted.append(str(p.relative_to(cfg.project_root)))
                    except ValueError:
                        deleted.append(p.name)
                except OSError as exc:
                    log.warning(f"silme hatası {p}: {exc}")

    if not deleted:
        raise HTTPException(status_code=404,
                            detail="Kart bulunamadı — silinecek dosya yok.")

    # uploads_log'dan kayıt çıkar (jsonl → satır satır süz)
    if cfg.instagram and cfg.instagram.uploads_log:
        log_path = cfg.project_root / cfg.instagram.uploads_log
        if log_path.exists():
            try:
                kept: list[str] = []
                removed = 0
                for line in log_path.read_text(encoding="utf-8").splitlines():
                    if not line.strip():
                        continue
                    try:
                        rec = json.loads(line)
                    except ValueError:
                        kept.append(line)
                        continue
                    if rec.get("name") == stem:
                        removed += 1
                        continue
                    kept.append(line)
                if removed:
                    tmp = log_path.with_suffix(log_path.suffix + ".tmp")
                    tmp.write_text("\n".join(kept) + ("\n" if kept else ""),
                                    encoding="utf-8")
                    tmp.replace(log_path)
                    deleted.append(f"{cfg.instagram.uploads_log} ({removed} kayıt)")
            except OSError as exc:
                log.warning(f"uploads_log güncellenemedi: {exc}")

    return {"ok": True, "deleted": deleted, "count": len(deleted)}


@app.post("/api/story/update/{name}")
def story_update(name: str, req: StoryUpdateRequest) -> dict[str, Any]:
    """Mevcut kartı yeni metinlerle AYNI dosyaya yeniden render et (overwrite).
    Arka plan görseli sidecar'daki bg_local'den (yoksa background_url'den indirilerek)
    kullanılır."""
    name = _safe_story_name(name)
    if cfg.stories is None:
        raise HTTPException(status_code=400, detail="stories config yok.")
    found = _find_story_jpg(name)
    if found is None:
        raise HTTPException(status_code=404, detail="Kart bulunamadı.")
    jpg, _is_ready = found

    sc = jpg.with_suffix(".json")
    meta: dict[str, Any] = {}
    if sc.exists():
        try:
            meta = json.loads(sc.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            meta = {}

    # arka plan görselini çöz
    from src import story_generator
    bg_dir = cfg.stories.backgrounds_dir
    bg_path: Path | None = None
    bg_local = meta.get("bg_local")
    if bg_local and bg_dir is not None:
        cand = bg_dir / bg_local
        if cand.exists():
            bg_path = cand
    if bg_path is None and meta.get("background_url") and bg_dir is not None:
        # cache'te yok → indir
        try:
            bg_dir.mkdir(parents=True, exist_ok=True)
            fname = bg_local or f"unsplash-edit-{meta.get('background_id','x')}.jpg"
            cand = bg_dir / fname
            r = requests.get(meta["background_url"], timeout=60, stream=True)
            r.raise_for_status()
            with cand.open("wb") as fh:
                for chunk in r.iter_content(chunk_size=8192):
                    fh.write(chunk)
            bg_path = cand
        except requests.RequestException as exc:
            raise HTTPException(status_code=502,
                                detail=f"Arka plan indirilemedi: {exc}") from exc
    if bg_path is None:
        raise HTTPException(status_code=400,
                            detail="Bu kartın arka plan bilgisi yok (eski kart) — düzenlenemiyor.")

    kart = {"aciklama": req.aciklama, "ust_tag": req.ust_tag or "GEZİ DEFTERİ"}
    try:
        story_generator.render_card(cfg, kart, bg_path, jpg)   # AYNI path → overwrite
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Render hatası: {exc}") from exc

    # .txt caption güncelle
    txt = jpg.with_suffix(".txt")
    pc = (req.post_caption or "").strip()
    try:
        if pc:
            txt.write_text(pc, encoding="utf-8")
        elif txt.exists():
            txt.unlink()
    except OSError as exc:
        log.warning(f"caption .txt güncellenemedi: {exc}")

    # sidecar güncelle
    meta.update({"aciklama": req.aciklama, "ust_tag": req.ust_tag or "GEZİ DEFTERİ",
                 "post_caption": pc})
    _write_story_meta(jpg, meta)

    rel = "ready/" if _is_ready else ""
    return {"ok": True, "file": name,
            "url": f"/media/stories/{rel}{quote(name)}"}


_VARY_SYSTEM = (
    "Sen @japonyaruyasi için ansiklopedik/belgesel tonda hap bilgi metinleri "
    "üreten bir editörsün. Sana verilen metni, AYNI KONUYU koruyarak ama "
    "FARKLI bir açıdan veya başka bir somut bilgiyle yeniden yazarsın. Türkçen "
    "kusursuzdur; klişe/pazarlama dili ve hitap kullanmazsın. Uydurma sayı/tarih "
    "YASAK. Yanıt SADECE yeni metin — açıklama/tırnak/prefix YOK."
)


@app.post("/api/story/vary_text")
def story_vary_text(req: VaryTextRequest) -> dict[str, Any]:
    """Verilen kart metnini aynı konuda FARKLI bir yorumla yeniden üret (Random)."""
    if cfg.openai is None:
        raise HTTPException(status_code=400,
                            detail="OpenAI key gerekli. config.yaml → openai.api_key.")
    from src.openai_client import OpenAIClient
    oai = OpenAIClient.from_config(cfg)
    if oai is None:
        raise HTTPException(status_code=400, detail="OpenAI client oluşturulamadı.")
    prompt = (
        "Aşağıdaki metin bir Japonya bilgi kartının ana metni:\n"
        f"\"{req.text.strip()}\"\n\n"
        "AYNI KONUYU/temayı koru ama FARKLI bir açıdan, başka bir somut detayla "
        "YENİDEN yaz. Farklı cümle kurulumu kullan — kopya veya eş anlamlı "
        "tekrar olmasın.\n\n"
        f"{_TR_STYLE}\n\n"
        "BİÇİM: EN FAZLA 2 cümle, toplam max 28 kelime (3. cümle YOK), emoji "
        "YOK. Sadece yeni metni yaz."
    )
    try:
        text = oai.chat_text(_VARY_SYSTEM, prompt, temperature=0.95, max_tokens=160)
    except (RuntimeError, ValueError) as exc:
        raise HTTPException(status_code=502, detail=f"OpenAI hatası: {exc}") from exc
    text = text.strip().strip('"').strip("'").strip()
    if not text:
        raise HTTPException(status_code=502, detail="AI boş yanıt döndürdü")
    return {"text": text}


@app.post("/api/story/mark_ready/{name}")
def story_mark_ready(name: str) -> dict[str, Any]:
    """Kartı 'Yayına Hazır' olarak işaretle — output/stories/<name>.jpg'yi
    output/stories/ready/<name>.jpg'ye taşı. Varsa .txt caption dosyası da
    birlikte taşınır."""
    name = _safe_story_name(name)
    if cfg.stories is None:
        raise HTTPException(status_code=400, detail="stories config yok.")

    src = cfg.stories.output_dir / name
    if not src.exists():
        # zaten ready'de mi?
        if (cfg.stories.output_dir / "ready" / name).exists():
            return {"ok": True, "already_ready": True,
                    "queue_sync": _auto_fill_ready_impl()}
        raise HTTPException(status_code=404, detail="Kart bulunamadı.")

    dst = _story_ready_dir() / name
    src.rename(dst)

    # .txt + .json sidecar dosyaları varsa onları da taşı
    for suf in (".txt", ".json"):
        s = src.with_suffix(suf)
        if s.exists():
            s.rename(dst.with_suffix(suf))

    return {"ok": True, "path": str(dst.relative_to(cfg.project_root)),
            "queue_sync": _auto_fill_ready_impl()}


@app.post("/api/story/submit_approval/{name}")
def story_submit_approval(name: str) -> dict[str, Any]:
    """Taslak kartı Onay bekliyor akışına taşı.

    Yayınlama burada yapılmaz; kart yalnızca pending_approval'a alınır ve
    Instagram işlemi sonraki Onayla ve Instagram'da yayınla aksiyonuna kalır.
    """
    name = _safe_story_name(name)
    if cfg.stories is None:
        raise HTTPException(status_code=400, detail="stories config yok.")

    src = cfg.stories.output_dir / name
    dst = _story_pending_dir() / name
    if not src.exists():
        if dst.exists():
            return {"ok": True, "already_pending": True}
        raise HTTPException(status_code=404, detail="Taslak kart bulunamadı.")

    try:
        src.rename(dst)
        for suf in (".txt", ".json"):
            sidecar = src.with_suffix(suf)
            if sidecar.exists():
                sidecar.rename(dst.with_suffix(suf))
    except OSError as exc:
        raise HTTPException(status_code=500,
                            detail=f"Onay bekliyor'a taşınamadı: {exc}") from exc

    return {"ok": True, "path": str(dst.relative_to(cfg.project_root))}


@app.post("/api/story/unmark_ready/{name}")
def story_unmark_ready(name: str) -> dict[str, Any]:
    """Yayına Hazır'dan geri al — output/stories/ready/<name>.jpg'yi geri taşı."""
    name = _safe_story_name(name)
    if cfg.stories is None:
        raise HTTPException(status_code=400, detail="stories config yok.")

    ready_dir = cfg.stories.output_dir / "ready"
    src = ready_dir / name
    if not src.exists():
        raise HTTPException(status_code=404, detail="Yayına Hazır'da bulunamadı.")

    dst = cfg.stories.output_dir / name
    src.rename(dst)

    for suf in (".txt", ".json"):
        s = src.with_suffix(suf)
        if s.exists():
            s.rename(dst.with_suffix(suf))

    return {"ok": True}


@app.post("/api/instagram/story-draft/{name}")
def instagram_story_draft(name: str) -> dict[str, Any]:
    """Yayına Hazır'daki JPG'yi Instagram Photo Drafts'a gönder.
    Yanındaki .txt caption dosyasını caption olarak kullanır."""
    name = _safe_story_name(name)
    if cfg.stories is None:
        raise HTTPException(status_code=400, detail="stories config yok.")
    if cfg.instagram is None:
        raise HTTPException(status_code=400,
                            detail="Instagram config yok. config.yaml içindeki instagram bölümünü doldur.")

    jpg = cfg.stories.output_dir / "ready" / name
    if not jpg.exists():
        raise HTTPException(status_code=404,
                            detail="Kart Yayına Hazır'da değil. Önce 'Yayına Hazır' yap.")

    stem = jpg.stem
    from src import instagram_publisher as ig
    existing = ig.read_upload_log(cfg).get(stem)
    if existing:
        raise HTTPException(status_code=409,
                            detail=f"Bu kart zaten drafts'a gönderilmiş (media_id={existing.get('media_id')})")

    txt = jpg.with_suffix(".txt")
    caption = txt.read_text(encoding="utf-8") if txt.exists() else ""

    def target(emit: Callable[..., None], cancel_ev: Event) -> None:
        try:
            ig.upload_photo_draft(cfg, jpg, caption, emit, cancel_ev)
        except Exception as exc:
            emit(f"✖ Instagram photo upload hatası: {exc}", "error")
            raise

    try:
        manager.start_callable(f"Instagram Photo Draft: {name}", target)
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"ok": True, "job": manager.state}


@app.post("/api/batch/generate")
def batch_generate(req: BatchRequest) -> dict[str, Any]:
    """Arşivi süpür → her videoyu Reels havuzuna dönüştür (temiz video + GPT caption).
    Yazı VİDEO ÜZERİNE BASILMAZ — kullanıcı Instagram'da caption'ı yapıştırır."""
    from src import batch_pipeline

    def target(emit: Callable[..., None], cancel_ev: Event) -> None:
        batch_pipeline.run_batch(cfg, emit, cancel_ev, limit=req.limit, overwrite=req.overwrite)

    label = f"Arşivi Reels'e Dönüştür{f' (limit={req.limit})' if req.limit else ''}"
    try:
        manager.start_callable(label, target)
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"ok": True, "job": manager.state}


@app.post("/api/cancel")
def cancel() -> dict[str, Any]:
    stopped = manager.cancel()
    return {"ok": stopped}


# /api/logs → src/web/routers/system.py


def _reel_item(mp4: Path, media_prefix: str) -> dict[str, Any]:
    stem = mp4.stem
    final = cfg.paths.plans_dir / f"{stem}_final.json"
    data: dict[str, Any] = {}
    if final.exists():
        try:
            data = json.loads(final.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            data = {}
    plan = data.get("kurgu_json", {}) if isinstance(data, dict) else {}
    videos = data.get("video_dosyalari", []) if isinstance(data, dict) else []

    thumb = None
    if videos:
        frame = cfg.paths.frames_dir / f"{Path(videos[0]).stem}.jpg"
        if frame.exists():
            thumb = f"/media/frames/{quote(frame.name)}"

    caption = ""
    cap_file = mp4.with_suffix(".txt")
    if cap_file.exists():
        caption = cap_file.read_text(encoding="utf-8").strip()

    hashtags = plan.get("hashtagler") or []
    if isinstance(hashtags, str):
        hashtags = [h.strip() for h in hashtags.split() if h.strip()]

    return {
        "name": stem,
        "mekan": data.get("mekan_etiketi", stem),
        "url": f"{media_prefix}/{quote(mp4.name)}",
        "thumb": thumb,
        "hook": plan.get("hook", ""),
        "cta": plan.get("cta", ""),
        "aciklama": plan.get("aciklama", ""),
        "hashtags": hashtags,
        "caption": caption,
        "clips": len(videos),
        "prompt": data.get("kullanici_prompt", ""),
        "mtime": mp4.stat().st_mtime,
    }


def _safe_reel_path(base: Path, name: str) -> Path:
    if not name or "/" in name or "\\" in name or name.startswith("."):
        raise HTTPException(status_code=400, detail="Geçersiz isim.")
    p = (base / f"{name}.mp4").resolve()
    if p.parent != base.resolve():
        raise HTTPException(status_code=400, detail="Geçersiz yol.")
    return p


def _move_reel(src_dir: Path, dst_dir: Path, name: str) -> None:
    mp4 = _safe_reel_path(src_dir, name)
    if not mp4.exists():
        raise HTTPException(status_code=404, detail="Reel bulunamadı.")
    dst_dir.mkdir(parents=True, exist_ok=True)
    shutil.move(str(mp4), str(dst_dir / mp4.name))
    txt = mp4.with_suffix(".txt")
    if txt.exists():
        shutil.move(str(txt), str(dst_dir / txt.name))


@app.get("/api/reels")
def reels() -> JSONResponse:
    pending = [
        _reel_item(m, "/media/reels")
        for m in sorted(cfg.paths.output_dir.glob("*.mp4"), key=lambda p: p.stat().st_mtime, reverse=True)
    ]
    ready = [
        _reel_item(m, "/media/ready")
        for m in sorted(cfg.paths.ready_dir.glob("*.mp4"), key=lambda p: p.stat().st_mtime, reverse=True)
    ]
    return JSONResponse({"pending": pending, "ready": ready})


@app.post("/api/reels/{name}/approve")
def approve(name: str) -> dict[str, Any]:
    _move_reel(cfg.paths.output_dir, cfg.paths.ready_dir, name)
    return {"ok": True}


@app.post("/api/reels/{name}/reject")
def reject(name: str) -> dict[str, Any]:
    mp4 = _safe_reel_path(cfg.paths.output_dir, name)
    if not mp4.exists():
        raise HTTPException(status_code=404, detail="Reel bulunamadı.")
    mp4.unlink()
    txt = mp4.with_suffix(".txt")
    if txt.exists():
        txt.unlink()
    return {"ok": True}


@app.post("/api/ready/{name}/unpublish")
def unpublish(name: str) -> dict[str, Any]:
    _move_reel(cfg.paths.ready_dir, cfg.paths.output_dir, name)
    return {"ok": True}


# ---------------- Instagram Draft ----------------
@app.get("/api/instagram/status")
def instagram_status() -> dict[str, Any]:
    """Instagram entegrasyonu aktif mi + hangi reel'ler drafts'a gönderildi?"""
    from src import instagram_publisher as ig
    session_exists = False
    if cfg.instagram is not None:
        session_path = cfg.project_root / cfg.instagram.session_file
        session_exists = session_path.exists()
    return {
        "enabled": cfg.instagram is not None,
        "username": cfg.instagram.username if cfg.instagram else "",
        "session_exists": session_exists,
        "uploads": ig.read_upload_log(cfg),
    }


@app.post("/api/instagram/reset_session")
def instagram_reset_session() -> dict[str, Any]:
    """data/instagram_session.json'ı sil — checkpoint/challenge sonrası
    temiz login denemesi için. Session yoksa da OK döner."""
    if cfg.instagram is None:
        raise HTTPException(status_code=400,
                            detail="Instagram config yok — config.yaml → instagram bölümünü doldur.")
    from src import instagram_publisher as ig
    removed = ig.logout(cfg)
    return {"ok": True, "removed": removed}


@app.post("/api/instagram/draft/{name}")
def instagram_draft(name: str) -> dict[str, Any]:
    """Yayına Hazır'daki mp4'ü Instagram uygulaması Drafts sekmesine yükler."""
    if cfg.instagram is None:
        raise HTTPException(status_code=400,
                            detail="Instagram config yok. config.yaml içindeki instagram bölümünü doldur.")

    mp4 = _safe_reel_path(cfg.paths.ready_dir, name)
    if not mp4.exists():
        raise HTTPException(status_code=404, detail="Reel bulunamadı (Yayına Hazır'da değil).")

    # zaten gönderilmiş mi kontrol
    from src import instagram_publisher as ig
    existing = ig.read_upload_log(cfg).get(name)
    if existing:
        raise HTTPException(status_code=409,
                            detail=f"Bu reel zaten drafts'a gönderilmiş (media_id={existing.get('media_id')})")

    # caption: mp4'ün yanındaki .txt
    txt = mp4.with_suffix(".txt")
    caption = txt.read_text(encoding="utf-8") if txt.exists() else ""

    def target(emit: Callable[..., None], cancel_ev: Event) -> None:
        try:
            ig.upload_draft(cfg, mp4, caption, emit, cancel_ev)
        except Exception as exc:
            emit(f"✖ Instagram upload hatası: {exc}", "error")
            raise

    try:
        manager.start_callable(f"Instagram Draft: {name}", target)
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"ok": True, "job": manager.state}


@app.post("/api/instagram/logout")
def instagram_logout() -> dict[str, Any]:
    """Session cache'i sil — sonraki upload'ta re-login."""
    from src import instagram_publisher as ig
    removed = ig.logout(cfg)
    return {"ok": True, "removed": removed}


# =============================================================================
# Reels Caption Üretici — kendi çektiğiniz videolar için hazır metin
# =============================================================================

_REELS_CAPTION_SYSTEM = (
    "Sen @japonyaruyasi Instagram kanalı için Reels caption'ı yazan bir "
    "editörsün. Kanal sahibi Mennan; ailesiyle 13 gün Japonya (Tokyo/Osaka/"
    "Kyoto/Nara, Mayıs 2026) gezmiş bir Türk gezgin. Birinci çoğul ağız (biz, "
    "ailemle), kusursuz ve akıcı Türkçe, samimi ama bilgi veren ton. "
    "Uydurma sayı/saat/fiyat YASAK. Klişe YASAK ('büyülü', 'eşsiz', 'muhteşem', "
    "'erken git', 'rahat ayakkabı'). Japonca özel isimler (Shinkansen, onsen, "
    "ryokan) çevrilmez. Yanıt SADECE geçerli JSON."
)


def _reels_caption_prompt(konu: str, ton: str, ekstra: str) -> str:
    ton_hint = {
        "samimi": "Sıcak, samimi, birinci ağızdan deneyim anlatımı.",
        "merak": "Merak uyandıran, cliffhanger — 'çoğu kişi bilmiyor' tonunda.",
        "bilgi": "Bilgilendirici, somut ipucu/tüyo odaklı, belgesel tonu.",
    }.get(ton, "Sıcak, samimi.")

    ekstra_line = f"\nKullanıcının eklemek istediği detay: {ekstra}\n" if ekstra.strip() else ""

    return (
        f"Video konusu: {konu}\n"
        f"İstenen ton: {ton} — {ton_hint}"
        f"{ekstra_line}\n"
        "Bu konuda çektiğim Reels için 3 farklı hook + 1 caption + hashtag üret.\n\n"
        "ÇIKTI (sadece JSON):\n"
        "{\n"
        '  "hooklar": ["video başında söylenecek/yazılacak 3 farklı çarpıcı '
        'açılış cümlesi (max 8 kelime)"],\n'
        '  "aciklama": "3-5 kısa cümle, birinci çoğul, somut bir gözlem/tüyo, '
        '2-4 emoji, sonda yumuşak kanal hatırlatması",\n'
        '  "hashtagler": ["8-12 tag, # olmadan, küçük harf"]\n'
        "}\n\n"
        "Kurallar: hook'lar birbirinden farklı tarzda olsun (biri merak, biri "
        "tüyo, biri kişisel). Uydurma bilgi yok. SADECE JSON döndür."
    )


@app.post("/api/reels/caption")
def reels_caption(req: ReelsCaptionRequest) -> dict[str, Any]:
    """Kendi çektiğiniz Reels için hazır Türkçe caption + hook + hashtag üret.

    Video üretmez — sadece metin. CapCut/InShot'ta düzenlediğiniz videoyu
    Instagram'a yüklerken bu metni kopyala-yapıştır kullanırsınız.
    """
    from src.openai_client import OpenAIClient
    from src import persona

    oai = OpenAIClient.from_config(cfg)

    if oai is not None:
        try:
            data = oai.chat_json(
                _REELS_CAPTION_SYSTEM,
                _reels_caption_prompt(req.konu, req.ton, req.ekstra),
                temperature=0.8,
                max_tokens=700,
            )
        except (RuntimeError, ValueError) as exc:
            log.warning(f"Reels caption OpenAI hatası, seed fallback: {exc}")
            data = None

        if data:
            hooklar = [str(h).strip() for h in (data.get("hooklar") or []) if str(h).strip()]
            aciklama = str(data.get("aciklama", "")).strip()
            # klişe temizliği
            import re as _re
            parts = _re.split(r"(?<=[.!?])\s+", aciklama)
            aciklama = " ".join(p for p in parts if not persona.cliche_iceriyor(p)).strip()
            hashtagler = []
            for t in (data.get("hashtagler") or []):
                t = _re.sub(r"[^0-9A-Za-zçğıöşüÇĞİÖŞÜ]", "", str(t)).lower()
                if t and t not in hashtagler:
                    hashtagler.append(t)
            if hooklar and aciklama and hashtagler:
                tags_line = " ".join(f"#{t}" for t in hashtagler[:12])
                full_caption = f"{aciklama}\n\n{tags_line}"
                return {
                    "ok": True,
                    "hooklar": hooklar[:3],
                    "aciklama": aciklama,
                    "hashtagler": hashtagler[:12],
                    "full_caption": full_caption,
                    "source": "openai",
                }

    # Fallback: persona seed
    seed = persona.seed_for(req.konu, req.konu)
    aciklama = seed.get("aciklama") or persona.GENERIC["aciklama"]
    hashtagler = seed.get("hashtags", persona.GENERIC["hashtags"])[:12]
    hook = seed.get("hook", persona.GENERIC["hook"])
    tags_line = " ".join(f"#{t}" for t in hashtagler)
    return {
        "ok": True,
        "hooklar": [hook],
        "aciklama": aciklama,
        "hashtagler": hashtagler,
        "full_caption": f"{aciklama}\n\n{tags_line}",
        "source": "seed",
    }


# =============================================================================
# Scheduler — Reels Posting Kuyruğu
# =============================================================================
class SchedulerEnqueueRequest(BaseModel):
    mp4_name: str = Field(..., min_length=1)        # output/reels/ altındaki dosya adı
    caption: str = ""                                # boşsa final.json'dan alınır
    scheduled_at: str = ""                           # ISO: "2026-07-28T18:00:00"; boşsa otomatik


class SchedulerStoryScheduleRequest(BaseModel):
    """Onay bekleyen / ready'de olan bir story kartını kuyruğa ekler.

    UI akışı: kart onay panelinde 'Onayla + Planla' → burası çağrılır.
    - name pending_approval'da ise ready/'ye taşınır.
    - Ready'de ise olduğu yerde bırakılır, sadece kuyruğa eklenir.
    - scheduled_at boşsa scheduler'daki sıradaki uygun slot bulunur.
    """
    name: str = Field(..., min_length=1)
    caption: str = ""
    scheduled_at: str = ""


class SchedulerRescheduleRequest(BaseModel):
    scheduled_at: str = Field(..., min_length=8)


class SchedulerReplaceAssetRequest(BaseModel):
    asset_name: str = Field(..., min_length=1)


@app.get("/api/scheduler/queue")
def scheduler_queue_list() -> dict[str, Any]:
    """Tüm kuyruk içeriğini + özet istatistiklerini döndür."""
    from src import scheduler as sched_mod
    summary = sched_mod.queue_summary(
        cfg.project_root,
        cfg.scheduler.queue_file if cfg.scheduler else "data/scheduler_queue.json",
    )
    summary["config_enabled"] = bool(cfg.scheduler and cfg.scheduler.enabled)
    summary["auto_upload"] = bool(cfg.scheduler and cfg.scheduler.auto_upload)
    summary["daily_limit"] = cfg.scheduler.daily_limit if cfg.scheduler else None
    summary["default_times"] = cfg.scheduler.default_times if cfg.scheduler else None
    return summary


@app.post("/api/scheduler/queue")
def scheduler_enqueue(req: SchedulerEnqueueRequest) -> dict[str, Any]:
    """Reels MP4'ünü yayın kuyruğuna ekle."""
    from src import scheduler as sched_mod

    sched_cfg = cfg.scheduler
    mp4 = cfg.paths.output_dir / req.mp4_name
    if not mp4.exists():
        raise HTTPException(status_code=404, detail=f"MP4 bulunamadı: {req.mp4_name}")

    # caption: request'te yoksa final.json'dan bul
    caption = req.caption
    if not caption:
        plans_dir = cfg.paths.plans_dir
        # mp4 adından slug çıkar → final.json ara
        stem_parts = mp4.stem.split("_")
        for final in plans_dir.glob("*_final.json"):
            try:
                import json as _json
                data = _json.loads(final.read_text(encoding="utf-8"))
                kj = data.get("kurgu_json", {})
                aciklama = kj.get("aciklama", "")
                hashtagler = kj.get("hashtagler", [])
                if aciklama and data.get("mekan_etiketi", "") in mp4.stem:
                    tags = " ".join(f"#{t}" for t in hashtagler[:12])
                    caption = f"{aciklama}\n\n{tags}".strip()
                    break
            except Exception:
                continue

    try:
        entry = sched_mod.enqueue(
            project_root=cfg.project_root,
            mp4_path=mp4,
            caption=caption,
            scheduled_at=req.scheduled_at or None,
            daily_limit=sched_cfg.daily_limit if sched_cfg else 2,
            default_times=sched_cfg.default_times if sched_cfg else ["08:00", "18:00"],
            queue_file=sched_cfg.queue_file if sched_cfg else "data/scheduler_queue.json",
            kind="reel",
        )
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc

    return {"ok": True, "entry": entry}


@app.post("/api/scheduler/schedule_story")
def scheduler_schedule_story(req: SchedulerStoryScheduleRequest) -> dict[str, Any]:
    """Onay bekleyen bir story kartını 'ready/'ye taşı + posting kuyruğuna ekle.

    Kullanıcının 'üretip seçtiğim postlar zamanı gelince gönderilsin' istediği akış:
        pending_approval/<name>.jpg  → ready/<name>.jpg + queue entry (kind=story)
    """
    if cfg.stories is None:
        raise HTTPException(status_code=400, detail="stories config yok.")
    if not (cfg.instagram and cfg.instagram.graph_token and cfg.instagram.ig_user_id):
        raise HTTPException(status_code=400,
                            detail="Instagram Graph API ayarlı değil — story yayınlanamaz.")
    if not (cfg.instagram.public_base_url or "").strip():
        raise HTTPException(status_code=400,
                            detail="public_base_url boş — story görseli Instagram'a servis edilemez.")

    name = _safe_story_name(req.name)
    pending = cfg.stories.output_dir / "pending_approval" / name
    ready_dir = cfg.stories.output_dir / "ready"
    ready_dir.mkdir(parents=True, exist_ok=True)
    ready = ready_dir / name
    root = cfg.stories.output_dir / name   # kartlar kökte de olabilir (legacy/onay bekleyen)

    # Kaynağı sırayla ara: pending_approval → ready → kök
    if pending.exists():
        src_jpg = pending
    elif ready.exists():
        src_jpg = ready
    elif root.exists():
        src_jpg = root
    else:
        src_jpg = None
    if src_jpg is None:
        raise HTTPException(status_code=404, detail=f"Kart bulunamadı: {name}")

    # pending/ veya kök → ready/ taşı (sidecar .txt/.json dahil)
    if src_jpg != ready:
        try:
            src_jpg.rename(ready)
            for suf in (".txt", ".json"):
                s = src_jpg.with_suffix(suf)
                if s.exists():
                    s.rename(ready.with_suffix(suf))
        except OSError as exc:
            raise HTTPException(status_code=500,
                                detail=f"ready/'ye taşınamadı: {exc}") from exc

    # caption: request'te yoksa .txt'ten oku
    caption = req.caption
    if not caption:
        cap_txt = ready.with_suffix(".txt")
        if cap_txt.exists():
            try:
                caption = cap_txt.read_text(encoding="utf-8")
            except OSError:
                caption = ""

    from src import scheduler as sched_mod
    sched_cfg = cfg.scheduler
    try:
        entry = sched_mod.enqueue(
            project_root=cfg.project_root,
            mp4_path=ready,           # story JPG
            caption=caption,
            scheduled_at=req.scheduled_at or None,
            daily_limit=sched_cfg.daily_limit if sched_cfg else 2,
            default_times=sched_cfg.default_times if sched_cfg else ["08:00", "18:00"],
            queue_file=sched_cfg.queue_file if sched_cfg else "data/scheduler_queue.json",
            kind="story",
        )
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc

    return {"ok": True, "entry": entry}


@app.post("/api/scheduler/reschedule/{entry_id}")
def scheduler_reschedule(entry_id: str, req: SchedulerRescheduleRequest) -> dict[str, Any]:
    """Bekleyen bir kuyruk girdisinin yayın zamanını değiştir."""
    from src import scheduler as sched_mod
    try:
        updated = sched_mod.reschedule(
            cfg.project_root, entry_id, req.scheduled_at,
            cfg.scheduler.queue_file if cfg.scheduler else "data/scheduler_queue.json",
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if updated is None:
        raise HTTPException(status_code=404, detail=f"Girdi bulunamadı: {entry_id}")
    return {"ok": True, "entry": updated}


@app.post("/api/scheduler/replace_asset/{entry_id}")
def scheduler_replace_asset(entry_id: str, req: SchedulerReplaceAssetRequest) -> dict[str, Any]:
    """Bir kuyruk slotundaki görseli onaylı bir kartla değiştir.

    Seçilen kart başka bir aktif slotta varsa iki slotun görselleri swap edilir.
    """
    if cfg.stories is None:
        raise HTTPException(status_code=400, detail="stories config yok.")

    name = _safe_story_name(req.asset_name)
    ready_asset = cfg.stories.output_dir / "ready" / name
    if not ready_asset.exists():
        raise HTTPException(status_code=404,
                            detail=f"Onaylı görsel bulunamadı (ready): {name}")

    from src import scheduler as sched_mod
    try:
        replaced = sched_mod.replace_entry_asset(
            project_root=cfg.project_root,
            entry_id=entry_id,
            asset_path=ready_asset,
            queue_file=cfg.scheduler.queue_file if cfg.scheduler else "data/scheduler_queue.json",
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    if replaced is None:
        raise HTTPException(status_code=404, detail=f"Girdi bulunamadı: {entry_id}")

    return {"ok": True, **replaced}


@app.post("/api/scheduler/auto_fill_ready")
def scheduler_auto_fill_ready() -> dict[str, Any]:
    """Ready kartları içerik tipinin açık otomasyon slotlarına sırayla diz."""
    return _auto_fill_ready_impl()


def _auto_fill_ready_impl() -> dict[str, Any]:
    """Planlanmamış Ready kartlarını Haber/Görsel otomasyonuna bağla."""
    if cfg.stories is None:
        raise HTTPException(status_code=400, detail="stories config yok.")

    from src import scheduler as sched_mod
    from src.web import dashboard_state as dashboard_state_mod

    ready_dir = cfg.stories.output_dir / "ready"
    if not ready_dir.exists():
        return {"ok": True, "scheduled": 0, "entries": [], "message": "Ready klasörü boş."}

    sched_cfg = cfg.scheduler
    queue_file = sched_cfg.queue_file if sched_cfg else "data/scheduler_queue.json"
    auto_cfg = _load_auto_cfg()
    existing_queue = sched_mod.load_queue(cfg.project_root, queue_file)
    queued_names = {
        (item.get("asset_name") or item.get("mp4_name") or "")
        for item in existing_queue
        if item.get("status") not in ("done", "cancelled", "failed")
    }

    from src import instagram_publisher as ig_pub
    try:
        uploaded_log = ig_pub.read_upload_log(cfg)
    except Exception:
        uploaded_log = {}

    candidates = sorted(
        (path for path in ready_dir.glob("*.jpg")
         if path.name not in queued_names and path.stem not in uploaded_log),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    if not candidates:
        return {"ok": True, "scheduled": 0, "entries": [],
                "message": "Zaten hepsi planlı veya yayında."}

    scheduled_entries: list[dict[str, Any]] = []
    fails: list[dict[str, str]] = []
    skipped: list[dict[str, str]] = []
    for jpg in candidates:
        meta: dict[str, Any] = {}
        meta_path = jpg.with_suffix(".json")
        if meta_path.exists():
            try:
                meta = json.loads(meta_path.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                meta = {}

        content_type = dashboard_state_mod._derive_type(jpg.name, meta)
        automation_kind = "news" if content_type == "haber" else "topic"
        slot_cfg = auto_cfg.get(automation_kind) or {}
        if not slot_cfg.get("enabled"):
            skipped.append({"name": jpg.name, "reason": f"{automation_kind} otomasyonu kapalı"})
            continue
        days = [int(day) for day in (slot_cfg.get("days") or []) if 0 <= int(day) <= 6]
        if not days:
            skipped.append({"name": jpg.name, "reason": f"{automation_kind} için gün seçilmedi"})
            continue

        caption = ""
        caption_path = jpg.with_suffix(".txt")
        if caption_path.exists():
            try:
                caption = caption_path.read_text(encoding="utf-8")
            except OSError:
                caption = ""
        try:
            scheduled_at = sched_mod.next_automation_slot(
                existing_queue, days, int(slot_cfg.get("hour", 9)),
                int(slot_cfg.get("minute", 0)),
                automation_kind=automation_kind,
            )
            entry = sched_mod.enqueue(
                project_root=cfg.project_root,
                mp4_path=jpg,
                caption=caption,
                scheduled_at=scheduled_at,
                queue_file=queue_file,
                kind="story",
                auto_publish=bool(slot_cfg.get("auto_publish", False)),
                automation_kind=automation_kind,
            )
            scheduled_entries.append(entry)
            existing_queue.append(entry)
        except ValueError as exc:
            fails.append({"name": jpg.name, "reason": str(exc)})

    return {
        "ok": True,
        "scheduled": len(scheduled_entries),
        "failed": len(fails),
        "skipped": len(skipped),
        "entries": scheduled_entries,
        "fails": fails,
        "skips": skipped,
        "slot_config": auto_cfg,
    }
@app.delete("/api/scheduler/queue/{entry_id}")
def scheduler_dequeue(entry_id: str) -> dict[str, Any]:
    """Kuyruktan iptal et (status → 'cancelled')."""
    from src import scheduler as sched_mod
    ok = sched_mod.cancel_entry(
        cfg.project_root, entry_id,
        cfg.scheduler.queue_file if cfg.scheduler else "data/scheduler_queue.json"
    )
    if not ok:
        raise HTTPException(status_code=404, detail=f"Girdi bulunamadı: {entry_id}")
    return {"ok": True}


@app.post("/api/scheduler/run")
def scheduler_run_now() -> dict[str, Any]:
    """Zamanı gelmiş girdileri hemen işle (manuel tetik)."""
    from src import scheduler as sched_mod
    processed = sched_mod.process_due(
        project_root=cfg.project_root,
        output_dir=cfg.paths.output_dir,
        cfg_any=cfg,
        queue_file=cfg.scheduler.queue_file if cfg.scheduler else "data/scheduler_queue.json",
        auto_upload=cfg.scheduler.auto_upload if cfg.scheduler else False,
    )
    return {"ok": True, "processed": len(processed), "items": processed}


@app.post("/api/scheduler/maintenance_cleanup")
def scheduler_maintenance_cleanup() -> dict[str, Any]:
    """uploads_log'a göre stale queue kayıtlarını manuel temizle."""
    from src import scheduler as sched_mod

    result = sched_mod.maintenance_cleanup(
        project_root=cfg.project_root,
        cfg_any=cfg,
        queue_file=cfg.scheduler.queue_file if cfg.scheduler else "data/scheduler_queue.json",
    )
    return result


# =============================================================================
# TikTok — Cross-Platform Yayın
# =============================================================================

class TikTokUploadRequest(BaseModel):
    mp4_name: str = Field(..., min_length=1)
    caption: str = ""


@app.get("/api/tiktok/status")
def tiktok_status() -> dict[str, Any]:
    """TikTok config durumu + yayınlanan video sayısı."""
    enabled = cfg.tiktok is not None
    log_path = (cfg.project_root / cfg.tiktok.uploads_log) if cfg.tiktok else None
    uploaded_count = 0
    if log_path and log_path.exists():
        uploaded_count = sum(1 for line in log_path.read_text(encoding="utf-8").splitlines() if line.strip())
    return {
        "enabled": enabled,
        "open_id": cfg.tiktok.open_id if cfg.tiktok else None,
        "uploaded_videos": uploaded_count,
    }


@app.post("/api/tiktok/upload")
def tiktok_upload(req: TikTokUploadRequest) -> dict[str, Any]:
    """Reels MP4'ünü TikTok'a yükle ve yayınla."""
    if cfg.tiktok is None:
        raise HTTPException(status_code=400,
                            detail="TikTok configure edilmemiş. config.yaml → tiktok bölümünü doldur.")

    mp4 = cfg.paths.output_dir / req.mp4_name
    if not mp4.exists():
        raise HTTPException(status_code=404, detail=f"MP4 bulunamadı: {req.mp4_name}")

    caption = req.caption
    if not caption:
        txt = mp4.with_suffix(".txt")
        if txt.exists():
            caption = txt.read_text(encoding="utf-8")

    uploads_log = cfg.project_root / cfg.tiktok.uploads_log

    def target(emit: Callable[..., None], cancel_ev: Event) -> None:
        from src import tiktok_publisher
        tiktok_publisher.upload_video(
            mp4_path=mp4,
            caption=caption,
            access_token=cfg.tiktok.access_token,
            open_id=cfg.tiktok.open_id,
            uploads_log=uploads_log,
            emit=emit,
            cancel=cancel_ev,
        )

    try:
        manager.start_callable(f"TikTok: {req.mp4_name[:40]}", target)
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"ok": True, "job": manager.state}


@app.post("/api/tiktok/refresh_token")
def tiktok_refresh_token() -> dict[str, Any]:
    """TikTok access_token'ı yenile (refresh_token kullanır)."""
    if cfg.tiktok is None or not cfg.tiktok.refresh_token:
        raise HTTPException(status_code=400, detail="TikTok refresh_token yok.")
    from src import tiktok_publisher
    try:
        result = tiktok_publisher.refresh_access_token(
            cfg.tiktok.client_key,
            cfg.tiktok.client_secret,
            cfg.tiktok.refresh_token,
        )
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Token yenileme hatası: {exc}") from exc
    return {"ok": True, "expires_in": result.get("expires_in"), "message": "Yeni token'ı config.yaml'a yazın."}


# =============================================================================
# Analytics — Yayın istatistikleri ve Hook A/B Test
# =============================================================================

class HookImpressionRequest(BaseModel):
    hook_tip: str = Field(..., min_length=1)   # merak | sayi_gercek | karsilastirma | hata_uyarisi


@app.get("/api/analytics/overview")
def analytics_overview(days: int = 30) -> dict[str, Any]:
    """Son N günlük yayın istatistikleri + haftalık frekans önerisi."""
    from src import analytics
    ig_log = cfg.instagram.uploads_log if cfg.instagram else "data/instagram_uploads.jsonl"
    tt_log = cfg.tiktok.uploads_log if cfg.tiktok else "data/tiktok_uploads.jsonl"
    return analytics.overview(
        project_root=cfg.project_root,
        ig_log=ig_log,
        tt_log=tt_log,
        scheduler_queue=cfg.scheduler.queue_file if cfg.scheduler else "data/scheduler_queue.json",
        lookback_days=days,
    )


@app.get("/api/analytics/hooks")
def analytics_hooks() -> dict[str, Any]:
    """Hook A/B test varyant analizi — hangi hook tipi daha iyi performans gösteriyor."""
    from src import analytics
    return analytics.hook_ab_analysis(cfg.paths.plans_dir)


@app.post("/api/analytics/hooks/{plan_name}/impression")
def analytics_record_impression(plan_name: str, req: HookImpressionRequest) -> dict[str, Any]:
    """Belirli plan + hook tipine impression kaydı ekle (reel izlenince tetiklenir)."""
    from src import analytics
    if "/" in plan_name or "\\" in plan_name or ".." in plan_name:
        raise HTTPException(status_code=400, detail="Geçersiz plan adı.")
    try:
        result = analytics.record_hook_impression(cfg.paths.plans_dir, plan_name, req.hook_tip)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"ok": True, **result}


@app.get("/api/analytics/platforms")
def analytics_platforms() -> dict[str, Any]:
    """Instagram vs TikTok platform karşılaştırma istatistikleri."""
    from src import analytics
    ig_log = cfg.instagram.uploads_log if cfg.instagram else "data/instagram_uploads.jsonl"
    tt_log = cfg.tiktok.uploads_log if cfg.tiktok else "data/tiktok_uploads.jsonl"
    return analytics.platform_comparison(cfg.project_root, ig_log, tt_log)


# --- Domain doğrulama (TikTok / Meta vb.) — EN SONDA olmalı ---
# TikTok "Verify URL properties" adımı kök dizinde bir .txt dosyası ister:
#   https://api.rotori.app/tiktokXXXXXXXX.txt
# İndirdiğin doğrulama dosyasını data/domain_verification/ klasörüne koy.
# KRİTİK: Bu catch-all route (`/{verify_file:path}`) MUTLAKA tüm diğer route'ların
# ARDINDAN kayıtlı olmalı — FastAPI route'ları tanımlanma sırasına göre eşleştirir;
# başta olursa /api/* dahil her şeyi gölgeler (404). En sonda = güvenli fallback.
@app.get("/{verify_file:path}")
def domain_verification(verify_file: str) -> FileResponse:
    # Path traversal koruması + yalnızca güvenli doğrulama dosyaları.
    if "/" in verify_file or "\\" in verify_file or ".." in verify_file:
        raise HTTPException(status_code=404, detail="Not found")
    allowed = verify_file.endswith(".txt") or verify_file.endswith(".html")
    is_verify = verify_file.startswith(("tiktok", "google", "pinterest", "BingSiteAuth"))
    if not (allowed and is_verify):
        raise HTTPException(status_code=404, detail="Not found")
    path = cfg.project_root / "data" / "domain_verification" / verify_file
    if not path.exists():
        raise HTTPException(status_code=404, detail="Doğrulama dosyası bulunamadı")
    return FileResponse(str(path), media_type="text/plain")
