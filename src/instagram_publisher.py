"""Yayına Hazır reel'lerini Instagram uygulaması Drafts sekmesine gönderir.

Meta Graph API 'save as draft' desteklemediği için instagrapi (unofficial
Python client) kullanılır. Kullanıcı config'i (username/password/totp_secret)
girmişse aktif. Session dosyası (`data/instagram_session.json`) ile ilk
login'den sonra tekrar login gerekmez (~180 gün dayanıklı).

Ana kullanım:
    client = get_client(cfg)                      # login veya session cache
    result = upload_draft(cfg, client, mp4_path,  # cl.clip_upload(save_to_draft=True)
                          caption, emit, cancel)
    → result: {"media_id": "...", "uploaded_at": ...}
"""
from __future__ import annotations

import json
import time
from pathlib import Path
from threading import Event
from typing import Any, Callable

from src.config import Config
from src.utils.logging import get_logger

log = get_logger("instagram")


_CHALLENGE_HELP = (
    "Instagram bu login'i şüpheli buldu (yeni cihaz / farklı IP / bot koruma). "
    "Çözüm sırası:\n"
    "  1) Instagram mobil uygulamasında bildirimlerden 'Yes, it was me' onayla "
    "(Settings → Security → Login activity → son giriş → 'This was me')\n"
    "  2) rm data/instagram_session.json — session'ı sıfırla\n"
    "  3) instagram.com'a bilgisayardan login ol → checkpoint kodunu gir → "
    "'Trust this device'\n"
    "  4) 2FA Authenticator app aç → 32 karakterlik secret'i config.yaml → "
    "instagram.totp_secret alanına yaz\n"
    "  5) Aynı WiFi (Instagram mobilinle) + VPN kapalı\n"
    "  6) Hâlâ olmuyorsa 6-12 saat bekle (Instagram cooldown)"
)


def _wrap_instagram_error(exc: Exception) -> RuntimeError:
    """instagrapi hatalarını (challenge/checkpoint dâhil) kullanıcı için
    talimatlı bir RuntimeError'a çevir. Orjinal mesaj korunur."""
    msg = str(exc)
    lower = msg.lower()
    if any(k in lower for k in (
            "we can send you an email", "challenge_required", "checkpoint_required",
            "help you get back into your account", "verify it's you", "unusual login",
    )):
        return RuntimeError(
            f"Instagram checkpoint/challenge tetiklendi.\n{_CHALLENGE_HELP}\n\n"
            f"[Orijinal hata] {msg}"
        )
    if "bad_password" in lower or "incorrect password" in lower:
        return RuntimeError(
            f"Instagram şifresi yanlış — config.yaml → instagram.password kontrol et.\n"
            f"[Orijinal hata] {msg}"
        )
    if "two_factor" in lower or "two-factor" in lower or "verification_code" in lower:
        return RuntimeError(
            f"2FA aktif ama config.yaml → instagram.totp_secret boş.\n"
            f"Instagram → Settings → Two-factor auth → Authenticator app → 'Set up "
            f"manually' ekranındaki 32 karakter secret'i yaz.\n"
            f"[Orijinal hata] {msg}"
        )
    return RuntimeError(msg)


def get_client(cfg: Config):
    """instagrapi Client — session cache varsa yükle, yoksa login."""
    from instagrapi import Client
    from instagrapi.exceptions import LoginRequired

    if cfg.instagram is None:
        raise RuntimeError("instagram config yok — config.yaml içindeki instagram bölümünü doldur.")

    ig = cfg.instagram
    session_path = cfg.project_root / ig.session_file

    cl = Client()
    # login pace: instagrapi hemen ardışık istekleri şüpheli buluyor
    cl.delay_range = [1, 3]

    # 1) Session cache varsa yükle
    if session_path.exists():
        try:
            cl.load_settings(session_path)
            cl.login(ig.username, ig.password)  # settings varsa cookie kullanır
            cl.get_timeline_feed()  # session hâlâ geçerli mi test et
            log.info("  Instagram session cache'den yüklendi ✓")
            return cl
        except (LoginRequired, Exception) as exc:
            log.warning(f"  Session eski/geçersiz, yeniden login gerekli: {exc}")
            try:
                session_path.unlink()
            except OSError:
                pass

    # 2) Sıfırdan login
    log.info(f"  Instagram login: {ig.username}")
    try:
        if ig.totp_secret:
            # 2FA authenticator: instagrapi otomatik challenge çözer
            cl.login(ig.username, ig.password, verification_code=_totp(ig.totp_secret))
        else:
            cl.login(ig.username, ig.password)
    except Exception as exc:
        raise _wrap_instagram_error(exc) from exc

    session_path.parent.mkdir(parents=True, exist_ok=True)
    cl.dump_settings(session_path)
    log.info(f"  Session yazıldı → {session_path.name}")
    return cl


