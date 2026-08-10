"""Görsel arama sorgusu zenginleştirme.

Sorun: kullanıcının yazdığı kelime ham hâlde Unsplash'e gidiyordu. Stok
fotoğraf arşivinde marka/tesis adı yoktur — gerçek ölçüm:

    "teamlabs"                                   →    3 sonuç (saat kulesi, portre)
    "immersive digital art installation japan"   → 2068 sonuç (ışık enstalasyonu)

Arayüz Türkçe olduğu için kullanıcı "tapınak bahçesi" de yazıyor; Unsplash
İngilizce arar. Bu testler üç kuralı kilitler: marka → sahne, Türkçe → İngilizce
(ek almış sözcükler dâhil), Japonya çıpası.
"""
from __future__ import annotations

import pytest

from src import downloader as dl


# ---------------------------------------------------------------------------
# Marka / tesis adı → çekilebilir genel sahne
# ---------------------------------------------------------------------------
@pytest.mark.parametrize("raw", ["teamlabs", "teamlab", "teamLab Planets",
                                 "teamlab borderless"])
def test_teamlab_becomes_photographable_scene(raw):
    out = dl.enrich_query(raw)
    assert "teamlab" not in out
    assert "digital art" in out
    assert "japan" in out


@pytest.mark.parametrize("raw,beklenen", [
    ("usj", "theme park"),
    ("universal studios japan", "theme park"),
    ("disneysea", "theme park"),
    ("tokyo disneyland", "amusement park"),
    ("pokemon center", "toy shop"),
    ("ghibli müzesi", "forest"),
    ("jr pass", "train station"),
    ("familymart", "convenience store"),
])
def test_brand_names_are_mapped_to_scenes(raw, beklenen):
    out = dl.enrich_query(raw)
    assert beklenen in out
    # Marka adının kendisi sorguda kalmamalı — stok fotoğrafta yok.
    for marka in ("disney", "universal", "pokemon", "ghibli", "familymart"):
        assert marka not in out


def test_place_anchor_survives_brand_mapping():
    """'tokyo disneyland' → şehir bilgisi kaybolmamalı."""
    out = dl.enrich_query("tokyo disneyland")
    assert out.startswith("tokyo")
    assert "amusement park" in out


# ---------------------------------------------------------------------------
# Türkçe → İngilizce (ek almış sözcükler dâhil)
# ---------------------------------------------------------------------------
@pytest.mark.parametrize("raw,beklenen", [
    ("tapınak", "japan temple"),
    ("tapınak bahçesi gece", "japan temple garden night"),
    ("kaplıca bahçesi", "japan hot spring garden"),
    ("tema parkı", "japan theme park"),
    ("kyoto sokakları", "kyoto street"),
    ("sonbahar yaprakları", "japan autumn leaves"),
    ("kar manzarası", "japan snow landscape"),
])
def test_turkish_words_are_translated(raw, beklenen):
    assert dl.enrich_query(raw) == beklenen


def test_untranslatable_turkish_word_is_dropped_not_sent_raw():
    """Çevrilemeyen Türkçe sözcük sorguyu kirletmemeli."""
    out = dl.enrich_query("şeyler")
    assert "şeyler" not in out
    assert out == "japan travel"


# ---------------------------------------------------------------------------
# Japonya çıpası
# ---------------------------------------------------------------------------
def test_japan_anchor_added_when_missing():
    assert dl.enrich_query("ramen").startswith("japan")
    assert dl.enrich_query("shinkansen").startswith("japan")


def test_existing_place_anchor_is_not_duplicated():
    out = dl.enrich_query("kyoto temple")
    assert out == "kyoto temple"
    assert out.count("japan") == 0


def test_fuji_gets_anchor_because_it_is_ambiguous():
    """'fuji' tek başına Fujifilm kameralarını da getiriyor."""
    assert dl.enrich_query("mount fuji view") == "japan mount fuji view"


def test_empty_query_falls_back_to_safe_scene():
    assert dl.enrich_query("") == "japan travel"
    assert dl.enrich_query("   ") == "japan travel"


def test_query_is_capped_to_eight_words():
    out = dl.enrich_query("tapınak bahçesi gece kar tren yemek çay köprü kule ada")
    assert len(out.split()) <= 8


# ---------------------------------------------------------------------------
# Kademeli fallback listesi
# ---------------------------------------------------------------------------
def test_ladder_goes_from_specific_to_safe():
    ladder = dl.build_search_queries("teamlabs")
    assert ladder[0] == dl.enrich_query("teamlabs")
    assert ladder[-1] == "japan"
    assert "japan travel" in ladder
    assert len(ladder) == len(set(ladder)), "tekrarlı sorgu olmamalı"


