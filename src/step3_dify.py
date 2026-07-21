from __future__ import annotations

import argparse
import json
import re
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any

import requests
from tqdm import tqdm

from src import persona
from src.config import Config, load_config
from src.ollama_client import OllamaClient
from src.utils.logging import get_logger

log = get_logger("step3")

# Daha iyi Türkçe için varsa bu modeli tercih et
_PREFERRED_TEXT_MODELS = ["qwen2.5:7b", "qwen2.5:7b-instruct"]


def call_dify(cfg: Config, group: dict[str, Any]) -> dict[str, Any]:
    url = f"{cfg.dify.base_url.rstrip('/')}{cfg.dify.workflow_endpoint}"
    headers = {"Authorization": f"Bearer {cfg.dify.api_key}", "Content-Type": "application/json"}
    payload = {
        "inputs": {
            "mekan_etiketi": group["mekan_etiketi"],
            "video_dosyalari": ", ".join(group["video_dosyalari"]),
            "toplam_sure_sn": group["toplam_sure_sn"],
            "aciklama_tipi": group.get("aciklama_tipi", cfg.dify.aciklama_tipi),
            "kullanici_prompt": group.get("kullanici_prompt", ""),
            "knowledge": group.get("knowledge", ""),
        },
        "response_mode": "blocking",
        "user": "reels-maker",
    }
    last_err: Exception | None = None
    for attempt in range(3):
        try:
            resp = requests.post(url, headers=headers, json=payload, timeout=cfg.dify.timeout_sn)
            resp.raise_for_status()
            data = resp.json()
            return data.get("data", {}).get("outputs", {}) or data.get("outputs", {})
        except (requests.RequestException, ValueError) as exc:
            last_err = exc
            time.sleep(2 ** attempt)
    raise RuntimeError(f"Dify tüm denemeler başarısız: {last_err}")


def pick_text_model(cfg: Config, client: OllamaClient) -> str:
    try:
        r = requests.get(f"{cfg.ollama.base_url.rstrip('/')}/api/tags", timeout=5)
        names = {m["name"] for m in r.json().get("models", [])}
        for m in _PREFERRED_TEXT_MODELS:
            if m in names:
                return m
    except requests.RequestException:
        pass
    return cfg.ollama.text_model


def _extract_json(text: str) -> dict[str, Any]:
    m = re.search(r"\{.*\}", text, re.DOTALL)
    if not m:
        raise ValueError(f"JSON bulunamadı: {text[:200]}")
    return json.loads(m.group(0))


def _words_max(text: str, n: int) -> str:
    words = str(text).strip().strip('"').strip("'").split()
    return " ".join(words[:n]).strip(" .,-–—")


def _clean_hashtags(raw: Any, seed_tags: list[str]) -> list[str]:
    tags: list[str] = []
    if isinstance(raw, str):
        raw = re.split(r"[\s,]+", raw)
    if isinstance(raw, list):
        for t in raw:
            t = re.sub(r"[^0-9A-Za-zçğıöşüÇĞİÖŞÜ]", "", str(t)).lower()
            if t and t not in tags:
                tags.append(t)
    for t in seed_tags:
        if len(tags) >= 10:
            break
        if t not in tags:
            tags.append(t)
    return tags[:12]


def _build_overlays(texts: list[str], total: float, cfg: Config) -> list[dict[str, Any]]:
    texts = [t for t in (_words_max(x, 4) for x in texts) if t]
    texts = texts[:5]
    if len(texts) < 2:
        return []
    start_min = max(cfg.reels.hook_duration_sn + 1.5, 4.5)
    end_max = max(start_min + 2.0, total - cfg.reels.cta_duration_sn - 3.0)
    n = len(texts)
    gap = (end_max - start_min) / n if n else 0
    sure = min(3.2, max(2.5, gap * 0.8)) if gap > 0 else 3.0

    overlays: list[dict[str, Any]] = []
    for i, t in enumerate(texts):
        start = round(start_min + i * gap, 1) if gap > 0 else round(start_min + i * 3.3, 1)
        if start + sure >= total:
            break
        overlays.append({
            "saniye": start,
            "metin": t,
            "sure": round(sure, 1),
            "stil": "baslik" if i % 2 == 0 else "vurgu",
            "renk": "kirmizi" if i == 0 else "sari",
        })
    return overlays


