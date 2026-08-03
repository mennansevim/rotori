# Agent Mimarisi: Konuşma-Tabanlı Commit / Push / Deploy CLI

Bu doküman, `tools/review-commit/` altındaki agent'ın mimarisini ve onu **başka bir uygulamaya** taşırken neyi nasıl uyarlayacağını anlatır.

---

## 1. Tek cümleyle ne yapar?

Doğal dilde verilen tek bir Türkçe/İngilizce komutu — örn. *"en son değişiklikleri gönder"* — alıp, **git commit + git push + uzak sunucuya SSH deploy** zincirine çevirir; her aşamada interactive onay alır veya `--yes` ile sessiz çalışır.

```
Kullanıcı:  "en son değişiklikleri gönder"
   ↓
[Plan]   commit  →  push  →  deploy
   ↓
[Onay]   E/h
   ↓
[Çalıştır] git add -A && git commit + git push + ssh → docker compose
```

---

## 2. Tasarım hedefleri

| # | Hedef | Nasıl karşılandı |
|---|---|---|
| 1 | **Konuşma odaklı** | Plain-Türkçe komut → action plan'a çevrilir |
| 2 | **AI-bağımsız** | Provider abstraction; Ollama (lokal/ücretsiz) ↔ Cursor SDK ↔ vs. takılabilir |
| 3 | **Cürbel** (interactive ↔ otomatik) | Aynı binary `npm run review` ile insan, `--yes` ile makine kullanır |
| 4 | **Ucuz / ücretsiz default** | `qwen2.5:3b` lokal, internet gerekmiyor, kota yok |
| 5 | **Idempotent ve güvenli** | Her aşama ayrı exit code, push/deploy onayları, parola repo dışı (`.env`) |
| 6 | **Cursor agent ile entegre** | `.cursor/skills/<name>/SKILL.md` ile chat'ten otomatik çağırılır |

---

## 3. Yüksek seviye mimari

```
┌────────────────────────────────────────────────────────────────┐
│                          KULLANICI                             │
│           (terminal / Cursor chat / CI script)                  │
└──────────────────────────┬──────────────────────────────────────┘
                           │ doğal dil komutu
                           ▼
┌────────────────────────────────────────────────────────────────┐
│                      review.ts (orchestrator)                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  interpretCommand()                                       │  │
│  │   ├─ defaultPlanForKeywords()  ← hızlı yol (AI yok)      │  │
│  │   └─ aiPrompt()                ← anlaşılmazsa AI yorumlar│  │
│  └──────────────────────┬────────────────────────────────────┘  │
│                          ▼ Plan { actions[], rationale }        │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  executePlan()                                            │  │
│  │   ├─ runCommitFlow()  ─→ git status/diff + AI msg + git  │  │
│  │   ├─ runPushFlow()    ─→ git push                         │  │
│  │   └─ runDeployFlow()  ─→ deploy.ts (SSH)                  │  │
│  └──────────────────────────────────────────────────────────┘  │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                ┌──────────┴───────────┐
                ▼                      ▼
       ┌──────────────────┐    ┌──────────────────┐
       │     ai.ts        │    │    deploy.ts     │
       │  Provider abstr. │    │   SSH client     │
       │  ┌─Ollama────┐   │    │   (ssh2 lib)     │
       │  ├─Cursor    │   │    │  Pi → docker     │
       │  └─...       │   │    │     compose      │
       └──────────────────┘    └──────────────────┘
```

---

## 4. Katmanlar

### 4.1. Orchestrator (`review.ts`)
Sorumluluk: kullanıcı niyetini yorumla → plana çevir → planı sırayla çalıştır.

İçerdiği fonksiyonlar:

| Fonksiyon | Sorumluluk |
|---|---|
| `main()` | CLI arg parse (`--yes`), readline, plan onayı |
| `interpretCommand(input)` | Komutu `Plan`'a çevir |
| `defaultPlanForKeywords(input)` | Ön-tanımlı keyword eşleşmesi (hızlı yol) |
| `executePlan(plan)` | Action listesini sırayla çalıştır |
| `runCommitFlow()` | `git status`/`diff` → AI msg → onay → `git commit` |
| `runPushFlow(branch)` | branch doğrulama → `git push origin <branch>` |
| `runDeployFlow()` | `loadPiConfig()` + `runOnPi()` |
| `ask(question, autoAnswer)` | Readline wrapper, `AUTO_YES` modunda otomatik cevap |

