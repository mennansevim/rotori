from __future__ import annotations

from types import SimpleNamespace

import pytest

from src import instagram_graph as igraph


class _Resp:
    def __init__(self, status_code: int, content_type: str):
        self.status_code = status_code
        self.headers = {"content-type": content_type}

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False


def _cfg() -> SimpleNamespace:
    return SimpleNamespace(
        instagram=SimpleNamespace(
            graph_token="token",
            ig_user_id="123",
        )
    )


def test_publish_image_fails_fast_when_public_url_not_200(monkeypatch):
    monkeypatch.setattr(igraph.requests, "get", lambda *a, **k: _Resp(404, "image/jpeg"))

    def _never_called(*args, **kwargs):
        raise AssertionError("_req should not be called when preflight fails")

    monkeypatch.setattr(igraph, "_req", _never_called)

    with pytest.raises(igraph.GraphError, match="preflight başarısız"):
        igraph.publish_image(_cfg(), "https://api.rotori.app/media/stories/ready/a.jpg", "cap")


def test_publish_image_fails_fast_when_public_url_not_image(monkeypatch):
    monkeypatch.setattr(igraph.requests, "get", lambda *a, **k: _Resp(200, "application/json"))

    with pytest.raises(igraph.GraphError, match=r"content-type image/\* değil"):
        igraph.publish_image(_cfg(), "https://api.rotori.app/media/stories/ready/a.jpg", "cap")


def test_publish_image_continues_when_preflight_ok(monkeypatch):
    monkeypatch.setattr(igraph.requests, "get", lambda *a, **k: _Resp(200, "image/jpeg"))
    monkeypatch.setattr(igraph, "_wait_container_ready", lambda *a, **k: None)

    calls = []

    def _fake_req(method: str, path: str, params=None, timeout=30):
        calls.append((method, path, params))
        if path.endswith("/media"):
            return {"id": "container_1"}
        if path.endswith("/media_publish"):
            return {"id": "media_1"}
        return {}

    monkeypatch.setattr(igraph, "_req", _fake_req)

    out = igraph.publish_image(_cfg(), "https://api.rotori.app/media/stories/ready/a.jpg", "cap")
    assert out == {"id": "media_1", "container_id": "container_1"}
    assert len(calls) == 2
