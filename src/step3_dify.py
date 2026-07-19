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

from src.config import Config, load_config
from src.ollama_client import OllamaClient
from src.utils.logging import get_logger

log = get_logger("step3")


def call_dify(cfg: Config, group: dict[str, Any]) -> dict[str, Any]:
    url = f"{cfg.dify.base_url.rstrip('/')}{cfg.dify.workflow_endpoint}"
    headers = {
        "Authorization": f"Bearer {cfg.dify.api_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "inputs": {
            "mekan_etiketi": group["mekan_etiketi"],
            "video_dosyalari": ", ".join(group["video_dosyalari"]),
            "toplam_sure_sn": group["toplam_sure_sn"],
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
            outputs = data.get("data", {}).get("outputs", {}) or data.get("outputs", {})
            return outputs
        except (requests.RequestException, ValueError) as exc:
            last_err = exc
            wait = 2 ** attempt
            log.warning(f"Dify hata (attempt {attempt+1}): {exc}. {wait}s bekliyor.")
            time.sleep(wait)
    raise RuntimeError(f"Dify tüm denemeler başarısız: {last_err}")


_HOOK_PROMPT = (
    "Sen bir Instagram Reels senaristisin. Verilen mekan için 6-8 kelimelik, "
    "Türkçe, çarpıcı ve merak uyandıran bir HOOK metni yaz. "
    "Sadece hook metnini döndür, açıklama yazma."
)

_OVERLAY_SYSTEM = (
    "Sen bir Reels kurgu asistanısın. Verilen mekan için JSON çıktısı üret. "
    "Hiçbir açıklama yazma, sadece geçerli JSON döndür. Format:\n"
    "{\n"
    '  "hook": "kısa çarpıcı metin (6-8 kelime)",\n'
    '  "overlays": [\n'
    '    {"saniye": 5.0, "metin": "kısa vurgu", "sure": 3.0, "stil": "vurgu"},\n'
    '    {"saniye": 15.0, "metin": "başka bir vurgu", "sure": 3.0, "stil": "altbaslik"}\n'
    "  ],\n"
    '  "cta": "Kaydet ve paylaş!"\n'
    "}\n"
    "Kurallar: 3-5 arası overlay üret. Her metin max 5 kelime Türkçe. saniye ve sure float."
)


def call_ollama_fallback(cfg: Config, group: dict[str, Any]) -> dict[str, Any]:
    client = OllamaClient(cfg.ollama.base_url, cfg.ollama.request_timeout_sn)
    prompt = (
        f"Mekan: {group['mekan_etiketi']}\n"
        f"Toplam süre: {group['toplam_sure_sn']} saniye\n"
        f"Klip sayısı: {group['hedef_klip_sayisi']}"
    )
    raw = client.generate_text(cfg.ollama.text_model, prompt, system=_OVERLAY_SYSTEM, temperature=0.6)
    return _extract_json(raw)


def _extract_json(text: str) -> dict[str, Any]:
    m = re.search(r"\{.*\}", text, re.DOTALL)
    if not m:
        raise ValueError(f"JSON bulunamadı: {text[:200]}")
    return json.loads(m.group(0))


def validate_plan(plan: dict[str, Any], max_sn: float) -> dict[str, Any]:
    if "hook" not in plan or "overlays" not in plan:
        raise ValueError("plan hook veya overlays içermiyor")
    overlays: list[dict[str, Any]] = []
    for o in plan.get("overlays", []):
        try:
            overlays.append({
                "saniye": float(o["saniye"]),
                "metin": str(o["metin"])[:60],
                "sure": float(o.get("sure", 3.0)),
                "stil": str(o.get("stil", "vurgu")),
                "renk": str(o.get("renk", "beyaz")),
            })
        except (KeyError, ValueError, TypeError):
            continue
    overlays = [o for o in overlays if o["saniye"] < max_sn]
    plan["overlays"] = overlays
    plan.setdefault("cta", "Takip et 👉")
    plan.setdefault("aciklama", "")
    plan.setdefault("hashtagler", [])
    return plan


def process_group(cfg: Config, input_path: Path, use_dify: bool) -> Path | None:
    group = json.loads(input_path.read_text(encoding="utf-8"))
    output_path = input_path.with_name(input_path.name.replace("_input.json", "_final.json"))
    if output_path.exists():
        log.info(f"Atlanıyor (var): {output_path.name}")
        return output_path
    try:
        if use_dify and cfg.dify.api_key != "REPLACE_ME_APP_TOKEN":
            raw = call_dify(cfg, group)
            plan = raw.get("kurgu_json") or raw
            if isinstance(plan, str):
                plan = _extract_json(plan)
        else:
            plan = call_ollama_fallback(cfg, group)
        plan = validate_plan(plan, group["toplam_sure_sn"])
    except Exception as exc:
        log.error(f"Grup başarısız ({input_path.name}): {exc}")
        return None

    merged = {**group, "kurgu_json": plan}
    output_path.write_text(json.dumps(merged, ensure_ascii=False, indent=2), encoding="utf-8")
    return output_path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=None)
    parser.add_argument("--no-dify", action="store_true", help="Dify'ı bypass et, direkt Ollama kullan")
    args = parser.parse_args()

    cfg = load_config(args.config)
    inputs = sorted(cfg.paths.plans_dir.glob("*_input.json"))
    log.info(f"İşlenecek grup: {len(inputs)}")

    use_dify = not args.no_dify
    if use_dify and cfg.dify.api_key == "REPLACE_ME_APP_TOKEN":
        log.warning("Dify API key ayarlanmamış — Ollama fallback kullanılacak.")
        use_dify = False

    with ThreadPoolExecutor(max_workers=cfg.dify.concurrency) as pool:
        futures = {pool.submit(process_group, cfg, p, use_dify): p for p in inputs}
        with tqdm(total=len(futures), desc="Kurgu planı") as bar:
            for fut in as_completed(futures):
                fut.result()
                bar.update(1)

    finals = list(cfg.paths.plans_dir.glob("*_final.json"))
    log.info(f"Toplam final plan: {len(finals)}")


if __name__ == "__main__":
    main()
