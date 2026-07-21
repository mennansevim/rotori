"""Unsplash otomatik arka plan indirici.

Story kartlarına arka plan olacak Japan temalı görselleri
`assets/story_backgrounds/` klasörüne indirir. Her sorgu için N adet
portrait-oriented CC0 fotoğraf (Getty benzeri kalite, ticari kullanım OK).

Dosya adı formatı: `unsplash-<query-slug>-<photo-id>.jpg`
→ story_generator._pick_from_assets buradaki query-slug'ı arıyor, GPT'nin
   arka_plan_anahtarlar'ıyla eşleşiyor.

Free tier: 50 istek/saat. Kullanıcı config'de 10 sorgu × 3 görsel = 30 dosya
(10 arama + 30 indirme = 40 istek — bol bol yeter).
"""
from __future__ import annotations

import re
import time
import unicodedata
from pathlib import Path
from threading import Event
from typing import Any, Callable

import requests

from src.config import Config
from src.utils.logging import get_logger

log = get_logger("downloader")


def _slugify(text: str) -> str:
    t = (text or "").lower()
    t = "".join(c for c in unicodedata.normalize("NFKD", t)
                if not unicodedata.combining(c))
    t = re.sub(r"[^a-z0-9]+", "-", t).strip("-")
    return t or "generic"


def _search_photos(access_key: str, query: str, per_page: int,
                   orientation: str) -> list[dict[str, Any]]:
    r = requests.get(
        "https://api.unsplash.com/search/photos",
        headers={
            "Authorization": f"Client-ID {access_key}",
            "Accept-Version": "v1",
        },
        params={
            "query": query,
            "per_page": max(per_page, 5),
            "orientation": orientation,
            "content_filter": "high",
        },
        timeout=30,
    )
    r.raise_for_status()
    data = r.json()
    return data.get("results", [])


def _track_download(access_key: str, download_link: str) -> None:
    """Unsplash guideline'a göre indirmeler track edilmeli (analytics).
    Bu istek attribution'a bilgi verir — ücretsiz."""
    try:
        requests.get(download_link,
                     headers={"Authorization": f"Client-ID {access_key}"},
                     timeout=10)
    except requests.RequestException:
        pass  # tracking non-critical


def download_backgrounds(cfg: Config, emit: Callable[..., None],
                         cancel: Event) -> None:
    """Config'deki tüm query'ler için görsel indir. Idempotent (var olanı
    atlar), iptal edilebilir."""
    if cfg.unsplash is None:
        emit("✖ Unsplash config yok. config.yaml → unsplash.access_key doldur.", "error")
        return
    if cfg.stories is None or cfg.stories.backgrounds_dir is None:
        emit("✖ stories.backgrounds_dir yok. config.yaml → stories.backgrounds_dir doldur.", "error")
        return

    dst_dir = cfg.stories.backgrounds_dir
    dst_dir.mkdir(parents=True, exist_ok=True)

    queries = cfg.unsplash.queries or []
    if not queries:
        emit("⚠ unsplash.queries listesi boş.", "warn")
        return

    emit(f"① Unsplash indirici başlıyor — {len(queries)} sorgu × {cfg.unsplash.per_query} görsel", "info")
    emit(f"   klasör: {dst_dir}", "log")

    total_downloaded = 0
    total_skipped = 0
    total_failed = 0

    for q_idx, query in enumerate(queries, 1):
        if cancel.is_set():
            emit("⏹ İptal edildi.", "warn")
            break

        slug = _slugify(query)
        emit(f"── [{q_idx}/{len(queries)}] '{query}' ──", "info")

        try:
            photos = _search_photos(
                cfg.unsplash.access_key, query,
                per_page=cfg.unsplash.per_query,
                orientation=cfg.unsplash.orientation,
            )
        except requests.HTTPError as exc:
            emit(f"  ✗ arama başarısız: HTTP {exc.response.status_code} — "
                 f"{exc.response.text[:120]}", "error")
            if exc.response.status_code in (401, 403):
                emit("  ✗ access_key geçersiz olabilir; unsplash.com/developers'dan doğrula.", "error")
                break
            continue
        except requests.RequestException as exc:
            emit(f"  ✗ ağ hatası: {exc}", "error")
            continue

        emit(f"  {len(photos)} sonuç bulundu, ilk {cfg.unsplash.per_query} indirilecek", "log")
        for photo in photos[: cfg.unsplash.per_query]:
            if cancel.is_set():
                break
            pid = photo.get("id", "unknown")
            photographer = photo.get("user", {}).get("username", "unknown")
            urls = photo.get("urls", {})
            img_url = urls.get("regular") or urls.get("full")
            dl_track = photo.get("links", {}).get("download_location", "")

            if not img_url:
                emit(f"  ⚠ {pid}: URL yok, atlanıyor", "warn")
                continue

            filename = f"unsplash-{slug}-{pid}.jpg"
            dst = dst_dir / filename
            if dst.exists():
                total_skipped += 1
                emit(f"  ⤵ {filename} zaten var", "log")
                continue

            try:
                img_r = requests.get(img_url, timeout=60, stream=True)
                img_r.raise_for_status()
                with dst.open("wb") as fh:
                    for chunk in img_r.iter_content(chunk_size=8192):
                        fh.write(chunk)
                size_kb = dst.stat().st_size // 1024
                total_downloaded += 1
                emit(f"  ✓ {filename} ({size_kb} KB) — @{photographer}", "log")

                # Unsplash guideline: her download'da tracking endpoint'e ping
                if dl_track:
                    _track_download(cfg.unsplash.access_key, dl_track)

                # rate limit için nezaket gecikmesi
                time.sleep(0.3)
            except (requests.RequestException, OSError) as exc:
                total_failed += 1
                emit(f"  ✗ indirme hatası {pid}: {exc}", "error")
                if dst.exists():
                    dst.unlink()

    emit(f"② Bitti — indirilen: {total_downloaded} · atlanan: {total_skipped} · "
         f"başarısız: {total_failed}. Toplam dosya: "
         f"{len(list(dst_dir.glob('*.jpg')) + list(dst_dir.glob('*.png')) + list(dst_dir.glob('*.webp')))}",
         "info")
