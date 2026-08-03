from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path
from typing import Any

from moviepy import (
    ColorClip,
    CompositeVideoClip,
    TextClip,
    VideoFileClip,
    concatenate_videoclips,
)
from proglog import ProgressBarLogger
from tqdm import tqdm

from src.config import Config, load_config, require_video_source
from src.utils.ffprobe import probe
from src.utils.logging import get_logger

log = get_logger("step4")


COLOR_MAP: dict[str, str] = {
    "beyaz": "white",
    "sari": "#FFD400",
    "sarı": "#FFD400",
    "kirmizi": "#FF3B30",
    "kırmızı": "#FF3B30",
    "siyah": "black",
    "yesil": "#34C759",
    "yeşil": "#34C759",
    "mavi": "#0A84FF",
    "turuncu": "#FF9500",
    "pembe": "#FF2D92",
}

STIL_STYLE: dict[str, dict[str, Any]] = {
    "baslik":    {"size": 130, "y_ratio": 0.15, "default_color": "beyaz"},
    "hook":      {"size": 130, "y_ratio": 0.15, "default_color": "beyaz"},
    "altbaslik": {"size": 78,  "y_ratio": 0.78, "default_color": "beyaz"},
    "cta":       {"size": 88,  "y_ratio": 0.78, "default_color": "sari"},
    "vurgu":     {"size": 110, "y_ratio": 0.42, "default_color": "sari"},
    # Kalıcı footer imzası — video boyunca sabit, altta (kanal handle vb.)
    "footer":    {"size": 38,  "y_ratio": 0.93, "default_color": "beyaz"},
}

# Hook'un giriş süresi: sadece başta görünsün, sonra kaybolsun.
HOOK_START_SN = 0.4
HOOK_VISIBLE_SN = 4.5


class LineProgressLogger(ProgressBarLogger):
    """MoviePy encode progress'ini `\\r` yerine yeni satırla basar — böylece
    subprocess okuyucuları (web dashboard, tail -f, docker logs) her adımı
    canlı görebilir."""

    def __init__(self, prefix: str = "encode", step_pct: int = 5) -> None:
        super().__init__()
        self.prefix = prefix
        self.step = max(1, step_pct)
        self._last_pct: dict[str, int] = {}

    def bars_callback(self, bar, attr, value, old_value=None):
        if attr != "index":
            return
        total = self.bars.get(bar, {}).get("total") or 0
        if total <= 0:
            return
        pct = int(value / total * 100)
        prev = self._last_pct.get(bar, -1)
        if pct >= 100 or pct - prev >= self.step:
            self._last_pct[bar] = pct
            log.info(f"  [{self.prefix}:{bar}] {value}/{total} ({pct}%)")

    def callback(self, **changes):
        msg = changes.get("message")
        if msg:
            log.info(f"  [{self.prefix}] {msg}")


def crop_to_vertical(clip: VideoFileClip, target_w: int, target_h: int) -> Any:
    tw, th = target_w, target_h
    src_w, src_h = clip.w, clip.h
    target_ratio = tw / th
    src_ratio = src_w / src_h

    if src_ratio > target_ratio:
        new_w = int(src_h * target_ratio)
        x1 = (src_w - new_w) // 2
        clip = clip.cropped(x1=x1, y1=0, x2=x1 + new_w, y2=src_h)
    else:
        new_h = int(src_w / target_ratio)
        y1 = (src_h - new_h) // 2
        clip = clip.cropped(x1=0, y1=y1, x2=src_w, y2=y1 + new_h)
    return clip.resized((tw, th))