def _aciklama_fallback(mekan: str, tips: list[str]) -> str:
    body = " ".join(t.strip() for t in tips[:3] if t.strip())
    lead = f"{mekan} bizim için gezinin sürprizlerinden biriydi."
    plug = "Bu tür detayları ailece 13 günde biriktirdik, burada paylaşıyorum 👇"
    return " ".join(x for x in [lead, body, plug] if x).strip()


def _sanitize_aciklama(text: str, mekan: str, tips: list[str]) -> str:
    text = (text or "").strip()
    parts = re.split(r"(?<=[.!?])\s+", text)
    kept = [p for p in parts if p.strip() and not persona.cliche_iceriyor(p)]
    result = " ".join(kept).strip()
    if len(result) < 40:
        return _aciklama_fallback(mekan, tips)
    return result


_ACIKLAMA_LEAK = re.compile(r"[{}]|\b(hook|overlay|hashtag|json|kelime)\b", re.IGNORECASE)
_HOOK_KOTU = re.compile(r"\d\s*kelime|kelime|placeholder|string|^\W*$", re.IGNORECASE)


def _valid_hook(h: str) -> bool:
    h = (h or "").strip()
    words = h.split()
    if not (3 <= len(words) <= 9):
        return False
    if _HOOK_KOTU.search(h) or persona.cliche_iceriyor(h):
        return False
    return True


def _valid_aciklama(t: str) -> bool:
    t = (t or "").strip()
    if not (60 <= len(t) <= 700):
        return False
    if _ACIKLAMA_LEAK.search(t) or persona.cliche_iceriyor(t):
        return False
    return True


def _llm_aciklama(client: OllamaClient, model: str, mekan: str, tips: list[str]) -> str | None:
    """LLM'den yalnızca düz açıklama metni iste (JSON değil → çok daha sağlam)."""
    if not tips:
        return None
    tips_block = "\n".join(f"- {t}" for t in tips)
    user = (
        f"Aşağıdaki GERÇEK tüyoları kullanarak '{mekan}' için Instagram açıklaması yaz.\n"
        "Kurallar: birinci çoğul ağız (biz, ailemle), 3-5 KISA cümle, akıcı ve kusursuz "
        "Türkçe, uydurma bilgi/sayı/saat ekleme, klişe yok. Sonda tek cümlelik yumuşak "
        "kanal hatırlatması ve 1-2 emoji.\n"
        f"TÜYOLAR:\n{tips_block}\n\n"
        "SADECE açıklama metnini yaz. JSON, tırnak, başlık, madde işareti YOK."
    )
    for _ in range(2):
        try:
            out = client.generate_text(model, user, system=persona.SYSTEM_PROMPT, temperature=0.6)
        except RuntimeError:
            continue
        out = out.strip().strip("`").strip().strip('"').strip()
        parts = re.split(r"(?<=[.!?])\s+", out)
        out = " ".join(p for p in parts if not persona.cliche_iceriyor(p)).strip()
        if _valid_aciklama(out):
            return out
    return None


_OPENAI_SYSTEM = (
    "Sen Japonya'yı ailesiyle 13 gün gezmiş bir Türk gezginsin (Mayıs 2026, "
    "Tokyo/Osaka/Kyoto/Nara). Kanalın 'Mennan'ın Japonya Günlüğü'. Videoların "
    "üzerine gelecek KISA overlay metinleri + Instagram description üretiyorsun. "
    "Yanıtın SADECE geçerli JSON olsun. Türkçen kusursuz, klişesiz, samimi ve "
    "otoriter. Uydurma sayı/saat/fiyat YASAK — bilmiyorsan hiç yazma."
)

_OPENAI_CAPTION_SYSTEM = (
    "Sen Japonya'yı ailesiyle 13 gün gezmiş bir Türk gezginsin (Mayıs 2026, "
    "Tokyo/Osaka/Kyoto/Nara). Kanalın 'Mennan'ın Japonya Günlüğü'. Sadece "
    "Instagram description ve hashtagler üretiyorsun — video ÜZERİNE hiçbir "
    "metin gitmiyor, kullanıcı yazıyı kendi ekler. Türkçen kusursuz, klişesiz. "
    "Uydurma sayı/saat/fiyat YASAK. Yanıt SADECE JSON."
)


