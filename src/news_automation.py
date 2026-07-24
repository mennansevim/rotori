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
    python -m src.news_automation --dry-run  # sadece seçim + metin, dosya yazmaz
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
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
    """Tüm feed'lerden haberleri çek, son lookback_days içindekileri döndür
    (en yeni önce). Tarihi olmayan haberler dahil edilir."""
    import feedparser

    lookback = max(1, cfg.news.lookback_days) if cfg.news else 2
    now = time.time()
    cutoff = now - lookback * 86400
    items: list[dict[str, Any]] = []
    feeds = cfg.news.feeds if cfg.news else []
    for url in feeds:
        try:
            d = feedparser.parse(url, agent=_UA)
        except Exception as exc:
            log.warning(f"  feed alınamadı ({url}): {exc}")
            continue
        source = (d.feed.get("title") if getattr(d, "feed", None) else "") or url
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
            items.append({
                "title": title,
                "summary": summary,
                "link": (e.get("link") or "").strip(),
                "source": source,
                "published_ts": pub or 0.0,
            })
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


def _text_prompt(news: dict[str, Any]) -> str:
    return (
        "Aşağıdaki Japonya haberinden bir Instagram kartının ÜST METNİNİ üret. "
        "Bu metin kartın üstünde büyük görünür — KISA ve MERAK UYANDIRAN bir "
        "haber spotu olmalı. Detay caption'a bırakılır, kartta VERİLMEZ.\n\n"
        f"BAŞLIK: {news['title']}\n"
        f"ÖZET: {news['summary']}\n\n"
        "KURALLAR:\n"
        "- TEK cümle, en fazla ~14 kelime. Kısa, vurucu.\n"
        "- Profesyonel bir haber editörü/gazeteci tonu — abartısız ama İLGİ "
        "ÇEKİCİ. Haberin en çarpıcı/şaşırtıcı yönünü öne çıkar; okuru "
        "meraklandır ('peki nasıl/neden?' dedirt) ama tüm detayı AÇIKLAMA.\n"
        "- Spesifik sayı/tarih/yer/kurum adı YIĞMA — bunlar caption'da yer alır.\n"
        "- Ucuz clickbait YASAK ('inanmayacaksınız', 'şok', 'bakın ne oldu', "
        "'bir tık'). Klişe/pazarlama dili YASAK. 2. şahıs/emir YASAK.\n"
        "- 3. şahıs, kusursuz Türkçe. Emoji YOK. Japonca özel terimleri çevirme "
        "(Shinkansen, onsen, ryokan, sakura olduğu gibi).\n\n"
        "Örnek ton (kısa + meraklandıran):\n"
        "✓ 'Bir Japon tren istasyonu, dev bir anime heykeline ev sahipliği yapacak.'\n"
        "✓ 'Japonya'da bir tren, bu yaz hareket eden bir otele dönüşüyor.'\n\n"
        "Sadece metni yaz — başlık/tırnak/prefix EKLEME."
    )


_CAPTION_SYSTEM = (
    "Sen @japonyaruyasi için profesyonel bir haber editörü/gazeteci tonunda "
    "Instagram post caption'ı yazan bir editörsün. Kart üstündeki kısa spot "
    "merak uyandırır; caption ise haberin DETAYINI (kim, ne, nerede, ne zaman, "
    "neden) net ve akıcı biçimde açıklar. Kusursuz Türkçe, klişesiz. Uydurma YOK."
)


