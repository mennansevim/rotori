"""API smoke testleri — tüm GET endpoint'leri 5xx vermemeli + kritik
POST akışları (otomasyon tetik, scheduler) doğru sözleşmeyle cevap vermeli.

Amaç: "bu buton çalışmıyor" hatalarını (yanlış method/param, 422, 500) UI
yerine burada yakalamak. Dış servisler (Ollama/OpenAI/IG) conftest'te stub'lı;
otomasyon işleri arka planda kuyruklanır — burada yalnızca endpoint sözleşmesi
denetlenir, gerçek üretim yapılmaz.
"""
from __future__ import annotations

import pytest

# UI + widget tarafından tüketilen, parametresiz GET endpoint'ler.
GET_ENDPOINTS = [
    "/",
    "/api/version",
    "/api/status",
    "/api/logs",
    "/api/suggestions",
    "/api/backgrounds/status",
    "/api/story/list",
    "/api/reels/sources",
    "/api/reels/generated",
    "/api/instagram/graph_status",
    "/api/approval/list",
    "/api/automation/config",
    "/api/reels",
    "/api/instagram/status",
    "/api/scheduler/queue",
    "/api/tiktok/status",
    "/api/analytics/overview",
    "/api/analytics/hooks",
    "/api/analytics/platforms",
    "/api/dashboard/overview",
    "/api/dashboard/library",
    "/api/dashboard/publishes",
    "/api/dashboard/automation",
]


@pytest.mark.parametrize("path", GET_ENDPOINTS)
def test_get_endpoint_not_5xx(client, path):
    """Hiçbir GET endpoint 5xx dönmemeli (200/3xx/4xx kabul; 5xx = kırık)."""
    r = client.get(path)
    assert r.status_code < 500, f"{path} → {r.status_code} (sunucu hatası)"


def test_automation_config_shape(client):
    """UI Ayarlar ekranı bu şemayı okuyor: news/topic → days/hour/minute."""
    r = client.get("/api/automation/config")
    assert r.status_code == 200
    data = r.json()
    for kind in ("news", "topic"):
        assert kind in data, f"automation config '{kind}' eksik"
        conf = data[kind]
        assert "days" in conf and isinstance(conf["days"], list)
        assert "hour" in conf and isinstance(conf["hour"], int)
        assert "minute" in conf and isinstance(conf["minute"], int)


def test_scheduler_queue_shape(client):
    """Komuta/Özet ekranları bu alanları okuyor."""
    r = client.get("/api/scheduler/queue")
    assert r.status_code == 200
    data = r.json()
    for k in ("pending", "ready", "done", "items"):
        assert k in data, f"scheduler queue '{k}' alanı eksik"
    assert isinstance(data["items"], list)


def test_story_list_shape(client):
    """Kütüphane ekranı cards[] okuyor."""
    r = client.get("/api/story/list")
    assert r.status_code == 200
    data = r.json()
    assert "cards" in data and isinstance(data["cards"], list)


# --- Otomasyon tetikleyicileri: doğru method + body sözleşmesi ---------------
def test_topic_run_now_accepts_json_body(client, monkeypatch):
    """runTopicBtn `{kind:'topic'}` JSON body gönderir → 200 (422 OLMAMALI).

    Gerçek üretim yapılmasın diye job manager stub'lanır.
    """
    import src.web.app as appmod

    monkeypatch.setattr(appmod.manager, "start_callable",
                        lambda *a, **k: None, raising=False)
    r = client.post("/api/automation/run_now", json={"kind": "topic"})
    assert r.status_code == 200, f"topic run_now → {r.status_code} (body: {r.text})"
    assert r.json().get("kind") == "topic"


def test_news_run_now_legacy_ok(client, monkeypatch):
    """runNewsBtn `/api/news/run_now` (body'siz POST) → 200."""
    import src.web.app as appmod

    monkeypatch.setattr(appmod.manager, "start_callable",
                        lambda *a, **k: None, raising=False)
    r = client.post("/api/news/run_now")
    assert r.status_code == 200, f"news run_now → {r.status_code}"


def test_automation_run_now_default_kind(client, monkeypatch):
    """Body'siz POST → default kind=news (RunNowRequest default'ları)."""
    import src.web.app as appmod

    monkeypatch.setattr(appmod.manager, "start_callable",
                        lambda *a, **k: None, raising=False)
    r = client.post("/api/automation/run_now", json={})
    assert r.status_code == 200
    assert r.json().get("kind") == "news"
