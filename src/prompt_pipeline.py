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


# Prompt'ta aranan spesifik konu anahtarları (semantic fallback için).
# Sözlükte match yoksa sahne_ozeti'nde bu terimlerin geçtiği klipleri arıyoruz.
_STOP_WORDS = {
    "bir", "hakkinda", "hakkında", "icin", "için", "reels", "video", "kısa",
    "kisa", "uzun", "orta", "mutlaka", "bilmeniz", "gereken", "bilinmesi", "sey",
    "şey", "en", "ne", "cok", "çok", "ve", "ile", "japon", "japonya", "japonyadaki",
    "japonyada",
}


def _prompt_keywords(prompt: str) -> list[str]:
    """Prompt'tan aramaya değer anahtar kelimeleri çıkar (stop-word'süz, min 3 karakter)."""
    words = re.findall(r"[a-zçğıöşü]+", _norm(prompt))
    return [w for w in words if len(w) >= 3 and w not in _STOP_WORDS]


def _semantic_score_row(r: dict[str, Any], kws: list[str]) -> int:
    """Bir metadata satırının prompt anahtar kelimeleriyle puanı.
    sahne_ozeti (Türkçe cümle) + sahne_ogeleri (öge listesi) +
    sahne_mekan_tahmini alanlarında match arar."""
    text = " ".join([
        _norm(r.get("sahne_ozeti", "") or ""),
        _norm(r.get("sahne_ogeleri", "") or ""),
        _norm(r.get("sahne_mekan_tahmini", "") or ""),
    ])
    if not text.strip():
        return 0
    return sum(1 for k in kws if k in text)


def _semantic_match(rows: list[dict[str, Any]], prompt: str) -> tuple[str | None, list[dict[str, Any]]]:
    """Sözlük eşleşmediyse veya eşleşen mekana ait klip yoksa devreye girer.

    Return: (secilen_mekan_etiketi, secilen_satirlar_orijinal_puanla)
    - secilen_satirlar: puanı > 0 olan satırlar, puana göre azalan sıra
    - secilen_mekan: en çok puan alan mekan_etiketi (görsel/label için)
    """
    kws = _prompt_keywords(prompt)
    if not kws:
        return None, []

    # her satır için puan hesapla
    scored: list[tuple[int, dict[str, Any]]] = []
    for r in rows:
        s = _semantic_score_row(r, kws)
        if s > 0:
            scored.append((s, r))

    if not scored:
        return None, []

    scored.sort(key=lambda x: (-x[0], -float(x[1].get("sure_sn", 0) or 0)))

    # etiket seçimi: en çok görülen mekan_etiketi
    from collections import Counter
    label_counts = Counter(r.get("mekan_etiketi", "") for _, r in scored)
    best_label = label_counts.most_common(1)[0][0]

    # dönen satırlar: sadece puan sırasına göre
    return best_label, [r for _, r in scored]


