"""Web UI'dan çağrılan analiz akışı — step1_analyze.py'nin dışarı açılmış
runner versiyonu.

Adımlar:
  1. Video kaynağını tara → metadata.csv'de olmayan yeni dosyaları bul
  2. Her yeni dosya için etiketle (labeling.parse_filename → vision fallback)
  3. Opsiyonel: sahne özetleri üret (multi-frame + qwen sentez)

`JobManager.start_callable` içinde emit/cancel parametreleriyle çalışır.
Log satırları web dashboard'un "Canlı Süreç" panelinde akar.
"""
from __future__ import annotations

from threading import Event
from typing import Callable

from src.config import Config, require_video_source
from src.ollama_client import OllamaClient
from src.utils.logging import get_logger

log = get_logger("analyze")


def run_analyze(cfg: Config, emit: Callable[..., None], cancel: Event,
                enrich: bool = True) -> None:
    # ağır bağımlılıklar tembel yüklensin
    from src import step1_analyze as s1

    try:
        source = require_video_source(cfg)
    except SystemExit as exc:
        emit(str(exc), "error")
        return

    client = OllamaClient(cfg.ollama.base_url, cfg.ollama.request_timeout_sn)
    if not client.health():
        emit("⚠️ Ollama erişilemiyor — vision fallback ve sahne özeti devre dışı.", "warn")

    # ---- 1) yeni video keşfi + baseline analiz ----
    emit("① Kaynak klasörü taranıyor…", "log")
    videos = s1.scan_videos(source)
    emit(f"   → {len(videos)} benzersiz video bulundu", "info")

    seen = s1.load_seen(cfg.paths.metadata_csv)
    todo = [v for v in videos if v.name not in seen]
    emit(f"   → CSV'de olan: {len(seen)}, yeni: {len(todo)}", "info")

    if todo:
        emit(f"② Yeni {len(todo)} video etiketleniyor…", "log")
        for i, v in enumerate(todo, 1):
            if cancel.is_set():
                emit("⏹ İptal edildi.", "warn")
                return
            try:
                row = s1.analyze_one(v, source, cfg, client)
            except Exception as exc:
                emit(f"   ✗ [{i}/{len(todo)}] {v.name}: {exc}", "error")
                continue
            if row is None:
                emit(f"   ✗ [{i}/{len(todo)}] {v.name}: analiz başarısız", "error")
                continue
            s1.append_row(cfg.paths.metadata_csv, row)
            emit(f"   ✓ [{i}/{len(todo)}] {row['dosya_adi']} → {row['mekan_etiketi']} ({row['kaynak']})",
                 "log")
    else:
        emit("② Yeni video yok — hepsi zaten metadata.csv'de.", "info")

    if cancel.is_set():
        emit("⏹ İptal edildi.", "warn")
        return

    # ---- 3) sahne özetleri (opsiyonel) ----
    if not enrich:
        emit("Sahne özeti atlandı (enrich=False).", "info")
        return

    if not client.health():
        emit("Ollama yok, sahne özeti atlanıyor.", "warn")
        return

    emit("③ Sahne özetleri üretiliyor (multi-frame → llava → qwen sentez)…", "log")
    # _enrich_scenes zaten kendi progress log'unu emit ediyor (bridge sayesinde
    # step1 logger'ı JobManager canlı akışına düşüyor)
    try:
        s1._enrich_scenes(cfg, source, limit=None)
    except SystemExit as exc:
        emit(f"✖ Sahne özeti hatası: {exc}", "error")
        return

    emit("✅ Analiz tamamlandı.", "info")
