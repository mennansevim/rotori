// Rota inceleme — üretilen günlük planı LLM'e okutup daha iyi bir SIRALAMA
// önerisi ister.
//
// Neden sunucuda: OpenAI anahtarı istemciye konamaz. parse-price-tag ile aynı
// deseni izler ve AYNI secret'ı (`openai_api_key`) kullanır.
//
// Sözleşme dar tutuldu — LLM:
//   • yeni yer EKLEMEZ, mevcut durakları silmez (yalnız sıra önerir),
//   • kilitli durakları ASLA oynatmaz,
//   • gerekçesini kısa notlar hâlinde döner.
// İstemci öneriyi kendi motoruna uygular; motor kilidi ve çakışmayı yine
// bağımsız doğrular. Yani bu fonksiyon güven sınırı DEĞİL, sadece öneri kaynağı.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "Authorization, Content-Type, apikey, x-client-info",
  "Access-Control-Max-Age": "86400",
};

const OPENAI_API_KEY = Deno.env.get("openai_api_key")!;
const LLM_MODEL = "gpt-4o-mini";
const LLM_ENDPOINT = "https://api.openai.com/v1/chat/completions";
const PROMPT_VERSION = "route-review-candidate-v3";

/// LLM'i beklerken istemciyi süresiz tutmamak için üst sınır.
const LLM_TIMEOUT_MS = 6_000;

interface Stop {
  id: string;
  title: string;
  time: string | null;
  durationMin: number | null;
  lat: number | null;
  lng: number | null;
  locked: boolean;
  kind: string | null;
}

interface Day {
  dayNumber: number;
  date: string;
  city: string;
  weather?: {
    code: number;
    tempMaxC: number;
    tempMinC: number;
    precipProb: number | null;
  } | null;
  stops: Stop[];
}

interface ReviewRequest {
  promptVersion?: string;
  language?: string;
  cities?: { city: string; arrival: string; departure: string }[];
  hotels?: {
    city: string;
    name: string;
    address: string;
    lat: number | null;
    lng: number | null;
    checkIn: string;
    checkOut: string;
  }[];
  days: Day[];
}

interface DaySuggestion {
  dayNumber: number;
  /// Durak id'lerinin ÖNERİLEN sırası. Girdideki id kümesiyle aynı olmalı.
  order: string[];
  /// Geriye uyumlu istemci alanı. v3 model sözleşmesi yalnız sıra üretir.
  times: Record<string, string>;
}

interface ModelReviewResult {
  verdict: "ok" | "improve";
  notes: string[];
  days: { dayNumber: number; order: string[] }[];
}

interface ReviewResult extends ModelReviewResult {
  days: DaySuggestion[];
  meta?: {
    model: string;
    promptVersion: string;
    elapsedMs: number;
    inputTokens: number | null;
    outputTokens: number | null;
  };
}

const SYSTEM_PROMPT =
  `You review a day-by-day travel itinerary in Japan and propose a better ORDER.

You may ONLY reorder existing stops. You must NOT:
- invent new places, - remove stops, - move a stop to another day,
- move any stop whose "locked" is true from its current index.

Optimise for, in priority order:
1. LOCKED stops stay exactly where and when they are. Build the day around them.
2. Less back-and-forth travel. Group stops that are geographically close
   (use lat/lng). A day should read as one sweep, not a zig-zag.
3. Weather. On rainy/snowy days, group indoor stops and keep outdoor stops in
   daylight. There is no hourly forecast, so never claim to know the wettest
   hour. Do not reorder for weather when precipProb is null or low.
4. Hotel proximity. The first stop of a day should be reachable from the hotel
   and the last stop should not be far from it.
5. Sensible flow: meals stay near their existing meal period,
   temples/gardens in daylight, night views late in the route.

If the itinerary is already good, return verdict "ok" with an empty days array.
Only return a day when you actually change something in it.

Respond ONLY with JSON: {"verdict","notes","days":[{"dayNumber","order"}]}.
"notes" holds at most 3 short reasons, written in the requested language.`;

const REVIEW_RESPONSE_FORMAT = {
  type: "json_schema",
  json_schema: {
    name: "route_review_candidate",
    strict: true,
    schema: {
      type: "object",
      properties: {
        verdict: { type: "string", enum: ["ok", "improve"] },
        notes: {
          type: "array",
          items: { type: "string" },
          maxItems: 3,
        },
        days: {
          type: "array",
          maxItems: 3,
          items: {
            type: "object",
            properties: {
              dayNumber: { type: "integer" },
              order: { type: "array", items: { type: "string" } },
            },
            required: ["dayNumber", "order"],
            additionalProperties: false,
          },
        },
      },
      required: ["verdict", "notes", "days"],
      additionalProperties: false,
    },
  },
};

function buildUserPrompt(body: ReviewRequest): string {
  const lang = body.language === "en" ? "English" : "Turkish";
  return [
    `Answer notes in ${lang}.`,
    body.cities?.length
      ? `Route: ${
        body.cities.map((c) => `${c.city} (${c.arrival}→${c.departure})`).join(
          " → ",
        )
      }`
      : "Route: unknown",
    body.hotels?.length
      ? `Hotels: ${
        body.hotels.map((h) =>
          `${h.name}, ${h.city} [${h.address}]${
            h.lat != null && h.lng != null ? ` @${h.lat},${h.lng}` : ""
          } ${h.checkIn}→${h.checkOut}`
        ).join(" | ")
      }`
      : "Hotels: none booked yet — do not assume a base location.",
    "",
    "Itinerary:",
    JSON.stringify(body.days),
  ].join("\n");
}

