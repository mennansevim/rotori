/**
 * "Gitmeden Önce" hap bilgi kartları — viewer'da kullanıcıya
 * Japonya gezisinden önce hazırlık konularında pratik özet sunar.
 */

export interface PreJapanLink {
  label: string;
  url: string;
}

export interface PreJapanCard {
  id: string;
  emoji: string;
  title: string;
  /** 1-2 satırlık kart kapağı altı özet. */
  summary: string;
  /** Açık paragraflar — yeni satır = yeni paragraf. */
  body: string;
  /** Opsiyonel madde listesi. */
  bullets?: string[];
  /** Dış linkler (resmi/güvenilir). */
  links?: PreJapanLink[];
}

export const PRE_JAPAN_CARDS: PreJapanCard[] = [
  {
    id: 'visit-japan-web',
    emoji: '🛂',
    title: 'Visit Japan Web',
    summary:
      'Pasaport, gümrük ve beyan işlemlerini önceden doldur — varışta QR ile geç.',
    body:
      'Japonya’ya girişte pasaport, gümrük ve beyan işlemleri için Visit Japan Web formunu önceden doldurman önerilir.\n\nKayıt sonrası giriş ve gümrük için iki QR kod üretilir. Bu QR’ları ekran görüntüsü olarak da sakla — havalimanında internet kesilirse işine yarar.',
    bullets: [
      'Kayıt en az 1 hafta öncesinden yapılabilir.',
      'Aile üyelerini tek hesaba ekleyebilirsin.',
      'Otel adresi ve uçuş bilgisi gerekir.',
    ],
    links: [{ label: 'Visit Japan Web (resmi)', url: 'https://vjw-lp.digital.go.jp/en/' }],
  },
  {
    id: 'payment-cash',
    emoji: '💴',
    title: 'Ödeme & Nakit',
    summary: 'Birçok yerde kart geçer ama küçük yerler nakit ister. Plan B hazır olsun.',
    body:
      'Japonya’da çoğu zincir mağaza ve büyük restoran kart kabul eder, ama bazı küçük restoranlar, tapınak çevresi dükkanları, bilet makineleri ve yerel noktalar sadece nakit ister.\n\nKredi kartından nakit avans çekebilirsin; ama limitler bankaya göre değişir (~25.000 TL civarı sınırlı olabilir). Gitmeden önce bankanı arayıp limit ve döviz kuru komisyonunu sor.\n\n7-Eleven ATM’leri yabancı kartlarla en uyumlu olanlardır. JR istasyonlarındaki Seven Bank de uygundur.',
    bullets: [
      'Yanına ~30.000¥ acil nakit al.',
      'Suica/Pasmo (IC kart) hem metro hem konbini için pratik.',
      'Bazı Donki şubeleri ve restoranlar Apple Pay / Google Pay kabul eder.',
    ],
  },
  {
    id: 'markets',
    emoji: '🏪',
    title: 'Market Rehberi',
    summary: 'Konbini ve büyük mağaza farkı — neyi nereden alırsın.',
    body:
      'Japonya market kültürü Türkiye’den farklı. Konbini (24/7 mini market) hazır yemek, içecek, atıştırmalık ve günlük ihtiyaçların ana noktası.',
    bullets: [
      '7-Eleven — yabancı kart ATM, hazır yemek, onigiri.',
      'Lawson — karaage, premium tatlılar.',
      'FamilyMart — famichiki tavuk, fried chicken.',
      'Don Quijote (Donki) — kozmetik, ilaç, atıştırmalık, valiz (gece geç saate kadar açık).',
      'Aeon — büyük süpermarket, aile alışverişi.',
      'Life / Gyomu Super — toplu alışveriş, ucuz fiyat.',
    ],
  },
  {
    id: 'amazon-japan',
    emoji: '📦',
    title: 'Amazon Japan',
    summary: 'Japonya’dayken otele sipariş — ama teslimat sürelerini hesapla.',
    body:
      'amazon.co.jp üzerinden Japonya içindeyken alışveriş yapabilirsin. Otel adresine veya desteklenen teslim noktalarına sipariş gönderebilirsin.\n\nOtelin paket kabul edip etmediğini check-in’de teyit et. Teslim süresi genelde 1–3 gün; son güne kalan siparişler yetişmeyebilir.',
    bullets: [
      'Hesap Türkiye Amazon ile ortak değildir; yeni hesap aç.',
      'Bazı ürünler "Prime same-day" — büyük şehirlerde aynı gün gelebilir.',
      'Konbini’de teslim alma seçeneği bazı satıcılarda mevcut.',
    ],
    links: [{ label: 'amazon.co.jp', url: 'https://www.amazon.co.jp' }],
  },
  {
    id: 'yamato-luggage',
    emoji: '🧳',
    title: 'Yamato Valiz Transfer',
    summary: 'Şehir değiştirirken büyük valizleri kargolat — Shinkansen’de hafif çık.',
    body:
      'Yamato Transport (Kuroneko Yamato) Japonya’nın en yaygın kargo şirketi. Büyük valizleri otelden otele, havalimanından otele veya otelden havalimanına gönderebilirsin.\n\nGenelde ertesi gün teslim; bazı uzak şehirlerde 2 gün sürebilir. Otel resepsiyonu çoğunlukla işlemi sizin için yapar.\n\nBir gecelik ihtiyaçlarını el çantanda taşı: pasaport, ilaç, para, elektronik, şarj aleti, yedek iç çamaşırı, telefon kablosu.',
    bullets: [
      'Tek valiz ~2000–3000¥ aralığında.',
      'Otel teslim için en az check-out gününden 1 gün önce ver.',
      'Pasaport, ilaç, değerli elektronik VALİZE KONMAZ.',
    ],
    links: [{ label: 'Yamato Transport', url: 'https://www.kuronekoyamato.co.jp/en/' }],
  },
  {
    id: 'suitcase-shopping',
    emoji: '🛍️',
    title: 'Valiz & Alışveriş',
    summary: 'Tax-free, ekstra valiz ve havayolu bagaj sınırı.',
    body:
      'Japonya’da alışverişin yoğunlaşabilir. Tax-free indirimi için pasaportun yanında olmalı ve aynı mağazada 5.000¥ üstü harcama gerekir.\n\nEkstra valiz almak için: Don Quijote (uygun fiyat), Yodobashi/Bic Camera (kalite + tax-free), büyük AVM’ler ve outlet (premium markalar).',
    bullets: [
      'Tax-free için pasaport gerek; mağazada özel kasa.',
      'Ekstra valiz son gün almak risklidir — bir gün öncesi al.',
      'Havayolu bagaj limitini kontrol et (~23kg standart).',
      'Lityum pil ve power bank EL ÇANTASINDA olmalı.',
    ],
  },
];

export function getPreJapanCard(id: string): PreJapanCard | undefined {
  return PRE_JAPAN_CARDS.find((c) => c.id === id);
}
