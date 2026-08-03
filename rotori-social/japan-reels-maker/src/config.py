from __future__ import annotations

import os
from dataclasses import dataclass, field
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
    ready_dir: Path


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
    aciklama_tipi: str = "aciklayici"


@dataclass
class OpenAICfg:
    api_key: str
    model: str = "gpt-4o-mini"
    base_url: str = "https://api.openai.com/v1"
    timeout_sn: int = 60


@dataclass
class InstagramCfg:
    username: str
    password: str
    totp_secret: str = ""    # 2FA aktifse authenticator app "elle setup" secret
    # Tarayıcıdaki oturumun sessionid cookie'si. Doluysa login akışı (CAA/Bloks
    # + 2FA + checkpoint) TAMAMEN atlanır — instagrapi bu cookie ile direkt
    # oturum açar. Instagram login'i sürekli reddediyorsa en güvenilir yol.
    sessionid: str = ""
    session_file: str = "data/instagram_session.json"
    uploads_log: str = "data/instagram_uploads.jsonl"
    # Instagram Graph API (resmi, Business Login) — instagrapi'nin alternatifi.
    # Yeni yayın akışı bunu kullanır: /media (container) → /media_publish.
    # Token: Instagram Business Login ile alınmış long-lived access token (~60g).
    graph_token: str = ""
    ig_user_id: str = ""       # Instagram Business account ID (17 haneli)
    app_secret: str = ""       # Long-lived refresh + debug için
    # Otomatik yenilenen token'ın saklandığı YAZILABİLİR dosya. config.yaml
    # container'da read-only mount edildiğinden, haftalık otomasyon token'ı
    # yeniler ve buraya yazar. Bu dosya VARSA graph_token'ı override eder.
    graph_token_file: str = "data/graph_token.txt"
    # Kart JPG'sine Instagram'ın erişebilmesi için public HTTPS URL tabanı.
    # (Cloudflare tunnel, ngrok, Cloudinary vb.) Yayın anında image_url =
    # f"{public_base_url}/media/stories/<name>" olarak kullanılır.
    public_base_url: str = ""


@dataclass
class StoriesCfg:
    output_dir: Path
    backgrounds_dir: Path | None = None    # kullanıcının yüklediği Japan görseller
    width: int = 1080
    height: int = 1920
    handle: str = "@mennansjapan"


@dataclass
class UnsplashCfg:
    access_key: str
    queries: list[str]
    per_query: int = 3
    orientation: str = "portrait"


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
    footer_text: str = ""   # her reel'de sabit alt imza; boşsa footer basılmaz
    # False (default): video temiz kalır — hook, overlay, footer ekrana BASILMAZ.
    # Kullanıcı Instagram uygulamasında caption'ı kendi yazar/düzenler.
    # True: eski davranış — hook + footer video üzerine gömülür.
    add_overlays: bool = False


@dataclass
class PilotCfg:
    pilot_mode: bool
    pilot_count: int
    random_seed: int


@dataclass
class RunCfg:
    max_videos_per_run: int = 10


@dataclass
class TikTokCfg:
    access_token: str = ""          # OAuth2 access token (24 saat geçerli)
    refresh_token: str = ""         # 365 gün geçerli; yenilemek için kullanılır
    open_id: str = ""               # TikTok kullanıcı ID'si
    client_key: str = ""
    client_secret: str = ""
    uploads_log: str = "data/tiktok_uploads.jsonl"


@dataclass
class SchedulerCfg:
    enabled: bool = False
    daily_limit: int = 2                   # günde max kaç Reels yayınlanır
    default_times: list[str] = field(default_factory=lambda: ["08:00", "18:00"])
    auto_upload: bool = False              # True → Instagram upload otomatik tetiklenir
    queue_file: str = "data/scheduler_queue.json"
    check_interval_sn: int = 60            # background thread kontrol aralığı (saniye)


# Varsayılan Japonya haber RSS feed'leri.
# Pratik seyahat/tasarruf feed'leri (para-zaman-güvenlik faydası — editöryel
# kalite kapısına uygun) + genel kültür/güncel karışım:
#   Tokyo Cheapo   → ulaşım, IC kart, tasarruf, pratik ipuçları (birebir on-brand)
#   SoraNews24     → kültür/yaşam/seyahat
#   Nippon.com     → kültür/toplum
#   Japan Today    → genel güncel
_DEFAULT_NEWS_FEEDS = [
    "https://tokyocheapo.com/feed/",
    "https://soranews24.com/feed/",
    "https://www.nippon.com/en/feed/",
    "https://japantoday.com/feed",
]


