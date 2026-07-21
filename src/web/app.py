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
from src.web.jobs import JobManager

VIDEO_EXT = {".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm"}

cfg: Config = load_config()
manager = JobManager(cfg.project_root)

STATIC_DIR = Path(__file__).resolve().parent / "static"

app = FastAPI(title="Japan Reels Maker", docs_url=None, redoc_url=None)

# Üretilen medya + kareler (StaticFiles HTTP Range destekler → video seek çalışır)
app.mount("/media/reels", StaticFiles(directory=str(cfg.paths.output_dir)), name="reels")
app.mount("/media/ready", StaticFiles(directory=str(cfg.paths.ready_dir)), name="ready")
app.mount("/media/frames", StaticFiles(directory=str(cfg.paths.frames_dir)), name="frames")
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
    return {
        "enabled": cfg.instagram is not None,
        "username": cfg.instagram.username if cfg.instagram else "",
        "uploads": ig.read_upload_log(cfg),
    }


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
