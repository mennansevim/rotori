import { fetchFlight } from '../tools/flightProvider.mjs';

/** Vercel Serverless Function: GET /api/flight?number=TK2638&date=2026-05-15 */
export default async function handler(req, res) {
  const { number, date, callsign } = req.query ?? {};
  const { status, body } = await fetchFlight(number, date, undefined, callsign);
  res.status(status).json(body);
}
