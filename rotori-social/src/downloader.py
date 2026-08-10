"""Unsplash otomatik arka plan indirici.

Story kartlarına arka plan olacak Japan temalı görselleri
`assets/story_backgrounds/` klasörüne indirir. Her sorgu için N adet
portrait-oriented CC0 fotoğraf (Getty benzeri kalite, ticari kullanım OK).

Dosya adı formatı: `unsplash-<query-slug>-<photo-id>.jpg`
→ story_generator._pick_from_assets buradaki query-slug'ı arıyor, GPT'nin
   arka_plan_anahtarlar'ıyla eşleşiyor.

Free tier: 50 istek/saat. Kullanıcı config'de 10 sorgu × 3 görsel = 30 dosya
(10 arama + 30 indirme = 40 istek — bol bol yeter).
"""
from __future__ import annotations

import re
import time
import unicodedata
from pathlib import Path
from threading import Event
from typing import Any, Callable

import requests

from src.config import Config
from src.utils.logging import get_logger

log = get_logger("downloader")


def _slugify(text: str) -> str:
    t = (text or "").lower()
    t = "".join(c for c in unicodedata.normalize("NFKD", t)
                if not unicodedata.combining(c))
    t = re.sub(r"[^a-z0-9]+", "-", t).strip("-")
    return t or "generic"


# ═════════════════════════════════════════════════════════════════════════════
# Sorgu zenginleştirme
# ═════════════════════════════════════════════════════════════════════════════
# Sorun: kullanıcının yazdığı kelime doğrudan Unsplash'e gidiyordu. Stok
# fotoğraf arşivinde MARKA/tesis adı yoktur; "teamlabs" 3 alakasız sonuç
# döndürür (saat kulesi, rastgele portre), "immersive digital art installation
# japan" ise 2000+ ilgili sonuç. Ayrıca arayüz Türkçe olduğu için kullanıcı
# "tapınak" yazıyor — Unsplash İngilizce arar.
#
# Bu yüzden her sorgu üç adımdan geçer:
#   1. Marka/tesis adı → çekilebilir GENEL sahne  (teamLab → digital art)
#   2. Türkçe seyahat sözcükleri → İngilizce       (tapınak → temple)
#   3. Japonya çıpası yoksa "japan" eklenir        (ramen → japan ramen)
# Sonra kademeli fallback listesi üretilir: hiçbir arama boş dönmesin.

# Marka/tesis → stok fotoğrafta BULUNABİLİR genel sahne. Anahtarlar normalize
# edilmiş (küçük harf, noktalama yok) biçimde aranır; en uzun eşleşme kazanır.
_BRAND_SCENES: dict[str, str] = {
    "teamlab planets": "immersive digital art installation dark room",
    "teamlab borderless": "immersive digital art installation dark room",
    "teamlab": "immersive digital art installation dark room",
    "teamlabs": "immersive digital art installation dark room",
    "tokyo disneysea": "theme park harbor night lights",
    "disneysea": "theme park harbor night lights",
    "tokyo disneyland": "amusement park castle night lights",
    "disneyland": "amusement park castle night lights",
    "disney": "amusement park castle night lights",
    "super nintendo world": "theme park colorful ride",
    "universal studios japan": "theme park roller coaster",
    "universal studios": "theme park roller coaster",
    "usj": "theme park roller coaster",
    "nintendo": "arcade game center neon",
    "pokemon center": "toy shop colorful display",
    "pokemon": "toy shop colorful display",
    "studio ghibli": "forest museum garden path",
    "ghibli": "forest museum garden path",
    "don quijote": "discount store aisle neon",
    "donki": "discount store aisle neon",
    "uniqlo": "clothing store shelves",
    "muji": "minimal store interior",
    "familymart": "japanese convenience store night",
    "seven eleven": "japanese convenience store night",
    "7 eleven": "japanese convenience store night",
    "lawson": "japanese convenience store night",
    "tokyo skytree": "tokyo tower skyline night",
    "skytree": "tokyo tower skyline night",
    "shibuya sky": "tokyo skyline observation deck",
    "jr pass": "japanese train station platform",
    "suica": "train ticket gate station",
    "pasmo": "train ticket gate station",
    "ic kart": "train ticket gate station",
    "ic card": "train ticket gate station",
    "takkyubin": "luggage suitcase station",
    "shukubo": "temple lodging garden",
    "minshuku": "japanese guesthouse tatami",
    "esim": "traveler smartphone city street",
    "cep wifi": "traveler smartphone city street",
    "pocket wifi": "traveler smartphone city street",
}

