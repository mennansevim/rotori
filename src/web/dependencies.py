"""Router'ların paylaştığı tekil bağımlılıklar.

app.py hâlâ Config ve JobManager singleton'larını yükler; router'lar bu
modül üzerinden erişir. Böylece devre dışı bir router bağımsız test
edilebilir ve app.py refactor'u aşamalı yürüyebilir.

Strangler pattern kuralı: app.py'yi bir kerede parçalama. Route'ları teker
teker taşırken bu modül üzerinden Config/JobManager alınır. app.py hâlâ
kendi kopyalarını tutar ve module state (`_cfg`, `_manager`) burada
paylaşılır — çift-init olmaz.
"""
from __future__ import annotations

from typing import TYPE_CHECKING, Optional

if TYPE_CHECKING:
    from src.config import Config
    from src.web.jobs import JobManager


_cfg: Optional["Config"] = None
_manager: Optional["JobManager"] = None


def set_runtime(cfg: "Config", manager: "JobManager") -> None:
    """app.py başlangıçta bir kez çağırır."""
    global _cfg, _manager
    _cfg = cfg
    _manager = manager


def get_cfg() -> "Config":
    if _cfg is None:
        raise RuntimeError(
            "dependencies.set_runtime() çağrılmamış — app.py bootstrap eksik."
        )
    return _cfg


def get_manager() -> "JobManager":
    if _manager is None:
        raise RuntimeError(
            "dependencies.set_runtime() çağrılmamış — app.py bootstrap eksik."
        )
    return _manager
