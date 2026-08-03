"""Posting Scheduler — TEK yayın kuyruğu (Reels MP4 + Story JPG kartlar).

Bu modül Buffer/Later benzeri bir "unified queue" implement eder:
    - Kuyruğa hem MP4 (kind="reel") hem JPG (kind="story") girebilir.
    - Zamanı gelen öğe, tipine göre doğru publisher'a gider:
        reel  → instagram_publisher.upload_draft() (private API — draft yükleme)
        story → instagram_graph.publish_image()   (resmi Graph API — direkt yayın)
    - Aynı slot iki kez dolmaz; daily_limit aşılırsa sonraki güne öteleme.
    - Timezone: Europe/Istanbul (UTC+3) sabittir — kullanıcı hesabının bulunduğu TZ.

Web API (bkz. src/web/app.py):
    GET    /api/scheduler/queue              → tüm kuyruk + istatistik
    POST   /api/scheduler/queue              → Reels MP4 ekle
    POST   /api/scheduler/schedule_story     → Onay bekleyen kartı ready'e taşı + kuyruğa ekle
    POST   /api/scheduler/reschedule/{id}    → slotu değiştir
    DELETE /api/scheduler/queue/{id}         → iptal (status=cancelled)
    POST   /api/scheduler/run                → zamanı geleni HEMEN işle

Kuyruk şeması (data/scheduler_queue.json — JSON array):
    {
      "id": "reel_kyoto_00_1735000000",
      "kind": "reel" | "story",           # yeni: hangi publisher çağrılır
      "asset_name": "kyoto_00.mp4",       # dosya adı (mp4 veya jpg)
      "asset_path": "…/output/reels/…",
      "caption": "…",
      "scheduled_at": "2026-08-01T18:00:00",   # naive Europe/Istanbul
      "status": "pending"|"uploading"|"done"|"failed"|"cancelled",
      "added_at": "…",
      "result": {...} | "…"
    }

Geriye dönük uyumluluk: eski girdilerde 'mp4_name'/'mp4_path' varsa okurken normalize edilir.
"""
from __future__ import annotations

import json
import threading
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from src.utils.logging import get_logger

# Europe/Istanbul sabit. Sunucu UTC/başka TZ'de olsa bile kullanıcı için
# TR saati konuşuruz. now()'u DIŞ dünyaya bu TZ'de aktarıyoruz.
try:
    from zoneinfo import ZoneInfo
    _TZ = ZoneInfo("Europe/Istanbul")
except Exception:  # noqa: BLE001 — Python 3.9+ hep var, defensive
    _TZ = None


def _now() -> datetime:
    """Europe/Istanbul yerel saatinde naive datetime döndürür (kuyruk formatıyla uyumlu)."""
    if _TZ is not None:
        return datetime.now(_TZ).replace(tzinfo=None)
    return datetime.now()

log = get_logger("scheduler")

_LOCK = threading.Lock()


# ---------------------------------------------------------------------------
# Kuyruk dosyası yardımcıları
# ---------------------------------------------------------------------------

def _queue_path(project_root: Path, queue_file: str = "data/scheduler_queue.json") -> Path:
    p = Path(queue_file)
    return p if p.is_absolute() else project_root / p


def load_queue(project_root: Path, queue_file: str = "data/scheduler_queue.json") -> list[dict[str, Any]]:
    path = _queue_path(project_root, queue_file)
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except (OSError, json.JSONDecodeError):
        return []


def _save_queue(project_root: Path, queue: list[dict[str, Any]], queue_file: str) -> None:
    path = _queue_path(project_root, queue_file)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(queue, ensure_ascii=False, indent=2), encoding="utf-8")


# ---------------------------------------------------------------------------
# Tarih/saat hesaplama
# ---------------------------------------------------------------------------

