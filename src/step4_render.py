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
from tqdm import tqdm

from src.config import Config, load_config, require_video_source
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
}


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
    if clip.duration > target_sn:
        clip = clip.subclipped(0, target_sn)
    clip = crop_to_vertical(clip, cfg.reels.target_width, cfg.reels.target_height)
    return clip.with_fps(cfg.reels.fps)


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


def make_overlay(text: str, cfg: Config, stil: str, renk: str) -> list[Any]:
    style = STIL_STYLE.get(stil.lower(), STIL_STYLE["vurgu"])
    size = style["size"]
    y_ratio = style["y_ratio"]
    color = _resolve_color(renk or style["default_color"])
    font = _font_path(cfg, stil)
    caption_w = int(cfg.reels.target_width * 0.88)

    def _build(color_hex: str, stroke_hex: str, stroke_w: int) -> TextClip:
        return TextClip(
            text=text.upper(),
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
    off = cfg.reels.shadow_offset

    shadow = _build("black", "black", 0).with_opacity(0.55).with_position(("center", y_pos + off))
    main = _build(color, "black", cfg.reels.stroke_width).with_position(("center", y_pos))
    return [shadow, main]


def render_reel(final_json: Path, cfg: Config, source_dir: Path, name_index: dict[str, Path]) -> Path | None:
    data = json.loads(final_json.read_text(encoding="utf-8"))
    videos: list[str] = data["video_dosyalari"]
    plan = data["kurgu_json"]

    per_clip_sn = cfg.reels.max_duration_sn / max(len(videos), 1)

    clips: list[Any] = []
    for name in videos:
        path = name_index.get(name)
        if path is None or not path.exists():
            log.warning(f"Bulunamadı: {name}")
            continue
        try:
            c = load_and_trim(path, per_clip_sn, cfg)
            clips.append(c)
        except Exception as exc:
            log.error(f"Klip yüklenemedi ({name}): {exc}")

    if not clips:
        log.error(f"Hiç klip yok, atlanıyor: {final_json.name}")
        return None

    base = concatenate_videoclips(clips, method="compose")
    if base.duration < cfg.reels.min_duration_sn:
        pad = ColorClip(
            size=(cfg.reels.target_width, cfg.reels.target_height),
            color=(0, 0, 0),
            duration=cfg.reels.min_duration_sn - base.duration,
        ).with_fps(cfg.reels.fps)
        base = concatenate_videoclips([base, pad])
    if base.duration > cfg.reels.max_duration_sn:
        base = base.subclipped(0, cfg.reels.max_duration_sn)

    overlay_clips: list[Any] = []

    hook_text = str(plan.get("hook", "")).strip()
    if hook_text:
        for c in make_overlay(hook_text, cfg, "hook", "beyaz"):
            overlay_clips.append(c.with_start(0.0).with_duration(cfg.reels.hook_duration_sn))

    for o in plan.get("overlays", []):
        try:
            stil = str(o.get("stil", "vurgu"))
            renk = str(o.get("renk", ""))
            start = max(0.0, float(o["saniye"]))
            dur = min(float(o.get("sure", 3.0)), max(0.5, base.duration - start))
            if dur <= 0:
                continue
            for c in make_overlay(str(o["metin"]), cfg, stil, renk):
                overlay_clips.append(c.with_start(start).with_duration(dur))
        except Exception as exc:
            log.warning(f"Overlay atlandı: {exc}")

    cta = str(plan.get("cta") or cfg.reels.cta_text)
    if cta:
        cta_start = max(0.0, base.duration - cfg.reels.cta_duration_sn)
        for c in make_overlay(cta, cfg, "cta", "sari"):
            overlay_clips.append(c.with_start(cta_start).with_duration(cfg.reels.cta_duration_sn))

    final = CompositeVideoClip(
        [base, *overlay_clips],
        size=(cfg.reels.target_width, cfg.reels.target_height),
    )

    out_name = final_json.name.replace("_final.json", ".mp4")
    out_path = cfg.paths.output_dir / out_name
    log.info(f"Render → {out_path.name} ({final.duration:.1f}s)")

    final.write_videofile(
        str(out_path),
        codec="libx264",
        audio_codec="aac",
        fps=cfg.reels.fps,
        preset="medium",
        threads=4,
        logger=None,
    )

    _write_caption(final_json, plan, out_path)

    for c in clips:
        c.close()
    final.close()
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
