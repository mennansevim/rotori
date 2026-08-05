from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass
class VideoInfo:
    path: Path
    duration_sn: float
    width: int
    height: int
    fps: float


def probe(video_path: Path) -> VideoInfo:
    cmd = [
        "ffprobe", "-v", "error", "-print_format", "json",
        "-show_streams", "-show_format", str(video_path),
    ]
    out = subprocess.check_output(cmd, stderr=subprocess.STDOUT).decode()
    data = json.loads(out)
    v_stream = next((s for s in data["streams"] if s["codec_type"] == "video"), None)
    if v_stream is None:
        raise ValueError(f"No video stream: {video_path}")
    duration = float(data["format"].get("duration", 0.0) or v_stream.get("duration", 0.0) or 0.0)
    fps_expr = v_stream.get("avg_frame_rate", "0/1")
    num, _, den = fps_expr.partition("/")
    fps = (float(num) / float(den)) if den and float(den) != 0 else 0.0
    return VideoInfo(
        path=video_path,
        duration_sn=round(duration, 3),
        width=int(v_stream["width"]),
        height=int(v_stream["height"]),
        fps=round(fps, 3),
    )


def extract_first_frame(video_path: Path, out_jpg: Path, at_sn: float = 1.0) -> Path:
    out_jpg.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-ss", str(at_sn), "-i", str(video_path),
        "-frames:v", "1", "-q:v", "3",
        str(out_jpg),
    ]
    subprocess.check_call(cmd)
    return out_jpg
