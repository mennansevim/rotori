# Flutter iOS Release Quality Analysis (2026-07-26)

## Scope
This report covers Phase 1 (Repository & Application Analysis), Phase 2 (Risk-Based Test Strategy), and Phase 3 (Static Analysis & Build Verification) for the Flutter app in `mobile/`.

---

## 1) Repository & Application Analysis

### Toolchain and Platform (Confirmed)
- Flutter SDK (local): `3.44.4` (stable)
- Dart SDK (local): `3.12.2`
- Declared constraints:
  - `pubspec.yaml`: Dart `>=3.4.0 <4.0.0`, Flutter `>=3.24.0`
  - `pubspec.lock`: Dart `>=3.12.0 <4.0.0`, Flutter `>=3.44.0`
- Minimum iOS version: `15.5`
  - `ios/Podfile`: `platform :ios, '15.5'`
  - `ios/Runner.xcodeproj/project.pbxproj`: `IPHONEOS_DEPLOYMENT_TARGET = 15.5`
- Supported Apple device families: `1,2` (iPhone + iPad)

### Project Structure (Confirmed)
- Flutter app root: `mobile/`
- Main source folders:
  - `lib/core` (routing, app core)
  - `lib/data` (repositories, stores, adapters)
  - `lib/domain` (business logic and generators)
  - `lib/features` (UI features/screens)
- Native iOS assets:
  - `ios/Runner/**`
  - iOS docs: `docs/APPLE_SIGNIN_SETUP.md`, `docs/IOS_WIDGET_SETUP.md`

### Application Purpose (Confirmed)
Trip planning and trip execution companion app focused on Japan travel workflows: planning itineraries, viewing day plans/maps/weather/checklists, handling tickets/OCR, reminders, and travel utilities.

### Major Features and Screens (Confirmed)
- Auth:
  - `features/auth/auth_screen.dart`
  - `features/auth/auth_repository.dart`
- Plans:
  - `features/plans/plans_list_screen.dart`
  - `features/plans/plan_editor_screen.dart`
  - `features/plans/plan_viewer_screen.dart`
- Planner wizard:
  - `features/planner/planner_screen.dart`
  - `features/planner/steps/*`
- Viewer tools:
  - map/day map, weather, checklist, budget, rewards map, phrases, compass, prep checklist
  - `features/viewer/*`
- Reminders and notifications:
  - `features/reminders/reminders_screen.dart`
  - `features/notifications/notifications_service_*.dart`
- Ticket OCR:
  - `features/shared/ticket_ocr.dart` (+ platform-specific impl)

### Primary User Journeys (Confirmed)
1. Launch app → authenticate (email/password or Apple) → open plans list.
2. Create/edit plan in planner → publish/preview → open plan viewer.
3. Use day map + weather + checklist during trip.
4. Add reminders and receive local notifications.
5. Add ticket content/OCR assistance.

### Architecture Summary (Confirmed)
- State management: `flutter_riverpod`
- Navigation: `go_router` in `core/router.dart` + some local `Navigator.push`
- Backend/data:
  - Supabase (`supabase_flutter`) for auth and plan/checklist data
  - External weather API (`open-meteo`) in `data/weather_service.dart`
- Local storage:
  - `SharedPreferences` used broadly for reminders, language, stats, geofence, cache
- Authentication/session:
  - Supabase session observed by providers/router
  - Apple Sign-In flow with nonce hashing
- Notifications:
  - Local notifications only (`flutter_local_notifications`)
- Deep linking:
  - Outbound map links present (`google_maps_launcher.dart`); no strong evidence of inbound universal-link router handling in current flow
- Native integration:
  - Home widget hook (`home_widget`), iOS setup documented manually

### Security/Privacy-Sensitive Areas (Confirmed)
- Auth/session handling (`features/auth/*`, `main.dart`)
- Location usage (`Info.plist` usage descriptions)
- Camera/photo usage (`Info.plist` usage descriptions)
- App Group / widget communication path (`home_widget` setup docs)

### Explicitly Not Found / Assumed
- No in-app purchase/subscription system found in `mobile/lib/**`.
- No production payment logic discovered.
- No custom iOS `MethodChannel` implementation found in `ios/Runner/**`.
- These are static-code observations; device/runtime behavior still needs validation.

