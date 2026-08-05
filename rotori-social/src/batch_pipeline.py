"""Arşivi Reels havuzuna çevirir — batch mod.

metadata.csv'deki her videoyu:
  1) 9:16 crop + trim (config.reels.max_duration_sn'e kadar)
  2) output/reels/<slug>.mp4 olarak yaz — VIDEO ÜZERİNE YAZI YOK (temiz)
  3) GPT ile o videoya özel Türkçe description + hashtagler üret
  4) yan yana .txt olarak kaydet (kullanıcı Instagram'da yapıştıracak)

Idempotent: hedef mp4 zaten varsa atlar.
İptal edilebilir: JobManager.start_callable içinden cancel event ile.
Log akışı: emit(text, kind) → web dashboard Canlı Süreç panelinde.
"""
from __future__ import annotations

import csv
import json
import re
import time
from pathlib import Path
from threading import Event
from typing import Any, Callable

from src.config import Config, require_video_source
from src.utils.logging import get_logger

log = get_logger("batch")


def _slug(text: str) -> str:
    tr = {"ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u"}
    for a, b in tr.items():
        text = text.replace(a, b).replace(a.upper(), b.upper())
    s = re.sub(r"[^A-Za-z0-9]+", "_", text).strip("_").lower()
    return s or "reel"


def _read_metadata(csv_path: Path) -> list[dict[str, Any]]:
    if not csv_path.exists():
        return []
    with csv_path.open("r", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def _target_name(cfg: Config, row: dict[str, Any]) -> str:
    """Video için hedef mp4 adı — mekan slug + orijinal isim stem."""
    mekan = row.get("mekan_etiketi", "genel") or "genel"
    stem = Path(row.get("dosya_adi", "reel")).stem
    return f"{_slug(mekan)}_{_slug(stem)}"


def run_batch(cfg: Config, emit: Callable[..., None], cancel: Event,
              limit: int | None = None, overwrite: bool = False) -> None:
    """Arşivi süpür → her videoyu Reels havuzuna çevir.

    - limit: opsiyonel, sadece ilk N video (test için).
    - overwrite: False (default) mevcut hedef mp4 varsa atlar; True yeniden yazar.
    """
    # ağır bağımlılıklar tembel yükle
    from src import step3_dify as step3
    from src import step4_render as step4
    from src.utils.ffprobe import probe

    if not cfg.paths.metadata_csv.exists():
        emit("✖ metadata.csv yok. Önce videoları analiz et.", "error")
        return

    try:
        source = require_video_source(cfg)
    except SystemExit as exc:
        emit(str(exc), "error")
        return

    rows = _read_metadata(cfg.paths.metadata_csv)
    if not rows:
        emit("✖ metadata.csv boş.", "error")
        return

    if limit is not None:
        rows = rows[:limit]

    emit(f"① Arşiv taranıyor: {len(rows)} video işlenecek", "info")
    emit(f"   Video mod: TEMİZ (add_overlays={cfg.reels.add_overlays})", "log")
    emit(f"   Hedef klasör: {cfg.paths.output_dir}", "log")

    # kaynak dosya index'i
    name_index: dict[str, Path] = {}
    for p in source.rglob("*"):
        if p.is_file() and p.suffix.lower() in {".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm"}:
            name_index[p.name] = p

    ok, skip, fail = 0, 0, 0
    for i, row in enumerate(rows, 1):
        if cancel.is_set():
            emit("⏹ İptal edildi.", "warn")
            break

        dosya = row.get("dosya_adi", "")
        mekan = row.get("mekan_etiketi", "")
        emit(f"── [{i}/{len(rows)}] {dosya} ({mekan}) ──", "info")

        src_path = name_index.get(dosya)
        if src_path is None:
            emit(f"  ✗ kaynak dosya bulunamadı", "warn")
            fail += 1
            continue

        base = _target_name(cfg, row)
        target_mp4 = cfg.paths.output_dir / f"{base}.mp4"
        target_txt = cfg.paths.output_dir / f"{base}.txt"

        if target_mp4.exists() and not overwrite:
            emit(f"  ⤵ zaten var, atlanıyor: {base}.mp4", "log")
            skip += 1
            continue

        # 1) GPT ile caption üret (temiz mod)
        emit(f"  ① GPT caption üretiliyor…", "log")
        try:
            cap = step3.generate_caption_only(cfg, row)
        except Exception as exc:
            emit(f"  ✗ caption başarısız: {exc}", "error")
            fail += 1
            continue

        # 2) final_json yaz (step4 bunu okuyor)
        try:
            dur = float(row.get("sure_sn", 0) or 0)
        except (TypeError, ValueError):
            dur = float(cfg.reels.max_duration_sn)
        target_sn = min(float(cfg.reels.max_duration_sn), max(1.0, dur))

        final_data = {
            "mekan_etiketi": mekan,
            "kategori": row.get("kategori", ""),
            "sehir": row.get("sehir", ""),
            "toplam_sure_sn": target_sn,
            "video_dosyalari": [dosya],
            "kurgu_json": {
                "hook": "",              # temiz mod: video üzerinde metin yok
                "overlays": [],
                "cta": "",
                "aciklama": cap["aciklama"],
                "hashtagler": cap["hashtagler"],
            },
        }
        # step4 final_json'u <base>_final.json olarak bekliyor
        final_json = cfg.paths.plans_dir / f"{base}_final.json"
        final_json.write_text(json.dumps(final_data, ensure_ascii=False, indent=2),
                              encoding="utf-8")

        # 3) render — step4.render_reel çağır (overlay=False cfg'den okur)
        emit(f"  ② Video kesim + render (9:16, {target_sn:.1f}s)…", "log")
        try:
            # step4 output ismini final_json.name'den türetiyor → base ile aynı
            out = step4.render_reel(final_json, cfg, source, name_index)
        except Exception as exc:
            emit(f"  ✗ render hatası: {exc}", "error")
            fail += 1
            continue

        if out is None:
            emit(f"  ✗ render başarısız (klip yüklenemedi)", "error")
            fail += 1
            continue

        emit(f"  ✓ {out.name} — Onay bekleyende", "info")
        ok += 1

    if not cancel.is_set():
        emit(f"② Bitti — başarılı: {ok} · atlandı: {skip} · hatalı: {fail}", "info")