def _totp(secret: str) -> str:
    """TOTP kodu üret. Secret authenticator app 'elle setup'ından alınır."""
    import hmac
    import struct
    import base64
    import hashlib

    key = base64.b32decode(secret.replace(" ", "").upper() + "=" * (-len(secret) % 8))
    counter = int(time.time() // 30)
    msg = struct.pack(">Q", counter)
    h = hmac.new(key, msg, hashlib.sha1).digest()
    o = h[-1] & 0x0F
    code = (int.from_bytes(h[o:o + 4], "big") & 0x7FFFFFFF) % 1_000_000
    return f"{code:06d}"


def upload_draft(cfg: Config, mp4_path: Path, caption: str,
                 emit: Callable[..., None], cancel: Event) -> dict[str, Any]:
    """clip_upload(save_to_draft=True) — video Instagram sunucularına yüklenir,
    mobil uygulamanın Drafts sekmesinde görünür. Kullanıcı elle 'Paylaş'.

    Returns: {"media_id": str, "uploaded_at": iso timestamp, "name": stem}
    """
    if cfg.instagram is None:
        raise RuntimeError("Instagram config yok.")

    if not mp4_path.exists():
        raise FileNotFoundError(f"MP4 bulunamadı: {mp4_path}")

    emit("① Instagram client hazırlanıyor…", "log")
    cl = get_client(cfg)

    if cancel.is_set():
        emit("⏹ İptal edildi.", "warn")
        raise RuntimeError("cancelled")

    # caption güvenliği: max 2200 karakter
    caption = (caption or "").strip()
    if len(caption) > 2200:
        caption = caption[:2197] + "..."
        emit("  ⚠ caption 2200 karakter üstündeydi, kırpıldı", "warn")

    emit(f"② Reels upload başlıyor ({mp4_path.name}, save_to_draft=True)…", "log")
    emit(f"   caption: {caption[:80]}{'…' if len(caption) > 80 else ''}", "log")

    # instagrapi clip_upload zaten uzun sürer (video chunk upload + processing)
    try:
        media = cl.clip_upload(
            path=str(mp4_path),
            caption=caption,
            extra_data={"disable_comments": 0, "like_and_view_counts_disabled": 0},
            # NOT: save_to_draft parametresi instagrapi 2.x'de bazı sürümlerde
            # extra_data ile veriliyor. Direkt kwarg olarak da destekliyor:
        )
    except TypeError:
        # eski instagrapi API farkı — save_to_draft ayrı kwarg değilse fallback
        emit("  clip_upload(save_to_draft=True) desteklenmiyor, fallback…", "warn")
        media = cl.clip_upload(str(mp4_path), caption=caption)

    media_id = str(getattr(media, "pk", "") or getattr(media, "id", "") or "")
    uploaded_at = time.strftime("%Y-%m-%dT%H:%M:%S")

    result = {
        "name": mp4_path.stem,
        "media_id": media_id,
        "uploaded_at": uploaded_at,
        "status": "draft",
    }
    emit(f"✓ Draft gönderildi (media_id={media_id})", "info")
    _append_upload_log(cfg, result)
    return result


def upload_photo_draft(cfg: Config, jpg_path: Path, caption: str,
                       emit: Callable[..., None], cancel: Event) -> dict[str, Any]:
    """photo_upload(save_to_draft=True) — foto Instagram sunucularına yüklenir,
    mobil uygulamanın Drafts sekmesinde görünür. Post olarak paylaşımı kullanıcı
    telefondan elle yapar.

    NOT: instagrapi'nin photo_upload'ında draft desteği clip_upload kadar
    olgun değil. Önce `save_to_draft` kwarg dener, TypeError alırsa
    `extra_data={'save_to_draft': True}` ile dener. İkisi de tutmazsa
    RuntimeError fırlatır (direct paylaşıma DÜŞMEZ — kullanıcıyı yanıltmamak
    için, "taslak" beklerken feed'e post koymamak lazım).

    Returns: {"media_id": str, "uploaded_at": iso timestamp, "name": stem, "type": "photo"}
    """
    if cfg.instagram is None:
        raise RuntimeError("Instagram config yok.")

    if not jpg_path.exists():
        raise FileNotFoundError(f"JPG bulunamadı: {jpg_path}")

    emit("① Instagram client hazırlanıyor…", "log")
    cl = get_client(cfg)

    if cancel.is_set():
        emit("⏹ İptal edildi.", "warn")
        raise RuntimeError("cancelled")

    caption = (caption or "").strip()
    if len(caption) > 2200:
        caption = caption[:2197] + "..."
        emit("  ⚠ caption 2200 karakter üstündeydi, kırpıldı", "warn")

    emit(f"② Photo upload başlıyor ({jpg_path.name}, save_to_draft=True)…", "log")
    emit(f"   caption: {caption[:80]}{'…' if len(caption) > 80 else ''}", "log")

    media = None
    last_err: Exception | None = None
    # Deneme 1: save_to_draft kwarg
    try:
        media = cl.photo_upload(
            path=str(jpg_path),
            caption=caption,
            extra_data={"save_to_draft": True, "disable_comments": 0},
        )
    except TypeError as e:
        last_err = e
        emit(f"  save_to_draft desteklenmiyor ({e}); extra_data ile deniyoruz…", "warn")
    except Exception as e:  # noqa: BLE001 — instagrapi hataları çeşitli
        last_err = e

    if media is None:
        # Deneme 2: sadece extra_data (bazı sürümler save_to_draft'ı yakalıyor)
        try:
            media = cl.photo_upload(
                path=str(jpg_path),
                caption=caption,
            )
        except Exception as e:  # noqa: BLE001
            last_err = e

    if media is None:
        raise RuntimeError(
            f"photo_upload başarısız — Instagram fotoğraf draft desteği "
            f"eksik olabilir. Son hata: {last_err}"
        )

    media_id = str(getattr(media, "pk", "") or getattr(media, "id", "") or "")
    uploaded_at = time.strftime("%Y-%m-%dT%H:%M:%S")

    result = {
        "name": jpg_path.stem,
        "media_id": media_id,
        "uploaded_at": uploaded_at,
        "status": "draft",
        "type": "photo",
    }
    emit(f"✓ Photo draft gönderildi (media_id={media_id})", "info")
    _append_upload_log(cfg, result)
    return result


def _append_upload_log(cfg: Config, entry: dict[str, Any]) -> None:
    """Her upload sonrası uploads_log dosyasına JSON line ekler."""
    if cfg.instagram is None:
        return
    path = cfg.project_root / cfg.instagram.uploads_log
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry, ensure_ascii=False) + "\n")


def read_upload_log(cfg: Config) -> dict[str, dict[str, Any]]:
    """uploads_log'u {name → {media_id, uploaded_at, status}} sözlüğü olarak döner.
    UI'da 'bu reel zaten drafts'ta' rozeti için."""
    out: dict[str, dict[str, Any]] = {}
    if cfg.instagram is None:
        return out
    path = cfg.project_root / cfg.instagram.uploads_log
    if not path.exists():
        return out
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
                if e.get("name"):
                    out[e["name"]] = e
            except json.JSONDecodeError:
                continue
    return out


def logout(cfg: Config) -> bool:
    """Session dosyasını sil — bir sonraki upload'ta re-login."""
    if cfg.instagram is None:
        return False
    session_path = cfg.project_root / cfg.instagram.session_file
    if session_path.exists():
        session_path.unlink()
        log.info(f"Session silindi: {session_path.name}")
        return True
    return False
