#!/usr/bin/env bash
# QA senaryo runner — flutter test integration_test/ ile ilk 10 senaryoyu
# koşar, sonuçları mobile/qa/latest-run.json'a yazar.
#
# Kullanım (mobile/ dizininden):
#   ./qa/run_and_report.sh
#
# Dashboard'ı görmek için: `python3 -m http.server 8766` (qa/ içinde).
set -euo pipefail

cd "$(dirname "$0")/.."  # mobile/

echo "→ flutter pub get"
flutter pub get > /dev/null

echo "→ integration_test koşuluyor…"
# Headless test — device gerekmez. --machine JSON çıktısı stdout'a düşer.
flutter test integration_test/scenario_runner_test.dart --machine > qa/.raw-run.json 2>&1 || true

# Runner test kendisi qa/latest-run.json'a yazar (tearDownAll).
if [ -f qa/latest-run.json ]; then
  echo ""
  echo "✓ Rapor: qa/latest-run.json"
  # Kısa özet
  python3 - <<'PY'
import json, sys
try:
    d = json.load(open('qa/latest-run.json'))
    results = d.get('results', [])
    total = len(results)
    passed = sum(1 for r in results if r.get('status') == 'pass')
    failed = sum(1 for r in results if r.get('status') == 'fail')
    print(f"Toplam koşulan: {total}")
    print(f"Geçti:  {passed}")
    print(f"Kaldı:  {failed}")
    if failed:
        print("\nKalan senaryolar:")
        for r in results:
            if r.get('status') == 'fail':
                print(f"  {r['id']}: {r.get('error', 'unknown')}")
except Exception as e:
    print("Rapor parse edilemedi:", e, file=sys.stderr)
PY
else
  echo "⚠ qa/latest-run.json bulunamadı — flutter test çıktısı:"
  tail -30 qa/.raw-run.json 2>/dev/null || true
  exit 1
fi

echo ""
echo "→ Dashboard: mobile/qa/dashboard.html (python3 -m http.server 8766 → localhost:8766/dashboard.html)"
