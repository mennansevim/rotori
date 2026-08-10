"""Otomasyon dedup + toplu üretim dayanıklılığı.

Bu testler üç somut regresyonu kilitler:

1. **Konu tekrarı** — havuz tükendiğinde eskiden `fresh_topics = list(pool)` ile
   TÜM havuz sessizce yeniden açılıyordu; aynı konu üst üste üretiliyordu
   (canlı state'te Konbini 3x, Onsen 2x, Ramen 2x). Artık cooldown dolmadan
   hiçbir konu geri gelmez.
2. **Aynı konu farklı kaynaktan** — dedup yalnız link'e bakıyordu; aynı başlık
   başka bir feed'den (ya da evergreen olarak) gelince tekrar üretilebiliyordu.
3. **Toplu üretimde kısmi hata** — bir turdaki exception tüm bulk'u çökertiyor,
   iş "hata" olarak bitiyor ama o ana kadar üretilmiş kartlar sessiz kalıyordu.
"""
from __future__ import annotations

import time

import pytest

from src import news_automation as na


POOL = [
    {"title": "Konbini Kültürü", "query": "japan konbini"},
    {"title": "Onsen Deneyimi", "query": "japan onsen"},
    {"title": "JR Pass Ne Zaman Kâr Ettirir", "query": "shinkansen platform"},
]


def _iso(ts: float) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(ts))


# ---------------------------------------------------------------------------
# 1) Cooldown — havuz tükendiğinde sessiz reset YOK
# ---------------------------------------------------------------------------
def test_fresh_topics_returned_when_pool_not_exhausted():
    ordered, note = na.eligible_topics(POOL, used=set(), state={}, cooldown_days=45)
    assert len(ordered) == 3
    assert "taze" in note


def test_exhausted_pool_is_not_silently_recycled():
    """Kök neden testi: tüm konular kullanıldıysa ve cooldown dolmadıysa BOŞ döner."""
    now = time.time()
    used: set[str] = set()
    for topic in POOL:
        na._remember(used, {"title": topic["title"]})
    state = {"history": [{"at": _iso(now - 2 * 86400), "title": t["title"]} for t in POOL]}

    ordered, note = na.eligible_topics(POOL, used, state, cooldown_days=45, now=now)

    assert ordered == [], "havuz tükendiğinde konular sessizce yeniden açılmamalı"
    assert "bekleme" in note


def test_cooldown_elapsed_returns_oldest_used_first():
    now = time.time()
    used: set[str] = set()
    for topic in POOL:
        na._remember(used, {"title": topic["title"]})
    state = {"history": [
        {"at": _iso(now - 100 * 86400), "title": "Onsen Deneyimi"},      # en eski
        {"at": _iso(now - 90 * 86400), "title": "Konbini Kültürü"},
        {"at": _iso(now - 80 * 86400), "title": "JR Pass Ne Zaman Kâr Ettirir"},
    ]}

    ordered, note = na.eligible_topics(POOL, used, state, cooldown_days=45, now=now)

    assert [t["title"] for t in ordered] == [
        "Onsen Deneyimi", "Konbini Kültürü", "JR Pass Ne Zaman Kâr Ettirir",
    ]
    assert "yeniden uygun" in note


def test_cooldown_zero_keeps_legacy_recycle_behaviour():
    """cooldown_days=0 açıkça 'beklemesiz' demektir — eski davranış korunur."""
    used: set[str] = set()
    for topic in POOL:
        na._remember(used, {"title": topic["title"]})
    ordered, note = na.eligible_topics(POOL, used, {"history": []}, cooldown_days=0)
    assert len(ordered) == 3
    assert "cooldown kapalı" in note


def test_topic_automation_uses_same_cooldown_rule():
    """topic_automation._pick_topic de sessizce havuz sıfırlamamalı."""
    from src import topic_automation as ta

    now = time.time()
    used: set[str] = set()
    for topic in POOL:
        na._remember(used, {"title": topic["title"]})
    state = {"history": [{"at": _iso(now - 86400), "topic": t["title"]} for t in POOL]}

    assert ta._pick_topic(POOL, used, state, cooldown_days=45) is None
    assert ta._pick_topic(POOL, set(), state, cooldown_days=45) is not None


