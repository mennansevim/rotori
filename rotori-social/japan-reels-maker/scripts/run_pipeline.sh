#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -d ".venv" ]; then
  echo "❌ .venv yok. Önce: python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
  exit 1
fi

PY=".venv/bin/python"
EXTRA=""
if [[ "${1:-}" == "--pilot" ]]; then
  EXTRA="--pilot"
  echo "▶ PILOT MODE"
fi

echo "═════════════════════════════════════════"
echo "🎬 REELS PIPELINE $(date +%H:%M:%S)"
echo "═════════════════════════════════════════"

echo ""
echo "[1/4] Vision analiz (llava)…"
$PY -m src.step1_analyze $EXTRA

echo ""
echo "[2/4] Mekan gruplama…"
$PY -m src.step2_group

echo ""
echo "[3/4] Dify kurgu planı üretimi…"
$PY -m src.step3_dify

echo ""
echo "[4/4] MoviePy render…"
$PY -m src.step4_render

echo ""
echo "✅ Bitti. Çıktı: output/reels/"
ls -la output/reels/ | tail -20
