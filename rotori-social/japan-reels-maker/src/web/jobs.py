from __future__ import annotations

import logging
import re
import subprocess
import sys
import threading
import time
from collections import deque
from pathlib import Path
from typing import Any, Callable

# Adım tanımları: numara -> (modül, insan-okur ad)
STEP_MODULES: dict[int, tuple[str, str]] = {
    1: ("src.step1_analyze", "Vision analiz (llava)"),
    2: ("src.step2_group", "Mekan gruplama"),
    3: ("src.step3_dify", "Dify kurgu planı"),
    4: ("src.step4_render", "MoviePy render"),
}

# tqdm ilerleme çubuğu satırlarını normal loglardan ayırmak için
_PROGRESS_RE = re.compile(r"\d+%\|| it/s|\d+/\d+ \[|\(\d+%\)")
# terminal renk kodlarını (ANSI) temizlemek için
_ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")

# in-process üretimde (generate) logları JobManager'a köprülemek için
_BRIDGE_LOGGER_NAMES = (
    "step3", "step4", "step1", "step2",
    # Haber üretimi de aynı JobManager üzerinden çalışır. Bu logger'lar
    # bağlanmadığında RSS/GPT/render aşamaları UI'da sessiz kalıyordu.
    "news", "openai", "story",
)


class _EmitLogHandler(logging.Handler):
    """step3/step4 vb. logger çıktısını canlı log tamponuna yazar."""

    def __init__(self, manager: "JobManager") -> None:
        super().__init__(level=logging.INFO)
        self._manager = manager

    def emit(self, record: logging.LogRecord) -> None:
        try:
            text = _ANSI_RE.sub("", record.getMessage()).strip()
            if not text:
                return
            if _PROGRESS_RE.search(text):
                self._manager.state["progress_line"] = text
                # encode % satırlarını hem progress_line hem log akışına koy
                if "(" in text and "%" in text:
                    self._manager._emit(text, "log")
                return
            if record.levelno >= logging.ERROR:
                kind = "error"
            elif record.levelno >= logging.WARNING:
                kind = "warn"
            else:
                kind = "log"
            self._manager._emit(text, kind)
        except Exception:  # noqa: BLE001
            self.handleError(record)