# ---------------------------------------------------------------------------
# 2) Dedup anahtarları
# ---------------------------------------------------------------------------
def test_same_title_from_different_source_is_deduped():
    used: set[str] = set()
    na._remember(used, {"title": "Konbini Kültürü", "link": ""})

    assert na._is_used({"title": "Konbini Kültürü",
                        "link": "https://baska-kaynak.example/haber"}, used)


def test_title_normalisation_ignores_case_and_punctuation():
    used: set[str] = set()
    na._remember(used, {"title": "Konbini Kültürü", "link": "https://a.example/1"})

    assert na._is_used({"title": "KONBINI  kültürü!", "link": "https://b.example/2"}, used)


def test_unrelated_title_is_not_deduped():
    used: set[str] = set()
    na._remember(used, {"title": "Konbini Kültürü", "link": ""})
    assert not na._is_used({"title": "Hakone Teleferik Hattı", "link": ""}, used)


def test_legacy_state_keys_still_match():
    """Mevcut state dosyaları (iki farklı eski hash şeması) geçersiz olmamalı."""
    import hashlib

    title = "Konbini Kültürü"
    legacy_news = hashlib.sha1(title.strip().lower().encode()).hexdigest()[:16]
    legacy_topic = hashlib.sha1(title.encode()).hexdigest()[:16]

    assert na._is_used({"title": title}, {legacy_news})
    assert na._is_used({"title": title}, {legacy_topic})


def test_ordered_used_preserves_recency_and_caps():
    previous = ["eski1", "eski2"]
    used = {"eski2", "yeni1", "yeni2"}
    out = na._ordered_used(previous, used)

    assert out[0] == "eski2", "hâlâ geçerli eski anahtar sırasını korumalı"
    assert set(out) == used
    assert "eski1" not in out, "artık kullanılmayan anahtar düşmeli"
    assert len(na._ordered_used([], {f"k{i}" for i in range(na._USED_CAP + 50)})) == na._USED_CAP


# ---------------------------------------------------------------------------
# 3) Toplu üretim — bir tur patlarsa bulk devam etmeli
# ---------------------------------------------------------------------------
@pytest.fixture()
def bulk(monkeypatch):
    """_run_now_bulk'u izole çalıştır: emit toplanır, cfg/otomasyon stub'lanır."""
    from threading import Event

    from src.web import app as web_app

    def _run(results, count=None):
        """results: her tur için dict (dönüş) veya Exception (fırlatılır)."""
        lines: list[str] = []
        calls = {"n": 0}

        def _fake_run(cfg, auto_publish=False):
            idx = calls["n"]
            calls["n"] += 1
            item = results[idx] if idx < len(results) else {"ok": False, "reason": "x"}
            if isinstance(item, Exception):
                raise item
            return item

        monkeypatch.setattr(web_app.news_automation_module, "run_once_with_publish",
                            _fake_run, raising=False)
        web_app._run_now_bulk(
            kind="news", count=count or len(results), forced_auto_publish=False,
            topic="", query="", emit=lambda text, kind="log": lines.append(text),
            cancel_ev=Event(),
        )
        return lines, calls["n"]

    return _run


def test_bulk_continues_after_one_iteration_raises(monkeypatch):
    """6 başarı + 1 exception → iş çökmemeli, kalan turlar denenmeli."""
    from threading import Event

    from src.web import app as web_app

    results = [{"ok": True, "file": f"kart{i}.jpg"} for i in range(6)]
    results.append(RuntimeError("Uygun görsel bulunamadı (Unsplash boş)."))
    results += [{"ok": True, "file": "kart7.jpg"}] * 3
    calls = {"n": 0}
    lines: list[str] = []

    def _fake_run(cfg, auto_publish=False):
        item = results[calls["n"]]
        calls["n"] += 1
        if isinstance(item, Exception):
            raise item
        return item

    import src.news_automation as news_mod
    monkeypatch.setattr(news_mod, "run_once_with_publish", _fake_run)

    web_app._run_now_bulk(
        kind="news", count=10, forced_auto_publish=False, topic="", query="",
        emit=lambda text, kind="log": lines.append(text), cancel_ev=Event(),
    )

    assert calls["n"] == 10, "hata veren tur bulk'u durdurmamalı"
    ozet = next(line for line in lines if line.startswith("📦"))
    assert "9/10 kart üretildi" in ozet
    assert "1 hata" in ozet