# ---------------------------------------------------------------------------
# search_with_fallback — ağ yok, search_only stub'lanır
# ---------------------------------------------------------------------------
@pytest.fixture()
def fake_search(monkeypatch):
    """search_only'yi sorgu→sonuç haritasıyla değiştirir, çağrıları kaydeder."""
    def _install(mapping):
        calls: list[str] = []

        def _fake(cfg, query, count=10, page=1):
            calls.append(query)
            return [{"id": f"{query}-{i}"} for i in range(mapping.get(query, 0))]

        monkeypatch.setattr(dl, "search_only", _fake)
        return calls
    return _install


def test_sparse_result_is_topped_up_from_broader_query(fake_search):
    """Spesifik sorgu 2 sonuç verirse grid genel sahneyle 10'a tamamlanır."""
    enriched = dl.enrich_query("teamlabs")
    calls = fake_search({enriched: 2, "japan immersive": 20})

    out = dl.search_with_fallback(object(), "teamlabs", count=10)

    assert len(out["results"]) == 10
    assert out["effective_query"] == enriched, "en alakalı sorgu gösterilmeli"
    assert out["results"][0]["id"].startswith(enriched), "spesifik sonuçlar üstte"
    assert len(calls) == 2


def test_single_request_when_first_query_is_enough(fake_search):
    """Sorgu yeterli sonuç veriyorsa fazladan istek yapılmaz (50/saat kotası)."""
    enriched = dl.enrich_query("kyoto temple")
    calls = fake_search({enriched: 10})

    out = dl.search_with_fallback(object(), "kyoto temple", count=10)

    assert len(calls) == 1
    assert len(out["results"]) == 10


def test_request_count_is_capped(fake_search):
    """Hiçbir sorgu sonuç vermese bile kota korunur: en fazla 3 istek."""
    calls = fake_search({})
    out = dl.search_with_fallback(object(), "teamlabs", count=10)
    assert len(calls) == 3
    assert out["results"] == []


def test_duplicate_ids_are_not_repeated(monkeypatch):
    """Aynı fotoğraf iki sorgudan gelirse grid'de bir kez görünmeli."""
    def _fake(cfg, query, count=10, page=1):
        return [{"id": "ayni"}, {"id": f"{query}-x"}]

    monkeypatch.setattr(dl, "search_only", _fake)
    out = dl.search_with_fallback(object(), "teamlabs", count=10)

    ids = [r["id"] for r in out["results"]]
    assert ids.count("ayni") == 1
    assert len(ids) == len(set(ids))


def test_network_error_on_later_query_keeps_earlier_results(monkeypatch):
    """İkinci sorgu patlarsa elde olan sonuçlar kaybolmamalı."""
    import requests

    enriched = dl.enrich_query("teamlabs")

    def _fake(cfg, query, count=10, page=1):
        if query == enriched:
            return [{"id": "a"}, {"id": "b"}]
        raise requests.RequestException("limit aşıldı")

    monkeypatch.setattr(dl, "search_only", _fake)
    out = dl.search_with_fallback(object(), "teamlabs", count=10)
    assert [r["id"] for r in out["results"]] == ["a", "b"]


def test_network_error_on_first_query_propagates(monkeypatch):
    """Hiç sonuç yokken hata yutulmaz — kullanıcı sebebi görmeli."""
    import requests

    def _fake(cfg, query, count=10, page=1):
        raise requests.RequestException("limit aşıldı")

    monkeypatch.setattr(dl, "search_only", _fake)
    with pytest.raises(requests.RequestException):
        dl.search_with_fallback(object(), "teamlabs", count=10)


# ---------------------------------------------------------------------------
# Otomasyon ve API aynı yardımcıyı kullanıyor mu?
# ---------------------------------------------------------------------------
def test_automation_pick_image_uses_shared_builder(project_root):
    src = (project_root / "src" / "news_automation.py").read_text(encoding="utf-8")
    assert "downloader.build_search_queries(query)" in src


def test_preview_endpoint_uses_fallback_search(project_root):
    src = (project_root / "src" / "web" / "app.py").read_text(encoding="utf-8")
    assert "downloader.search_with_fallback(" in src
    assert '"effective_query": found["effective_query"]' in src


def test_dashboard_shows_effective_query(project_root):
    js = (project_root / "src" / "web" / "static" / "dashboard" / "pages"
          / "create.js").read_text(encoding="utf-8")
    assert "res.effective_query" in js
    assert "picker-query-note" in js
