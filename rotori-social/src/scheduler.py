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
import re
import threading
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any
from urllib.parse import quote

import requests

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
_NGROK_TUNNELS_API = "http://127.0.0.1:4040/api/tunnels"
_CLOUDFLARED_METRICS = "http://127.0.0.1:20241/metrics"


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
    for delta_day in range(90):  # 90 gün ≈ 12 hafta — haftalık slot zinciri için yeterli
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


def next_automation_slot(
    queue: list[dict[str, Any]],
    launchd_days: list[int],
    hour: int,
    minute: int,
    from_dt: datetime | None = None,
    automation_kind: str | None = None,
) -> str:
    """İçerik tipinin otomasyon günlerindeki ilk boş yayın slotunu bul.

    automation_kind verildiyse ("news" | "topic") sadece aynı otomasyon
    kanalındaki kayıtlarla çakışma kontrolü yapılır. automation_kind'i olmayan
    legacy/manual kayıtlar geriye uyum için yine engelleyici kabul edilir.
    """
    days = {int(day) for day in launchd_days if 0 <= int(day) <= 6}
    if not days:
        raise ValueError("Otomasyon için en az bir yayın günü seçilmeli.")

    hour = max(0, min(23, int(hour)))
    minute = max(0, min(59, int(minute)))
    now = from_dt or _now()
    kind_filter = (automation_kind or "").strip().lower() or None

    def _is_occupied(item: dict[str, Any]) -> bool:
        if item.get("status") in ("done", "cancelled", "failed"):
            return False
        if not item.get("scheduled_at"):
            return False
        if kind_filter is None:
            return True

        item_kind = str(item.get("automation_kind") or "").strip().lower()
        if not item_kind:
            # Legacy/manual kayıtlar otomasyon lane'i bilinmediği için bloklayıcı.
            return True
        if item_kind not in ("news", "topic"):
            return True
        return item_kind == kind_filter

    occupied = {
        item.get("scheduled_at")
        for item in queue
        if _is_occupied(item)
    }

    for delta_day in range(90):  # 90 gün ≈ 12 hafta — haftalık slot zinciri için yeterli
        candidate_day = now.date() + timedelta(days=delta_day)
        launchd_weekday = (candidate_day.weekday() + 1) % 7
        if launchd_weekday not in days:
            continue
        slot_dt = datetime(candidate_day.year, candidate_day.month, candidate_day.day,
                           hour, minute)
        if slot_dt <= now:
            continue
        slot = slot_dt.strftime("%Y-%m-%dT%H:%M:%S")
        if slot not in occupied:
            return slot

    raise ValueError("Seçili otomasyon günlerinde 90 gün içinde boş slot bulunamadı. Günlük limiti artırın veya slotları temizleyin.")


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
    auto_publish: bool | None = None,
    automation_kind: str = "",
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
            existing_name = item.get("asset_name") or item.get("mp4_name")
            if existing_name == mp4_path.name and item.get("status") == "failed":
                item["status"] = "cancelled"
                item["cancelled_reason"] = "automation_rescheduled"
            active = item.get("status") not in ("done", "cancelled", "failed")
            if not active:
                continue
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
        if auto_publish is not None:
            entry["auto_publish"] = bool(auto_publish)
        if automation_kind:
            entry["automation_kind"] = automation_kind
        queue.append(entry)
        # scheduled_at'e göre sırala
        queue.sort(key=lambda x: x.get("scheduled_at", ""))
        _save_queue(project_root, queue, queue_file)
        log.info(f"Kuyruğa eklendi [{kind}]: {mp4_path.name} → {scheduled_at}")
        return entry


