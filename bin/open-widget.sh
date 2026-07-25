#!/bin/bash
# Japan Reels Maker — Onay widget'ını Chrome app-mode'da aç.
#
# Chrome / Chromium / Brave / Edge — hangisi varsa onu kullanır.
# app-mode: tarayıcı chrome'u olmayan, native pencere görünümlü.
#
# Widget URL: config.yaml → instagram.public_base_url (varsa) veya localhost.
# Auto-open on login için:
#     ln -sf "$(pwd)/bin/open-widget.sh" ~/Library/LaunchAgents/japan-widget.sh
#     …veya launchd plist ekle (README).

set -euo pipefail

# URL — varsayılan localhost, opsiyonel ilk parametre ile override
URL="${1:-http://localhost:8000/?view=widget}"

# Chrome benzeri tarayıcıları sırayla dene (Chrome > Brave > Edge > Chromium)
BROWSER=""
for candidate in \
    "/Applications/Google Chrome.app" \
    "/Applications/Brave Browser.app" \
    "/Applications/Microsoft Edge.app" \
    "/Applications/Chromium.app"; do
    if [[ -d "$candidate" ]]; then
        BROWSER="$candidate"
        break
    fi
done

if [[ -z "$BROWSER" ]]; then
    # Fallback: default browser'ı aç (widget görünümü olmadan, sekme olarak)
    echo "⚠ Chromium tabanlı tarayıcı bulunamadı — default browser'da açılıyor."
    open "$URL"
    exit 0
fi

# App-mode + sabit pencere boyutu (Instagram post 4:5'e uygun)
EXE="$BROWSER/Contents/MacOS/$(basename "$BROWSER" .app)"
# Google Chrome özel binary adı
[[ "$BROWSER" == "/Applications/Google Chrome.app" ]] && EXE="$BROWSER/Contents/MacOS/Google Chrome"
[[ "$BROWSER" == "/Applications/Brave Browser.app" ]] && EXE="$BROWSER/Contents/MacOS/Brave Browser"
[[ "$BROWSER" == "/Applications/Microsoft Edge.app" ]] && EXE="$BROWSER/Contents/MacOS/Microsoft Edge"

echo "🖥 Widget açılıyor: $URL"
echo "   tarayıcı: $BROWSER"

# app-mode ile aç, arka planda bırak
"$EXE" \
    --app="$URL" \
    --window-size=460,860 \
    --window-position=100,100 \
    --user-data-dir="$HOME/.japan-widget-profile" \
    >/dev/null 2>&1 &

disown
