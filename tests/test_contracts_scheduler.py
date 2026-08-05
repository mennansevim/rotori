"""Contract testleri — /api/scheduler/queue.

Şu oturumda enrichment yapıldı (config_enabled, auto_upload, daily_limit,
default_times alanları eklendi). UI bu alanları scheduler kapalıyken
kullanıcıya YAML örneği göstermek için okuyor — sözleşme kilitlenir.
"""
from __future__ import annotations

import json
from datetime import datetime
from unittest.mock import patch

from src import scheduler


def test_scheduler_queue_shape(client):
    r = client.get("/api/scheduler/queue")
    assert r.status_code == 200
    data = r.json()

    # Ana istatistik alanları (queue_summary)
    for k in ("total", "pending", "ready", "failed", "done", "items"):
        assert k in data, f"{k} eksik"
    assert isinstance(data["items"], list)

    # Enrichment alanları (Karar 3 — 2026-07-30)
    for k in ("config_enabled", "auto_upload", "daily_limit", "default_times"):
        assert k in data, f"enrichment field '{k}' eksik — sözleşme bozuldu"

    # Enabled bool olmalı
    assert isinstance(data["config_enabled"], bool)
    assert isinstance(data["auto_upload"], bool)

    # daily_limit: int veya None (scheduler kapalıysa None)
    assert data["daily_limit"] is None or isinstance(data["daily_limit"], int)

    # default_times: list[str] veya None
    if data["default_times"] is not None:
        assert isinstance(data["default_times"], list)
        assert all(isinstance(t, str) for t in data["default_times"])


def test_scheduler_run_endpoint_reachable(client):
    """POST /api/scheduler/run — kuyruk boşken bile 200 dönmeli."""
    r = client.post("/api/scheduler/run")
    assert r.status_code == 200
    data = r.json()
    assert "ok" in data
    assert "processed" in data
    assert isinstance(data["processed"], int)


def test_automation_slot_uses_selected_weekdays_in_order():
    queue = [{"scheduled_at": "2026-08-05T17:05:00", "status": "pending"}]
    slot = scheduler.next_automation_slot(
        queue, [2, 3], 17, 5, from_dt=datetime(2026, 8, 4, 18, 0, 0)
    )
    assert slot == "2026-08-11T17:05:00"


def test_failed_item_does_not_block_automation_slot():
    queue = [{"scheduled_at": "2026-08-05T17:05:00", "status": "failed"}]
    slot = scheduler.next_automation_slot(
        queue, [3], 17, 5, from_dt=datetime(2026, 8, 4, 12, 0, 0)
    )
    assert slot == "2026-08-05T17:05:00"


def test_sync_automation_slots_replans_existing_items(tmp_path):
    queue_file = "queue.json"
    queue = [
        {"id": "news-1", "asset_name": "one.jpg", "status": "pending",
         "scheduled_at": "2026-08-04T17:05:00", "added_at": "2026-08-04T09:00:00",
         "automation_kind": "news"},
        {"id": "manual-1", "asset_name": "manual.jpg", "status": "pending",
         "scheduled_at": "2026-08-05T12:00:00", "added_at": "2026-08-04T09:00:00"},
    ]
    (tmp_path / queue_file).write_text(json.dumps(queue), encoding="utf-8")
    config = {
        "news": {"enabled": True, "days": [4], "hour": 18, "minute": 30,
                 "auto_publish": True},
        "topic": {"enabled": False, "days": [], "hour": 20, "minute": 0},
    }
    with patch("src.scheduler._now", return_value=datetime(2026, 8, 4, 10, 0, 0)):
        result = scheduler.sync_automation_slots(tmp_path, config, queue_file)
    saved = {item["id"]: item for item in scheduler.load_queue(tmp_path, queue_file)}
    assert result == {"rescheduled": 1, "unscheduled": 0}
    assert saved["news-1"]["scheduled_at"] == "2026-08-06T18:30:00"
    assert saved["manual-1"]["scheduled_at"] == "2026-08-05T12:00:00"
