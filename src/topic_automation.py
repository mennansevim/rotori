"""Konu havuzundan rastgele Japonya kartı üretici (görsel akışının otomatik hali).

Akış (run_once):
  1) assets/topic_pool.json'dan random konu seç (dedup state)
  2) Unsplash query → görsel indir
  3) GPT: konuya belgesel Türkçe kart metni + Instagram caption
  4) render_from_url → JPG + .txt + .json sidecar
  5) Opsiyonel: Instagram Graph API ile direkt yayına at

Kullanım:
    python -m src.topic_automation           # 1 tur (Drive'a atmaz)
    python -m src.topic_automation --publish # üret + Instagram'a yayınla
"""
from __future__ import annotations

import argparse
import hashlib
import json
import random
import shutil
import sys
import time
from pathlib import Path
from typing import Any

from src.config import Config, load_config
from src.utils.logging import get_logger

log = get_logger("topic")

_STATE_SUBDIR = "data/topic_automation"
_POOL_PATH = "assets/topic_pool.json"
_USED_CAP = 200


def _topic_id(topic: dict[str, Any]) -> str:
    return hashlib.sha1((topic.get("title") or "").encode("utf-8")).hexdigest()[:16]


def _state_path(cfg: Config) -> Path:
    return cfg.project_root / _STATE_SUBDIR / "state.json"


def _load_state(cfg: Config) -> dict[str, Any]:
    p = _state_path(cfg)
    if p.exists():
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            pass
    return {"used_ids": [], "used_bg_ids": [], "last_run": None, "history": []}


def _save_state(cfg: Config, state: dict[str, Any]) -> None:
    p = _state_path(cfg)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(p)


def _load_pool(cfg: Config) -> list[dict[str, Any]]:
    p = cfg.project_root / _POOL_PATH
    if not p.exists():
        return []
    try:
        return json.loads(p.read_text(encoding="utf-8")).get("topics", [])
    except (OSError, ValueError):
        return []


def _pick_topic(pool: list[dict[str, Any]], used: set[str]) -> dict[str, Any] | None:
    fresh = [t for t in pool if _topic_id(t) not in used]
    if not fresh:
        # havuz tükendi → sıfırla, tekrar başla
        log.info("  Havuz tükendi, sıfırlanıp başa dönülüyor.")
        fresh = pool
    if not fresh:
        return None
    return random.choice(fresh)


# ---- GPT metin (news_automation'ın belgesel Türkçe stilini kullanır) ----
_TR_STYLE = (
    "Türkçen kusursuz, akıcı ve ansiklopedik/belgesel olmalı. 3. şahıs, genel "
    "bilgi kipi ('…dır', '…olarak biliniyor'). Klişe/pazarlama dili YASAK "
    "('büyüleyici', 'eşsiz', 'muhteşem'). Emir/2. şahıs hitap YASAK. Uydurma "
    "spesifik sayı/tarih YASAK — genel bilgi ver."
)


def _card_prompt(konu: str) -> str:
    return (
        f"KONU: {konu}\n\n"
        "Bu konu hakkında bir Instagram kartı için KISA merak uyandıran spot yaz.\n\n"
        f"{_TR_STYLE}\n\n"
        "BİÇİM: TEK cümle, ~10-14 kelime. Konuyu tanıt, merak uyandır (detay "
        "caption'a bırakılır). Emoji YOK. Sadece metni yaz."
    )


def _caption_prompt(konu: str, aciklama: str) -> str:
    return (
        f"KONU: {konu}\n"
        f"Kartın üst spotu: {aciklama}\n\n"
        "Bunu detaylı bir Instagram post caption'ına genişlet. Gazeteci netliğinde:\n"
        "1. Açılış (1-2 cümle, 1-2 emoji): konuyu tanıt.\n"
        "2. 3-4 madde (emoji + kısa somut bilgi).\n"
        "3. Kısa CTA (örn 'Kaydet 📌').\n"
        "4. Boş satır + 8-12 hashtag (TR/EN karışık).\n"
        "Klişe/emir/2. şahıs YASAK. 400-1000 karakter."
    )


