"""Reels Posting Scheduler — haftalık yayın kuyruğu ve otomatik Instagram draft upload.

Kullanım (web API üzerinden):
    POST /api/scheduler/queue      → Reels MP4'ünü kuyruğa ekle + hedef tarih/saat
    GET  /api/scheduler/queue      → Kuyruktaki tüm girdileri listele
    DELETE /api/scheduler/queue/{id} → Kuyruktan çıkar
    POST /api/scheduler/run        → Şu an zamanı gelen girdileri işle (manuel tetik)

Scheduler config (config.yaml → scheduler):
    enabled: true
    daily_limit: 2          # günde max kaç Reels yayınlanır
    default_times: ["08:00", "18:00"]   # varsayılan yayın saatleri (UTC+3)
    auto_upload: false      # true → Instagram upload otomatik; false → sadece kuyruk
    queue_file: data/scheduler_queue.json

Tasarım notları:
- Kuyruk: data/scheduler_queue.json (JSON Lines değil, tam JSON array — düzenleme kolaylığı)
- Idempotent: aynı MP4 iki kez kuyruğa eklenemez
- Her MP4 için opsiyonel caption; yoksa final.json'daki aciklama + hashtagler birleştirilir
- auto_upload=True ise web scheduler background thread'inden upload_draft() çağrılır
- daily_limit aşılırsa sonraki uygun güne öteleme (round-robin saat havuzu)
"""
from __future__ import annotations

import json
import threading
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from src.utils.logging import get_logger

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

    now = from_dt or datetime.now()
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
) -> dict[str, Any]:
    """MP4'ü posting kuyruğuna ekle.

    Returns: eklenen kuyruk girdisi
    Raises: ValueError — aynı MP4 zaten kuyruğa eklenmişse
    """
    times = default_times or ["08:00", "18:00"]

    with _LOCK:
        queue = load_queue(project_root, queue_file)

        # Idempotency: aynı dosya zaten kuyruğa eklenmiş mi?
        for item in queue:
            if (item.get("mp4_name") == mp4_path.name
                    and item.get("status") not in ("done", "cancelled")):
                raise ValueError(f"Bu Reels zaten kuyruğa eklenmiş: {mp4_path.name}")

        if not scheduled_at:
            scheduled_at = _next_available_slot(queue, daily_limit, times)

        entry: dict[str, Any] = {
            "id": f"reel_{mp4_path.stem}_{int(time.time())}",
            "mp4_name": mp4_path.name,
            "mp4_path": str(mp4_path),
            "caption": caption,
            "scheduled_at": scheduled_at,
            "status": "pending",       # pending | uploading | done | failed | cancelled
            "added_at": datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
            "result": None,
        }
        queue.append(entry)
        # scheduled_at'e göre sırala
        queue.sort(key=lambda x: x.get("scheduled_at", ""))
        _save_queue(project_root, queue, queue_file)
        log.info(f"Kuyruğa eklendi: {mp4_path.name} → {scheduled_at}")
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

    auto_upload=True: instagram_publisher.upload_draft() çağrılır.
    auto_upload=False: sadece status='ready' yapılır, kullanıcı web UI'dan yayınlar.

    Returns: işlenen girdilerin listesi
    """
    def _emit(msg: str, lvl: str = "log") -> None:
        if emit:
            emit(msg, lvl)
        else:
            log.info(msg)

    now = datetime.now()
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

            mp4 = Path(item["mp4_path"])
            if not mp4.exists():
                # output_dir içinde ara
                mp4_candidate = output_dir / item["mp4_name"]
                if mp4_candidate.exists():
                    mp4 = mp4_candidate
                else:
                    _emit(f"⚠ MP4 bulunamadı, atlanıyor: {item['mp4_name']}", "warn")
                    item["status"] = "failed"
                    item["result"] = "mp4_not_found"
                    changed = True
                    continue

            _emit(f"⏰ Zamanı geldi: {item['mp4_name']} ({sched_str})", "info")
            item["status"] = "uploading"
            changed = True

            if auto_upload:
                try:
                    from src import instagram_publisher
                    from threading import Event
                    cancel_ev = Event()
                    caption = item.get("caption", "")
                    result = instagram_publisher.upload_draft(
                        cfg_any, mp4, caption, _emit, cancel_ev
                    )
                    item["status"] = "done"
                    item["result"] = result
                    _emit(f"✓ Draft yüklendi: {item['mp4_name']} (media_id={result.get('media_id')})", "info")
                except Exception as exc:
                    item["status"] = "failed"
                    item["result"] = str(exc)
                    _emit(f"✖ Upload başarısız ({item['mp4_name']}): {exc}", "error")
            else:
                # auto_upload kapalı → kullanıcı web UI'dan yayınlar
                item["status"] = "ready"
                item["result"] = "manual_upload_required"
                _emit(f"📋 Hazır (manuel yayın bekleniyor): {item['mp4_name']}", "info")

            processed.append(dict(item))

        if changed:
            _save_queue(project_root, queue, queue_file)

    return processed


# ---------------------------------------------------------------------------
# Kuyruk özeti (dashboard için)
# ---------------------------------------------------------------------------

def queue_summary(project_root: Path, queue_file: str = "data/scheduler_queue.json") -> dict[str, Any]:
    """Dashboard gösterimi için kuyruk istatistikleri."""
    queue = load_queue(project_root, queue_file)
    active = [i for i in queue if i.get("status") not in ("done", "cancelled")]
    pending = [i for i in active if i.get("status") == "pending"]
    ready = [i for i in active if i.get("status") == "ready"]
    failed = [i for i in queue if i.get("status") == "failed"]
    done = [i for i in queue if i.get("status") == "done"]

    next_item = pending[0] if pending else None

    return {
        "total": len(queue),
        "pending": len(pending),
        "ready": len(ready),
        "failed": len(failed),
        "done": len(done),
        "next_scheduled": next_item.get("scheduled_at") if next_item else None,
        "next_mp4": next_item.get("mp4_name") if next_item else None,
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
