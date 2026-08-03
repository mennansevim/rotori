import { fetchItinerary } from '../tools/itineraryProvider.mjs';

/** Vercel Serverless: POST /api/itinerary — body: Trip JSON */
export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'method-not-allowed' });
    return;
  }
  const groqKey = process.env.GROQ_API_KEY;
  const trip = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
  const { status, body } = await fetchItinerary(trip, groqKey);
  res.status(status).json(body);
}