class JobManager:
    """Pipeline adımlarını subprocess olarak çalıştırır, çıktısını canlı toplar."""

    def __init__(self, project_root: Path) -> None:
        self.project_root = project_root
        self._lock = threading.Lock()
        self._thread: threading.Thread | None = None
        self._proc: subprocess.Popen[str] | None = None
        self._cancel = threading.Event()

        self._log: deque[dict[str, Any]] = deque(maxlen=4000)
        self._log_lock = threading.Lock()
        self._seq = 0

        self.state: dict[str, Any] = {
            "running": False,
            "log_seq": 0,
            "steps": [],
            "current_step": None,
            "step_status": {},          # {"1": "pending|running|done|error|cancelled"}
            "label": None,
            "pilot": False,
            "no_dify": False,
            "started_at": None,
            "finished_at": None,
            "error": None,
            "progress_line": "",        # en son tqdm satırı
        }

    # ---------- log ----------
    def _emit(self, text: str, kind: str = "log") -> None:
        with self._log_lock:
            self._seq += 1
            self._log.append({"seq": self._seq, "t": time.time(), "kind": kind, "text": text})

    def logs_since(self, since: int) -> tuple[list[dict[str, Any]], int]:
        with self._log_lock:
            entries = [e for e in self._log if e["seq"] > since]
            return entries, self._seq

    def _install_log_bridge(self) -> _EmitLogHandler:
        """In-process işlerde step logger'larını Canlı Süreç paneline bağla."""
        handler = _EmitLogHandler(self)
        for name in _BRIDGE_LOGGER_NAMES:
            lg = logging.getLogger(name)
            lg.setLevel(logging.INFO)
            # aynı handler'ı iki kez ekleme
            if not any(isinstance(h, _EmitLogHandler) for h in lg.handlers):
                lg.addHandler(handler)
        return handler

    def _remove_log_bridge(self, handler: _EmitLogHandler | None) -> None:
        if handler is None:
            return
        for name in _BRIDGE_LOGGER_NAMES:
            lg = logging.getLogger(name)
            if handler in lg.handlers:
                lg.removeHandler(handler)

    # ---------- kontrol ----------
    def start(self, steps: list[int], pilot: bool, no_dify: bool) -> None:
        with self._lock:
            if self.state["running"]:
                raise RuntimeError("Zaten çalışan bir iş var.")
            steps = [s for s in steps if s in STEP_MODULES]
            if not steps:
                raise ValueError("Geçerli adım yok.")
            self._cancel.clear()
            self.state = {
                "running": True,
                "log_seq": self._seq,
                "steps": steps,
                "current_step": None,
                "step_status": {str(s): "pending" for s in steps},
                "label": None,
                "pilot": pilot,
                "no_dify": no_dify,
                "started_at": time.time(),
                "finished_at": None,
                "error": None,
                "progress_line": "",
            }
            self._thread = threading.Thread(
                target=self._run, args=(steps, pilot, no_dify), daemon=True
            )
            self._thread.start()

    def cancel(self) -> bool:
        with self._lock:
            if not self.state["running"]:
                return False
            self._cancel.set()
            if self._proc and self._proc.poll() is None:
                self._proc.terminate()
            return True

    # ---------- genel amaçlı iş (subprocess değil, in-process callable) ----------
    def start_callable(self, label: str, target: Callable[[Callable[..., None], "threading.Event"], None]) -> None:
        """Rastgele bir işi (ör. kategori bazlı reel üretimi) arka planda çalıştırır.

        `target(emit, cancel)` imzalı olmalı: emit(text, kind) log yayınlar,
        cancel bir threading.Event'tir. Loglar mevcut "Canlı Süreç" akışına düşer.
        """
        with self._lock:
            if self.state["running"]:
                raise RuntimeError("Zaten çalışan bir iş var.")
            self._cancel.clear()
            self.state = {
                "running": True,
                "log_seq": self._seq,
                "steps": [],
                "current_step": None,
                "step_status": {},
                "label": label,
                "pilot": False,
                "no_dify": True,
                "started_at": time.time(),
                "finished_at": None,
                "error": None,
                "progress_line": "",
            }
            self._thread = threading.Thread(target=self._run_callable, args=(label, target), daemon=True)
            self._thread.start()

    def _run_callable(self, label: str, target: Callable[..., None]) -> None:
        bridge = self._install_log_bridge()
        self._emit(f"▶ {label} başladı", "info")
        try:
            target(self._emit, self._cancel)
            if self._cancel.is_set():
                self._emit("⏹ İptal edildi.", "warn")
            else:
                self._emit(f"✅ {label} tamamlandı.", "info")
        except Exception as exc:  # noqa: BLE001
            self.state["error"] = str(exc)
            self._emit(f"✖ Beklenmeyen hata: {exc}", "error")
        finally:
            self._remove_log_bridge(bridge)
            self.state["running"] = False
            self.state["current_step"] = None
            self.state["progress_line"] = ""
            self.state["finished_at"] = time.time()
            self._proc = None

    # ---------- yürütme ----------
    def _run(self, steps: list[int], pilot: bool, no_dify: bool) -> None:
        self._emit(f"▶ Pipeline başladı — adımlar: {', '.join(map(str, steps))}"
                   f"{' [PILOT]' if pilot else ''}{' [NO-DIFY]' if no_dify else ''}", "info")
        try:
            for s in steps:
                if self._cancel.is_set():
                    self.state["step_status"][str(s)] = "cancelled"
                    self._emit("⏹ İptal edildi.", "warn")
                    break
                self.state["current_step"] = s
                self.state["step_status"][str(s)] = "running"
                rc = self._run_step(s, pilot, no_dify)
                if self._cancel.is_set():
                    self.state["step_status"][str(s)] = "cancelled"
                    self._emit("⏹ İptal edildi.", "warn")
                    break
                if rc != 0:
                    self.state["step_status"][str(s)] = "error"
                    self.state["error"] = f"Adım {s} hata verdi (çıkış kodu {rc})."
                    self._emit(f"✖ Adım {s} başarısız (rc={rc}).", "error")
                    break
                self.state["step_status"][str(s)] = "done"
                self._emit(f"✓ Adım {s} tamamlandı.", "info")
            else:
                self._emit("✅ Pipeline tamamlandı.", "info")
        except Exception as exc:  # noqa: BLE001
            self.state["error"] = str(exc)
            self._emit(f"✖ Beklenmeyen hata: {exc}", "error")
        finally:
            self.state["running"] = False
            self.state["current_step"] = None
            self.state["progress_line"] = ""
            self.state["finished_at"] = time.time()
            self._proc = None

    def _run_step(self, step: int, pilot: bool, no_dify: bool) -> int:
        module, label = STEP_MODULES[step]
        cmd = [sys.executable, "-u", "-m", module]
        if step == 1 and pilot:
            cmd.append("--pilot")
        if step == 3 and no_dify:
            cmd.append("--no-dify")

        self._emit(f"$ {' '.join(cmd[3:])}  ({label})", "cmd")
        proc = subprocess.Popen(
            cmd,
            cwd=str(self.project_root),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        self._proc = proc
        assert proc.stdout is not None
        for line in proc.stdout:
            line = _ANSI_RE.sub("", line.rstrip("\n"))
            if not line.strip():
                continue
            if _PROGRESS_RE.search(line):
                self.state["progress_line"] = line.strip()
            else:
                self._emit(line)
        proc.wait()
        self.state["progress_line"] = ""
        return proc.returncode
