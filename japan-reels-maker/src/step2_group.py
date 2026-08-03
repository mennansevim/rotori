from __future__ import annotations

import argparse
import csv
import json
import re
from collections import defaultdict
from pathlib import Path
from typing import Any

from src import labeling
from src.config import Config, load_config
from src.utils.logging import get_logger

log = get_logger("step2")

# Kategoriye göre anlatım tonu (çeşitlilik için)
_TIP_MAP = {
    "Nara": "merak_uyandir",
    "Fushimi Inari": "merak_uyandir",
    "Tapınak": "merak_uyandir",
    "teamLab": "merak_uyandir",
    "Havadan": "bolgeyi_tanit",
    "Osaka Kalesi": "bolgeyi_tanit",
    "Tokyo Tower": "bolgeyi_tanit",
    "Skytree": "bolgeyi_tanit",
    "Shibuya": "bolgeyi_tanit",
    "Dotonbori": "bolgeyi_tanit",
    "Umeda": "bolgeyi_tanit",
}


def _aciklama_tipi(kategori: str, default: str) -> str:
    return _TIP_MAP.get(kategori, default if default else "aciklayici")


def read_metadata(csv_path: Path) -> list[dict[str, Any]]:
    if not csv_path.exists():
        raise SystemExit(f"metadata.csv bulunamadı: {csv_path}. Önce step1_analyze çalıştırın.")
    with csv_path.open("r", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def _usable(dur: float, cap: float) -> float:
    """Bir klibin reel'e katacağı kullanılabilir saniye (çok uzunları kırpar)."""
    return min(max(dur, 0.0), cap)


def build_groups(rows: list[dict[str, Any]], cfg: Config) -> list[dict[str, Any]]:
    per_reel = cfg.reels.clip_per_reel
    target = cfg.reels.max_duration_sn
    min_fill = cfg.reels.min_duration_sn
    per_clip_cap = max(6.0, target / 2)  # tek klip ekranı fazla kaplamasın

    buckets: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for r in rows:
        buckets[r.get("mekan_etiketi", "Genel")].append(r)

    groups: list[dict[str, Any]] = []
    for mekan, items in sorted(buckets.items()):
        if len(items) < 2:
            log.info(f"Atlanıyor '{mekan}' — sadece {len(items)} klip")
            continue

        # intro başa, geçiş/yavaş sona; eşitlikte uzun klip öne
        items.sort(key=lambda r: (labeling.tip_sira(r.get("cekim_tipi", "normal")),
                                  -float(r.get("sure_sn", 0) or 0)))

        idx = 0
        i = 0
        n = len(items)
        while i < n:
            chunk: list[dict[str, Any]] = []
            acc = 0.0
            while i < n and len(chunk) < per_reel:
                r = items[i]
                chunk.append(r)
                acc += _usable(float(r.get("sure_sn", 0) or 0), per_clip_cap)
                i += 1
                if acc >= min_fill and len(chunk) >= 2:
                    break
            if len(chunk) < 2:
                # kalan tek klip: mümkünse öncekine ekle, değilse at
                if groups and groups[-1]["mekan_etiketi"] == mekan and len(groups[-1]["video_dosyalari"]) < per_reel:
                    groups[-1]["video_dosyalari"].append(chunk[0]["dosya_adi"])
                    groups[-1]["klip_sureleri"].append(float(chunk[0].get("sure_sn", 0) or 0))
                    groups[-1]["cekim_tipleri"].append(chunk[0].get("cekim_tipi", "normal"))
                break

            kategori = chunk[0].get("kategori", "")
            sehir = chunk[0].get("sehir", "")
            groups.append({
                "mekan_etiketi": mekan,
                "kategori": kategori,
                "sehir": sehir,
                "idx": idx,
                "aciklama_tipi": _aciklama_tipi(kategori, cfg.dify.aciklama_tipi),
                "toplam_sure_sn": target,
                "hedef_klip_sayisi": len(chunk),
                "video_dosyalari": [c["dosya_adi"] for c in chunk],
                "klip_sureleri": [float(c.get("sure_sn", 0) or 0) for c in chunk],
                "cekim_tipleri": [c.get("cekim_tipi", "normal") for c in chunk],
            })
            idx += 1
    return groups


def slug(text: str) -> str:
    tr = {"ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u"}
    for a, b in tr.items():
        text = text.replace(a, b).replace(a.upper(), b)
    s = re.sub(r"[^A-Za-z0-9]+", "_", text).strip("_").lower()
    return s or "grup"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=None)
    args = parser.parse_args()

    cfg = load_config(args.config)
    rows = read_metadata(cfg.paths.metadata_csv)
    log.info(f"Toplam metadata satırı: {len(rows)}")

    groups = build_groups(rows, cfg)
    log.info(f"Oluşturulan grup (reel adayı): {len(groups)}")

    for g in groups:
        fname = f"{slug(g['mekan_etiketi'])}_{g['idx']:02d}_input.json"
        (cfg.paths.plans_dir / fname).write_text(
            json.dumps(g, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        log.info(f"  {fname}: {len(g['video_dosyalari'])} klip · {g['aciklama_tipi']}")
    log.info(f"Grup input JSON'lar: {cfg.paths.plans_dir}")


if __name__ == "__main__":
    main()
