"""macOS native notification helper via osascript.

Kullanım:
    from src.mac_notifier import notify
    notify("Yeni post onay bekliyor", subtitle="Haber otomasyonu",
           message="japonyaruyasi — inceleyip yayınla")

Notification'a tıklamak Chrome widget'ını AÇMAZ (osascript sınırı) — sadece
bilgilendirme amaçlı. Widget zaten sürekli açık olmalı.
"""
from __future__ import annotations

import shutil
import subprocess
from typing import Optional

from src.utils.logging import get_logger

log = get_logger("notify")


def _escape_applescript(s: str) -> str:
    """AppleScript string literal içinde geçerli olacak şekilde kaçır."""
    return s.replace("\\", "\\\\").replace('"', '\\"')


def notify(title: str, message: str = "", subtitle: Optional[str] = None,
           sound: str = "Glass") -> bool:
    """macOS notification göster. Sadece macOS'ta çalışır; diğer platformlarda
    session bilgisi log'a yazılır ve False döner."""
    if shutil.which("osascript") is None:
        log.info(f"[notify:mock] {title} — {message}")
        return False
    parts = [f'display notification "{_escape_applescript(message)}"']
    parts.append(f' with title "{_escape_applescript(title)}"')
    if subtitle:
        parts.append(f' subtitle "{_escape_applescript(subtitle)}"')
    if sound:
        parts.append(f' sound name "{_escape_applescript(sound)}"')
    script = "".join(parts)
    try:
        subprocess.run(["osascript", "-e", script], check=False, timeout=5,
                       capture_output=True)
        return True
    except (subprocess.SubprocessError, OSError) as exc:
        log.warning(f"osascript notify başarısız: {exc}")
        return False
