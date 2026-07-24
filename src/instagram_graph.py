"""Instagram Graph API (resmi) publisher — foto yayın.

Instagram Business Login token'ı kullanır. 2 adımlı yayın:
  1) POST /{ig_user_id}/media → container (image_url + caption)
  2) POST /{ig_user_id}/media_publish → yayınla (container_id)

image_url PUBLIC HTTPS olmalı (Meta sunucusu yerelden erişemez). Cloudflare
Tunnel / ngrok / Cloudinary kullanılabilir; cfg.instagram.public_base_url
tabanı + kartın URL'si birleştirilir.

Ana fonksiyonlar:
    publish_image(cfg, jpg_url, caption) -> {"id": media_id}
    refresh_token(cfg) -> new_long_lived_token
"""
from __future__ import annotations

import json
import time
from typing import Any

import requests

from src.config import Config
from src.utils.logging import get_logger

log = get_logger("igraph")

_BASE = "https://graph.instagram.com/v21.0"


class GraphError(RuntimeError):
    def __init__(self, msg: str, code: int | None = None, sub: int | None = None,
                 payload: dict[str, Any] | None = None):
        super().__init__(msg)
        self.code = code
        self.sub = sub
        self.payload = payload or {}


def _req(method: str, path: str, params: dict[str, Any] | None = None,
         timeout: int = 30) -> dict[str, Any]:
    url = f"{_BASE}/{path.lstrip('/')}" if not path.startswith("http") else path
    try:
        r = requests.request(method, url, params=params or {}, timeout=timeout)
    except requests.RequestException as exc:
        raise GraphError(f"Ağ hatası: {exc}") from exc
    try:
        data = r.json()
    except ValueError:
        data = {"raw": r.text[:300]}
    if not r.ok or "error" in data:
        err = data.get("error", {}) if isinstance(data, dict) else {}
        raise GraphError(
            _tr_err(err.get("message") or str(data)[:300]),
            code=err.get("code"), sub=err.get("error_subcode"), payload=err,
        )
    return data


def _tr_err(msg: str) -> str:
    """Yaygın Meta hatalarını Türkçe ipucuyla zenginleştir."""
    m = (msg or "").lower()
    if "session key invalid" in m or "revoked" in m:
        return (f"Token geçersiz/iptal edildi ({msg}). Meta Developers → "
                "Instagram → API setup → Generate token ile yenile ve "
                "config.yaml → instagram.graph_token'a yaz.")
    if "media type" in m or "not a valid instagram" in m or "url does not exist" in m:
        return (f"Görsel URL'sine Instagram erişemedi ({msg}). image_url "
                "public HTTPS olmalı — public_base_url ayarlı ve dışarıdan "
                "açılıyor mu kontrol et (Cloudflare tunnel çalışıyor mu?).")
    if "does not have permission" in m or "insufficient" in m:
        return (f"İzin yetersiz ({msg}). Token'ın instagram_content_publish "
                "iznine ihtiyacı var. Hesap Business (Creator değil) olmalı.")
    return msg


# ---------------- token yönetimi ----------------
def debug_token(cfg: Config) -> dict[str, Any]:
    """Token'ın geçerliliği + izinleri hakkında mini rapor."""
    ig = cfg.instagram
    if not (ig and ig.graph_token):
        return {"ok": False, "reason": "graph_token boş"}
    try:
        me = _req("GET", "me", {
            "fields": "id,username,account_type,media_count",
            "access_token": ig.graph_token,
        })
        return {"ok": True, "account": me, "publish_ready":
                me.get("account_type") == "BUSINESS"}
    except GraphError as exc:
        return {"ok": False, "reason": str(exc)}


def refresh_token(cfg: Config) -> str:
    """Long-lived token'ı ~60 gün daha uzat (ig_refresh_token). Yeni token'ı
    döndürür; caller config.yaml'a yazmalı."""
    ig = cfg.instagram
    if not (ig and ig.graph_token):
        raise GraphError("graph_token yok — önce oluştur.")
    data = _req("GET", "refresh_access_token", {
        "grant_type": "ig_refresh_token",
        "access_token": ig.graph_token,
    })
    tok = data.get("access_token")
    if not tok:
        raise GraphError(f"Yenileme yanıtı beklenmedik: {data}")
    log.info(f"  token yenilendi, {data.get('expires_in', 0)//86400} gün geçerli")
    return tok


# ---------------- yayınlama ----------------
def _wait_container_ready(cfg: Config, container_id: str,
                          timeout_sn: int = 90) -> None:
    """Container FINISHED oluncaya kadar bekle (Instagram medyayı işler)."""
    ig = cfg.instagram
    deadline = time.time() + timeout_sn
    last = None
    while time.time() < deadline:
        st = _req("GET", container_id, {
            "fields": "status_code,status",
            "access_token": ig.graph_token,
        })
        code = st.get("status_code")
        last = st
        if code == "FINISHED":
            return
        if code in ("ERROR", "EXPIRED"):
            raise GraphError(f"Container hazırlanamadı: {st}")
        time.sleep(2)
    raise GraphError(f"Container timeout ({timeout_sn}s): {last}")


def publish_image(cfg: Config, image_url: str, caption: str) -> dict[str, Any]:
    """Foto post yayınla. Döner: {'id': published_media_id}."""
    ig = cfg.instagram
    if not (ig and ig.graph_token and ig.ig_user_id):
        raise GraphError("Instagram Graph API config eksik "
                         "(graph_token / ig_user_id).")
    if not image_url.startswith(("http://", "https://")):
        raise GraphError(f"image_url public HTTPS olmalı: {image_url}")

    log.info(f"  Instagram Graph: container oluşturuluyor…")
    container = _req("POST", f"{ig.ig_user_id}/media", {
        "image_url": image_url,
        "caption": caption or "",
        "access_token": ig.graph_token,
    })
    cid = container.get("id")
    if not cid:
        raise GraphError(f"Container id dönmedi: {container}")

    log.info(f"  container id={cid}, hazır olması bekleniyor…")
    _wait_container_ready(cfg, cid)

    log.info(f"  yayınlanıyor…")
    pub = _req("POST", f"{ig.ig_user_id}/media_publish", {
        "creation_id": cid,
        "access_token": ig.graph_token,
    })
    mid = pub.get("id")
    if not mid:
        raise GraphError(f"Yayın id dönmedi: {pub}")
    log.info(f"  ✓ yayınlandı: media_id={mid}")
    return {"id": mid, "container_id": cid}


# ---------------- CLI: hızlı kontrol ----------------
if __name__ == "__main__":
    import sys
    from pathlib import Path
    from src.config import load_config
    cfg = load_config(Path("config.yaml"))
    if len(sys.argv) > 1 and sys.argv[1] == "refresh":
        print("Yeni long-lived token:")
        print(refresh_token(cfg))
    else:
        report = debug_token(cfg)
        print(json.dumps(report, ensure_ascii=False, indent=2))
