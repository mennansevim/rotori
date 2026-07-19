from __future__ import annotations

import base64
import time
from pathlib import Path
from typing import Any

import requests

from src.utils.logging import get_logger

log = get_logger("ollama")


class OllamaClient:
    def __init__(self, base_url: str, timeout_sn: int = 120) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout_sn

    def _post(self, path: str, payload: dict[str, Any], retries: int = 2) -> dict[str, Any]:
        url = f"{self.base_url}{path}"
        last_err: Exception | None = None
        for attempt in range(retries + 1):
            try:
                resp = requests.post(url, json=payload, timeout=self.timeout)
                resp.raise_for_status()
                return resp.json()
            except (requests.RequestException, ValueError) as exc:
                last_err = exc
                wait = 2 ** attempt
                log.warning(f"Ollama {path} denemesi {attempt + 1} başarısız: {exc}. {wait}s bekliyor.")
                time.sleep(wait)
        raise RuntimeError(f"Ollama {path} tüm denemeler başarısız: {last_err}")

    def generate_text(self, model: str, prompt: str, system: str | None = None, temperature: float = 0.3) -> str:
        payload: dict[str, Any] = {
            "model": model,
            "prompt": prompt,
            "stream": False,
            "options": {"temperature": temperature},
        }
        if system:
            payload["system"] = system
        data = self._post("/api/generate", payload)
        return data.get("response", "").strip()

    def generate_vision(self, model: str, prompt: str, image_path: Path, temperature: float = 0.2) -> str:
        with image_path.open("rb") as fh:
            b64 = base64.b64encode(fh.read()).decode()
        payload = {
            "model": model,
            "prompt": prompt,
            "images": [b64],
            "stream": False,
            "options": {"temperature": temperature},
        }
        data = self._post("/api/generate", payload)
        return data.get("response", "").strip()

    def health(self) -> bool:
        try:
            r = requests.get(f"{self.base_url}/api/tags", timeout=5)
            return r.status_code == 200
        except requests.RequestException:
            return False
