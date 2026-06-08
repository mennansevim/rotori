// Kişisel sevimm-japan-2026.json gezisinden anonimleştirilmiş, yeniden
// kullanılabilir "Japonya 14 günlük" şablonu üretir. Otel adı, bilet rezervasyon
// kodu, kişiye özel notlar temizlenir; rota/saat/yer önerileri korunur.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const src = join(root, 'data/trips/sevimm-japan-2026.json');
const out = join(root, 'data/templates/japan-14d.json');

const trip = JSON.parse(readFileSync(src, 'utf8'));

// --- Üst düzey kimlik & başlık ---
trip.id = 'japan-14d';
trip.slug = 'japan-14d';
trip.title = '🇯🇵 Japonya 14 günlük rota';
trip.subtitle = 'Tokyo → Osaka, gün gün hazır plan (kişisel rezervasyon yok)';

// --- Otelleri jenerikleştir ---
trip.hotels = trip.hotels.map((h) => {
  if (h.city === 'Tokyo') {
    return {
      id: 'tokyo-ikebukuro',
      city: 'Tokyo',
      name: 'Ikebukuro bölgesi (otelinizi seçin)',
      checkIn: h.checkIn,
      checkOut: h.checkOut,
      address: 'Ikebukuro, Toshima-ku, Tokyo',
      notes:
        'Önerilen bölge: Ikebukuro veya Shinjuku — JR Yamanote hattı üzerinde, Skytree/Asakusa/Shibuya hepsine kolay erişim. Disney transferi için JR avantajlı.',
    };
  }
  if (h.city === 'Osaka') {
    return {
      id: 'osaka-namba',
      city: 'Osaka',
      name: 'Namba bölgesi (otelinizi seçin)',
      checkIn: h.checkIn,
      checkOut: h.checkOut,
      address: 'Namba / Shinsaibashi, Chuo-ku, Osaka',
      notes:
        'Önerilen bölge: Namba veya Shinsaibashi — Dotonbori yürüme mesafesinde, Nankai Rapit ile KIX, JR Yumesaki ile USJ.',
    };
  }
  return h;
});

// --- Biletleri jenerikleştir: satın alınmamış, kişisel kod yok ---
trip.tickets = trip.tickets.map((t) => {
  const next = { ...t, purchased: false };
  delete next.reservationCode;
  delete next.confirmationCode;
  return next;
});

// --- Uçuşları kaldır (kişiye/tarihe özel) ---
trip.flights = { outbound: [], return: [] };

// --- Gün içi item açıklamalarını temizle ---
function cleanText(s) {
  if (typeof s !== 'string') return s;
  return (
    s
      // Spesifik rezervasyon kodları
      .replace(/Rezervasyon: ARS_[A-Z0-9_-]+/g, 'Bilet rezervasyonu önerilir')
      .replace(/ARS_[A-Z0-9_-]+/g, '')
      // Otel adı
      .replace(/Hotel Grand City Ikebukuro/g, 'Tokyo oteli')
      .replace(/Hotel Grand City/g, 'Tokyo oteli')
      .replace(/Ikebukuro Hotel/g, 'Tokyo oteli')
      // Kişiye özel ifadeler (kız/aileye yönelik) — yumuşat
      .replace(/kızınız için/gi, 'çocuklar için')
      .replace(/4 kişi toplam/g, 'aile için')
      .replace(/tüm aile tek ücret/g, 'tek ücret')
      // China Southern özel uçuş süresi referansları
      .replace(/21 saat 45 dakikalık yolculuk sonrası /g, '')
      .replace(/21 saat 35 dakikalık yolculuk \(1 aktarma\)\.?/g, 'uzun uçuş, aktarmalı olabilir.')
      .replace(/China Southern ile /g, '')
      // Çift boşluk temizliği
      .replace(/\s{2,}/g, ' ')
      .trim()
  );
}

for (const day of trip.days) {
  if (Array.isArray(day.items)) {
    for (const it of day.items) {
      it.title = cleanText(it.title);
      if (it.description) it.description = cleanText(it.description);
      if (it.tips) it.tips = cleanText(it.tips);
    }
  }
  if (Array.isArray(day.highlights)) {
    for (const h of day.highlights) {
      h.title = cleanText(h.title);
      h.body = cleanText(h.body);
    }
  }
  if (day.theme) day.theme = cleanText(day.theme);
  // Day 7 check-out title — otel adı geçiyor
  if (Array.isArray(day.items)) {
    for (const it of day.items) {
      if (it.title?.includes('Tokyo oteli') && it.title?.includes('Check-out')) {
        it.title = 'Tokyo otelinden Check-out';
      }
    }
  }
}

mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, JSON.stringify(trip, null, 2) + '\n', 'utf8');
console.log(`✓ ${out} yazıldı (${trip.days.length} gün)`);
