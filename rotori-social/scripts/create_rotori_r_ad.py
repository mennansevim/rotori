#!/usr/bin/env python3
"""Rotori için R harfinden türeyen, 9:16 Apple-esintili reklam filmi üretir.

Kaynak ekranlar ``assets/ads/rotori_r_apple`` altında tutulur. Betik yalnızca
yerel Pillow/NumPy/ffmpeg araçlarını kullanır; müzik ve ses efektleri de
sentetik olarak üretilir, dolayısıyla çıktıda üçüncü taraf telifli öğe yoktur.
"""
from __future__ import annotations

import argparse
import math
import subprocess
import wave
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont


WIDTH = 1080
HEIGHT = 1920
FPS = 30
DURATION = 12.6
BACKGROUND = (248, 248, 246, 255)
INK = (28, 28, 30, 255)
MUTED = (111, 111, 116, 255)
RED = (222, 25, 28, 255)
DEEP_RED = (171, 13, 17, 255)
FONT_REGULAR = Path("/System/Library/Fonts/SFNS.ttf")
FONT_ROUNDED = Path("/System/Library/Fonts/SFNSRounded.ttf")
FONT_BOLD = Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf")


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def phase(t: float, start: float, end: float) -> float:
    if end <= start:
        return float(t >= end)
    return clamp((t - start) / (end - start))


def ease_out_cubic(value: float) -> float:
    p = clamp(value)
    return 1.0 - (1.0 - p) ** 3


def ease_in_out(value: float) -> float:
    p = clamp(value)
    return p * p * (3.0 - 2.0 * p)


def ease_out_back(value: float) -> float:
    p = clamp(value)
    c1 = 1.70158
    c3 = c1 + 1.0
    return 1.0 + c3 * (p - 1.0) ** 3 + c1 * (p - 1.0) ** 2


def font(size: int, *, bold: bool = False, rounded: bool = False) -> ImageFont.FreeTypeFont:
    path = FONT_BOLD if bold else FONT_ROUNDED if rounded else FONT_REGULAR
    return ImageFont.truetype(str(path), size=size)


def text_center(
    canvas: Image.Image,
    text: str,
    y: int,
    size: int,
    fill: tuple[int, int, int, int] = INK,
    *,
    bold: bool = False,
    rounded: bool = False,
    alpha: float = 1.0,
) -> None:
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    chosen = font(size, bold=bold, rounded=rounded)
    box = draw.textbbox((0, 0), text, font=chosen)
    x = (WIDTH - (box[2] - box[0])) // 2
    color = (*fill[:3], int(fill[3] * clamp(alpha)))
    draw.text((x, y), text, font=chosen, fill=color)
    canvas.alpha_composite(layer)


def cubic_bezier(
    p0: tuple[float, float],
    p1: tuple[float, float],
    p2: tuple[float, float],
    p3: tuple[float, float],
    count: int = 20,
) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for i in range(1, count + 1):
        t = i / count
        mt = 1.0 - t
        x = mt**3 * p0[0] + 3 * mt**2 * t * p1[0] + 3 * mt * t**2 * p2[0] + t**3 * p3[0]
        y = mt**3 * p0[1] + 3 * mt**2 * t * p1[1] + 3 * mt * t**2 * p2[1] + t**3 * p3[1]
        points.append((x, y))
    return points


def r_route_points(scale: float = 1.0, offset: tuple[float, float] = (0.0, 0.0)) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = [(336, 1240), (336, 650), (575, 650)]
    points += cubic_bezier((575, 650), (735, 650), (785, 735), (758, 814), 18)
    points += cubic_bezier((758, 814), (735, 918), (635, 956), (505, 956), 18)
    points += [(350, 956), (512, 956), (760, 1240)]
    ox, oy = offset
    return [((x - WIDTH / 2) * scale + WIDTH / 2 + ox, (y - HEIGHT / 2) * scale + HEIGHT / 2 + oy) for x, y in points]


