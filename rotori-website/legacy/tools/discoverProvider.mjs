/**
 * Şehir/ülke için "en çok ziyaret edilen yerler" listesi üretir (Groq AI).
 * Anahtar yoksa 501 döner.
 *
 * Dönüş: { status, body: { places: [...] } }
 */

function buildPrompt(city, country) {
  const cityLabel = city ? `${city}${country ? ` (${country})` : ''}` : country || 'belirtilmemiş';
  return `Sen Japonya uzmanı bir seyahat rehberisin. Türkçe yanıt ver.

Önemli: Bu uygulama YALNIZCA Japonya gezileri içindir. Sadece Japonya'daki şehirler için öneri yap; istenen şehir Japonya dışındaysa Japonya'ya en yakın benzer şehri seç (örn. Tokyo) ve onun için liste üret.

Görev: ${cityLabel} için "en çok ziyaret edilen, mutlaka görülmesi gereken" 12 yer öner. Tarihi/kültürel/eğlence/yemek/manzara karışımı dengeli olsun.

Her yer için:
- id: kısa kebab-case slug (örn. "senso-ji")
- name: yerel/uluslararası bilinen isim
- emoji: 1 emoji
- category: "culture" | "nature" | "food" | "fun" | "shopping" | "transport" arasından SADECE BİRİ
- description: 1-2 cümle, neden gidilmeli
- tips: 1 kısa pratik ipucu (en iyi saat, kuyruk, fiyat aralığı vb.)
- typicalSteps: tahmini adım (5000-20000)
- imageQuery: Wikipedia'da aranacak başlık (İngilizce, kesin başlık, örn. "Sensō-ji" veya "Hagia Sophia")
- mapsQuery: Google Maps arama metni (örn. "Senso-ji Temple Tokyo")
- lat: ondalıklı enlem (örn. 35.7148)
- lng: ondalıklı boylam (örn. 139.7967)
- durationMin: yerde geçirilmesi tahmin edilen süre (dakika, 30-180)

YALNIZCA bu JSON şemasında yanıt ver, başka açıklama EKLEME:
{
  "places": [
    {
      "id": "senso-ji",
      "name": "Senso-ji Tapınağı",
      "emoji": "⛩️",
      "category": "culture",
      "description": "Tokyo'nun en eski Budist tapınağı, Asakusa'nın simgesi. Kaminarimon kapısı ve Nakamise alışveriş sokağı ile ünlü.",
      "tips": "Sabah 8'den önce kalabalık azdır.",
      "typicalSteps": 8000,
      "imageQuery": "Sensō-ji",
      "mapsQuery": "Senso-ji Temple Tokyo",
      "lat": 35.7148,
      "lng": 139.7967,
      "durationMin": 90
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
              'You output only valid JSON listing top tourist attractions in Turkish. No markdown, no prose. Always include imageQuery as an English Wikipedia title.',
          },
          { role: 'user', content: prompt },
        ],
        temperature: 0.4,
        max_tokens: 4000,
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
    if (!Array.isArray(parsed?.places)) return null;
    return parsed.places;
  } catch {
    return null;
  }
}

/**
 * @param {string} city
 * @param {string} country
 * @param {string|undefined} groqKey
 */
export async function fetchDiscover(city, country, groqKey) {
  if (!groqKey) {
    return { status: 501, body: { error: 'not-configured' } };
  }
  if (!city && !country) {
    return { status: 400, body: { error: 'city-or-country-required' } };
  }
  let places = await fromGroq(buildPrompt(city, country), groqKey);
  if (!places) {
    // Tek retry — Groq geçici hata / parse hatası verdiyse bir kere daha dene.
    await new Promise((r) => setTimeout(r, 600));
    places = await fromGroq(buildPrompt(city, country), groqKey);
  }
  if (!places) {
    return { status: 502, body: { error: 'ai-failed' } };
  }
  return { status: 200, body: { places } };
}