# Türkçe → İngilizce seyahat sözlüğü (kelime bazlı; UI Türkçe, Unsplash değil).
_TR_EN: dict[str, str] = {
    "tapınak": "temple", "tapinak": "temple", "mabet": "shrine",
    "kale": "castle", "saray": "palace", "bahçe": "garden", "bahce": "garden",
    "orman": "forest", "deniz": "sea", "dağ": "mountain", "dag": "mountain",
    "göl": "lake", "gol": "lake", "şelale": "waterfall", "selale": "waterfall",
    "sokak": "street", "cadde": "street", "çarşı": "market", "carsi": "market",
    "pazar": "market", "tren": "train", "metro": "subway",
    "istasyon": "station", "havalimanı": "airport", "havalimani": "airport",
    "otobüs": "bus", "otobus": "bus", "otel": "hotel",
    "konaklama": "hotel room", "yemek": "food", "balık": "fish", "balik": "fish",
    "çay": "tea", "cay": "tea", "kahve": "coffee", "tatlı": "dessert",
    "kar": "snow", "kış": "winter", "kis": "winter", "yaz": "summer",
    "ilkbahar": "spring", "sonbahar": "autumn", "gece": "night",
    "gündoğumu": "sunrise", "gunbatimi": "sunset", "günbatımı": "sunset",
    "festival": "festival", "havai": "fireworks", "fişek": "fireworks",
    "geyik": "deer", "maymun": "monkey", "kedi": "cat", "kuş": "bird",
    "müze": "museum", "muze": "museum", "sergi": "exhibition",
    "alışveriş": "shopping", "alisveris": "shopping", "manzara": "landscape",
    "köprü": "bridge", "kopru": "bridge", "kule": "tower", "ada": "island",
    "plaj": "beach", "kaplıca": "hot spring", "kaplica": "hot spring",
    "yürüyüş": "hiking", "yuruyus": "hiking", "çiçek": "blossom",
    "cicek": "blossom", "yaprak": "leaves", "gökdelen": "skyscraper",
    "gokdelen": "skyscraper", "tema": "theme", "parkı": "park", "parki": "park",
    "lunapark": "amusement park", "kapsül": "capsule", "kapsul": "capsule",
    "yolculuk": "travel", "ulaşım": "transport", "ulasim": "transport",
}

# Bunlardan biri varsa sorgu zaten yer/ülke çıpası taşıyor — "japan" eklenmez.
_JP_ANCHORS = {
    "japan", "japanese", "nippon", "tokyo", "kyoto", "osaka", "nara",
    "hokkaido", "okinawa", "sapporo", "nagoya", "kobe", "yokohama",
    "hiroshima", "kanazawa", "nikko", "hakone", "kamakura",
    # NOT: "fuji" bilinçli olarak YOK — tek başına Fujifilm kameralarını da
    # getiriyor. Çıpasız kalıp "japan fuji" olması daha isabetli sonuç veriyor.
    "shibuya", "shinjuku", "akihabara", "asakusa", "arashiyama",
    "dotonbori", "harajuku", "ginza", "ueno", "odaiba",
}


def _normalise(text: str) -> str:
    """Küçük harf, noktalama yerine boşluk, tek boşluk."""
    t = (text or "").lower()
    t = re.sub(r"[^0-9a-zçğıöşü]+", " ", t)
    return re.sub(r"\s+", " ", t).strip()


_TR_SPECIFIC = set("çğıöşü")


def _translate_word(word: str) -> str | None:
    """Türkçe sözcüğü İngilizceye çevir; çeviremezsen None (Türkçe ekli ise).

    Türkçe eklemeli bir dil: "bahçesi", "sokakları", "müzesi" sözlükte birebir
    yoktur. Bu yüzden gövde eşlemesi yapılır (en uzun kök kazanır).
    """
    if word in _TR_EN:
        return _TR_EN[word]
    for key in sorted((k for k in _TR_EN if len(k) >= 4), key=len, reverse=True):
        if word.startswith(key):
            return _TR_EN[key]
    # Hâlâ Türkçe'ye özgü harf taşıyorsa bu bir Türkçe sözcüktür ve Unsplash'te
    # karşılığı yoktur — sorguyu kirletmesin diye düşürülür.
    if any(ch in _TR_SPECIFIC for ch in word):
        return None
    return word