def _clean_video_cache_dir(cfg: Config) -> Path:
    """Cache klasörü: data/cleaned/ altında normalize edilmiş kopyalar."""
    d = cfg.paths.frames_dir.parent / "cleaned"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _sanitize_input(video_path: Path, cfg: Config) -> Path:
    """iPhone 17+ videolarında apac (Apple Positional Audio Codec) + DoVi HEVC
    10-bit + mebx metadata stream'leri var → MoviePy ffmpeg parser bunları
    tanımıyor, dosya açılmıyor. Kaynak dosyayı ffmpeg ile sadeleştirip
    (yalnızca ilk video stream, ses yok, standart H.264 8-bit) cache'e yaz.

    Cache anahtarı: dosya adı + mtime → aynı video değişmediyse yeniden üretilmez.
    """
    cache = _clean_video_cache_dir(cfg)
    dst = cache / f"{video_path.stem}.mp4"
    try:
        if dst.exists() and dst.stat().st_mtime >= video_path.stat().st_mtime:
            return dst
    except OSError:
        pass

    log.info(f"  clean: {video_path.name} → {dst.name}")
    # iPhone 17+ videolar birden fazla MoviePy uyumsuzluğu içeriyor:
    # 1. apac (Apple Positional Audio Codec) audio stream → probe fail
    # 2. HEVC Main 10 + Dolby Vision → decode ağır
    # 3. Ambient Viewing Environment side data → MoviePy 2.1.1 parser hatası
    # 4. BT.2020 → colorspace uyumsuzluğu
    #
    # ffmpeg pipeline hepsini tek seferde temizler:
    # -map 0:v:0           → sadece ilk video, diğer stream'ler yok
    # -vf scale=… BT.709   → 1080p yükseklik + renk uzayı normalize
    # -pix_fmt yuv420p     → 8-bit (10-bit DoVi'yi düşür)
    # -color_* bt709       → SDR metadata (Ambient Viewing side data düşer)
    # -map_metadata -1     → tüm mov box'ları sıfırla
    # -crf 20 veryfast     → dengeli kalite/hız
    # -an                  → ses yok (zaten kullanmıyoruz)
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error",
         "-i", str(video_path),
         "-map", "0:v:0",
         "-vf", "scale=-2:1080:in_color_matrix=bt2020nc:out_color_matrix=bt709,format=yuv420p",
         "-c:v", "libx264",
         "-pix_fmt", "yuv420p",
         "-crf", "20",
         "-preset", "veryfast",
         "-color_primaries", "bt709",
         "-color_trc", "bt709",
         "-colorspace", "bt709",
         "-map_metadata", "-1",
         "-map_chapters", "-1",
         "-an",
         "-movflags", "+faststart",
         str(dst)],
        check=True,
    )
    return dst


def load_and_trim(video_path: Path, target_sn: float, cfg: Config) -> Any:
    """Video dosyasını aç, süreye trim et, 9:16 crop et.
    Sorunlu iPhone stream'leri (apac, DoVi 10-bit) için önden sanitize eder."""
    try:
        clip = VideoFileClip(str(video_path), audio=False)
    except (OSError, IOError):
        # ffmpeg probe fail → önden ffmpeg ile temizle (cache'li), tekrar dene
        cleaned = _sanitize_input(video_path, cfg)
        clip = VideoFileClip(str(cleaned), audio=False)

    if clip.duration and clip.duration > target_sn:
        clip = clip.subclipped(0, target_sn)
    clip = crop_to_vertical(clip, cfg.reels.target_width, cfg.reels.target_height)
    return clip.with_fps(cfg.reels.fps)


def _plan_durations(clip_durations: list[float], cfg: Config) -> list[float]:
    """Her klibe, kaynağını AŞMADAN, orantılı ekran süresi ver — siyah dolgu yok,
    klipler yarıda garipçe kesilmez. Toplam [min, max] aralığına oturur."""
    avail = sum(max(d, 0.0) for d in clip_durations)
    if avail <= 0:
        return [cfg.reels.max_duration_sn / max(len(clip_durations), 1)] * len(clip_durations)
    target = min(cfg.reels.max_duration_sn, max(cfg.reels.min_duration_sn, avail))
    target = min(target, avail)  # kaynaktan fazlasını isteme
    ratio = target / avail
    return [max(0.8, d * ratio) for d in clip_durations]


def _font_path(cfg: Config, stil: str) -> str | None:
    primary = Path(cfg.reels.font)
    if primary.exists():
        return str(primary)
    alt = Path(cfg.reels.font_alt)
    if alt.exists():
        return str(alt)
    return None


def _resolve_color(name: str) -> str:
    return COLOR_MAP.get(name.strip().lower(), name)


def tr_upper(text: str) -> str:
    """Türkçe-duyarlı büyük harf: i→İ, ı→I (Python .upper() bunu yanlış yapar)."""
    return text.replace("i", "İ").replace("ı", "I").upper()


def _fit_font_size(text: str, base_size: int, upper: bool) -> int:
    """Uzun metinde font-size'ı otomatik küçült — kenardan taşmayı önler.
    Impact/Arial Black gibi kondense fontlarda 4 kelimeye kadar rahat, üstü sıkışır."""
    render = text.upper() if upper else text
    words = render.split()
    max_w = max((len(w) for w in words), default=0)
    total_len = len(render)
    if max_w >= 14 or total_len > 40:
        return int(base_size * 0.70)
    if max_w >= 11 or total_len > 30:
        return int(base_size * 0.80)
    if total_len > 22:
        return int(base_size * 0.90)
    return base_size


