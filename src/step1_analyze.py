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
    "sahne_ozeti",
]

SAHNE_PROMPT = (
    "Bu Japonya seyahatinden bir video karesi. Kısa Türkçe olarak SADECE ne "
    "gördüğünü listele: belirgin öğeler + mekan (varsa). Örnek çıktılar:\n"
    "- 'geyikler park, uzakta büyük tapınak çatısı, ağaçlar'\n"
    "- 'kırmızı torii kapılar, dar patika, orman'\n"
    "- 'gece neon reklamlar, kalabalık cadde, Glico koşan adam'\n"
    "- 'shinkansen istasyon peronu, mavi tren, yolcular'\n"
    "- 'drone kuşbakışı şehir, gökdelenler, nehir kıvrılıyor'\n"
    "Sadece görsel içerik, tahmini şehir/mekan varsa ismi yaz. Max 15 kelime. "
    "Emojisiz, tırnak veya markdown olmadan tek satır."
)


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
        "sahne_ozeti": "",
    }


def _enrich_scenes(cfg: Config, source: Path, limit: int | None) -> None:
    """metadata.csv satırlarını dolaş, sahne_ozeti boş olanlar için llava'ya
    "bu karede ne var" sordur ve yaz. Semantic prompt search'in kaynağı budur.

    - Idempotent: dolu satırlar atlanır.
    - Frame yoksa üretir.
    - Her satırdan sonra CSV'yi yeniden yazar (çakışma yok, tek işlem çalışır)
      → ollama çökse bile ilerleme kaybolmaz.
    """
    if not cfg.paths.metadata_csv.exists():
        log.error(f"metadata.csv yok: {cfg.paths.metadata_csv}")
        sys.exit(1)

    client = OllamaClient(cfg.ollama.base_url, cfg.ollama.request_timeout_sn)
    if not client.health():
        log.error("Ollama erişilemiyor — sahne özeti çıkarımı iptal.")
        sys.exit(1)

    # isim → path
    name_to_path: dict[str, Path] = {}
    for p in source.rglob("*"):
        if p.is_file() and p.suffix.lower() in VIDEO_EXT:
            name_to_path.setdefault(p.name, p)

    with cfg.paths.metadata_csv.open("r", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        rows = list(reader)
        # eski dosyalar sahne_ozeti kolonuna sahip olmayabilir → migrate
        for r in rows:
            r.setdefault("sahne_ozeti", "")

    todo = [r for r in rows if not (r.get("sahne_ozeti") or "").strip()]
    if limit is not None:
        todo = todo[:limit]
    log.info(f"Sahne özeti üretilecek satır: {len(todo)} / {len(rows)}")

    def _save() -> None:
        with cfg.paths.metadata_csv.open("w", encoding="utf-8", newline="") as fh:
            writer = csv.DictWriter(fh, fieldnames=CSV_FIELDS)
            writer.writeheader()
            writer.writerows(rows)

    with tqdm(total=len(todo), desc="Sahne özeti") as bar:
        for r in todo:
            name = r["dosya_adi"]
            p = name_to_path.get(name)
            if p is None:
                log.warning(f"  ✗ dosya bulunamadı: {name}")
                bar.update(1)
                continue

            frame_path = cfg.paths.frames_dir / f"{p.stem}.jpg"
            if not frame_path.exists():
                try:
                    dur = float(r.get("sure_sn") or 1.0)
                    extract_first_frame(p, frame_path, at_sn=min(1.0, max(0.2, dur * 0.1)))
                except Exception as exc:
                    log.warning(f"  ✗ frame çıkarılamadı ({name}): {exc}")
                    bar.update(1)
                    continue

            try:
                raw = client.generate_vision(cfg.ollama.vision_model, SAHNE_PROMPT, frame_path)
                summary = _clean_summary(raw)
                if summary:
                    r["sahne_ozeti"] = summary
                    log.info(f"  ✓ {name} → {summary}")
                    _save()
            except Exception as exc:
                log.warning(f"  ✗ llava hata ({name}): {exc}")
            bar.update(1)

    log.info(f"Bitti. CSV güncellendi: {cfg.paths.metadata_csv}")


def _clean_summary(text: str) -> str:
    """Llava çıktısını normalize et — tek satır, tırnak/emoji/markdown temizle."""
    if not text:
        return ""
    text = text.strip().strip("`").strip('"').strip("'")
    # birden fazla satırsa ilk anlamlı satırı al
    for line in text.splitlines():
        line = line.strip("-* \t").strip()
        if len(line) >= 10:
            text = line
            break
    # basit ascii-dışı emoji temizliği
    text = "".join(ch for ch in text if ord(ch) < 0x1F300 or ord(ch) > 0x1FAFF)
    return text.strip()[:200]


def _relabel_existing(cfg: Config, source: Path) -> None:
    """Mevcut metadata.csv'yi oku, her satır için labeling.parse_filename'i tekrar
    uygula ve mekan_etiketi/kategori/sehir/cekim_tipi kolonlarını güncelle. Vision
    çağırmaz — dosya-adı kurallarıyla anında yeniden etiketleme.

    Kullanım: `_KURALLAR` sözlüğünü genişlettikten sonra tüm eski satırların yeni
    kuralları görmesi için çalıştır. Video kaynağını rglob ile alt-klasör bulmak
    için de kullanır."""
    if not cfg.paths.metadata_csv.exists():
        log.error(f"metadata.csv yok: {cfg.paths.metadata_csv}")
        sys.exit(1)

    # subdir bilgisini üretmek için isim → path index
    name_to_path: dict[str, Path] = {}
    for p in source.rglob("*"):
        if p.is_file() and p.suffix.lower() in VIDEO_EXT:
            name_to_path.setdefault(p.name, p)

    with cfg.paths.metadata_csv.open("r", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))

    degisti = 0
    yeni_kaynak = 0
    for r in rows:
        name = r.get("dosya_adi", "")
        p = name_to_path.get(name)
        subdir = _subdir(p, source) if p else ""
        et = labeling.parse_filename(name, subdir)
        if et is None:
            # dosya adı kuralları yakalayamadıysa mevcut değerleri koru (vision sonucu olabilir)
            continue
        eski_mekan = r.get("mekan_etiketi", "")
        eski_kategori = r.get("kategori", "")
        if eski_mekan != et.mekan_etiketi or eski_kategori != et.kategori:
            degisti += 1
            log.info(f"  {name}: {eski_mekan or '-'} → {et.mekan_etiketi}")
        r["mekan_etiketi"] = et.mekan_etiketi
        r["kategori"] = et.kategori
        r["sehir"] = et.sehir
        r["cekim_tipi"] = et.cekim_tipi
        if r.get("kaynak") != "dosya_adi":
            yeni_kaynak += 1
        r["kaynak"] = "dosya_adi"

    with cfg.paths.metadata_csv.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=CSV_FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    log.info(f"Yeniden etiketleme bitti. Toplam satır: {len(rows)}, "
             f"etiketi değişen: {degisti}, kaynak güncellenen: {yeni_kaynak}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=None)
    parser.add_argument("--pilot", action="store_true", help="Sadece pilot_count kadar örnek işle")
    parser.add_argument("--max", type=int, default=None, help="Bu çalıştırmada işlenecek maksimum video (config'i geçersiz kılar)")
    parser.add_argument("--overwrite", action="store_true",
                        help="Mevcut metadata.csv'yi sil ve tüm videoları yeniden etiketle. "
                             "Yeni labeling kuralları veya değişen dosya isimleri için kullan.")
    parser.add_argument("--relabel-only", action="store_true",
                        help="Vision çağırmadan sadece dosya-adı kurallarıyla mevcut satırları yeniden etiketle "
                             "(çok hızlı, ollama gerektirmez).")
    parser.add_argument("--enrich-scenes", action="store_true",
                        help="metadata.csv'deki her satır için llava ile 'sahne_ozeti' üret. "
                             "prompt_pipeline sözlük eşleşmediğinde bu özetlerde substring arar → "
                             "semantic search light. ~5-8sn/video (llava:7b, Metal GPU).")
    parser.add_argument("--enrich-limit", type=int, default=None,
                        help="Sadece bu kadar satıra sahne özeti üret (test için)")
    args = parser.parse_args()

    cfg = load_config(args.config)
    source = require_video_source(cfg)
    client = OllamaClient(cfg.ollama.base_url, cfg.ollama.request_timeout_sn)

    # --relabel-only: metadata satırlarını mevcut _KURALLAR ile yeniden yaz, vision atla.
    if args.relabel_only:
        _relabel_existing(cfg, source)
        return

    # --enrich-scenes: sadece sahne_ozeti kolonunu doldur (mevcut etiketlere dokunmaz)
    if args.enrich_scenes:
        _enrich_scenes(cfg, source, args.enrich_limit)
        return

    if args.overwrite and cfg.paths.metadata_csv.exists():
        backup = cfg.paths.metadata_csv.with_suffix(".csv.bak")
        cfg.paths.metadata_csv.replace(backup)
        log.info(f"Eski metadata yedeklendi → {backup.name}, sıfırdan yeniden etiketleniyor.")

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
