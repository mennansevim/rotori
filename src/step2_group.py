from __future__ import annotations

import argparse
import csv
import json
import random
import re
from collections import defaultdict
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any

from src.config import Config, load_config
from src.utils.logging import get_logger

log = get_logger("step2")


def _normalize(label: str) -> str:
    text = label.lower().strip()
    text = re.sub(r"[^\w\s]", "", text, flags=re.UNICODE)
    return re.sub(r"\s+", " ", text)


def canonicalize(labels: list[str], threshold: float = 0.8) -> dict[str, str]:
    canonical: list[str] = []
    mapping: dict[str, str] = {}
    for lbl in labels:
        norm = _normalize(lbl)
        matched: str | None = None
        for c in canonical:
            if SequenceMatcher(None, norm, _normalize(c)).ratio() >= threshold:
                matched = c
                break
        if matched is None:
            canonical.append(lbl)
            mapping[lbl] = lbl
        else:
            mapping[lbl] = matched
    return mapping


def read_metadata(csv_path: Path) -> list[dict[str, Any]]:
    if not csv_path.exists():
        raise SystemExit(f"metadata.csv bulunamadı: {csv_path}. Önce step1_analyze çalıştırın.")
    with csv_path.open("r", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def build_groups(rows: list[dict[str, Any]], cfg: Config) -> list[dict[str, Any]]:
    unique_labels = sorted({r["mekan_etiketi"] for r in rows})
    canon_map = canonicalize(unique_labels)
    log.info(f"Etiket normalizasyonu: {len(unique_labels)} → {len(set(canon_map.values()))}")

    buckets: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for r in rows:
        buckets[canon_map[r["mekan_etiketi"]]].append(r)

    rng = random.Random(cfg.pilot.random_seed)
    per_reel = cfg.reels.clip_per_reel
    groups: list[dict[str, Any]] = []
    for canon_label, items in buckets.items():
        if len(items) < 2:
            log.info(f"Atlanıyor '{canon_label}' — sadece {len(items)} klip")
            continue
        rng.shuffle(items)
        idx = 0
        for start in range(0, len(items), per_reel):
            chunk = items[start:start + per_reel]
            if len(chunk) < 2:
                break
            groups.append({
                "mekan_etiketi": canon_label,
                "idx": idx,
                "toplam_sure_sn": cfg.reels.max_duration_sn,
                "hedef_klip_sayisi": len(chunk),
                "video_dosyalari": [c["dosya_adi"] for c in chunk],
                "klip_sureleri": [float(c["sure_sn"]) for c in chunk],
            })
            idx += 1
    return groups


def slug(text: str) -> str:
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
    log.info(f"Oluşturulan grup (reel adayı) sayısı: {len(groups)}")

    for g in groups:
        fname = f"{slug(g['mekan_etiketi'])}_{g['idx']:02d}_input.json"
        (cfg.paths.plans_dir / fname).write_text(
            json.dumps(g, ensure_ascii=False, indent=2), encoding="utf-8"
        )
    log.info(f"Grup input JSON'lar: {cfg.paths.plans_dir}")


if __name__ == "__main__":
    main()
