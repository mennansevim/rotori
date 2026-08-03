/**
 * Aktif gün için kısa Türkçe sabah özeti üretir.
 * Hızlı (max 250 token) — UI banner'ında gösterilir.
 *
 * Dönüş: { status, body: { source, summary } | { error } }
 */

function buildPrompt({ day, weather, prefs }) {
  const childCount = prefs?.childProfiles?.length ?? prefs?.childrenCount ?? 0;
  const items = (day?.items ?? [])
    .slice(0, 8)
    .map((it) => `${it.time ?? ''} ${it.title}`)
    .join(' · ');

  return `Bugün ${day?.dayNumber ?? '—'}. gün — ${day?.theme ?? ''}.
Planlanan aktiviteler: ${items || '—'}
Tahmini yürüyüş: ${day?.stepsEstimate ?? '—'} adım
${weather ? `Hava: ${weather}` : ''}
${childCount > 0 ? `Çocuk sayısı: ${childCount}` : ''}

Türkçe, samimi ve KISA bir sabah özeti yaz (3-4 cümle). "Günaydın." ile başla. Saatler ve önemli aktiviteleri özetle. Yağmur varsa kısa uyarı ekle. Sonunda kullanıcıya "Bugünkü planda değişiklik ister misin?" diye sor.

YALNIZCA bu JSON'u döndür:
{ "summary": "Günaydın. ..." }`;
}

function extractJson(text) {
  const raw = String(text ?? '').trim();
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/);
  const candidate = fenced ? fenced[1].trim() : raw;
  try {
    return JSON.parse(candidate);
  } catch {
    const start = candidate.indexOf('{');
    const end = candidate.lastIndexOf('}');
    if (start >= 0 && end > start) return JSON.parse(candidate.slice(start, end + 1));
    throw new Error('invalid-json');
  }
}

async function fromGroq(prompt, key) {
  let resp;
  try {
    resp = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'llama-3.3-70b-versatile',
        messages: [
          {
            role: 'system',
            content:
              'You write short, warm Turkish morning summaries for Japan travelers. Output only valid JSON with a summary field. 3-4 sentences total.',
          },
          { role: 'user', content: prompt },
        ],
        temperature: 0.6,
        max_tokens: 400,
        response_format: { type: 'json_object' },
      }),
    });
  } catch {
    return null;
  }
  if (!resp.ok) return null;
  let data;
  try {
    data = await resp.json();
  } catch {
    return null;
  }
  const content = data?.choices?.[0]?.message?.content;
  if (!content) return null;
  try {
    const parsed = extractJson(content);
    if (typeof parsed?.summary !== 'string') return null;
    return parsed.summary;
  } catch {
    return null;
  }
}

function fallbackSummary({ day, weather }) {
  const items = (day?.items ?? [])
    .slice(0, 3)
    .map((it) => `${it.time ?? ''} ${it.title}`.trim())
    .filter(Boolean)
    .join(', ');
  const steps = day?.stepsEstimate
    ? `Tahmini yürüyüş ${day.stepsEstimate.toLocaleString('tr-TR')} adım. `
    : '';
  const weatherNote = weather ? `Hava: ${weather}. ` : '';
  return `Günaydın. Bugünkü planın: ${items || day?.theme || 'plan yok'}. ${steps}${weatherNote}Bugünkü planda değişiklik ister misin?`;
}

/**
 * @param {object} input
 * @param {object} input.day
 * @param {string|undefined} input.weather
 * @param {object|undefined} input.prefs
 * @param {string|undefined} groqKey
 */
export async function fetchMorningSummary(input, groqKey) {
  if (!input?.day) {
    return { status: 400, body: { error: 'missing-day' } };
  }
  if (!groqKey) {
    return {
      status: 200,
      body: { source: 'rules', summary: fallbackSummary(input) },
    };
  }
  const summary = await fromGroq(buildPrompt(input), groqKey);
  if (!summary) {
    return {
      status: 200,
      body: { source: 'rules', summary: fallbackSummary(input) },
    };
  }
  return { status: 200, body: { source: 'ai', summary } };
}