def run_once(cfg: Config, auto_publish: bool = False,
             dry_run: bool = False) -> dict[str, Any]:
    if cfg.openai is None:
        raise RuntimeError("OpenAI key gerekli (config.yaml → openai.api_key).")
    if cfg.stories is None:
        raise RuntimeError("stories config yok.")
    from src.openai_client import OpenAIClient
    oai = OpenAIClient.from_config(cfg)
    if oai is None:
        raise RuntimeError("OpenAI client kurulamadı.")

    log.info("=== Konu otomasyonu başladı ===")
    pool = _load_pool(cfg)
    if not pool:
        raise RuntimeError(f"Konu havuzu boş/bulunamadı: {_POOL_PATH}")
    log.info(f"  havuz: {len(pool)} konu")

    state = _load_state(cfg)
    used = set(state.get("used_ids", []))
    used_bg = set(state.get("used_bg_ids", []))
    topic = _pick_topic(pool, used)
    if topic is None:
        return {"ok": False, "reason": "no_topic"}
    log.info(f"  seçilen konu: {topic['title']}  | görsel: {topic['query']}")

    # metin
    aciklama = oai.chat_text(
        "Sen @japonyaruyasi için belgesel tonda kısa haber spotları üreten bir "
        "editörsün. Yanıt SADECE metin.",
        _card_prompt(topic["title"]),
        temperature=0.7, max_tokens=70,
    ).strip().strip('"').strip("'").strip()

    caption = ""
    try:
        caption = oai.chat_text(
            "Sen @japonyaruyasi için detaylı Instagram post caption'ı yazan bir "
            "editörsün. Kusursuz Türkçe.",
            _caption_prompt(topic["title"], aciklama),
            temperature=0.8, max_tokens=700).strip()
    except Exception as exc:
        log.warning(f"  caption üretilemedi: {exc}")

    log.info(f"  kart metni: {aciklama}")
    if dry_run:
        log.info("  [DRY-RUN] dosya yazılmadı.")
        return {"ok": True, "dry_run": True, "topic": topic, "aciklama": aciklama}

    # görsel (news_automation'daki _pick_image ile aynı akış)
    from src.news_automation import _pick_image
    bg = _pick_image(cfg, oai, topic["query"], topic["title"], used_bg)
    if bg is None:
        raise RuntimeError("Uygun görsel bulunamadı.")

    from src import story_generator
    out_path = story_generator.render_from_url(
        cfg, bg_url=bg["download_url"], bg_id=bg["id"],
        bg_query=topic["query"], baslik="", aciklama=aciklama,
        photographer=bg.get("photographer", ""),
    )
    if caption:
        try:
            out_path.with_suffix(".txt").write_text(caption, encoding="utf-8")
        except OSError as exc:
            log.warning(f"  .txt yazılamadı: {exc}")
    # sidecar
    try:
        slug_q = story_generator._slugify(topic["query"])
        out_path.with_suffix(".json").write_text(json.dumps({
            "background_url": bg["download_url"], "background_id": bg["id"],
            "query": topic["query"],
            "bg_local": f"unsplash-{slug_q}-{bg['id']}.jpg",
            "photographer": bg.get("photographer", ""),
            "aciklama": aciklama, "ust_tag": "GEZİ DEFTERİ",
            "post_caption": caption,
            "source_topic": topic["title"],
            "auto_generated": True,
        }, ensure_ascii=False, indent=2), encoding="utf-8")
    except OSError as exc:
        log.warning(f"  sidecar yazılamadı: {exc}")

    # state güncelle
    used.add(_topic_id(topic))
    state["used_ids"] = list(used)[-_USED_CAP:]
    used_bg.add(bg["id"])
    state["used_bg_ids"] = list(used_bg)[-_USED_CAP:]
    state["last_run"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    state.setdefault("history", []).append({
        "at": state["last_run"], "topic": topic["title"], "file": out_path.name,
    })
    state["history"] = state["history"][-100:]
    _save_state(cfg, state)

    log.info(f"✓ Kart üretildi: {out_path.name}")

    # opsiyonel yayın
    published_media_id = None
    if auto_publish and cfg.instagram and cfg.instagram.graph_token:
        try:
            log.info("  📤 Otomatik yayına gönderiliyor…")
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
                rec = {"name": new_path.stem, "media_id": res["id"],
                       "container_id": res["container_id"],
                       "uploaded_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
                       "method": "graph_auto_topic"}
                log_path = cfg.project_root / cfg.instagram.uploads_log
                log_path.parent.mkdir(parents=True, exist_ok=True)
                with log_path.open("a", encoding="utf-8") as f:
                    f.write(json.dumps(rec, ensure_ascii=False) + "\n")
                log.info(f"  ✅ Yayınlandı: media_id={res['id']}")
        except Exception as exc:
            log.warning(f"  Otomatik yayın hata verdi: {exc} — kart hazır, elle yayınlanabilir")

    log.info("=== Konu otomasyonu bitti ===")
    return {"ok": True, "file": out_path.name, "topic": topic["title"],
            "published_media_id": published_media_id}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Konu havuzundan rastgele kart")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--publish", action="store_true", help="Otomatik yayına at")
    ap.add_argument("--config", default=None)
    args = ap.parse_args(argv)
    cfg = load_config(args.config)
    try:
        res = run_once(cfg, auto_publish=args.publish, dry_run=args.dry_run)
    except Exception as exc:
        log.error(f"HATA: {exc}")
        return 1
    return 0 if res.get("ok") else 2


if __name__ == "__main__":
    sys.exit(main())
