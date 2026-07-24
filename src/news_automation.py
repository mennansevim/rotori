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
        'İngilizce görsel arama; Japonya bağlamı>", "reason": "<kısa>"}\n'
        "Turist adayına hitap eden hiçbir haber yoksa: {\"index\": -1}\n"
        "unsplash_query örnek: 'cherry blossom kyoto', 'autumn leaves temple', "
        "'tokyo street food', 'mount fuji snow', 'traditional ryokan onsen'."
    )


def _text_prompt(news: dict[str, Any]) -> str:
    return (
        "Aşağıdaki Japonya haberinden bir Instagram bilgi kartının ANA METNİNİ "
        "üret.\n\n"
        f"BAŞLIK: {news['title']}\n"
        f"ÖZET: {news['summary']}\n\n"
        f"{_TR_STYLE}\n\n"
        "BİÇİM: EN FAZLA 2 cümle, toplam max 28 kelime. Haberin özünü (ne oldu, "
        "neden önemli) belgesel tonda aktar. Emoji YOK. Sadece metni yaz — "
        "başlık/tırnak/prefix EKLEME."
    )


_CAPTION_SYSTEM = (
    "Sen @japonyaruyasi için belgesel tonda Instagram post caption'ı yazan bir "
    "editörsün. Kusursuz Türkçe, klişesiz, bilgilendirici. Uydurma YOK."
)


def _caption_prompt(news: dict[str, Any], aciklama: str) -> str:
    return (
        f"Haber: {news['title']}\nÖzet: {news['summary']}\n"
        f"Kart metni: {aciklama}\n\n"
        "Bunu Instagram post caption'ına genişlet. Format:\n"
        "1. Açılış (1 cümle, 1-2 emoji) — haberi tanıtan objektif fact.\n"
        "2. 3-4 madde (her satır emoji + 1 kısa somut bilgi cümlesi).\n"
        "3. Kısa CTA (örn 'Kaydet 📌').\n"
        "4. Boş satır + 8-12 hashtag (Türkçe/İngilizce karışık).\n"
        "Klişe/emir/2. şahıs YASAK. 400-1200 karakter. Sadece caption — "
        "markdown başlığı/prefix YOK."
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
        "Sen @japonyaruyasi için ansiklopedik/belgesel Türkçe hap bilgi metinleri "
        "üreten bir editörsün. Yanıt SADECE metin.",
        _text_prompt(news), temperature=0.6, max_tokens=120,
    ).strip().strip('"').strip("'").strip()
    caption = ""
    try:
        caption = oai.chat_text(_CAPTION_SYSTEM, _caption_prompt(news, aciklama),
                                temperature=0.8, max_tokens=700).strip()
    except (RuntimeError, ValueError) as exc:
        log.warning(f"  caption üretilemedi: {exc}")
    return aciklama, caption


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

    # görsel
    if cfg.stories is None:
        raise RuntimeError("stories config yok — kart render edilemez.")
    from src import downloader, story_generator
    try:
        results = downloader.search_only(cfg, news["unsplash_query"], count=10)
    except Exception as exc:
        log.warning(f"  Unsplash arama hatası: {exc} — 'japan' fallback")
        results = []
    if not results:
        try:
            results = downloader.search_only(cfg, "japan", count=10)
        except Exception as exc:
            raise RuntimeError(f"Unsplash görsel bulunamadı: {exc}") from exc
    if not results:
        raise RuntimeError("Unsplash hiç görsel döndürmedi.")
    bg = results[0]

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

    # state güncelle
    used.add(_news_id(news))
    state["used_ids"] = list(used)[-_USED_CAP:]
    state["last_run"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    state.setdefault("history", []).append({
        "at": state["last_run"], "title": news["title"], "link": news["link"],
        "file": out_path.name, "drive": bool(copied),
    })
    state["history"] = state["history"][-100:]
    _save_state(cfg, state)

    log.info(f"✓ Kart üretildi: {out_path.name} | Drive: {copied or 'kopyalanmadı'}")
    log.info("=== Haber otomasyonu bitti ===")
    return {"ok": True, "file": out_path.name, "copied": copied,
            "news_title": news["title"], "news_link": news["link"]}


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
