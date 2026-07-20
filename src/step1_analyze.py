from __future__ import annotations

import argparse
import csv
import random
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from tqdm import tqdm

from src import labeling
from src.config import Config, load_config, require_video_source
from src.ollama_client import OllamaClient
from src.utils.ffprobe import VideoInfo, extract_first_frame, probe
from src.utils.logging import get_logger

log = get_logger("step1")

VIDEO_EXT = {".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm"}

VISION_PROMPT = (
    "Classify this Japan travel video frame with a SHORT English label (2-3 words). "
    "Reply ONLY the label. Examples: 'Temple Shrine', 'Neon Street', 'Aerial City', "
    "'Food Market', 'Theme Park Ride', 'Train Station', 'Park Garden', 'Castle Tower'. "
    "Label:"
)

CSV_FIELDS = [
    "dosya_adi", "mekan_etiketi", "kategori", "sehir", "cekim_tipi",
    "cekim_tarihi", "kaynak", "sure_sn", "genislik", "yukseklik", "fps",
]


def scan_videos(source: Path) -> list[Path]:
    """Basename bazında tekilleştir (aynı dosya hem kökte hem alt klasörde olabiliyor)."""
    seen: dict[str, Path] = {}
    for p in sorted(source.rglob("*")):
        if p.is_file() and p.suffix.lower() in VIDEO_EXT:
            key = p.name.lower()
            if key not in seen:
                seen[key] = p
    return list(seen.values())


def load_seen(csv_path: Path) -> set[str]:
    if not csv_path.exists():
        return set()
    seen: set[str] = set()
    with csv_path.open("r", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            seen.add(row["dosya_adi"])
    return seen


def append_row(csv_path: Path, row: dict[str, object]) -> None:
    is_new = not csv_path.exists()
    with csv_path.open("a", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=CSV_FIELDS)
        if is_new:
            writer.writeheader()
        writer.writerow(row)


def _subdir(video: Path, source: Path) -> str:
    try:
        return str(video.parent.relative_to(source))
    except ValueError:
        return video.parent.name


def analyze_one(video: Path, source: Path, cfg: Config, client: OllamaClient) -> dict[str, object] | None:
    try:
        info: VideoInfo = probe(video)
    except Exception as exc:
        log.error(f"ffprobe hata ({video.name}): {exc}")
        return None

    # 1) Önce dosya adı + klasör + tarihten akıllı etiket
    et = labeling.parse_filename(video.name, _subdir(video, source))

    # 2) Belirsizse (çoğunlukla ham DJI değil, isimsiz klip) vision devreye girer
    if et is None:
        frame_path = cfg.paths.frames_dir / f"{video.stem}.jpg"
        seek = min(1.0, max(0.2, info.duration_sn * 0.1))
        try:
            extract_first_frame(video, frame_path, at_sn=seek)
            raw_label = client.generate_vision(cfg.ollama.vision_model, VISION_PROMPT, frame_path)
            et = labeling.etiket_from_vision(raw_label)
        except Exception as exc:
            log.warning(f"vision fallback hata ({video.name}): {exc}")
            et = labeling.Etiket("Genel", "Genel", "", kaynak="vision", guven=0.1)
    else:
        # thumbnail yine de üret (panelde önizleme için)
        frame_path = cfg.paths.frames_dir / f"{video.stem}.jpg"
        if not frame_path.exists():
            try:
                extract_first_frame(video, frame_path, at_sn=min(1.0, max(0.2, info.duration_sn * 0.1)))
            except Exception:
                pass

    return {
        "dosya_adi": video.name,
        "mekan_etiketi": et.mekan_etiketi,
        "kategori": et.kategori,
        "sehir": et.sehir,
        "cekim_tipi": et.cekim_tipi,
        "cekim_tarihi": labeling.cekim_tarihi(video.name),
        "kaynak": et.kaynak,
        "sure_sn": info.duration_sn,
        "genislik": info.width,
        "yukseklik": info.height,
        "fps": info.fps,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=None)
    parser.add_argument("--pilot", action="store_true", help="Sadece pilot_count kadar örnek işle")
    parser.add_argument("--max", type=int, default=None, help="Bu çalıştırmada işlenecek maksimum video (config'i geçersiz kılar)")
    args = parser.parse_args()

    cfg = load_config(args.config)
    source = require_video_source(cfg)
    client = OllamaClient(cfg.ollama.base_url, cfg.ollama.request_timeout_sn)

    if not client.health():
        log.warning("Ollama erişilemiyor — isimsiz klipler için vision atlanacak (dosya-adı etiketleri yine çalışır).")

    videos = scan_videos(source)
    log.info(f"Benzersiz video sayısı: {len(videos)}")
    if not videos:
        log.error(f"Kaynak boş: {source}")
        sys.exit(1)

    seen = load_seen(cfg.paths.metadata_csv)
    todo = [v for v in videos if v.name not in seen]
    log.info(f"CSV'de olan: {len(seen)}, işlenecek aday: {len(todo)}")

    if args.pilot or cfg.pilot.pilot_mode:
        random.seed(cfg.pilot.random_seed)
        random.shuffle(todo)
        todo = todo[: cfg.pilot.pilot_count]
        log.info(f"Pilot mode: {len(todo)} video seçildi")

    cap = args.max if args.max is not None else cfg.run.max_videos_per_run
    cap = max(1, cap)
    if len(todo) > cap:
        todo = todo[:cap]
        log.info(f"Çalıştırma sınırı: en fazla {cap} video işlenecek")

    if not todo:
        log.info("İşlenecek video yok, çıkılıyor.")
        return

    with ThreadPoolExecutor(max_workers=cfg.ollama.vision_concurrency) as pool:
        futures = {pool.submit(analyze_one, v, source, cfg, client): v for v in todo}
        with tqdm(total=len(futures), desc="Analiz") as bar:
            for fut in as_completed(futures):
                row = fut.result()
                if row is not None:
                    append_row(cfg.paths.metadata_csv, row)
                    log.info(f"✓ {row['dosya_adi']} → {row['mekan_etiketi']} [{row['kaynak']}]")
                bar.update(1)

    log.info(f"Bitti. CSV: {cfg.paths.metadata_csv}")


if __name__ == "__main__":
    main()
