from __future__ import annotations

import argparse
import json
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
    # Küçük puntolu, kalıcı lokasyon etiketi (alt tarafta, hook ile çakışmaz).
    "lokasyon":  {"size": 44,  "y_ratio": 0.90, "default_color": "beyaz"},
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


def load_and_trim(video_path: Path, target_sn: float, cfg: Config) -> Any:
    clip = VideoFileClip(str(video_path))
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


def make_overlay(text: str, cfg: Config, stil: str, renk: str, upper: bool = True) -> list[Any]:
    style = STIL_STYLE.get(stil.lower(), STIL_STYLE["vurgu"])
    size = style["size"]
    y_ratio = style["y_ratio"]
    color = _resolve_color(renk or style["default_color"])
    font = _font_path(cfg, stil)
    caption_w = int(cfg.reels.target_width * 0.88)
    render_text = tr_upper(text) if upper else text

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
    # Gölge/kontur kalınlığını punto ile orantıla: büyük hook aynı kalır,
    # küçük lokasyon etiketinde kontur okunur boyutta olur.
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

    log.info("  overlay'ler ekleniyor (hook + lokasyon)…")
    overlay_clips: list[Any] = []

    # 1) HOOK: büyük/vurgulu, yalnızca girişte görünür (sonra kaybolur).
    hook_text = str(plan.get("hook", "")).strip()
    if hook_text:
        hook_start = min(HOOK_START_SN, max(0.0, base.duration - 0.5))
        hook_dur = max(0.5, min(HOOK_VISIBLE_SN, base.duration - hook_start))
        for c in make_overlay(hook_text, cfg, "hook", "beyaz"):
            overlay_clips.append(c.with_start(hook_start).with_duration(hook_dur))
        log.info(f"    hook: \"{hook_text[:60]}\" ({hook_dur:.1f}s)")

    # 2) LOKASYON ETİKETİ: küçük puntolu, normal yazım, TÜM video boyunca kalıcı.
    lokasyon = str(data.get("mekan_etiketi", "")).strip()
    if lokasyon:
        for c in make_overlay(lokasyon, cfg, "lokasyon", "beyaz", upper=False):
            overlay_clips.append(c.with_start(0.0).with_duration(base.duration))
        log.info(f"    lokasyon: \"{lokasyon}\"")

    # 3) Aradaki overlay'ler ve 4) sondaki CTA artık ekrana basılmıyor
    #    (bu bilgiler açıklama/.txt içinde korunuyor).

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
            audio_codec="aac",
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