def draw_partial_path(
    layer: Image.Image,
    points: list[tuple[float, float]],
    amount: float,
    *,
    width: int,
    fill: tuple[int, int, int, int],
    dot: bool = False,
) -> None:
    amount = clamp(amount)
    if amount <= 0 or len(points) < 2:
        return
    lengths = [math.dist(points[i], points[i + 1]) for i in range(len(points) - 1)]
    total = sum(lengths)
    remaining = total * amount
    visible = [points[0]]
    for i, segment_length in enumerate(lengths):
        if remaining >= segment_length:
            visible.append(points[i + 1])
            remaining -= segment_length
            continue
        ratio = remaining / segment_length if segment_length else 0.0
        x = points[i][0] + (points[i + 1][0] - points[i][0]) * ratio
        y = points[i][1] + (points[i + 1][1] - points[i][1]) * ratio
        visible.append((x, y))
        break
    draw = ImageDraw.Draw(layer)
    if len(visible) > 1:
        draw.line(visible, fill=fill, width=width, joint="curve")
        radius = width // 2
        for point in (visible[0], visible[-1]):
            draw.ellipse((point[0] - radius, point[1] - radius, point[0] + radius, point[1] + radius), fill=fill)
    if dot and visible:
        x, y = visible[-1]
        radius = max(8, width // 2 + 5)
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=(20, 20, 22, fill[3]))


def transparent_logo(path: Path) -> Image.Image:
    source = Image.open(path).convert("RGBA")
    rgba = np.asarray(source).copy()
    rgb = rgba[:, :, :3]
    alpha = np.clip(255 - rgb.min(axis=2), 0, 255).astype(np.uint8)
    alpha[alpha < 8] = 0
    rgba[:, :, 3] = alpha
    return Image.fromarray(rgba, "RGBA")


def with_opacity(image: Image.Image, opacity: float) -> Image.Image:
    result = image.copy()
    alpha = result.getchannel("A").point(lambda value: int(value * clamp(opacity)))
    result.putalpha(alpha)
    return result


def paste_center(canvas: Image.Image, image: Image.Image, center: tuple[float, float]) -> None:
    x = int(center[0] - image.width / 2)
    y = int(center[1] - image.height / 2)
    canvas.alpha_composite(image, (x, y))


