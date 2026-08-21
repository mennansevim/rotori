# Hava Koşullarına Göre Günlük Rota Yenileme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a per-day “Havaya göre düzenle” action that creates an AI weather-aware reorder preview and replaces only the selected day after user approval.

**Architecture:** Reuse the existing Open-Meteo forecast and `review-route` Edge Function contracts. Add current-weather fields and a selected-day review/apply flow in the viewer; keep validation and persistence in the existing `PlanEditSession`/repository path, with an undo snapshot for the selected day.

**Tech Stack:** Flutter, Riverpod, Supabase Edge Functions, Open-Meteo, existing route-review JSON schema, Flutter widget/unit tests.

**Spec:** `docs/superpowers/specs/2026-08-19-weather-aware-day-replan-design.md`

## Global Constraints

- AI never adds, removes, or moves stops between days.
- Locked stops retain their original index.
- User approval is required before a plan mutation.
- Weather/API/LLM failure leaves the current plan unchanged.
- OpenAI credentials remain server-side.

---

### Task 1: Extend weather data for current conditions

**Files:**
- Modify: `rotori-mobile/lib/data/weather_service.dart`
- Test: `rotori-mobile/test/data/weather_service_test.dart`

**Interfaces:**
- Produce `CurrentWeather` and `WeatherSnapshot` data with current precipitation/rain signal plus the existing daily forecast.
- Keep `DayForecast` and `fetchForecast` backward compatible for existing viewer code.

- [ ] Add failing fixtures/tests for parsing current precipitation and for missing current fields.
- [ ] Run the weather service tests and verify the new assertions fail.
- [ ] Add Open-Meteo `current=precipitation,rain,weather_code,temperature_2m` parsing with nullable fallback.
- [ ] Run weather tests and confirm all pass.

### Task 2: Add selected-day weather review contract

**Files:**
- Modify: `supabase/functions/review-route/index.ts`
- Modify: `rotori-mobile/lib/data/ai_route_reviewer.dart`
- Test: `rotori-mobile/test/data/ai_route_reviewer_test.dart`

**Interfaces:**
- Consume one `Day` plus weather snapshot through the existing review request.
- Produce a validated `RouteReviewResult` containing the candidate order and up to three notes.

- [ ] Add a failing test that rejects a candidate with a different stop set or a locked stop at a different index.
- [ ] Run the reviewer tests and verify the validator fails before implementation.
- [ ] Extend the server prompt/schema to include current weather and explicitly request weather-driven indoor/outdoor ordering without claiming hourly certainty.
- [ ] Extend the client validator and request builder for a single selected day while preserving the existing multi-day path.
- [ ] Run the reviewer tests and the Edge Function type check.

### Task 3: Add per-day action and preview/apply flow

**Files:**
- Modify: `rotori-mobile/lib/features/plans/plan_viewer_screen.dart`
- Modify: `rotori-mobile/lib/core/l10n.dart`
- Test: `rotori-mobile/test/features/viewer/plan_viewer_test.dart`

**Interfaces:**
- Consume `_forecast`, the selected `DayPlan`, and the existing route review provider/client.
- Produce a per-day `Havaya göre düzenle` button, preview sheet, approval callback, and selected-day undo state.

- [ ] Add widget tests for one action per day, loading/error states, cancel without mutation, and approval changing only the selected day.
- [ ] Run the focused widget tests and verify the new expectations fail.
- [ ] Implement the action beneath each day card, dynamic weather label, preview comparison, and confirmation CTA.
- [ ] Apply only the selected day through `PlanEditSession`, persist it, and expose a one-step undo that restores the captured day snapshot.
- [ ] Run the focused viewer tests and confirm they pass.

### Task 4: Align the standalone weather screen

**Files:**
- Modify: `rotori-mobile/lib/features/viewer/weather_screen.dart`
- Modify: `rotori-mobile/lib/core/l10n.dart`
- Test: `rotori-mobile/test/features/viewer/weather_screen_test.dart`

**Interfaces:**
- Consume the shared route forecast and current weather provider.
- Produce day-by-day expandable weather cards with the same dates/destinations used by the viewer.

- [ ] Add widget tests for collapsed cards, expanded details, and per-day action visibility.
- [ ] Implement the accordion card layout with condition, min/max, precipitation probability, and short AI/weather note slot.
- [ ] Run the weather screen widget tests and confirm no overflow at the existing mobile test sizes.

### Task 5: Verify and document the feature

**Files:**
- Modify: `docs/CURRENT_TASK.md`
- Modify: `docs/DECISIONS.md` only if the final implementation changes the approved contract.

- [ ] Run the complete targeted weather/reviewer/viewer test set.
- [ ] Run `flutter analyze --no-pub` on all changed Dart files and Edge Function type checking.
- [ ] Run `git diff --check` and a web preview build.
- [ ] Inspect the 390 dp preview for accordion density, button labels, preview confirmation, and undo behavior.
- [ ] Record the completed feature and verification results in `docs/CURRENT_TASK.md`.
