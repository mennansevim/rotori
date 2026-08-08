const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, apikey, x-client-info",
  "Access-Control-Max-Age": "86400",
};

const OPENAI_API_KEY = Deno.env.get("openai_api_key")!;
const LLM_MODEL = "gpt-4o-mini";
const LLM_ENDPOINT = "https://api.openai.com/v1/chat/completions";

// Her pazar yeri için search URL + parser.
const MARKETPLACES: MarketplaceDef[] = [
  {
    id: "hepsiburada",
    label: "Hepsiburada",
    searchUrl: (q) => `https://www.hepsiburada.com/ara?q=${encodeURIComponent(q)}`,
    parser: parseHepsiburada,
  },
  {
    id: "trendyol",
    label: "Trendyol",
    searchUrl: (q) => `https://www.trendyol.com/sr?q=${encodeURIComponent(q)}`,
    parser: parseTrendyol,
  },
  {
    id: "amazon_tr",
    label: "Amazon TR",
    searchUrl: (q) => `https://www.amazon.com.tr/s?k=${encodeURIComponent(q)}`,
    parser: parseAmazonTR,
  },
];

interface MarketplaceDef {
  id: string;
  label: string;
  searchUrl: (query: string) => string;
  parser: (html: string, query: string) => ParsedPrice | null;
}

interface ParsedPrice {
  priceTry: number;
  title: string;
  url: string;
  inStock: boolean;
}

interface PriceRequest {
  productModel: string;
  referenceJpyPrice?: number;
}

interface PriceResult {
  model: string;
  referenceJpy: number | null;
  platforms: PlatformPrice[];
  currency: string;
  updatedAt: string;
  source: string;
}

interface PlatformPrice {
  platform: string;
  priceTry: number | null;
  currency: string;
  url: string;
  inStock: boolean;
  title: string | null;
  confidence: "high" | "medium" | "low";
  source: "html" | "llm" | "fallback";
}

// ─── HTML Parsers ───────────────────────────────────────

function parseHepsiburada(html: string, query: string): ParsedPrice | null {
  // Hepsiburada search result cards
  const cardRegex = /<li[^>]*class="[^"]*productListContent[^"]*"[^>]*>([\s\S]*?)<\/li>/gi;
  // Fiyat: data-bind="markupText:'currentPrice'" içinde
  const priceRegex = /([\d.,]+)\s*TL\s*<\/span>/gi;
  const titleRegex = /<h3[^>]*>([\s\S]*?)<\/h3>/i;
  const hrefRegex = /href="(\/[\w\d\-\/]+-p-[A-Z0-9]+)"/i;

  let match;
  while ((match = cardRegex.exec(html)) !== null) {
    const card = match[1];
    if (!card.toLowerCase().includes(query.toLowerCase().slice(0, 6))) continue;

    const titleMatch = titleRegex.exec(card);
    const title = titleMatch?.[1]?.replace(/<[^>]+>/g, "").trim() ?? null;
    if (!title) continue;

    const priceMatch = priceRegex.exec(card);
    const priceRaw = priceMatch?.[1]?.replace(/[,\.]/g, "");
    const price = priceRaw ? parseFloat(priceRaw) : null;

    const hrefMatch = hrefRegex.exec(card);
    const url = hrefMatch ? `https://www.hepsiburada.com${hrefMatch[1]}` : null;

    if (price && price > 1) {
      return { priceTry: Math.round(price), title, url: url ?? "", inStock: true };
    }
  }
  return null;
}