### 4.2. AI Provider Abstraction (`ai.ts`)
Sorumluluk: prompt → text. Provider'lar arasında aynı arayüz.

```typescript
interface AiResult {
  text: string;
  provider: AiProvider;
  model: string;
}

async function aiPrompt(prompt: string): Promise<AiResult>
function describeProvider(): string
function ensureProviderReady(): { ok: true } | { ok: false; reason: string }
```

Provider seçimi: `process.env.AI_PROVIDER` (`ollama` | `cursor` | ...).

Yeni provider eklemek = `ai.ts` içine 1 fonksiyon (örn. `geminiPrompt()`) + `aiPrompt()`'a 1 if dalı + `.env`'de `AI_PROVIDER=gemini`.

### 4.3. Remote Execution (`deploy.ts`)
Sorumluluk: SSH bağlan, komutu çalıştır, çıktıyı stream et.

```typescript
loadPiConfig(env): { config?: PiDeployConfig; missing: string[] }
runOnPi(config): Promise<{ exitCode, signal? }>
```

`pty: true` ile stream'lenen output `process.stdout`'a real-time yazılır (docker spinner'lar dahil).

### 4.4. Konfigürasyon (`.env` + `dotenv`)
Tüm sırlar ve ortam değişkenleri `.env`'de. Repo'ya `.env.example` template gider, `.env` `.gitignore`'da.

---

## 5. Veri Akışı: `Plan` & `Action`

### 5.1. Tipler

```typescript
type Action =
  | { type: "commit" }
  | { type: "push"; branch?: string }
  | { type: "deploy" };

interface Plan {
  actions: Action[];
  rationale: string;   // 1-2 cümle Türkçe açıklama
}
```

`Plan` = AI/keyword tarafından üretilen, kullanıcıya gösterilen ve onaylanan **iş listesi**.

### 5.2. Keyword fallback

```typescript
function defaultPlanForKeywords(input: string): Plan | null {
  const t = input.toLowerCase().trim();
  if (!t) return { actions: [{ type: "commit" }], rationale: "Boş komut..." };
  if (/^commit$|kaydet/.test(t)) return { actions: [{ type: "commit" }], rationale: "..." };
  if (/^push$|yükle/.test(t)) return { actions: [{ type: "push" }], rationale: "..." };
  if (/^deploy/.test(t)) return { actions: [{ type: "deploy" }], rationale: "..." };
  if (/en son değişiklikleri gönder|pi'ye gönder|hepsini yap/.test(t)) {
    return { actions: [{ type: "commit" }, { type: "push" }, { type: "deploy" }], rationale: "..." };
  }
  return null;  // → AI'a düş
}
```

**Mantık**: AI çağrısı 1-3 saniye, keyword eşleşmesi anında. Yaygın 5-6 ifade keyword'le yakalanır → AI sadece nadir ifadelerde çalışır.

### 5.3. AI fallback prompt

```
Kullanıcı CLI tool'a Türkçe komut verdi. Bu komutu action'lara çevir.
KOMUT: "${input}"
MEVCUT ACTIONS: ...
KURALLAR: ...
YANLIZCA aşağıdaki JSON ile cevap ver:
{"actions":[{"type":"commit"}],"rationale":"<1-2 cümle>"}
```

Cevap parse edilirken JSON'un metin içinde gömülü olabileceği varsayılır:

```typescript
function parseAiPlan(text: string): Plan | null {
  const match = text.match(/\{[\s\S]*"actions"[\s\S]*\}/);
  if (!match) return null;
  try { return JSON.parse(match[0]); } catch { return null; }
}
```

Parse başarısız olursa `commit` fallback'i çalışır — **asla** `null` plan dönmez.

---

## 6. Action: Commit Flow Detayı

```
git status (porcelain)        ──→ değişiklik var mı?
git diff --staged --no-color  ──→ AI'a context
git diff --no-color           ──→ AI'a context
                                  ↓
buildCommitPrompt(...)            ↓
                                  ↓
aiPrompt(prompt)                  ↓ ~5s (Ollama 3b)
                                  ↓
parseCommitOutput(text):
  ── Yorum (Türkçe) ──
  ── Commit Mesajı ── (Conventional Commits formatında)
                                  ↓
ask("[E]vet [D]üzenle [İ]ptal")
  E → git add -A && git commit -m
  D → readline ile yeni mesaj
  İ → return 0
```

### 6.1. Diff bütçeleme

```typescript
const MAX_DIFF_BYTES = 100 * 1024;  // 100 KB
function clipDiff(diff: string): string {
  if (diff.length <= MAX_DIFF_BYTES) return diff;
  return diff.slice(0, MAX_DIFF_BYTES) + "\n...[clipped]...";
}
```

Büyük diff'ler model context'ini doldurmasın diye kesilir.

### 6.2. Commit prompt şablonu

```
Sen yardımcı bir Türkçe konuşan kod inceleme asistanısın.

İki şey üret:
1. ── Değişiklik Yorumu ── altında 2-4 cümle Türkçe özet
2. ── Önerilen Commit Mesajı ── altında **Conventional Commits** formatında tek satırlık İngilizce mesaj

Git status:
${status}

Staged diff:
${stagedDiff}

Unstaged diff:
${unstagedDiff}
```

---

## 7. Cürbel (interactive ↔ otomatik)

Tek bir `AUTO_YES` flag'i ve `ask()` wrapper'ıyla yönetilir:

```typescript
let AUTO_YES = false;

async function ask(question: string, autoAnswer = "e"): Promise<string> {
  if (AUTO_YES) {
    process.stdout.write(`${question}[auto: ${autoAnswer}]\n`);
    return autoAnswer;
  }
  const rl = createInterface({ input, output });
  try { return (await rl.question(question)).trim(); }
  finally { rl.close(); }
}

// main():
const yesFlag = rawArgs.some(a => a === "--yes" || a === "-y");
AUTO_YES = yesFlag;
```

Her `ask()` çağrısı kendi default cevabını alır (commit onayı `"e"`, msg edit `""`, plan onayı `"e"`).

**Kullanım senaryoları:**
- İnsan: `npm run review`
- CI / Cursor agent / cron: `npm run review -- --yes "deploy"`

---

## 8. Exit Code Sözleşmesi

```typescript
0  → success / kullanıcı iptal etti
1  → provider not ready (env eksik, Ollama açık değil, model yok)
2  → AI run hatası
3  → git commit komutu başarısız
4  → git push başarısız
5  → SSH veya deploy başarısız
6  → Pi config eksik
```

**Tasarım kuralı**: Her dış sistem (AI, git, ssh, config) ayrı code aralığına sahip. CI script'leri `$?` ile spesifik hatayı yakalayabilir.

---

## 9. Hata Yönetimi Stratejisi

### 9.1. Custom error tipi

```typescript
class AiError extends Error {
  constructor(
    message: string,
    public readonly provider: AiProvider,
    public readonly retryable = false,
  ) {
    super(message);
    this.name = "AiError";
  }
}
```

`retryable` flag → çağıran tarafta otomatik retry kararı verilebilir.

### 9.2. Çağrı sınırı

`execa` shell komutları için `ExecaError` yakalanır, `stdout`/`stderr` korunur:

```typescript
try { await execa("git", ["push", "origin", branch], { cwd: REPO_ROOT, stdio: "inherit" }); }
catch (err) {
  if (err instanceof ExecaError) {
    console.error(err.stderr ?? err.shortMessage);
    return 4;
  }
  throw err;
}
```

### 9.3. Plan üretme garantisi

AI parse edilemese bile asla crash etmez — **her zaman** fallback `commit` planı döner.

---

## 10. Cursor Skill Entegrasyonu

`.cursor/skills/<skill-name>/SKILL.md` agent'a şunu öğretir:

1. **Trigger ifadeleri**: hangi Türkçe/İngilizce ifadeler bu tool'u tetikler
2. **Çağrı şekli**: `cd <tool-dir> && npm run review -- --yes "<command>"`
3. **Onay protokolü**: push/deploy gibi geri-dönülemez aksiyonlar için chat'te kullanıcıya `AskQuestion` ile sor
4. **Exit code yorumu**: kod → kullanıcı dostu mesaj

Skill yapısı:
```yaml
---
name: <project>-deploy
description: >-
  Run the project's review-commit tool... Use when the user says
  "commit et", "pushla", "deploy et", ... or English equivalents.
---
# Tetikleme ifadeleri
# Çağrı şekli
# Workflow (önce onay, sonra Shell)
# When NOT to invoke
# Exit code tablosu
```

---

## 11. Bağımlılıklar ve Gerekçeleri

| Paket | Neden seçildi | Alternatif |
|---|---|---|
| `tsx` | TypeScript runner, derleme yok, hızlı | `ts-node` (daha yavaş), `bun` (Node ekosistemi dışı) |
| `execa` | Promise tabanlı, structured stderr/stdout, pipe kolay | `child_process` raw (verbose) |
| `dotenv` | `.env` standart, herkes biliyor | `vite-config` türevi (ağır) |
| `ssh2` | Saf JS, native bağımlılık yok, password+key destekler | `node-ssh` (ssh2 wrapper, fazla soyutlanmış) |
| `@cursor/sdk` | Cursor cloud agents, sadece cursor provider için | direkt HTTP API |

**Toplam bundle:** ~5 MB. node_modules ~120 MB (tipik).

`package.json` esans:

```json
{
  "type": "module",
  "scripts": { "review": "tsx review.ts" },
  "dependencies": {
    "@cursor/sdk": "^x.y.z",
    "dotenv": "^16",
    "execa": "^9",
    "ssh2": "^1"
  },
  "devDependencies": {
    "@types/node": "^20",
    "@types/ssh2": "^1",
    "tsx": "^4"
  }
}
```

`tsconfig.json` esans:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "Bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["*.ts"]
}
```

---

## 12. Klasör Yapısı (Template)

```
<repo-root>/
├── .env.example                 # commit edilebilir
├── .gitignore                   # .env, node_modules, vs.
├── tools/
│   └── <agent-name>/
│       ├── .env                 # parolalar, NEVER commit
│       ├── .env.example
│       ├── .gitignore
│       ├── package.json
│       ├── tsconfig.json
│       ├── README.md
│       ├── ARCHITECTURE.md      ← bu dosya
│       ├── review.ts            # orchestrator
│       ├── ai.ts                # provider abstraction
│       └── deploy.ts            # SSH/uzak çalıştırma
└── .cursor/
    └── skills/
        └── <project>-deploy/
            └── SKILL.md         # Cursor agent'a komut → tool eşlemesi
