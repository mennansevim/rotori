"""Dashboard durum toplayıcı (aggregation).

Bu modül YENİ bir veri kaynağı DEĞİLDİR — mevcut gerçek verileri
(story kartı klasörleri, scheduler kuyruğu, automation config, uploads log)
tek bir normalize durum modeline dönüştürür. Yeni tasarım UI'ı buradan beslenir.

İçerik = Instagram post kartı (JPG + .txt caption + .json meta). Durum, dosyanın
bulunduğu klasörle temsil edilir:

    output/stories/*.jpg                 → draft   (taslak / ertelenmiş)
    output/stories/pending_approval/*.jpg → pending_approval (onay bekliyor)
    output/stories/ready/*.jpg            → approved/ready · scheduler kuyruğundaysa
                                            queued/scheduled · uploads_log'daysa published

Durum modeli (prompt sözleşmesi):
    draft · pending_approval · approved · queued · scheduled · publishing ·
    published · rejected · failed

Reddedilenler dosya sisteminden silindiği için (approval_reject) kalıcı
"rejected" listesi tutulmaz; UI'da reddetme anlık işlemdir.

Saat dilimi: tüm hesaplar scheduler._now() (Europe/Istanbul) üzerinden yürür.
"""
from __future__ import annotations

import json
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any
from urllib.parse import quote

# UI Türkçe karşılıkları — tek kaynak (frontend de aynı haritayı kullanır)
STATUS_TR = {
    "draft": "Taslak",
    "pending_approval": "Onay bekliyor",
    "approved": "Onaylandı",
    "queued": "Kuyrukta",
    "scheduled": "Planlandı",
    "publishing": "Yayınlanıyor",
    "published": "Yayınlandı",
    "rejected": "Reddedildi",
    "failed": "Hata",
}

_IMG_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
_TR_DAYS_SHORT = ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"]  # Monday=0


# ---------------------------------------------------------------------------
# Yardımcılar
# ---------------------------------------------------------------------------
def _now(cfg: Any) -> datetime:
    """Europe/Istanbul now — scheduler ile aynı kaynak."""
    try:
        from src import scheduler as sched_mod
        return sched_mod._now()  # noqa: SLF001
    except Exception:
        return datetime.now()


def _read_meta(jpg: Path) -> dict[str, Any]:
    meta_path = jpg.with_suffix(".json")
    if meta_path.exists():
        try:
            return json.loads(meta_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}
    return {}


def _read_caption(jpg: Path) -> str:
    cap = jpg.with_suffix(".txt")
    if cap.exists():
        try:
            return cap.read_text(encoding="utf-8")
        except OSError:
            return ""
    return ""


def _derive_type(name: str, meta: dict[str, Any]) -> str:
    """İçerik tipi: 'haber' | 'gorsel'."""
    source = str(meta.get("source", meta.get("source_topic", ""))).lower()
    if "news" in source or "haber" in source or name.lower().startswith("news"):
        return "haber"
    return "gorsel"


def _derive_title(name: str, meta: dict[str, Any]) -> str:
    """Kart başlığı: meta.baslik → ust_tag → dosya adından türet."""
    title = (meta.get("baslik") or "").strip()
    if title:
        return title
    aciklama = (meta.get("aciklama") or "").strip()
    if aciklama:
        # ilk cümle / ilk 60 karakter
        first = aciklama.split(". ")[0].strip()
        return first[:80]
    # dosya adı slug'ını okunur hâle getir
    stem = Path(name).stem
    stem = stem.replace("news_", "").replace("topic_", "")
    parts = [p for p in stem.replace("_", " ").split() if not p.isdigit()]
    pretty = " ".join(parts).strip().title()
    return pretty or stem


