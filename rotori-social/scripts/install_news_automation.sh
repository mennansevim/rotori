#!/usr/bin/env bash
# Japonya haber otomasyonunu macOS launchd'ye kurar — her 2 günde bir çalışır.
# Uygulama (web) açık olmasa da çalışır. Kaldırmak için: aşağıdaki "Kaldır" satırı.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$PROJECT_DIR/.venv/bin/python"
LABEL="com.japonyaruyasi.news"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$PROJECT_DIR/data/news_automation"
INTERVAL=172800   # 2 gün (saniye)

if [ ! -x "$PY" ]; then
  echo "✖ venv python bulunamadı: $PY"
  echo "  Önce: python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
  exit 1
fi

mkdir -p "$LOG_DIR" "$(dirname "$PLIST")"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PY</string>
        <string>-m</string>
        <string>src.news_automation</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$PROJECT_DIR</string>
    <key>StartInterval</key>
    <integer>$INTERVAL</integer>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/run.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/run.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo "✓ Haber otomasyonu kuruldu (her 2 günde bir)"
echo "  Label : $LABEL"
echo "  Plist : $PLIST"
echo "  Log   : $LOG_DIR/run.log"
echo "  Python: $PY"
echo ""
echo "  Şimdi bir kez elle çalıştır (test):"
echo "    cd \"$PROJECT_DIR\" && \"$PY\" -m src.news_automation"
echo ""
echo "  Kaldırmak için:"
echo "    launchctl unload \"$PLIST\" && rm \"$PLIST\""
