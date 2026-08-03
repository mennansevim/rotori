/**
 * Bilet fotoğrafından uçuş bilgilerini çıkar (Groq Vision).
 * İstek: { imageDataUrl: "data:image/jpeg;base64,..." }
 * Yanıt: { airline?, flightNo?, outboundDate?, returnDate?, origin?, destination?, raw? }
 */

const SYSTEM = `You extract structured flight information from a Turkish airline boarding pass or ticket photo.
Return ONLY a JSON object with these fields (omit if unknown):
- airline: IATA airline name as written (e.g. "Turkish Airlines", "JAL")
- flightNo: flight number (e.g. "TK198")
- outboundDate: ISO date YYYY-MM-DD
- returnDate: ISO date YYYY-MM-DD (only if a round-trip ticket clearly shows it)
- origin: 3-letter IATA code if visible (e.g. "IST")
- destination: 3-letter IATA code if visible (e.g. "HND")
No other prose, no markdown, just JSON.`;

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

export async function fetchTicketOcr(input, groqKey) {
  if (!groqKey) {
    return { status: 501, body: { error: 'not-configured' } };
  }
  const dataUrl = input?.imageDataUrl;
  if (!dataUrl || typeof dataUrl !== 'string' || !dataUrl.startsWith('data:image/')) {
    return { status: 400, body: { error: 'invalid-image' } };
  }

  let resp;
  try {
    resp = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${groqKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        // Groq's vision-capable model
        model: 'llama-3.2-90b-vision-preview',
        messages: [
          { role: 'system', content: SYSTEM },
          {
            role: 'user',
            content: [
              { type: 'text', text: 'Bu bilet/biniş kartından uçuş bilgilerini JSON olarak çıkar.' },
              { type: 'image_url', image_url: { url: dataUrl } },
            ],
          },
        ],
        temperature: 0.1,
        max_tokens: 600,
        response_format: { type: 'json_object' },
      }),
    });
  } catch (e) {
    console.error('[ticketOcr] fetch threw:', e?.message);
    return { status: 502, body: { error: 'fetch-failed' } };
  }

  if (!resp.ok) {
    const errText = await resp.text().catch(() => '');
    console.error('[ticketOcr] groq non-ok:', resp.status, errText.slice(0, 300));
    return { status: 502, body: { error: 'ai-failed' } };
  }

  let data;
  try {
    data = await resp.json();
  } catch {
    return { status: 502, body: { error: 'ai-failed' } };
  }
  const content = data?.choices?.[0]?.message?.content;
  if (!content) {
    return { status: 502, body: { error: 'empty-content' } };
  }
  try {
    const parsed = extractJson(content);
    return { status: 200, body: parsed };
  } catch {
    return { status: 502, body: { error: 'ai-failed', raw: content.slice(0, 300) } };
  }
}
