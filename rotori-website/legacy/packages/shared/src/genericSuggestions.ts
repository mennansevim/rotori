/** Ülke bağımsız hızlı aktivite fikirleri */
export const QUICK_ACTIVITIES = [
  { id: 'museum', name: 'Müze', emoji: '🏛️', steps: 6000 },
  { id: 'nature', name: 'Doğa / park', emoji: '🌳', steps: 8000 },
  { id: 'beach', name: 'Plaj / sahil', emoji: '🏖️', steps: 5000 },
  { id: 'food-tour', name: 'Yemek turu', emoji: '🍽️', steps: 7000 },
  { id: 'old-town', name: 'Eski şehir / tarih', emoji: '🏰', steps: 9000 },
  { id: 'shopping', name: 'Alışveriş', emoji: '🛍️', steps: 6000 },
  { id: 'nightlife', name: 'Gece hayatı', emoji: '🌃', steps: 5000 },
  { id: 'free', name: 'Serbest zaman', emoji: '☕', steps: 3000 },
] as const;

export const DAY_THEME_PRESETS = [
  { id: 'arrival', label: 'Varış günü', theme: 'Varış & yerleşme', emoji: '🛬', steps: 5000 },
  { id: 'explore', label: 'Keşif', theme: 'Şehir keşfi', emoji: '🗺️', steps: 12000 },
  { id: 'culture', label: 'Kültür', theme: 'Kültür & müzeler', emoji: '🎭', steps: 11000 },
  { id: 'nature', label: 'Doğa', theme: 'Doğa günü', emoji: '⛰️', steps: 14000 },
  { id: 'departure', label: 'Dönüş', theme: 'Havalimanı & dönüş', emoji: '✈️', steps: 5000 },
] as const;