# --- Klip seçimi -----------------------------------------------------------
def _read_metadata(csv_path: Path) -> list[dict[str, Any]]:
    if not csv_path.exists():
        return []
    with csv_path.open("r", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def _usable(dur: float, cap: float) -> float:
    return min(max(dur, 0.0), cap)


def _pick_from_scored(scored_rows: list[dict[str, Any]], sure_modu: str
                      ) -> tuple[list[dict[str, Any]], float]:
    """Semantic search sonucu puanı > 0 satırlardan TEK klip seç.
    Klipleri birleştirmiyoruz — sadece en yüksek puanlı klibi alıp süre moduna
    göre trim ediyoruz (kliplerin doğal süresi < mode.max ise olduğu gibi kalır)."""
    if not scored_rows:
        return [], SURE_MODU.get(sure_modu, SURE_MODU["orta"])["hedef"]
    mode = SURE_MODU.get(sure_modu, SURE_MODU["orta"])
    picked = [scored_rows[0]]
    dur = float(picked[0].get("sure_sn", 0) or 0)
    hedef = min(mode["max"], dur) if dur > 0 else mode["hedef"]
    return picked, hedef


def select_clips(rows: list[dict[str, Any]], mekan_etiketi: str, sure_modu: str
                 ) -> tuple[list[dict[str, Any]], float]:
    """Metadata satırlarından mekan_etiketi'ne match eden TEK klip seç.

    Tasarım kararı: kullanıcı 'birden fazla klibi birleştirme' istedi, çünkü
    kesitler videonun akışını bozuyor. Bunun yerine tek klibi olduğu gibi
    render'a veriyoruz, üstüne sadece overlay/hook text bindiriyoruz.

    Return: ([tek klip], hedef süre — klibin doğal süresiyle mode.max min'i)
    """
    mode = SURE_MODU.get(sure_modu, SURE_MODU["orta"])

    matched = [r for r in rows if (r.get("mekan_etiketi") or "") == mekan_etiketi]
    if not matched:
        return [], mode["hedef"]

    # intro/normal → yakin → yürüyüş → geçiş → yavaş. Eşitlikte SÜRE MODUNA
    # yakın olan klip başa (kullanıcı "kısa" isterse kısa klip; "uzun"da uzun).
    hedef_sure = mode["hedef"]
    matched.sort(key=lambda r: (
        labeling.tip_sira(r.get("cekim_tipi", "normal")),
        abs(float(r.get("sure_sn", 0) or 0) - hedef_sure),
    ))

    picked = [matched[0]]
    dur = float(picked[0].get("sure_sn", 0) or 0)
    hedef_toplam = min(mode["max"], dur) if dur > 0 else mode["hedef"]
    return picked, hedef_toplam


# --- Knowledge base yükleyici ---------------------------------------------
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

    emit("② Metadata okunuyor + klipler seçiliyor (süre modu: %s)…" % sure_modu, "log")
    rows = _read_metadata(cfg.paths.metadata_csv)
    if not rows:
        emit("✖ metadata.csv boş/eksik. Önce step1_analyze'i çalıştır.", "error")
        return

    picked: list[dict[str, Any]] = []
    hedef_sn: float = 0.0

    # 1) Sözlük eşleşmesi varsa → önce ondan klip aramaya çalış
    if mekan:
        emit(f"   → sözlük eşleşmesi: {mekan} · kategori: {parsed['kategori']} · ton: {parsed['aciklama_tipi']}", "info")
        picked, hedef_sn = select_clips(rows, mekan, sure_modu)

    # 2) Klip yoksa (sözlük yakaladı ama arşivde etiketli klip yok, ya da hiç
    #    eşleşme olmadı) → sahne_ozeti + sahne_ogeleri üzerinde semantic search.
    #    Bu kez mekan_etiketi ile filter yerine puanı > 0 olan spesifik satırları
    #    doğrudan klip listesi olarak kullanıyoruz — böylece aynı mekan altındaki
    #    farklı konulu videolarda doğru olanı seçebiliyoruz.
    if not picked:
        emit("   Sözlük yolu boş — sahne özetlerinde anahtar kelime araması yapılıyor…", "log")
        alt_mekan, alt_rows = _semantic_match(rows, prompt)
        if alt_rows:
            emit(f"   → semantic hit: {len(alt_rows)} klip puanlandı, en yaygın etiket: {alt_mekan}", "info")
            # süre moduna göre puanı en yüksek olanlardan alt kümeyi al
            picked, hedef_sn = _pick_from_scored(alt_rows, sure_modu)
            if picked:
                mekan = alt_mekan or "Karışık"
                # kategori/sehir devral
                if not parsed["kategori"]:
                    parsed["kategori"] = picked[0].get("kategori", "")
                    parsed["sehir"] = picked[0].get("sehir", "")

    if not mekan:
        emit("✖ Prompt'tan tanınabilir bir mekan çıkaramadım ve sahne özetlerinde de "
             "eşleşme yok. 'Nara', 'Osaka', 'Fushimi', 'Shibuya' gibi bir mekan adı ekle "
             "veya `python -m src.step1_analyze --enrich-scenes` ile sahne özetlerini üret.",
             "error")
        return
    if not picked:
        emit(f"✖ '{mekan}' için hiçbir klip bulunamadı (ne mekan_etiketi ne sahne_ozeti eşleşti).", "error")
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

    emit("④ LLM (lokal Ollama) → kurgu planı üretiliyor…", "log")
    client = OllamaClient(cfg.ollama.base_url, cfg.ollama.request_timeout_sn)
    model = step3.pick_text_model(cfg, client)
    emit(f"   model: {model}", "log")

    final_path = step3.process_group(cfg, input_path, use_dify=False, client=client, model=model)
    if final_path is None:
        emit("✖ Kurgu planı üretilemedi.", "error")
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
