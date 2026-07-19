#!/usr/bin/env bash
set -euo pipefail

echo "Ollama modellerini indiriyorum…"
ollama pull llava:7b
ollama pull qwen2.5:3b

echo ""
echo "Yüklü modeller:"
ollama list
