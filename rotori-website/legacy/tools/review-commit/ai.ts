import { Agent, CursorAgentError } from "@cursor/sdk";

export type AiProvider = "cursor" | "ollama";

export interface AiResult {
  text: string;
  provider: AiProvider;
  model: string;
}

export class AiError extends Error {
  constructor(
    message: string,
    public readonly provider: AiProvider,
    public readonly retryable = false,
  ) {
    super(message);
    this.name = "AiError";
  }
}

function getProvider(): AiProvider {
  const v = (process.env.AI_PROVIDER ?? "ollama").trim().toLowerCase();
  if (v === "cursor" || v === "ollama") return v;
  throw new AiError(`Bilinmeyen AI_PROVIDER: "${v}". Kullanılabilir: cursor, ollama`, "ollama");
}

function getOllamaConfig() {
  return {
    url: (process.env.OLLAMA_URL ?? "http://localhost:11434").replace(/\/$/, ""),
    model: process.env.OLLAMA_MODEL ?? "qwen2.5:3b",
  };
}

async function ollamaPrompt(prompt: string): Promise<AiResult> {
  const { url, model } = getOllamaConfig();
  let res: Response;
  try {
    res = await fetch(`${url}/api/generate`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        prompt,
        stream: false,
        options: { temperature: 0.2 },
      }),
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new AiError(
      `Ollama'ya bağlanılamadı (${url}): ${msg}. 'ollama serve' çalışıyor mu?`,
      "ollama",
      true,
    );
  }
  if (!res.ok) {
    const body = await res.text();
    if (res.status === 404) {
      throw new AiError(
        `Model "${model}" Ollama'da yok. 'ollama pull ${model}' ile indirin.`,
        "ollama",
      );
    }
    throw new AiError(`Ollama HTTP ${res.status}: ${body}`, "ollama");
  }
  const data = (await res.json()) as { response?: string; error?: string };
  if (data.error) throw new AiError(`Ollama error: ${data.error}`, "ollama");
  return { text: data.response ?? "", provider: "ollama", model };
}

async function cursorPrompt(prompt: string): Promise<AiResult> {
  const apiKey = process.env.CURSOR_API_KEY;
  if (!apiKey) {
    throw new AiError(
      "CURSOR_API_KEY tanımlı değil. .env'e ekleyin veya AI_PROVIDER=ollama kullanın.",
      "cursor",
    );
  }
  const model = process.env.CURSOR_REVIEW_MODEL ?? "composer-2";
  try {
    const result = await Agent.prompt(prompt, {
      apiKey,
      model: { id: model },
      local: { cwd: process.cwd() },
    });
    if (result.status !== "finished") {
      throw new AiError(
        `Cursor run hatası: status=${result.status}, run=${result.id}`,
        "cursor",
      );
    }
    return { text: result.result ?? "", provider: "cursor", model };
  } catch (err) {
    if (err instanceof CursorAgentError) {
      throw new AiError(
        `Cursor SDK hatası: ${err.message}`,
        "cursor",
        err.isRetryable,
      );
    }
    throw err;
  }
}

export async function aiPrompt(prompt: string): Promise<AiResult> {
  const provider = getProvider();
  if (provider === "ollama") return ollamaPrompt(prompt);
  return cursorPrompt(prompt);
}

export function describeProvider(): string {
  const provider = getProvider();
  if (provider === "ollama") {
    const { url, model } = getOllamaConfig();
    return `ollama (${model} @ ${url})`;
  }
  const model = process.env.CURSOR_REVIEW_MODEL ?? "composer-2";
  return `cursor (${model})`;
}

export function ensureProviderReady(): { ok: true } | { ok: false; reason: string } {
  const provider = getProvider();
  if (provider === "cursor" && !process.env.CURSOR_API_KEY) {
    return {
      ok: false,
      reason:
        "CURSOR_API_KEY tanımlı değil.\n.env'e ekleyin (https://cursor.com/dashboard/cloud-agents)\n" +
        "veya .env'de AI_PROVIDER=ollama yaparak ücretsiz lokal modele geçin.",
    };
  }
  return { ok: true };
}