def sync_automation_slots(
    project_root: Path,
    automation_config: dict[str, Any],
    queue_file: str = "data/scheduler_queue.json",
) -> dict[str, int]:
    """Aktif otomasyon girdilerini güncel tip slotlarına yeniden yerleştir."""
    with _LOCK:
        queue = load_queue(project_root, queue_file)
        movable = [
            item for item in queue
            if item.get("automation_kind") in ("news", "topic")
            and item.get("status") in ("pending", "ready")
        ]
        movable.sort(key=lambda item: (
            item.get("scheduled_at", ""), item.get("added_at", ""),
            item.get("asset_name") or item.get("mp4_name") or "",
        ))
        movable_ids = {id(item) for item in movable}
        occupancy = [item for item in queue if id(item) not in movable_ids]
        rescheduled = 0
        unscheduled = 0

        for item in movable:
            automation_kind = item.get("automation_kind", "")
            slot_cfg = automation_config.get(automation_kind) or {}
            days = [int(day) for day in (slot_cfg.get("days") or [])
                    if 0 <= int(day) <= 6]
            if not slot_cfg.get("enabled") or not days:
                item["status"] = "cancelled"
                item["cancelled_reason"] = "automation_disabled"
                unscheduled += 1
                occupancy.append(item)
                continue
            item["scheduled_at"] = next_automation_slot(
                occupancy, days, int(slot_cfg.get("hour", 9)),
                int(slot_cfg.get("minute", 0)),
                automation_kind=automation_kind,
            )
            item["auto_publish"] = bool(slot_cfg.get("auto_publish", False))
            item.pop("cancelled_reason", None)
            occupancy.append(item)
            rescheduled += 1

        queue.sort(key=lambda item: item.get("scheduled_at", ""))
        _save_queue(project_root, queue, queue_file)
        return {"rescheduled": rescheduled, "unscheduled": unscheduled}


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


def _story_public_url_from_asset(base: str, stories_root: Path | None, asset: Path) -> str:
    """Story dosyası için public URL üret.

    stories_root altında ise alt klasör yapısını korur (örn. ready/xxx.jpg).
    """
    clean_base = base.strip().rstrip("/")
    if stories_root is not None:
        try:
            rel = asset.relative_to(stories_root)
        except ValueError:
            rel = None
        if rel is not None:
            return f"{clean_base}/media/stories/" + "/".join(quote(p) for p in rel.parts)
    return f"{clean_base}/media/stories/{quote(asset.name)}"


def _detect_ngrok_public_base_url(timeout_sn: float = 1.2) -> str | None:
    """Local ngrok API'den aktif HTTPS public URL'i yakala."""
    try:
        resp = requests.get(_NGROK_TUNNELS_API, timeout=timeout_sn)
        resp.raise_for_status()
        payload = resp.json()
    except (requests.RequestException, ValueError):
        return None

    tunnels = payload.get("tunnels") if isinstance(payload, dict) else []
    if not isinstance(tunnels, list):
        return None
    for tunnel in tunnels:
        if not isinstance(tunnel, dict):
            continue
        pub = str(tunnel.get("public_url") or "").strip().rstrip("/")
        if pub.startswith("https://"):
            return pub
    return None


def _detect_trycloudflare_public_base_url(timeout_sn: float = 1.0) -> str | None:
    """cloudflared metrics çıktısından quick tunnel URL'ini yakala."""
    try:
        resp = requests.get(_CLOUDFLARED_METRICS, timeout=timeout_sn)
        resp.raise_for_status()
        text = resp.text
    except requests.RequestException:
        return None

    match = re.search(r'userHostname="(https://[^"\s]+\.trycloudflare\.com)"', text)
    if not match:
        return None
    return match.group(1).strip().rstrip("/")


def _story_url_preflight(url: str, timeout_sn: int = 8) -> tuple[bool, str]:
    """Public URL dışarıdan erişilebilir mi (HTTP 200 + image/*)?"""
    try:
        with requests.get(
            url,
            timeout=timeout_sn,
            stream=True,
            allow_redirects=True,
            headers={"User-Agent": "rotori-social-scheduler/1.0"},
        ) as resp:
            ctype = (resp.headers.get("content-type") or "").split(";")[0].strip().lower()
            if resp.status_code != 200:
                return False, f"HTTP {resp.status_code}"
            if not ctype.startswith("image/"):
                return False, f"content-type={ctype or '-'}"
            return True, "ok"
    except requests.RequestException as exc:
        return False, f"ağ hatası: {exc}"


