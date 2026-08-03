import { createWorker } from 'tesseract.js';

export async function extractTextFromImage(file: File): Promise<string> {
  const worker = await createWorker('eng+jpn', 1, {
    logger: () => {},
  });
  try {
    const { data } = await worker.recognize(file);
    return data.text;
  } finally {
    await worker.terminate();
  }
}

export function parseTicketFromText(text: string): {
  label?: string;
  visitDate?: string;
} {
  const result: { label?: string; visitDate?: string } = {};

  const full = text.match(/(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})/);
  if (full) {
    result.visitDate = `${full[1]}-${full[2].padStart(2, '0')}-${full[3].padStart(2, '0')}`;
  }

  const airportPair = text.match(/\b([A-Z]{3})\s*[-–→>]+\s*([A-Z]{3})\b/);
  if (airportPair) {
    result.label = `${airportPair[1]} → ${airportPair[2]}`;
  }

  const venues = [
    'Skytree',
    'Disney',
    'Disneyland',
    'teamLab',
    'Universal',
    'USJ',
    'Shinkansen',
    'Ghibli',
    'Turkish Airlines',
    'THY',
    'Pegasus',
  ];
  for (const v of venues) {
    if (text.toLowerCase().includes(v.toLowerCase())) {
      result.label = v;
      break;
    }
  }

  if (!result.label) {
    const line = text.split('\n').find((l) => l.trim().length > 4 && l.length < 60);
    if (line) result.label = line.trim().slice(0, 48);
  }

  return result;
}

export function readFileAsDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(r.result as string);
    r.onerror = reject;
    r.readAsDataURL(file);
  });
}