def _next_available_slot(
    queue: list[dict[str, Any]],
    daily_limit: int,
    default_times: list[str],
    from_dt: datetime | None = None,
) -> str:
    """Kuyrukta daily_limit'i aşmayacak şekilde sonraki boş slot'u bul.

    Returns: ISO 8601 string 'YYYY-MM-DDTHH:MM:SS'
    """
    if not default_times:
        default_times = ["08:00", "18:00"]

    now = from_dt or _now()
    # Kuyruktaki planlanmış saatleri gün → count haritasına dön
    day_counts: dict[str, int] = {}
    for item in queue:
        if item.get("status") in ("done", "cancelled"):
            continue
        sch = item.get("scheduled_at", "")
        if sch:
            day = sch[:10]  # YYYY-MM-DD
            day_counts[day] = day_counts.get(day, 0) + 1

    # Gün + saat kombinasyonlarını tara, ilk boşu döndür
    for delta_day in range(60):  # en fazla 60 gün ileriye bak
        candidate_day = now.date() + timedelta(days=delta_day)
        day_str = candidate_day.isoformat()
        count = day_counts.get(day_str, 0)
        if count >= daily_limit:
            continue
        for t in default_times:
            hh, mm = t.split(":")
            slot_dt = datetime(candidate_day.year, candidate_day.month, candidate_day.day,
                               int(hh), int(mm), 0)
            # Geçmiş slotları atla
            if slot_dt <= now:
                continue
            # Bu slot dolu mu?
            slot_str = slot_dt.strftime("%Y-%m-%dT%H:%M:%S")
            if any(i.get("scheduled_at") == slot_str and i.get("status") not in ("done", "cancelled")
                   for i in queue):
                continue
            return slot_str

    # Fallback: 7 gün sonra 08:00
    fallback = now + timedelta(days=7)
    return fallback.strftime("%Y-%m-%dT08:00:00")


# ---------------------------------------------------------------------------
# Kuyruğa ekleme / çıkarma
# ---------------------------------------------------------------------------

def enqueue(
    project_root: Path,
    mp4_path: Path,
    caption: str = "",
    scheduled_at: str | None = None,   # None → otomatik hesapla
    daily_limit: int = 2,
    default_times: list[str] | None = None,
    queue_file: str = "data/scheduler_queue.json",
    kind: str = "reel",                # "reel" (mp4) | "story" (jpg)
) -> dict[str, Any]:
    """Asset'i (MP4 reel veya JPG story) posting kuyruğuna ekle.

    Returns: eklenen kuyruk girdisi
    Raises: ValueError — aynı dosya zaten kuyruğa eklenmişse
    """
    times = default_times or ["08:00", "18:00"]
    kind = kind if kind in ("reel", "story") else "reel"

    with _LOCK:
        queue = load_queue(project_root, queue_file)

        # Idempotency: aynı dosya zaten kuyrukta aktif mi?
        for item in queue:
            active = item.get("status") not in ("done", "cancelled", "failed")
            if not active:
                continue
            existing_name = item.get("asset_name") or item.get("mp4_name")
            if existing_name == mp4_path.name:
                raise ValueError(f"Bu içerik zaten kuyrukta: {mp4_path.name}")

        if not scheduled_at:
            scheduled_at = _next_available_slot(queue, daily_limit, times)

        prefix = "story" if kind == "story" else "reel"
        entry: dict[str, Any] = {
            "id": f"{prefix}_{mp4_path.stem}_{int(time.time())}",
            "kind": kind,
            "asset_name": mp4_path.name,
            "asset_path": str(mp4_path),
            # Geriye dönük uyum — eski UI/kod hâlâ mp4_name okuyor olabilir
            "mp4_name": mp4_path.name,
            "mp4_path": str(mp4_path),
            "caption": caption,
            "scheduled_at": scheduled_at,
            "status": "pending",       # pending | uploading | done | failed | cancelled
            "added_at": _now().strftime("%Y-%m-%dT%H:%M:%S"),
            "result": None,
        }
        queue.append(entry)
        # scheduled_at'e göre sırala
        queue.sort(key=lambda x: x.get("scheduled_at", ""))
        _save_queue(project_root, queue, queue_file)
        log.info(f"Kuyruğa eklendi [{kind}]: {mp4_path.name} → {scheduled_at}")
        return entry