def _pick_story_public_url(cfg_any: Any, asset: Path, emit: Any = None) -> str:
    """Story yayınında kullanılacak public URL'i seç.

    Önce config'teki public_base_url denenir; erişilemiyorsa local tünel
    adayları (ngrok → trycloudflare) preflight ile test edilip fallback edilir.
    """
    ig = getattr(cfg_any, "instagram", None)
    configured_base = ((ig.public_base_url if ig else "") or "").strip().rstrip("/")

    stories_root = None
    stories_cfg = getattr(cfg_any, "stories", None)
    if stories_cfg is not None:
        stories_root = getattr(stories_cfg, "output_dir", None)
        if stories_root is not None:
            stories_root = Path(stories_root)

    candidate_bases: list[str] = []
    if configured_base:
        candidate_bases.append(configured_base)

    for detected in (
        _detect_ngrok_public_base_url(),
        _detect_trycloudflare_public_base_url(),
    ):
        if detected and detected not in candidate_bases:
            candidate_bases.append(detected)

    if not candidate_bases:
        raise RuntimeError(
            "public_base_url boş — story yayınlanamaz "
            "(ve aktif tünel URL'i de tespit edilemedi)."
        )

    diagnostics: list[str] = []
    for base in candidate_bases:
        image_url = _story_public_url_from_asset(base, stories_root, asset)
        ok, reason = _story_url_preflight(image_url)
        if ok:
            if emit and configured_base and base != configured_base:
                emit(
                    f"ℹ Story public URL fallback aktif: {base}",
                    "warn",
                )
            return image_url
        diagnostics.append(f"{image_url} -> {reason}")

    detail = " | ".join(diagnostics) if diagnostics else "preflight sonucu yok"
    raise RuntimeError(
        "Story public URL erişilemedi. "
        "Aşağıdaki URL'ler test edildi: "
        f"{detail}"
    )


def _ensure_story_asset_ready(cfg_any: Any, item: dict[str, Any], asset: Path) -> Path:
    """Story dosyası ready/ altında değilse oraya taşı ve queue item'ını güncelle."""
    stories_cfg = getattr(cfg_any, "stories", None)
    if stories_cfg is None:
        return asset

    stories_root = Path(getattr(stories_cfg, "output_dir", ""))
    if not stories_root:
        return asset

    try:
        rel = asset.relative_to(stories_root)
    except ValueError:
        return asset

    if rel.parts and rel.parts[0] == "ready":
        return asset

    ready_dir = stories_root / "ready"
    ready_dir.mkdir(parents=True, exist_ok=True)
    target = ready_dir / asset.name

    if target != asset:
        if target.exists():
            asset = target
        else:
            asset.rename(target)
            for suf in (".txt", ".json"):
                src_side = (stories_root / rel).with_suffix(suf)
                dst_side = target.with_suffix(suf)
                if src_side.exists() and not dst_side.exists():
                    src_side.rename(dst_side)
            asset = target

    item["asset_name"] = asset.name
    item["asset_path"] = str(asset)
    item["mp4_name"] = asset.name
    item["mp4_path"] = str(asset)
    return asset


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
        published_stems = _published_stems_from_uploads_log(cfg_any)

        # Housekeeping: içerik uploads_log'da yayınlanmış görünüyorsa kuyruktaki
        # aktif/stale girdiyi otomatik tamamlandıya çek.
        if published_stems:
            completed_at = _now().strftime("%Y-%m-%dT%H:%M:%S")
            for item in queue:
                if item.get("status") in ("done", "cancelled"):
                    continue
                asset_name = item.get("asset_name") or item.get("mp4_name") or ""
                if Path(str(asset_name)).stem not in published_stems:
                    continue
                item["status"] = "done"
                item["result"] = "already_published"
                item["last_result_at"] = item.get("last_result_at") or completed_at
                item["last_result_status"] = "done"
                item.pop("failure_reason", None)
                changed = True
                processed.append(dict(item))
                _emit(f"ℹ Stale kuyruk girdisi kapatıldı (zaten yayınlı): {asset_name}", "log")

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

            attempted_at = _now().strftime("%Y-%m-%dT%H:%M:%S")
            item["last_attempt_at"] = attempted_at
            item["attempt_count"] = int(item.get("attempt_count", 0)) + 1
            item.pop("failure_reason", None)

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
                    item["failure_reason"] = "asset_not_found"
                    item["last_result_at"] = attempted_at
                    item["last_result_status"] = "failed"
                    changed = True
                    continue

            _emit(f"⏰ Zamanı geldi [{kind}]: {asset_name} ({sched_str})", "info")
            item["status"] = "uploading"
            changed = True

            entry_auto_upload = item.get("auto_publish")
            should_upload = auto_upload if entry_auto_upload is None else bool(entry_auto_upload)
            if not should_upload:
                # auto_upload kapalı → kullanıcı UI'dan yayınlar
                item["status"] = "ready"
                item["result"] = "manual_upload_required"
                item["last_result_at"] = attempted_at
                item["last_result_status"] = "ready"
                _emit(f"📋 Hazır (manuel yayın bekleniyor): {asset_name}", "info")
                processed.append(dict(item))
                continue

            try:
                if kind == "story":
                    # Graph API — public HTTPS URL üzerinden yayın
                    from src import instagram_graph
                    before_asset = asset
                    asset = _ensure_story_asset_ready(cfg_any, item, asset)
                    if asset != before_asset:
                        changed = True
                    image_url = _pick_story_public_url(cfg_any, asset, _emit)
                    item["public_url"] = image_url
                    caption = item.get("caption") or ""
                    if not caption:
                        cap_txt = asset.with_suffix(".txt")
                        if cap_txt.exists():
                            try:
                                caption = cap_txt.read_text(encoding="utf-8")
                            except OSError:
                                caption = ""
                    res = instagram_graph.publish_image(cfg_any, image_url, caption)
                    done_at = _now().strftime("%Y-%m-%dT%H:%M:%S")
                    item["status"] = "done"
                    item["result"] = {"media_id": res.get("id"),
                                      "container_id": res.get("container_id"),
                                      "published_at": done_at}
                    item["last_result_at"] = done_at
                    item["last_result_status"] = "done"
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
                    done_at = _now().strftime("%Y-%m-%dT%H:%M:%S")
                    result_payload = dict(result) if isinstance(result, dict) else {"result": result}
                    result_payload.setdefault("uploaded_at", done_at)
                    item["status"] = "done"
                    item["result"] = result_payload
                    item["last_result_at"] = done_at
                    item["last_result_status"] = "done"
                    _emit(f"✓ Draft yüklendi [reel]: {asset_name} "
                          f"(media_id={result.get('media_id')})", "info")
            except Exception as exc:
                failed_at = _now().strftime("%Y-%m-%dT%H:%M:%S")
                item["status"] = "failed"
                item["result"] = str(exc)
                item["failure_reason"] = str(exc)
                item["last_result_at"] = failed_at
                item["last_result_status"] = "failed"
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


