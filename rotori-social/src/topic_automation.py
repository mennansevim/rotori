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


def _pick_topic(pool: list[dict[str, Any]], used: set[str],
                state: dict[str, Any] | None = None,
                cooldown_days: int = 45) -> dict[str, Any] | None:
    """Havuzdan konu seç. Havuz tükendiyse SIFIRLAMAZ — cooldown'ı dolan en eski
    konuya döner. Eskiden burada havuz sıfırlanıyordu ve aynı konu üst üste
    üretilebiliyordu (bkz. news_automation.eligible_topics)."""
    from src.news_automation import eligible_topics

    ordered, note = eligible_topics(pool, used, state or {}, cooldown_days)
    if not ordered:
        log.warning(f"  Konu seçilemedi: {note}. "
                    f"Yeni konu eklemek için {_POOL_PATH}.")
        return None
    log.info(f"  konu havuzu: {note}")
    return ordered[0]


# NOT: Kart üst metni + caption üretimi artık src/editorial.py'daki PAYLAŞIMLI
# 'Japonya Rüyası araştırma editörü' system prompt'una taşındı
# (generate_editorial_topic). Eski _TR_STYLE / _card_prompt / _caption_prompt
# kaldırıldı; 'Konudan Üret' butonu ve otomasyon aynı kalıbı/kalite kapısını kullanır.


def run_once(cfg: Config, auto_publish: bool = False,
             dry_run: bool = False,
             topic_override: dict[str, Any] | None = None) -> dict[str, Any]:
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
    cooldown = int(getattr(cfg.news, "topic_cooldown_days", 45)) if cfg.news else 45
    # Kullanıcı özel konu verdiyse onu kullan (dedup atlanır), yoksa havuzdan seç
    if topic_override and topic_override.get("title"):
        topic = {
            "title": str(topic_override["title"]).strip(),
            "query": str(topic_override.get("query") or topic_override["title"]).strip(),
        }
        log.info(f"  ÖZEL konu (kullanıcı): {topic['title']}")
    else:
        topic = _pick_topic(pool, used, state, cooldown)
    if topic is None:
        return {"ok": False, "reason": "no_topic",
                "detail": f"Havuzdaki tüm konular kullanıldı ve {cooldown} günlük "
                          f"bekleme süresi dolmadı. {_POOL_PATH}'a yeni konu ekleyin."}
    log.info(f"  seçilen konu: {topic['title']}  | görsel: {topic['query']}")

    # metin + caption — PAYLAŞIMLI 'Japonya Rüyası' editöryel prompt (konu modu).
    # 'Konudan Üret' butonu ve konu otomasyonu aynı kaliteyi/kalıbı kullanır.
    from src import editorial
    res = editorial.generate_editorial_topic(oai, topic["title"])
    if not res.get("uygun"):
        log.info(f"  ⏭ Konu kalite kapısını geçemedi "
                 f"(toplam={res.get('toplam', 0)}/50, min={editorial.MIN_SCORE}).")
        return {"ok": False, "reason": "low_score", "topic": topic,
                "toplam": res.get("toplam", 0)}
    aciklama = res["kart_ust_metni"]
    caption = res["caption"]
    editorial_data = res.get("data", {})
    log.info(f"  ✓ Editöryel içerik (puan={res.get('toplam')}/50, "
             f"kategori={editorial_data.get('kategori', '?')})")
    # Görsel konsepti üretildiyse görsel sorgusunu ONUNLA değiştir — metin ve
    # görsel aynı editöryel kaynaktan gelir → uyum sağlamlaşır.
    gorsel = (res.get("gorsel_konsepti") or "").strip()
    if gorsel:
        log.info(f"  🎯 görsel konsepti: '{gorsel}'")
        topic["query"] = gorsel

    log.info(f"  kart metni: {aciklama}")
    if dry_run:
        log.info("  [DRY-RUN] dosya yazılmadı.")
        return {"ok": True, "dry_run": True, "topic": topic, "aciklama": aciklama}

    # görsel (news_automation'daki _pick_image ile aynı akış)
    from src.news_automation import _pick_image
    bg = _pick_image(cfg, oai, topic["query"], topic["title"], used_bg)
    if bg is None:
        # Toplu üretimi çökertmemek için exception değil, atlanabilir sonuç.
        log.warning("  Uygun görsel bulunamadı (Unsplash boş veya limit aşıldı).")
        return {"ok": False, "reason": "no_image", "topic": topic,
                "detail": "Unsplash görsel döndürmedi (sorgu boş sonuç verdi "
                          "veya saatlik istek limiti aşıldı)."}

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
            "baslik": topic.get("title", ""),
            "bg_local": f"unsplash-{slug_q}-{bg['id']}.jpg",
            "photographer": bg.get("photographer", ""),
            "aciklama": aciklama, "ust_tag": "GEZİ DEFTERİ", "style": "style2",
            "post_caption": caption,
            "kategori": editorial_data.get("kategori", ""),
            "puan": editorial_data.get("puan", {}),
            "toplam_puan": editorial_data.get("toplam"),
            "kaynak": editorial_data.get("kaynak", ""),
            "source_topic": topic["title"],
            "auto_generated": True,
        }, ensure_ascii=False, indent=2), encoding="utf-8")
    except OSError as exc:
        log.warning(f"  sidecar yazılamadı: {exc}")

    # state güncelle — sıra korunur; dedup anahtarları news_automation ile ortak
    from src.news_automation import _ordered_used, _remember
    previous_used = list(state.get("used_ids", []))
    _remember(used, topic)
    state["used_ids"] = _ordered_used(previous_used, used)
    previous_bg = list(state.get("used_bg_ids", []))
    used_bg.add(bg["id"])
    state["used_bg_ids"] = _ordered_used(previous_bg, used_bg)
    state["last_run"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    state.setdefault("history", []).append({
        "at": state["last_run"], "topic": topic["title"], "file": out_path.name,
    })
    state["history"] = state["history"][-100:]
    _save_state(cfg, state)

    log.info(f"✓ Kart üretildi: {out_path.name}")

    # Onay Bekleyen'e taşı — yayına ALMAZ, kullanıcı widget'ta inceleyip
    # onaylayana kadar bekletir.
    pending_notified = False
    if auto_publish:
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
            # sidecar'a source ekle (widget'ta konu = pembe rozet)
            meta_p = new_path.with_suffix(".json")
            if meta_p.exists():
                try:
                    meta = json.loads(meta_p.read_text(encoding="utf-8"))
                    meta["source"] = "konu"
                    meta_p.write_text(json.dumps(meta, ensure_ascii=False, indent=2),
                                       encoding="utf-8")
                except (OSError, ValueError):
                    pass
            try:
                from src.mac_notifier import notify
                notify(
                    title="Onay Bekliyor — Konu",
                    subtitle="@japonyaruyasi",
                    message=topic["title"][:80],
                )
                pending_notified = True
            except Exception as exc:
                log.warning(f"  Notification atlandı: {exc}")
            out_path = new_path
        except OSError as exc:
            log.warning(f"  pending'e taşıma hatası: {exc}")

    log.info("=== Konu otomasyonu bitti ===")
    return {"ok": True, "file": out_path.name, "topic": topic["title"],
            "pending": pending_notified}


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
