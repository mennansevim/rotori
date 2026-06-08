# review-commit

**%100 ücretsiz** lokal AI ile çalışan, terminal üzerinden doğal dil komutu alan kod inceleme + commit + push + Pi deploy ajanı.

`npm run review` deyince:

1. **Komut sorulur** — sadece üç seçenek var: `commit`, `push`, `deploy`.
2. Komut bir action plan'a dönüşür ve onaylanınca çalışır:
   - **commit**: AI Türkçe yorum + commit msg önerir, onaylarsanız `git add -A && git commit`
   - **push**: `git push origin <branch>`
   - **deploy**: Pi'ye SSH bağlanıp `git pull && docker compose ...`

## Kurulum

### 1) Bağımlılıklar

```bash
cd tools/review-commit
npm install
```

### 2) AI Sağlayıcı Seç

İki seçenek var:

#### A. **Ollama (ücretsiz, lokal — varsayılan)** ⭐

```bash
# Ollama kurulu mu?
which ollama
# Yoksa: brew install ollama && brew services start ollama

# Modeli indir (~2GB, bir kez)
ollama pull qwen2.5:3b
```

`.env` ayarı (default zaten):

```env
AI_PROVIDER=ollama
OLLAMA_MODEL=qwen2.5:3b
OLLAMA_URL=http://localhost:11434
```

**İnternet bile gerekmiyor**, hiçbir şey ödemiyorsun.

#### B. **Cursor SDK (ücretli, bulut)**

`.env`:

```env
AI_PROVIDER=cursor
CURSOR_API_KEY=cursor_...     # https://cursor.com/dashboard/cloud-agents
```

Daha kaliteli sonuç, Pro plan dahil kotasını yer.

### 3) Pi Deploy (opsiyonel)

`.env`:

```env
PI_HOST=192.168.1.60
PI_USER=mennano
PI_PASSWORD=945000
PI_REPO_DIR=agora-voice-chatbot-web
PI_BRANCH=main
PI_DEPLOY_CMD=git pull origin main && docker compose down && docker compose up -d --build
```

## Kullanım

### İnteraktif

```bash
npm run review
```

```
Ne yapılsın? > 
```

### CLI argümanı

```bash
npm run review -- "commit"
npm run review -- "push"
npm run review -- "deploy"
```

### Non-interaktif (`--yes`)