function parseTrendyol(html: string, query: string): ParsedPrice | null {
  // Trendyol JSON-LD veya SSR price span
  const cardRegex = /<div[^>]*class="[^"]*p-card-chart[^"]*"[^>]*>([\s\S]*?)<\/div>\s*<\/div>\s*<\/div>/gi;
  const priceRegex = /([\d.,]+)\s*TL/gi;
  const titleRegex = /<span[^>]*class="[^"]*prdct-desc-cntnr-name[^"]*"[^>]*>([\s\S]*?)<\/span>/i;
  const hrefRegex = /href="(\/[^"]+\?[^"]*)"/i;

  // Try JSON-LD first (cleanest)
  const jsonLdRegex = /<script type="application\/ld\+json">([\s\S]*?)<\/script>/gi;
  let jsonMatch: RegExpExecArray | null;
  while ((jsonMatch = jsonLdRegex.exec(html)) !== null) {
    try {
      const ld = JSON.parse(jsonMatch[1]);
      if (ld.name && ld.offers) {
        const offers = Array.isArray(ld.offers) ? ld.offers[0] : ld.offers;
        if (offers?.price && offers?.price > 1) {
          const name = (typeof ld.name === "string" ? ld.name : "").toLowerCase();
          const qLower = query.toLowerCase();
          if (name.includes(qLower.slice(0, 6))) {
            return {
              priceTry: Math.round(offers.price),
              title: ld.name,
              url: ld.url ?? `https://www.trendyol.com/sr?q=${encodeURIComponent(query)}`,
              inStock: offers.availability !== "https://schema.org/OutOfStock",
            };
          }
        }
      }
    } catch { /* JSON-LD parse error, continue */ }
  }

  // Fallback: regex card parser
  let match;
  while ((match = cardRegex.exec(html)) !== null) {
    const card = match[1];
    if (!card.toLowerCase().includes(query.toLowerCase().slice(0, 6))) continue;

    const titleMatch = titleRegex.exec(card);
    const title = titleMatch?.[1]?.replace(/<[^>]+>/g, "").trim() ?? null;
    if (!title) continue;

    const priceMatches = [...card.matchAll(priceRegex)];
    if (priceMatches.length === 0) continue;
    const priceMatch = priceMatches[priceMatches.length - 1]; // son fiyat (indirimli olabilir)
    const priceRaw = priceMatch[1]?.replace(/[,\.]/g, "");
    const price = priceRaw ? parseFloat(priceRaw) : null;

    const hrefMatch = hrefRegex.exec(card);
    const url = hrefMatch ? `https://www.trendyol.com${hrefMatch[1]}` : null;

    if (price && price > 1) {
      return { priceTry: Math.round(price), title, url: url ?? "", inStock: true };
    }
  }
  return null;
}

function parseAmazonTR(html: string, query: string): ParsedPrice | null {
  // Amazon search results
  const cardRegex = /<div[^>]*data-component-type="s-search-result"[^>]*>([\s\S]*?)<\/div>\s*<\/div>\s*<\/div>/gi;
  const priceWholeRegex = /<span[^>]*class="[^"]*a-price-whole[^"]*"[^>]*>([\d,.]+)<\/span>/gi;
  const priceFracRegex = /<span[^>]*class="[^"]*a-price-fraction[^"]*"[^>]*>(\d+)<\/span>/gi;
  const titleRegex = /<span[^>]*class="[^"]*a-text-normal[^"]*"[^>]*>([\s\S]*?)<\/span>/i;
  const hrefRegex = /href="(\/[^"]+\/dp\/[^"]+)"/i;

  let match;
  while ((match = cardRegex.exec(html)) !== null) {
    const card = match[1];
    if (!card.toLowerCase().includes(query.toLowerCase().slice(0, 6))) continue;

    const titleMatch = titleRegex.exec(card);
    const title = titleMatch?.[1]?.replace(/<[^>]+>/g, "").trim() ?? null;
    if (!title) continue;

    const wholeMatch = priceWholeRegex.exec(card);
    const fracMatch = priceFracRegex.exec(card);
    const whole = wholeMatch?.[1]?.replace(/[,\.]/g, "");
    const frac = fracMatch?.[1] ?? "00";
    const price = whole ? parseFloat(`${whole}.${frac}`) : null;

    const hrefMatch = hrefRegex.exec(card);
    const url = hrefMatch ? `https://www.amazon.com.tr${hrefMatch[1]}` : null;

    if (price && price > 1) {
      return { priceTry: Math.round(price), title, url: url ?? "", inStock: true };
    }
  }
  return null;
}

// ─── HTML fetch ─────────────────────────────────────────

async function fetchMarketplacePage(
  mp: MarketplaceDef,
  query: string
): Promise<string | null> {
  const url = mp.searchUrl(query);
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 6000);

    const resp = await fetch(url, {
      signal: controller.signal,
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko)",
        "Accept": "text/html,application/xhtml+xml",
        "Accept-Language": "tr-TR,tr;q=0.9,en;q=0.8",
      },
    });
    clearTimeout(timeout);

    if (!resp.ok) return null;
    const html = await resp.text();
    // Sadece ilk 80KB yeterli (ürünler üstte)
    return html.slice(0, 80_000);
  } catch {
    return null;
  }
}

