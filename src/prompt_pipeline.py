"""Prompt-driven Reels pipeline.

Kullanıcı serbest metinle "ne istediğini" yazar (örn. "Nara geyikleri hakkında
bir Reels", "Japon kültüründe pirincin önemi"), sistem:
  1. Metinden mekan_etiketi + ton çıkarır (labeling._KURALLAR üzerinden)
  2. metadata.csv'den eşleşen klipleri seçer (süre moduna göre)
  3. knowledge/japonya_tuyolar.md'yi tam içerik olarak yükler
  4. Dify workflow'una `kullanici_prompt + knowledge` ile birlikte çağrı atar
     (Dify yoksa lokal Ollama fallback)
  5. LLM çıktısını kullanıcı override'larıyla harmanlar (hook / cta / baslik /
     hashtagler alanları)
  6. step4_render.render_reel ile mp4 + .txt üretir
"""
from __future__ import annotations

import csv
import json
import re
import time
from pathlib import Path
from threading import Event
from typing import Any, Callable

import requests

from src import labeling
from src.config import Config, require_video_source
from src.utils.logging import get_logger

log = get_logger("prompt")

VIDEO_EXT = {".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm"}


# --- Süre modu tanımları -------------------------------------------------
SURE_MODU = {
    "kisa":  {"min": 15.0, "hedef": 20.0, "max": 25.0, "klip_min": 1, "klip_max": 3, "per_clip_cap": 10.0},
    "orta":  {"min": 30.0, "hedef": 35.0, "max": 40.0, "klip_min": 2, "klip_max": 4, "per_clip_cap": 15.0},
    "uzun":  {"min": 50.0, "hedef": 55.0, "max": 60.0, "klip_min": 3, "klip_max": 5, "per_clip_cap": 20.0},
}


# --- Ton (aciklama_tipi) heuristic -----------------------------------------
_TON_ANAHTARLARI: list[tuple[list[str], str]] = [
    (["sir", "bilinmeyen", "gizli", "kimse", "sasirtici", "trick", "keske bilseydik"], "merak_uyandir"),
    (["tanit", "gezin", "kalbi", "ruhu", "kultur", "gelenek", "tarih"], "bolgeyi_tanit"),
    (["nasil", "fiyat", "kac", "yen", "ne kadar", "ipucu", "tuyo", "yapmali"], "aciklayici"),
]


def _norm(text: str) -> str:
    text = (text or "").lower()
    repl = {"ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u", "İ": "i"}
    for a, b in repl.items():
        text = text.replace(a, b)
    return text


def parse_prompt(prompt: str) -> dict[str, Any]:
    """Kullanıcı promptundan mekan_etiketi + kategori + sehir + aciklama_tipi çıkar.

    Mekan tespiti: labeling._KURALLAR (aynı sözlük dosya adı için de kullanılan
    kurallar) prompt cümlesinde arar. İlk match → mekan.

    Ton: cümle içindeki anahtar sözcüklerden. Match yoksa 'aciklayici' default.
    """
    hay = _norm(prompt)

    mekan_etiketi = ""
    kategori = ""
    sehir = ""
    for keys, mekan, kat, seh in labeling._KURALLAR:
        if any(k in hay for k in keys):
            mekan_etiketi = mekan
            kategori = kat
            sehir = seh
            break

    ton = "aciklayici"
    for anahtar_listesi, ton_ad in _TON_ANAHTARLARI:
        if any(a in hay for a in anahtar_listesi):
            ton = ton_ad
            break

    return {
        "mekan_etiketi": mekan_etiketi,
        "kategori": kategori,
        "sehir": sehir,
        "aciklama_tipi": ton,
    }