def enrich_query(raw: str) -> str:
    """Kullanıcı/LLM sorgusunu Unsplash'te sonuç verecek hâle getir."""
    norm = _normalise(raw)
    if not norm:
        return "japan travel"

    # Yer çıpasını sakla: marka eşlemesi "tokyo disneyland"ın tamamını yutsa da
    # şehir bilgisi kaybolmasın.
    place = next((w for w in norm.split() if w in _JP_ANCHORS), "")

    # 1) Marka/tesis eşlemesi — en uzun anahtar önce (teamlab planets > teamlab)
    for key in sorted(_BRAND_SCENES, key=len, reverse=True):
        if key in norm:
            norm = _normalise(norm.replace(key, " ") + " " + _BRAND_SCENES[key])
            break

    # 2) Türkçe sözcükleri İngilizceye çevir (çevrilemeyen Türkçe sözcük düşer)
    words = [w for w in (_translate_word(w) for w in norm.split()) if w]
    if not words and not place:
        # Sorgunun tamamı çevrilemedi → hiçbir bilgi kalmadı, güvenli sahneye düş.
        return "japan travel"

    # 3) Yer çıpasını geri koy, yoksa "japan" ekle
    if place and place not in words:
        words.insert(0, place)
    if not any(w in _JP_ANCHORS for w in words):
        words.insert(0, "japan")

    # Tekrarları koru-sıralı ele (ör. "japan japan tower")
    seen: set[str] = set()
    out = [w for w in words if not (w in seen or seen.add(w))]
    return " ".join(out[:8])   # Unsplash uzun sorgularda daralır → 8 kelime tavan


def build_search_queries(raw: str) -> list[str]:
    """Denenecek sorguları sırayla döndür — ilki en spesifik, sonu en güvenli.

    Kademeli fallback: zenginleştirilmiş sorgu boş dönerse daha genel bir
    sahneye düşer, böylece kullanıcı asla boş ekranla kalmaz.
    """
    enriched = enrich_query(raw)
    words = [w for w in enriched.split() if w != "japan"]
    ladder = [enriched]
    if words:
        ladder.append(f"japan {words[0]}")
    ladder += ["japan travel", "japan"]
    seen: set[str] = set()
    return [q for q in ladder if q and not (q in seen or seen.add(q))]


def _search_photos(access_key: str, query: str, per_page: int,
                   orientation: str, page: int = 1) -> list[dict[str, Any]]:
    r = requests.get(
        "https://api.unsplash.com/search/photos",
        headers={
            "Authorization": f"Client-ID {access_key}",
            "Accept-Version": "v1",
        },
        params={
            "query": query,
            "per_page": max(per_page, 5),
            "orientation": orientation,
            "content_filter": "high",
            "page": max(1, page),
        },
        timeout=30,
    )
    r.raise_for_status()
    data = r.json()
    return data.get("results", [])


def _track_download(access_key: str, download_link: str) -> None:
    """Unsplash guideline'a göre indirmeler track edilmeli (analytics).
    Bu istek attribution'a bilgi verir — ücretsiz."""
    try:
        requests.get(download_link,
                     headers={"Authorization": f"Client-ID {access_key}"},
                     timeout=10)
    except requests.RequestException:
        pass  # tracking non-critical


def search_only(cfg: Config, query: str, count: int = 10,
                page: int = 1) -> list[dict[str, Any]]:
    """Sorgu yap, download etmeden liste döndür — preview için.
    page: 1'den başlar; her artışta Unsplash search'in sonraki sayfası."""
    if cfg.unsplash is None:
        raise RuntimeError("Unsplash config yok")
    photos = _search_photos(cfg.unsplash.access_key, query,
                            per_page=count, orientation=cfg.unsplash.orientation,
                            page=page)
    out = []
    for p in photos:
        urls = p.get("urls", {})
        out.append({
            "id": p.get("id", ""),
            "photographer": p.get("user", {}).get("username", "unknown"),
            "photographer_name": p.get("user", {}).get("name", ""),
            "thumb": urls.get("small") or urls.get("thumb", ""),
            "download_url": urls.get("regular") or urls.get("full", ""),
            "download_track": p.get("links", {}).get("download_location", ""),
            "width": p.get("width", 0),
            "height": p.get("height", 0),
        })
    return out