// ─── LLM parser (regex bulamazsa) ────────────────────────

async function llmParsePrice(
  htmlSnippet: string,
  platform: string,
  query: string
): Promise<ParsedPrice | null> {
  try {
    const response = await fetch(LLM_ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: LLM_MODEL,
        messages: [
          {
            role: "system",
            content:
              `You extract the first matching product price from HTML search results.\n` +
              `Return JSON: { "priceTry": number, "title": "string", "url": "string", "inStock": boolean }.\n` +
              `priceTry is the Turkish Lira amount as integer. Return null fields if not found.`,
          },
          {
            role: "user",
            content:
              `Platform: ${platform}\nSearch query: ${query}\n\nHTML (first results):\n${htmlSnippet.slice(0, 4000)}`,
          },
        ],
        temperature: 0,
        max_tokens: 300,
        response_format: { type: "json_object" },
      }),
    });

    if (!response.ok) return null;
    const data = await response.json();
    const content = data.choices?.[0]?.message?.content;
    if (!content) return null;

    const parsed = JSON.parse(content);
    if (typeof parsed.priceTry !== "number" || parsed.priceTry < 1) return null;

    return {
      priceTry: Math.round(parsed.priceTry),
      title: parsed.title ?? query,
      url: parsed.url ?? "",
      inStock: parsed.inStock !== false,
    };
  } catch {
    return null;
  }
}

// ─── Main handler ────────────────────────────────────────

async function fetchPlatformPrice(
  mp: MarketplaceDef,
  query: string
): Promise<PlatformPrice> {
  const baseUrl = mp.searchUrl(query);

  // 1. Try to get HTML
  const html = await fetchMarketplacePage(mp, query);
  if (!html) {
    return {
      platform: mp.label,
      priceTry: null,
      currency: "TRY",
      url: baseUrl,
      inStock: false,
      title: null,
      confidence: "low",
      source: "fallback",
    };
  }

  // 2. Try regex parser (fast, free)
  const regexResult = mp.parser(html, query);
  if (regexResult) {
    return {
      platform: mp.label,
      priceTry: regexResult.priceTry,
      currency: "TRY",
      url: regexResult.url || baseUrl,
      inStock: regexResult.inStock,
      title: regexResult.title,
      confidence: "high",
      source: "html",
    };
  }

  // 3. Try LLM parser (slower, costs)
  const llmResult = await llmParsePrice(html, mp.label, query);
  if (llmResult) {
    return {
      platform: mp.label,
      priceTry: llmResult.priceTry,
      currency: "TRY",
      url: llmResult.url || baseUrl,
      inStock: llmResult.inStock,
      title: llmResult.title,
      confidence: "medium",
      source: "llm",
    };
  }

  // 4. Nothing found
  return {
    platform: mp.label,
    priceTry: null,
    currency: "TRY",
    url: baseUrl,
    inStock: false,
    title: null,
    confidence: "low",
    source: "fallback",
  };
}

// Mem cache (Edge Function stateless olduğundan sadece aynı request lifecycle)
const memCache = new Map<string, PriceResult>();
const CACHE_TTL_MS = 10 * 60 * 1000;

function normalizeModelKey(model: string): string {
  return model.trim().toUpperCase().replace(/\s+/g, "");
}

Deno.serve(async (req: Request) => {
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
    const body: PriceRequest = await req.json();
    const model = body.productModel?.trim();
    if (!model || model.length < 3) {
      return new Response(JSON.stringify({ error: "productModel required (min 3 chars)" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const key = normalizeModelKey(model);
    const cached = memCache.get(key);
    if (cached) {
      const age = Date.now() - new Date(cached.updatedAt).getTime();
      if (age < CACHE_TTL_MS) {
        return new Response(JSON.stringify({ ...cached, cached: true }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    // Parallel fetch all 3 marketplaces
    const platformResults = await Promise.all(
      MARKETPLACES.map((mp) => fetchPlatformPrice(mp, model))
    );

    const result: PriceResult = {
      model: model.toUpperCase(),
      referenceJpy: body.referenceJpyPrice ?? null,
      platforms: platformResults,
      currency: "TRY",
      updatedAt: new Date().toISOString(),
      source: "marketplace_scrape",
    };

    memCache.set(key, result);

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("fetch-tr-prices error:", err);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        detail: err instanceof Error ? err.message : String(err),
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