def make_overlay(text: str, cfg: Config, stil: str, renk: str, upper: bool = True) -> list[Any]:
    style = STIL_STYLE.get(stil.lower(), STIL_STYLE["vurgu"])
    y_ratio = style["y_ratio"]
    color = _resolve_color(renk or style["default_color"])
    font = _font_path(cfg, stil)
    # %78 caption genişliği — kenardan güvenli margin bırakır (önceden %88 idi,
    # 4K+dikey videolarda geniş harfler kenarda kesilebiliyordu).
    caption_w = int(cfg.reels.target_width * 0.78)
    render_text = tr_upper(text) if upper else text
    size = _fit_font_size(render_text, style["size"], upper=False)  # zaten upper'landı

    def _build(color_hex: str, stroke_hex: str, stroke_w: int) -> TextClip:
        return TextClip(
            text=render_text,
            font_size=size,
            color=color_hex,
            font=font,
            stroke_color=stroke_hex,
            stroke_width=stroke_w,
            method="caption",
            size=(caption_w, None),
            text_align="center",
        )

    y_pos = int(cfg.reels.target_height * y_ratio)
    scale = size / 130
    off = max(2, round(cfg.reels.shadow_offset * scale))
    stroke_w = max(2, round(cfg.reels.stroke_width * scale))

    shadow = _build("black", "black", 0).with_opacity(0.55).with_position(("center", y_pos + off))
    main = _build(color, "black", stroke_w).with_position(("center", y_pos))
    return [shadow, main]


def render_reel(final_json: Path, cfg: Config, source_dir: Path, name_index: dict[str, Path]) -> Path | None:
    data = json.loads(final_json.read_text(encoding="utf-8"))
    videos: list[str] = data["video_dosyalari"]
    plan = data["kurgu_json"]

    log.info(f"▶ {final_json.name} — {len(videos)} klip")

    present: list[Path] = []
    durations: list[float] = []
    for name in videos:
        path = name_index.get(name)
        if path is None or not path.exists():
            log.warning(f"  ✗ bulunamadı: {name}")
            continue
        try:
            d = probe(path).duration_sn
            durations.append(d)
            present.append(path)
            log.info(f"  · {name} ({d:.1f}s)")
        except Exception as exc:
            log.warning(f"  ✗ süre okunamadı ({name}): {exc}")

    if not present:
        log.error(f"Hiç klip yok, atlanıyor: {final_json.name}")
        return None

    shares = _plan_durations(durations, cfg)
    log.info(f"  paylaşım: {', '.join(f'{s:.1f}s' for s in shares)} (toplam {sum(shares):.1f}s)")

    log.info("  klipler yükleniyor + 9:16 crop…")
    clips: list[Any] = []
    for i, (path, share) in enumerate(zip(present, shares), 1):
        try:
            clips.append(load_and_trim(path, share, cfg))
            log.info(f"    [{i}/{len(present)}] {path.name} hazır")
        except Exception as exc:
            log.error(f"  ✗ klip yüklenemedi ({path.name}): {exc}")

    if not clips:
        log.error(f"Hiç klip yüklenemedi, atlanıyor: {final_json.name}")
        return None

    log.info(f"  {len(clips)} klip birleştiriliyor…")
    base = concatenate_videoclips(clips, method="compose")
    if base.duration > cfg.reels.max_duration_sn:
        base = base.subclipped(0, cfg.reels.max_duration_sn)
    if base.duration < 3.0:
        pad = ColorClip(
            size=(cfg.reels.target_width, cfg.reels.target_height),
            color=(0, 0, 0), duration=3.0 - base.duration,
        ).with_fps(cfg.reels.fps)
        base = concatenate_videoclips([base, pad])

    overlay_clips: list[Any] = []

    if cfg.reels.add_overlays:
        # add_overlays=True: eski davranış — hook + footer video'ya gömülür.
        log.info("  overlay'ler ekleniyor (hook + footer)…")

        # 1) HOOK: büyük/vurgulu, yalnızca girişte görünür (sonra kaybolur).
        hook_text = str(plan.get("hook", "")).strip()
        if hook_text:
            hook_start = min(HOOK_START_SN, max(0.0, base.duration - 0.5))
            hook_dur = max(0.5, min(HOOK_VISIBLE_SN, base.duration - hook_start))
            for c in make_overlay(hook_text, cfg, "hook", "beyaz"):
                overlay_clips.append(c.with_start(hook_start).with_duration(hook_dur))
            log.info(f"    hook: \"{hook_text[:60]}\" ({hook_dur:.1f}s)")

        # 2) FOOTER: cfg.reels.footer_text video boyunca altta sabit.
        footer_text = str(cfg.reels.footer_text or "").strip()
        if footer_text:
            for c in make_overlay(footer_text, cfg, "footer", "beyaz", upper=False):
                overlay_clips.append(c.with_start(0.0).with_duration(base.duration))
            log.info(f"    footer: \"{footer_text}\"")
    else:
        # add_overlays=False (default): video TEMİZ kalır. Yazılar sadece
        # .txt caption dosyasında; kullanıcı Instagram'da caption'ı ekler.
        log.info("  overlay YOK — video temiz kalıyor (add_overlays=False)")

    final = CompositeVideoClip(
        [base, *overlay_clips],
        size=(cfg.reels.target_width, cfg.reels.target_height),
    )

    out_name = final_json.name.replace("_final.json", ".mp4")
    out_path = cfg.paths.output_dir / out_name
    expected = float(final.duration)
    tmp_path = out_path.with_suffix(".part.mp4")
    log.info(f"  encode başlıyor → {out_path.name} (hedef {expected:.1f}s @ {cfg.reels.fps}fps, H.264/AAC, 4 thread)")

    try:
        final.write_videofile(
            str(tmp_path),
            codec="libx264",
            audio=False,       # kliplerin audio'sunu okumuyoruz (iPhone apac uyumsuz)
            fps=cfg.reels.fps,
            preset="medium",
            threads=4,
            logger=LineProgressLogger(prefix=out_name),
        )
    finally:
        for c in clips:
            try:
                c.close()
            except Exception:
                pass
        final.close()

    # Tam-render doğrulaması: dosya var, süre beklenene yakın (yarıda kesilmemiş)
    try:
        got = probe(tmp_path).duration_sn
    except Exception as exc:
        log.error(f"✖ Çıktı doğrulanamadı ({out_name}): {exc}")
        tmp_path.unlink(missing_ok=True)
        return None
    if got < min(expected - 1.5, expected * 0.9):
        log.error(f"✖ Render eksik/kesik ({out_name}): beklenen {expected:.1f}s, elde {got:.1f}s — atılıyor")
        tmp_path.unlink(missing_ok=True)
        return None

    tmp_path.replace(out_path)
    _write_caption(final_json, plan, out_path)
    log.info(f"✓ {out_name} doğrulandı ({got:.1f}s)")
    return out_path