def search_with_fallback(cfg: Config, query: str, count: int = 10,
                         page: int = 1) -> dict[str, Any]:
    """Zenginleştirilmiş sorguyla ara; boş dönerse daha genel sahnelere düş.

    Döner: {"results", "effective_query", "tried", "enriched"}
    `effective_query` sonucu getiren sorgudur — UI bunu kullanıcıya gösterir ki
    "neden bu görseller geldi" belli olsun.
    """
    tried: list[str] = []
    queries = build_search_queries(query)
    collected: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    effective = queries[0] if queries else query
    # Spesifik sorgu az sonuç verirse (portrait filtresi daralttığı için sık olur)
    # grid boş kalmasın: daha genel sahnelerle TAMAMLANIR, sıra korunur —
    # en alakalı üstte. İstek kotası (50/saat) için en fazla 3 arama yapılır.
    MAX_REQUESTS = 3
    for q in queries[:MAX_REQUESTS]:
        tried.append(q)
        try:
            results = search_only(cfg, q, count=count, page=page)
        except requests.RequestException as exc:
            log.warning(f"  Unsplash arama hatası ('{q}'): {exc}")
            if collected:
                break        # elde sonuç varsa hatayı yut, olanı döndür
            raise
        if results and not collected:
            effective = q    # sonucu ilk getiren sorgu "aranan" olarak gösterilir
        for item in results:
            if item.get("id") in seen_ids:
                continue
            seen_ids.add(item.get("id"))
            collected.append(item)
        if len(collected) >= count:
            break

    if collected:
        if _normalise(effective) != _normalise(query):
            log.info(f"  görsel arama: '{query}' → '{effective}' "
                     f"({len(collected)} sonuç, {len(tried)} sorgu)")
    else:
        log.warning(f"  Unsplash hiçbir sorgu için sonuç vermedi: {tried}")
    return {"results": collected[:count], "effective_query": effective,
            "tried": tried, "enriched": queries[0] if queries else query}


def download_selected(cfg: Config, query: str, items: list[dict[str, Any]],
                      emit: Callable[..., None], cancel: Event) -> None:
    """Kullanıcının modal'dan seçtiği görselleri indir."""
    if cfg.unsplash is None:
        emit("✖ Unsplash config yok.", "error")
        return
    if cfg.stories is None or cfg.stories.backgrounds_dir is None:
        emit("✖ stories.backgrounds_dir yok.", "error")
        return

    dst_dir = cfg.stories.backgrounds_dir
    dst_dir.mkdir(parents=True, exist_ok=True)
    slug = _slugify(query)

    emit(f"① Seçilen {len(items)} görsel indirilecek — '{query}'", "info")
    total_ok = 0
    total_skip = 0
    total_fail = 0

    for i, it in enumerate(items, 1):
        if cancel.is_set():
            emit("⏹ İptal edildi.", "warn")
            break
        pid = it.get("id", "?")
        url = it.get("download_url", "")
        track = it.get("download_track", "")
        photographer = it.get("photographer", "unknown")

        if not url:
            emit(f"  [{i}/{len(items)}] ✗ URL yok ({pid})", "warn")
            total_fail += 1
            continue

        filename = f"unsplash-{slug}-{pid}.jpg"
        dst = dst_dir / filename
        if dst.exists():
            total_skip += 1
            emit(f"  [{i}/{len(items)}] ⤵ zaten var: {filename}", "log")
            continue

        try:
            r = requests.get(url, timeout=60, stream=True)
            r.raise_for_status()
            with dst.open("wb") as fh:
                for chunk in r.iter_content(chunk_size=8192):
                    fh.write(chunk)
            kb = dst.stat().st_size // 1024
            total_ok += 1
            emit(f"  [{i}/{len(items)}] ✓ {filename} ({kb} KB) — @{photographer}", "log")
            if track:
                _track_download(cfg.unsplash.access_key, track)
            time.sleep(0.2)
        except (requests.RequestException, OSError) as exc:
            total_fail += 1
            emit(f"  [{i}/{len(items)}] ✗ indirme hatası: {exc}", "error")
            if dst.exists():
                dst.unlink()

    emit(f"② Bitti — kaydedilen: {total_ok} · atlanan: {total_skip} · başarısız: {total_fail}",
         "info")