def build_card(source: Path, target_width: int, max_height: int = 1340) -> Image.Image:
    screenshot = Image.open(source).convert("RGBA")
    ratio = min(target_width / screenshot.width, max_height / screenshot.height)
    size = (int(screenshot.width * ratio), int(screenshot.height * ratio))
    screenshot = screenshot.resize(size, Image.Resampling.LANCZOS)
    radius = 46
    margin = 58
    card = Image.new("RGBA", (size[0] + margin * 2, size[1] + margin * 2), (0, 0, 0, 0))
    shadow_mask = Image.new("L", card.size, 0)
    shadow_draw = ImageDraw.Draw(shadow_mask)
    shadow_draw.rounded_rectangle(
        (margin - 5, margin + 4, margin + size[0] + 5, margin + size[1] + 14),
        radius=radius + 5,
        fill=120,
    )
    shadow = Image.new("RGBA", card.size, (18, 18, 22, 0))
    shadow.putalpha(shadow_mask.filter(ImageFilter.GaussianBlur(30)))
    card.alpha_composite(shadow)

    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    background = Image.new("RGBA", size, (255, 255, 255, 255))
    background.putalpha(mask)
    card.alpha_composite(background, (margin, margin))
    screenshot.putalpha(mask)
    card.alpha_composite(screenshot, (margin, margin))
    edge = Image.new("RGBA", card.size, (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(
        (margin, margin, margin + size[0] - 1, margin + size[1] - 1),
        radius=radius,
        outline=(210, 210, 214, 135),
        width=2,
    )
    card.alpha_composite(edge)
    return card


@dataclass(frozen=True)
class Scene:
    start: float
    end: float
    title: str
    card: Image.Image
    rotation: float


def composite_rotated(canvas: Image.Image, image: Image.Image, center: tuple[float, float], angle: float, opacity: float) -> None:
    if opacity <= 0:
        return
    rotated = with_opacity(image, opacity).rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
    paste_center(canvas, rotated, center)


def render_intro(canvas: Image.Image, t: float, logo: Image.Image) -> None:
    path_progress = ease_in_out(phase(t, 0.12, 1.42))
    fade_out = 1.0 - ease_in_out(phase(t, 1.68, 2.12))
    route_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw_partial_path(
        route_layer,
        r_route_points(),
        path_progress,
        width=35,
        fill=(RED[0], RED[1], RED[2], int(255 * fade_out)),
        dot=t < 1.48,
    )
    canvas.alpha_composite(route_layer)

    logo_in = ease_out_back(phase(t, 1.17, 1.83))
    logo_out = 1.0 - ease_in_out(phase(t, 1.88, 2.18))
    if logo_in > 0 and logo_out > 0:
        width = max(4, int(428 * (0.82 + 0.18 * logo_in)))
        resized = logo.resize((width, width), Image.Resampling.LANCZOS)
        paste_center(canvas, with_opacity(resized, logo_in * logo_out), (WIDTH / 2, 930))

    caption_in = ease_out_cubic(phase(t, 0.82, 1.25))
    caption_out = 1.0 - ease_in_out(phase(t, 1.75, 2.05))
    text_center(canvas, "Bir R ile başlar.", 1392, 65, INK, bold=True, alpha=caption_in * caption_out)


def render_background_route(canvas: Image.Image, t: float, scene_index: int, opacity: float) -> None:
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    scale = 1.23 + scene_index * 0.04
    x_shift = (-95, 85, -65, 105)[scene_index]
    y_shift = (-8, 45, 70, 38)[scene_index]
    amount = 0.55 + 0.12 * math.sin(t * 0.85 + scene_index)
    draw_partial_path(
        layer,
        r_route_points(scale=scale, offset=(x_shift, y_shift)),
        amount,
        width=25,
        fill=(222, 25, 28, int(42 * opacity)),
    )
    layer = layer.filter(ImageFilter.GaussianBlur(0.7))
    canvas.alpha_composite(layer)


def render_scene(canvas: Image.Image, scene: Scene, t: float, index: int) -> None:
    fade_in = ease_out_cubic(phase(t, scene.start, scene.start + 0.38))
    fade_out = 1.0 - ease_in_out(phase(t, scene.end - 0.42, scene.end))
    opacity = fade_in * fade_out
    if opacity <= 0:
        return
    render_background_route(canvas, t, index, opacity)

    local = phase(t, scene.start, scene.end)
    enter = ease_out_back(phase(t, scene.start, scene.start + 0.58))
    leave = ease_in_out(phase(t, scene.end - 0.48, scene.end))
    scale = 0.86 + 0.14 * enter - 0.055 * leave
    width = max(2, int(scene.card.width * scale))
    height = max(2, int(scene.card.height * scale))
    card = scene.card.resize((width, height), Image.Resampling.LANCZOS)
    x = WIDTH / 2 + (1.0 - enter) * 210 - leave * 215
    float_y = math.sin((t - scene.start) * 1.8) * 8
    y = 1035 + (1.0 - enter) * 118 + leave * 35 + float_y
    angle = scene.rotation * (1.0 - enter) - scene.rotation * 0.35 * leave
    composite_rotated(canvas, card, (x, y), angle, opacity)

    title_in = ease_out_cubic(phase(t, scene.start + 0.14, scene.start + 0.50))
    title_out = 1.0 - ease_in_out(phase(t, scene.end - 0.62, scene.end - 0.28))
    title_opacity = title_in * title_out
    title_y = int(196 + (1.0 - title_in) * 36)
    text_center(canvas, scene.title, title_y, 78, INK, bold=True, alpha=title_opacity)
    dot_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(dot_layer)
    pill_w = 70
    d.rounded_rectangle(
        (WIDTH // 2 - pill_w // 2, title_y + 112, WIDTH // 2 + pill_w // 2, title_y + 120),
        radius=5,
        fill=(RED[0], RED[1], RED[2], int(210 * title_opacity)),
    )
    canvas.alpha_composite(dot_layer)


def render_montage(canvas: Image.Image, t: float, scenes: list[Scene], logo: Image.Image) -> None:
    intro = ease_out_cubic(phase(t, 9.28, 9.82))
    outro = 1.0 - ease_in_out(phase(t, 10.25, 10.72))
    opacity = intro * outro
    if opacity <= 0:
        return
    placements = [
        ((210, 625), -8.0, 0.30),
        ((815, 590), 7.0, 0.28),
        ((225, 1240), 7.5, 0.29),
        ((810, 1260), -6.5, 0.27),
    ]
    for scene, (center, angle, base_scale) in zip(scenes, placements):
        scale = base_scale * (0.82 + 0.18 * intro)
        card = scene.card.resize(
            (max(2, int(scene.card.width * scale)), max(2, int(scene.card.height * scale))),
            Image.Resampling.LANCZOS,
        )
        composite_rotated(canvas, card, center, angle * intro, opacity * 0.82)

    route = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw_partial_path(route, r_route_points(scale=0.73, offset=(0, 22)), intro, width=28, fill=(222, 25, 28, int(220 * opacity)), dot=False)
    canvas.alpha_composite(route)
    logo_scale = ease_out_back(phase(t, 9.62, 10.16))
    size = max(4, int(310 * (0.76 + 0.24 * logo_scale)))
    logo_frame = logo.resize((size, size), Image.Resampling.LANCZOS)
    paste_center(canvas, with_opacity(logo_frame, opacity * logo_scale), (WIDTH / 2, 942))


def render_final(canvas: Image.Image, t: float, logo: Image.Image) -> None:
    enter = ease_out_back(phase(t, 10.35, 11.05))
    if enter <= 0:
        return
    wipe = ease_in_out(phase(t, 10.26, 10.62))
    if wipe > 0:
        overlay = Image.new("RGBA", canvas.size, (248, 248, 246, int(255 * wipe)))
        canvas.alpha_composite(overlay)

    size = max(4, int(340 * (0.82 + 0.18 * enter)))
    final_logo = logo.resize((size, size), Image.Resampling.LANCZOS)
    paste_center(canvas, with_opacity(final_logo, enter), (WIDTH / 2, 735))
    text_center(canvas, "rotori", 1002, 154, INK, rounded=True, alpha=ease_out_cubic(phase(t, 10.72, 11.18)))
    text_center(canvas, "Sürpriz yok, plan var.", 1195, 58, MUTED, alpha=ease_out_cubic(phase(t, 11.02, 11.46)))

    line_p = ease_in_out(phase(t, 11.18, 11.68))
    line = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(line)
    half = int(80 * line_p)
    draw.rounded_rectangle((WIDTH // 2 - half, 1315, WIDTH // 2 + half, 1325), radius=5, fill=RED)
    canvas.alpha_composite(line)


def render_frame(t: float, logo: Image.Image, scenes: list[Scene]) -> Image.Image:
    canvas = Image.new("RGBA", (WIDTH, HEIGHT), BACKGROUND)
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((-190, 660, 1270, 1840), fill=(255, 45, 58, 11))
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(85)))

    if t < 2.2:
        render_intro(canvas, t, logo)
    for index, scene in enumerate(scenes):
        if scene.start - 0.02 <= t <= scene.end + 0.02:
            render_scene(canvas, scene, t, index)
    if 9.25 <= t <= 10.75:
        render_montage(canvas, t, scenes, logo)
    if t >= 10.25:
        render_final(canvas, t, logo)
    return canvas.convert("RGB")


def create_soundtrack(path: Path) -> None:
    sample_rate = 48_000
    count = int(DURATION * sample_rate)
    time = np.arange(count, dtype=np.float64) / sample_rate
    audio = np.zeros(count, dtype=np.float64)

    slow_envelope = np.sin(np.pi * np.clip(time / DURATION, 0.0, 1.0)) ** 1.4
    audio += 0.010 * slow_envelope * np.sin(2 * np.pi * 110 * time)
    audio += 0.006 * slow_envelope * np.sin(2 * np.pi * 220 * time + 0.7)

    rng = np.random.default_rng(20260814)
    noise = rng.normal(0.0, 1.0, count)
    kernel = np.ones(140) / 140
    smooth_noise = np.convolve(noise, kernel, mode="same")
    for moment in (1.88, 3.76, 5.66, 7.56, 9.46, 10.42):
        envelope = np.exp(-((time - moment) / 0.17) ** 2)
        audio += 0.18 * smooth_noise * envelope
        click_t = time - moment
        click_mask = (click_t >= 0) & (click_t < 0.18)
        audio[click_mask] += 0.045 * np.sin(2 * np.pi * 310 * click_t[click_mask]) * np.exp(-click_t[click_mask] * 22)

    for delay, frequency in ((0.00, 523.25), (0.13, 659.25), (0.27, 783.99), (0.43, 1046.50)):
        local = time - (10.46 + delay)
        mask = (local >= 0) & (local < 1.45)
        audio[mask] += 0.055 * np.sin(2 * np.pi * frequency * local[mask]) * np.exp(-local[mask] * 2.8)

    fade_out = np.clip((DURATION - time) / 0.42, 0.0, 1.0)
    audio *= fade_out
    peak = np.max(np.abs(audio)) or 1.0
    audio = np.clip(audio / peak * 0.42, -1.0, 1.0)
    pcm = (audio * 32767).astype("<i2")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(pcm.tobytes())


def create_preview(path: Path, frames: list[tuple[float, Image.Image]]) -> None:
    thumb_w, thumb_h = 270, 480
    preview = Image.new("RGB", (thumb_w * len(frames), thumb_h + 74), (238, 238, 236))
    draw = ImageDraw.Draw(preview)
    caption_font = font(28, bold=True)
    for index, (t, frame) in enumerate(frames):
        thumb = frame.resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        preview.paste(thumb, (index * thumb_w, 0))
        label = f"{t:.1f} sn"
        box = draw.textbbox((0, 0), label, font=caption_font)
        draw.text((index * thumb_w + (thumb_w - (box[2] - box[0])) / 2, thumb_h + 20), label, font=caption_font, fill=(60, 60, 64))
    preview.save(path, quality=90, optimize=True)


def build(repo_root: Path, output_path: Path) -> None:
    asset_root = repo_root / "rotori-social/assets/ads/rotori_r_apple"
    logo_path = repo_root / "rotori-mobile/assets/images/rotori-logo.png"
    logo = transparent_logo(logo_path)
    scenes = [
        Scene(1.82, 4.03, "Şehrini seç.", build_card(asset_root / "city_picker.png", 718), -1.8),
        Scene(3.72, 5.94, "Rotanı kur.", build_card(asset_root / "trip_days.png", 758), 1.4),
        Scene(5.63, 7.84, "Her adım belli.", build_card(asset_root / "day_timeline.png", 842), -1.1),
        Scene(7.54, 9.76, "Bütçen bile.", build_card(asset_root / "budget.png", 700), 1.1),
    ]

    output_path.parent.mkdir(parents=True, exist_ok=True)
    silent_path = output_path.with_name(output_path.stem + "_silent.mp4")
    audio_path = output_path.with_suffix(".wav")
    preview_path = output_path.with_name(output_path.stem + "_preview.jpg")
    poster_path = output_path.with_name(output_path.stem + "_poster.jpg")

    command = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{WIDTH}x{HEIGHT}",
        "-r", str(FPS), "-i", "-", "-an", "-c:v", "libx264",
        "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p",
        "-movflags", "+faststart", str(silent_path),
    ]
    process = subprocess.Popen(command, stdin=subprocess.PIPE)
    assert process.stdin is not None
    samples: list[tuple[float, Image.Image]] = []
    sample_times = (1.45, 2.90, 4.82, 6.73, 8.62, 11.55)
    sample_indices = {round(value * FPS): value for value in sample_times}
    total_frames = round(DURATION * FPS)
    try:
        for frame_index in range(total_frames):
            t = frame_index / FPS
            frame = render_frame(t, logo, scenes)
            if frame_index in sample_indices:
                samples.append((sample_indices[frame_index], frame.copy()))
            process.stdin.write(frame.tobytes())
    finally:
        process.stdin.close()
    if process.wait() != 0:
        raise RuntimeError("Sessiz video ffmpeg kodlaması başarısız oldu.")

    create_soundtrack(audio_path)
    subprocess.run(
        [
            "ffmpeg", "-y", "-loglevel", "error", "-i", str(silent_path), "-i", str(audio_path),
            "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart",
            str(output_path),
        ],
        check=True,
    )
    create_preview(preview_path, samples)
    render_frame(11.55, logo, scenes).save(poster_path, quality=94, optimize=True)
    silent_path.unlink(missing_ok=True)
    audio_path.unlink(missing_ok=True)
    print(output_path)
    print(preview_path)
    print(poster_path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    repo_root = Path(__file__).resolve().parents[2]
    default_output = repo_root / "rotori-social/output/reels/rotori_r_apple_ad_1080x1920.mp4"
    build(repo_root, (args.output or default_output).resolve())


if __name__ == "__main__":
    main()
