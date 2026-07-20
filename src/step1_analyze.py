from __future__ import annotations

import argparse
import csv
import json
import random
import re
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any

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
    "sahne_ozeti", "sahne_ogeleri", "sahne_mekan_tahmini",
]

# Llava:7b Türkçe prompt'a çok kötü uyum sağlıyor + uzun cevap veriyor (5+ dk/kare).
# İngilizce prompt + num_predict=40 ile 5-10sn/kare. Türkçe'ye qwen sentez adımında
# çeviriyoruz — bu ayrıca konu-mekan çıkarımını da yapar.
FRAME_PROMPT = (
    "This is one frame from a Japan travel video. List the concrete visual "
    "elements in a single short comma-separated English line (max 12 words). "
    "If you can identify a specific place (temple name, station, park, park ride, "
    "shrine gate type, city district), include it. No emoji, no quotes, no full "
    "sentences.\n"
    "Examples:\n"
    "'red torii gates, stone path, forest'\n"
    "'shinkansen platform, blue train, waiting passengers'\n"
    "'giant Buddha statue, wooden pillars, temple interior'\n"
    "'aerial drone shot, skyscrapers, river bending'\n"
    "'theme park ride, roller coaster tracks, castle backdrop'"
)

# Küçük modelde JSON mode güvenilmez → düz text prompt + regex parse.
# 3 ayrı ETIKET altında satır bekleniyor: OZET / OGELER / MEKAN. Bu format
# qwen2.5:3b tarafından bile ~%98 güvenilir üretiliyor.
SYNTH_SYSTEM = (
    "Sen bir video analiz asistanısın. Sana bir videonun farklı zamanlarından "
    "çekilmiş kare tanımları verilir. Bu tanımların ORTAK içeriğinden video "
    "sahnesinin özetini çıkarırsın. Kusursuz Türkçe kullanırsın. Hallüsinasyon "
    "yasak — sadece kare tanımlarında geçen bilgiyi kullan."
)

SYNTH_PROMPT_TEMPLATE = """Aşağıda bir Japonya seyahat videosunun farklı zamanlarındaki kareler İNGİLİZCE tanımlanmış:

{kareler}

Bu İngilizce kare tanımlarını TÜRKÇE'ye çevirerek videonun özetini çıkar.
Çıktın SADECE aşağıdaki 3 satırdan oluşsun — başka hiçbir şey yazma:

OZET: <1 tam Türkçe cümle, max 20 kelime, videonun ne gösterdiğini anlatır>
OGELER: <virgülle ayrılmış 5-10 somut Türkçe isim, küçük harf>
MEKAN: <spesifik mekan adı yaz (Fushimi Inari, Todai-ji, Shibuya, Universal Studios, Nara Park vb.) veya emin değilsen boş bırak>"""


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
        "sahne_ogeleri": "",
        "sahne_mekan_tahmini": "",
    }


def _sample_times(duration_sn: float) -> list[float]:
    """Video süresine göre örneklem zaman noktaları döner.
    Kısa live-photo (< 1sn) tek kare, 5-20sn 2 kare, 20-40sn 3 kare, 40+ 4 kare.
    Frame sayısını sıkı tutuyoruz — llava çağrısı en pahalı adım."""
    d = max(0.1, duration_sn)
    if d < 1.5:
        return [round(d * 0.5, 2)]
    if d <= 20:
        return [round(d * 0.25, 2), round(d * 0.75, 2)]
    if d <= 40:
        return [1.0, round(d * 0.5, 2), round(d - 1.0, 2)]
    return [1.0, round(d * 0.33, 2), round(d * 0.66, 2), round(d - 1.0, 2)]


def _clean_frame_line(text: str) -> str:
    """Tek bir kare tanımını tek-satır virgüllü listeye normalize et."""
    if not text:
        return ""
    text = text.strip().strip("`").strip('"').strip("'")
    for line in text.splitlines():
        line = line.strip("-* \t").strip()
        if len(line) >= 5:
            text = line
            break
    text = "".join(ch for ch in text if ord(ch) < 0x1F300 or ord(ch) > 0x1FAFF)
    return text.strip()[:200]


_OZET_RE = re.compile(r"^\s*OZET\s*:\s*(.+)$", re.MULTILINE | re.IGNORECASE)
_OGELER_RE = re.compile(r"^\s*OGELER\s*:\s*(.+)$", re.MULTILINE | re.IGNORECASE)
_MEKAN_RE = re.compile(r"^\s*MEKAN\s*:\s*(.+)$", re.MULTILINE | re.IGNORECASE)