def _read_asset_caption(asset_path: Path) -> str:
    cap = asset_path.with_suffix(".txt")
    if not cap.exists():
        return ""
    try:
        return cap.read_text(encoding="utf-8")
    except OSError:
        return ""


def _normalize_entry_asset(item: dict[str, Any], asset_path: Path, caption: str | None = None) -> None:
    name = asset_path.name
    item["kind"] = "story" if name.lower().endswith((".jpg", ".jpeg", ".png")) else "reel"
    item["asset_name"] = name
    item["asset_path"] = str(asset_path)
    # Geriye dönük uyum
    item["mp4_name"] = name
    item["mp4_path"] = str(asset_path)
    item["caption"] = _read_asset_caption(asset_path) if caption is None else caption

    if item.get("status") in ("failed", "ready"):
        item["status"] = "pending"
    item["result"] = None
    item.pop("failure_reason", None)
    item.pop("last_result_status", None)
    
def _published_stems_from_uploads_log(cfg_any: Any) -> set[str]:
    """uploads_log içindeki yayınlanmış içerik stem'lerini döndür.

    cfg_any tam Config olmayabilir (testlerde SimpleNamespace). Alanlardan biri
    eksikse sessizce boş set döner.
    """
    ig = getattr(cfg_any, "instagram", None)
    project_root = getattr(cfg_any, "project_root", None)
    uploads_log = getattr(ig, "uploads_log", None) if ig is not None else None
    if ig is None or project_root is None or not uploads_log:
        return set()

    path = Path(project_root) / str(uploads_log)
    if not path.exists():
        return set()

    stems: set[str] = set()
    try:
        with path.open("r", encoding="utf-8") as fh:
            for line in fh:
                raw = line.strip()
                if not raw:
                    continue
                try:
                    rec = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                name = str(rec.get("name") or "").strip()
                if name:
                    stems.add(name)
    except OSError:
        return set()
    return stems