def test_bulk_stops_after_three_consecutive_errors(monkeypatch):
    from threading import Event

    import src.news_automation as news_mod
    from src.web import app as web_app

    calls = {"n": 0}
    lines: list[str] = []

    def _always_raise(cfg, auto_publish=False):
        calls["n"] += 1
        raise RuntimeError("dış servis düştü")

    monkeypatch.setattr(news_mod, "run_once_with_publish", _always_raise)

    with pytest.raises(RuntimeError, match="hiç kart üretilemedi"):
        web_app._run_now_bulk(
            kind="news", count=10, forced_auto_publish=False, topic="", query="",
            emit=lambda text, kind="log": lines.append(text), cancel_ev=Event(),
        )

    assert calls["n"] == 3, "üst üste 3 hatadan sonra devre kesici devreye girmeli"


def test_bulk_treats_no_image_as_skippable_not_terminal(monkeypatch):
    """no_image geçici bir durum — bulk erken sonlanmamalı."""
    from threading import Event

    import src.news_automation as news_mod
    from src.web import app as web_app

    results = [
        {"ok": False, "reason": "no_image", "detail": "Unsplash boş"},
        {"ok": True, "file": "kart1.jpg"},
        {"ok": True, "file": "kart2.jpg"},
    ]
    calls = {"n": 0}
    lines: list[str] = []

    def _fake_run(cfg, auto_publish=False):
        item = results[calls["n"]]
        calls["n"] += 1
        return item

    monkeypatch.setattr(news_mod, "run_once_with_publish", _fake_run)

    web_app._run_now_bulk(
        kind="news", count=3, forced_auto_publish=False, topic="", query="",
        emit=lambda text, kind="log": lines.append(text), cancel_ev=Event(),
    )

    assert calls["n"] == 3
    ozet = next(line for line in lines if line.startswith("📦"))
    assert "2/3 kart üretildi" in ozet
    assert "1 atlandı" in ozet


def test_bulk_stops_early_when_no_candidates_left(monkeypatch):
    """no_text gerçekten 'aday kalmadı' demek — boşuna tekrar denenmemeli."""
    from threading import Event

    import src.news_automation as news_mod
    from src.web import app as web_app

    calls = {"n": 0}
    lines: list[str] = []

    def _fake_run(cfg, auto_publish=False):
        calls["n"] += 1
        if calls["n"] == 1:
            return {"ok": True, "file": "kart1.jpg"}
        return {"ok": False, "reason": "no_text", "detail": "aday yok"}

    monkeypatch.setattr(news_mod, "run_once_with_publish", _fake_run)

    web_app._run_now_bulk(
        kind="news", count=10, forced_auto_publish=False, topic="", query="",
        emit=lambda text, kind="log": lines.append(text), cancel_ev=Event(),
    )

    assert calls["n"] == 2, "aday kalmadıysa bulk erken sonlanmalı"
    assert any("erken sonlandırıldı" in line for line in lines)


# ---------------------------------------------------------------------------
# 4) Havuz içeriği — kullanıcı isteği: ipucu niteliğinde konular
# ---------------------------------------------------------------------------
def test_topic_pool_covers_practical_travel_tips(project_root):
    import json

    pool = json.loads((project_root / "assets" / "topic_pool.json")
                      .read_text(encoding="utf-8"))["topics"]
    titles = " · ".join(t["title"] for t in pool)

    for beklenen in ("JR Pass", "Suica", "Kapsül Otel", "Universal Studios",
                     "Disneyland", "DisneySea", "teamLab", "Havalimanı"):
        assert beklenen in titles, f"havuzda eksik ipucu konusu: {beklenen}"

    # Başlıklar tekrarsız olmalı (normalize edilmiş hâliyle de)
    norms = [na._norm_title(t["title"]) for t in pool]
    assert len(norms) == len(set(norms)), "havuzda çakışan başlık var"

    # Unsplash sorguları marka adı içermemeli — stok fotoğrafta bulunmaz.
    yasak = ("disney", "universal", "teamlab", "nintendo", "pokemon", "ghibli")
    for topic in pool:
        q = topic["query"].lower()
        assert not any(marka in q for marka in yasak), \
            f"marka adı içeren görsel sorgusu: {topic['title']} → {topic['query']}"
