---
name: rotori-social-deploy
description: Push the current Japan Reels Maker application to the rotori-social GitHub remote and deploy it safely to the Raspberry Pi service behind api.rotori.app. Use when the user says deploy, deploy et, publish, or asks to send the current app to api.rotori.app.
---

# Rotori Social Deploy

Use this skill for the complete application release flow: commit any requested
changes, push `main` to `https://github.com/mennansevim/rotori-social.git`,
update `/home/mennano/rotori-social` on the Pi, rebuild `rotori-social`, and
verify `https://api.rotori.app`.

## Release workflow

1. Inspect `git status`, current branch, and the latest commit. Never reset,
   stash, delete, or overwrite unrelated work.
2. If the user requested a code change, validate the relevant files and create
   a focused commit. Do not make an empty commit.
3. Push the current `main` branch to the `social` remote. The target is
   `mennansevim/rotori-social`, not the `origin` remote.
4. Connect with public-key SSH only:

   ```bash
   ssh -o BatchMode=yes -o PreferredAuthentications=publickey \
     -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
     -o ConnectTimeout=10 -i ~/.ssh/id_ed25519 \
     mennano@192.168.1.60
   ```

5. Deploy from `/home/mennano/rotori-social`. If the Pi has local changes,
   inspect them first. Preserve the local `data/automation_config.json`,
   especially the configured Monday + Thursday 20:00 news schedule. Do not
   reset or stash it. Temporarily copy it to a user-writable home backup,
   fast-forward the repository, restore the file, then rebuild.
6. Build with the real commit metadata:

   ```bash
   export GIT_COMMIT="$(git rev-parse --short HEAD)"
   export BUILD_DATE="$(git log -1 --format=%cd --date=format:%Y-%m-%d\ %H:%M)"
   docker compose up -d --build
   docker compose ps
   ```

7. Verify both:

   ```bash
   docker ps --filter name=rotori-social --format "{{.Names}}\t{{.Status}}"
   curl -sS --max-time 15 https://api.rotori.app/api/version
   curl -sS -o /dev/null -w 'studio HTTP %{http_code}\n' \
     --max-time 15 https://api.rotori.app/studio
   ```

## Safety and failure handling

- Stop and report if SSH authentication fails, the Pi repository has an
  unresolved conflict, or the target remote is not `rotori-social`.
- Never use passwords, `sshpass`, `git reset --hard`, destructive Docker
  cleanup, or broad file deletion.
- If a local Pi config conflicts with `git pull`, preserve it and use the
  safe temporary-copy workflow above; do not silently replace it with the
  repository version.
- Report the pushed commit, container health, API version, and studio HTTP
  status after a successful deployment.
