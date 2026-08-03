#!/usr/bin/env tsx
import "dotenv/config";
import { execa, ExecaError } from "execa";
import { createInterface } from "node:readline/promises";
import { stdin as input, stdout as output } from "node:process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { loadPiConfig, runOnPi } from "./deploy.js";
import { aiPrompt, AiError, describeProvider, ensureProviderReady } from "./ai.js";

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(SCRIPT_DIR, "..", "..");
const MAX_DIFF_BYTES = 100 * 1024;
const DEFAULT_PUSH_BRANCH = (process.env.PI_BRANCH || "main").trim();

const colors = {
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  dim: "\x1b[2m",
  red: "\x1b[31m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  cyan: "\x1b[36m",
};

function log(label: string, msg: string, color: string = colors.cyan) {
  console.log(`${color}${colors.bold}${label}${colors.reset} ${msg}`);
}

function header(title: string) {
  const line = "─".repeat(Math.max(8, 60 - title.length));
  console.log(`\n${colors.cyan}${colors.bold}── ${title} ${line}${colors.reset}`);
}

let AUTO_YES = false;

async function ask(question: string, autoAnswer = "e"): Promise<string> {
  if (AUTO_YES) {
    process.stdout.write(`${question}${colors.dim}[auto: ${autoAnswer}]${colors.reset}\n`);
    return autoAnswer;
  }
  const rl = createInterface({ input, output });
  try {
    const answer = await rl.question(question);
    return answer.trim();
  } finally {
    rl.close();
  }
}

async function gitOutput(args: string[]): Promise<string> {
  try {
    const { stdout } = await execa("git", args, { cwd: REPO_ROOT });
    return stdout;
  } catch (err) {
    const e = err as ExecaError;
    throw new Error(`git ${args.join(" ")} başarısız: ${e.stderr || e.message}`);
  }
}

async function getCurrentBranch(): Promise<string> {
  return (await gitOutput(["rev-parse", "--abbrev-ref", "HEAD"])).trim();
}

function truncateDiff(diff: string, label: string): string {
  if (diff.length <= MAX_DIFF_BYTES) return diff;
  const truncated = diff.slice(0, MAX_DIFF_BYTES);
  return `${truncated}\n\n... [${label}: ${diff.length - MAX_DIFF_BYTES} byte daha kesildi]`;
}

// =============================================================
// Komut yorumlama → Plan üretme
// =============================================================

type ActionType = "commit" | "push" | "deploy";

interface PlanAction {
  type: ActionType;
  branch?: string;
  note?: string;
}

interface Plan {
  actions: PlanAction[];
  rationale: string;
}

function actionLabel(a: PlanAction): string {
  switch (a.type) {
    case "commit":
      return "commit (AI yorumu + onay + git commit)";
    case "push":
      return `push (git push origin ${a.branch || DEFAULT_PUSH_BRANCH})`;
    case "deploy":
      return `deploy (SSH → Pi: cd <repo> && ${process.env.PI_DEPLOY_CMD || "<deploy cmd>"})`;
  }
}

function defaultPlanForKeywords(input: string): Plan | null {
  const s = input.toLowerCase().trim();
  if (/^commit$/.test(s)) return { actions: [{ type: "commit" }], rationale: "Sadece commit." };
  if (/^push$/.test(s)) {
    return { actions: [{ type: "push", branch: DEFAULT_PUSH_BRANCH }], rationale: "Sadece push." };
  }
  if (/^deploy$/.test(s)) return { actions: [{ type: "deploy" }], rationale: "Sadece deploy." };
  return null;
}

function parseAiPlan(raw: string | undefined): Plan | null {
  if (!raw) return null;
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const candidate = fenced ? fenced[1] : raw;
  const jsonMatch = candidate.match(/\{[\s\S]*\}/);
  if (!jsonMatch) return null;
  try {
    const parsed = JSON.parse(jsonMatch[0]) as { actions?: PlanAction[]; rationale?: string };
    if (!Array.isArray(parsed.actions)) return null;
    const valid = parsed.actions.filter(
      (a) => a && (a.type === "commit" || a.type === "push" || a.type === "deploy"),
    );
    if (valid.length === 0) return null;
    return {
      actions: valid,
      rationale: parsed.rationale || "(AI sebep belirtmedi)",
    };
  } catch {
    return null;
  }
}

async function interpretCommand(userInput: string): Promise<Plan> {
  const trimmed = userInput.trim();

  if (!trimmed) {
    return { actions: [{ type: "commit" }], rationale: "Boş giriş; varsayılan: sadece commit." };
  }

  const fast = defaultPlanForKeywords(trimmed);
  if (fast) return fast;

  log("→", "Komut AI tarafından yorumlanıyor...", colors.dim);
  const prompt = `Kullanıcı bir CLI tool'a Türkçe komut verdi. Bu komutu yapılacak action'lara çevir.

KOMUT: """${trimmed}"""

MEVCUT ACTIONS:
- {"type": "commit"} — staged + unstaged değişiklikleri AI'a yorumlatıp git commit yapar
- {"type": "push", "branch": "<branch>"} — git push origin <branch> (varsayılan: ${DEFAULT_PUSH_BRANCH})
- {"type": "deploy"} — Raspberry Pi'ye SSH bağlanıp uzak deploy komutunu çalıştırır

KURALLAR:
- Sadece üç atomik komut destekleniyor: "commit", "push", "deploy"
- "commit" → [commit]
- "push" → [push]
- "deploy" → [deploy]
- Anlam belirsizse [commit] döndür
- "deploy" → [deploy]
- "main'e gönder" gibi spesifik branch belirtirse push.branch değerini ver
- Birden fazla iş varsa ("commit ve deploy", "her şeyi yap") action'ları o sırada listele
- Anlam belirsizse [commit] döndür, rationale'a not düş

YANLIZCA aşağıdaki JSON formatında cevap ver, başka HİÇBİR şey yazma. Code fence kullanma:
{"actions":[{"type":"commit"}],"rationale":"<1-2 cümle Türkçe>"}`;

  let aiResult;
  try {
    aiResult = await aiPrompt(prompt);
  } catch (err) {
    if (err instanceof AiError) {
      log(
        "⚠",
        `Komut yorumlanamadı (${err.message}). Fallback: commit.`,
        colors.yellow,
      );
      return { actions: [{ type: "commit" }], rationale: "AI hata; fallback: commit" };
    }
    throw err;
  }

  const parsed = parseAiPlan(aiResult.text);
  if (!parsed) {
    log("⚠", "AI cevabı plan olarak parse edilemedi. Fallback: commit.", colors.yellow);
    return { actions: [{ type: "commit" }], rationale: "Parse hatası; fallback: commit" };
  }
  return parsed;
}

// =============================================================
// COMMIT akışı
// =============================================================

function buildCommitPrompt(status: string, staged: string, unstaged: string): string {
  return `Aşağıda bir git deposundaki değişiklikler var. Sen bir kod inceleme asistanısın.

GÖREV:
1) Değişiklikleri Türkçe, 2-4 cümleyle özetle (NEDEN değişti). Dosya yollarına ve fonksiyon/section isimlerine değin.
2) Conventional commit formatında, tek satır, küçük harfle başlayan, en fazla 72 karakterlik commit mesajı öner. Tip seçenekleri: feat, fix, docs, style, refactor, test, chore.

ÇIKTI FORMATI (KESİNLİKLE bu sırayla, başlıkları aynen kullan):
## Yorum
<2-4 cümle özet>

## Commit
<tek satır commit mesajı>

----- GIT STATUS -----
${status || "(boş)"}

----- STAGED DIFF -----
${truncateDiff(staged, "STAGED") || "(boş)"}

----- UNSTAGED DIFF -----
${truncateDiff(unstaged, "UNSTAGED") || "(boş)"}
`;
}

interface ParsedCommit {
  yorum: string;
  commitMsg: string;
}

function parseCommitOutput(raw: string | undefined): ParsedCommit {
  if (!raw) return { yorum: "(AI boş cevap döndü)", commitMsg: "chore: update files" };
  const yorumMatch = raw.match(/##\s*Yorum\s*\n([\s\S]*?)(?=\n##\s|$)/i);
  const commitMatch = raw.match(/##\s*Commit\s*\n([\s\S]*?)$/i);
  const yorum = (yorumMatch?.[1] ?? "").trim() || raw.trim();
  let commitMsg = (commitMatch?.[1] ?? "").trim();
  commitMsg = commitMsg.split(/\r?\n/).map((l) => l.trim()).filter(Boolean)[0] ?? "";
  if (!commitMsg) commitMsg = "chore: update files";
  return { yorum, commitMsg };
}

async function runCommitFlow(): Promise<number> {
  const status = await gitOutput(["status", "--short"]);
  const staged = await gitOutput(["diff", "--staged"]);
  const unstaged = await gitOutput(["diff"]);

  if (!status.trim()) {
    log("ℹ", "Değişiklik yok, commit adımı atlandı.", colors.dim);
    return 0;
  }

  header("Git Status");
  console.log(status);

  log("→", `AI'a değişiklikler gönderiliyor (${describeProvider()})...`);
  let aiResult;
  try {
    aiResult = await aiPrompt(buildCommitPrompt(status, staged, unstaged));
  } catch (err) {
    if (err instanceof AiError) {
      console.error(
        `${colors.red}AI çağrısı başarısız:${colors.reset} ${err.message}` +
          (err.retryable ? ` ${colors.dim}(retryable)${colors.reset}` : ""),
      );
      return 1;
    }
    throw err;
  }

  const { yorum, commitMsg } = parseCommitOutput(aiResult.text);

  header("Değişiklik Yorumu");
  console.log(yorum);
  header("Önerilen Commit Mesajı");
  console.log(`${colors.green}${commitMsg}${colors.reset}`);

  console.log(
    `\n${colors.bold}Seçenekler:${colors.reset} ` +
      `${colors.green}[E]${colors.reset}vet · ` +
      `${colors.yellow}[D]${colors.reset}üzenle · ` +
      `${colors.red}[İ]${colors.reset}ptal`,
  );
  const choice = ((await ask("Seçiminiz: ")).toLowerCase()[0] ?? "i") as string;
  if (choice === "i") {
    log("✗", "Commit iptal edildi.", colors.yellow);
    return 10;
  }
  let finalMsg = commitMsg;
  if (choice === "d") {
    const edited = await ask(`Yeni mesaj (boş bırakılırsa öneri kullanılır):\n> `);
    if (edited) finalMsg = edited;
  } else if (choice !== "e") {
    log("?", `Tanınmayan seçim "${choice}". İptal edildi.`, colors.yellow);
    return 10;
  }

  log("→", "git add -A");
  await execa("git", ["add", "-A"], { cwd: REPO_ROOT, stdio: "inherit" });

  log("→", `git commit -m "${finalMsg}"`);
  try {
    await execa("git", ["commit", "-m", finalMsg], { cwd: REPO_ROOT, stdio: "inherit" });
  } catch (err) {
    const e = err as ExecaError;
    console.error(`${colors.red}Commit başarısız:${colors.reset} ${e.shortMessage || e.message}`);
    return 3;
  }
  log("✓", "Commit oluşturuldu.", colors.green);
  return 0;
}

// =============================================================
// PUSH akışı
// =============================================================

async function runPushFlow(targetBranch?: string): Promise<number> {
  const current = await getCurrentBranch();
  const branch = (targetBranch || DEFAULT_PUSH_BRANCH).trim();

  if (current !== branch) {
    log(
      "⚠",
      `Mevcut branch "${current}" ≠ hedef "${branch}". 'git push origin ${branch}' istenmedik commit'leri içerebilir.`,
      colors.yellow,
    );
    const ok = (await ask(`"git push origin ${branch}" ile devam edilsin mi? [E/h]: `)).toLowerCase();
    if (ok && !ok.startsWith("e")) {
      log("✗", "Push iptal edildi.", colors.yellow);
      return 10;
    }
  }

  log("→", `git push origin ${branch}`);
  try {
    await execa("git", ["push", "origin", branch], { cwd: REPO_ROOT, stdio: "inherit" });
  } catch (err) {
    const e = err as ExecaError;
    console.error(`${colors.red}Push başarısız:${colors.reset} ${e.shortMessage || e.message}`);
    return 4;
  }
  log("✓", `Push tamamlandı (origin/${branch}).`, colors.green);
  return 0;
}

// =============================================================
// DEPLOY akışı
// =============================================================

async function runDeployFlow(): Promise<number> {
  const piResult = loadPiConfig();
  if (!piResult.config) {
    console.error(
      `${colors.red}Pi config eksik:${colors.reset} ${piResult.missing.join(", ")} .env dosyasına ekleyin.`,
    );
    return 6;
  }
  const cfg = piResult.config;
  log("→", `SSH ${cfg.user}@${cfg.host} → cd ${cfg.repoDir} && ${cfg.deployCmd}`);
  header(`Pi @ ${cfg.host}`);
  try {
    const result = await runOnPi(cfg);
    if (result.exitCode !== 0) {
      console.error(
        `${colors.red}Deploy komutu başarısız:${colors.reset} exit=${result.exitCode}` +
          (result.signal ? ` signal=${result.signal}` : ""),
      );
      return 5;
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`${colors.red}SSH bağlantısı başarısız:${colors.reset} ${msg}`);
    return 5;
  }
  log("✓", "Pi'ye deploy tamamlandı.", colors.green);
  return 0;
}

// =============================================================
// MAIN
// =============================================================

async function executePlan(plan: Plan): Promise<number> {
  for (const [i, action] of plan.actions.entries()) {
    header(`Adım ${i + 1}/${plan.actions.length} — ${action.type.toUpperCase()}`);
    let code = 0;
    if (action.type === "commit") code = await runCommitFlow();
    else if (action.type === "push") code = await runPushFlow(action.branch);
    else if (action.type === "deploy") code = await runDeployFlow();

    if (code === 10) {
      log("ℹ", "Kullanıcı bu adımı iptal etti, akış durduruldu.", colors.yellow);
      return 0;
    }
    if (code !== 0) {
      log("✗", `Adım ${action.type} hata verdi (kod ${code}). Akış durduruldu.`, colors.red);
      return code;
    }
  }
  return 0;
}

async function main(): Promise<number> {
  const ready = ensureProviderReady();
  if (!ready.ok) {
    console.error(`${colors.red}HATA:${colors.reset} ${ready.reason}`);
    return 1;
  }

  log("→", `Repo: ${REPO_ROOT}`);
  log("→", `AI: ${describeProvider()}`, colors.dim);

  const rawArgs = process.argv.slice(2);
  const yesFlag = rawArgs.some((a) => a === "--yes" || a === "-y");
  AUTO_YES = yesFlag;
  const cliArg = rawArgs
    .filter((a) => a !== "--yes" && a !== "-y")
    .join(" ")
    .trim();

  let userInput = cliArg;
  if (!userInput) {
    if (yesFlag) {
      userInput = "commit";
      log("→", `--yes modu, varsayılan komut: "${userInput}"`, colors.dim);
    } else {
      console.log(
        `${colors.dim}Komutlar: commit · push · deploy${colors.reset}`,
      );
      userInput = await ask("Ne yapılsın? > ", "commit");
    }
  } else {
    log("→", `CLI komutu: "${userInput}"`, colors.dim);
    if (yesFlag) log("→", "--yes: tüm onaylar otomatik evet", colors.dim);
  }

  const plan = await interpretCommand(userInput);

  header("Plan");
  plan.actions.forEach((a, i) => {
    console.log(`  ${colors.bold}${i + 1}.${colors.reset} ${actionLabel(a)}`);
  });
  console.log(`${colors.dim}Sebep: ${plan.rationale}${colors.reset}`);

  if (plan.actions.length > 1) {
    const ok = (await ask(`\nBu plan ile devam edilsin mi? [E/h]: `)).toLowerCase();
    if (ok && !ok.startsWith("e")) {
      log("✗", "Plan iptal edildi.", colors.yellow);
      return 0;
    }
  }

  return await executePlan(plan);
}

main()
  .then((code) => process.exit(code))
  .catch((err) => {
    console.error(`${colors.red}Beklenmeyen hata:${colors.reset}`, err);
    process.exit(1);
  });
