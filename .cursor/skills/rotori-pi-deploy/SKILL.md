---
name: rotori-pi-deploy
description: >-
  Deploy the Rotori marketing site (rotori-website) and social/reels stack
  (rotori-social) from this monorepo to the Raspberry Pi. Use when the user
  says "deploy website", "deploy social", "siteyi deploy et", "sosyali deploy
  et", or asks to publish either surface to the Pi. Covers the monorepo →
  separate Pi folder mapping, ports, and health checks.
---

# rotori-pi-deploy

Bu monorepo (`japan-trip`) tek bir yerde toplanmıştır ama Raspberry Pi iki
**ayrı** klasörden servis eder. Deploy = ilgili monorepo alt klasörünü Pi'deki
karşılığına gönderip container'ı yeniden kurmak.

## Pi topolojisi

| Yüzey | Yerel kaynak | Pi klasörü | GitHub remote | Container | Port |
|---|---|---|---|---|---|
| Tanıtım sitesi | `rotori-website/` | `~/rotori-web` | `mennansevim/rotori-web` | `rotori-web` | `3080 → 80` |
| Sosyal / reels | `rotori-social/` | `~/rotori-social` | `mennansevim/rotori-social` | `rotori-social` | `3090 → 8420` |

- **İsim eşlemesi:** yerel `rotori-website/` ↔ Pi `rotori-web/` (kozmetik fark,
  değiştirme — container isimleri `docker-compose.yml`'deki `name:`/`container_name:`
  alanından gelir, klasörden değil).
- **SSH:** `mennano@192.168.1.60` (host adı `raspberrypi`). Anahtar tabanlı auth
  çalışır; `-o BatchMode=yes` ile şifre sormadan bağlanır.
- **Dış erişim:** Cloudflare Tunnel `localhost:3080 → rotori.app`,
  `localhost:3090 → api.rotori.app`. Container'lar dış networke doğrudan expose
  edilmez.

## Deploy yöntemi: rsync (doğrudan)

Monorepo alt klasörünü Pi'deki klasöre `rsync` ile senkronla, sonra container'ı
yeniden kur. Ayrı yayın repolarına (`rotori-web`/`rotori-social`) push **zorunlu
değildir**; monorepo tek kaynaktır.

### Website deploy

```bash
# 1) İçeriği Pi'ye senkronla (legacy/ ve videos/ hariç — public'e girmez).
rsync -az --delete \
  --exclude 'legacy/' --exclude 'videos/' \
  /Users/sevimm/Documents/Projects/rotori-app/rotori-website/ \
  mennano@192.168.1.60:~/rotori-web/public/

# 2) Container'ı yeniden kur + sağlık kontrolü.
ssh -o BatchMode=yes mennano@192.168.1.60 \
  'cd ~/rotori-web && docker compose up -d --build && sleep 3 && \
   curl -sI http://localhost:3080 | head -1'
```

Doğrulama: `curl -sI https://rotori.app | head -1` → `HTTP/2 200`.

> `--delete` Pi'deki `public/`'i yerelin birebir aynası yapar. Pi'de elle eklenen
> dosya varsa silinir — kasıtlı. `--exclude` listesi büyürse buraya ekle.

### Social deploy

> ⚠️ **KRİTİK — social'ı ASLA monorepo'dan rsync ETME.** Yereldeki
> `rotori-social/` Pi'dekinin tam kopyası **değil** (eksik snapshot). Pi'nin
> `~/rotori-social`'ı kendi GitHub reposundan gelir
> (`git@github.com:mennansevim/rotori-social.git`). Monorepo'dan `rsync --delete`
> yaparsan Pi'nin gerçek `docker-compose.yml`, `Dockerfile`, `deploy.sh`, `bin/`,
> `content/`, `docs/`'unu **siler**. (2026-08-05'te yaşandı; `git reset --hard`
> ile kurtarıldı, kesinti olmadı.)

`rotori-social` **kendi git akışıyla** deploy edilir. Pi'de `config.yaml` gizli
ve mevcut — dokunma. Değişiklik `rotori-social` GitHub reposuna push edilir,
Pi çeker:

```bash
# Pi'de, kendi deploy scriptiyle (git pull --ff-only + compose up):
ssh -o BatchMode=yes mennano@192.168.1.60 \
  'cd ~/rotori-social && ./deploy.sh'
```

`deploy.sh`: `git pull --ff-only && docker compose up -d --build`.
Doğrulama: `curl -sI https://api.rotori.app | head -1` ve
`docker compose ps` → `healthy`.

**Kurtarma (yanlışlıkla monorepo'dan silme yapıldıysa):**
```bash
ssh -o BatchMode=yes mennano@192.168.1.60 \
  'cd ~/rotori-social && git reset --hard HEAD && git clean -fd'
# config.yaml + output/ + assets/story_backgrounds/ gitignored → korunur.
```

## Kritik kurallar

- **Gizli dosyalar asla senkronlanmaz:** `config.yaml`, `.env`, `.venv/`,
  Supabase anahtarları. rsync `--exclude` listesinde kalmalı.
- **Port çakışması yok:** website `3080`, social `3090`, agora `3003`, dify
  `3000/5001`. Yeni servis eklerken bunlarla çakışma.
- **Sağlık kontrolü zorunlu:** her deploy sonrası ilgili `curl -I` ile
  `HTTP .. 200` doğrula. `docker compose ps`'te `healthy` bekle.
- **Sıra:** önce rsync (içerik), sonra `docker compose up -d --build` (imaj),
  sonra health check.

## Alternatif: yayın-repo (git) akışı

Git-tabanlı deploy tercih edilirse: monorepo alt klasörünü ilgili yayın reposuna
(`rotori-web` / `rotori-social`) kopyala → commit → push → Pi'de
`cd ~/<klasör> && ./deploy.sh` (`git pull --ff-only && docker compose up -d --build`).
Dezavantaj: iki yere push bakımı. rsync bunu ortadan kaldırdığı için varsayılan
değildir.
