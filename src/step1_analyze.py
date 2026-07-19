from __future__ import annotations

import argparse
import csv
import random
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from tqdm import tqdm

from src.config import Config, load_config, require_video_source
from src.ollama_client import OllamaClient
from src.utils.ffprobe import VideoInfo, extract_first_frame, probe
from src.utils.logging import get_logger

log = get_logger("step1")

VIDEO_EXT = {".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm"}

VISION_PROMPT = (
    "Classify this image with a SHORT English label (2-3 words max). "
    "Reply ONLY the label, NO explanation, NO sentences, NO 'this is a...'. "
    "Examples of valid replies: "
    "'Shibuya Crossing', 'Temple Interior', 'Ramen Shop', 'Tokyo Streets', "
    "'Sushi Restaurant', 'Aerial View City', 'Aerial View Mountain', 'Theme Park', "
    "'Train Station', 'Cherry Blossom Park', 'Neon Street', 'Ryokan Room'. "
    "Now reply with only the label:"
)

_STOPWORDS = {"bu", "the", "a", "an", "is", "it", "görselde", "image", "shows", "this", "there"}

CSV_FIELDS = ["dosya_adi", "mekan_etiketi", "sure_sn", "genislik", "yukseklik", "fps"]


def scan_videos(source: Path) -> list[Path]:
    return sorted(
        p for p in source.rglob("*") if p.is_file() and p.suffix.lower() in VIDEO_EXT
    )


def load_seen(csv_path: Path) -> set[str]:
    if not csv_path.exists():
        return set()
    seen: set[str] = set()
    with csv_path.open("r", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            seen.add(row["dosya_adi"])
    return seen


def append_row(csv_path: Path, row: dict[str, object]) -> None:
    is_new = not csv_path.exists()
    with csv_path.open("a", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=CSV_FIELDS)
        if is_new:
            writer.writeheader()
        writer.writerow(row)


def clean_label(raw: str) -> str:
    text = raw.strip().strip('"').strip("'").strip("*").strip("`")
    for sep in ["\n", ".", ",", ":", ";", "(", "—", "-"]:
        if sep in text:
            text = text.split(sep, 1)[0].strip()

    tokens = [t for t in text.split() if t]
    while tokens and tokens[0].lower() in _STOPWORDS:
        tokens.pop(0)

    prefixes = ["image of", "picture of", "photo of", "view of", "a photo", "a picture", "a view"]
    joined = " ".join(tokens).lower()
    for p in prefixes:
        if joined.startswith(p):
            tokens = tokens[len(p.split()):]
            break

    if not tokens:
        return "Unlabeled"
    tokens = tokens[:4]
    cleaned = " ".join(tokens).strip().rstrip(",.;:")
    return cleaned.title() if cleaned else "Unlabeled"


def analyze_one(video: Path, cfg: Config, client: OllamaClient) -> dict[str, object] | None:
    try:
        info: VideoInfo = probe(video)
    except Exception as exc:
        log.error(f"ffprobe hata ({video.name}): {exc}")
        return None

    frame_path = cfg.paths.frames_dir / f"{video.stem}.jpg"
    seek = min(1.0, max(0.2, info.duration_sn * 0.1))
    try:
        extract_first_frame(video, frame_path, at_sn=seek)
    except Exception as exc:
        log.error(f"frame çıkarma hata ({video.name}): {exc}")
        return None

    try:
        raw_label = client.generate_vision(
            model=cfg.ollama.vision_model,
            prompt=VISION_PROMPT,
            image_path=frame_path,
        )
    except Exception as exc:
        log.error(f"vision hata ({video.name}): {exc}")
        return None

    return {
        "dosya_adi": video.name,
        "mekan_etiketi": clean_label(raw_label),
        "sure_sn": info.duration_sn,
        "genislik": info.width,
        "yukseklik": info.height,
        "fps": info.fps,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=None)
    parser.add_argument("--pilot", action="store_true", help="Sadece pilot_count kadar örnek işle")
    args = parser.parse_args()

    cfg = load_config(args.config)
    source = require_video_source(cfg)
    client = OllamaClient(cfg.ollama.base_url, cfg.ollama.request_timeout_sn)

    if not client.health():
        log.error("Ollama erişilemiyor. `ollama serve` çalışıyor mu?")
        sys.exit(1)

    videos = scan_videos(source)
    log.info(f"Bulunan video sayısı: {len(videos)}")
    if not videos:
        log.error(f"Kaynak boş: {source}")
        sys.exit(1)

    seen = load_seen(cfg.paths.metadata_csv)
    todo = [v for v in videos if v.name not in seen]
    log.info(f"CSV'de olan: {len(seen)}, işlenecek: {len(todo)}")

    if args.pilot or cfg.pilot.pilot_mode:
        random.seed(cfg.pilot.random_seed)
        random.shuffle(todo)
        todo = todo[: cfg.pilot.pilot_count]
        log.info(f"Pilot mode: {len(todo)} video işlenecek")

    if not todo:
        log.info("İşlenecek video yok, çıkılıyor.")
        return

    with ThreadPoolExecutor(max_workers=cfg.ollama.vision_concurrency) as pool:
        futures = {pool.submit(analyze_one, v, cfg, client): v for v in todo}
        with tqdm(total=len(futures), desc="Vision analiz") as bar:
            for fut in as_completed(futures):
                row = fut.result()
                if row is not None:
                    append_row(cfg.paths.metadata_csv, row)
                    log.info(f"✓ {row['dosya_adi']} → {row['mekan_etiketi']}")
                bar.update(1)

    log.info(f"Bitti. CSV: {cfg.paths.metadata_csv}")


if __name__ == "__main__":
    main()
