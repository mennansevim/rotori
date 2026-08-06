"""Japonya haber otomasyonu — RSS tara → uygun haber seç → kart üret → Drive'a at.

Akış (run_once):
  1) RSS feed'lerinden son N günün haberlerini çek (feedparser)
  2) GPT ile kanala uygun + daha önce kullanılmamış BİR haber seç
     (siyaset/felaket/trajedi/suç/spor-skoru elenir) + Unsplash arama kelimesi
  3) Unsplash'tan görsel indir
  4) GPT: belgesel Türkçe kart metni + Instagram post caption
  5) Standart kartı render et (JAPONYA/RÜYASI wordmark + metin)
  6) caption .txt + .json sidecar yaz → Drive senkron klasörüne kopyala
  7) state.json'a işaretle (tekrar yok)

Kullanım:
    python -m src.news_automation            # 1 tur çalıştır (Drive'a atar)
    python -m src.news_automation --publish  # üret + Onay Bekleyen'e taşı
    python -m src.news_automation --dry-run  # sadece seçim + metin, dosya yazmaz
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import html
import json
import os
import random
import re
import shutil
import sys
import time
from pathlib import Path
from typing import Any

from src.config import Config, load_config
from src.utils.logging import get_logger

log = get_logger("news")

_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
_STATE_SUBDIR = "data/news_automation"
_USED_CAP = 200   # state'te tutulacak maks. kullanılmış haber id sayısı
_TOPIC_POOL_PATH = "assets/topic_pool.json"   # evergreen fallback konu havuzu


# ---------------- state (dedup) ----------------
def _state_path(cfg: Config) -> Path:
    return cfg.project_root / _STATE_SUBDIR / "state.json"


def _load_state(cfg: Config) -> dict[str, Any]:
    p = _state_path(cfg)
    if p.exists():
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            pass
    return {"used_ids": [], "last_run": None, "history": []}


def _save_state(cfg: Config, state: dict[str, Any]) -> None:
    p = _state_path(cfg)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(p)   # atomic


def _news_id(entry: dict[str, Any]) -> str:
    seed = (entry.get("link") or entry.get("title") or "").strip().lower()
    return hashlib.sha1(seed.encode("utf-8")).hexdigest()[:16]


# ---------------- RSS fetch ----------------
def _strip_html(s: str) -> str:
    s = re.sub(r"<[^>]+>", " ", s or "")
    s = html.unescape(s)
    return re.sub(r"\s+", " ", s).strip()


def fetch_news(cfg: Config) -> list[dict[str, Any]]:
    """RSS kaynaklarını paralel çek, son lookback_days haberlerini döndür.

    Her kaynak bağımsız timeout ile çalışır; tek bir yavaş yayın diğerlerini
    bekletmez. Kaynak bazlı loglar JobManager üzerinden UI'a akar.
    """
    import feedparser
    import requests

    lookback = max(1, cfg.news.lookback_days) if cfg.news else 2
    now = time.time()
    cutoff = now - lookback * 86400
    feeds = cfg.news.feeds if cfg.news else []
    def feed_label(url: str) -> str:
        labels = {
            "tokyocheapo.com": "Tokyo Cheapo",
            "soranews24.com": "SoraNews24",
            "nippon.com": "Nippon.com",
            "japantoday.com": "Japan Today",
            "japantimes.co.jp": "Japan Times",
        }
        return next((v for k, v in labels.items() if k in url), url.split("/")[2] if "/" in url else url)

    def fetch_one(url: str) -> tuple[str, list[dict[str, Any]], float, str | None]:
        label = feed_label(url)
        started = time.monotonic()
        log.info(f"  ↗ {label} bağlanıyor…")
        try:
            # Paralel taramada tek bir kaynak en fazla 10 saniye bekletir.
            response = requests.get(url, headers={"User-Agent": _UA}, timeout=(3, 10))
            response.raise_for_status()
            d = feedparser.parse(response.content)
        except Exception as exc:  # noqa: BLE001 — tek kaynak tüm turu durdurmasın
            elapsed = time.monotonic() - started
            log.warning(f"  ✕ {label} yanıt vermedi ({elapsed:.1f}s) — diğer kaynaklarla devam ediliyor.")
            return label, [], elapsed, str(exc)
        source = (d.feed.get("title") if getattr(d, "feed", None) else "") or url
        local_items: list[dict[str, Any]] = []
        for e in d.entries:
            pub = None
            for key in ("published_parsed", "updated_parsed"):
                if e.get(key):
                    try:
                        pub = time.mktime(e[key])
                    except (OverflowError, ValueError):
                        pub = None
                    break
            # tarih varsa ve eskiyse ele; yoksa dahil et
            if pub is not None and pub < cutoff:
                continue
            title = (e.get("title") or "").strip()
            if not title:
                continue
            summary = _strip_html(e.get("summary") or e.get("description") or "")[:600]
            local_items.append({
                "title": title,
                "summary": summary,
                "link": (e.get("link") or "").strip(),
                "source": source,
                "published_ts": pub or 0.0,
            })
        elapsed = time.monotonic() - started
        log.info(f"  ✓ {label} tamamlandı · {len(local_items)} haber · {elapsed:.1f}s")
        return label, local_items, elapsed, None

    items: list[dict[str, Any]] = []
    if feeds:
        workers = min(4, len(feeds))
        log.info(f"  ⚡ {len(feeds)} RSS kaynağı paralel taranıyor (maks. {workers} eşzamanlı)…")
        with ThreadPoolExecutor(max_workers=workers, thread_name_prefix="rss") as pool:
            futures = [pool.submit(fetch_one, url) for url in feeds]
            for future in as_completed(futures):
                _label, feed_items, _elapsed, _error = future.result()
                items.extend(feed_items)
    # en yeni önce (tarihsizler sona)
    items.sort(key=lambda x: x["published_ts"], reverse=True)
    log.info(f"  {len(items)} haber toplandı ({len(feeds)} feed, son {lookback} gün)")
    return items


# ---------------- GPT: seçim + metin ----------------
_TR_STYLE = (
    "Türkçen kusursuz, akıcı ve ansiklopedik/belgesel olmalı. 3. şahıs, genel "
    "bilgi kipi ('…dır', '…olarak biliniyor', '…açıkladı'). Klişe/pazarlama dili "
    "YASAK ('büyüleyici', 'eşsiz', 'muhteşem', 'atmosfer sunar'). Emir/2. şahıs "
    "hitap YASAK. Uydurma YOK — yalnızca haberdeki bilgiye dayan. "
    "Japonca özel isim/terimleri BİREBİR ÇEVİRME, olduğu gibi bırak: "
    "'Shinkansen' (mermi treni DEĞİL), 'onsen', 'ryokan', 'konbini', 'sakura', "
    "'torii'. Kurum adları için resmi karşılık kullan (örn. 'JR East')."
)

_SELECT_SYSTEM = (
    "Sen @japonyaruyasi Instagram kanalının editörüsün. HEDEF KİTLE: Japonya'da "
    "YAŞAMAYAN, Japonya'ya gitmek isteyen veya merak eden kişiler (potansiyel "
    "turistler / hayalini kuranlar). Sana Japonya haberleri verilir; bu kitlenin "
    "'Japonya'ya gitsem bunu görür/yaşarım' diyeceği, görselleştirilebilir BİR "
    "haber seçersin. Yanıt SADECE JSON."
)


def _select_prompt(cands: list[dict[str, Any]]) -> str:
    lines = []
    for i, c in enumerate(cands):
        lines.append(f"[{i}] ({c['source']}) {c['title']} — {c['summary'][:180]}")
    liste = "\n".join(lines)
    return (
        "Aşağıda güncel Japonya haberleri var. TURİST/ziyaretçi adayının ilgisini "
        "en çok çekecek BİR haber seç.\n\n"
        "ÖNCELİK (bunları tercih et): mevsim ve doğa olayları (sakura/kiraz "
        "çiçeği, sonbahar yaprakları, kar/kış manzaraları), hava durumu ve gidiş "
        "zamanı, festivaller ve etkinlikler, gezilecek yerler/açılan yeni "
        "mekanlar (otel, park, sergi, müze), yemek/mutfak deneyimi, turizm "
        "haberleri ve rekorları, ulaşım (Shinkansen, JR Pass, turist kartları), "
        "kültürel deneyim, geleneksel mekanlar.\n"
        "ELE (SEÇME): Japonya'da yaşayanları ilgilendiren iç politika/seçim, "
        "ekonomi/borsa, iş dünyası, suç/cinayet, savaş, ölüm/felaket/deprem/kaza, "
        "spor skoru, skandal, hassas/trajik veya turistle alakasız yerel konular.\n\n"
        f"HABERLER:\n{liste}\n\n"
        "ÇIKTI: sadece JSON —\n"
        '  {"index": <uygun haberin numarası>, "unsplash_query": "<2-4 kelime '
        'İngilizce görsel arama>", "reason": "<kısa>"}\n'
        "Turist adayına hitap eden hiçbir haber yoksa: {\"index\": -1}\n\n"
        "unsplash_query KURALLARI (çok önemli — stok fotoğrafta bulunmalı):\n"
        "- ÇEKİLEBİLİR, GENEL bir sahne yaz. Marka/anime/film/karakter/kurum "
        "adı YAZMA (Evangelion, Ghibli, Uniqlo, Pokémon stok fotoğrafta YOK).\n"
        "- Haberin temasını gerçek bir sahneye çevir. Örnekler:\n"
        "  'Evangelion heykeli tren istasyonunda' → 'japanese train station'\n"
        "  'Studio Ghibli festivali' → 'tokyo cinema night' veya 'anime akihabara'\n"
        "  'sakura tahminleri' → 'cherry blossom park'\n"
        "  'yeni onsen oteli' → 'traditional ryokan onsen'\n"
        "- Japonya bağlamını koru (mümkünse 'japan/tokyo/kyoto' + sahne)."
    )


# NOT: Kart üst metni + caption üretimi artık src/editorial.py'daki PAYLAŞIMLI
# 'Japonya Rüyası araştırma editörü' system prompt'una taşındı (generate_text →
# editorial.generate_editorial). Eski _text_prompt / _CAPTION_SYSTEM /
# _caption_prompt fonksiyonları kaldırıldı; buton ve otomasyon aynı kalıbı kullanır.


def pick_news(cfg: Config, oai, items: list[dict[str, Any]],
              used_ids: set[str]) -> dict[str, Any] | None:
    fresh = [it for it in items if _news_id(it) not in used_ids]
    if not fresh:
        log.info("  Taze (kullanılmamış) haber yok.")
        return None
    cands = fresh[: (cfg.news.max_candidates if cfg.news else 25)]
    try:
        out = oai.chat_json(_SELECT_SYSTEM, _select_prompt(cands),
                            temperature=0.4, max_tokens=200)
    except (RuntimeError, ValueError) as exc:
        log.warning(f"  Haber seçimi (GPT) başarısız: {exc}")
        return None
    idx = out.get("index", -1)
    if not isinstance(idx, int) or idx < 0 or idx >= len(cands):
        log.info(f"  GPT uygun haber bulamadı (index={idx}).")
        return None
    chosen = dict(cands[idx])
    chosen["unsplash_query"] = (out.get("unsplash_query") or "japan").strip() or "japan"
    chosen["select_reason"] = out.get("reason", "")
    log.info(f"  Seçilen haber: {chosen['title'][:70]}  | görsel: {chosen['unsplash_query']}")
    return chosen


def generate_text(cfg: Config, oai, news: dict[str, Any]) -> tuple[str, str]:
    """Haberden kart üst metni + caption üret — PAYLAŞIMLI editöryel prompt ile.

    Hem 'Haberden Üret' butonu hem otomasyon bu yolu kullanır (ikisi de run_once
    → generate_text çağırır). İçerik, src/editorial.py'daki 'Japonya Rüyası
    araştırma editörü' system prompt'una ve 40-puan kalite kapısına tabidir.
    Uygun değilse ('', '') döner → run_once 'no_text' ile atlar."""
    from src import editorial

    pub_ts = news.get("published_ts") or 0.0
    pub_str = time.strftime("%Y-%m-%d", time.localtime(pub_ts)) if pub_ts else ""
    try:
        res = editorial.generate_editorial(
            oai, title=news.get("title", ""), summary=news.get("summary", ""),
            source=news.get("source", ""), published=pub_str,
        )
    except (RuntimeError, ValueError) as exc:
        log.warning(f"  editöryel üretim başarısız: {exc}")
        news["_gate_fail"] = {"baslik": news.get("title", "")[:70],
                              "toplam": None, "hata": str(exc)}
        return "", ""

    if not res.get("uygun"):
        toplam = res.get("toplam", 0)
        puan = res.get("puan") or {}
        # Puan kırılımını oku (varsa) → en zayıf kriterleri göster.
        kirilim = ", ".join(f"{k}={v}" for k, v in puan.items()) if puan else "—"
        log.info(f"  ⏭ Kalite kapısı: '{news.get('title', '')[:60]}' ELENDI "
                 f"(toplam={toplam}/50 < min={editorial.MIN_SCORE}) | puan: {kirilim}")
        news["_gate_fail"] = {"baslik": news.get("title", "")[:70],
                              "toplam": toplam, "puan": puan}
        return "", ""

    log.info(f"  ✓ Editöryel içerik (puan={res.get('toplam')}/50, "
             f"kategori={res.get('data', {}).get('kategori', '?')})")
    # Yapılandırılmış alanları news'e iliştir — run_once sidecar'a yazsın
    news["_editorial"] = res.get("data", {})
    news["_score"] = res.get("toplam", 0)   # karma sıralama için puanı sakla
    # Görsel konsepti üretildiyse Unsplash sorgusunu ONUNLA değiştir — metin ve
    # görsel aynı kaynaktan (editöryel model) gelir → uyum sağlamlaşır.
    gorsel = (res.get("gorsel_konsepti") or "").strip()
    if gorsel:
        log.info(f"  🎯 görsel konsepti: '{gorsel}' (seçim sorgusu güncellendi)")
        news["unsplash_query"] = gorsel
    return res["kart_ust_metni"], res["caption"]


# ---------------- Evergreen fallback (RSS'e bağımlı olmayan genel Japonya bilgisi) ----------------
def _load_topic_pool(cfg: Config) -> list[dict[str, Any]]:
    """assets/topic_pool.json'daki evergreen konuları döndür (yoksa boş liste)."""
    p = cfg.project_root / _TOPIC_POOL_PATH
    if not p.exists():
        return []
    try:
        return json.loads(p.read_text(encoding="utf-8")).get("topics", [])
    except (OSError, ValueError):
        return []


