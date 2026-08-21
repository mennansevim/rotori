"""Manuel içerik kategorisi sözleşmesi ve üretim yönlendirmesi."""
from __future__ import annotations

from pathlib import Path

from src import content_categories as cc


def test_category_order_and_labels_are_stable():
    categories = cc.category_list()

    assert [item["slug"] for item in categories] == [
        "guncel_haberler",
        "seyahat_hazirligi",
        "animeler",
        "teknoloji",
    ]
    assert categories[0]["mode"] == "rss"
    assert all(item["label"] and item["description"] for item in categories)


def test_category_aliases_normalize_to_public_slugs():
    assert cc.normalize_category("güncel-haberler") == "guncel_haberler"
    assert cc.normalize_category("travel") == "seyahat_hazirligi"
    assert cc.normalize_category("anime") == "animeler"
    assert cc.normalize_category("tech") == "teknoloji"


def test_category_topic_pools_include_existing_and_new_topics(project_root: Path):
    import json

    base_pool = json.loads(
        (project_root / "assets" / "topic_pool.json").read_text(encoding="utf-8")
    )["topics"]

    travel = cc.topics_for_category("seyahat_hazirligi", base_pool)
    anime = cc.topics_for_category("animeler", base_pool)
    technology = cc.topics_for_category("teknoloji", base_pool)

    assert any("Suica" in item["title"] for item in travel)
    assert any("İlk Kez Giderken" in item["title"] for item in travel)
    assert any("Akihabara" in item["title"] for item in anime)
    assert any("Kamera ve Lens" in item["title"] for item in technology)
    assert all(item.get("query") for item in travel + anime + technology)


def test_category_prompt_keeps_selected_category_visible():
    from src.editorial import build_topic_prompt

    prompt = build_topic_prompt("Japonya Uçuşunda Kabin Bagajı Düzeni", "Japonya Yolculuğu")

    assert "ÜST KATEGORİ: Japonya Yolculuğu" in prompt
    assert "başka bir kategoriye kaydırma" in prompt


def test_manual_non_news_category_uses_topic_pipeline(monkeypatch):
    from src.web import app as web_app

    calls = {}

    def fake_topic_run(cfg, auto_publish=False, category=None, **kwargs):
        calls["category"] = category
        return {"ok": True, "file": "anime.jpg"}

    import src.topic_automation as topic_module

    monkeypatch.setattr(topic_module, "run_once", fake_topic_run)
    web_app._run_now_bulk(
        kind="news",
        count=1,
        forced_auto_publish=False,
        topic="",
        query="",
        emit=lambda *args, **kwargs: None,
        cancel_ev=type("Cancel", (), {"is_set": lambda self: False})(),
        category="animeler",
    )

    assert calls == {"category": "animeler"}
