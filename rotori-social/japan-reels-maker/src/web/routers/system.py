"""System router — meta/sağlık endpoint'leri.

Route'lar:
    GET /api/version   — semver + git commit + build tarihi
    GET /api/status    — job durumu + kaynak sayaçları + Ollama sağlığı
    GET /api/logs      — canlı job log akışı (long-polling parametresi ile)

Sözleşme aynen app.py'deki eski davranıştır — response şeması değişmedi.
Bu router `dependencies.get_cfg()` ve `get_manager()` üzerinden singleton
erişir; app.py init sırasında set_runtime() çağırır.
"""
from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path
from typing import Any

import requests
from fastapi import APIRouter

from src.web.dependencies import get_cfg, get_manager

router = APIRouter(tags=["system"])


# ---------------------------------------------------------------------------
# Sürüm yardımcıları (module-load'da hesaplanır, /api/version'da cache'lenir).
# ---------------------------------------------------------------------------
def _read_version(project_root: Path) -> dict[str, str]:
    version = ""
    try:
        version = (project_root / "VERSION").read_text(encoding="utf-8").strip()
    except OSError:
        version = ""
    if version and not version.lower().startswith("v"):
        version = "v" + version

    bfile = project_root / "BUILD_INFO"
    if bfile.exists():
        try:
            raw = json.loads(bfile.read_text(encoding="utf-8"))
            if isinstance(raw, dict) and raw.get("commit"):
                return {
                    "version": version or "v?",
                    "commit": str(raw.get("commit", "")).strip()[:7],
                    "date": str(raw.get("date", "")).strip(),
                    "source": "build",
                }
        except (OSError, ValueError):
            pass

    try:
        commit = subprocess.check_output(
            ["git", "-C", str(project_root), "rev-parse", "--short", "HEAD"],
            stderr=subprocess.DEVNULL,
            timeout=3,
        ).decode().strip()
        date = subprocess.check_output(
            ["git", "-C", str(project_root), "log", "-1",
             "--format=%cd", "--date=format:%Y-%m-%d %H:%M"],
            stderr=subprocess.DEVNULL,
            timeout=3,
        ).decode().strip()
        return {"version": version or "dev", "commit": commit,
                "date": date, "source": "git"}
    except Exception:
        return {"version": version or "dev", "commit": "dev",
                "date": "", "source": "none"}


# ---------------------------------------------------------------------------
# Kaynak sayacı — mevcut _source_video_count/_metadata_count/_glob_count
# davranışını taşıyan yardımcılar. Cache 60s (aynı app.py mantığı).
# ---------------------------------------------------------------------------
VIDEO_EXT = {".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm"}
_src_cache: dict[str, Any] = {"count": None, "ts": 0.0}


def _source_video_count() -> int:
    cfg = get_cfg()
    now = time.time()
    if _src_cache["count"] is not None and now - _src_cache["ts"] < 60:
        return int(_src_cache["count"])
    src = cfg.paths.video_source_dir
    count = 0
    if str(src) != "REPLACE_ME" and src.exists():
        count = sum(
            1 for p in src.rglob("*")
            if p.is_file() and p.suffix.lower() in VIDEO_EXT
        )
    _src_cache.update(count=count, ts=now)
    return count


def _metadata_count() -> int:
    cfg = get_cfg()
    p = cfg.paths.metadata_csv
    if not p.exists():
        return 0
    with p.open("r", encoding="utf-8") as fh:
        return max(0, sum(1 for _ in fh) - 1)


def _glob_count(directory: Path, pattern: str) -> int:
    return sum(1 for _ in directory.glob(pattern))


def _ollama_ok() -> bool:
    cfg = get_cfg()
    try:
        r = requests.get(
            f"{cfg.ollama.base_url.rstrip('/')}/api/tags", timeout=2
        )
        return r.status_code == 200
    except requests.RequestException:
        return False


# ---------------------------------------------------------------------------
# Route'lar
# ---------------------------------------------------------------------------
@router.get("/api/version")
def api_version() -> dict[str, str]:
    """VERSION dosyası + git/build commit — footer badge'e basılır."""
    cfg = get_cfg()
    # Deploy sırasında BUILD_INFO değişebilir; her istekte oku (ucuz).
    return _read_version(cfg.project_root)


@router.get("/api/status")
def api_status() -> dict[str, Any]:
    """Poll endpoint — sağ alt canlı süreç footer'ı 2s'de bir çağırır."""
    cfg = get_cfg()
    manager = get_manager()
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


@router.get("/api/logs")
def api_logs(since: int = 0) -> dict[str, Any]:
    """Long-polling — since seq'ten sonraki logları döndür."""
    manager = get_manager()
    entries, seq = manager.logs_since(since)
    return {
        "entries": entries,
        "seq": seq,
        "progress_line": manager.state.get("progress_line", ""),
    }