@dataclass
class NewsCfg:
    enabled: bool = True
    feeds: list[str] = field(default_factory=lambda: list(_DEFAULT_NEWS_FEEDS))
    lookback_days: int = 2      # son N günün haberleri dikkate alınır
    max_candidates: int = 40    # GPT'ye sunulacak aday haber sayısı (geniş havuz)
    # ---- Karma kalite profili (haftalık/manuel çalışma için) ----
    # RSS haberleri + evergreen konular AYNI kalite kapısından geçer, en yüksek
    # puanlı kazanır. Env (NEWS_RSS_TRIES vb.) bu değerleri override eder.
    rss_tries: int = 6          # kaç RSS haberi puanlanıp yarışa girsin
    evergreen_enabled: bool = True   # evergreen konu havuzu yarışa katılsın mı
    evergreen_tries: int = 6    # kaç evergreen konu puanlanıp yarışa girsin
    gate_timeout_sec: int = 180  # karma yarışma için toplam süre limiti (sn)


@dataclass
class Config:
    paths: PathsCfg
    ollama: OllamaCfg
    dify: DifyCfg
    reels: ReelsCfg
    pilot: PilotCfg
    run: RunCfg
    project_root: Path
    openai: OpenAICfg | None = None
    instagram: InstagramCfg | None = None
    stories: "StoriesCfg | None" = None
    unsplash: "UnsplashCfg | None" = None
    # "Drive'a Gönder" hedefi — yerel senkron klasör yolu (Google Drive Desktop /
    # OneDrive vb.). Dosyalar buraya kopyalanır, bulut uygulaması otomatik yükler.
    drive_folder: Path | None = None
    news: "NewsCfg | None" = None    # haber otomasyonu ayarları
    scheduler: "SchedulerCfg | None" = None   # reels posting scheduler
    tiktok: "TikTokCfg | None" = None         # tiktok cross-posting


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
        ready_dir=_resolve(project_root, p.get("ready_dir", "output/ready_to_publish")),
    )
    ollama = OllamaCfg(**raw["ollama"])
    dify = DifyCfg(**raw["dify"])
    reels = ReelsCfg(**raw["reels"])
    # Platform bağımsız font — config'teki path yoksa (ör. macOS fontu Pi'de
    # yok) gömülü assets/fonts'a düş. Böylece Docker/Linux'ta da render çalışır.
    _font_bundled = project_root / "assets" / "fonts" / "ChunkFive.otf"
    _font_alt_bundled = project_root / "assets" / "fonts" / "Oswald-VariableFont.ttf"
    if not Path(reels.font).exists() and _font_bundled.exists():
        reels.font = str(_font_bundled)
    if not Path(reels.font_alt).exists() and _font_alt_bundled.exists():
        reels.font_alt = str(_font_alt_bundled)
    pilot = PilotCfg(**raw["pilot"])
    run = RunCfg(**raw.get("run", {}))

    openai_raw = raw.get("openai") or {}
    openai_cfg: OpenAICfg | None = None
    if openai_raw.get("api_key") and openai_raw["api_key"] not in ("", "REPLACE_ME_OPENAI_KEY"):
        openai_cfg = OpenAICfg(**openai_raw)

    ig_raw = raw.get("instagram") or {}
    ig_cfg: InstagramCfg | None = None
    if (ig_raw.get("username") and ig_raw["username"] not in ("", "REPLACE_ME_USERNAME")
            and ig_raw.get("password") and ig_raw["password"] not in ("", "REPLACE_ME_PASSWORD")):
        ig_cfg = InstagramCfg(**ig_raw)
        # Otomatik yenilenen token dosyası varsa config.yaml'daki graph_token'ı
        # EZ (read-only mount'ta bile çalışır — dosya writable data/ altında).
        try:
            tok_path = _resolve(project_root, ig_cfg.graph_token_file)
            if tok_path.exists():
                saved = tok_path.read_text(encoding="utf-8").strip()
                if saved:
                    ig_cfg.graph_token = saved
        except OSError:
            pass

    stories_raw = raw.get("stories") or {}
    stories_cfg: StoriesCfg | None = None
    if stories_raw:
        stories_output = _resolve(project_root,
                                  stories_raw.get("output_dir", "output/stories"))
        stories_output.mkdir(parents=True, exist_ok=True)
        bg_dir = None
        if stories_raw.get("backgrounds_dir"):
            bg_dir = _resolve(project_root, stories_raw["backgrounds_dir"])
            bg_dir.mkdir(parents=True, exist_ok=True)
        stories_cfg = StoriesCfg(
            output_dir=stories_output,
            backgrounds_dir=bg_dir,
            width=int(stories_raw.get("width", 1080)),
            height=int(stories_raw.get("height", 1920)),
            handle=str(stories_raw.get("handle", "@mennansjapan")),
        )

    for d in (paths.frames_dir, paths.plans_dir, paths.output_dir, paths.ready_dir, paths.metadata_csv.parent):
        d.mkdir(parents=True, exist_ok=True)

    unsplash_raw = raw.get("unsplash") or {}
    unsplash_cfg: UnsplashCfg | None = None
    if (unsplash_raw.get("access_key")
            and unsplash_raw["access_key"] not in ("", "REPLACE_ME_UNSPLASH_KEY")):
        unsplash_cfg = UnsplashCfg(
            access_key=unsplash_raw["access_key"],
            queries=list(unsplash_raw.get("queries") or []),
            per_query=int(unsplash_raw.get("per_query", 3)),
            orientation=str(unsplash_raw.get("orientation", "portrait")),
        )

    # Drive'a Gönder hedef klasörü (yerel senkron yolu)
    drive_raw = raw.get("drive") or {}
    drive_folder: Path | None = None
    _df = (drive_raw.get("folder") or "").strip()
    if _df and _df not in ("", "REPLACE_ME_DRIVE_FOLDER"):
        drive_folder = _resolve(project_root, _df)

    # Haber otomasyonu
    news_raw = raw.get("news_automation") or {}
    news_cfg = NewsCfg(
        enabled=bool(news_raw.get("enabled", True)),
        feeds=list(news_raw.get("feeds") or _DEFAULT_NEWS_FEEDS),
        lookback_days=int(news_raw.get("lookback_days", 2)),
        max_candidates=int(news_raw.get("max_candidates", 25)),
        rss_tries=int(news_raw.get("rss_tries", 6)),
        evergreen_enabled=bool(news_raw.get("evergreen_enabled", True)),
        evergreen_tries=int(news_raw.get("evergreen_tries", 6)),
        gate_timeout_sec=int(news_raw.get("gate_timeout_sec", 180)),
    )

    return Config(paths=paths, ollama=ollama, dify=dify, reels=reels, pilot=pilot,
                  run=run, project_root=project_root, openai=openai_cfg,
                  instagram=ig_cfg, stories=stories_cfg, unsplash=unsplash_cfg,
                  drive_folder=drive_folder, news=news_cfg,
                  scheduler=_load_scheduler_cfg(raw),
                  tiktok=_load_tiktok_cfg(raw))