---

## 2) Feature Map, Screen Inventory, and Flow Diagram

### Feature Map
- Authentication
- Plan management (create/edit/list/view)
- Planner wizard with multiple themed steps
- Trip viewer utilities (map/weather/checklists/phrases/budget/compass/reward)
- Reminder scheduling + notifications
- Ticket OCR assistance
- Home screen widget refresh hook

### Screen Inventory (Representative)
- `/auth`
- `/plans`
- `/plans/:id/edit`
- `/plans/:id/view`
- `/plans/:id/prep`
- `/reminders`
- Planner step screens under `features/planner/steps/*`
- Viewer utility screens under `features/viewer/*`

### User Flow Diagram (Text)
1. App launch
2. Session check via providers/router
3. If unauthenticated → Auth screen
4. If authenticated → Plans list
5. Plan selection:
   - Edit path → planner screens → save/publish
   - View path → viewer hub and utility tools
6. Reminders/checklists/weather/map/OCR used during trip
7. Logout returns user to protected-route-safe state

### Critical Business Flows
- Auth/session route protection
- Plan create/edit/save/load from backend/cache
- Viewer reliability for day map/checklist/weather
- Reminder creation/listing and notification scheduling
- Error handling for network/API failures

---

## 3) Risk-Based Strategy

### P0 — Release Blocking
- App fails to launch or route-guard loop on startup/auth restore.
- Auth broken (email/password or Apple Sign-In) preventing entry.
- Protected screens accessible after logout.
- Critical plan data loss/corruption (local cache or backend sync).
- Release build failure for iOS.
- Corrupted persisted state causing unrecoverable startup.

### P1 — Core Functional Risks
- Plans list/editor/viewer regressions.
- Infinite loading and API error handling gaps.
- Offline behavior and dirty-state sync not flushing predictably.
- Reminder scheduling/permission handling inconsistencies.
- Navigation edge cases with mixed `go_router` + direct `Navigator` pushes.
- iOS capability misconfiguration for Apple Sign-In and widget integration.

### P2 — Edge Cases
- Long/tricky text (Turkish chars, emoji, accessibility text scaling).
- Small screens and overflow in planner/viewer screens.
- Slow network/API timeout behavior.
- Dark mode and locale/date/timezone edge behavior.

### P3 — Low-Value (De-prioritized)
- Pixel-perfect styling assertions.
- Trivial getter/setter tests.
- Broad snapshot tests without defect-detection value.

---

## 4) Existing Testing Infrastructure

### What Exists (Confirmed)
- `test/domain/**`: business/domain logic tests
- `test/data/**`: repository/storage tests
- `test/features/**`: feature/widget-level tests
- `test/qa_scenarios_test.dart`: scenario catalog runner writing JSON report
- `qa/dashboard.html`: report visualization
- `qa/scenarios.json`: scenario definitions
- `qa/run_and_report.sh`: shell runner

### Testability Issues / Gaps
- QA runner mismatch risk:
  - `qa/run_and_report.sh` currently targets an integration test path that is not present.
  - Actual scenario runner exists in `test/qa_scenarios_test.dart`.
- Missing dedicated `integration_test/` suite for top 3–5 P0 journeys on iOS device/simulator.
- Limited direct automation evidence for:
  - Apple Sign-In cancellation/error/revocation matrix
  - Notification permission and delivery lifecycle
  - iOS widget end-to-end behavior
  - Real-device location/geofence behavior

### Areas Requiring Manual Testing
- Apple Sign-In end-to-end on real Apple IDs/sandbox
- Notification permission transitions and delivery timing
- Home widget updates on iPhone lock/home screens
- Geolocation/permissions in real movement contexts
- Accessibility/VoiceOver and dynamic type stress checks

---

## 5) Static Analysis & Build Verification (Executed)

All commands were executed in `mobile/`.

1. `flutter --version` ✅
2. `dart --version` ✅
3. `flutter doctor -v` ⚠️
   - Android SDK missing (non-blocker for iOS release)
4. `flutter pub get` ✅
5. `dart format --output=none --set-exit-if-changed .` ❌ (Exit 1)
   - Root cause: repository contains unformatted files (reported by formatter)
   - Suggested fix: run formatter in a dedicated formatting PR, then re-run gate