def generate_text_topic(cfg: Config, oai, cand: dict[str, Any]) -> tuple[str, str]:
    """Evergreen KONUDAN kart üst metni + caption üret — aynı editöryel prompt +
    kalite kapısı. cand['title'] konu başlığıdır. Uygun değilse ('', '') döner ve
    cand['_gate_fail'] doldurulur (neden raporu için)."""
    from src import editorial

    try:
        res = editorial.generate_editorial_topic(oai, cand.get("title", ""))
    except (RuntimeError, ValueError) as exc:
        log.warning(f"  evergreen üretim başarısız: {exc}")
        cand["_gate_fail"] = {"baslik": cand.get("title", "")[:70],
                              "toplam": None, "hata": str(exc)}
        return "", ""

    if not res.get("uygun"):
        toplam = res.get("toplam", 0)
        puan = res.get("puan") or {}
        kirilim = ", ".join(f"{k}={v}" for k, v in puan.items()) if puan else "—"
        log.info(f"  ⏭ Kalite kapısı (evergreen): '{cand.get('title', '')[:60]}' ELENDI "
                 f"(toplam={toplam}/50 < min={editorial.MIN_SCORE}) | puan: {kirilim}")
        cand["_gate_fail"] = {"baslik": cand.get("title", "")[:70],
                              "toplam": toplam, "puan": puan}
        return "", ""

    log.info(f"  ✓ Evergreen içerik (puan={res.get('toplam')}/50, "
             f"kategori={res.get('data', {}).get('kategori', '?')})")
    cand["_editorial"] = res.get("data", {})
    cand["_score"] = res.get("toplam", 0)   # karma sıralama için puanı sakla
    gorsel = (res.get("gorsel_konsepti") or "").strip()
    if gorsel:
        log.info(f"  🎯 görsel konsepti: '{gorsel}' (evergreen)")
        cand["unsplash_query"] = gorsel
    return res["kart_ust_metni"], res["caption"]


