#!/usr/bin/env python3
"""Flutter test --machine JSON akışını dashboard için yapılandırılmış rapora çevirir.

stdin'den `flutter test --machine` çıktısını (newline-delimited JSON) okur,
suite (dosya) bazında gruplayıp qa/flutter-tests.json üretir.

Kullanım (mobile/ dizininden):
    flutter test --machine | python3 qa/collect_flutter_tests.py [out.json]
"""
import json
import os
import sys
from datetime import datetime, timezone


def main() -> int:
    out_path = sys.argv[1] if len(sys.argv) > 1 else "qa/flutter-tests.json"

    suites = {}      # suiteId -> {path, tests: {testId: {...}}}
    tests = {}       # testId -> record
    started_ms = None
    finished_ms = None

    for raw in sys.stdin:
        raw = raw.strip()
        if not raw or not raw.startswith("{"):
            continue
        try:
            ev = json.loads(raw)
        except json.JSONDecodeError:
            continue

        etype = ev.get("type")
        ts = ev.get("time")
        if ts is not None:
            started_ms = ts if started_ms is None else min(started_ms, ts)
            finished_ms = ts if finished_ms is None else max(finished_ms, ts)

        if etype == "suite":
            s = ev.get("suite", {})
            suites[s.get("id")] = {
                "path": s.get("path") or "(bilinmeyen)",
                "tests": {},
            }
        elif etype == "testStart":
            t = ev.get("test", {})
            # Yükleme/derleme sanal testlerini atla (name "loading ...").
            name = t.get("name", "")
            if name.startswith("loading ") or name.startswith("(setUpAll)") or name.startswith("(tearDownAll)"):
                continue
            tests[t.get("id")] = {
                "name": name,
                "suiteId": t.get("suiteID"),
                "startMs": ev.get("time"),
                "status": "pending",
                "durationMs": None,
                "error": None,
            }
        elif etype == "testDone":
            tid = ev.get("testID")
            rec = tests.get(tid)
            if rec is None:
                continue
            if ev.get("hidden"):
                tests.pop(tid, None)
                continue
            result = ev.get("result", "")
            skipped = ev.get("skipped", False)
            rec["status"] = "skip" if skipped else ("pass" if result == "success" else "fail")
            if rec["startMs"] is not None and ev.get("time") is not None:
                rec["durationMs"] = ev["time"] - rec["startMs"]
        elif etype == "error":
            tid = ev.get("testID")
            rec = tests.get(tid)
            if rec is not None:
                err = ev.get("error", "")
                stack = ev.get("stackTrace", "")
                rec["error"] = (err + ("\n" + stack if stack else "")).strip()
                rec["status"] = "fail"

    # Testleri suite'lere yerleştir.
    for rec in tests.values():
        sid = rec.pop("suiteId", None)
        rec.pop("startMs", None)
        suite = suites.get(sid)
        if suite is None:
            suite = suites.setdefault(sid, {"path": "(bilinmeyen)", "tests": {}})
        suite["tests"][rec["name"]] = rec

    suite_list = []
    total = passed = failed = skipped = 0
    for suite in suites.values():
        t_list = list(suite["tests"].values())
        if not t_list:
            continue
        s_pass = sum(1 for t in t_list if t["status"] == "pass")
        s_fail = sum(1 for t in t_list if t["status"] == "fail")
        s_skip = sum(1 for t in t_list if t["status"] == "skip")
        total += len(t_list)
        passed += s_pass
        failed += s_fail
        skipped += s_skip
        # Dosya adını kısalt: test/ göreli yol.
        path = suite["path"]
        rel = path
        if "/mobile/" in path:
            rel = path.split("/mobile/", 1)[1]
        suite_list.append({
            "path": rel,
            "total": len(t_list),
            "passed": s_pass,
            "failed": s_fail,
            "skipped": s_skip,
            "durationMs": sum((t["durationMs"] or 0) for t in t_list),
            "tests": sorted(t_list, key=lambda t: t["name"]),
        })

    suite_list.sort(key=lambda s: (s["failed"] == 0, s["path"]))

    report = {
        "generatedAt": datetime.now(timezone.utc).astimezone().isoformat(),
        "durationMs": (finished_ms - started_ms) if (started_ms is not None and finished_ms is not None) else None,
        "summary": {
            "total": total,
            "passed": passed,
            "failed": failed,
            "skipped": skipped,
        },
        "suites": suite_list,
    }

    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "w") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    print(f"✓ {out_path} — {passed}/{total} geçti, {failed} kaldı, {skipped} skip, {len(suite_list)} suite")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