def _write_caption(final_json: Path, plan: dict[str, Any], mp4_path: Path) -> None:
    aciklama = str(plan.get("aciklama", "")).strip()
    hashtagler = plan.get("hashtagler") or []
    if isinstance(hashtagler, str):
        hashtagler = [h.strip() for h in hashtagler.split() if h.strip()]
    tags = " ".join(
        (t if t.startswith("#") else f"#{t}")
        for t in hashtagler
        if isinstance(t, str) and t.strip()
    )
    parts = [p for p in [aciklama, tags] if p]
    caption = ("\n\n".join(parts)).strip() or "(Instagram açıklaması üretilmedi)"
    caption_path = mp4_path.with_suffix(".txt")
    caption_path.write_text(caption + "\n", encoding="utf-8")
    log.info(f"Caption → {caption_path.name}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=None)
    parser.add_argument("--limit", type=int, default=None, help="En fazla kaç reel render edilsin")
    args = parser.parse_args()

    cfg = load_config(args.config)
    source = require_video_source(cfg)
    finals = sorted(cfg.paths.plans_dir.glob("*_final.json"))
    if args.limit:
        finals = finals[: args.limit]
    log.info(f"Render edilecek reel: {len(finals)}")

    log.info("Kaynak indeksi oluşturuluyor…")
    name_index: dict[str, Path] = {}
    for p in source.rglob("*"):
        if p.is_file() and p.suffix.lower() in {".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm"}:
            name_index[p.name] = p
    log.info(f"İndeks: {len(name_index)} dosya")

    ok, fail = 0, 0
    for path in tqdm(finals, desc="Reels render"):
        try:
            out = render_reel(path, cfg, source, name_index)
            if out:
                ok += 1
            else:
                fail += 1
        except Exception as exc:
            log.error(f"Render hata ({path.name}): {exc}")
            fail += 1
    log.info(f"Tamam. Başarılı: {ok}, başarısız: {fail}. Klasör: {cfg.paths.output_dir}")


if __name__ == "__main__":
    main()