# ---------------- Görsel seçimi (dedup + vision doğrulama) ----------------
def _img_fits(oai, thumb_url: str, konu: str) -> bool:
    """Adayı GPT-vision ile denetle: bu görsel habere/temaya uygun mu?
    Thumb'ı indirip base64 gönderir (OpenAI Unsplash CDN'ini doğrudan çekemiyor).
    Denetim yapılamazsa True döner (engelleme)."""
    if not thumb_url:
        return True
    try:
        import base64
        import requests as _rq
        r = _rq.get(thumb_url, timeout=12, headers={"User-Agent": _UA})
        r.raise_for_status()
        mime = r.headers.get("Content-Type", "image/jpeg").split(";")[0].strip()
        if not mime.startswith("image/"):
            mime = "image/jpeg"
        data_uri = f"data:{mime};base64,{base64.b64encode(r.content).decode('ascii')}"
        out = oai.chat_vision_json(
            "Sen bir görsel editörüsün — bir haber görselinin konuya uygunluğunu "
            "denetlersin. Yanıt SADECE JSON.",
            f"Haber konusu: \"{konu}\"\n\nBu görsel, bu konudaki bir Japonya "
            "paylaşımına GÖRSEL olarak uygun/ilgili mi? Konuyu birebir göstermesi "
            "şart değil ama teması/atmosferi uymalı ve alakasız olmamalı "
            "(örn. konu 'tren' ise orman fotoğrafı UYGUN DEĞİL).\n"
            'JSON: {"uygun": true veya false}',
            image_url=data_uri, detail="low", temperature=0, max_tokens=30,
        )
        return bool(out.get("uygun", True))
    except Exception as exc:
        log.warning(f"  görsel denetimi atlandı: {exc}")
        return True