def _caption_prompt(news: dict[str, Any], aciklama: str) -> str:
    return (
        f"Haber başlığı: {news['title']}\n"
        f"Haber özeti: {news['summary']}\n"
        f"Kartın üst spotu (bunu TEKRARLAMA, detaylandır): {aciklama}\n\n"
        "Bunu, haberin detayını veren bir Instagram post caption'ına dönüştür. "
        "Kart sadece merak uyandırdı; burada CEVABI ver. Format:\n"
        "1. Açılış (1-2 cümle, 1-2 emoji): haberin özü — ne oldu, nerede, "
        "kim/hangi kurum. Gazeteci netliğinde.\n"
        "2. 3-4 madde (her satır emoji + 1 somut detay: tarih, yer, sayı, "
        "arka plan, neden önemli).\n"
        "3. Kısa kapanış/CTA (örn 'Kaydet 📌', 'Detaylar için takipte kal 🇯🇵').\n"
        "4. Boş satır + 8-12 hashtag (Türkçe/İngilizce karışık).\n"
        "Klişe/ucuz clickbait/emir/2. şahıs YASAK. 400-1200 karakter. "
        "Yalnızca yalın haberdeki bilgiye dayan. Sadece caption — markdown "
        "başlığı/prefix YOK."
    )


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
    aciklama = oai.chat_text(
        "Sen @japonyaruyasi için profesyonel bir haber editörü tonunda KISA, "
        "merak uyandıran haber spotları yazan bir editörsün. Yanıt SADECE metin.",
        _text_prompt(news), temperature=0.7, max_tokens=70,
    ).strip().strip('"').strip("'").strip()
    caption = ""
    try:
        caption = oai.chat_text(_CAPTION_SYSTEM, _caption_prompt(news, aciklama),
                                temperature=0.8, max_tokens=700).strip()
    except (RuntimeError, ValueError) as exc:
        log.warning(f"  caption üretilemedi: {exc}")
    return aciklama, caption


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

    # ilk 3 kullanılmamış adayı vision ile doğrula, ilk 'uygun'u seç
    checked = 0
    for cand in pool:
        if checked >= 3:
            break
        checked += 1
        if _img_fits(oai, cand.get("thumb") or cand.get("download_url", ""), konu):
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
    oai = OpenAIClient.from_config(cfg)
    if oai is None:
        raise RuntimeError("OpenAI client oluşturulamadı.")

    log.info("=== Haber otomasyonu başladı ===")
    items = fetch_news(cfg)
    if not items:
        log.info("Hiç haber toplanamadı (feed'ler boş/erişilemez).")
        return {"ok": False, "reason": "no_news"}

    state = _load_state(cfg)
    used = set(state.get("used_ids", []))
    news = pick_news(cfg, oai, items, used)
    if news is None:
        return {"ok": False, "reason": "no_suitable_news"}

    aciklama, caption = generate_text(cfg, oai, news)
    if not aciklama or len(aciklama) < 8:
        log.warning("  Kart metni üretilemedi/çok kısa — atlanıyor.")
        return {"ok": False, "reason": "no_text"}

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
        out_path.with_suffix(".json").write_text(json.dumps({
            "background_url": bg["download_url"], "background_id": bg["id"],
            "query": news["unsplash_query"],
            "bg_local": f"unsplash-{slug_q}-{bg['id']}.jpg",
            "photographer": bg.get("photographer", ""),
            "aciklama": aciklama, "ust_tag": "GEZİ DEFTERİ",
            "post_caption": caption,
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

    # Otomatik yayın (opsiyonel) — Instagram Graph API üzerinden direkt
    published_media_id = None
    if globals().get("_AUTO_PUBLISH_NEXT") and cfg.instagram and cfg.instagram.graph_token:
        try:
            log.info("  📤 Otomatik yayına gönderiliyor…")
            # kartı ready/ altına taşı (aksi halde image_url erişilebilir olmayabilir)
            ready_dir = cfg.stories.output_dir / "ready"
            ready_dir.mkdir(parents=True, exist_ok=True)
            new_path = ready_dir / out_path.name
            out_path.rename(new_path)
            for suf in (".txt", ".json"):
                s = out_path.with_suffix(suf)
                if s.exists():
                    s.rename(new_path.with_suffix(suf))
            base = (cfg.instagram.public_base_url or "").rstrip("/")
            if not base:
                log.warning("  public_base_url boş — otomatik yayın atlandı")
            else:
                from urllib.parse import quote
                from src import instagram_graph
                image_url = f"{base}/media/stories/ready/{quote(new_path.name)}"
                cap = new_path.with_suffix(".txt")
                cap_text = cap.read_text(encoding="utf-8") if cap.exists() else ""
                res = instagram_graph.publish_image(cfg, image_url, cap_text)
                published_media_id = res["id"]
                # uploads_log
                import json as _json
                rec = {"name": new_path.stem, "media_id": res["id"],
                       "container_id": res["container_id"],
                       "uploaded_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
                       "method": "graph_auto"}
                log_path = cfg.project_root / cfg.instagram.uploads_log
                log_path.parent.mkdir(parents=True, exist_ok=True)
                with log_path.open("a", encoding="utf-8") as f:
                    f.write(_json.dumps(rec, ensure_ascii=False) + "\n")
                log.info(f"  ✅ Yayınlandı: media_id={res['id']}")
        except Exception as exc:
            log.warning(f"  Otomatik yayın hata verdi: {exc} — kart hazır, elle yayınlanabilir")

    log.info("=== Haber otomasyonu bitti ===")
    return {"ok": True, "file": out_path.name, "copied": copied,
            "news_title": news["title"], "news_link": news["link"],
            "published_media_id": published_media_id}


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
    ap.add_argument("--config", default=None, help="config.yaml yolu")
    args = ap.parse_args(argv)
    cfg = load_config(args.config)
    try:
        res = run_once(cfg, dry_run=args.dry_run)
    except Exception as exc:
        log.error(f"HATA: {exc}")
        return 1
    return 0 if res.get("ok") else 2


if __name__ == "__main__":
    sys.exit(main())
