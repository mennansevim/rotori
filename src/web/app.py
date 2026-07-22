from __future__ import annotations

import json
import shutil
import time
from pathlib import Path
from threading import Event
from typing import Any, Callable
from urllib.parse import quote

import requests
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from src.config import Config, load_config
from src.utils.logging import get_logger
from src.web.jobs import JobManager

log = get_logger("web")

VIDEO_EXT = {".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm"}

cfg: Config = load_config()
manager = JobManager(cfg.project_root)

STATIC_DIR = Path(__file__).resolve().parent / "static"

app = FastAPI(title="Japan Reels Maker", docs_url=None, redoc_url=None)

# Üretilen medya + kareler (StaticFiles HTTP Range destekler → video seek çalışır)
app.mount("/media/reels", StaticFiles(directory=str(cfg.paths.output_dir)), name="reels")
app.mount("/media/ready", StaticFiles(directory=str(cfg.paths.ready_dir)), name="ready")
app.mount("/media/frames", StaticFiles(directory=str(cfg.paths.frames_dir)), name="frames")
if cfg.stories:
    app.mount("/media/stories", StaticFiles(directory=str(cfg.stories.output_dir)), name="stories")
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


# ---------------- yardımcılar ----------------
_src_cache: dict[str, Any] = {"count": None, "ts": 0.0}


def _source_video_count() -> int:
    now = time.time()
    if _src_cache["count"] is not None and now - _src_cache["ts"] < 60:
        return int(_src_cache["count"])
    src = cfg.paths.video_source_dir
    count = 0
    if str(src) != "REPLACE_ME" and src.exists():
        count = sum(1 for p in src.rglob("*") if p.is_file() and p.suffix.lower() in VIDEO_EXT)
    _src_cache.update(count=count, ts=now)
    return count


def _metadata_count() -> int:
    p = cfg.paths.metadata_csv
    if not p.exists():
        return 0
    with p.open("r", encoding="utf-8") as fh:
        return max(0, sum(1 for _ in fh) - 1)


def _glob_count(directory: Path, pattern: str) -> int:
    return sum(1 for _ in directory.glob(pattern))


def _ollama_ok() -> bool:
    try:
        r = requests.get(f"{cfg.ollama.base_url.rstrip('/')}/api/tags", timeout=2)
        return r.status_code == 200
    except requests.RequestException:
        return False


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


class AICaptionRequest(BaseModel):
    konu: str = Field(..., min_length=2)
    mode: str = "subtitle"   # "title" | "subtitle"


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


# ---------------- endpoint'ler ----------------
@app.get("/")
def index() -> FileResponse:
    return FileResponse(str(STATIC_DIR / "index.html"))


@app.get("/api/status")
def status() -> dict[str, Any]:
    src_total = _source_video_count()
    meta = _metadata_count()
    reels = _glob_count(cfg.paths.output_dir, "*.mp4")
    ready = _glob_count(cfg.paths.ready_dir, "*.mp4")
    return {
        "job": manager.state,
        "counts": {
            "source_videos": src_total,
            "metadata": meta,
            "reels": reels,
            "ready": ready,
        },
        "env": {
            "source_dir": str(cfg.paths.video_source_dir),
            "source_ready": str(cfg.paths.video_source_dir) != "REPLACE_ME"
            and cfg.paths.video_source_dir.exists(),
            "ollama_url": cfg.ollama.base_url,
            "ollama_ok": _ollama_ok(),
            "ready_dir": str(cfg.paths.ready_dir),
        },
    }


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
        "photographer": req.photographer,
        "bg_local": bg_local,
        "aciklama": req.aciklama,
        "ust_tag": req.ust_tag or "GEZİ DEFTERİ",
        "post_caption": (req.post_caption or "").strip(),
    })

    return {
        "ok": True,
        "file": out.name,
        "url": f"/media/stories/{quote(out.name)}",
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
    """Kartı top-level veya ready/ altında bul. (jpg_path, is_ready) döner."""
    if cfg.stories is None:
        return None
    top = cfg.stories.output_dir / name
    if top.exists():
        return top, False
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

    cards = []
    # 1) ready/ altındaki (yayına hazır)
    if ready_dir.exists():
        for p in ready_dir.glob("*.jpg"):
            stem = p.stem
            cards.append({
                "file": p.name,
                "url": f"/media/stories/ready/{quote(p.name)}",
                "mtime": p.stat().st_mtime,
                "ready": True,
                "draft": stem in uploads,
                "draft_info": uploads.get(stem),
                "has_caption": p.with_suffix(".txt").exists(),
            })
    # 2) top-level (henüz hazır işaretlenmemiş)
    for p in cfg.stories.output_dir.glob("*.jpg"):
        stem = p.stem
        cards.append({
            "file": p.name,
            "url": f"/media/stories/{quote(p.name)}",
            "mtime": p.stat().st_mtime,
            "ready": False,
            "draft": stem in uploads,
            "draft_info": uploads.get(stem),
            "has_caption": p.with_suffix(".txt").exists(),
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
    return {"ok": True, "name": name, "ready": is_ready, "meta": meta}


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
            return {"ok": True, "already_ready": True}
        raise HTTPException(status_code=404, detail="Kart bulunamadı.")

    dst = _story_ready_dir() / name
    src.rename(dst)

    # .txt + .json sidecar dosyaları varsa onları da taşı
    for suf in (".txt", ".json"):
        s = src.with_suffix(suf)
        if s.exists():
            s.rename(dst.with_suffix(suf))

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


@app.get("/api/logs")
def logs(since: int = 0) -> dict[str, Any]:
    entries, seq = manager.logs_since(since)
    return {"entries": entries, "seq": seq, "progress_line": manager.state.get("progress_line", "")}


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
