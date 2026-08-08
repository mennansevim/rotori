/// Affiliate / referans linkleri ve bağlamsal öneri kartları.
/// Tüm linkler tek yerden yönetilir; affiliate ID'ler değişince burada güncellenir.
///
/// i18n: Kart metinleri LText ile iki dilli (TR/EN) — uygulama geneliyle uyumlu.

import '../domain/localized_text.dart';

class AffiliateLink {
  const AffiliateLink({
    required this.label,
    required this.description,
    required this.url,
    required this.emoji,
    required this.cta,
    this.priceHint,
  });

  final LText label;
  final LText description;
  final String url;
  final String emoji;
  final LText cta;
  final LText? priceHint;
}

/// Seyahat öncesi hazırlık — en yüksek dönüşüm noktası.
const kPreDepartureAffiliates = <AffiliateLink>[
  AffiliateLink(
    emoji: '🚄',
    label: LText('JR Pass (Tüm Japonya)', 'JR Pass (All Japan)'),
    description: LText(
      '7/14/21 günlük sınırsız tren bileti. Şehirler arası seyahat edeceksen '
      'tek tek bilet almaktan çok daha ucuz.',
      '7/14/21-day unlimited rail pass. Much cheaper than individual tickets '
      'if you travel between cities.',
    ),
    url: 'https://www.jrailpass.com/?aff=rotori',
    cta: LText('JR Pass al', 'Get JR Pass'),
    priceHint: LText('7 gün ~¥50,000', '7 days ~¥50,000'),
  ),
  AffiliateLink(
    emoji: '📶',
    label: LText('Japonya eSIM / Pocket WiFi', 'Japan eSIM / Pocket WiFi'),
    description: LText(
      'Havalimanında kuyruk beklemeyin. eSIM\'i şimdi alın, uçaktan iner inmez '
      'internete bağlanın.',
      'Skip the airport queue. Get your eSIM now and connect as soon as you land.',
    ),
    url: 'https://airalo.pxf.io/rotori-japan',
    cta: LText('eSIM al', 'Get eSIM'),
    priceHint: LText('8 gün ~400 TL', '8 days ~\$12'),
  ),
  AffiliateLink(
    emoji: '🏨',
    label: LText('Booking.com ile otel ara', 'Search hotels on Booking.com'),
    description: LText(
      'Ücretsiz iptalli otelleri filtrele, puanlara ve konuma göre karşılaştır.',
      'Filter for free cancellation, compare by rating and location.',
    ),
    url: 'https://www.booking.com/index.html?aid=rotori',
    cta: LText('Otel ara', 'Find hotels'),
  ),
  AffiliateLink(
    emoji: '🎫',
    label: LText('Aktiviteler ve deneyimler', 'Activities & experiences'),
    description: LText(
      'TeamLab, Disney, Universal, tapınak turları, yemek deneyimleri — '
      'popüler aktiviteleri önceden ayırtın.',
      'TeamLab, Disney, Universal, temple tours, food experiences — '
      'book popular activities in advance.',
    ),
    url: 'https://www.klook.com/affiliate/rotori?dest=japan',
    cta: LText('Aktiviteleri keşfet', 'Explore activities'),
  ),
  AffiliateLink(
    emoji: '🚕',
    label: LText('Havalimanı transferi', 'Airport transfer'),
    description: LText(
      'Narita\'dan Tokyo\'ya ya da Kansai\'den Osaka\'ya özel transfer. '
      'Metroyla uğraşmak istemeyenler için.',
      'Private transfer from Narita to Tokyo or Kansai to Osaka. '
      'For those who don\'t want to deal with the subway with luggage.',
    ),
    url: 'https://www.klook.com/affiliate/rotori?dest=japan&cat=transfer',
    cta: LText('Transfer ayırt', 'Book transfer'),
    priceHint: LText('~1,500 TL', '~\$45'),
  ),
];

/// Şehirlerarası ulaşım — planlama akışında gösterilir.
const journeyAffiliate = AffiliateLink(
  emoji: '🚄',
  label: LText('JR Pass ile şehirlerarası sınırsız ulaşım', 'Unlimited intercity travel with JR Pass'),
  description: LText(
    'Bu şehirler arası tek tek bilet alsan ~¥35,000-60,000 tutar. '
    '7 günlük JR Pass ile hepsini tek fiyata gez.',
    'Individual tickets between these cities would cost ~¥35,000-60,000. '
    'A 7-day JR Pass covers all of them for one price.',
  ),
  url: 'https://www.jrailpass.com/?aff=rotori',
  cta: LText('JR Pass fiyatlarını gör', 'See JR Pass prices'),
  priceHint: LText('7 gün ~¥50,000', '7 days ~¥50,000'),
);

/// Otel adımında gösterilir.
const hotelAffiliate = AffiliateLink(
  emoji: '🏨',
  label: LText('Booking.com\'da bu şehirdeki oteller', 'Hotels in this city on Booking.com'),
  description: LText(
    'Ücretsiz iptal, konum puanı ve fiyata göre filtrele. '
    'Rezervasyon yapmadan önce puanları karşılaştır.',
    'Filter by free cancellation, location score, and price. '
    'Compare ratings before you book.',
  ),
  url: 'https://www.booking.com/searchresults.html?aid=rotori',
  cta: LText('Otel ara', 'Search hotels'),
);