6. `flutter analyze` ❌ (Exit 1)
   - 12 issues, all `info` level (deprecations/style)
   - Notable: deprecated `anonKey` usage in `lib/main.dart`
   - Suggested fix: clean up deprecations/lints in a focused maintenance pass
7. `flutter test` ✅
   - Test suite passed (`266` tests)
   - Observed repeated image codec exceptions in map-related tests, but suite still passed
8. `flutter build ios --release --no-codesign` ✅
   - Successful release app build
   - Warning: several plugins do not yet support Swift Package Manager (future compatibility risk)
9. `flutter pub outdated --no-transitive` ✅
   - Multiple direct dependencies constrained behind latest resolvable versions

### Severity Categorization
- **Blocker:** none confirmed by current checks
- **Critical:** none confirmed by current checks
- **High:** QA command drift; potential auth/iOS capability misconfiguration risk if not validated on device
- **Medium:** analyzer info debt/deprecations; formatting gate currently failing; dependency staleness
- **Low:** style-only lints and ordering preferences
- **Informational:** Android SDK missing on this machine for Android dev

---

## 6) Immediate Implementation Priorities

1. Fix QA runner entrypoint drift (`qa/run_and_report.sh` → existing test target).
2. Add high-value P0/P1 regression tests (auth route protection, session transitions, sync/dirty-state behavior).
3. Introduce a minimal `integration_test/` suite for launch + auth + primary flow + error recovery.
4. Add iOS manual-gate checklist execution evidence for Apple Sign-In and widget setup.
5. Schedule deprecation/format maintenance PR to pass strict quality gates cleanly.

---

## 7) Assumptions and Limits

- This report is based on repository and command execution in local environment.
- Real iPhone behavior (permissions, notifications, Apple Sign-In revoke, widget lifecycle) still requires simulator/physical-device passes.
- No destructive production API operations were executed.

---

## 8) Follow-up Iteration Update (2026-07-26)

After the first baseline report, a low-risk lint/deprecation cleanup pass was applied.

### Implemented
- Fixed Supabase init deprecation in `lib/main.dart` (`anonKey` → `publishableKey`).
- Fixed `curly_braces_in_flow_control_structures` in `lib/features/planner/planner_screen.dart`.
- Fixed `sort_child_properties_last` in `lib/features/planner/steps/title_step.dart`.
- Replaced deprecated `.withOpacity(...)` with `.withValues(alpha: ...)` in `lib/features/planner/widgets/booking_alert_dialog.dart`.
- Fixed `prefer_const_declarations` warnings in `test/qa_scenarios_test.dart`.

### Re-Verification (Executed)
1. `flutter analyze` ✅ (`No issues found!`)
2. `flutter test` ✅ (`All tests passed`, 271 tests)

### Notes
- Map-related widget tests still print repeated codec exceptions during run output, but test suite remains green.
- Device-only iOS validation items (Apple Sign-In credential state, notification behavior, widget lifecycle, permissions) remain in manual/real-device gate.

---

## 9) Parallel Execution Update (2026-07-26)

Two streams were executed in parallel:

### Stream A — Integration Coverage Bootstrap
- Added `integration_test/` contract-style suite:
  - `integration_test/app_launch_test.dart`
  - `integration_test/authentication_test.dart`
  - `integration_test/main_flow_test.dart`
  - `integration_test/error_recovery_test.dart`
  - `integration_test/helpers/test_harness.dart`
- Added CI-friendly mirror suite:
  - `test/integration_contracts_test.dart`

Execution notes:
- `flutter test integration_test` requires a supported device target and did not run in the current host setup (web prompt / macOS project missing).
- Contract validation was completed via `flutter test test/integration_contracts_test.dart` (pass).
- Added helper runner: `qa/run_integration_tests.sh`
  - First tries the native `integration_test` lane when a supported target exists.
  - Falls back to `test/integration_contracts_test.dart` when this host cannot execute device integration lane.

### Stream B — iOS Manual Gate Hardening
- Added release gate checklist document:
  - `docs/IOS_RELEASE_MANUAL_GATE_CHECKLIST.md`
- Includes:
  - P0/P1 gate items
  - Apple Sign-In matrix
  - Permission matrix
  - Real-device matrix
  - Sign-off template