def remove_from_queue(
    project_root: Path,
    entry_id: str,
    queue_file: str = "data/scheduler_queue.json",
) -> bool:
    """Kuyruktan ID ile çıkar. True döner başarılıysa."""
    with _LOCK:
        queue = load_queue(project_root, queue_file)
        before = len(queue)
        queue = [i for i in queue if i.get("id") != entry_id]
        if len(queue) == before:
            return False
        _save_queue(project_root, queue, queue_file)
        log.info(f"Kuyruktan çıkarıldı: {entry_id}")
        return True


def cancel_entry(
    project_root: Path,
    entry_id: str,
    queue_file: str = "data/scheduler_queue.json",
) -> bool:
    """Kaydı silmek yerine 'cancelled' yap — log için sakla."""
    with _LOCK:
        queue = load_queue(project_root, queue_file)
        for item in queue:
            if item.get("id") == entry_id:
                item["status"] = "cancelled"
                _save_queue(project_root, queue, queue_file)
                return True
        return False


# ---------------------------------------------------------------------------
# Zamanı gelen girdileri işle
# ---------------------------------------------------------------------------

def process_due(
    project_root: Path,
    output_dir: Path,
    cfg_any: Any,          # src.config.Config — import döngüsünden kaçınmak için Any
    queue_file: str = "data/scheduler_queue.json",
    auto_upload: bool = False,
    emit: Any = None,
) -> list[dict[str, Any]]:
    """Scheduled_at zamanı gelmiş 'pending' girdileri işle.

    - kind='reel'  → instagram_publisher.upload_draft(mp4)     (private, draft)
    - kind='story' → instagram_graph.publish_image(image_url)  (resmi Graph)
    auto_upload=False: sadece 'ready' işaretlenir; kullanıcı UI'dan yayınlar.
    """
    def _emit(msg: str, lvl: str = "log") -> None:
        if emit:
            emit(msg, lvl)
        else:
            log.info(msg)

    now = _now()
    processed = []

    with _LOCK:
        queue = load_queue(project_root, queue_file)
        changed = False

        for item in queue:
            if item.get("status") != "pending":
                continue
            sched_str = item.get("scheduled_at", "")
            if not sched_str:
                continue
            try:
                sched_dt = datetime.fromisoformat(sched_str)
            except ValueError:
                continue
            if sched_dt > now:
                continue  # henüz zamanı gelmedi

            # Asset yolu — yeni şema (asset_path) veya eski (mp4_path)
            asset_name = item.get("asset_name") or item.get("mp4_name", "")
            asset_path_str = item.get("asset_path") or item.get("mp4_path", "")
            kind = item.get("kind") or ("story" if asset_name.lower().endswith((".jpg", ".jpeg", ".png")) else "reel")

            asset = Path(asset_path_str) if asset_path_str else Path()
            if not asset.exists():
                candidate = output_dir / asset_name
                if candidate.exists():
                    asset = candidate
                else:
                    _emit(f"⚠ Dosya bulunamadı, atlanıyor: {asset_name}", "warn")
                    item["status"] = "failed"
                    item["result"] = "asset_not_found"
                    changed = True
                    continue

            _emit(f"⏰ Zamanı geldi [{kind}]: {asset_name} ({sched_str})", "info")
            item["status"] = "uploading"
            changed = True

            if not auto_upload:
                # auto_upload kapalı → kullanıcı UI'dan yayınlar
                item["status"] = "ready"
                item["result"] = "manual_upload_required"
                _emit(f"📋 Hazır (manuel yayın bekleniyor): {asset_name}", "info")
                processed.append(dict(item))
                continue

            try:
                if kind == "story":
                    # Graph API — public HTTPS URL üzerinden yayın
                    from src import instagram_graph
                    ig = getattr(cfg_any, "instagram", None)
                    base = ((ig.public_base_url if ig else "") or "").strip().rstrip("/")
                    if not base:
                        raise RuntimeError("public_base_url boş — story yayınlanamaz")
                    # Kart 'ready/' altındaysa oradan servis edelim; değilse output_dir'e göre relative
                    from urllib.parse import quote
                    stories_root = None
                    stories_cfg = getattr(cfg_any, "stories", None)
                    if stories_cfg is not None:
                        stories_root = stories_cfg.output_dir
                    if stories_root and asset.is_relative_to(stories_root):
                        rel = asset.relative_to(stories_root)
                        image_url = f"{base}/media/stories/" + "/".join(quote(p) for p in rel.parts)
                    else:
                        image_url = f"{base}/media/stories/{quote(asset.name)}"
                    caption = item.get("caption") or ""
                    if not caption:
                        cap_txt = asset.with_suffix(".txt")
                        if cap_txt.exists():
                            try:
                                caption = cap_txt.read_text(encoding="utf-8")
                            except OSError:
                                caption = ""
                    res = instagram_graph.publish_image(cfg_any, image_url, caption)
                    item["status"] = "done"
                    item["result"] = {"media_id": res.get("id"),
                                      "container_id": res.get("container_id")}
                    _emit(f"✅ Yayınlandı [story]: {asset_name} · media_id={res.get('id')}", "info")
                else:
                    # Reel — private API draft
                    from src import instagram_publisher
                    from threading import Event
                    cancel_ev = Event()
                    caption = item.get("caption", "")
                    result = instagram_publisher.upload_draft(
                        cfg_any, asset, caption, _emit, cancel_ev
                    )
                    item["status"] = "done"
                    item["result"] = result
                    _emit(f"✓ Draft yüklendi [reel]: {asset_name} "
                          f"(media_id={result.get('media_id')})", "info")
            except Exception as exc:
                item["status"] = "failed"
                item["result"] = str(exc)
                _emit(f"✖ Yayın başarısız ({asset_name}): {exc}", "error")

            processed.append(dict(item))

        if changed:
            _save_queue(project_root, queue, queue_file)

    return processed


