#!/usr/bin/env python3
"""metadata.csv'de dosya-adı kuralı yakalayamamış (fallback vision veya tarih
kaynaklı, ya da "Genel" kategorili) videoları listeler — kullanıcının bunları
[docs/isimlendirme_rehberi.md]'deki formata uygun şekilde manuel yeniden
adlandırmasına yardım eder.

Kullanım:
    .venv/bin/python scripts/list_videos_for_rename.py [--limit N] [--show-path] [--all]
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

# repo root'u path'e ekle (script bağımsız çalışabilsin)
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from src.config import load_config  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=100)
    parser.add_argument("--show-path", action="store_true",
                        help="Sadece isim değil, tam dosya yolunu da yaz.")
    parser.add_argument("--all", action="store_true",
                        help="Sadece 'yeniden adlandırılabilir' değil, tüm satırları göster.")
    args = parser.parse_args()

    cfg = load_config()
    if not cfg.paths.metadata_csv.exists():
        print(f"metadata.csv yok: {cfg.paths.metadata_csv}")
        return

    # kaynak videolar için isim → path index
    path_index: dict[str, Path] = {}
    src = cfg.paths.video_source_dir
    if src.exists():
        for p in src.rglob("*"):
            if p.is_file():
                path_index.setdefault(p.name, p)

    with cfg.paths.metadata_csv.open("r", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))

    fallback = [
        r for r in rows
        if args.all
        or r.get("kaynak") in ("vision", "tarih")
        or r.get("mekan_etiketi") in ("Genel", "")
        or r.get("mekan_etiketi", "").endswith("Havadan")
    ]

    if not fallback:
        print("Tüm satırlar zaten dosya-adı kuralı ile etiketlenmiş. 🎉")
        return

    print(f"# Yeniden adlandırılabilir {len(fallback)} video "
          f"({len(rows)} toplam):\n")
    print(f"{'# dosya adı':60s}  {'şu anki etiket':30s}  {'kaynak':8s}")
    print("-" * 105)

    for r in fallback[: args.limit]:
        name = r.get("dosya_adi", "")
        mekan = r.get("mekan_etiketi", "?")
        kaynak = r.get("kaynak", "?")
        if args.show_path:
            p = path_index.get(name)
            path_display = str(p) if p else f"[bulunamadı] {name}"
            print(f"{path_display:60s}  {mekan:30s}  {kaynak:8s}")
        else:
            print(f"{name:60s}  {mekan:30s}  {kaynak:8s}")

    if len(fallback) > args.limit:
        print(f"\n# {len(fallback) - args.limit} tane daha var")
    print("\n# Yeniden adlandırma sonrası çalıştır:")
    print("#   .venv/bin/python -m src.step1_analyze --relabel-only")


if __name__ == "__main__":
    main()