def _pick_image(cfg, oai, query: str, konu: str,
                used_bg_ids: set[str]) -> dict[str, Any] | None:
    """Habere uygun, DAHA ÖNCE KULLANILMAMIŞ görsel seç.
    Sorgu boş sonuç verirse kademeli genişletir; adayları vision ile doğrular
    (en fazla 3 aday denetlenir); hiçbiri geçmezse ilk kullanılmamışa düşer."""
    from src import downloader
    queries = [query, f"japan {query.split()[0]}" if query else "japan",
               "japan travel", "japan"]
    seen_q, results = set(), []
    for q in queries:
        q = q.strip()
        if not q or q in seen_q:
            continue
        seen_q.add(q)
        try:
            results = downloader.search_only(cfg, q, count=12)
        except Exception as exc:
            log.warning(f"  Unsplash arama hatası ('{q}'): {exc}")
            results = []
        if results:
            log.info(f"  görsel arama: '{q}' → {len(results)} sonuç")
            break
    if not results:
        return None

    unused = [r for r in results if r.get("id") not in used_bg_ids]
    pool = unused or results   # hepsi kullanıldıysa mecburen tekrar

    # ilk 3 kullanılmamış adayı vision ile doğrula, ilk 'uygun'u seç.
    # Denetim ÖZNESİ = genel görsel konsepti (query) — spesifik başlık değil.
    # Böylece stok fotoğrafta ULAŞILABİLİR bir eşleşme doğrulanır (generic
    # konbini görseli 'convenience store' konseptine uyar; orman uymaz).
    vision_subject = query or konu
    checked = 0
    for cand in pool:
        if checked >= 3:
            break
        checked += 1
        if _img_fits(oai, cand.get("thumb") or cand.get("download_url", ""), vision_subject):
            log.info(f"  ✓ görsel uygun bulundu (id={cand.get('id')}, {checked}. aday)")
            return cand
        log.info(f"  ✗ aday uygun değil (id={cand.get('id')}), sonrakine bakılıyor")
    # hiçbiri doğrulanmadı → en iyi kullanılmamış (yoksa ilk)
    log.info("  uygun aday doğrulanamadı — ilk kullanılmamış görsel kullanılıyor")
    return pool[0]


