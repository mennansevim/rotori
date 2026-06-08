/** Ülkeye göre genişletilebilir beslenme etiketleri */
export interface DietaryOption {
  id: string;
  label: string;
  emoji: string;
  description: string;
  countries?: string[]; // boş = evrensel
}

export const DIETARY_OPTIONS: DietaryOption[] = [
  {
    id: 'halal',
    label: 'Helal',
    emoji: '🕌',
    description: 'Helal sertifikalı veya domuzsuz seçenekler',
    countries: ['JP', 'TR', 'MY'],
  },
  {
    id: 'no_pork',
    label: 'Domuz yok',
    emoji: '🐷',
    description: 'Domuz eti ve domuz yağı içermesin',
    countries: ['JP', 'TR'],
  },
  {
    id: 'vegetarian',
    label: 'Vejetaryen',
    emoji: '🥬',
    description: 'Et ve balık yok, yumurta/süt olabilir',
  },
  {
    id: 'vegan',
    label: 'Vegan',
    emoji: '🌱',
    description: 'Hayvansal ürün yok',
  },
  {
    id: 'low_fat',
    label: 'Yağsız / hafif',
    emoji: '💧',
    description: 'Kızartma ve ağır soslardan kaçın',
  },
  {
    id: 'no_alcohol',
    label: 'Alkolsüz',
    emoji: '🚫',
    description: 'Yemeklerde alkol kullanılmasın',
  },
  {
    id: 'bakery_ok',
    label: 'Hamur işi OK',
    emoji: '🥐',
    description: 'Ekmek, noodle, unlu atıştırmalıklar uygun',
  },
  {
    id: 'meat_ok',
    label: 'Et sever',
    emoji: '🥩',
    description: 'Wagyu, yakiniku, et ağırlıklı menüler',
    countries: ['JP'],
  },
  {
    id: 'chicken_only',
    label: 'Tavuk / hindi',
    emoji: '🍗',
    description: 'Kırmızı et yerine tavuk tercih',
  },
  {
    id: 'seafood_ok',
    label: 'Deniz ürünü',
    emoji: '🐟',
    description: 'Sushi, sashimi, deniz ürünleri uygun',
    countries: ['JP'],
  },
  {
    id: 'gluten_free',
    label: 'Glutensiz',
    emoji: '🌾',
    description: 'Buğday / gluten hassasiyeti',
  },
  {
    id: 'spicy_ok',
    label: 'Acı sever',
    emoji: '🌶️',
    description: 'Acı ve baharatlı yemekler uygun',
    countries: ['KR', 'TH', 'MX'],
  },
  {
    id: 'spicy_avoid',
    label: 'Acı istemiyorum',
    emoji: '🚫🌶️',
    description: 'Acı sos ve gochujang azaltılsın',
    countries: ['KR'],
  },
];

export function dietaryForCountry(countryCode: string): DietaryOption[] {
  if (!countryCode) {
    return DIETARY_OPTIONS.filter((o) => !o.countries?.length);
  }
  return DIETARY_OPTIONS.filter(
    (o) => !o.countries?.length || o.countries.includes(countryCode),
  );
}

/** Çoklu ülke rotası: her destinasyonun kurallarını birleştirir */
export function dietaryForCountries(countryCodes: string[]): DietaryOption[] {
  const codes = countryCodes.filter(Boolean);
  if (!codes.length) return dietaryForCountry('');
  const seen = new Set<string>();
  const out: DietaryOption[] = [];
  for (const code of codes) {
    for (const opt of dietaryForCountry(code)) {
      if (!seen.has(opt.id)) {
        seen.add(opt.id);
        out.push(opt);
      }
    }
  }
  return out;
}
