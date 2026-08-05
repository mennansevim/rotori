# Japan Reels Maker — AI Coding Agent Instructions

## Project Purpose
Automated Instagram Reels pipeline for the account **@japonyaruyasi** (Turkish-language Japan travel). Converts a ~1000-video archive into ready-to-post Reels + Story cards via AI scripting and video rendering.

## Architecture: 4-Step Pipeline

```
Source Videos → [Step1: Analyze] → metadata.csv
             → [Step2: Group]   → data/kurgu_planlari/*_input.json
             → [Step3: Script]  → data/kurgu_planlari/*_final.json
             → [Step4: Render]  → output/reels/*.mp4
```

Parallel automations: `news_automation.py` (Mon 20:00) + `topic_automation.py` (Fri 20:00) → `output/stories/`

## Key Entry Points

```bash
# Full pipeline (CLI)
./scripts/run_pipeline.sh

# Pilot mode — processes only N videos (config: pilot_count)
./scripts/run_pipeline.sh --pilot

# Web dashboard
./scripts/run_web.sh
```

## Critical Conventions

### Content Quality — Seed-First Principle
`src/persona.py` contains hand-crafted seeds for 20+ Japan locations. **These always win over LLM output.** Never modify seed data without factual verification. The cliché filter (`is_quality_text()`) rejects: "büyülü", "eşsiz", "muhteşem", "erken git", "rahat ayakkabı", etc.

### Video Rendering — Clean Mode Default
`add_overlays: false` (default in `RenderConfig`) — no text burned into video. Captions are typed manually in Instagram. Only change to `true` when specifically implementing overlay features.

### Turkish Language Specifics
- Uppercase conversion uses `turkish_upper()` in `step4_render.py` (handles `i→İ`, `ı→I`)
- Vision model (llava:7b) is prompted in **English** — Turkish synthesis is a separate step via qwen2.5:3b
- Japanese proper nouns (Shinkansen, onsen, ryokan) stay untranslated per persona rules

### iPhone 17+ Compatibility
HEVC/DoVi/apac videos are auto-transcoded to H.264 via `ensure_h264_cache()` in `step4_render.py`. Cache keyed by mtime, stored at `data/frames/`. Do not remove this step.

## Configuration
- All secrets in `config.yaml` (gitignored). Template: `config.yaml.example`
- `src/config.py` — typed dataclasses; change defaults here, not inline
- `data/automation_config.json` — scheduler settings (news: Mon 20:00, topic: Fri 20:00)

## AI/LLM Stack
| Role | Model | Fallback |
|---|---|---|
| Vision labeling | llava:7b (Ollama) | filename parsing |
| Scene synthesis | qwen2.5:3b (Ollama) | — |
| Scripting | Dify workflow (qwen2.5:7b) | OpenAI gpt-4o-mini |
| Story/news captions | OpenAI gpt-4o-mini | — |

Content generation priority in `step3_dify.py`: persona seeds → Dify → OpenAI → local LLM.

## Instagram Publishing
`src/instagram_publisher.py` — 3-tier auth: session cache → sessionid cookie → username+password+TOTP. Device fingerprint in `data/instagram_device.json` (locale: `tr_TR`, UTC+3). Upload log in `data/instagram_uploads.jsonl`. Caption truncated to 2200 chars.

## Idempotency Pattern
All pipeline steps skip already-processed files. Safe to re-run partial pipelines. Steps 1–4 must run **sequentially** (no inter-step parallelism).

## Key Files Reference
- `src/persona.py` — content seeds + cliché filter + persona definition
- `src/step3_dify.py` — scripting logic, quality gates, concurrency
- `src/step4_render.py` — rendering, Turkish text, iPhone compat
- `src/story_generator.py` — PIL story card layout + Unsplash integration
- `assets/topic_pool.json` — 25 evergreen Japan topics (Turkish titles + Unsplash queries)
- `dify/system_prompt.md` — Dify node prompt template (6 input vars → JSON output schema)
