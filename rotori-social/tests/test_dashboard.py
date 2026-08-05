"""Dashboard aggregation router testleri.

Yeni tasarım UI'ının okuduğu /api/dashboard/* endpoint'lerinin sözleşmesini
ve dashboard_state saf fonksiyonlarını doğrular. Dış servis çağrısı yok —
mevcut gerçek config + dosya sistemi okunur (conftest client fixture).
"""
from __future__ import annotations

from datetime import datetime, timedelta
from pathlib import Path

import pytest

from src.web import dashboard_state as ds


DASHBOARD_STATIC = Path(__file__).resolve().parent.parent / "src" / "web" / "static" / "dashboard"


# --------------------------------------------------------------- Endpoint sözleşmesi
DASHBOARD_GETS = [
    "/api/dashboard/overview",
    "/api/dashboard/library",
    "/api/dashboard/publishes",
    "/api/dashboard/automation",
]


@pytest.mark.parametrize("path", DASHBOARD_GETS)
def test_dashboard_get_not_5xx(client, path):
    r = client.get(path)
    assert r.status_code < 500, f"{path} → {r.status_code}"
    assert r.headers["content-type"].startswith("application/json")


def test_overview_shape(client):
    data = client.get("/api/dashboard/overview").json()
    for key in ("counts", "timeline", "pending_approval", "ready_queue", "now", "timezone"):
        assert key in data, f"overview '{key}' eksik"
    for c in ("drafts", "pending_approval", "ready", "week_publishes"):
        assert c in data["counts"]
        assert isinstance(data["counts"][c], int)
    assert data["timezone"] == "Europe/Istanbul"
    assert len(data["timeline"]["days"]) == 7


def test_library_shape(client):
    data = client.get("/api/dashboard/library").json()
    assert "items" in data and isinstance(data["items"], list)
    assert "counts" in data
    for c in ("all", "draft", "pending_approval", "ready", "published"):
        assert c in data["counts"]
    # her item normalize durum modeline uymalı
    valid = set(ds.STATUS_TR.keys())
    for it in data["items"][:20]:
        assert it["status"] in valid, f"geçersiz durum: {it['status']}"
        assert it["type"] in ("gorsel", "haber")
        assert it["url"].startswith("/media/stories/")


def test_publishes_shape(client):
    data = client.get("/api/dashboard/publishes").json()
    for key in ("upcoming", "published", "timeline", "metrics_available"):
        assert key in data


def test_automation_shape(client):
    data = client.get("/api/dashboard/automation").json()
    assert "config" in data
    for kind in ("news", "topic"):
        assert kind in data["config"]
        for f in ("enabled", "days", "hour", "minute"):
            assert f in data["config"][kind]
    timeline_items = [item for day in data["timeline"]["days"] for item in day["items"]]
    assert all("url" in item for item in timeline_items)


# --------------------------------------------------------------- Saf fonksiyonlar
def test_humanize_delta_days():
    assert ds.humanize_delta(4 * 86400 + 12 * 3600) == "4 gün 12 saat kaldı"


def test_humanize_delta_minutes():
    assert ds.humanize_delta(42 * 60) == "42 dakika kaldı"


def test_humanize_delta_past_no_negative():
    """Geçmiş tarih negatif süre göstermemeli."""
    txt = ds.humanize_delta(-500)
    assert "-" not in txt
    assert txt == "Yayın zamanı geçti"


def test_humanize_delta_none():
    assert ds.humanize_delta(None) == "—"


def test_seconds_until_future():
    now = datetime(2026, 8, 3, 12, 0, 0)
    future = (now + timedelta(days=1)).strftime("%Y-%m-%dT%H:%M:%S")
    assert ds.seconds_until(future, now) == 86400


def test_seconds_until_invalid():
    assert ds.seconds_until(None, datetime.now()) is None
    assert ds.seconds_until("bozuk-tarih", datetime.now()) is None


def test_derive_type_news():
    assert ds._derive_type("news_tokyo_123.jpg", {"source": "news"}) == "haber"
    assert ds._derive_type("kyoto_00.jpg", {"source": "manuel"}) == "gorsel"


def test_status_tr_covers_model():
    """Durum modeli TR karşılıkları tam olmalı."""
    for s in ("draft", "pending_approval", "approved", "queued", "scheduled",
              "publishing", "published", "rejected", "failed"):
        assert s in ds.STATUS_TR


def test_recovered_dark_board_and_timeline_contracts():
    overview_js = (DASHBOARD_STATIC / "pages" / "overview.js").read_text(encoding="utf-8")
    automation_js = (DASHBOARD_STATIC / "pages" / "automation.js").read_text(encoding="utf-8")
    styles = (DASHBOARD_STATIC / "styles.css").read_text(encoding="utf-8")
    lib_js = (DASHBOARD_STATIC / "lib.js").read_text(encoding="utf-8")
    assert "kanban-card--" in overview_js
    assert "timelineItem(it)" in automation_js
    assert "await renderAutomation(root, ctx)" in automation_js
    assert ".tl-item__thumb" in styles
    assert "--bg-app: #0f172a" in styles
    assert "settled = true" in lib_js