async function callLLM(body: ReviewRequest): Promise<ReviewResult> {
  const startedAt = Date.now();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), LLM_TIMEOUT_MS);
  let response: Response;
  try {
    response = await fetch(LLM_ENDPOINT, {
      method: "POST",
      signal: controller.signal,
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: LLM_MODEL,
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: buildUserPrompt(body) },
        ],
        temperature: 0,
        max_tokens: 900,
        response_format: REVIEW_RESPONSE_FORMAT,
      }),
    });
  } finally {
    clearTimeout(timer);
  }

  if (!response.ok) {
    const errBody = await response.text();
    throw new Error(
      `OpenAI API error ${response.status}: ${errBody.slice(0, 300)}`,
    );
  }

  const data = await response.json();
  const content = data.choices?.[0]?.message?.content;
  if (!content) throw new Error("Empty LLM response");

  let parsed: ModelReviewResult;
  try {
    parsed = JSON.parse(content);
  } catch {
    const match = content.match(/\{[\s\S]*\}/);
    if (!match) throw new Error("LLM response is not valid JSON");
    parsed = JSON.parse(match[0]);
  }

  return {
    ...sanitize(parsed, body),
    meta: {
      model: LLM_MODEL,
      promptVersion: PROMPT_VERSION,
      elapsedMs: Date.now() - startedAt,
      inputTokens: typeof data.usage?.prompt_tokens === "number"
        ? data.usage.prompt_tokens
        : null,
      outputTokens: typeof data.usage?.completion_tokens === "number"
        ? data.usage.completion_tokens
        : null,
    },
  };
}

/// LLM çıktısını girdiyle karşılaştırıp uydurma/eksik olanı atar.
///
/// İstemci de ayrıca doğruluyor; buradaki eleme ağdan boşa veri taşımamak ve
/// bariz hataları erken düşürmek için.
function sanitize(parsed: ModelReviewResult, body: ReviewRequest): ReviewResult {
  const byDay = new Map(body.days.map((d) => [d.dayNumber, d]));
  const days: DaySuggestion[] = [];

  for (const suggestion of Array.isArray(parsed.days) ? parsed.days : []) {
    const day = byDay.get(suggestion.dayNumber);
    if (!day) continue;

    const inputIds = day.stops.map((s) => s.id);
    const order = Array.isArray(suggestion.order)
      ? suggestion.order.filter((id) => inputIds.includes(id))
      : [];
    // Sıra önerisi ancak TAM permütasyonsa kabul edilir; eksik id demek
    // "durak düşürüldü" olurdu.
    const isPermutation = order.length === inputIds.length &&
      new Set(order).size === inputIds.length;

    const lockedIds = new Set(
      day.stops.filter((s) => s.locked).map((s) => s.id),
    );
    // Kilitli durak indeks değiştirdiyse tüm sıra önerisi çöpe gider.
    const keepsLocked = isPermutation &&
      inputIds.every((id, i) => !lockedIds.has(id) || order[i] === id);

    if (!keepsLocked) continue;
    days.push({
      dayNumber: day.dayNumber,
      order,
      times: {},
    });
  }

  const notes = (Array.isArray(parsed.notes) ? parsed.notes : [])
    .filter((n): n is string => typeof n === "string" && n.trim().length > 0)
    .slice(0, 3);

  return {
    verdict: days.length === 0 ? "ok" : "improve",
    notes,
    days,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "POST required" }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Missing authorization" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const userClient = createClient(
      supabaseUrl,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        auth: { autoRefreshToken: false, persistSession: false },
        global: { headers: { Authorization: authHeader } },
      },
    );
    const { data: { user }, error: authErr } = await userClient.auth.getUser();
    if (authErr || !user) return json({ error: "Unauthorized" }, 401);

    const rawBody = await req.text();
    if (rawBody.length > 100_000) {
      return json({ error: "request_too_large" }, 413);
    }
    const body = JSON.parse(rawBody) as ReviewRequest;
    if (!Array.isArray(body?.days) || body.days.length === 0) {
      return json({ error: "days required" }, 400);
    }
    const stopCount = body.days.reduce(
      (total, day) => total + (Array.isArray(day.stops) ? day.stops.length : 0),
      0,
    );
    if (body.days.length > 3 || stopCount > 36) {
      return json({ error: "review_scope_too_large" }, 400);
    }
    if (body.days.some((day) =>
      !Number.isInteger(day.dayNumber) ||
      !Array.isArray(day.stops) ||
      day.stops.length < 4 ||
      new Set(day.stops.map((stop) => stop.id)).size !== day.stops.length
    )) {
      return json({ error: "invalid_day_contract" }, 400);
    }
    if (body.promptVersion !== PROMPT_VERSION) {
      return json({ error: "unsupported_prompt_version" }, 400);
    }

    const result = await callLLM(body);
    return json(result, 200);
  } catch (error) {
    // İstemci bu hatada deterministik planı olduğu gibi tutar; kullanıcı
    // akışı kesilmez. Yine de gerçek sebebi dönüyoruz ki loglardan görülsün.
    return json({
      error: "review_failed",
      detail: error instanceof Error ? error.message : String(error),
    }, 502);
  }
});

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
