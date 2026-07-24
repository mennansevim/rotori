"""OpusClip-tarzı basit reels üretici.

Kaynak videoyu (config.paths.video_source_dir — 'JAPAN REELS' klasörü) alır,
9:16 dikey formata REFRAME eder (center-cover crop → 1080×1920), istenen süreye
trim eder ve temiz bir Reels MP4'ü üretir (üstüne yazı BASMAZ).

ffmpeg tabanlı. STT/otomatik altyazı YOK (o ayrı bir modül; whisper gerekir).

Ana fonksiyonlar:
    list_source_videos(cfg) -> [{name, size_mb, duration_sn, thumb_url}]
    make_reel(cfg, video_name, max_sn, emit, cancel) -> Path
"""
from __future__ import annotations

import json
import shutil
import subprocess
import time
from pathlib import Path
from threading import Event
from typing import Any, Callable

from src.config import Config
from src.utils.logging import get_logger

log = get_logger("reel")

_VIDEO_EXT = {".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm"}


def _ffmpeg() -> str:
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def _ffprobe() -> str | None:
    return shutil.which("ffprobe")


def _slug(text: str, max_len: int = 48) -> str:
    import re
    import unicodedata
    t = (text or "").lower()
    for a, b in {"ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u"}.items():
        t = t.replace(a, b)
    t = "".join(c for c in unicodedata.normalize("NFKD", t) if not unicodedata.combining(c))
    t = re.sub(r"[^a-z0-9]+", "_", t).strip("_")
    return t[:max_len] or "reel"


def _probe_duration(path: Path) -> float:
    fp = _ffprobe()
    if not fp:
        return 0.0
    try:
        out = subprocess.run(
            [fp, "-v", "error", "-select_streams", "v:0",
             "-show_entries", "format=duration:stream=duration",
             "-of", "default=nw=1:nk=1", str(path)],
            capture_output=True, text=True, timeout=20,
        ).stdout.strip().splitlines()
        for line in out:
            try:
                v = float(line)
                if v > 0:
                    return v
            except ValueError:
                continue
    except (subprocess.SubprocessError, OSError):
        pass
    return 0.0


def _source_dir(cfg: Config) -> Path:
    return cfg.paths.video_source_dir


def _find_source(cfg: Config, name: str) -> Path | None:
    """Kaynak videoyu ada göre bul (path-traversal güvenli — sadece basename)."""
    if "/" in name or "\\" in name or ".." in name:
        return None
    root = _source_dir(cfg)
    if not root.exists():
        return None
    for p in root.rglob("*"):
        if p.is_file() and p.name == name and p.suffix.lower() in _VIDEO_EXT:
            return p
    return None


def _thumbs_dir(cfg: Config) -> Path:
    d = cfg.paths.output_dir / "_srcthumbs"
    d.mkdir(parents=True, exist_ok=True)
    return d


def ensure_thumbnail(cfg: Config, src: Path) -> str | None:
    """Kaynak video için 9:16 önizleme karesi üret (yoksa) → /media/reels altında
    servis edilebilir yol döndür."""
    thumb = _thumbs_dir(cfg) / f"{_slug(src.stem)}.jpg"
    if not thumb.exists():
        dur = _probe_duration(src)
        ss = max(0.0, min(dur * 0.25, 3.0)) if dur else 0.0
        try:
            subprocess.run(
                [_ffmpeg(), "-y", "-ss", f"{ss:.2f}", "-i", str(src), "-frames:v", "1",
                 "-vf", "scale=360:640:force_original_aspect_ratio=increase,crop=360:640",
                 str(thumb)],
                capture_output=True, timeout=30,
            )
        except (subprocess.SubprocessError, OSError) as exc:
            log.warning(f"  thumbnail üretilemedi ({src.name}): {exc}")
            return None
    if thumb.exists():
        from urllib.parse import quote
        return f"/media/reels/_srcthumbs/{quote(thumb.name)}"
    return None


def list_source_videos(cfg: Config) -> list[dict[str, Any]]:
    root = _source_dir(cfg)
    if not root.exists():
        return []
    vids = [p for p in root.rglob("*")
            if p.is_file() and p.suffix.lower() in _VIDEO_EXT]
    vids.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    out = []
    for p in vids:
        dur = _probe_duration(p)
        out.append({
            "name": p.name,
            "size_mb": round(p.stat().st_size / 1048576, 1),
            "duration_sn": round(dur, 1),
            "thumb_url": ensure_thumbnail(cfg, p),
        })
    return out


def make_reel(cfg: Config, video_name: str, max_sn: int,
              emit: Callable[..., None], cancel: Event) -> Path:
    """Kaynak videoyu 9:16 dikey reels'e çevir (crop-cover 1080×1920 + trim)."""
    src = _find_source(cfg, video_name)
    if src is None:
        raise RuntimeError(f"Kaynak video bulunamadı: {video_name}")

    W = cfg.reels.target_width or 1080
    H = cfg.reels.target_height or 1920
    fps = cfg.reels.fps or 30
    dur = _probe_duration(src)
    max_sn = int(max_sn or cfg.reels.max_duration_sn or 60)
    trim = min(dur, max_sn) if dur else max_sn

    out_dir = cfg.paths.output_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{_slug(src.stem)}_{int(time.time())}.mp4"

    emit(f"🎬 {src.name} → 9:16 reframe ({W}×{H}, {trim:.0f}s)…", "info")
    # center-cover: kısa kenarı hedefi kaplayacak şekilde büyüt, ortadan kırp
    vf = (f"scale={W}:{H}:force_original_aspect_ratio=increase,"
          f"crop={W}:{H},fps={fps}")
    cmd = [_ffmpeg(), "-y", "-i", str(src)]
    if trim and dur and trim < dur:
        cmd += ["-t", f"{trim:.2f}"]
    cmd += [
        "-vf", vf,
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "22",
        "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k",
        "-movflags", "+faststart", str(out_path),
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"ffmpeg zaman aşımı: {exc}") from exc
    if cancel.is_set():
        out_path.unlink(missing_ok=True)
        raise RuntimeError("İptal edildi.")
    if proc.returncode != 0 or not out_path.exists():
        tail = (proc.stderr or "")[-400:]
        raise RuntimeError(f"ffmpeg hatası: {tail}")

    size_mb = out_path.stat().st_size / 1048576
    emit(f"✓ Reel hazır: {out_path.name} ({size_mb:.1f} MB)", "info")
    log.info(f"  reel üretildi: {out_path.name}")
    return out_path


def list_generated(cfg: Config) -> list[dict[str, Any]]:
    """output/reels altındaki üretilmiş reels'leri listele (en yeni önce)."""
    from urllib.parse import quote
    out_dir = cfg.paths.output_dir
    if not out_dir.exists():
        return []
    items = []
    for p in out_dir.glob("*.mp4"):
        items.append({
            "name": p.name,
            "url": f"/media/reels/{quote(p.name)}",
            "size_mb": round(p.stat().st_size / 1048576, 1),
            "mtime": p.stat().st_mtime,
            "has_caption": p.with_suffix(".txt").exists(),
        })
    items.sort(key=lambda x: x["mtime"], reverse=True)
    return items
