import type { TripGuide } from './types.js';

function id(prefix: string, i: number) {
  return `${prefix}-s-${i}`;
}

export const JAPAN_GUIDE_DEFAULTS: TripGuide = {
  useSuggestions: true,
  practicalTips: [
    {
      id: id('tip', 0),
      icon: '🎫',
      title: 'Suica / Pasmo',
      body: 'Haneda veya JR istasyonundan alın. 2000–3000¥ yükleyin. Metro, konbini ve markette geçerli.',
      source: 'suggestion',
    },
    {
      id: id('tip', 1),
      icon: '📱',
      title: 'eSIM',
      body: 'Uçuştan önce QR ile kurun (Ubigi, Airalo). Haritaları çevrimdışı indirin.',
      source: 'suggestion',
    },
    {
      id: id('tip', 2),
      icon: '🚃',
      title: 'Haneda → şehir',
      body: 'Keikyu Line → Shinagawa → JR Yamanote önerilir (~45–50 dk).',
      source: 'suggestion',
    },
    {
      id: id('tip', 3),
      icon: '🧳',
      title: 'Yamato valiz transfer',
      body: 'Şehirler arasında büyük valizleri Yamato (Kuroneko) ile otelden otele yollayın. Genelde ertesi gün teslim.',
      source: 'suggestion',
    },
    {
      id: id('tip', 4),
      icon: '💴',
      title: 'Nakit + IC kart',
      body: 'Bazı küçük restoran/bilet makineleri sadece nakit. 7-Eleven ATM yabancı kart kabul eder.',
      source: 'suggestion',
    },
  ],
  shopping: [
    { id: id('shop', 0), category: 'Tokyo', text: 'Kit Kat çeşitleri (sınırlı aromalar)', source: 'suggestion' },
    { id: id('shop', 1), category: 'Tokyo', text: 'Tokyo Banana / souvenir tatlı', source: 'suggestion' },
    { id: id('shop', 2), category: 'Tokyo', text: 'Daiso / Seria (100¥ shop)', source: 'suggestion' },
    { id: id('shop', 3), category: 'Elektronik', text: 'Bic Camera / Yodobashi (Tax-Free)', source: 'suggestion' },
    { id: id('shop', 4), category: 'Osaka', text: 'Pocky & Glico çeşitleri', source: 'suggestion' },
    { id: id('shop', 5), category: 'Osaka', text: 'Kitchenware (Japon bıçağı vb.)', source: 'suggestion' },
    { id: id('shop', 6), category: 'Donki', text: 'Don Quijote — ilaç, kozmetik, atıştırmalık (gece açık)', source: 'suggestion' },
  ],
  foodSpots: [
    {
      id: id('food', 0),
      name: 'Gyukatsu Motomura',
      area: 'Shinjuku',
      category: 'Et',
      note: 'Kızarmış dana şnitzel, sıra olabilir (~¥1.500)',
      source: 'suggestion',
    },
    {
      id: id('food', 1),
      name: 'Ichiran Ramen',
      area: 'Birçok şube',
      category: 'Ramen',
      note: 'Tek kişilik kabin ramen deneyimi',
      source: 'suggestion',
    },
    {
      id: id('food', 2),
      name: 'Kuromon Market',
      area: 'Osaka',
      category: 'Sokak',
      note: 'Taze deniz ürünü ve atıştırmalık',
      source: 'suggestion',
    },
  ],
  compass: [
    {
      id: id('comp', 0),
      title: 'Acil numaralar',
      kind: 'emergency',
      content: '110 Polis · 119 Ambulans · Yabancılar: 03-3501-0110 (Tokyo)',
      source: 'suggestion',
    },
    {
      id: id('comp', 1),
      title: 'Temel Japonca',
      kind: 'phrases',
      content: 'Sumimasen (pardon) · Arigatou (teşekkür) · Doko desu ka? (nerede?) · Eigo ga hanasemasu ka?',
      source: 'suggestion',
    },
    {
      id: id('comp', 2),
      title: 'Yemekte sor',
      kind: 'phrases',
      content: 'この料理に豚肉は入っていますか？(Domuz var mı?) · ラードは使われていますか？(Domuz yağı?) · 鶏肉のメニューはありますか？(Tavuklu var mı?) · お子様用に辛くないものはありますか？(Çocuk için acısız?)',
      source: 'suggestion',
    },
    {
      id: id('comp', 3),
      title: 'Para',
      kind: 'money',
      content: 'Nakit yaygın. 7-Eleven ATM yabancı kart kabul eder. Kredi kartı nakit avans limiti bankaya göre değişir; gitmeden önce kontrol edin.',
      source: 'suggestion',
    },
    {
      id: id('comp', 4),
      title: 'Ulaşım',
      kind: 'transport',
      content: 'Suica/Pasmo metro+konbini için. Şehirler arası Shinkansen (Hyperdia / Japan Travel app rota gösterir).',
      source: 'suggestion',
    },
  ],
};

export function getGuideDefaultsForCountry(code: string): TripGuide | null {
  // Uygulama Japonya'ya özel; her durumda JP defaults döner.
  if (code && code !== 'JP') return JAPAN_GUIDE_DEFAULTS;
  return JAPAN_GUIDE_DEFAULTS;
}
