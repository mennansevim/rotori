/**
 * Uçuş numarası + tarih ile rota getiren tek kaynaklı sağlayıcı.
 * Hem Vite dev middleware, hem Vercel serverless fonksiyonu, hem de
 * apps/api (Raspberry Pi) sunucusu bu modülü kullanır.
 *
 * Sağlayıcı sırası:
 *   1) AeroDataBox (RapidAPI) — yalnızca AERODATABOX_KEY/RAPIDAPI_KEY varsa.
 *      Tarihe özel rota + saat verir.
 *   2) adsbdb.com — ANAHTARSIZ, ücretsiz callsign→rota veritabanı.
 *      Saat vermez ama kalkış/varış havaalanını verir.
 *
 * API anahtarı (varsa) sunucuda tutulur, istemciye sızmaz.
 * Dönüş: { status, body } — body FlightLookupResult ya da { error }.
 */

function pickAirport(side) {
  const ap = side?.airport;
  if (!ap) return undefined;
  const loc = ap.location ?? {};
  return {
    iata: ap.iata ?? ap.icao ?? '',
    city: ap.municipalityName ?? ap.shortName ?? ap.name ?? undefined,
    countryCode: ap.countryCode ?? undefined,
    countryName: ap.countryName ?? undefined,
    lat: typeof loc.lat === 'number' ? loc.lat : undefined,
    lng: typeof loc.lon === 'number' ? loc.lon : undefined,
  };
}

function pickTime(side) {
  const t = side?.scheduledTime ?? side?.revisedTime ?? {};
  const raw = t.local ?? t.utc;
  if (!raw) return undefined;
  // "2026-05-15 14:30+03:00" → "14:30"
  const m = String(raw).match(/(\d{2}:\d{2})/);
  return m ? m[1] : undefined;
}

/** AeroDataBox (RapidAPI) — anahtar gerekir, tarihe özel rota + saat. */
async function fromAerodatabox(num, day, key) {
  const url =
    `https://aerodatabox.p.rapidapi.com/flights/number/${encodeURIComponent(num)}/${encodeURIComponent(day)}` +
    `?withAircraftImage=false&withLocation=true`;
  let resp;
  try {
    resp = await fetch(url, {
      headers: {
        'X-RapidAPI-Key': key,
        'X-RapidAPI-Host': 'aerodatabox.p.rapidapi.com',
        accept: 'application/json',
      },
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
  const flights = Array.isArray(data) ? data : data?.flights ?? [];
  const f = flights[0];
  if (!f) return null;
  return {
    departure: pickAirport(f.departure),
    arrival: pickAirport(f.arrival),
    departureTime: pickTime(f.departure),
    arrivalTime: pickTime(f.arrival),
    departureDate: day,
  };
}

/** adsbdb.com — ANAHTARSIZ callsign→rota. Saat yok, rota var. */
async function fromAdsbdb(callsign) {
  const cs = String(callsign ?? '').replace(/\s+/g, '').toUpperCase();
  if (!cs) return null;
  let resp;
  try {
    resp = await fetch(`https://api.adsbdb.com/v0/callsign/${encodeURIComponent(cs)}`, {
      headers: { accept: 'application/json' },
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
  const fr = data?.response?.flightroute;
  if (!fr || !fr.origin) return null;
  const ep = (a) =>
    a
      ? {
          iata: a.iata_code,
          city: a.municipality,
          countryCode: a.country_iso_name,
          countryName: a.country_name,
          lat: typeof a.latitude === 'number' ? a.latitude : undefined,
          lng: typeof a.longitude === 'number' ? a.longitude : undefined,
        }
      : undefined;
  return {
    departure: ep(fr.origin),
    arrival: ep(fr.destination),
  };
}

export async function fetchFlight(number, date, keyOverride, callsign) {
  const num = String(number ?? '').replace(/\s+/g, '').toUpperCase();
  const day = String(date ?? '').slice(0, 10);
  if (!num) {
    return { status: 400, body: { error: 'bad-request' } };
  }
  const validDay = /^\d{4}-\d{2}-\d{2}$/.test(day) ? day : undefined;

  const key = keyOverride || process.env.AERODATABOX_KEY || process.env.RAPIDAPI_KEY;

  // 1) AeroDataBox (anahtar varsa) — tarihe özel saatli sonuç.
  if (key && validDay) {
    const ad = await fromAerodatabox(num, validDay, key);
    if (ad && (ad.departure || ad.arrival)) {
      return { status: 200, body: ad };
    }
  }

  // 2) adsbdb (anahtarsız) — rota veritabanı.
  const fr = await fromAdsbdb(callsign);
  if (fr && (fr.departure || fr.arrival)) {
    return { status: 200, body: { ...fr, departureDate: validDay } };
  }

  return { status: 404, body: { error: 'not-found' } };
}

/** Node http req/res yardımcıları (dev middleware ve Pi sunucusu için). */
export async function handleFlightRequest(query, res) {
  const { status, body } = await fetchFlight(
    query.get('number'),
    query.get('date'),
    undefined,
    query.get('callsign'),
  );
  res.statusCode = status;
  res.setHeader('content-type', 'application/json');
  res.end(JSON.stringify(body));
}