def download_backgrounds(cfg: Config, emit: Callable[..., None],
                         cancel: Event, custom_query: str = "",
                         custom_count: int | None = None) -> None:
    """Config'deki tüm query'ler için görsel indir. Idempotent (var olanı
    atlar), iptal edilebilir.

    custom_query verilirse: sadece o sorgu için indirir (custom_count kadar,
    default 8). Config'deki queries listesi göz ardı edilir.
    """
    if cfg.unsplash is None:
        emit("✖ Unsplash config yok. config.yaml → unsplash.access_key doldur.", "error")
        return
    if cfg.stories is None or cfg.stories.backgrounds_dir is None:
        emit("✖ stories.backgrounds_dir yok. config.yaml → stories.backgrounds_dir doldur.", "error")
        return

    dst_dir = cfg.stories.backgrounds_dir
    dst_dir.mkdir(parents=True, exist_ok=True)

    if custom_query and custom_query.strip():
        queries = [custom_query.strip()]
        per_query = custom_count if custom_count and custom_count > 0 else 8
        emit(f"① Unsplash özel sorgu — '{custom_query.strip()}' × {per_query} görsel", "info")
    else:
        queries = cfg.unsplash.queries or []
        per_query = cfg.unsplash.per_query
        if not queries:
            emit("⚠ unsplash.queries listesi boş.", "warn")
            return
        emit(f"① Unsplash indirici başlıyor — {len(queries)} sorgu × {per_query} görsel", "info")

    emit(f"   klasör: {dst_dir}", "log")

    total_downloaded = 0
    total_skipped = 0
    total_failed = 0

    for q_idx, query in enumerate(queries, 1):
        if cancel.is_set():
            emit("⏹ İptal edildi.", "warn")
            break

        slug = _slugify(query)
        emit(f"── [{q_idx}/{len(queries)}] '{query}' ──", "info")

        try:
            photos = _search_photos(
                cfg.unsplash.access_key, query,
                per_page=per_query,
                orientation=cfg.unsplash.orientation,
            )
        except requests.HTTPError as exc:
            emit(f"  ✗ arama başarısız: HTTP {exc.response.status_code} — "
                 f"{exc.response.text[:120]}", "error")
            if exc.response.status_code in (401, 403):
                emit("  ✗ access_key geçersiz olabilir; unsplash.com/developers'dan doğrula.", "error")
                break
            continue
        except requests.RequestException as exc:
            emit(f"  ✗ ağ hatası: {exc}", "error")
            continue

        emit(f"  {len(photos)} sonuç bulundu, ilk {per_query} indirilecek", "log")
        for photo in photos[: per_query]:
            if cancel.is_set():
                break
            pid = photo.get("id", "unknown")
            photographer = photo.get("user", {}).get("username", "unknown")
            urls = photo.get("urls", {})
            img_url = urls.get("regular") or urls.get("full")
            dl_track = photo.get("links", {}).get("download_location", "")

            if not img_url:
                emit(f"  ⚠ {pid}: URL yok, atlanıyor", "warn")
                continue

            filename = f"unsplash-{slug}-{pid}.jpg"
            dst = dst_dir / filename
            if dst.exists():
                total_skipped += 1
                emit(f"  ⤵ {filename} zaten var", "log")
                continue

            try:
                img_r = requests.get(img_url, timeout=60, stream=True)
                img_r.raise_for_status()
                with dst.open("wb") as fh:
                    for chunk in img_r.iter_content(chunk_size=8192):
                        fh.write(chunk)
                size_kb = dst.stat().st_size // 1024
                total_downloaded += 1
                emit(f"  ✓ {filename} ({size_kb} KB) — @{photographer}", "log")

                # Unsplash guideline: her download'da tracking endpoint'e ping
                if dl_track:
                    _track_download(cfg.unsplash.access_key, dl_track)

                # rate limit için nezaket gecikmesi
                time.sleep(0.3)
            except (requests.RequestException, OSError) as exc:
                total_failed += 1
                emit(f"  ✗ indirme hatası {pid}: {exc}", "error")
                if dst.exists():
                    dst.unlink()

    emit(f"② Bitti — indirilen: {total_downloaded} · atlanan: {total_skipped} · "
         f"başarısız: {total_failed}. Toplam dosya: "
         f"{len(list(dst_dir.glob('*.jpg')) + list(dst_dir.glob('*.png')) + list(dst_dir.glob('*.webp')))}",
         "info")