def reschedule(
    project_root: Path,
    entry_id: str,
    new_scheduled_at: str,
    queue_file: str = "data/scheduler_queue.json",
) -> dict[str, Any] | None:
    """Bekleyen bir girdinin slotunu değiştir. Sadece pending/ready üzerinde geçerli."""
    with _LOCK:
        queue = load_queue(project_root, queue_file)
        target = None
        for item in queue:
            if item.get("id") == entry_id:
                target = item
                break
        if target is None:
            return None
        if target.get("status") in ("done", "cancelled", "uploading"):
            raise ValueError(f"Bu durumda reschedule yapılamaz: {target.get('status')}")
        # yeni zamanı doğrula
        try:
            datetime.fromisoformat(new_scheduled_at)
        except ValueError as exc:
            raise ValueError(f"Geçersiz tarih: {new_scheduled_at}") from exc
        target["scheduled_at"] = new_scheduled_at
        # başarısızlıktan dönebilsin
        if target.get("status") in ("failed", "ready"):
            target["status"] = "pending"
            target["result"] = None
        queue.sort(key=lambda x: x.get("scheduled_at", ""))
        _save_queue(project_root, queue, queue_file)
        log.info(f"Reschedule: {entry_id} → {new_scheduled_at}")
        return dict(target)


# ---------------------------------------------------------------------------
# Kuyruk özeti (dashboard için)
# ---------------------------------------------------------------------------