def generate_caption_only(cfg: Config, row: dict[str, Any]) -> dict[str, Any]:
    """metadata.csv satırından o videoya özel Instagram caption + hashtagler üret.

    row: metadata.csv'den bir video satırı — dosya_adi, mekan_etiketi, kategori,
    sehir, sahne_ozeti, sahne_ogeleri, sahne_mekan_tahmini, sure_sn içerir.
    Return: {"aciklama": str, "hashtagler": [str, ...]}

    OpenAI yoksa persona seed'den fallback (deterministik).
    """
    from src.openai_client import OpenAIClient

    dosya = row.get("dosya_adi", "")
    mekan = row.get("mekan_etiketi", "")
    kategori = row.get("kategori", "")
    sehir = row.get("sehir", "")
    sahne_ozeti = (row.get("sahne_ozeti") or "").strip()
    sahne_ogeleri = (row.get("sahne_ogeleri") or "").strip()
    sahne_mekan = (row.get("sahne_mekan_tahmini") or "").strip()

    oai = OpenAIClient.from_config(cfg)
    if oai is not None:
        # OpenAI ile üret
        user = f"""Bir Reels için Instagram caption'ı üret.

VİDEO METADATA:
- Mekan: {mekan}
- Kategori: {kategori}
- Şehir: {sehir}
- Sahne özeti (llava vision): {sahne_ozeti or 'yok'}
- Sahnede görünen ögeler: {sahne_ogeleri or 'yok'}
- Model'in mekan tahmini: {sahne_mekan or 'yok'}
- Süre: {row.get('sure_sn', '?')} sn

Çıktı JSON:
{{
  "aciklama": "3-5 kısa Türkçe cümle, birinci çoğul (biz/ailemle),
    somut bir gözlem/tüyo, 2-4 emoji. Videoyu ÖZETLEME — mekan/konu
    hakkında bilgi ver. Sonuna kısa kanal hatırlatması ekle (opsiyonel).",
  "hashtagler": ["japonya", "gezi", "reels", ...]  // 8-12 tag, # olmadan
}}

KURALLAR:
- SADECE sahne özetinde/mekan bilgisinde açıkça geçen bilgiye dayan
- Uydurma fiyat/saat/tarih/sayı YASAK
- Klişe cümle YASAK ("büyülü ülke", "erken git", "rahat ayakkabı")
- Cümleler kusursuz Türkçe olmalı
- Yalnızca JSON döndür"""

        try:
            data = oai.chat_json(_OPENAI_CAPTION_SYSTEM, user, temperature=0.7, max_tokens=800)
        except (RuntimeError, ValueError) as exc:
            log.warning(f"OpenAI caption başarısız, seed fallback: {exc}")
            data = None

        if data:
            aciklama = _sanitize_aciklama(str(data.get("aciklama", "")),
                                          mekan, [sahne_ozeti])
            hashtagler = _clean_hashtags(data.get("hashtagler"), [])
            if aciklama and hashtagler:
                log.info(f"  ↳ GPT caption ({oai.model}): {aciklama[:50]}…")
                return {"aciklama": aciklama, "hashtagler": hashtagler}

    # Fallback: persona seed'den
    seed = persona.seed_for(mekan, kategori)
    aciklama = seed.get("aciklama") or _aciklama_fallback(mekan,
                                                          [sahne_ozeti] if sahne_ozeti else seed.get("tips", []))
    hashtagler = _clean_hashtags(None, seed.get("hashtags", persona.GENERIC["hashtags"]))
    return {"aciklama": aciklama, "hashtagler": hashtagler}


