/**
 * AI destekli günlük rota üretimi (Groq ücretsiz katman).
 * Anahtar yoksa 501 döner; istemci shared generateItineraryFromTrip ile devam eder.
 *
 * Dönüş: { status, body }
 */

function paceLabel(pace) {
  if (pace === 'relaxed') return 'Rahat (günde 2–3 aktivite, uzun molalar)';
  if (pace === 'intense') return 'Yoğun (5+ aktivite, sabah erken başla)';
  return 'Dengeli (3–4 aktivite, akşamları rahat)';
}

function buildPrompt(trip) {
  const prefs = trip.preferences ?? {};

  const destinations = (prefs.destinations ?? [])
    .slice()
    .sort((a, b) => a.order - b.order)
    .map((d) => ({
      id: d.id,
      city: d.city,
      country: d.countryName,
      countryCode: d.countryCode,
      arrival: d.arrivalDate,
      departure: d.departureDate,
      airline: d.airline,
      flightNo: d.flightNo,
    }));

  const days = (trip.days ?? []).map((d) => ({
    dayNumber: d.dayNumber,
    date: d.date,
    weekday: d.weekday,
  }));

  const hotels = (trip.hotels ?? []).map((h) => ({
    city: h.city,
    name: h.name,
    address: h.address,
    checkIn: h.checkIn,
    checkOut: h.checkOut,
  }));

  const tickets = (trip.tickets ?? []).map((t) => ({
    label: t.label,
    visitDate: t.visitDate,
    purchased: t.purchased,
  }));

  const foodPrefs = (prefs.destinationFood ?? []).map((f) => ({
    destinationId: f.destinationId,
    dietary: f.dietaryTags,
    likes: f.foodLikes,
    dislikes: f.foodDislikes,
    budgetPerPerson: f.mealBudgetPerPerson,
    currency: f.mealBudgetCurrency,
  }));

  const partySize = prefs.partySize ?? 1;
  const childrenCount = prefs.childrenCount ?? 0;
  const mustSee = prefs.mustSee ?? [];
  const dietary = prefs.dietary ?? prefs.dietaryTags ?? [];
  const origin = prefs.originCity ? `${prefs.originCity}${prefs.originAirport ? ` (${prefs.originAirport})` : ''}` : '—';
  const mealBudget = prefs.mealBudgetPerPerson
    ? `${prefs.mealBudgetPerPerson} ${prefs.mealBudgetCurrency ?? ''} / kişi / öğün`
    : '—';
  const interests = prefs.interests ?? [];
  const walkingLabel = prefs.walkingTarget === 'light'
    ? 'Az (~7k adım/gün)'
    : prefs.walkingTarget === 'intense'
      ? 'Yoğun (~15k+ adım/gün)'
      : 'Orta (~11k adım/gün)';
  const transportLabel = {
    transit: 'Toplu taşıma ağırlıklı',
    taxi_assisted: 'Taksi destekli',
    walking: 'Yürüyüş ağırlıklı',
    mixed: 'Karışık',
  }[prefs.transportPreference ?? 'transit'] ?? 'Toplu taşıma ağırlıklı';

  return `Sen Japonya'ya giden Türk kullanıcılar için uzmanlaşmış bir seyahat planlayıcısısın. Türkçe yanıt ver.

Önemli: Bu uygulama YALNIZCA Japonya gezileri içindir. Tüm öneriler, ulaşım, restoran ve aktiviteler Japonya içindeki şehirlerden olmalı. Başka ülke önerme.

Görev: Aşağıdaki seyahat için gün gün, SAAT SAAT detaylı plan üret. Plan referans seyahat günlüğü kalitesinde olmalı: her aktivitenin SAATİ, AÇIKLAMASI, ULAŞIM YÖNTEMİ + SÜRE + ÜCRET, ÖNERİLEN YEMEK YERLERİ ve PRATİK İPUCU var.

Seyahat bilgileri:
- Kalkış: ${origin}
- Kişi sayısı: ${partySize} (çocuk: ${childrenCount})
- Diyet/kısıtlar: ${dietary.length ? dietary.join(', ') : '—'}
- Mutlaka gör (zorunlu): ${mustSee.length ? mustSee.join(', ') : '—'}
- İlgi alanları: ${interests.length ? interests.join(', ') : '—'}
- Yürüyüş hedefi: ${walkingLabel}
- Ulaşım tercihi: ${transportLabel}
- Tempo: ${paceLabel(prefs.pace)}
- Öğün bütçesi: ${mealBudget}
- Destinasyonlar: ${JSON.stringify(destinations)}
- Günler: ${JSON.stringify(days)}
- Oteller: ${JSON.stringify(hotels)}
- Hazır biletler: ${JSON.stringify(tickets)}
- Yemek tercihleri (destinasyon başına): ${JSON.stringify(foodPrefs)}

Kurallar:
1. Her günün dayNumber değeri verilen günlerle bire bir eşleşmeli. KESİNLİKLE EKSİK GÜN BIRAKMA — toplam ${days.length} gün, hepsini doldur. Hiçbir günü 0 aktiviteyle bırakma; her günde en az 4 item (1 sabah, 1 öğle yemeği, 1-2 öğleden sonra, 1 akşam yemeği veya akşam aktivitesi) olsun.
1b. Plan optimize edilmiş olmalı: aynı bölgeden yerleri aynı güne grupla, gereksiz şehir-arası seyahati en aza indir. Uzun trip'te (>10 gün) çevre şehirlere day-trip (Nikko, Kamakura, Hakone, Yokohama, Nara, Kobe, Himeji) ekleyerek günleri çeşitlendir.
2. Varış günü: hafif tempo, check-in, çevre keşfi, akşam yemeği. Ayrılış günü: check-out + havaalanı transferi + uçuş.
3. Aktiviteleri saat sırasına dizin: 08:00–10:00 sabah, 12:00–14:00 öğle yemeği, 14:00–18:00 öğleden sonra, 18:30–21:00 akşam.
4. Her gün en az 1 yemek (kind:"meal") ve mümkünse 1 ulaşım (kind:"transport") kalemi olsun.
4b. KIND alanı YALNIZCA bu 4 değerden biri olabilir: "activity", "transport", "meal", "hotel". Başka değer ("arrival", "flight", "departure", "checkin", "food" vb.) YASAK; varış/ayrılış/havaalanı için "transport", check-in/out için "hotel" kullan.
5. Önerdiğin restoran/yemek için ülke + yöre tarzına uygun spesifik isim ve menü ipucu ver (örn. "Tonkotsu ramen — Ichiran Shibuya").
6. Ulaşım kalemlerinde: hat/sefer adı, süre, ücret aralığı yaz (örn. "Keikyu Line, ~15 dk, ~300¥").
7. mapUrl alanına Google Maps arama linki üret: "https://www.google.com/maps/search/?api=1&query=<URL_ENCODED_QUERY>".
8. Çocuk varsa: çocuk dostu mekanlar, kısa yürüyüş mesafeleri, atıştırmalık molaları.
9. mustSee'deki maddeleri en uygun günde KESİNLİKLE programa al.
9b. İlgi alanlarına göre yer seçimi yap: anime→Akihabara/Nakano Broadway, temples→Senso-ji/Meiji/Fushimi, tech→Akihabara, shopping→Shibuya/Ginza, food→Tsukiji Outer/Dotonbori, theme_parks→Disney/USJ, photography→Skytree/Shibuya Crossing/Arashiyama. mustSee yoksa bunlardan günleri doldur.
9c. Yürüyüş hedefine UY: light için stepsEstimate 5000-8000, moderate için 9000-13000, intense için 14000-22000. Sınırı aşma.
9d. Ulaşım tercihine UY: taxi_assisted ise transport kalemlerini taksi/Uber ile yaz; walking ise yakın mesafeli rota öner; transit ise tren/metro detayı; mixed ise gün içinde harmanla.
10. Otel adresleri verilmişse: ilk gün check-in ve son gün check-out kalemlerini ona göre yaz.
11. tips alanı KISA olsun (1 cümle, somut bilgi: en iyi saat, kuyruk uyarısı, fotoğraf noktası, ücret bilgisi vb.).
12. theme: emoji + günün ana karakteri ("🗼 Asakusa & Skytree akşam manzarası").
13. tags: günün etiketleri (3–5 adet, kısa: "Tapınak", "Manzara", "Yemek").
14. stepsEstimate: tempoya göre 6000–22000 arası gerçekçi tahmin.
15. highlights: 1–3 madde, gün özetini cebine sığacak şekilde.

YALNIZCA aşağıdaki JSON şemasında yanıt ver, başka açıklama EKLEME:
{
  "days": [
    {
      "dayNumber": 1,
      "theme": "🛬 Tokyo'ya varış & Shinjuku akşamı",
      "tags": ["Varış", "Shinjuku", "Akşam"],
      "stepsEstimate": 8000,
      "highlights": [
        { "title": "İlk gece", "body": "Otele yerleş, kısa yürüyüş, izakaya akşam yemeği." }
      ],
      "items": [
        {
          "time": "15:00",
          "title": "🛬 Haneda → Shinjuku transferi",
          "description": "Keikyu Line ile Shinagawa, oradan JR Yamanote ile Shinjuku.",
          "tips": "Suica/Pasmo kartı havaalanından al, ~2000¥ depozito.",
          "kind": "transport",
          "durationMin": 60,
          "cost": 700,
          "costCurrency": "JPY",
          "mapUrl": "https://www.google.com/maps/search/?api=1&query=Haneda+Airport+Keikyu+Line"
        },
        {
          "time": "19:00",
          "title": "🍜 Akşam yemeği — Ichiran Ramen Shinjuku",
          "description": "Tonkotsu ramen, kişiye özel bölme. Vending machine ile sipariş.",
          "tips": "20:00 sonrası kuyruk kısalır.",
          "kind": "meal",
          "durationMin": 45,
          "cost": 1200,
          "costCurrency": "JPY",
          "mapUrl": "https://www.google.com/maps/search/?api=1&query=Ichiran+Ramen+Shinjuku"
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
    if (start >= 0 && end > start) {
      return JSON.parse(candidate.slice(start, end + 1));
    }
    throw new Error('invalid-json');
  }
}

async function fromGroq(prompt, key, maxTokens = 6000, retriesLeft = 2) {
  let resp;
  try {
    resp = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'llama-3.3-70b-versatile',
        messages: [
          {
            role: 'system',
            content:
              'You output only valid JSON for Japan travel itineraries in Turkish. Only Japan locations. No markdown, no prose. Be specific about times, transit modes/durations/prices, restaurant names, and practical tips. Always include mapUrl for places.',
          },
          { role: 'user', content: prompt },
        ],
        temperature: 0.4,
        max_tokens: maxTokens,
        response_format: { type: 'json_object' },
      }),
    });
  } catch (e) {
    console.error('[itinerary] fetch threw:', e?.message);
    return null;
  }
  if (resp.status === 429 && retriesLeft > 0) {
    // Rate limit — mesajdan "try again in X.Xs" parse et, bekle, tekrar dene.
    const errText = await resp.text().catch(() => '');
    const match = errText.match(/try again in ([\d.]+)s/);
    const waitMs = match
      ? Math.ceil(parseFloat(match[1]) * 1000) + 1500
      : 12000;
    console.error(
      `[itinerary] 429 rate-limit, ${waitMs}ms beklenip retry (kalan ${retriesLeft})`,
    );
    await new Promise((r) => setTimeout(r, waitMs));
    return fromGroq(prompt, key, maxTokens, retriesLeft - 1);
  }
  if (!resp.ok) {
    const errText = await resp.text().catch(() => '');
    console.error('[itinerary] groq non-ok:', resp.status, errText.slice(0, 400));
    return null;
  }
  let data;
  try {
    data = await resp.json();
  } catch (e) {
    console.error('[itinerary] json parse failed:', e?.message);
    return null;
  }
  const content = data?.choices?.[0]?.message?.content;
  if (!content) {
    console.error('[itinerary] empty content:', JSON.stringify(data).slice(0, 400));
    return null;
  }
  try {
    const parsed = extractJson(content);
    if (!Array.isArray(parsed?.days)) {
      console.error('[itinerary] not array days:', JSON.stringify(parsed).slice(0, 200));
      return null;
    }
    return parsed.days;
  } catch (e) {
    console.error('[itinerary] extractJson failed:', e?.message, 'content head:', content.slice(0, 200));
    return null;
  }
}

const CHUNK_SIZE = 7;
const TOKENS_PER_DAY = 750;
const MIN_TOKENS = 2500;
const MAX_TOKENS_PER_CALL = 7000;
const CHUNK_DELAY_MS = 6500;

function estimateMaxTokens(dayCount) {
  return Math.min(
    MAX_TOKENS_PER_CALL,
    Math.max(MIN_TOKENS, dayCount * TOKENS_PER_DAY),
  );
}

/**
 * @param {object} trip — Trip JSON özeti
 * @param {string|undefined} groqKey — GROQ_API_KEY
 */
export async function fetchItinerary(trip, groqKey) {
  if (!groqKey) {
    return { status: 501, body: { error: 'not-configured', source: 'rules' } };
  }
  if (!trip?.days?.length) {
    return { status: 400, body: { error: 'no-days' } };
  }

  const days = trip.days;

  // Kısa gezi: tek çağrı
  if (days.length <= CHUNK_SIZE) {
    const prompt = buildPrompt(trip);
    const aiDays = await fromGroq(prompt, groqKey, estimateMaxTokens(days.length));
    if (!aiDays) {
      return { status: 502, body: { error: 'ai-failed', source: 'rules' } };
    }
    return { status: 200, body: { source: 'ai', days: aiDays } };
  }

  // Uzun gezi: 7'şer günlük parçalara böl, ardışık çağrılar.
  // Her parça için ayrı prompt, sonuçları birleştir.
  const chunks = [];
  for (let i = 0; i < days.length; i += CHUNK_SIZE) {
    chunks.push(days.slice(i, i + CHUNK_SIZE));
  }
  console.error(`[itinerary] uzun gezi (${days.length}g) → ${chunks.length} parça`);

  const merged = [];
  for (let i = 0; i < chunks.length; i++) {
    const chunk = chunks[i];
    const chunkTrip = { ...trip, days: chunk };
    const prompt = buildPrompt(chunkTrip);
    const aiDays = await fromGroq(prompt, groqKey, estimateMaxTokens(chunk.length));
    if (aiDays) {
      merged.push(...aiDays);
      console.error(`[itinerary] parça ${i + 1}/${chunks.length} → ${aiDays.length} gün`);
    } else {
      console.error(`[itinerary] parça ${i + 1}/${chunks.length} → BAŞARISIZ`);
    }
    if (i < chunks.length - 1) {
      await new Promise((r) => setTimeout(r, CHUNK_DELAY_MS));
    }
  }

  if (merged.length === 0) {
    return { status: 502, body: { error: 'ai-failed', source: 'rules' } };
  }

  return { status: 200, body: { source: 'ai', days: merged } };
}
