import { fetchTicketOcr } from '../tools/ticketOcrProvider.mjs';

/** Vercel Serverless: POST /api/ticket-ocr  body: { imageDataUrl } */
export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'method-not-allowed' });
    return;
  }
  const groqKey = process.env.GROQ_API_KEY;
  const { status, body } = await fetchTicketOcr(req.body, groqKey);
  res.status(status).json(body);
}