def _load_scheduler_cfg(raw: dict[str, Any]) -> "SchedulerCfg | None":
    sched_raw = raw.get("scheduler") or {}
    if not sched_raw:
        return None
    return SchedulerCfg(
        enabled=bool(sched_raw.get("enabled", False)),
        daily_limit=int(sched_raw.get("daily_limit", 2)),
        default_times=list(sched_raw.get("default_times") or ["08:00", "18:00"]),
        auto_upload=bool(sched_raw.get("auto_upload", False)),
        queue_file=str(sched_raw.get("queue_file", "data/scheduler_queue.json")),
        check_interval_sn=int(sched_raw.get("check_interval_sn", 60)),
    )


def _load_tiktok_cfg(raw: dict[str, Any]) -> "TikTokCfg | None":
    tt_raw = raw.get("tiktok") or {}
    if not tt_raw:
        return None
    access_token = str(tt_raw.get("access_token", "")).strip()
    if not access_token or access_token == "REPLACE_ME":
        return None
    return TikTokCfg(
        access_token=access_token,
        refresh_token=str(tt_raw.get("refresh_token", "")),
        open_id=str(tt_raw.get("open_id", "")),
        client_key=str(tt_raw.get("client_key", "")),
        client_secret=str(tt_raw.get("client_secret", "")),
        uploads_log=str(tt_raw.get("uploads_log", "data/tiktok_uploads.jsonl")),
    )


def require_video_source(cfg: Config) -> Path:
    if str(cfg.paths.video_source_dir) == "REPLACE_ME" or not cfg.paths.video_source_dir.exists():
        raise SystemExit(
            "config.yaml içindeki paths.video_source_dir alanını gerçek video klasörünüzle güncelleyin."
        )
    return cfg.paths.video_source_dir