# ---------------- Drive kopyala ----------------
def _copy_to_drive(cfg: Config, jpg: Path) -> list[str]:
    if cfg.drive_folder is None:
        log.info("  drive.folder ayarsız — Drive'a kopyalanmadı.")
        return []
    dest = cfg.drive_folder
    try:
        dest.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        log.warning(f"  Drive klasörü erişilemedi ({dest}): {exc}")
        return []
    copied = []
    for f in (jpg, jpg.with_suffix(".txt")):
        if f.exists():
            try:
                shutil.copy2(f, dest / f.name)
                copied.append(f.name)
            except OSError as exc:
                log.warning(f"  Drive kopyalama hatası ({f.name}): {exc}")
    return copied


# ---------------- ana akış ----------------
def run_once(cfg: Config, dry_run: bool = False) -> dict[str, Any]:
    if cfg.news is None or not cfg.news.enabled:
        log.info("Haber otomasyonu kapalı (config: news_automation.enabled=false).")
        return {"ok": False, "reason": "disabled"}
    if cfg.openai is None:
        raise RuntimeError("OpenAI key gerekli (config.yaml → openai.api_key).")

    from src.openai_client import OpenAIClient
    from src import editorial
    oai = OpenAIClient.from_config(cfg)
    if oai is None:
        raise RuntimeError("OpenAI client oluşturulamadı.")

    # Instagram Graph token'ını fırsatçı yenile — haftalık otomasyon her
    # çalıştığında ~60 gün uzatır → token süresiz otomatik yaşar, elle
    # uğraşmak gerekmez. Başarısız olursa (token çok taze / IP kısıtı) sessizce
    # geçer; mevcut token zaten geçerlidir.
    if cfg.instagram and cfg.instagram.graph_token:
        try:
            from src import instagram_graph
            instagram_graph.ensure_fresh_token(cfg)
        except Exception as exc:   # noqa: BLE001 — yenileme opsiyonel, akışı durdurma
            log.info(f"  Graph token yenileme atlandı: {exc}")

    log.info("=== Haber otomasyonu başladı ===")
    items = fetch_news(cfg)
    if not items:
        log.info("Hiç haber toplanamadı (feed'ler boş/erişilemez).")
        return {"ok": False, "reason": "no_news"}

    state = _load_state(cfg)
    used = set(state.get("used_ids", []))

    # Kalite kapısı (editorial) seçilen haberi eleyebilir. Uygun bir aday
    # bulunana kadar DÖNGÜ: her turda başka haber seçtir; havuz tükenirse
    # feed'leri yeniden çekip baştan dene. TIMEOUT (varsayılan 5 dk) dolunca dur.
    # Env: NEWS_GATE_TIMEOUT_SEC ile ayarlanabilir.
    # Öncelik: env > config.yaml (news_automation) > kod varsayılanı.
    def _int_pref(env_key: str, cfg_val: int) -> int:
        raw = os.environ.get(env_key)
        if raw is not None:
            try:
                return int(float(raw))
            except ValueError:
                pass
        return cfg_val

    ncfg = cfg.news
    timeout_sec = float(_int_pref("NEWS_GATE_TIMEOUT_SEC",
                                  getattr(ncfg, "gate_timeout_sec", 180)))
    deadline = time.monotonic() + timeout_sec
    tried_ids: set[str] = set()
    news: dict[str, Any] | None = None
    aciklama = caption = ""
    fails: list[dict[str, Any]] = []   # elenen adayların özeti (neden raporu için)
    attempt = 0
    refetches = 0
    log.info(f"  Kalite kapısı döngüsü başladı (timeout={int(timeout_sec)}sn, "
             f"min={editorial.MIN_SCORE}/50).")

    # ── KARMA HAVUZ ──────────────────────────────────────────────────────────
    # Artık "ilk geçen kazanır" DEĞİL: hem RSS haberleri hem evergreen konular
    # AYNI kalite kapısından geçirilir, puanı saklanır ve EN YÜKSEK PUANLI kazanır.
    # winners: kapıyı geçen adaylar (her birinde _score/_aciklama/_caption var).
    # Ayarlar (env > config.yaml > varsayılan): NEWS_RSS_TRIES, NEWS_EVERGREEN_TRIES,
    # NEWS_EVERGREEN_FALLBACK=0 ile evergreen'i tamamen kapat.
    winners: list[dict[str, Any]] = []
    rss_tries = max(1, _int_pref("NEWS_RSS_TRIES", getattr(ncfg, "rss_tries", 6)))

    # Faz 1 — RSS haberlerini puanla (en fazla rss_tries aday veya deadline).
    while time.monotonic() < deadline and len(winners) < rss_tries:
        attempt += 1
        cand = pick_news(cfg, oai, items, used | tried_ids)
        if cand is None:
            # Bu turda işlenebilir haber kalmadı → feed'leri tazele, baştan dene.
            if attempt == 1 and refetches == 0:
                log.warning("  Kalite eşiğini geçebilecek uygun haber bulunamadı "
                            "(feed'ler yumuşak/haber niteliği düşük olabilir).")
            break
        a, c = generate_text(cfg, oai, cand)
        if a and len(a) >= 8:
            cand["_aciklama"] = a
            cand["_caption"] = c
            winners.append(cand)
            log.info(f"  ➕ RSS adayı kapıyı geçti (puan={cand.get('_score')}/50): "
                     f"{cand.get('title', '')[:60]}")
        else:
            gf = cand.get("_gate_fail")
            if gf:
                fails.append(gf)
        tried_ids.add(_news_id(cand))

    # Faz 2 — Evergreen konuları puanla (RSS'e bağımlı DEĞİL, her tur yarışır).
    ev_env = os.environ.get("NEWS_EVERGREEN_FALLBACK")
    if ev_env is not None:
        ev_on = ev_env not in ("0", "false", "False")
    else:
        ev_on = bool(getattr(ncfg, "evergreen_enabled", True))
    if ev_on and time.monotonic() < deadline:
        pool = _load_topic_pool(cfg)
        if pool:
            fresh_topics = [t for t in pool
                            if _news_id({"title": t.get("title", "")}) not in used]
            if not fresh_topics:   # havuz tükendiyse baştan (dedup sıfırla)
                fresh_topics = list(pool)
            random.shuffle(fresh_topics)
            ev_tries = max(1, _int_pref("NEWS_EVERGREEN_TRIES",
                                        getattr(ncfg, "evergreen_tries", 6)))
            log.info(f"  🌿 Evergreen konular yarışa katılıyor "
                     f"({len(fresh_topics)} taze konu, en fazla {ev_tries} deneme).")
            for t in fresh_topics[:ev_tries]:
                if time.monotonic() >= deadline:
                    break
                cand = {
                    "title": t.get("title", ""),
                    "summary": "",
                    "link": "",
                    "source": "Evergreen (konu havuzu)",
                    "published_ts": time.time(),
                    "unsplash_query": t.get("query") or "japan",
                }
                a, c = generate_text_topic(cfg, oai, cand)
                if a and len(a) >= 8:
                    cand["_aciklama"] = a
                    cand["_caption"] = c
                    winners.append(cand)
                    log.info(f"  ➕ Evergreen adayı kapıyı geçti "
                             f"(puan={cand.get('_score')}/50): {t.get('title', '')}")
                else:
                    gf = cand.get("_gate_fail")
                    if gf:
                        fails.append(gf)
        else:
            log.info("  🌿 Evergreen havuz boş/bulunamadı (assets/topic_pool.json).")

    # ── KAZANAN — en yüksek puanlı aday ──────────────────────────────────────
    if winners:
        winners.sort(key=lambda w: w.get("_score", 0), reverse=True)
        news = winners[0]
        aciklama = news.get("_aciklama", "")
        caption = news.get("_caption", "")
        src_tip = "evergreen" if news.get("source", "").startswith("Evergreen") else "RSS"
        log.info(f"  🏆 KAZANAN ({src_tip}, puan={news.get('_score')}/50): "
                 f"{news.get('title', '')[:60]}")
        if len(winners) > 1:
            digerleri = ", ".join(f"{w.get('title', '')[:30]}→{w.get('_score')}"
                                  for w in winners[1:])
            log.info(f"    (yarıştaki diğerleri: {digerleri})")
    elif time.monotonic() >= deadline:
        log.warning(f"  ⏰ {int(timeout_sec)}sn timeout doldu — uygun aday bulunamadı.")

    if news is None:
        # Neden raporu: kaç aday elendi + en yüksek puan + kırılım.
        scored = [f for f in fails if isinstance(f.get("toplam"), (int, float))]
        best = max((f["toplam"] for f in scored), default=None)
        satirlar = []
        for f in fails:
            t = f.get("toplam")
            tstr = f"{t}/50" if isinstance(t, (int, float)) else "hata"
            satirlar.append(f"• {f.get('baslik', '?')} → {tstr}")
        detail = (
            f"{len(fails)} aday kalite kapısını geçemedi "
            f"(min={editorial.MIN_SCORE}/50"
            + (f", en yüksek={best}/50" if best is not None else "")
            + f", {int(timeout_sec)}sn timeout doldu)."
        )
        log.warning("  Hiçbir aday kalite kapısını geçemedi — tur boş.")
        for s in satirlar:
            log.warning(f"    {s}")
        return {"ok": False, "reason": "no_text", "detail": detail,
                "fails": satirlar}

    log.info(f"  Kart metni: {aciklama}")
    if dry_run:
        log.info("  [DRY-RUN] dosya yazılmadı, Drive'a kopyalanmadı.")
        return {"ok": True, "dry_run": True, "news": news, "aciklama": aciklama,
                "caption_preview": caption[:120]}

    # görsel — habere uygun + kullanılmamış + vision doğrulamalı
    if cfg.stories is None:
        raise RuntimeError("stories config yok — kart render edilemez.")
    from src import story_generator
    used_bg = set(state.get("used_bg_ids", []))
    bg = _pick_image(cfg, oai, news["unsplash_query"], news["title"], used_bg)
    if bg is None:
        raise RuntimeError("Uygun görsel bulunamadı (Unsplash boş).")

    out_path = story_generator.render_from_url(
        cfg, bg_url=bg["download_url"], bg_id=bg["id"],
        bg_query=news["unsplash_query"], baslik="", aciklama=aciklama,
        photographer=bg.get("photographer", ""),
    )
    # caption .txt
    if caption:
        try:
            out_path.with_suffix(".txt").write_text(caption, encoding="utf-8")
        except OSError as exc:
            log.warning(f"  caption .txt yazılamadı: {exc}")
    # .json sidecar (UI'da düzenlenebilsin + kaynak haber linki)
    try:
        slug_q = story_generator._slugify(news["unsplash_query"])
        editorial_data = news.get("_editorial", {})
        out_path.with_suffix(".json").write_text(json.dumps({
            "background_url": bg["download_url"], "background_id": bg["id"],
            "query": news["unsplash_query"],
            "baslik": news.get("title", ""),
            "bg_local": f"unsplash-{slug_q}-{bg['id']}.jpg",
            "photographer": bg.get("photographer", ""),
            "aciklama": aciklama, "ust_tag": "GEZİ DEFTERİ", "style": "style2",
            "post_caption": caption,
            "kategori": editorial_data.get("kategori", ""),
            "puan": editorial_data.get("puan", {}),
            "toplam_puan": editorial_data.get("toplam"),
            "kaynak": editorial_data.get("kaynak", ""),
            "source_news": {"title": news["title"], "link": news["link"],
                            "source": news["source"]},
            "auto_generated": True,
        }, ensure_ascii=False, indent=2), encoding="utf-8")
    except OSError as exc:
        log.warning(f"  sidecar yazılamadı: {exc}")

    copied = _copy_to_drive(cfg, out_path)

    # state güncelle (haber + görsel dedup)
    used.add(_news_id(news))
    state["used_ids"] = list(used)[-_USED_CAP:]
    used_bg.add(bg["id"])
    state["used_bg_ids"] = list(used_bg)[-_USED_CAP:]
    state["last_run"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    state.setdefault("history", []).append({
        "at": state["last_run"], "title": news["title"], "link": news["link"],
        "file": out_path.name, "drive": bool(copied),
    })
    state["history"] = state["history"][-100:]
    _save_state(cfg, state)

    log.info(f"✓ Kart üretildi: {out_path.name} | Drive: {copied or 'kopyalanmadı'}")

    # Onay Bekleyen'e taşı (auto_publish=true iken) — yayına ALMAZ, kullanıcı
    # widget'ta inceleyip onaylayana kadar bekletir.
    pending_notified = False
    if globals().get("_AUTO_PUBLISH_NEXT"):
        try:
            log.info("  📥 Onay listesine ekleniyor…")
            pending_dir = cfg.stories.output_dir / "pending_approval"
            pending_dir.mkdir(parents=True, exist_ok=True)
            new_path = pending_dir / out_path.name
            out_path.rename(new_path)
            for suf in (".txt", ".json"):
                s = out_path.with_suffix(suf)
                if s.exists():
                    s.rename(new_path.with_suffix(suf))
            # source alanını sidecar'a ekle (widget'ta rengi ayırt etmek için)
            meta_p = new_path.with_suffix(".json")
            if meta_p.exists():
                try:
                    meta = json.loads(meta_p.read_text(encoding="utf-8"))
                    meta["source"] = "haber"
                    meta_p.write_text(json.dumps(meta, ensure_ascii=False, indent=2),
                                       encoding="utf-8")
                except (OSError, ValueError):
                    pass
            # Mac notification
            try:
                from src.mac_notifier import notify
                notify(
                    title="Onay Bekliyor — Haber",
                    subtitle="@japonyaruyasi",
                    message=news["title"][:80],
                )
                pending_notified = True
            except Exception as exc:
                log.warning(f"  Notification atlandı: {exc}")
            out_path = new_path
        except OSError as exc:
            log.warning(f"  pending'e taşıma hatası: {exc}")

    log.info("=== Haber otomasyonu bitti ===")
    return {"ok": True, "file": out_path.name, "copied": copied,
            "news_title": news["title"], "news_link": news["link"],
            "pending": pending_notified}


# Modül seviyesinde flag — CLI'dan / run_once caller'dan set edilir
_AUTO_PUBLISH_NEXT = False


def run_once_with_publish(cfg: Config, auto_publish: bool = False,
                          dry_run: bool = False) -> dict[str, Any]:
    """run_once'un auto_publish flag'iyle sarmalanmış hali (module-global
    kullanmak yerine wrapper — thread-safe olmasa da tek job/tur akışında OK)."""
    global _AUTO_PUBLISH_NEXT
    _AUTO_PUBLISH_NEXT = bool(auto_publish and not dry_run)
    try:
        return run_once(cfg, dry_run=dry_run)
    finally:
        _AUTO_PUBLISH_NEXT = False


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Japonya haber otomasyonu — 1 tur")
    ap.add_argument("--dry-run", action="store_true",
                    help="Sadece haber seçimi + metin üret, dosya yazma/Drive'a atma")
    ap.add_argument("--publish", action="store_true",
                    help="Üretilen kartı Onay Bekleyen'e taşı")
    ap.add_argument("--config", default=None, help="config.yaml yolu")
    args = ap.parse_args(argv)
    cfg = load_config(args.config)
    try:
        res = run_once_with_publish(cfg, auto_publish=args.publish,
                                    dry_run=args.dry_run)
    except Exception as exc:
        log.error(f"HATA: {exc}")
        return 1
    return 0 if res.get("ok") else 2


if __name__ == "__main__":
    sys.exit(main())
