import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, apikey, x-client-info",
  "Access-Control-Max-Age": "86400",
};

const OPENAI_API_KEY = Deno.env.get("openai_api_key")!;
const LLM_MODEL = "gpt-4o-mini";
const LLM_ENDPOINT = "https://api.openai.com/v1/chat/completions";

interface ScanRequest {
  ocrText: string;
  region?: string;
}

interface PriceItem {
  label: string;
  amountJpy: number;
  isMainPrice: boolean;
  category: "main_product" | "warranty" | "accessory" | "tax" | "point" | "discount" | "other";
}

interface ParseResult {
  productModel: string | null;
  brand: string | null;
  mainPriceJpy: number | null;
  taxIncluded: boolean;
  prices: PriceItem[];
  rawOcrText: string;
  confidence: number; // 0-1
}

// cache: bellekte 5 dk TTL ile basit Map tabanlı (Edge Function cold-start dostu)
const memCache = new Map<string, { result: ParseResult; ts: number }>();
const MEM_CACHE_TTL_MS = 5 * 60 * 1000;

const CACHE_KV = await Deno.openKv().catch(() => null);

function normalizeKey(ocrText: string): string {
  // Ilk 120 char + son 40 char + uzunluk → deterministik ama collision riski dusuk
  const head = ocrText.trim().slice(0, 120).replace(/\s+/g, " ");
  const tail = ocrText.trim().slice(-40).replace(/\s+/g, " ");
  return `${head.length}:${head}|${tail}`;
}