def _synthesize_scene(client: OllamaClient, model: str,
                      frame_lines: list[str]) -> dict[str, Any]:
    """Kare tanımlarını qwen2.5 ile düz text formatta özete birleştir (regex parse).
    Küçük modelde format=json güvenilmez → 3 satır etiketli çıktı çok daha stabil."""
    if not frame_lines:
        return {"sahne_ozeti": "", "ogeler": [], "mekan_tahmini": ""}

    kareler = "\n".join(f"Kare {i+1}: {line}" for i, line in enumerate(frame_lines))
    prompt = SYNTH_PROMPT_TEMPLATE.format(kareler=kareler)

    raw = ""
    for attempt in range(2):
        try:
            raw = client.generate_text(
                model, prompt, system=SYNTH_SYSTEM, temperature=0.2,
            )
            if raw.strip():
                break
        except RuntimeError as exc:
            if attempt == 1:
                log.warning(f"  sentez başarısız: {exc}")

    ozet_m = _OZET_RE.search(raw)
    ogeler_m = _OGELER_RE.search(raw)
    mekan_m = _MEKAN_RE.search(raw)

    ozet = (ozet_m.group(1).strip() if ozet_m else " · ".join(frame_lines))[:250]
    if mekan_m:
        mekan_raw = mekan_m.group(1).strip().strip('"').strip("'")
        # "boş", "bilinmiyor", "yok" gibi placeholder'ları temizle
        if mekan_raw.lower() in {"boş", "bos", "yok", "bilinmiyor", "belirsiz", "-", "n/a", "none", ""}:
            mekan = ""
        else:
            mekan = mekan_raw[:80]
    else:
        mekan = ""

    if ogeler_m:
        ogeler_raw = ogeler_m.group(1).strip().strip("[").strip("]")
        ogeler = [o.strip().strip('"').strip("'").lower()
                  for o in ogeler_raw.split(",") if o.strip()]
    else:
        # llava çıktısında geçenleri fallback ege çevir
        ogeler = [w.strip().lower() for line in frame_lines
                  for w in line.split(",") if w.strip()]
    # dedup + max 10
    seen: set[str] = set()
    uniq: list[str] = []
    for o in ogeler:
        if o and o not in seen:
            seen.add(o)
            uniq.append(o)

    return {"sahne_ozeti": ozet, "ogeler": uniq[:10], "mekan_tahmini": mekan}


