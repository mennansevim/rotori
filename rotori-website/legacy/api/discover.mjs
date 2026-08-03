import { fetchDiscover } from '../tools/discoverProvider.mjs';

/** Vercel Serverless: GET /api/discover?city=Tokyo&country=Japonya */
export default async function handler(req, res) {
  const { city, country } = req.query ?? {};
  const groqKey = process.env.GROQ_API_KEY;
  const { status, body } = await fetchDiscover(city, country, groqKey);
  res.status(status).json(body);
}
