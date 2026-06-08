export const STEPS = [
  { id: 'journey', label: 'Rota', num: 1 },
  { id: 'explore', label: 'Keşfet', num: 2 },
  { id: 'title', label: 'Başlık', num: 3 },
  { id: 'hotels', label: 'Konaklama', num: 4 },
  { id: 'food', label: 'Yemek', num: 5 },
  { id: 'plan', label: 'Plan', num: 6 },
  { id: 'calendar', label: 'Takvim', num: 7 },
  { id: 'publish', label: 'Yayın', num: 8 },
] as const;

export type StepId = (typeof STEPS)[number]['id'];
