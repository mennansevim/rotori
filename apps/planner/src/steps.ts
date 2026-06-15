export const STEPS = [
  { id: 'welcome', label: 'Başla', num: 1 },
  { id: 'journey', label: 'Rota', num: 2 },
  { id: 'explore', label: 'Keşfet', num: 3 },
  { id: 'title', label: 'Başlık', num: 4 },
  { id: 'hotels', label: 'Konaklama', num: 5 },
  { id: 'food', label: 'Yemek', num: 6 },
  { id: 'plan', label: 'Plan', num: 7 },
  { id: 'calendar', label: 'Takvim', num: 8 },
  { id: 'publish', label: 'Yayın', num: 9 },
] as const;

export type StepId = (typeof STEPS)[number]['id'];