def _fmt_dt(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%S")


def _mtime_iso(p: Path) -> str:
    return datetime.fromtimestamp(p.stat().st_mtime).strftime("%Y-%m-%dT%H:%M:%S")


# ---------------------------------------------------------------------------
# Kuyruk + yayın log erişimi
# ---------------------------------------------------------------------------
def _queue_summary(cfg: Any) -> dict[str, Any]:
    from src import scheduler as sched_mod
    queue_file = cfg.scheduler.queue_file if getattr(cfg, "scheduler", None) else "data/scheduler_queue.json"
    return sched_mod.queue_summary(cfg.project_root, queue_file)


def _uploads_log(cfg: Any) -> dict[str, Any]:
    if getattr(cfg, "instagram", None) is None:
        return {}
    try:
        from src import instagram_publisher as ig_pub
        return ig_pub.read_upload_log(cfg)  # {stem: {...}}
    except Exception:
        return {}


def _queue_index(summary: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """asset_name → aktif kuyruk girdisi."""
    idx: dict[str, dict[str, Any]] = {}
    for it in summary.get("items", []):
        name = it.get("asset_name") or it.get("mp4_name") or ""
        if name:
            idx[name] = it
    return idx


# ---------------------------------------------------------------------------
# İçerik tarama — tek gerçek kaynak
# ---------------------------------------------------------------------------
def scan_content(cfg: Any) -> list[dict[str, Any]]:
    """Tüm story kartlarını normalize durum modeliyle döndürür."""
    stories = getattr(cfg, "stories", None)
    if stories is None:
        return []
    root: Path = stories.output_dir
    if not root.exists():
        return []

    summary = _queue_summary(cfg)
    qidx = _queue_index(summary)
    uploads = _uploads_log(cfg)

    folders = [
        (root, "draft"),
        (root / "pending_approval", "pending_approval"),
        (root / "ready", "ready"),
    ]

    items: list[dict[str, Any]] = []
    for folder, base_status in folders:
        if not folder.exists():
            continue
        for jpg in folder.glob("*.jpg"):
            if jpg.suffix.lower() not in _IMG_EXTS:
                continue
            meta = _read_meta(jpg)
            caption = _read_caption(jpg)
            name = jpg.name
            ctype = _derive_type(name, meta)
            status = base_status

            # Yayın kuyruğu / yayınlanmış durum ezmesi (ready klasöründeki kartlar)
            scheduled_at = None
            entry_id = None
            queue_status = None
            published = uploads.get(jpg.stem)
            if published:
                status = "published"
            else:
                q = qidx.get(name)
                if q:
                    queue_status = q.get("status")
                    scheduled_at = q.get("scheduled_at")
                    entry_id = q.get("id")
                    if queue_status == "uploading":
                        status = "publishing"
                    elif queue_status == "failed":
                        status = "failed"
                    elif queue_status in ("pending", "ready"):
                        # zamanı planlanmış → scheduled, değilse queued/approved
                        status = "scheduled"
                elif base_status == "ready":
                    status = "approved"

            # media relatif URL
            if base_status == "pending_approval":
                url = f"/media/stories/pending_approval/{quote(name)}"
            elif base_status == "ready":
                url = f"/media/stories/ready/{quote(name)}"
            else:
                url = f"/media/stories/{quote(name)}"

            items.append({
                "name": name,
                "stem": jpg.stem,
                "url": url,
                "type": ctype,
                "status": status,
                "status_tr": STATUS_TR.get(status, status),
                "title": _derive_title(name, meta),
                "aciklama": (meta.get("aciklama") or "").strip(),
                "ust_tag": meta.get("ust_tag", "GEZİ DEFTERİ"),
                "post_caption": caption,
                "source": meta.get("source", meta.get("source_topic", "")),
                "created_at": _mtime_iso(jpg),
                "scheduled_at": scheduled_at,
                "queue_entry_id": entry_id,
                "queue_status": queue_status,
                "published": published or None,
                "size_kb": jpg.stat().st_size // 1024,
            })

    # en yeni önce
    items.sort(key=lambda x: x["created_at"], reverse=True)
    return items


# ---------------------------------------------------------------------------
# Kalan süre / countdown
# ---------------------------------------------------------------------------
def seconds_until(scheduled_at: str | None, now: datetime) -> int | None:
    if not scheduled_at:
        return None
    try:
        dt = datetime.fromisoformat(scheduled_at)
    except (ValueError, TypeError):
        return None
    return int((dt - now).total_seconds())


def humanize_delta(seconds: int | None) -> str:
    """'4 gün 12 saat kaldı' / '42 dakika kaldı' / 'Yayın zamanı geçti'."""
    if seconds is None:
        return "—"
    if seconds < 0:
        return "Yayın zamanı geçti"
    days, rem = divmod(seconds, 86400)
    hours, rem = divmod(rem, 3600)
    minutes = rem // 60
    if days > 0:
        return f"{days} gün {hours} saat kaldı"
    if hours > 0:
        return f"{hours} saat {minutes} dakika kaldı"
    if minutes > 0:
        return f"{minutes} dakika kaldı"
    return "birazdan"


# ---------------------------------------------------------------------------
# Haftalık timeline — gerçek kuyruk + içerik eşleşmesi
# ---------------------------------------------------------------------------
def weekly_timeline(cfg: Any, content: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    """Pazartesi→Pazar bu haftanın planlanmış yayınları."""
    now = _now(cfg)
    if content is None:
        content = scan_content(cfg)
    by_name = {c["name"]: c for c in content}

    summary = _queue_summary(cfg)
    monday = (now - timedelta(days=now.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
    sunday_end = monday + timedelta(days=7)

    # 7 günlük iskelet
    days: list[dict[str, Any]] = []
    for i in range(7):
        d = monday + timedelta(days=i)
        days.append({
            "index": i,
            "day_name": _TR_DAYS_SHORT[i],
            "date": d.strftime("%Y-%m-%d"),
            "date_label": d.strftime("%-d %b"),
            "is_today": d.date() == now.date(),
            "items": [],
        })

    for it in summary.get("items", []):
        sch = it.get("scheduled_at")
        if not sch:
            continue
        try:
            dt = datetime.fromisoformat(sch)
        except (ValueError, TypeError):
            continue
        if not (monday <= dt < sunday_end):
            continue
        name = it.get("asset_name") or it.get("mp4_name") or ""
        content_ref = by_name.get(name, {})
        ctype = content_ref.get("type") or (
            "gorsel" if name.lower().endswith((".jpg", ".jpeg", ".png")) else "haber"
        )
        secs = int((dt - now).total_seconds())
        entry = {
            "name": name,
            "title": content_ref.get("title") or _derive_title(name, {}),
            "type": ctype,
            "time": dt.strftime("%H:%M"),
            "scheduled_at": sch,
            "status": it.get("status"),
            "seconds_until": secs,
            "countdown": humanize_delta(secs),
        }
        days[dt.weekday()]["items"].append(entry)

    return {
        "now": _fmt_dt(now),
        "timezone": "Europe/Istanbul",
        "week_start": monday.strftime("%Y-%m-%d"),
        "days": days,
    }


# ---------------------------------------------------------------------------
# Genel Bakış (overview)
# ---------------------------------------------------------------------------
def overview(cfg: Any) -> dict[str, Any]:
    now = _now(cfg)
    content = scan_content(cfg)
    summary = _queue_summary(cfg)

    drafts = [c for c in content if c["status"] == "draft"]
    pending = [c for c in content if c["status"] == "pending_approval"]
    ready = [c for c in content if c["status"] in ("approved", "queued", "scheduled")]

    timeline = weekly_timeline(cfg, content)
    week_items = [i for d in timeline["days"] for i in d["items"]]
    week_items.sort(key=lambda x: x["scheduled_at"])

    # Sıradaki yayın = en yakın gelecekteki planlı yayın
    next_pub = None
    future = sorted(
        (i for i in summary.get("items", [])
         if i.get("scheduled_at") and i.get("status") in ("pending", "ready")),
        key=lambda x: x["scheduled_at"],
    )
    if future:
        it = future[0]
        secs = seconds_until(it.get("scheduled_at"), now)
        name = it.get("asset_name") or it.get("mp4_name") or ""
        ref = next((c for c in content if c["name"] == name), {})
        next_pub = {
            "name": name,
            "title": ref.get("title") or _derive_title(name, {}),
            "type": ref.get("type") or "gorsel",
            "scheduled_at": it.get("scheduled_at"),
            "seconds_until": secs,
            "countdown": humanize_delta(secs),
        }

    # Yayına hazır sırası (kuyruk sırası)
    ready_queue = []
    for idx, it in enumerate(future, start=1):
        name = it.get("asset_name") or it.get("mp4_name") or ""
        ref = next((c for c in content if c["name"] == name), {})
        secs = seconds_until(it.get("scheduled_at"), now)
        ready_queue.append({
            "order": idx,
            "name": name,
            "title": ref.get("title") or _derive_title(name, {}),
            "type": ref.get("type") or "gorsel",
            "url": ref.get("url"),
            "scheduled_at": it.get("scheduled_at"),
            "countdown": humanize_delta(secs),
        })

    return {
        "now": _fmt_dt(now),
        "date_label": now.strftime("%-d %B %Y"),
        "timezone": "Europe/Istanbul",
        "counts": {
            "drafts": len(drafts),
            "pending_approval": len(pending),
            "ready": len(ready),
            "week_publishes": len(week_items),
        },
        "next_publish": next_pub,
        "timeline": timeline,
        "pending_approval": pending[:6],
        "ready_queue": ready_queue[:8],
    }


# ---------------------------------------------------------------------------
# Yayınlar (publishes) — yaklaşan + yayınlanan
# ---------------------------------------------------------------------------
def publishes(cfg: Any) -> dict[str, Any]:
    now = _now(cfg)
    content = scan_content(cfg)
    summary = _queue_summary(cfg)
    by_name = {c["name"]: c for c in content}

    upcoming = []
    for it in sorted(
        (i for i in summary.get("items", []) if i.get("scheduled_at")),
        key=lambda x: x["scheduled_at"],
    ):
        name = it.get("asset_name") or it.get("mp4_name") or ""
        ref = by_name.get(name, {})
        secs = seconds_until(it.get("scheduled_at"), now)
        q_status = it.get("status")
        ui_status = {
            "pending": "scheduled", "ready": "approved",
            "uploading": "publishing", "failed": "failed",
        }.get(q_status, "queued")
        upcoming.append({
            "entry_id": it.get("id"),
            "name": name,
            "title": ref.get("title") or _derive_title(name, {}),
            "type": ref.get("type") or ("gorsel" if name.lower().endswith((".jpg", ".jpeg", ".png")) else "haber"),
            "url": ref.get("url"),
            "scheduled_at": it.get("scheduled_at"),
            "seconds_until": secs,
            "countdown": humanize_delta(secs),
            "status": ui_status,
            "status_tr": STATUS_TR.get(ui_status, ui_status),
            "error": it.get("result") if q_status == "failed" else None,
        })

    # Yayınlananlar — uploads_log
    uploads = _uploads_log(cfg)
    published = []
    for stem, rec in uploads.items():
        ref = next((c for c in content if c["stem"] == stem), {})
        published.append({
            "stem": stem,
            "title": ref.get("title") or _derive_title(stem, {}),
            "type": ref.get("type") or "gorsel",
            "url": ref.get("url"),
            "media_id": rec.get("media_id"),
            "uploaded_at": rec.get("uploaded_at"),
            "permalink": rec.get("permalink"),
            "method": rec.get("method"),
            # Performans verisi backend'de yoksa None — UI 'veri yok' gösterir
            "metrics": rec.get("metrics"),
        })
    published.sort(key=lambda x: x.get("uploaded_at") or "", reverse=True)

    return {
        "now": _fmt_dt(now),
        "timezone": "Europe/Istanbul",
        "timeline": weekly_timeline(cfg, content),
        "upcoming": upcoming,
        "published": published,
        "metrics_available": any(p.get("metrics") for p in published),
    }
