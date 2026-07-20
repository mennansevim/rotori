"""Minimal OpenAI Chat Completions wrapper — Türkçe metin üretimi için.

qwen2.5:3b (3B parametre) Türkçe cümle kalitesinde zorlanıyor: "diversifikilmiş",
"atalari" gibi hatalı kelimeler, klişe cümleler üretiyor. gpt-4o-mini Türkçe'de
mükemmel + saniye başına birkaç isteği ~$0.0005 fiyatla halleder — küçük arşiv
için maliyet önemsiz (10 reel için ~$0.005).

Kullanım:
    client = OpenAIClient.from_config(cfg)  # None dönebilir (key yok)
    if client:
        raw = client.chat_json(system_prompt, user_prompt)
"""
from __future__ import annotations

import json
from typing import Any

import requests

from src.utils.logging import get_logger

log = get_logger("openai")


class OpenAIClient:
    def __init__(self, api_key: str, model: str = "gpt-4o-mini",
                 base_url: str = "https://api.openai.com/v1",
                 timeout_sn: int = 60) -> None:
        self.api_key = api_key
        self.model = model
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout_sn

    @classmethod
    def from_config(cls, cfg) -> "OpenAIClient | None":
        if not cfg.openai or not cfg.openai.api_key:
            return None
        return cls(
            api_key=cfg.openai.api_key,
            model=cfg.openai.model,
            base_url=cfg.openai.base_url,
            timeout_sn=cfg.openai.timeout_sn,
        )

    def _chat(self, messages: list[dict[str, str]], response_format: dict[str, Any] | None,
              temperature: float = 0.7, max_tokens: int = 1000) -> str:
        url = f"{self.base_url}/chat/completions"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        payload: dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        if response_format:
            payload["response_format"] = response_format

        last_err: Exception | None = None
        for attempt in range(2):
            try:
                r = requests.post(url, headers=headers, json=payload, timeout=self.timeout)
                r.raise_for_status()
                data = r.json()
                return data["choices"][0]["message"]["content"]
            except (requests.RequestException, KeyError, ValueError) as exc:
                last_err = exc
                if attempt == 0:
                    log.warning(f"OpenAI hata (attempt 1): {exc} — retry")
        raise RuntimeError(f"OpenAI çağrısı başarısız: {last_err}")

    def chat_text(self, system: str, user: str, temperature: float = 0.7,
                  max_tokens: int = 500) -> str:
        return self._chat(
            [{"role": "system", "content": system},
             {"role": "user", "content": user}],
            response_format=None,
            temperature=temperature, max_tokens=max_tokens,
        ).strip()

    def chat_json(self, system: str, user: str, temperature: float = 0.5,
                  max_tokens: int = 1000) -> dict[str, Any]:
        """JSON mode ile chat — çıktı garantili geçerli JSON."""
        raw = self._chat(
            [{"role": "system", "content": system},
             {"role": "user", "content": user}],
            response_format={"type": "json_object"},
            temperature=temperature, max_tokens=max_tokens,
        )
        return json.loads(raw)
