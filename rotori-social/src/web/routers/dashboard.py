"""Dashboard router — yeni tasarım UI'ının okuduğu toplu (aggregate) durum.

Route'lar (hepsi GET, salt-okunur; yazma işlemleri mevcut /api/approval,
/api/scheduler, /api/automation endpoint'leri üzerinden yürür):

    GET /api/dashboard/overview    — Genel Bakış: sayaçlar + timeline + kuyruk
    GET /api/dashboard/library     — Kütüphane: tüm içerik + normalize durum
    GET /api/dashboard/publishes   — Yayınlar: yaklaşan + yayınlanan
    GET /api/dashboard/automation  — Otomasyon: slot config + bu hafta akışı

Veri kaynağı gerçek dosya sistemi + scheduler kuyruğu + automation config'tir
(src.web.dashboard_state). Mock yoktur.
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter

from src.web import dashboard_state as ds
from src.web.dependencies import get_cfg

router = APIRouter(prefix="/api/dashboard", tags=["dashboard"])


@router.get("/overview")
def dashboard_overview() -> dict[str, Any]:
    return ds.overview(get_cfg())


@router.get("/library")
def dashboard_library() -> dict[str, Any]:
    cfg = get_cfg()
    items = ds.scan_content(cfg)
    now = ds._now(cfg)  # noqa: SLF001
    # kalan süre metnini ekle
    for it in items:
        secs = ds.seconds_until(it.get("scheduled_at"), now)
        it["seconds_until"] = secs
        it["countdown"] = ds.humanize_delta(secs) if secs is not None else None
    counts = {
        "all": len(items),
        "draft": sum(1 for i in items if i["status"] == "draft"),
        "pending_approval": sum(1 for i in items if i["status"] == "pending_approval"),
        "ready": sum(1 for i in items if i["status"] in ("approved", "queued", "scheduled")),
        "published": sum(1 for i in items if i["status"] == "published"),
    }
    return {
        "now": ds._fmt_dt(now),  # noqa: SLF001
        "timezone": "Europe/Istanbul",
        "items": items,
        "counts": counts,
        "status_tr": ds.STATUS_TR,
    }


@router.get("/publishes")
def dashboard_publishes() -> dict[str, Any]:
    from pathlib import Path
    import json

    cfg = get_cfg()
    result = ds.publishes(cfg)

    # Devre dışı otomasyon lane'lerindeki upcoming öğeleri filtrele
    auto_conf_path = Path(cfg.project_root) / "data" / "automation_config.json"
    if auto_conf_path.exists():
        try:
            auto_cfg = json.loads(auto_conf_path.read_text(encoding="utf-8"))
            disabled_kinds = []
            if not auto_cfg.get("news", {}).get("enabled"):
                disabled_kinds.append("haber")
            if not auto_cfg.get("topic", {}).get("enabled"):
                disabled_kinds.append("gorsel")
            if disabled_kinds:
                result["upcoming"] = [
                    it for it in result.get("upcoming", [])
                    if it.get("type") not in disabled_kinds
                ]
        except (OSError, ValueError):
            pass

    return result


@router.get("/automation")
def dashboard_automation() -> dict[str, Any]:
    cfg = get_cfg()
    # Automation config'i app.py yerine burada minimal oku (tek gerçek dosya)
    import json
    from pathlib import Path

    default = {
        "news":  {"enabled": False, "days": [1, 4], "hour": 9,  "minute": 0, "auto_publish": False},
        "topic": {"enabled": False, "days": [2, 5], "hour": 12, "minute": 0, "auto_publish": False},
    }
    p = Path(cfg.project_root) / "data" / "automation_config.json"
    conf = {k: v.copy() for k, v in default.items()}
    if p.exists():
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
            for k in ("news", "topic"):
                item = data.get(k) or {}
                for key in ("enabled", "days", "hour", "minute", "auto_publish"):
                    if key in item:
                        conf[k][key] = item[key]
        except (OSError, ValueError):
            pass

    return {
        "config": conf,
        "timeline": ds.weekly_timeline(cfg),
        "next_publish": ds.overview(cfg)["next_publish"],
        "timezone": "Europe/Istanbul",
    }
