#!/usr/bin/env bash
# Tüm test hatlarını koşar ve dashboard verisini toplar:
#   1) Flutter unit/widget suite (--machine)  → qa/flutter-tests.json
#   2) QA senaryoları                          → qa/latest-run.json
#   3) Integration contract suite              → qa/integration-run.json
#
# Kullanım (mobile/ dizininden):
#   ./qa/refresh-dashboard.sh          # topla + özet
#   ./qa/refresh-dashboard.sh --serve  # topla + localhost:8766 aç
set -uo pipefail

cd "$(dirname "$0")/.."  # mobile/

SERVE=0
[ "${1:-}" = "--serve" ] && SERVE=1

echo "→ flutter pub get"
flutter pub get > /dev/null

# ── 1) Full Flutter suite ────────────────────────────────────────────────
echo "→ Flutter test suite (--machine)…"
set -o pipefail
flutter test --machine --exclude-tags uiflow 2>/dev/null | python3 qa/collect_flutter_tests.py qa/flutter-tests.json
FLUTTER_RC=$?
set +o pipefail

# ── 2) QA senaryoları ────────────────────────────────────────────────────
echo ""
echo "→ QA senaryoları…"
QA_TEST_TARGET="${QA_TEST_TARGET:-test/qa_scenarios_test.dart}"
flutter test "${QA_TEST_TARGET}" --machine > qa/.raw-run.json 2>&1 || true
QA_RC=0
python3 - <<'PY' || QA_RC=1
import json, sys

try:
  d = json.load(open('qa/latest-run.json'))
except Exception:
  sys.exit(1)

failed = sum(1 for r in d.get('results', []) if r.get('status') == 'fail')
sys.exit(1 if failed else 0)
PY

# ── 3) Integration contract suite ────────────────────────────────
echo ""
echo "→ Integration contract suite (--machine)…"
flutter test test/integration_contracts_test.dart --machine 2>/dev/null \
  | python3 qa/collect_flutter_tests.py qa/integration-run.json
INTEG_RC=$?

# ── 4) UI Otomasyon (gerçek gesture) suite ────────────────────
necho() { echo "$@"; }
echo ""
echo "→ UI Otomasyon (gesture) suite (--machine)…"
flutter test test/ui_flow/ --machine 2>/dev/null \
  | python3 qa/collect_flutter_tests.py qa/uiflow-run.json
UIFLOW_RC=$?

# ── Özet ─────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
python3 - <<'PY'
import json
from datetime import datetime

def safe_load(path):
  try:
    return json.load(open(path))
  except Exception:
    return None

def normalize(path, label):
  d = safe_load(path)
  if not d:
    return {
      "label": label,
      "path": path,
      "generatedAt": None,
      "summary": {"total": 0, "passed": 0, "failed": 0, "skipped": 0},
    }

  s = d.get("summary") or {}
  if "total" not in s:
    res = d.get("results", [])
    s = {
      "total": len(res),
      "passed": sum(1 for r in res if r.get("status") == "pass"),
      "failed": sum(1 for r in res if r.get("status") == "fail"),
      "skipped": 0,
    }

  return {
    "label": label,
    "path": path,
    "generatedAt": d.get("generatedAt") or d.get("completedAt") or d.get("startedAt"),
    "summary": {
      "total": int(s.get("total", 0)),
      "passed": int(s.get("passed", 0)),
      "failed": int(s.get("failed", 0)),
      "skipped": int(s.get("skipped", 0)),
    },
  }

def summ(path, label):
    try:
        d = json.load(open(path))
        s = d.get("summary") or {}
        if "total" not in s:  # latest-run.json formatı
            res = d.get("results", [])
            s = {
                "total": len(res),
                "passed": sum(1 for r in res if r.get("status") == "pass"),
                "failed": sum(1 for r in res if r.get("status") == "fail"),
            }
        icon = "✓" if s.get("failed", 0) == 0 else "✗"
        print(f"{icon} {label:26} {s.get('passed',0)}/{s.get('total',0)} geçti"
              + (f"  ({s['failed']} kaldı)" if s.get('failed') else ""))
    except Exception as e:
        print(f"· {label:26} rapor yok ({e})")

summ("qa/flutter-tests.json",  "Flutter suite")
summ("qa/latest-run.json",     "QA senaryoları")
summ("qa/integration-run.json","Integration")
summ("qa/uiflow-run.json",    "UI Otomasyon")

flutter = normalize("qa/flutter-tests.json", "flutter")
qa = normalize("qa/latest-run.json", "qa")
integration = normalize("qa/integration-run.json", "integration")
uiflow = normalize("qa/uiflow-run.json", "uiflow")

overall = {
  "total": flutter["summary"]["total"] + qa["summary"]["total"] + integration["summary"]["total"] + uiflow["summary"]["total"],
  "passed": flutter["summary"]["passed"] + qa["summary"]["passed"] + integration["summary"]["passed"] + uiflow["summary"]["passed"],
  "failed": flutter["summary"]["failed"] + qa["summary"]["failed"] + integration["summary"]["failed"] + uiflow["summary"]["failed"],
  "skipped": flutter["summary"]["skipped"] + qa["summary"]["skipped"] + integration["summary"]["skipped"] + uiflow["summary"]["skipped"],
}

dashboard = {
  "generatedAt": datetime.now().astimezone().isoformat(),
  "overall": overall,
  "sources": {
    "flutter": flutter,
    "qa": qa,
    "integration": integration,
    "uiflow": uiflow,
  },
}

with open("qa/test-dashboard.json", "w") as f:
  json.dump(dashboard, f, indent=2, ensure_ascii=False)
PY
echo "════════════════════════════════════════"
echo ""
echo "→ Dashboard: qa/dashboard.html"

if [ "$SERVE" -eq 1 ]; then
  echo "→ http://localhost:8766/dashboard.html (Ctrl+C ile durdur)"
  cd qa && python3 -m http.server 8766
fi

# Herhangi bir suite kaldıysa non-zero dön.
[ "${FLUTTER_RC:-0}" -eq 0 ] && [ "${QA_RC:-0}" -eq 0 ] && [ "${INTEG_RC:-0}" -eq 0 ] && [ "${UIFLOW_RC:-0}" -eq 0 ]