def _enrich_scenes(cfg: Config, source: Path, limit: int | None) -> None:
    """Multi-frame + iki-model sahne analizi — BATCH MIMARISI.

    Model swap pahalı (Ollama modeli VRAM'dan boşaltıp yeniden yüklüyor).
    Bu yüzden akış:
      Phase 1: TÜM videoların TÜM frame'lerini llava ile ardışık işle
               (llava sürekli yüklü, swap yok)
      Phase 2: TÜM sentezleri qwen ile ardışık yap
               (qwen sürekli yüklü, swap yok)

    Böylece model swap 2N yerine yalnızca 2 kere olur.
    Idempotent (dolu satır atlanır), crash-safe (her sentezden sonra CSV kaydedilir).
    """
    import shutil

    if not cfg.paths.metadata_csv.exists():
        log.error(f"metadata.csv yok: {cfg.paths.metadata_csv}")
        sys.exit(1)

    client = OllamaClient(cfg.ollama.base_url, cfg.ollama.request_timeout_sn)
    if not client.health():
        log.error("Ollama erişilemiyor — sahne özeti çıkarımı iptal.")
        sys.exit(1)

    from src.step3_dify import pick_text_model
    text_model = pick_text_model(cfg, client)
    log.info(f"Vision: {cfg.ollama.vision_model} · Sentez: {text_model}")

    name_to_path: dict[str, Path] = {}
    for p in source.rglob("*"):
        if p.is_file() and p.suffix.lower() in VIDEO_EXT:
            name_to_path.setdefault(p.name, p)

    with cfg.paths.metadata_csv.open("r", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
        for r in rows:
            r.setdefault("sahne_ozeti", "")
            r.setdefault("sahne_ogeleri", "")
            r.setdefault("sahne_mekan_tahmini", "")

    todo = [r for r in rows if not (r.get("sahne_ozeti") or "").strip()]
    if limit is not None:
        todo = todo[:limit]
    log.info(f"Analiz edilecek video: {len(todo)} / {len(rows)}")

    def _save() -> None:
        with cfg.paths.metadata_csv.open("w", encoding="utf-8", newline="") as fh:
            writer = csv.DictWriter(fh, fieldnames=CSV_FIELDS)
            writer.writeheader()
            writer.writerows(rows)

    # =============================================================
    # PHASE 1: Frame extraction + llava vision — llava sürekli yüklü
    # =============================================================
    log.info(f"═════ PHASE 1 — {cfg.ollama.vision_model} ile kare analizi ═════")
    frames_per_video: dict[str, list[str]] = {}   # dosya_adi → list[frame_line]
    total_frames = 0

    for r in todo:
        name = r["dosya_adi"]
        p = name_to_path.get(name)
        if p is None:
            log.warning(f"  ✗ dosya bulunamadı: {name}")
            continue
        duration = float(r.get("sure_sn") or 1.0)
        times = _sample_times(duration)
        total_frames += len(times)

    log.info(f"Toplam kare: {total_frames} ({len(todo)} video)")
    with tqdm(total=total_frames, desc="Vision (llava)", unit="kare") as bar:
        for r in todo:
            name = r["dosya_adi"]
            p = name_to_path.get(name)
            if p is None:
                continue

            duration = float(r.get("sure_sn") or 1.0)
            times = _sample_times(duration)
            log.info(f"▶ {name} ({duration:.1f}s, {len(times)} kare)")

            frame_lines: list[str] = []
            for i, t in enumerate(times, 1):
                fpath = cfg.paths.frames_dir / f"{p.stem}_f{i:02d}.jpg"
                try:
                    if not fpath.exists():
                        extract_first_frame(p, fpath, at_sn=t)
                    raw = client.generate_vision(
                        cfg.ollama.vision_model, FRAME_PROMPT, fpath,
                        max_tokens=40,
                    )
                    line = _clean_frame_line(raw)
                    if line:
                        frame_lines.append(line)
                        log.info(f"    [{i}/{len(times)}] t={t}s → {line}")
                except Exception as exc:
                    log.warning(f"    [{i}/{len(times)}] hata: {exc}")
                bar.update(1)

            frames_per_video[name] = frame_lines

            # standart thumbnail (galeri için)
            std_frame = cfg.paths.frames_dir / f"{p.stem}.jpg"
            if not std_frame.exists() and (cfg.paths.frames_dir / f"{p.stem}_f01.jpg").exists():
                shutil.copyfile(cfg.paths.frames_dir / f"{p.stem}_f01.jpg", std_frame)

    # ==========================================================
    # PHASE 2: Metin sentezi — qwen sürekli yüklü (llava boşalır)
    # ==========================================================
    log.info(f"═════ PHASE 2 — {text_model} ile sentez ═════")
    with tqdm(total=len(todo), desc=f"Sentez ({text_model})", unit="video") as bar:
        for r in todo:
            name = r["dosya_adi"]
            frame_lines = frames_per_video.get(name, [])
            if not frame_lines:
                log.warning(f"  ✗ kare yok, atlanıyor: {name}")
                bar.update(1)
                continue

            synth = _synthesize_scene(client, text_model, frame_lines)
            r["sahne_ozeti"] = synth["sahne_ozeti"]
            # sahne_ogeleri: Türkçe çeviri + orijinal İngilizce ham liste (arama zenginliği)
            tr_ogeler = " | ".join(synth["ogeler"])
            en_raw = " || ".join(frame_lines)
            r["sahne_ogeleri"] = f"{tr_ogeler} || {en_raw}" if tr_ogeler else en_raw
            r["sahne_mekan_tahmini"] = synth["mekan_tahmini"]
            log.info(f"  ✓ {name}")
            log.info(f"      ÖZET: {synth['sahne_ozeti']}")
            log.info(f"      ÖGELER: {r['sahne_ogeleri']}")
            if synth["mekan_tahmini"]:
                log.info(f"      MEKAN TAHMİNİ: {synth['mekan_tahmini']}")

            _save()
            bar.update(1)

    log.info(f"Bitti. CSV güncellendi: {cfg.paths.metadata_csv}")


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