```

---

## 13. Başka Bir Uygulamaya Taşıma Rehberi

Diyelim yeni projende **API'ye webhook tetikleme + lambda redeploy** yapan bir agent istiyorsun.

### Adım 1: Klasörü kopyala

```bash
cp -R tools/review-commit/ ../yeni-proje/tools/api-redeploy/
cd ../yeni-proje/tools/api-redeploy/
rm .env  # eski sırlar gitsin
```

### Adım 2: Action tipini değiştir

`review.ts` → `Action` union'ını domain'ine göre güncelle:

```typescript
type Action =
  | { type: "commit" }
  | { type: "push"; branch?: string }
  | { type: "trigger-webhook"; url: string }   // yeni
  | { type: "lambda-redeploy"; fn: string };   // yeni
```

### Adım 3: Action runner ekle

`review.ts`'e fonksiyon ekle, `executePlan`'da switch'e dal ekle:

```typescript
async function runWebhookFlow(url: string): Promise<number> {
  const res = await fetch(url, { method: "POST" });
  return res.ok ? 0 : 7;  // yeni exit kod aralığı
}
```

### Adım 4: Keyword fallback ve AI prompt güncelle

`defaultPlanForKeywords`'e domain'in keyword'lerini ekle (`"webhook tetikle"`, `"lambda yeniden deploy"`).

`interpretCommand`'in AI prompt şablonundaki **MEVCUT ACTIONS** listesi de güncellenmeli.

### Adım 5: `.env.example` ve config

Domain'e özel env değişkenlerini ekle (`WEBHOOK_URL`, `AWS_REGION`, vs).

### Adım 6: Cursor Skill

`.cursor/skills/<yeni-proje>-deploy/SKILL.md` yaz, trigger ifadelerini domain'e göre güncelle.

### Adım 7: Sıfırdan ihtiyacın olmayan parçayı sil

- SSH gerekmiyor mu? `deploy.ts`'i sil, `ssh2` dependency'sini kaldır.
- Cursor SDK gerekmiyor mu? `ai.ts`'den `cursorPrompt`'ı kaldır.
- AI hiç gerekmiyor mu? `ai.ts`'i tamamen at, `interpretCommand` sadece keyword olsun.

---

## 14. Genişletme Örnekleri

### 14.1. Yeni AI provider (Gemini, Groq, Anthropic, OpenAI)

`ai.ts`'e ek fonksiyon:

```typescript
async function geminiPrompt(prompt: string): Promise<AiResult> {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new AiError("GEMINI_API_KEY yok", "gemini");
  const model = process.env.GEMINI_MODEL ?? "gemini-2.0-flash";
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ contents: [{ parts: [{ text: prompt }] }] }),
    },
  );
  if (!res.ok) throw new AiError(`Gemini HTTP ${res.status}`, "gemini");
  const data = await res.json();
  return {
    text: data.candidates[0].content.parts[0].text,
    provider: "gemini",
    model,
  };
}

