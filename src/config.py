from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml


@dataclass
class PathsCfg:
    video_source_dir: Path
    frames_dir: Path
    metadata_csv: Path
    plans_dir: Path
    output_dir: Path


@dataclass
class OllamaCfg:
    base_url: str
    vision_model: str
    text_model: str
    request_timeout_sn: int
    vision_concurrency: int


@dataclass
class DifyCfg:
    base_url: str
    api_key: str
    workflow_endpoint: str
    concurrency: int
    timeout_sn: int


@dataclass
class ReelsCfg:
    target_width: int
    target_height: int
    fps: int
    min_duration_sn: float
    max_duration_sn: float
    clip_per_reel: int
    crossfade_sn: float
    hook_duration_sn: float
    cta_duration_sn: float
    cta_text: str
    font: str
    font_alt: str = "/System/Library/Fonts/Supplemental/Arial Black.ttf"
    shadow_offset: int = 6
    stroke_width: int = 8


@dataclass
class PilotCfg:
    pilot_mode: bool
    pilot_count: int
    random_seed: int


@dataclass
class Config:
    paths: PathsCfg
    ollama: OllamaCfg
    dify: DifyCfg
    reels: ReelsCfg
    pilot: PilotCfg
    project_root: Path


def _resolve(base: Path, p: str) -> Path:
    path = Path(p)
    return path if path.is_absolute() else (base / path).resolve()


def load_config(config_path: str | None = None) -> Config:
    project_root = Path(__file__).resolve().parent.parent
    cfg_path = Path(config_path) if config_path else project_root / "config.yaml"
    with cfg_path.open("r", encoding="utf-8") as fh:
        raw: dict[str, Any] = yaml.safe_load(fh)

    p = raw["paths"]
    paths = PathsCfg(
        video_source_dir=_resolve(project_root, p["video_source_dir"]) if p["video_source_dir"] != "REPLACE_ME" else Path("REPLACE_ME"),
        frames_dir=_resolve(project_root, p["frames_dir"]),
        metadata_csv=_resolve(project_root, p["metadata_csv"]),
        plans_dir=_resolve(project_root, p["plans_dir"]),
        output_dir=_resolve(project_root, p["output_dir"]),
    )
    ollama = OllamaCfg(**raw["ollama"])
    dify = DifyCfg(**raw["dify"])
    reels = ReelsCfg(**raw["reels"])
    pilot = PilotCfg(**raw["pilot"])

    for d in (paths.frames_dir, paths.plans_dir, paths.output_dir, paths.metadata_csv.parent):
        d.mkdir(parents=True, exist_ok=True)

    return Config(paths=paths, ollama=ollama, dify=dify, reels=reels, pilot=pilot, project_root=project_root)


def require_video_source(cfg: Config) -> Path:
    if str(cfg.paths.video_source_dir) == "REPLACE_ME" or not cfg.paths.video_source_dir.exists():
        raise SystemExit(
            "config.yaml içindeki paths.video_source_dir alanını gerçek video klasörünüzle güncelleyin."
        )
    return cfg.paths.video_source_dir
