/**
 * Wikipedia REST API summary endpoint'inden thumbnail URL'i çeker.
 * Anonim, anahtarsız, CORS açık.
 *
 * Önce TR Wikipedia, yoksa EN Wikipedia denenir.
 */

interface WikiSummary {
  thumbnail?: { source: string; width: number; height: number };
  originalimage?: { source: string };
  description?: string;
  extract?: string;
}

async function fetchSummary(title: string, lang: 'en' | 'tr'): Promise<WikiSummary | null> {
  const url = `https://${lang}.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(title)}`;
  try {
    const resp = await fetch(url, { headers: { accept: 'application/json' } });
    if (!resp.ok) return null;
    return (await resp.json()) as WikiSummary;
  } catch {
    return null;
  }
}

const cache = new Map<string, string | null>();

export async function fetchWikipediaThumbnail(query: string): Promise<string | null> {
  const q = query.trim();
  if (!q) return null;
  if (cache.has(q)) return cache.get(q)!;

  const en = await fetchSummary(q, 'en');
  const img = en?.thumbnail?.source ?? en?.originalimage?.source ?? null;
  if (img) {
    cache.set(q, img);
    return img;
  }

  const tr = await fetchSummary(q, 'tr');
  const trImg = tr?.thumbnail?.source ?? tr?.originalimage?.source ?? null;
  cache.set(q, trImg);
  return trImg;
}