// aiPrompt()'a:
if (provider === "gemini") return geminiPrompt(prompt);
```

### 14.2. Yeni action: `lint`, `test`, `migrate`, `notify-slack`...

Pattern aynı:
1. `Action` union'a tipi ekle
2. `runXFlow()` yaz
3. `executePlan` switch'ine ekle
4. `defaultPlanForKeywords`'e tetikleyici cümle ekle
5. AI prompt şablonunda action'ları listele
6. Skill SKILL.md'sine de yaz

---

## 15. Anti-Patterns (Kaçın)

| ❌ | ✅ |
|---|---|
| Tüm logic'i tek dosyada `main()` içinde tut | Action/provider'ları ayrı katmanlara böl |
| AI'ı senkronize tek path yap | Keyword fallback ile %80 vakayı AI'sız çöz |
| Onay = `[Y/n]` (İngilizce) ve interactive only | Hem interactive hem `--yes` modu |
| Parolayı kodda hardcode | `.env` + `.gitignore` |
| Tüm hatalar exit 1 | Her sistem için ayrı kod aralığı |
| `console.error("hata")` ham | `colors.red` + Türkçe + retryable bilgisi |
| Cursor agent doğrudan stdin'e cevap göndersin sansın | Tool'a `--yes` flag ekle, agent onu kullansın |
| Prompt ham AI'a → ham response ekrana | Prompt şablonu + parse fonksiyonu + fallback |

---

## 16. Test ve Doğrulama

### 16.1. Smoke test (provider doğru çalışıyor mu?)

```typescript
// _smoke.ts
import "dotenv/config";
import { aiPrompt, describeProvider, ensureProviderReady } from "./ai.js";

