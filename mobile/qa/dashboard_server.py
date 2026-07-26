#!/usr/bin/env python3
"""QA Dashboard server — statik dashboard'ı servis eder + `POST /run` ile
refresh-dashboard.sh'ı tetikler ve canlı log döner (SSE benzeri chunked).

Kullanım (mobile/ dizininden):
    python3 qa/dashboard_server.py             # 8766
    PORT=9000 python3 qa/dashboard_server.py

Dashboard: http://localhost:8766/dashboard.html
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path

QA_DIR = Path(__file__).resolve().parent
MOBILE_DIR = QA_DIR.parent
REFRESH_SCRIPT = QA_DIR / "refresh-dashboard.sh"

# Aynı anda birden çok koşum başlatılmasın.
_RUN_LOCK = threading.Lock()
_CURRENT_PROC: subprocess.Popen | None = None


class Handler(SimpleHTTPRequestHandler):
    # Serve from qa/ (dashboard.html, JSON'lar burada).
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(QA_DIR), **kw)

    def log_message(self, fmt, *args):
        sys.stderr.write("[dashboard] " + fmt % args + "\n")

    def do_GET(self):  # noqa: N802
        if self.path == "/status":
            self._json({
                "running": _CURRENT_PROC is not None and _CURRENT_PROC.poll() is None,
                "cwd": str(MOBILE_DIR),
                "script": str(REFRESH_SCRIPT),
            })
            return
        super().do_GET()

    def do_POST(self):  # noqa: N802
        if self.path != "/run":
            self.send_error(404, "unknown endpoint")
            return

        if not _RUN_LOCK.acquire(blocking=False):
            self._json({"ok": False, "error": "already running"}, status=409)
            return

        # Chunked text/plain: canlı log akıtacağız.
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

        global _CURRENT_PROC
        try:
            _CURRENT_PROC = subprocess.Popen(
                ["bash", str(REFRESH_SCRIPT)],
                cwd=str(MOBILE_DIR),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                bufsize=1,
                text=True,
            )
            assert _CURRENT_PROC.stdout is not None
            for line in _CURRENT_PROC.stdout:
                self._chunk(line)
            _CURRENT_PROC.wait()
            self._chunk(f"\n[exit code: {_CURRENT_PROC.returncode}]\n")
        except Exception as exc:  # noqa: BLE001
            self._chunk(f"\n[server error] {exc}\n")
        finally:
            self._chunk("")  # terminating chunk
            _CURRENT_PROC = None
            _RUN_LOCK.release()

    # ── helpers ────────────────────────────────────────────────────────
    def _chunk(self, text: str) -> None:
        try:
            data = text.encode("utf-8")
            self.wfile.write(f"{len(data):X}\r\n".encode())
            self.wfile.write(data)
            self.wfile.write(b"\r\n")
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    port = int(os.environ.get("PORT", "8766"))
    HTTPServer.allow_reuse_address = True
    server = HTTPServer(("127.0.0.1", port), Handler)
    print(f"→ Dashboard: http://localhost:{port}/dashboard.html")
    print(f"→ Trigger:   POST http://localhost:{port}/run")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")


if __name__ == "__main__":
    main()