def queue_summary(project_root: Path, queue_file: str = "data/scheduler_queue.json") -> dict[str, Any]:
    """Dashboard gösterimi için kuyruk istatistikleri + takvim grupları."""
    queue = load_queue(project_root, queue_file)
    active = [i for i in queue if i.get("status") not in ("done", "cancelled")]
    pending = [i for i in active if i.get("status") == "pending"]
    ready = [i for i in active if i.get("status") == "ready"]
    failed = [i for i in queue if i.get("status") == "failed"]
    done = [i for i in queue if i.get("status") == "done"]

    # normalize: eski girdilerde asset_name/kind boş olabilir → doldur
    for it in active:
        if not it.get("asset_name"):
            it["asset_name"] = it.get("mp4_name", "")
        if not it.get("asset_path"):
            it["asset_path"] = it.get("mp4_path", "")
        if not it.get("kind"):
            it["kind"] = "story" if it["asset_name"].lower().endswith((".jpg", ".jpeg", ".png")) else "reel"

    # Countdown + takvim bucket'ları (Europe/Istanbul)
    now = _now()
    today = now.date()
    tomorrow = today + timedelta(days=1)
    week_end = today + timedelta(days=7)

    def _bucket(sched_str: str) -> tuple[str, int]:
        """(bucket_label, seconds_until) döner."""
        try:
            dt = datetime.fromisoformat(sched_str)
        except (ValueError, TypeError):
            return ("unknown", 0)
        secs = int((dt - now).total_seconds())
        d = dt.date()
        if secs < 0:
            return ("overdue", secs)
        if d == today:
            return ("today", secs)
        if d == tomorrow:
            return ("tomorrow", secs)
        if d <= week_end:
            return ("this_week", secs)
        return ("later", secs)

    for it in active:
        bucket, secs = _bucket(it.get("scheduled_at", ""))
        it["_bucket"] = bucket
        it["_seconds_until"] = secs

    next_item = pending[0] if pending else None

    return {
        "total": len(queue),
        "pending": len(pending),
        "ready": len(ready),
        "failed": len(failed),
        "done": len(done),
        "next_scheduled": next_item.get("scheduled_at") if next_item else None,
        "next_mp4": next_item.get("asset_name") or next_item.get("mp4_name") if next_item else None,
        "next_asset": next_item.get("asset_name") if next_item else None,
        "now": now.strftime("%Y-%m-%dT%H:%M:%S"),
        "timezone": "Europe/Istanbul",
        "items": sorted(active, key=lambda x: x.get("scheduled_at", "")),
    }


# ---------------------------------------------------------------------------
# Background scheduler thread
# ---------------------------------------------------------------------------

_bg_thread: threading.Thread | None = None
_bg_stop = threading.Event()


def start_background_scheduler(
    project_root: Path,
    output_dir: Path,
    cfg_any: Any,
    queue_file: str = "data/scheduler_queue.json",
    auto_upload: bool = False,
    check_interval_sn: int = 60,
) -> None:
    """Web sunucusu başladığında çağrılır — dakikada bir process_due() çalıştırır."""
    global _bg_thread, _bg_stop

    if _bg_thread and _bg_thread.is_alive():
        log.info("Scheduler thread zaten çalışıyor.")
        return

    _bg_stop.clear()

    def _loop() -> None:
        log.info(f"Scheduler başladı (kontrol aralığı: {check_interval_sn}s, auto_upload={auto_upload})")
        while not _bg_stop.is_set():
            try:
                processed = process_due(
                    project_root, output_dir, cfg_any,
                    queue_file=queue_file, auto_upload=auto_upload
                )
                if processed:
                    log.info(f"Scheduler: {len(processed)} girdi işlendi.")
            except Exception as exc:
                log.warning(f"Scheduler döngü hatası: {exc}")
            _bg_stop.wait(timeout=check_interval_sn)
        log.info("Scheduler durduruldu.")

    _bg_thread = threading.Thread(target=_loop, daemon=True, name="reels-scheduler")
    _bg_thread.start()


def stop_background_scheduler() -> None:
    global _bg_stop
    _bg_stop.set()
