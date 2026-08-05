#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -d ".venv" ]; then
  echo "❌ .venv yok. Önce: python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
  exit 1
fi

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8420}"

echo "🎬 Japan Reels Maker web arayüzü → http://${HOST}:${PORT}"
exec .venv/bin/python -m uvicorn src.web.app:app --host "$HOST" --port "$PORT"
