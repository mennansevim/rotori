#!/usr/bin/env bash
# rotori-social deploy — Pi'de tek komutluk güncelleme.
# Kullanım (Pi'de, ~/rotori-social içinde):  ./deploy.sh
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f config.yaml ]; then
  echo "❌ config.yaml yok. Önce Mac'ten kopyala:"
  echo "   scp config.yaml mennano@192.168.1.60:~/rotori-social/config.yaml"
  exit 1
fi

echo "→ git pull"
git pull --ff-only

echo "→ docker compose up -d --build"
docker compose up -d --build

echo "→ container durumu"
docker compose ps

echo ""
echo "✓ Deploy tamam. Test:"
echo "  curl -I http://localhost:3090"
echo "  curl -I https://api.rotori.app"