# --- Klip seçimi -----------------------------------------------------------
def _read_metadata(csv_path: Path) -> list[dict[str, Any]]:
    if not csv_path.exists():
        return []
    with csv_path.open("r", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def _usable(dur: float, cap: float) -> float:
    return min(max(dur, 0.0), cap)


def select_clips(rows: list[dict[str, Any]], mekan_etiketi: str, sure_modu: str
                 ) -> tuple[list[dict[str, Any]], float]:
    """Metadata satırlarından mekan_etiketi'ne match edenleri süre moduna göre seç.

    Return: (seçilen satırlar, hedef toplam süre)
    """
    mode = SURE_MODU.get(sure_modu, SURE_MODU["orta"])

    matched = [r for r in rows if (r.get("mekan_etiketi") or "") == mekan_etiketi]
    if not matched:
        return [], mode["hedef"]

    # intro başa, geçiş/yavaş sona; eşitlikte uzun klip öne
    matched.sort(key=lambda r: (
        labeling.tip_sira(r.get("cekim_tipi", "normal")),
        -float(r.get("sure_sn", 0) or 0),
    ))

    picked: list[dict[str, Any]] = []
    total = 0.0
    for r in matched:
        if len(picked) >= mode["klip_max"]:
            break
        dur = _usable(float(r.get("sure_sn", 0) or 0), mode["per_clip_cap"])
        picked.append(r)
        total += dur
        if total >= mode["hedef"] and len(picked) >= mode["klip_min"]:
            break

    # klip_min doldurulamıyorsa: elimizdekiyle yetin (bilgi log'la)
    if len(picked) < mode["klip_min"] and matched:
        picked = matched[: mode["klip_min"]]
        total = sum(_usable(float(r.get("sure_sn", 0) or 0), mode["per_clip_cap"]) for r in picked)

    hedef_toplam = min(mode["max"], max(mode["min"], total)) if total > 0 else mode["hedef"]
    return picked, hedef_toplam


# --- Knowledge base yükleyici ---------------------------------------------
def _dify_alive(cfg: Config, timeout: float = 3.0) -> bool:
    """Dify API'ye hızlı bir bağlantı kontrolü. Yalnızca ping — payload atmaz.

    Uzun timeout beklemek yerine önden ağı test ediyoruz: erişilemezse
    direkt lokal Ollama'ya düşülür (kullanıcı Dify'ı henüz Publish etmemişse
    tipik durum)."""
    base = cfg.dify.base_url.rstrip("/")
    try:
        r = requests.get(f"{base}/v1/info", timeout=timeout,
                         headers={"Authorization": f"Bearer {cfg.dify.api_key}"})
        return r.status_code < 500
    except requests.RequestException:
        return False


def load_knowledge(project_root: Path) -> str:
    p = project_root / "knowledge" / "japonya_tuyolar.md"
    if not p.exists():
        return ""
    try:
        return p.read_text(encoding="utf-8")
    except OSError:
        return ""


# --- Slug + isim -----------------------------------------------------------
def _slug(text: str) -> str:
    tr = {"ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u"}
    for a, b in tr.items():
        text = text.replace(a, b).replace(a.upper(), b.upper())
    s = re.sub(r"[^A-Za-z0-9]+", "_", text).strip("_").lower()
    return s or "reel"


def _free_base_name(output_dir: Path, base: str) -> str:
    if not (output_dir / f"{base}.mp4").exists():
        return base
    i = 2
    while (output_dir / f"{base}_r{i}.mp4").exists():
        i += 1
    return f"{base}_r{i}"


# --- Override uygulaması ---------------------------------------------------
def _apply_overrides(plan: dict[str, Any], hook: str, overrides: dict[str, Any]) -> dict[str, Any]:
    """Kullanıcının verdiği alanlar LLM çıktısını override eder."""
    hook = (hook or "").strip()
    if hook:
        plan["hook"] = hook

    if not overrides:
        return plan
    if (o := (overrides.get("cta") or "").strip()):
        plan["cta"] = o
    if (o := (overrides.get("baslik") or "").strip()):
        # başlık = ilk overlay'in "baslik" stiliyle üstte gösterilmesi için
        plan["overlays"] = [{
            "saniye": 4.5, "metin": o, "sure": 3.5, "stil": "baslik", "renk": "beyaz",
        }] + [o for o in plan.get("overlays", []) if o.get("stil") != "baslik"]
    if (raw := overrides.get("hashtagler")):
        if isinstance(raw, str):
            tags = re.split(r"[\s,]+", raw)
        elif isinstance(raw, list):
            tags = raw
        else:
            tags = []
        cleaned = [re.sub(r"[^0-9A-Za-zçğıöşüÇĞİÖŞÜ]", "", str(t)).lower() for t in tags]
        plan["hashtagler"] = [t for t in cleaned if t][:12]
    return plan


# --- Ana runner ------------------------------------------------------------
def run_from_prompt(
    cfg: Config,
    prompt: str,
    hook: str,
    sure_modu: str,
    overrides: dict[str, Any] | None,
    emit: Callable[..., None],
    cancel: Event,
) -> None:
    """Web UI'dan çağrılır. JobManager.start_callable içinde koşar."""
    # ağır bağımlılıklar (moviepy) tembel yükle
    from src import step3_dify as step3
    from src import step4_render as step4
    from src.ollama_client import OllamaClient

    prompt = (prompt or "").strip()
    if not prompt:
        emit("Prompt boş — üretim iptal.", "error")
        return
    if sure_modu not in SURE_MODU:
        emit(f"Süre modu geçersiz: {sure_modu}. 'orta' varsayılıyor.", "warn")
        sure_modu = "orta"

    overrides = overrides or {}

    emit(f"① Prompt çözümleniyor: \"{prompt[:80]}{'…' if len(prompt) > 80 else ''}\"", "log")
    parsed = parse_prompt(prompt)
    mekan = parsed["mekan_etiketi"]
    if not mekan:
        emit("✖ Prompt'tan tanınabilir bir mekan çıkaramadım. "
             "Prompt'a 'Nara', 'Osaka', 'Fushimi', 'Shibuya' gibi bilinen bir mekan adı ekle.",
             "error")
        return
    emit(f"   → mekan: {mekan} · kategori: {parsed['kategori']} · ton: {parsed['aciklama_tipi']}", "info")

    emit(f"② Metadata okunuyor + klipler seçiliyor (süre modu: {sure_modu})…", "log")
    rows = _read_metadata(cfg.paths.metadata_csv)
    if not rows:
        emit("✖ metadata.csv boş/eksik. Önce step1_analyze'i çalıştır.", "error")
        return

    picked, hedef_sn = select_clips(rows, mekan, sure_modu)
    if not picked:
        emit(f"✖ '{mekan}' için metadata.csv'de klip bulunamadı.", "error")
        return
    emit(f"   → {len(picked)} klip seçildi, hedef süre {hedef_sn:.1f}s", "info")

    # source video path index
    try:
        source = require_video_source(cfg)
    except SystemExit as exc:
        emit(str(exc), "error")
        return

    if cancel.is_set():
        emit("İptal istendi — durduruldu.", "warn")
        return

    knowledge = load_knowledge(cfg.project_root)
    emit(f"③ Knowledge base yüklendi ({len(knowledge)} karakter)", "log")

    # group JSON'ı oluştur
    ts = int(time.time())
    base = _free_base_name(cfg.paths.output_dir, f"{_slug(mekan)}_{ts}")
    input_path = cfg.paths.plans_dir / f"{base}_input.json"
    group = {
        "mekan_etiketi": mekan,
        "kategori": parsed["kategori"],
        "sehir": parsed["sehir"],
        "idx": 0,
        "aciklama_tipi": parsed["aciklama_tipi"],
        "toplam_sure_sn": hedef_sn,
        "hedef_klip_sayisi": len(picked),
        "video_dosyalari": [c["dosya_adi"] for c in picked],
        "klip_sureleri": [float(c.get("sure_sn", 0) or 0) for c in picked],
        "cekim_tipleri": [c.get("cekim_tipi", "normal") for c in picked],
        "kullanici_prompt": prompt,
        "hook_manuel": (hook or "").strip(),
        "knowledge": knowledge,
    }
    input_path.write_text(json.dumps(group, ensure_ascii=False, indent=2), encoding="utf-8")
    emit(f"   → plan: {input_path.name}", "log")

    if cancel.is_set():
        emit("İptal istendi — durduruldu.", "warn")
        return

    emit("④ LLM → kurgu planı üretiliyor…", "log")
    client = OllamaClient(cfg.ollama.base_url, cfg.ollama.request_timeout_sn)
    use_dify = cfg.dify.api_key not in ("", "REPLACE_ME_APP_TOKEN") and _dify_alive(cfg)

    final_path = None
    if use_dify:
        emit("   Dify erişilebilir, workflow çağrılıyor…", "log")
        final_path = step3.process_group(cfg, input_path, use_dify=True, client=client, model="")
        if final_path is None:
            emit("   Dify başarısız — lokal Ollama fallback deniyor…", "warn")

    if final_path is None:
        model = step3.pick_text_model(cfg, client)
        emit(f"   Lokal üretim modeli: {model}", "log")
        final_path = step3.process_group(cfg, input_path, use_dify=False, client=client, model=model)

    if final_path is None:
        emit("✖ Kurgu planı üretilemedi (hem Dify hem lokal başarısız).", "error")
        return

    # override uygula
    data = json.loads(final_path.read_text(encoding="utf-8"))
    plan = data.get("kurgu_json") or {}
    plan = _apply_overrides(plan, hook, overrides)
    data["kurgu_json"] = plan
    final_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    if plan.get("hook"):
        emit(f"   → hook: \"{plan['hook']}\"", "info")

    if cancel.is_set():
        emit("İptal istendi — render başlatılmadı.", "warn")
        return

    # source video index
    emit("⑤ Kaynak video indeksi hazırlanıyor…", "log")
    name_index: dict[str, Path] = {}
    for p in source.rglob("*"):
        if p.is_file() and p.suffix.lower() in VIDEO_EXT:
            name_index[p.name] = p
    emit(f"   → {len(name_index)} dosya indekslendi", "log")

    emit("⑥ Render başlıyor…", "log")
    out = step4.render_reel(final_path, cfg, source, name_index)
    if out is None:
        emit("✖ Render başarısız.", "error")
        return
    emit(f"✓ Hazır: {out.name} — Onay kuyruğunda", "info")
