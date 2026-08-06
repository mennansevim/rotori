"""news_automation CLI kontratı.

launchd job'u auto_publish açıkken `python -m src.news_automation --publish`
çağırır. CLI bu parametreyi kabul edip run_once_with_publish'e aktarmalı.
"""
from __future__ import annotations

from src import news_automation


def test_news_cli_publish_flag_passed_to_wrapper(monkeypatch):
    fake_cfg = object()
    captured: dict[str, object] = {}

    monkeypatch.setattr(news_automation, "load_config", lambda _path=None: fake_cfg)

    def _fake_run_once_with_publish(cfg, auto_publish=False, dry_run=False):
        captured["cfg"] = cfg
        captured["auto_publish"] = auto_publish
        captured["dry_run"] = dry_run
        return {"ok": True}

    monkeypatch.setattr(news_automation, "run_once_with_publish", _fake_run_once_with_publish)

    exit_code = news_automation.main(["--publish"])

    assert exit_code == 0
    assert captured == {
        "cfg": fake_cfg,
        "auto_publish": True,
        "dry_run": False,
    }
