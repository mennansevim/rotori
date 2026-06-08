/** Havaalanı rehberi — Türkiye çıkışı ve Japonya iniş/çıkışı için pratik bilgi. */

interface GuideContent {
  name: string;
  flag: string;
  /** Terminaller ve hangi havayolu hangi terminalde */
  terminals: string;
  /** Transit / aktarma süresi tavsiyesi */
  transitTime?: string;
  /** Lounge erişimi */
  lounge?: string;
  /** Su çeşmesi / hidrasyon */
  water?: string;
  /** Wi-Fi / eSIM / SIM kart */
  connectivity?: string;
  /** Bagaj / koin lockers */
  baggage?: string;
  /** Ulaşım — şehir merkezine */
  transport: string;
  /** Yemek noktaları */
  food?: string;
  /** Gece geçirme — uçuş gecikti veya erken vardı */
  overnight?: string;
  /** Tax-free / iade noktaları (Japonya iadesi havalimanında değil ama Türkiye'ye girerken vs) */
  taxRefund?: string;
  /** Önemli not / kritik ipucu */
  critical?: string;
}

const GUIDES: Record<string, GuideContent> = {
  IST: {
    name: 'İstanbul Havalimanı',
    flag: '🇹🇷',
    terminals:
      'Tek terminal yapısı (devasa). THY ve Star Alliance: Departure Hall A–G. Diğer havayolları için kapı yönlendirmeleri ekranlarda.',
    transitTime:
      'Aktarmasız direkt Japonya uçuşu THY ile ~11 saat. Aktarmalıysanız ≥ 2 saat aktarma süresi bırakın — terminal çok uzun.',
    lounge:
      'THY Business / Miles & Smiles Elite lounge (D kapısı yakını). Priority Pass ile IGA Lounge ve diğerleri.',
    water:
      'Çeşmeler güvenlik sonrası tüm kapı bölgelerinde mevcut. Boş şişeyi yanınızda taşıyın.',
    connectivity:
      'Ücretsiz Wi-Fi 2 saat (pasaport numarasıyla); sonra ücretli. Türk Telekom / Vodafone / Turkcell stantları airside ve landside. Japonya için eSIM (Ubigi/Airalo) önceden kurun.',
    baggage:
      'Bagaj limit kontrolü kapıda da yapılabilir — el bagajı 8kg sınırına dikkat. Lost & Found arrivals seviyesinde.',
    transport:
      'Havaist (otobüs): Taksim/Sultanahmet ~85₺, 80–100 dk. M11 metrosu Kağıthane → Gayrettepe ~50 dk. Taksi ~700–900₺ trafik yoğunsa daha fazla.',
    food:
      'Airside: Simit Sarayı (kahvaltı), Kahve Dünyası, Burger King, Popeyes, sushi (Wagamama), kebap (Köfteci Yusuf).',
    overnight:
      'YOTEL içerde ve Hilton landside. Çok kısa aktarma için lounge\'da dinlenin; gece kapanma yok.',
    critical:
      'Uçuş 3 saat öncesinden online check-in açılır — bagajı bilet alanında dropla, kuyruğu atlatırsın. Sıvı 100ml kuralı uygulanır.',
  },
  SAW: {
    name: 'Sabiha Gökçen Havalimanı',
    flag: '🇹🇷',
    terminals:
      'Tek iç + tek dış terminal yan yana. Pegasus ve Anadolu Jet hub. THY de tarifeli.',
    transitTime:
      'Aktarma minimum 60 dk (iç↔dış); paspor kontrol kuyruğu yoğun saatte 30+ dk.',
    lounge: 'CIP Lounge (Priority Pass kabul) Gate 209 yakını.',
    water: 'Çeşmeler güvenlik sonrası mevcut. Pegasus uçuşunda su ücretli.',
    connectivity:
      'Ücretsiz Wi-Fi 2 saat. Vodafone/Turkcell standları landside; airside küçük market.',
    transport:
      'HAVABUS Taksim/Kadıköy ~70–110₺, 60–90 dk. Metro yok (M4 uzatma sürüyor). Taksi ~800–1100₺.',
    food: 'Airside seçenek az: Burger King, kahve zinciri, simit. Yemekleri uçuş öncesi planlayın.',
    critical:
      'Sabah erken (06:00–08:00) çıkışlarda güvenlik 1 saat sürebilir — 3 saat erken gelin.',
  },
  ESB: {
    name: 'Esenboğa Havalimanı',
    flag: '🇹🇷',
    terminals: 'Tek terminal, iç ve dış hatlar ayrı kapı blokları.',
    transitTime: 'Aktarma minimum 60 dk.',
    transport: 'Belko Air otobüs Kızılay ~30₺, 45 dk. Taksi Ankara merkez ~250–350₺.',
    food: 'Kafe ve hızlı restoran seçenekleri var; Japonya gibi uzun uçuş öncesi hafif yiyin.',
    critical: 'Ankara\'dan direkt Japonya uçuşu yok — aktarma genelde IST veya Avrupa.',
  },
  HND: {
    name: 'Tokyo Haneda Havalimanı',
    flag: '🇯🇵',
    terminals:
      'T1 (ANA iç hat), T2 (JAL iç hat), T3 (Uluslararası — THY/JAL/ANA uluslararası buradan). Terminaller ücretsiz shuttle veya tren ile bağlı.',
    transitTime:
      'İlk uçuşunuz HND ise: pasaport + bagaj + gümrük ~45–60 dk. Aktarmalıysanız (HND iç hat → KIX) ≥ 90 dk bırakın.',
    lounge:
      'TIAT Lounge (Priority Pass, T3). JAL Sakura Lounge ve ANA Lounge premium kabin için.',
    water:
      '🚰 Su çeşmeleri (mizu nomi-ba 水飲み場) her kat var — soğuk + sıcak musluk. Japonya musluk suyu güvenle içilir.',
    connectivity:
      '📶 Ücretsiz Wi-Fi (FREE_Wi-Fi_HANEDA) süresiz, sınırsız. JR East Pass ve mobile SIM stantları gelişler bölgesinde. eSIM zaten aktifse uçaktan iner inmez bağlanır.',
    baggage:
      '🧳 Koin lockers (300–700¥) her terminal: küçük el çantasından büyük bavula kadar. Sayfayı not edin, anahtarsız QR var.',
    transport:
      '🚃 Tokyo Monorail → Hamamatsucho ~15 dk, ~520¥ (Suica geçer). Keikyu Line → Shinagawa ~15 dk, ~330¥. Limuzin Otobüs Shinjuku/Ginza ~1.300¥. Taksi gece tarifesi ~7.000–10.000¥.',
    food:
      '🍣 T3 4–5. kat "Edo Market" ramen, sushi, tonkatsu — fiyat şehir restoranıyla aynı. T2 6. kat panoramik restoranlar. T3 24 saat açık.',
    overnight:
      'T3 First Cabin kapsül otel airside (~3.000¥/saat). Royal Park Hotel landside. Bench + ücretsiz Wi-Fi ile gece geçirmek yasal.',
    taxRefund:
      'Japonya alışverişlerinde tax-free (パスポート ile mağazada ayrılır) — havalimanı işlemi YOK, doğrudan mağazada %8–10 düşülür.',
    critical:
      '✅ Welcome Suica veya PASMO kartını arrivals zemindeki otomattan al (depozito yok, 28 gün geçerli). Cash 1.500–3.000¥ yükle — şehirde her şey için kullan.',
  },
  NRT: {
    name: 'Tokyo Narita Havalimanı',
    flag: '🇯🇵',
    terminals:
      'T1 (Star Alliance — THY/ANA), T2 (OneWorld — JAL), T3 (LCC — Jetstar/Peach). T1–T2 arası shuttle 8 dk; T3 yürüme 10 dk.',
    transitTime:
      'Aktarma ≥ 75 dk (T1↔T2). Pasaport + bagaj ~45 dk. NRT şehir merkezine UZAK — transfer için 90+ dk planlayın.',
    lounge: 'IASS Lounge (Priority Pass T1 ve T2). JAL Sakura Lounge, ANA Suite Lounge premium.',
    water: '🚰 Her terminal çoklu çeşme; "drinking water" tabelası takip et.',
    connectivity:
      '📶 NARITA-AIRPORT-FREE-WiFi süresiz ücretsiz. SoftBank/docomo/AU stantları arrivals; Japan Wireless / Sakura Mobile turist SIM/pocket WiFi tezgâhları.',
    baggage:
      '🧳 Koin lockers (300–1.000¥) her terminal. Yamato Transport (Takkyubin) tezgâhı arrivals — bagajınızı otele ertesi gün gönderin (~2.000¥/parça).',
    transport:
      '🚄 Narita Express (N\'EX) → Tokyo St / Shinjuku ~60 dk, ~3.070¥ (turist için round-trip 5.000¥ var). Keisei Skyliner → Ueno ~40 dk, ~2.570¥. Limuzin Otobüs Shinjuku ~3.200¥, 90 dk. Taksi 25.000–30.000¥!',
    food:
      '🍱 T1 5. kat "Narita Nagomi Yokocho" geleneksel Japon yemek sokağı. T2 4. kat ramen/sushi. T1 24 saat açık.',
    overnight:
      'T1 Nine Hours kapsül otel airside. Marroad Hotel ücretsiz shuttle ile 10 dk; gece son ulaşım 22:30, erken kalkışlarda otel zorunlu.',
    taxRefund:
      'Tax-free mağazada hesaplanır; havalimanında ekstra işlem yok. Tarımsal/yiyecek izinleri için gümrük formu uçakta dağıtılır.',
    critical:
      '✅ JR Pass aktivasyonu T1/T2 arrivals JR EAST Travel Service Center\'da yapılır — pasaport + voucher gerekli. Sıra olabilir, 30 dk pay bırakın.',
  },
  KIX: {
    name: 'Osaka Kansai Havalimanı',
    flag: '🇯🇵',
    terminals:
      'T1 (büyük havayolları — JAL/ANA/THY) ve T2 (Peach LCC). T1 4 kat: 1. gelişler, 2. iç hat, 4. dış hat gidiş.',
    transitTime: 'Aktarma ≥ 75 dk. Pasaport + bagaj 45–60 dk; dönüş uçuşunda 3 saat öncesinden geliniz.',
    lounge:
      'KAL Lounge ve Aeroplaza Lounge (Priority Pass). JAL Sakura ve ANA Suite premium kabin.',
    water: '🚰 Çeşmeler her katta; Japonya genelinde musluk suyu güvenli.',
    connectivity:
      '📶 KIX-Airport-FreeWiFi süresiz. T1 1. kat (arrivals) Japan Wireless tezgâhı pocket WiFi & SIM.',
    baggage:
      '🧳 Koin lockers (400–800¥) zemin ve 2. kat. Takkyubin (Yamato Transport / Sagawa) — Osaka otele teslim ~1.500¥, ertesi gün.',
    transport:
      '🚄 JR Haruka Express → Shin-Osaka ~50 dk, 2.420¥ (turist ICOCA & Haruka combo 3.600¥). Nankai Rapit → Namba ~38 dk, 1.450¥. Limuzin Otobüs ~1.600¥. Taksi Namba ~17.000¥.',
    food:
      '🍣 T1 3. kat (security öncesi) Aeroplaza\'da Osaka mutfağı: okonomiyaki, takoyaki, ramen. Airside seçim daha sınırlı; yemeği önceden alın.',
    overnight:
      'Hotel Nikko Kansai Airport T1 yürüme mesafesinde. First Cabin KIX airside kapsül otel. Bench + ücretsiz Wi-Fi gece için.',
    taxRefund:
      'Tax-free mağazada düşülür; havalimanında işlem yok. Yiyecek ihracat izinleri için gümrük tarafı kontrol eder.',
    critical:
      '✅ Dönüş uçuşunda 3 saat öncesinden gelin — KIX köprüde, ulaşım gecikebilir. Nankai Rapit ekspres sınırlı sefer, son tren 23:00 civarı.',
  },
};