Tüm onayları otomatik **evet** yapar (Cursor agent skill'i de bunu kullanır):

```bash
npm run review -- --yes "commit"
npm run review -- --yes "push"
npm run review -- --yes "deploy"
```

## Komutlar

Sadece üç atomik komut. **Sıra önemli**: önce `commit`, sonra `push`, en son `deploy`.

| Komut | Yapılan |
|---|---|
| `commit` | `git add -A && git commit` (AI Türkçe yorum + Conventional Commits msg) |
| `push` | `git push origin main` |
| `deploy` | SSH → Pi → `git pull && docker compose down && up -d --build` |

Her birini ayrı çalıştır, ara sonucu doğrula, sonra bir sonrakine geç. Bu **güvenli akış**:
local commit'i bozarsan rollback kolay; push'tan sonra `git revert` gerekir; deploy'dan sonra
container restart'ı şart.

## Tam akış örneği

```
→ Repo: /Users/.../japan-trip
→ AI: ollama (qwen2.5:3b @ http://localhost:11434)

── Plan ──
  1. commit (AI yorumu + onay + git commit)
  2. push (git push origin main)
  3. deploy (SSH → Pi: cd <repo> && git pull && docker compose ...)
Sebep: Tüm değişiklikleri commit'le, push'la ve Pi'ye deploy et.

Bu plan ile devam edilsin mi? [E/h]: e

── Adım 1/3 — COMMIT ──
→ AI'a değişiklikler gönderiliyor (ollama (qwen2.5:3b))...

── Değişiklik Yorumu ──
2. gün planına Doğa Bilimleri Müzesi (Ueno) eklendi; Skytree saatleri
yeniden hizalandı, akşam Bic Camera durağı eklendi.

── Önerilen Commit Mesajı ──
feat(plan): add Ueno Nature & Science Museum and Bic Camera stops to day 2

Seçenekler: [E]vet · [D]üzenle · [İ]ptal
Seçiminiz: e
✓ Commit oluşturuldu.

── Adım 2/3 — PUSH ──
→ git push origin main
✓ Push tamamlandı.

── Adım 3/3 — DEPLOY ──
→ SSH mennano@192.168.1.60 → cd agora-voice-chatbot-web && git pull...
── Pi @ 192.168.1.60 ──
[+] Stopping 3/3
[+] Building 5.4s
✓ Pi'ye deploy tamamlandı.
```

## Ortam Değişkenleri

| Değişken | Açıklama | Varsayılan |
|---|---|---|
| `AI_PROVIDER` | `ollama` veya `cursor` | `ollama` |
| `OLLAMA_URL` | Ollama HTTP endpoint | `http://localhost:11434` |
| `OLLAMA_MODEL` | Lokal model adı | `qwen2.5:3b` |
| `CURSOR_API_KEY` | Cursor SDK auth (`AI_PROVIDER=cursor` ise) | - |
| `CURSOR_REVIEW_MODEL` | Cursor model id | `composer-2` |
| `PI_HOST` | Raspberry Pi IP / hostname | - |
| `PI_USER` | SSH kullanıcı adı | - |
| `PI_PASSWORD` | SSH parolası | - |
| `PI_PORT` | SSH portu | `22` |
| `PI_REPO_DIR` | Pi'deki repo dizini | - |
| `PI_BRANCH` | Pi'nin pull edeceği & push hedefi | `main` |
| `PI_DEPLOY_CMD` | Pi'de çalıştırılacak komut | - |

## Model seçimi (Ollama)

Daha kaliteli sonuç için:

| Model | Boyut | RAM | Türkçe / Kod kalitesi |
|---|---|---|---|
| `qwen2.5:1.5b` | ~1 GB | ~2 GB | düşük (hızlı) |
| **`qwen2.5:3b`** ⭐ | ~2 GB | ~4 GB | iyi (önerilen) |
| `qwen2.5:7b` | ~4.5 GB | ~8 GB | çok iyi |
| `llama3.2:3b` | ~2 GB | ~4 GB | iyi |

Değiştirmek için: `.env`'de `OLLAMA_MODEL=qwen2.5:7b` ve `ollama pull qwen2.5:7b`.

## Exit Kodları

| Kod | Anlam |
|---|---|
| `0` | Başarılı / kullanıcı iptal etti |
| `1` | Başlatma — provider hazır değil (Ollama açık değil, model yok, vb.) |
| `2` | AI run hatası |
| `3` | Commit komutu hatası |
| `4` | `git push` başarısız |
| `5` | SSH veya Pi deploy başarısız |
| `6` | Pi config eksik |

## Sorun Giderme

- **"Ollama'ya bağlanılamadı"** → `ollama serve` çalıştır veya `brew services start ollama`.
- **"Model X Ollama'da yok"** → `ollama pull qwen2.5:3b`.
- **"CURSOR_API_KEY tanımlı değil"** → `.env`'de `AI_PROVIDER=ollama` yap (ücretsiz çözer).
- **AI yanlış commit msg önerdi** → Onay sırasında `d` ile düzelt.
- **Pi bağlanamıyor** → `ssh mennano@192.168.1.60` ile elle dene.

## japan-trip deploy (statik build)

Repo kökünde `npm run build` → `dist/` (`index.html`, `data/`, `viewer/`, `planner/`).

Pi `.env` örneği:

```env
PI_REPO_DIR=japan-trip
PI_DEPLOY_CMD=git pull origin main && npm ci && npm run build && rsync -a --delete dist/ /var/www/japan-trip/
```

Cursor skill: `commit` → `push` → `deploy` (değişmedi).

## Mimari

```
review.ts
  ├─ dotenv (.env yükle)
  ├─ kullanıcı komutu (CLI arg veya readline)
  ├─ interpretCommand()
  │     ├─ defaultPlanForKeywords()  (hızlı yol)
  │     └─ aiPrompt()                (anlaşılmazsa AI sorar)
  └─ executePlan()
        ├─ runCommitFlow()  → diff + aiPrompt() + onay + git commit
        ├─ runPushFlow()    → git push
        └─ runDeployFlow()  → ssh2 → Pi

ai.ts
  └─ aiPrompt(prompt)
        ├─ ollama  → fetch http://localhost:11434/api/generate
        └─ cursor  → @cursor/sdk Agent.prompt()
```