async function main() {
  console.log("Provider:", describeProvider());
  console.log("Ready:", ensureProviderReady());
  const result = await aiPrompt("Test prompt: '5+3 kaç?' Sadece sayı döndür.");
  console.log("Cevap:", result.text);
}
main().catch(console.error);
```

```bash
npx tsx _smoke.ts
```

### 16.2. Tool entegrasyon testi

```bash
# Keyword fallback (AI'a gitmemeli, hızlı olmalı)
time npm run review -- --yes "deploy"   # → ~10s (sadece SSH)

# AI yorumlama (commit msg üretimi)
echo "test" >> README.md
npm run review -- --yes "commit"        # → ~5s commit + AI msg

# Tüm zincir
npm run review -- --yes "en son değişiklikleri gönder"
```

### 16.3. Hata path'leri

- `.env`'den `OLLAMA_URL` kaldır → exit 1, anlamlı mesaj
- `OLLAMA_MODEL=foobar` → exit 1, "model yok, ollama pull..."
- `PI_HOST=192.168.0.99` (yanlış IP) → exit 5, ssh timeout

---

## 17. Sözlük

| Terim | Anlamı |
|---|---|
| **Plan** | Yapılacak action'ların sıralı listesi + Türkçe rationale |
| **Action** | Tek bir atomik iş (commit, push, deploy, ...) |
| **Provider** | AI'nın geldiği kaynak (Ollama, Cursor, Gemini, ...) |
| **Flow** | Bir action'ı yerine getiren async fonksiyon (`runXFlow()`) |
| **Auto-yes** | İnteraktif promptları otomatik onaylayan mod |
| **Skill** | Cursor agent'a tool'un nasıl çağrılacağını öğreten markdown |

---

## 18. Lisans / Tekrar Kullanım

Bu mimari herhangi bir komut zinciri otomasyonuna uyarlanabilir:

- **CI bot** → commit, lint, test, deploy zinciri
- **DevOps yardımcısı** → kubectl apply, helm upgrade, rollback
- **DBA agent** → migration, seed, backup, restore
- **Frontend ship-it** → build, optimize, upload S3, invalidate CDN

Çekirdek 3 dosya (`review.ts` ≈ 460 satır, `ai.ts` ≈ 130 satır, `deploy.ts` ≈ 80 satır) ve ~700 satır TypeScript ile başla; domain action'larını ekle.

---

**Sonuç**: Bu mimari, `Plan + Action + Provider abstraction + Auto-yes flag + Cursor skill` olarak 5 küçük desenin birleşimidir. Her biri bağımsız taşınabilir ve farklı domain'lere uydurulabilir.