def maintenance_cleanup(
    project_root: Path,
    cfg_any: Any,
    queue_file: str = "data/scheduler_queue.json",
    emit: Any = None,
) -> dict[str, Any]:
    """uploads_log'a göre stale kuyruk girdilerini done durumuna geçir."""

    def _emit(msg: str, lvl: str = "log") -> None:
        if emit:
            emit(msg, lvl)
        else:
            log.info(msg)

    with _LOCK:
        queue = load_queue(project_root, queue_file)
        published_stems = _published_stems_from_uploads_log(cfg_any)
        if not published_stems:
            return {"ok": True, "cleaned": 0, "items": []}

        cleaned_items: list[dict[str, Any]] = []
        changed = False
        completed_at = _now().strftime("%Y-%m-%dT%H:%M:%S")

        for item in queue:
            if item.get("status") in ("done", "cancelled"):
                continue
            asset_name = item.get("asset_name") or item.get("mp4_name") or ""
            if Path(str(asset_name)).stem not in published_stems:
                continue

            item["status"] = "done"
            item["result"] = "already_published"
            item["last_result_at"] = item.get("last_result_at") or completed_at
            item["last_result_status"] = "done"
            item.pop("failure_reason", None)
            changed = True
            cleaned_items.append(dict(item))
            _emit(f"ℹ Maintenance cleanup: stale kayıt kapatıldı → {asset_name}", "log")

        if changed:
            _save_queue(project_root, queue, queue_file)

        return {"ok": True, "cleaned": len(cleaned_items), "items": cleaned_items}


def replace_entry_asset(
    project_root: Path,
    entry_id: str,
    asset_path: Path,
    queue_file: str = "data/scheduler_queue.json",
    caption: str | None = None,
) -> dict[str, Any] | None:
    """Aktif kuyruk girdisinin medya dosyasını değiştir.

    Eğer yeni dosya başka bir aktif girdide kullanılıyorsa iki girdinin medyası
    swap edilir (slotlar korunur).
    """
    with _LOCK:
        queue = load_queue(project_root, queue_file)
        target: dict[str, Any] | None = None
        for item in queue:
            if item.get("id") == entry_id:
                target = item
                break
        if target is None:
            return None

        status = target.get("status")
        if status in ("done", "cancelled", "uploading"):
            raise ValueError(f"Bu durumda replace yapılamaz: {status}")

        current_name = target.get("asset_name") or target.get("mp4_name") or ""
        if current_name == asset_path.name:
            return {"entry": dict(target), "swapped_with": None}

        current_caption = target.get("caption", "")
        current_path = Path(target.get("asset_path") or target.get("mp4_path") or current_name)
        if not current_path.is_absolute():
            current_path = project_root / current_path

        swap_entry: dict[str, Any] | None = None
        for item in queue:
            if item is target:
                continue
            if item.get("status") in ("done", "cancelled"):
                continue
            other_name = item.get("asset_name") or item.get("mp4_name") or ""
            if other_name == asset_path.name:
                if item.get("status") == "uploading":
                    raise ValueError("Seçilen görsel şu anda yayınlanıyor, değiştirilemez.")
                swap_entry = item
                break

        _normalize_entry_asset(target, asset_path, caption)

        swapped_with = None
        if swap_entry is not None and current_name:
            swap_asset_path = current_path
            if not swap_asset_path.exists():
                candidate = asset_path.parent / current_name
                if candidate.exists():
                    swap_asset_path = candidate
            _normalize_entry_asset(swap_entry, swap_asset_path, current_caption)
            swapped_with = swap_entry.get("id")

        queue.sort(key=lambda item: item.get("scheduled_at", ""))
        _save_queue(project_root, queue, queue_file)
        log.info(f"Queue replace: {entry_id} -> {asset_path.name}" +
                 (f" (swap {swapped_with})" if swapped_with else ""))
        return {"entry": dict(target), "swapped_with": swapped_with}


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