interface Props {
  iata: string;
  /** Hangi yön — başlığı buna göre değiştirir. */
  role: 'origin' | 'destination' | 'return-origin';
}

const ROLE_LABELS: Record<Props['role'], string> = {
  origin: '🛫 Kalkış noktası',
  destination: '🛬 Varış noktası',
  'return-origin': '🛫 Dönüş kalkışı',
};

export function AirportGuide({ iata, role }: Props) {
  const guide = GUIDES[iata];
  if (!guide) return null;

  return (
    <details className="airport-guide">
      <summary className="airport-guide-head">
        <span className="airport-guide-flag">{guide.flag}</span>
        <span className="airport-guide-name">
          <strong>{guide.name}</strong>
          <span className="airport-guide-role">{ROLE_LABELS[role]} · {iata}</span>
        </span>
        <span className="airport-guide-toggle" aria-hidden>
          ▾
        </span>
      </summary>
      <div className="airport-guide-body">
        <Row label="🏢 Terminaller" body={guide.terminals} />
        {guide.critical && <Row label="⚠️ Önemli" body={guide.critical} highlight />}
        {guide.transport && <Row label="🚃 Şehre ulaşım" body={guide.transport} />}
        {guide.transitTime && <Row label="⏱️ Transit süresi" body={guide.transitTime} />}
        {guide.connectivity && <Row label="📶 İnternet & SIM" body={guide.connectivity} />}
        {guide.baggage && <Row label="🧳 Bagaj & lockers" body={guide.baggage} />}
        {guide.lounge && <Row label="🛋️ Lounge" body={guide.lounge} />}
        {guide.water && <Row label="💧 Su" body={guide.water} />}
        {guide.food && <Row label="🍽️ Yemek" body={guide.food} />}
        {guide.overnight && <Row label="🌙 Gece geçirme" body={guide.overnight} />}
        {guide.taxRefund && <Row label="💴 Tax-free" body={guide.taxRefund} />}
      </div>
    </details>
  );
}

function Row({ label, body, highlight }: { label: string; body: string; highlight?: boolean }) {
  return (
    <div className={`airport-guide-row${highlight ? ' highlight' : ''}`}>
      <span className="airport-guide-label">{label}</span>
      <span className="airport-guide-text">{body}</span>
    </div>
  );
}
