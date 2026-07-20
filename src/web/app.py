from __future__ import annotations

import csv
import json
import shutil
import subprocess
import time
from collections import Counter, OrderedDict
from pathlib import Path
from threading import Event
from typing import Any, Callable
from urllib.parse import quote

import requests
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from src.config import Config, load_config, require_video_source
from src.step2_group import build_groups, slug
from src.web.jobs import STEP_MODULES, JobManager

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


# ---------------- kategori yardımcıları ----------------
def _read_metadata_rows() -> list[dict[str, Any]]:
    p = cfg.paths.metadata_csv
    if not p.exists():
        return []
    with p.open("r", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def _compute_categories() -> dict[str, Any]:
    """metadata.csv'yi mekan_etiketi'ne göre grupla; her kategori için klip sayısı
    ve build_groups ile üretilebilecek gerçek reel adedini döndür."""
    rows = _read_metadata_rows()
    # tüm satırlar üzerinden bir kez grupla → mekan başına reel sayısını say
    try:
        groups = build_groups(rows, cfg)
    except Exception:
        groups = []
    reel_counts = Counter(g["mekan_etiketi"] for g in groups)

    # mekan_etiketi → ilk görülen kategori/sehir + klip sayısı (görülme sırasını koru)
    buckets: "OrderedDict[str, dict[str, Any]]" = OrderedDict()
    for r in rows:
        mekan = r.get("mekan_etiketi", "Genel") or "Genel"
        b = buckets.get(mekan)
        if b is None:
            b = {
                "mekan_etiketi": mekan,
                "kategori": r.get("kategori", "") or "",
                "sehir": r.get("sehir", "") or "",
                "klip_sayisi": 0,
            }
            buckets[mekan] = b
        b["klip_sayisi"] += 1

    kategoriler: list[dict[str, Any]] = []
    for mekan, b in buckets.items():
        b["uretilebilir_reel"] = int(reel_counts.get(mekan, 0))
        b["mevcut_reel"] = _glob_count(cfg.paths.output_dir, f"{slug(mekan)}_*.mp4")
        kategoriler.append(b)

    kategoriler.sort(key=lambda x: x["klip_sayisi"], reverse=True)
    return {"toplam_video": len(rows), "kategoriler": kategoriler}


def _render_lock_wait(emit: Callable[..., None], cancel: Event) -> None:
    """Devam eden bir src.step4_render subprocess'i varsa (başka bir ajan/işlem
    yeniden render ediyor olabilir) bitene kadar ~5sn arayla bekle."""
    warned = False
    while not cancel.is_set():
        try:
            rc = subprocess.run(
                ["pgrep", "-f", "src.step4_render"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            ).returncode
        except FileNotFoundError:
            return  # pgrep yoksa serileştirmeyi atla
        if rc != 0:
            if warned:
                emit("Dış render bitti, devam ediliyor.", "info")
            return
        if not warned:
            emit("⏳ Devam eden bir render var (src.step4_render). Bitmesi bekleniyor…", "warn")
            warned = True
        time.sleep(5)


def _free_base_name(base: str) -> str:
    """output_dir'de {base}.mp4 zaten varsa çakışmayan bir sonek üret."""
    if not (cfg.paths.output_dir / f"{base}.mp4").exists():
        return base
    i = 2
    while (cfg.paths.output_dir / f"{base}_r{i}.mp4").exists():
        i += 1
    return f"{base}_r{i}"


def _generate_reels(mekan_etiketi: str, adet: int, emit: Callable[..., None], cancel: Event) -> None:
    """Bir kategoriden `adet` reel üret: grup → *_input.json → *_final.json → mp4."""
    # ağır bağımlılıkları (moviepy) tembel yükle
    from src import step3_dify as step3
    from src import step4_render as step4
    from src.ollama_client import OllamaClient

    rows = [r for r in _read_metadata_rows() if (r.get("mekan_etiketi") or "") == mekan_etiketi]
    if not rows:
        emit(f"'{mekan_etiketi}' için metadata satırı yok.", "error")
        return

    groups = build_groups(rows, cfg)
    if not groups:
        emit(f"'{mekan_etiketi}' için üretilebilir grup yok (yeterli klip yok).", "error")
        return

    if adet > len(groups):
        emit(f"İstenen {adet} > mevcut {len(groups)} grup; {len(groups)}'e indirildi.", "warn")
        adet = len(groups)
    groups = groups[:adet]
    emit(f"'{mekan_etiketi}' → {len(groups)} reel üretilecek.", "info")

    try:
        source = require_video_source(cfg)
    except SystemExit as exc:
        emit(str(exc), "error")
        return

    # dış render ile çakışmayı önle
    _render_lock_wait(emit, cancel)
    if cancel.is_set():
        return

    emit("Kaynak indeksi oluşturuluyor…", "log")
    name_index: dict[str, Path] = {}
    for p in source.rglob("*"):
        if p.is_file() and p.suffix.lower() in VIDEO_EXT:
            name_index[p.name] = p
    emit(f"İndeks: {len(name_index)} dosya", "log")

    client = OllamaClient(cfg.ollama.base_url, cfg.ollama.request_timeout_sn)
    ts = int(time.time())
    ok = 0
    for i, g in enumerate(groups):
        if cancel.is_set():
            break
        base = _free_base_name(f"{slug(mekan_etiketi)}_{ts}_{i:02d}")
        input_path = cfg.paths.plans_dir / f"{base}_input.json"
        input_path.write_text(json.dumps(g, ensure_ascii=False, indent=2), encoding="utf-8")

        emit(f"[{i + 1}/{len(groups)}] Kurgu planı üretiliyor: {base}", "log")
        final_path = step3.process_group(cfg, input_path, use_dify=False, client=client, model="")
        if final_path is None:
            emit(f"✖ Kurgu planı başarısız: {base}", "error")
            continue

        emit(f"[{i + 1}/{len(groups)}] Render ediliyor: {base}", "log")
        out = step4.render_reel(final_path, cfg, source, name_index)
        if out is None:
            emit(f"✖ Render başarısız: {base}", "error")
            continue
        ok += 1
        emit(f"✓ Hazır: {out.name}", "info")

    emit(f"Üretim özeti: {ok}/{len(groups)} reel onay kuyruğuna eklendi.", "info")


# ---------------- modeller ----------------
class RunRequest(BaseModel):
    steps: list[int] = [1, 2, 3, 4]
    pilot: bool = False
    no_dify: bool = False


class GenerateRequest(BaseModel):
    mekan_etiketi: str
    adet: int = 1


# ---------------- endpoint'ler ----------------
@app.get("/")
def index() -> FileResponse:
    return FileResponse(str(STATIC_DIR / "index.html"))


@app.get("/api/status")
def status() -> dict[str, Any]:
    src_total = _source_video_count()
    meta = _metadata_count()
    inputs = _glob_count(cfg.paths.plans_dir, "*_input.json")
    finals = _glob_count(cfg.paths.plans_dir, "*_final.json")
    reels = _glob_count(cfg.paths.output_dir, "*.mp4")
    ready = _glob_count(cfg.paths.ready_dir, "*.mp4")
    return {
        "job": manager.state,
        "steps": [{"no": n, "label": STEP_MODULES[n][1]} for n in sorted(STEP_MODULES)],
        "counts": {
            "source_videos": src_total,
            "metadata": meta,
            "inputs": inputs,
            "finals": finals,
            "reels": reels,
            "ready": ready,
        },
        "progress": {
            "1": {"done": meta, "total": src_total},
            "2": {"done": inputs, "total": None},
            "3": {"done": finals, "total": inputs},
            "4": {"done": reels, "total": finals},
        },
        "env": {
            "source_dir": str(cfg.paths.video_source_dir),
            "source_ready": str(cfg.paths.video_source_dir) != "REPLACE_ME"
            and cfg.paths.video_source_dir.exists(),
            "ollama_url": cfg.ollama.base_url,
            "ollama_ok": _ollama_ok(),
            "dify_url": cfg.dify.base_url,
            "dify_ready": cfg.dify.api_key not in ("", "REPLACE_ME_APP_TOKEN"),
            "aciklama_tipi": cfg.dify.aciklama_tipi,
            "pilot_default": cfg.pilot.pilot_mode,
            "pilot_count": cfg.pilot.pilot_count,
            "max_videos_per_run": cfg.run.max_videos_per_run,
            "ready_dir": str(cfg.paths.ready_dir),
        },
    }


@app.post("/api/run")
def run(req: RunRequest) -> dict[str, Any]:
    try:
        manager.start(sorted(set(req.steps)), req.pilot, req.no_dify)
    except (RuntimeError, ValueError) as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"ok": True, "job": manager.state}


@app.get("/api/categories")
def categories() -> dict[str, Any]:
    return _compute_categories()


@app.post("/api/categorize")
def categorize() -> dict[str, Any]:
    """Analiz edilmemiş yeni klip varsa step1_analyze'i çalıştırıp metadata'yı
    günceller; yoksa sadece kategorileri döndürür."""
    if manager.state.get("running"):
        raise HTTPException(status_code=409, detail="Zaten çalışan bir iş var.")

    src_total = _source_video_count()
    meta = _metadata_count()
    if src_total > meta:
        try:
            manager.start([1], pilot=False, no_dify=True)
        except (RuntimeError, ValueError) as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc
        return {
            "started": True,
            "message": f"{src_total - meta} yeni video için analiz başlatıldı. "
                       "Bitince 'Yenile' ile kategoriler güncellenir.",
            **_compute_categories(),
        }
    return {
        "started": False,
        "message": "Yapılacak yeni video yok; tüm klipler zaten analiz edilmiş.",
        **_compute_categories(),
    }


@app.post("/api/generate")
def generate(req: GenerateRequest) -> dict[str, Any]:
    mekan = (req.mekan_etiketi or "").strip()
    if not mekan:
        raise HTTPException(status_code=400, detail="mekan_etiketi gerekli.")
    if req.adet < 1:
        raise HTTPException(status_code=400, detail="adet en az 1 olmalı.")

    def target(emit: Callable[..., None], cancel: Event) -> None:
        _generate_reels(mekan, req.adet, emit, cancel)

    try:
        manager.start_callable(f"'{mekan}' reel üretimi (adet={req.adet})", target)
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
        "mtime": mp4.stat().st_mtime,
    }


def _safe_reel_path(base: Path, name: str) -> Path:
    """name → base/name.mp4, path-traversal koruması ile."""
    if not name or "/" in name or "\\" in name or name.startswith("."):
        raise HTTPException(status_code=400, detail="Geçersiz isim.")
    p = (base / f"{name}.mp4").resolve()
    if p.parent != base.resolve():
        raise HTTPException(status_code=400, detail="Geçersiz yol.")
    return p


def _move_reel(src_dir: Path, dst_dir: Path, name: str) -> None:
    """mp4 + eşlik eden .txt caption'ı taşı."""
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