def _openai_generate(cfg: Config, group: dict[str, Any]) -> dict[str, Any] | None:
    """OpenAI (gpt-4o-mini) ile Türkçe kaliteli metin üret. Key yoksa None."""
    from src.openai_client import OpenAIClient

    oai = OpenAIClient.from_config(cfg)
    if oai is None:
        return None

    mekan = group["mekan_etiketi"]
    kategori = group.get("kategori", "")
    total = float(group["toplam_sure_sn"])
    kullanici = (group.get("kullanici_prompt") or "").strip()
    knowledge = (group.get("knowledge") or "").strip()
    tipi = group.get("aciklama_tipi", "aciklayici")

    # Seed'in tüyoları varsa referans olarak GPT'ye ver
    seed = persona.seed_for(mekan, kategori)
    tips_block = "\n".join(f"- {t}" for t in seed.get("tips", [])[:6])

    ton_hint = {
        "aciklayici": "Nötr bilgilendirici, somut fact (sayı/saat/fiyat varsa), emoji sınırlı.",
        "bolgeyi_tanit": "Sıcak turistik tanıtım, coğrafi + kültürel bağlam, 3-4 emoji.",
        "merak_uyandir": "Cliffhanger, gizemli — 'az kişi biliyor', sonuna kadar cevap verme.",
    }.get(tipi, "Nötr bilgilendirici")

    user_prompt = f"""Mekan: {mekan}
Kategori: {kategori}
Toplam reel süresi: {total} saniye
Ton: {tipi} — {ton_hint}
{f"Kullanıcı talebi: {kullanici}" if kullanici else ""}
{f"Tüyolar (referans olarak kullan, uydurmadan):\\n{tips_block}" if tips_block else ""}
{f"Insider Knowledge:\\n{knowledge[:5000]}" if knowledge else ""}

Aşağıdaki JSON şemasında çıktı ver:
{{
  "hook": "5-8 kelime Türkçe, çarpıcı, video başında görünecek",
  "overlays": [
    {{"saniye": 4.5, "metin": "MAX 4 KELİME", "sure": 3.0,
      "stil": "baslik|altbaslik|vurgu", "renk": "sari|kirmizi|beyaz|mavi|yesil|turuncu|pembe"}}
  ],
  "cta": "3-6 kelime aksiyon çağrısı",
  "aciklama": "3-5 kısa Türkçe cümle, birinci çoğul (biz/ailemle), somut trick, 2-4 emoji. Videoyu özetleme — bilgi ver.",
  "hashtagler": ["8-12 tag", "# olmadan", "küçük harf"]
}}

Kurallar:
- overlays 3-5 madde, ilk saniye 4-6 arası, sonuncu (total-6)'dan önce
- overlay metinleri MAX 4 kelime (kısa, Impact-punchy)
- aciklama uydurma sayı/saat/fiyat İÇERMEMELİ
- klişe cümleler yok ("erken git", "rahat ayakkabı", "büyülü ülke")
- SADECE JSON döndür, açıklama yazma"""

    try:
        data = oai.chat_json(_OPENAI_SYSTEM, user_prompt, temperature=0.7, max_tokens=1200)
    except (RuntimeError, ValueError) as exc:
        log.warning(f"OpenAI başarısız, seed fallback: {exc}")
        return None

    # savunmacı normalize + validate
    hook = str(data.get("hook", "")).strip()
    if not _valid_hook(hook):
        hook = seed.get("hook", persona.GENERIC["hook"])

    aciklama = _sanitize_aciklama(str(data.get("aciklama", "")), mekan, seed.get("tips", []))

    overlays_raw = data.get("overlays") or []
    if not isinstance(overlays_raw, list) or len(overlays_raw) < 2:
        overlays_raw = [{"metin": t} for t in seed.get("overlays", persona.GENERIC["overlays"])]

    hashtagler = _clean_hashtags(data.get("hashtagler"), seed.get("hashtags", persona.GENERIC["hashtags"]))

    log.info(f"  ↳ OpenAI ({oai.model}): {hook!r}")

    return {
        "hook": hook,
        "overlays": overlays_raw,   # validate_plan bunları düzenleyecek
        "cta": str(data.get("cta") or persona.CTA_HAVUZU[group.get("idx", 0) % len(persona.CTA_HAVUZU)]),
        "aciklama": aciklama,
        "hashtagler": hashtagler,
    }


