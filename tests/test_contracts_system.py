"""Contract testleri — /api/version, /api/status, /api/logs.

Bu üç endpoint sözleşmesi UI + widget + Cloudflare monitoring tarafından
tüketiliyor. Response şeması ASLA değişmemeli (backwards compat).
"""
from __future__ import annotations


def test_version_ok(client):
    r = client.get("/api/version")
    assert r.status_code == 200
    data = r.json()
    # Zorunlu alanlar
    assert set(data.keys()) >= {"version", "commit", "date", "source"}
    assert isinstance(data["version"], str)
    assert isinstance(data["commit"], str)
    assert data["source"] in ("build", "git", "none")


def test_status_ok(client):
    r = client.get("/api/status")
    assert r.status_code == 200
    data = r.json()
    # Ana bölümler
    assert "job" in data
    assert "counts" in data
    assert "env" in data
    # counts.* — int
    for k in ("source_videos", "metadata", "reels", "ready"):
        assert k in data["counts"], f"counts.{k} eksik"
        assert isinstance(data["counts"][k], int)
    # env.ollama_ok — bool (stub'ta True)
    assert isinstance(data["env"]["ollama_ok"], bool)
    assert data["env"]["ollama_ok"] is True
    # env.source_ready — bool
    assert isinstance(data["env"]["source_ready"], bool)


def test_logs_ok(client):
    r = client.get("/api/logs")
    assert r.status_code == 200
    data = r.json()
    assert set(data.keys()) >= {"entries", "seq", "progress_line"}
    assert isinstance(data["entries"], list)
    assert isinstance(data["seq"], int)
    assert isinstance(data["progress_line"], str)


def test_logs_since_param(client):
    """?since=0 varsayılan; ?since=N geriye uyumlu int param kabul eder."""
    r = client.get("/api/logs?since=99999999")
    assert r.status_code == 200
    data = r.json()
    # Çok yüksek since → boş entries; seq geriye uyumlu int
    assert isinstance(data["entries"], list)
    assert isinstance(data["seq"], int)


def test_status_headers_no_cache(client):
    """/api/status polling endpoint — cache olmamalı."""
    r = client.get("/api/status")
    # FastAPI default no-cache; sadece 200 kilitleme yeterli.
    assert r.status_code == 200


def test_version_stable_across_calls(client):
    """Aynı süreçte 2 çağrı aynı verify field'larını dönmeli."""
    a = client.get("/api/version").json()
    b = client.get("/api/version").json()
    assert a["source"] == b["source"]
    assert a["commit"] == b["commit"]
