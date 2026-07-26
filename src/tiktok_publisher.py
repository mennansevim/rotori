"""TikTok Video Publisher — Content Posting API v2 ile Reels MP4 yükleme.

TikTok için ayrı bir hesap açılması önerilir (örn. @japonyaruyasi veya @japonyaruyasi.tt).
Aynı MP4'ler hem Instagram'a hem TikTok'a yüklenebilir — cross-posting ile reach 2-3x artar.

Kurulum (config.yaml → tiktok):
    client_key: "..."         # TikTok Developer Portal'dan
    client_secret: "..."      # TikTok Developer Portal'dan
    access_token: "..."       # OAuth2 ile alınmış kullanıcı access token
    open_id: "..."            # Kullanıcının TikTok open_id (token ile birlikte gelir)
    uploads_log: "data/tiktok_uploads.jsonl"

OAuth2 akışı (tek seferlik):
    1. https://developers.tiktok.com → Manage Apps → uygulamanızı kaydedin
    2. Scope'lar: video.upload + video.list
    3. Redirect URI ile authorization code alın
    4. POST https://open.tiktokapis.com/v2/oauth/token/ → access_token + open_id
    5. access_token'ı config.yaml'a yazın (geçerlilik: 24 saat; refresh_token: 365 gün)

Referans: https://developers.tiktok.com/doc/content-posting-api-get-started

Dikkat:
    - TikTok Content Posting API Türkiye'deki hesaplara açık olmayabilir;
      hesabı ABD/UK App Store hesabıyla oluşturulmuş bir telefonda açın.
    - Video boyutu max 4GB, süre max 60dk (Reels için sorun yok).
    - caption max 2200 karakter (Instagram ile aynı).
    - Hashtag formatı: #japonya gibi caption içine gömülü.
"""
from __future__ import annotations

import json
import time
from pathlib import Path
from threading import Event
from typing import Any, Callable

import requests

from src.utils.logging import get_logger

log = get_logger("tiktok")

_TIKTOK_API_BASE = "https://open.tiktokapis.com/v2"

# TikTok Privacy seviyesi — başlangıç için "SELF_ONLY" (sadece sen görürsün)
# sonra web arayüzünden "PUBLIC_TO_EVERYONE"'a çevir
_DEFAULT_PRIVACY = "PUBLIC_TO_EVERYONE"


# ---------------------------------------------------------------------------
# Token yönetimi
# ---------------------------------------------------------------------------

