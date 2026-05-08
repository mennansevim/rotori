---
name: japan-trip-deploy
description: >-
  Run the project's review-commit tool for git commit, git push, or Raspberry
  Pi docker redeploy. Use when the user types exactly "commit", "push", or
  "deploy" — these are the only three supported commands. Lives at
  tools/review-commit/.
---

# japan-trip-deploy

Three atomic commands. Always run them **in order** for safety: commit first,
then push, then deploy.

## Commands

| User says | Action |
|---|---|
| `commit` | `git add -A && git commit` (AI-generated message) |
| `push` | `git push origin main` |
| `deploy` | SSH to Pi → `git pull && docker compose down && up -d --build` |

The recommended workflow is **commit → push → deploy**, run as three separate
invocations so the user verifies each step.

## How to invoke

```bash
cd tools/review-commit && npm run review -- --yes "<command>"
```

Examples:

```bash
cd tools/review-commit && npm run review -- --yes "commit"
cd tools/review-commit && npm run review -- --yes "push"
cd tools/review-commit && npm run review -- --yes "deploy"
```

`--yes` auto-confirms every prompt.

## Workflow

1. **Confirm with the user** before running `push` or `deploy` (they touch
   remote systems). For `commit`, just run it — local and reversible.
2. Run the requested command via `Shell` with `block_until_ms: 120000`.
3. Surface the final status lines and report success or failure.

## When NOT to invoke

- User asks to **review** changes without committing → run `git diff` and
  summarise instead.
- User wants a **custom commit message** → run interactively in their
  terminal: `cd tools/review-commit && npm run review`.
- No working-tree changes and request is `commit` → tell the user there's
  nothing to commit.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | success / cancelled |
| 1 | provider not ready (Ollama down) |
| 2 | AI run error |
| 3 | git commit failed |
| 4 | git push failed |
| 5 | SSH / Pi deploy failed |
| 6 | Pi config missing in `.env` |

## Tool internals

- AI: Ollama `qwen2.5:3b` (free, local).
- Pi: `mennano@192.168.1.60`, deploys `agora-voice-chatbot-web` via docker compose.
- Source: `tools/review-commit/{review,ai,deploy}.ts`.
