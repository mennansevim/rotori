/**
 * AI plan revizyonu — kullanıcı doğal dilde isteğini yazar,
 * mevcut günleri Groq'a verir, MİNİMUM gerekli değişiklikle güncellenmiş günleri döner.
 *
 * Dönüş: { status, body: { source, scope, days, summary } | { error } }
 */

function buildPrompt({ trip, instruction, scope, targetDayNumber, weather }) {
  const prefs = trip.preferences ?? {};
  const interests = prefs.interests ?? [];
  const sensitivities = prefs.foodSensitivities ?? [];
  const childCount =
    prefs.childProfiles?.length ?? prefs.childrenCount ?? 0;
  const childAges = (prefs.childProfiles ?? []).map((c) => c.age);

  const daysForContext = trip.days ?? [];
  let scopedDays;
  if (scope === 'day' && targetDayNumber != null) {
    scopedDays = daysForContext.filter((d) => d.dayNumber === targetDayNumber);
  } else if (scope === 'today' && targetDayNumber != null) {
    scopedDays = daysForContext.filter((d) => d.dayNumber === targetDayNumber);
  } else {
    scopedDays = daysForContext;
  }

  return `Sen Japonya gezi planlayıcısısın. Türkçe yanıt ver.

GÖREV: Kullanıcı mevcut plana doğal dilde bir DEĞİŞİKLİK istedi. Görevin minimum gerekli değişikliği yapmak.

KULLANICI İSTEĞİ:
"""
${instruction}
"""

KAPSAM: ${scope === 'all' ? 'Tüm gezi' : scope === 'today' ? `Sadece bugün (gün ${targetDayNumber})` : `Sadece gün ${targetDayNumber}`}
${weather ? `HAVA DURUMU BAĞLAMI: ${weather}` : ''}

KULLANICI PROFİLİ:
- Tempo: ${prefs.pace ?? 'moderate'}
- Çocuk: ${childCount}${childAges.length ? ` (yaşlar: ${childAges.join(', ')})` : ''}
- İlgi alanları: ${interests.join(', ') || '—'}
- Yemek hassasiyetleri: ${sensitivities.join(', ') || '—'}
- Yürüyüş üst sınırı: ${prefs.maxStepsPerDay ?? 11000} adım/gün
- Ulaşım: ${prefs.transportPreference ?? 'mixed'}

MEVCUT GÜNLER (JSON):
${JSON.stringify(scopedDays, null, 0)}

KURALLAR:
1. Tüm gezi planını yeniden YAZMA. Sadece istenen değişikliği yap, mümkün olduğunca diğer aktiviteleri olduğu gibi koru.
2. Saat çakışması olmasın. Aktivite süresi kadar boşluk bırak.
3. Yemek hassasiyetlerine UY: domuz vb. istenmiyorsa o tür yemek önerme.
4. Çocuk varsa molalar artsın.
5. Hava yağmurluysa kapalı alanları (AVM, müze, teamLab, akvaryum, Donki) öne çıkar.
6. Her item KIND alanı yalnızca: "activity", "transport", "meal", "hotel".
7. mapUrl üret: "https://www.google.com/maps/search/?api=1&query=<URL_ENCODED>".
8. summary alanı: 1-2 cümlelik Türkçe değişiklik açıklaması ("Salı günü X'i Y'ye taşıdım...").

YALNIZCA bu JSON şemasında yanıt ver:
{
  "summary": "1-2 cümlelik Türkçe değişiklik özeti.",
  "days": [
    {
      "dayNumber": 1,
      "theme": "🗼 Gün teması",
      "tags": ["Tokyo", "Tapınak"],
      "stepsEstimate": 9000,
      "highlights": [{ "title": "Öne çıkan", "body": "..." }],
      "items": [
        {
          "time": "10:00",
          "title": "🗼 Skytree",
          "description": "...",
          "tips": "...",
          "kind": "activity",
          "durationMin": 90,
          "cost": 2100,
          "costCurrency": "JPY",
          "mapUrl": "https://www.google.com/maps/search/?api=1&query=Tokyo+Skytree"
        }
      ]
    }
  ]
}`;
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
              'You revise Japan travel itineraries in Turkish based on user instructions. Output only valid JSON. Make minimum necessary changes; preserve existing items unless they conflict with the user request. Keep kind values only as activity/transport/meal/hotel.',
          },
          { role: 'user', content: prompt },
        ],
        temperature: 0.3,
        max_tokens: 6000,
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
    if (!Array.isArray(parsed?.days)) return null;
    return { summary: parsed.summary ?? '', days: parsed.days };
  } catch {
    return null;
  }
}

/**
 * @param {object} input
 * @param {object} input.trip
 * @param {string} input.instruction
 * @param {'all'|'day'|'today'} input.scope
 * @param {number|undefined} input.targetDayNumber
 * @param {string|undefined} input.weather
 * @param {string|undefined} groqKey
 */
export async function fetchEdit(input, groqKey) {
  if (!groqKey) {
    return { status: 501, body: { error: 'not-configured' } };
  }
  if (!input?.trip || !input?.instruction) {
    return { status: 400, body: { error: 'missing-trip-or-instruction' } };
  }
  const result = await fromGroq(buildPrompt(input), groqKey);
  if (!result) {
    return { status: 502, body: { error: 'ai-failed' } };
  }
  return {
    status: 200,
    body: {
      source: 'ai',
      scope: input.scope,
      summary: result.summary,
      days: result.days,
    },
  };
}