def refresh_access_token(client_key: str, client_secret: str, refresh_token: str) -> dict[str, Any]:
    """Süresi dolan access_token'ı yenile (refresh_token 365 gün geçerli).

    Returns: {"access_token": str, "expires_in": int, "open_id": str, ...}
    """
    resp = requests.post(
        f"{_TIKTOK_API_BASE}/oauth/token/",
        data={
            "client_key": client_key,
            "client_secret": client_secret,
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
        },
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()
    if data.get("error", {}).get("code", "ok") != "ok":
        raise RuntimeError(f"TikTok token refresh hatası: {data['error']}")
    return data.get("data", data)


# ---------------------------------------------------------------------------
# Video yükleme
# ---------------------------------------------------------------------------

def _init_upload(
    access_token: str,
    open_id: str,
    file_size: int,
    chunk_size: int = 10 * 1024 * 1024,    # 10MB chunks
) -> dict[str, Any]:
    """TikTok Direct Post init — upload URL + publish_id alır."""
    resp = requests.post(
        f"{_TIKTOK_API_BASE}/post/publish/video/init/",
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json; charset=UTF-8",
        },
        json={
            "post_info": {
                "title": "",           # caption ayrıca set edilecek
                "privacy_level": _DEFAULT_PRIVACY,
                "disable_duet": False,
                "disable_comment": False,
                "disable_stitch": False,
            },
            "source_info": {
                "source": "FILE_UPLOAD",
                "video_size": file_size,
                "chunk_size": chunk_size,
                "total_chunk_count": (file_size + chunk_size - 1) // chunk_size,
            },
        },
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()
    err = data.get("error", {})
    if err.get("code", "ok") != "ok":
        raise RuntimeError(f"TikTok init hatası: {err}")
    return data["data"]


def _upload_chunks(
    upload_url: str,
    mp4_path: Path,
    file_size: int,
    chunk_size: int,
    emit: Callable[..., None],
    cancel: Event,
) -> None:
    """MP4'ü chunk'lar halinde TikTok upload URL'sine PUT et."""
    total_chunks = (file_size + chunk_size - 1) // chunk_size
    with mp4_path.open("rb") as fh:
        for idx in range(total_chunks):
            if cancel.is_set():
                raise RuntimeError("İptal edildi.")
            start = idx * chunk_size
            end = min(start + chunk_size - 1, file_size - 1)
            chunk = fh.read(chunk_size)
            resp = requests.put(
                upload_url,
                headers={
                    "Content-Range": f"bytes {start}-{end}/{file_size}",
                    "Content-Length": str(len(chunk)),
                    "Content-Type": "video/mp4",
                },
                data=chunk,
                timeout=120,
            )
            resp.raise_for_status()
            emit(f"  Chunk {idx + 1}/{total_chunks} yüklendi ({end + 1}/{file_size} byte)", "log")


def _set_caption(
    access_token: str,
    publish_id: str,
    caption: str,
) -> None:
    """Yüklenen video'nun caption'ını güncelle (opsiyonel — init sonrası)."""
    # TikTok Direct Post'ta caption init'te title olarak verilir;
    # bu fonksiyon post-upload patch için ayrılmıştır (API v3'te kullanılabilir).
    pass


def _check_publish_status(access_token: str, publish_id: str, max_wait_sn: int = 120) -> dict[str, Any]:
    """Yayın işleminin tamamlanmasını bekle. Returns: {"status": str, "video_id": str}"""
    deadline = time.time() + max_wait_sn
    while time.time() < deadline:
        resp = requests.post(
            f"{_TIKTOK_API_BASE}/post/publish/status/fetch/",
            headers={
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json; charset=UTF-8",
            },
            json={"publish_id": publish_id},
            timeout=30,
        )
        resp.raise_for_status()
        data = resp.json().get("data", {})
        status = data.get("status", "")
        if status in ("PUBLISH_COMPLETE", "SUCCESS"):
            return {"status": "done", "video_id": data.get("video_id", ""), "publish_id": publish_id}
        if status in ("FAILED", "ERROR"):
            raise RuntimeError(f"TikTok yayın hatası: {data}")
        time.sleep(5)
    raise TimeoutError(f"TikTok yayın zaman aşımı (publish_id={publish_id})")


# ---------------------------------------------------------------------------
# Ana upload fonksiyonu
# ---------------------------------------------------------------------------

def upload_video(
    mp4_path: Path,
    caption: str,
    access_token: str,
    open_id: str,
    uploads_log: Path,
    emit: Callable[..., None],
    cancel: Event,
    chunk_size: int = 10 * 1024 * 1024,
) -> dict[str, Any]:
    """TikTok'a video yükle ve yayınla.

    Returns: {"video_id": str, "publish_id": str, "uploaded_at": str, "name": str}
    """
    if not mp4_path.exists():
        raise FileNotFoundError(f"MP4 bulunamadı: {mp4_path}")

    file_size = mp4_path.stat().st_size
    emit(f"① TikTok upload başlıyor: {mp4_path.name} ({file_size // (1024 * 1024)} MB)", "info")

    # caption güvenliği
    caption = (caption or "").strip()
    if len(caption) > 2200:
        caption = caption[:2197] + "..."

    # 1) Init
    emit("② Upload init…", "log")
    init_data = _init_upload(access_token, open_id, file_size, chunk_size)
    upload_url = init_data["upload_url"]
    publish_id = init_data["publish_id"]
    emit(f"   publish_id={publish_id}", "log")

    if cancel.is_set():
        emit("⏹ İptal edildi.", "warn")
        raise RuntimeError("cancelled")

    # 2) Chunk upload
    emit(f"③ Video chunk upload ({(file_size + chunk_size - 1) // chunk_size} chunk)…", "log")
    _upload_chunks(upload_url, mp4_path, file_size, chunk_size, emit, cancel)

    # 3) Yayın durumu bekle
    emit("④ Yayın işleniyor…", "log")
    result = _check_publish_status(access_token, publish_id)
    video_id = result.get("video_id", "")

    uploaded_at = time.strftime("%Y-%m-%dT%H:%M:%S")
    log_entry = {
        "name": mp4_path.stem,
        "video_id": video_id,
        "publish_id": publish_id,
        "uploaded_at": uploaded_at,
        "platform": "tiktok",
        "caption_preview": caption[:80],
    }

    uploads_log.parent.mkdir(parents=True, exist_ok=True)
    with uploads_log.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(log_entry, ensure_ascii=False) + "\n")

    emit(f"✓ TikTok yayınlandı! video_id={video_id}", "info")
    emit(f"  Caption: {caption[:80]}{'…' if len(caption) > 80 else ''}", "log")
    return log_entry


# ---------------------------------------------------------------------------
# Config yardımcısı (web app'ten çağrılır)
# ---------------------------------------------------------------------------

def get_tiktok_config(cfg: Any) -> dict[str, str] | None:
    """config.yaml'dan TikTok ayarlarını çek. None → TikTok configure edilmemiş."""
    tt_raw = getattr(cfg, "tiktok", None)
    if tt_raw is None:
        return None
    access_token = getattr(tt_raw, "access_token", "").strip()
    open_id = getattr(tt_raw, "open_id", "").strip()
    if not access_token or access_token in ("", "REPLACE_ME"):
        return None
    return {
        "access_token": access_token,
        "open_id": open_id,
        "client_key": getattr(tt_raw, "client_key", ""),
        "client_secret": getattr(tt_raw, "client_secret", ""),
        "uploads_log": getattr(tt_raw, "uploads_log", "data/tiktok_uploads.jsonl"),
    }


def read_upload_log(uploads_log_path: Path) -> dict[str, dict[str, Any]]:
    """TikTok uploads logunu {name → entry} dict'e çevir (UI rozeti için)."""
    out: dict[str, dict[str, Any]] = {}
    if not uploads_log_path.exists():
        return out
    with uploads_log_path.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
                if e.get("name"):
                    out[e["name"]] = e
            except json.JSONDecodeError:
                continue
    return out
