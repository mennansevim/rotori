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


def test_news_automation_rejects_more_than_one_weekly_day(client, monkeypatch):
    """Mavi haber akışı çoklu günle yeniden iki-üç günlük sıraya dönmemeli."""
    import src.web.app as appmod

    monkeypatch.setattr(
        appmod,
        "_load_auto_cfg",
        lambda: {
            "news": {"enabled": True, "days": [3], "hour": 23, "minute": 21,
                     "auto_publish": True},
            "topic": {"enabled": True, "days": [3, 5], "hour": 22, "minute": 22,
                      "auto_publish": True},
        },
    )
    r = client.post("/api/automation/config", json={
        "news": {"enabled": True, "days": [3, 6], "hour": 23, "minute": 21},
        "topic": {},
    })
    assert r.status_code == 422
    assert "haftada tam bir yayın günü" in r.json()["detail"]


def test_scheduler_queue_shape(client):
    """Komuta/Özet ekranları bu alanları okuyor."""
    r = client.get("/api/scheduler/queue")
    assert r.status_code == 200
    data = r.json()
    for k in ("pending", "ready", "done", "items"):
        assert k in data, f"scheduler queue '{k}' alanı eksik"
    assert isinstance(data["items"], list)


def test_single_approved_item_can_be_added_to_automation(client, monkeypatch):
    """Kart aksiyonu yalnız seçilen içeriği planlamalı, tüm havuzu değil."""
    import src.web.app as appmod

    called = {}

    def fake_auto_fill(only_name=None):
        called["only_name"] = only_name
        return {"ok": True, "scheduled": 1, "entries": [{"asset_name": only_name}]}

    monkeypatch.setattr(appmod, "_auto_fill_ready_impl", fake_auto_fill)
    response = client.post("/api/scheduler/auto_fill_ready/ornek-haber.jpg")

    assert response.status_code == 200
    assert response.json()["scheduled"] == 1
    assert called["only_name"] == "ornek-haber.jpg"


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


def test_news_run_now_accepts_count(client, monkeypatch):
    """Legacy endpoint body kabul etmeli: {count: N} ile bulk tetiklenebilir."""
    import src.web.app as appmod

    monkeypatch.setattr(appmod.manager, "start_callable",
                        lambda *a, **k: None, raising=False)
    r = client.post("/api/news/run_now", json={"count": 5})
    assert r.status_code == 200
    assert r.json().get("count") == 5


def test_automation_run_now_default_kind(client, monkeypatch):
    """Body'siz POST → default kind=news (RunNowRequest default'ları)."""
    import src.web.app as appmod

    monkeypatch.setattr(appmod.manager, "start_callable",
                        lambda *a, **k: None, raising=False)
    r = client.post("/api/automation/run_now", json={})
    assert r.status_code == 200
    assert r.json().get("kind") == "news"


def test_automation_run_now_accepts_count(client, monkeypatch):
    """Dashboard 'Haber Üret' bulk çağrısı count alanını endpoint'e gönderebilir."""
    import src.web.app as appmod

    monkeypatch.setattr(appmod.manager, "start_callable",
                        lambda *a, **k: None, raising=False)
    r = client.post("/api/automation/run_now", json={"kind": "news", "count": 2})
    assert r.status_code == 200
    body = r.json()
    assert body.get("kind") == "news"
    assert body.get("count") == 2
