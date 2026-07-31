"""Contract testleri — /api/scheduler/queue.

Şu oturumda enrichment yapıldı (config_enabled, auto_upload, daily_limit,
default_times alanları eklendi). UI bu alanları scheduler kapalıyken
kullanıcıya YAML örneği göstermek için okuyor — sözleşme kilitlenir.
"""
from __future__ import annotations


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