async function callLLM(ocrText: string, region: string): Promise<ParseResult> {
  const systemPrompt = `You are a Japanese electronics price tag parser. You extract structured product data from OCR output of Japanese store labels (Yodobashi, BicCamera, Yamada Denki, etc.).

CRITICAL RULES:
1. Identify the MAIN product on the label — not warranties, not accessories, not point cards.
2. The main product is the expensive item (camera, lens, headphones, game console, laptop, etc.).
3. Warranty/pack items (延長保証, ケータイ補償, 安心保証パック, 保険) are SECONDARY — mark them category "warranty", NEVER as main.
4. Point values (ポイント, 還元) are category "point", never the main price.
5. Tax-included (税込) price should be the main price if both 税込 and 税抜 are present.
6. Extract ALL prices on the label with their category.
7. Model code: usually a 5-15 character alphanumeric code with hyphens (e.g., WH-1000XM5, CFI-1200A, RX100M7, α7IV, Z8, RF24-70).
8. Brand: detect from context (SONY, Canon, Nikon, Apple, Nintendo, etc.).

DO NOT hallucinate prices. If you're unsure about the main price, set confidence low.
Respond ONLY with valid JSON matching the schema.`;

  const userPrompt = `Parse this Japanese electronics store label OCR output.

OCR text from device camera:
"""
${ocrText}
"""

Store region: ${region || "Japan"}
Return a JSON object with: productModel, brand, mainPriceJpy (integer), taxIncluded (boolean), prices (array of {label, amountJpy, isMainPrice, category}), confidence (0-1).`;

  const response = await fetch(LLM_ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${OPENAI_API_KEY}`,
    },
    body: JSON.stringify({
      model: LLM_MODEL,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      temperature: 0,
      max_tokens: 600,
      response_format: { type: "json_object" },
    }),
  });

  if (!response.ok) {
    const errBody = await response.text();
    throw new Error(`OpenAI API error ${response.status}: ${errBody.slice(0, 300)}`);
  }

  const data = await response.json();
  const content = data.choices?.[0]?.message?.content;

  if (!content) {
    throw new Error("Empty LLM response");
  }

  let parsed: ParseResult;
  try {
    parsed = JSON.parse(content);
  } catch {
    // JSON parse hatası: ham metin içindeki JSON'u çıkar dene
    const jsonMatch = content.match(/\{[\s\S]*\}/);
    if (!jsonMatch) throw new Error("LLM response is not valid JSON");
    parsed = JSON.parse(jsonMatch[0]);
  }

  // Alan validasyonu - eksik alanlari default'la
  return {
    productModel: parsed.productModel ?? null,
    brand: parsed.brand ?? null,
    mainPriceJpy: typeof parsed.mainPriceJpy === "number" ? parsed.mainPriceJpy : null,
    taxIncluded: parsed.taxIncluded === true,
    prices: Array.isArray(parsed.prices) ? parsed.prices.map((p: any) => ({
      label: String(p.label ?? ""),
      amountJpy: typeof p.amountJpy === "number" ? p.amountJpy : 0,
      isMainPrice: p.isMainPrice === true,
      category: ["main_product", "warranty", "accessory", "tax", "point", "discount", "other"].includes(p.category)
        ? p.category
        : "other",
    })) : [],
    rawOcrText: ocrText,
    confidence: typeof parsed.confidence === "number"
      ? Math.max(0, Math.min(1, parsed.confidence))
      : 0.5,
  };
}

Deno.serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST required" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Supabase client init (service_role for admin ops)
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // User auth check
    const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: authErr } = await userClient.auth.getUser();
    if (authErr || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Daily limit check (service_role client)
    const adminClient = createClient(supabaseUrl, supabaseKey);
    const { data: limitData, error: limitErr } = await adminClient.rpc(
      "check_daily_scan_limit",
      { _user_id: user.id },
    );

    if (limitErr) {
      return new Response(JSON.stringify({
        error: "Limit check failed",
        detail: limitErr.message,
      }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!limitData?.allowed) {
      return new Response(JSON.stringify({
        error: "Daily scan limit reached",
        limit: {
          ...limitData,
          // @ts-ignore: rpc returns jsonb
          remaining: typeof limitData?.remaining === "number" ? limitData.remaining : 0,
        },
      }), {
        status: 429,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Parse request body
    const body: ScanRequest = await req.json();
    if (!body.ocrText || body.ocrText.trim().length < 10) {
      return new Response(JSON.stringify({ error: "OCR text too short" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Cache check
    const cacheKey = normalizeKey(body.ocrText);

    // memory cache
    const memEntry = memCache.get(cacheKey);
    if (memEntry && Date.now() - memEntry.ts < MEM_CACHE_TTL_MS) {
      return respondCached(memEntry.result, limitData);
    }

    // KV cache (Deno KV varsa)
    if (CACHE_KV) {
      const kvEntry = await CACHE_KV.get<ParseResult>(["tag_cache", cacheKey]);
      if (kvEntry?.value && kvEntry.versionstamp) {
        const ageMs = Date.now() - new Date(kvEntry.versionstamp).getTime();
        // 24 saat KV cache
        if (ageMs < 24 * 60 * 60 * 1000) {
          memCache.set(cacheKey, { result: kvEntry.value, ts: Date.now() });
          return respondCached(kvEntry.value, limitData);
        }
      }
    }

    // DB cache check
    const { data: dbCache } = await adminClient
      .from("tag_cache")
      .select("result_json")
      .eq("normalized_key", cacheKey)
      .maybeSingle();

    if (dbCache?.result_json) {
      memCache.set(cacheKey, { result: dbCache.result_json as ParseResult, ts: Date.now() });
      return respondCached(dbCache.result_json as ParseResult, limitData);
    }

    // LLM call
    const result = await callLLM(body.ocrText, body.region ?? "Japan");

    // Cache yaz
    memCache.set(cacheKey, { result, ts: Date.now() });
    if (CACHE_KV) {
      await CACHE_KV.set(["tag_cache", cacheKey], result);
    }
    await adminClient.from("tag_cache").upsert({
      normalized_key: cacheKey,
      product_model: result.productModel ?? "unknown",
      result_json: result as unknown as Record<string, unknown>,
      source: "llm",
    }, { onConflict: "normalized_key" }).select().maybeSingle();

    // Increment scan count
    const { error: incErr } = await adminClient.rpc("increment_scan_count", {
      _user_id: user.id,
    });
    if (incErr) {
      console.error("Failed to increment scan count:", incErr);
    }

    return new Response(JSON.stringify({
      ...result,
      limit: limitData,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (err) {
    console.error("parse-price-tag error:", err);
    return new Response(JSON.stringify({
      error: "Internal server error",
      detail: err instanceof Error ? err.message : String(err),
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

function respondCached(result: ParseResult, limitData: any): Response {
  return new Response(JSON.stringify({
    ...result,
    cached: true,
    limit: limitData,
  }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
