"""pytest fixture'ları — FastAPI TestClient + dış servislerin stub'ı.

Kurulum:
    pip install -r requirements-dev.txt

Çalıştırma:
    pytest -q                       # tümü
    pytest tests/test_contracts_*   # sadece contract testler

Kural: hiçbir test gerçek Ollama/OpenAI/Instagram/TikTok/Unsplash çağırmaz;
gerekiyorsa monkeypatch ile stub verilir.
"""
from __future__ import annotations

import os
from pathlib import Path

import pytest

os.environ.setdefault("PYTHONDONTWRITEBYTECODE", "1")


@pytest.fixture(scope="session")
def project_root() -> Path:
    return Path(__file__).resolve().parent.parent


@pytest.fixture()
def client(monkeypatch, project_root):
    """FastAPI TestClient — app import edilmeden önce Ollama sağlığı
    stub'lanır (gerçek localhost:11434'e çıkmasın).

    Kullanıcının gerçek `config.yaml`'ı okunur (secret'lar test edilmez;
    yalnızca kurulumun düzgün load olduğu doğrulanır). Config yoksa
    test'ler skip edilir.
    """
    cfg_path = project_root / "config.yaml"
    if not cfg_path.exists():
        pytest.skip("config.yaml yok — kontrat testleri gerçek config gerektirir")

    # Ollama /api/tags — test sırasında localhost çağrılmasın diye stub.
    import requests

    class _StubResp:
        status_code = 200

        def json(self):
            return {"models": []}

    def _fake_get(url, **kw):
        return _StubResp()

    monkeypatch.setattr(requests, "get", _fake_get)

    # app import — cfg + manager singleton kurulumu tetiklenir.
    from fastapi.testclient import TestClient

    from src.web.app import app

    with TestClient(app) as c:
        yield c
