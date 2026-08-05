from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

from src import scheduler


def test_process_due_story_moves_to_ready_and_uses_ready_url(tmp_path, monkeypatch):
    project_root = tmp_path
    stories_root = project_root / "output" / "stories"
    stories_root.mkdir(parents=True, exist_ok=True)

    story = stories_root / "demo_story.jpg"
    story.write_bytes(b"fake-jpg-bytes")
    story.with_suffix(".txt").write_text("Demo caption", encoding="utf-8")

    queue_file = "queue.json"
    scheduler.enqueue(
        project_root=project_root,
        mp4_path=story,
        caption="",
        scheduled_at="2000-01-01T00:00:00",
        queue_file=queue_file,
        kind="story",
        auto_publish=True,
    )

    captured: dict[str, str] = {}

    def _fake_publish_image(cfg_any, image_url: str, caption: str):
        captured["url"] = image_url
        captured["caption"] = caption
        return {"id": "mock_media_1", "container_id": "mock_container_1"}

    import src.instagram_graph as igraph

    monkeypatch.setattr(igraph, "publish_image", _fake_publish_image)
    monkeypatch.setattr(
        scheduler,
        "_pick_story_public_url",
        lambda cfg_any, asset, emit=None: "https://api.rotori.app/media/stories/ready/demo_story.jpg",
    )

    cfg_any = SimpleNamespace(
        instagram=SimpleNamespace(public_base_url="https://api.rotori.app"),
        stories=SimpleNamespace(output_dir=stories_root),
    )

    processed = scheduler.process_due(
        project_root=project_root,
        output_dir=project_root / "output" / "reels",
        cfg_any=cfg_any,
        queue_file=queue_file,
        auto_upload=True,
    )

    assert len(processed) == 1
    assert processed[0]["status"] == "done"

    ready_story = stories_root / "ready" / "demo_story.jpg"
    assert ready_story.exists()
    assert not story.exists()

    assert (
        captured["url"]
        == "https://api.rotori.app/media/stories/ready/demo_story.jpg"
    )
    assert captured["caption"] == "Demo caption"

    saved = scheduler.load_queue(project_root, queue_file=queue_file)
    assert saved[0]["asset_path"].endswith("/output/stories/ready/demo_story.jpg")
    assert saved[0]["public_url"] == "https://api.rotori.app/media/stories/ready/demo_story.jpg"


def test_pick_story_public_url_falls_back_to_ngrok_when_config_base_unreachable(tmp_path, monkeypatch):
    stories_root = tmp_path / "output" / "stories"
    ready_root = stories_root / "ready"
    ready_root.mkdir(parents=True, exist_ok=True)
    asset = ready_root / "demo_story.jpg"
    asset.write_bytes(b"fake-jpg")

    cfg_any = SimpleNamespace(
        instagram=SimpleNamespace(public_base_url="https://api.rotori.app"),
        stories=SimpleNamespace(output_dir=stories_root),
    )

    monkeypatch.setattr(
        scheduler,
        "_detect_ngrok_public_base_url",
        lambda timeout_sn=1.2: "https://demo.ngrok-free.dev",
    )
    monkeypatch.setattr(
        scheduler,
        "_detect_trycloudflare_public_base_url",
        lambda timeout_sn=1.0: None,
    )

    class _Resp:
        def __init__(self, status_code: int, content_type: str):
            self.status_code = status_code
            self.headers = {"content-type": content_type}

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

    def _fake_get(url: str, **kwargs):
        if url.startswith("https://api.rotori.app/"):
            return _Resp(404, "text/html")
        if url.startswith("https://demo.ngrok-free.dev/"):
            return _Resp(200, "image/jpeg")
        raise AssertionError(f"Unexpected URL: {url}")

    monkeypatch.setattr(scheduler.requests, "get", _fake_get)

    picked = scheduler._pick_story_public_url(cfg_any, asset)
    assert picked == "https://demo.ngrok-free.dev/media/stories/ready/demo_story.jpg"