def generate_local(cfg: Config, group: dict[str, Any], client: OllamaClient, model: str) -> dict[str, Any]:
    """İçerik üretimi. Öncelik sırası:
      1. OpenAI (gpt-4o-mini) — cfg.openai.api_key varsa, en kaliteli Türkçe
      2. Persona seed (el yapımı) — key yoksa, deterministik ve klişesiz
    """
    # 1) OpenAI dene (varsa)
    oai_result = _openai_generate(cfg, group)
    if oai_result is not None:
        return oai_result

    # 2) Fallback: persona seed'lerinden
    mekan = group["mekan_etiketi"]
    kategori = group.get("kategori", "")
    total = float(group["toplam_sure_sn"])
    seed = persona.seed_for(mekan, kategori)

    aciklama = seed.get("aciklama") or _aciklama_fallback(mekan, seed.get("tips", []))
    return {
        "hook": seed.get("hook", persona.GENERIC["hook"]),
        "overlays": _build_overlays(seed.get("overlays", persona.GENERIC["overlays"]), total, cfg),
        "cta": persona.CTA_HAVUZU[group.get("idx", 0) % len(persona.CTA_HAVUZU)],
        "aciklama": aciklama,
        "hashtagler": _clean_hashtags(None, seed.get("hashtags", persona.GENERIC["hashtags"])),
    }


def validate_plan(plan: dict[str, Any], max_sn: float) -> dict[str, Any]:
    overlays: list[dict[str, Any]] = []
    for o in plan.get("overlays", []):
        try:
            sn = float(o["saniye"])
            if sn >= max_sn:
                continue
            overlays.append({
                "saniye": sn,
                "metin": str(o["metin"])[:60],
                "sure": float(o.get("sure", 3.0)),
                "stil": str(o.get("stil", "vurgu")),
                "renk": str(o.get("renk", "beyaz")),
            })
        except (KeyError, ValueError, TypeError):
            continue
    plan["overlays"] = overlays
    plan.setdefault("hook", "")
    plan.setdefault("cta", "Takip et 👉")
    plan.setdefault("aciklama", "")
    plan.setdefault("hashtagler", [])
    return plan


def process_group(cfg: Config, input_path: Path, use_dify: bool, client: OllamaClient, model: str) -> Path | None:
    group = json.loads(input_path.read_text(encoding="utf-8"))
    output_path = input_path.with_name(input_path.name.replace("_input.json", "_final.json"))
    if output_path.exists():
        log.info(f"Atlanıyor (var): {output_path.name}")
        return output_path
    try:
        if use_dify and cfg.dify.api_key not in ("", "REPLACE_ME_APP_TOKEN"):
            raw = call_dify(cfg, group)
            plan = raw.get("kurgu_json") or raw
            if isinstance(plan, str):
                plan = _extract_json(plan)
        else:
            plan = generate_local(cfg, group, client, model)
        plan = validate_plan(plan, group["toplam_sure_sn"])
    except Exception as exc:
        log.error(f"Grup başarısız ({input_path.name}): {exc}")
        return None

    # knowledge/kullanici_prompt input alanları çıktıya kopyalanmaz (final_json şişer)
    slim_group = {k: v for k, v in group.items() if k != "knowledge"}
    merged = {**slim_group, "kurgu_json": plan}
    output_path.write_text(json.dumps(merged, ensure_ascii=False, indent=2), encoding="utf-8")
    log.info(f"✓ {output_path.name} → \"{plan.get('hook','')}\"")
    return output_path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=None)
    parser.add_argument("--no-dify", action="store_true", help="Dify'ı bypass et, lokal üretim")
    args = parser.parse_args()

    cfg = load_config(args.config)
    client = OllamaClient(cfg.ollama.base_url, cfg.ollama.request_timeout_sn)
    inputs = sorted(cfg.paths.plans_dir.glob("*_input.json"))
    log.info(f"İşlenecek grup: {len(inputs)}")

    use_dify = not args.no_dify
    if use_dify and cfg.dify.api_key in ("", "REPLACE_ME_APP_TOKEN"):
        log.warning("Dify API key yok — lokal üretim kullanılacak.")
        use_dify = False

    model = "" if use_dify else pick_text_model(cfg, client)
    if not use_dify:
        log.info(f"Lokal üretim modeli: {model}")

    with ThreadPoolExecutor(max_workers=cfg.dify.concurrency) as pool:
        futures = {pool.submit(process_group, cfg, p, use_dify, client, model): p for p in inputs}
        with tqdm(total=len(futures), desc="Kurgu planı") as bar:
            for fut in as_completed(futures):
                fut.result()
                bar.update(1)

    finals = list(cfg.paths.plans_dir.glob("*_final.json"))
    log.info(f"Toplam final plan: {len(finals)}")


if __name__ == "__main__":
    main()
