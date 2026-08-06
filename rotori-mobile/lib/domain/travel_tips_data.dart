// "Mutlaka bilmeniz gerekenler" verisi — Japonya seyahati öncesi/esnası için
// pratik tavsiyeler ve uyarılar. Belgeler, para, ulaşım, elektronik, sağlık,
// valiz, görgü kuralları ve genel notlar bölümlerine ayrılmıştır.
//
// i18n: Bu içerik uzun ve serbest metindir; core/l10n.dart anahtar sistemine
// sığmaz. Bu yüzden TR + EN karşılıkları doğrudan modelin içinde `LText(tr, en)`
// ile yan yana tutulur — ekranda `.of(lang)` ile çözülür (bkz. localized_text.dart).
// Japonca terimler ve marka adları literal kalır.

import 'localized_text.dart';

/// Tek bir tavsiye/uyarı maddesi: başında bir emoji + iki dilli metin.
class MustKnowTip {
  const MustKnowTip({required this.emoji, required this.text});

  /// Madde başı ikonu — literal.
  final String emoji;

  /// Madde metni (TR + EN).
  final LText text;
}

/// Bir konu başlığı altında gruplanmış tavsiyeler (ör. Belgeler, Para, Sağlık).
class MustKnowSection {
  const MustKnowSection({
    required this.emoji,
    required this.title,
    required this.tips,
  });

  /// Bölüm ikonu — literal.
  final String emoji;

  /// Bölüm başlığı (TR + EN).
  final LText title;

  /// Bölümün maddeleri.
  final List<MustKnowTip> tips;
}

/// "Mutlaka bilmeniz gerekenler" bölümleri — ekranda sırayla PCard olarak çizilir.
const List<MustKnowSection> kMustKnowSections = [
  // -------------------------------------------------------------------------
  // 📄 Belgeler ve giriş
  // -------------------------------------------------------------------------
  MustKnowSection(
    emoji: '📄',
    title: LText('Belgeler ve Giriş', 'Documents & Entry'),
    tips: [
      MustKnowTip(
        emoji: '🛂',
        text: LText(
          'Pasaportun, seyahatin DÖNÜŞ tarihinden itibaren en az 6 ay geçerli '
          'olmalı. Süresi kısa kalıyorsa yola çıkmadan yenile.',
          'Your passport must be valid for at least 6 months from your RETURN '
          'date. If it is close to expiring, renew it before you travel.',
        ),
      ),
      MustKnowTip(
        emoji: '🇹🇷',
        text: LText(
          'Türkiye pasaportu ile turistik amaçlı 90 güne kadar vizesiz giriş '
          'yapabilirsin; yine de gidiş-dönüş bileti ve konaklama bilgisi hazır olsun.',
          'Turkish passport holders can enter visa-free for tourism for up to '
          '90 days; still, keep your return ticket and accommodation details handy.',
        ),
      ),
      MustKnowTip(
        emoji: '📱',
        text: LText(
          'Uçuştan önce Visit Japan Web üzerinden göçmenlik ve gümrük formlarını '
          'doldurup QR kodlarını al — havalimanında kuyruğu ciddi kısaltır.',
          'Before your flight, fill in the immigration and customs forms on '
          'Visit Japan Web and get the QR codes — it cuts the airport queues a lot.',
        ),
      ),
      MustKnowTip(
        emoji: '🪪',
        text: LText(
          'Pasaportunu her zaman yanında taşı: Japonya\'da yabancıların kimlik '
          'belgesini üstünde bulundurması yasal zorunluluk, ayrıca vergisiz '
          'alışverişte de gerekiyor.',
          'Always carry your passport: foreigners are legally required to carry '
          'ID in Japan, and you also need it for tax-free shopping.',
        ),
      ),
    ],
  ),

  // -------------------------------------------------------------------------
  // 💳 Para ve ödeme
  // -------------------------------------------------------------------------
  MustKnowSection(
    emoji: '💳',
    title: LText('Para ve Ödeme', 'Money & Payment'),
    tips: [
      MustKnowTip(
        emoji: '🏧',
        text: LText(
          'Banka/ATM kartını mutlaka yanına al — Japonya ATM\'lerinden mevduat '
          'hesabından ancak kartla para çekebilirsin. 7-Eleven ve Japan Post '
          '(Yūcho) ATM\'leri yabancı kartları kabul eder ve çoğu 7/24 açıktır.',
          'Bring your bank/ATM card — you can only withdraw cash from Japanese '
          'ATMs with a card linked to your account. 7-Eleven and Japan Post '
          '(Yūcho) ATMs accept foreign cards and most are open 24/7.',
        ),
      ),
      MustKnowTip(
        emoji: '⚠️',
        text: LText(
          'Önemli: Kredi kartında nakit avans limiti ayrı olabilir ve çoğu '
          'kartta günlük/işlem limiti düşüktür. Asıl nakit planını debit '
          '(banka) kartıyla yap; yolculuk öncesi bankandan yurtdışı ATM '
          'çekim limiti ve güvenlik bloklarını mutlaka kontrol et.',
          'Important: cash-advance limits on credit cards are often separate '
          'and usually lower per day/transaction. Plan your main cash access '
          'with a debit card; before travel, confirm your overseas ATM '
          'withdrawal limits and security blocks with your bank.',
        ),
      ),
      MustKnowTip(
        emoji: '💴',
        text: LText(
          'Japonya büyük ölçüde nakit kültürü: yanında ~10.000–20.000¥ nakit '
          'bulundur. Küçük lokantalar, tapınaklar ve pazarlar yalnız nakit kabul '
          'edebilir.',
          'Japan is largely a cash culture: keep ~¥10,000–20,000 in cash on you. '
          'Small restaurants, temples and markets may accept cash only.',
        ),
      ),
      MustKnowTip(
        emoji: '👛',
        text: LText(
          'Küçük bir el çantası veya bozuk para cüzdanı taşı — çok fazla madeni '
          'para (1, 5, 10, 100, 500¥) birikir ve cebinde kaybolur.',
          'Carry a small pouch or coin purse — you will collect a lot of coins '
          '(¥1, 5, 10, 100, 500) and they pile up fast.',
        ),
      ),
      MustKnowTip(
        emoji: '🚉',
        text: LText(
          'Suica veya Pasmo IC kart al (ya da telefonuna Mobile Suica ekle): '
          'metro, otobüs, konbini ve otomatlarda tek dokunuşla ödeme yaparsın.',
          'Get a Suica or Pasmo IC card (or add Mobile Suica to your phone): pay '
          'with one tap on trains, buses, convenience stores and vending machines.',
        ),
      ),
      MustKnowTip(
        emoji: '🏷️',
        text: LText(
          'Tax-free: aynı mağazada 5.000¥ üstü alışverişte pasaportunla vergisiz '
          'alabilirsin. Vergisiz ürünler ayrı poşetlenir; ülkeden çıkana kadar '
          'açmadan sakla.',
          'Tax-free: spend over ¥5,000 at one store and buy tax-free with your '
          'passport. Tax-free goods are sealed separately; keep them unopened '
          'until you leave the country.',
        ),
      ),
    ],
  ),

  // -------------------------------------------------------------------------
  // 🚆 Ulaşım ve internet
  // -------------------------------------------------------------------------
  MustKnowSection(
    emoji: '🚆',
    title: LText('Ulaşım ve İnternet', 'Transport & Connectivity'),
    tips: [
      MustKnowTip(
        emoji: '🎫',
        text: LText(
          'Japan Rail (JR) Pass kullanacaksan gitmeden ONLINE al ve değişim '
          'kuponunu Japonya\'da JR ofisinde gerçek pasa çevir. Şehirler arası çok '
          'seyahat edeceksen büyük tasarruf sağlar.',
          'If you will use a Japan Rail (JR) Pass, buy it ONLINE before you go '
          'and swap the exchange voucher for the real pass at a JR office in '
          'Japan. It saves a lot if you travel between many cities.',
        ),
      ),
      MustKnowTip(
        emoji: '📶',
        text: LText(
          'eSIM veya cep wifi\'sini (pocket wifi) gitmeden ayarla. İnternet '
          'harita, çeviri ve tren saatleri için şart; havalimanında kuyruğa '
          'girmemek için önceden hallet.',
          'Set up an eSIM or pocket wifi before you travel. Internet is '
          'essential for maps, translation and train times; sort it out in '
          'advance so you skip the airport queue.',
        ),
      ),
      MustKnowTip(
        emoji: '🚶',
        text: LText(
          'Günde ortalama 15.000–22.000 adım yürüyeceksin. Rotaları buna göre '
          'planla, mola ver ve su içmeyi ihmal etme.',
          'You will walk about 15,000–22,000 steps a day. Plan your routes '
          'accordingly, take breaks and stay hydrated.',
        ),
      ),
      MustKnowTip(
        emoji: '🤫',
        text: LText(
          'Trenlerde ve toplu taşımada sessizlik esastır: telefonla konuşma, '
          'zil sesini "manner mode"a al. Öncelikli koltuklar yaşlı ve engelliler '
          'içindir.',
          'Silence is expected on trains and public transport: do not talk on '
          'the phone and switch your ringer to "manner mode". Priority seats are '
          'for the elderly and disabled.',
        ),
      ),
    ],
  ),

  // -------------------------------------------------------------------------
  // 🔌 Elektronik
  // -------------------------------------------------------------------------
  MustKnowSection(
    emoji: '🔌',
    title: LText('Elektronik', 'Electronics'),
    tips: [
      MustKnowTip(
        emoji: '🔋',
        text: LText(
          'Powerbank kuralları: check-in bagajına VERİLEMEZ, yalnız kabin '
          'bagajında taşınır. 160 Wh ve altı olmalı; kişi başı en fazla 2 adet. '
          'Uçları bantla/yalıt, uçak içi prizle powerbank ŞARJ ETME ve uçakta '
          'powerbank\'ten başka cihaz şarj etme.',
          'Power bank rules: NOT allowed in checked luggage, cabin bag only. '
          'Must be 160 Wh or under; max 2 per person. Tape/insulate the '
          'terminals, do NOT charge the power bank from the aircraft socket, and '
          'do not charge other devices from the power bank in flight.',
        ),
      ),
      MustKnowTip(
        emoji: '🔌',
        text: LText(
          'Priz tipi A (iki düz uç), şebeke 100V / 50–60 Hz. Cihazların '
          '100V\'a uygun mu kontrol et; Türkiye tipi (F, yuvarlak) fişler için '
          'seyahat adaptörü götür.',
          'Plug type A (two flat pins), mains 100V / 50–60 Hz. Check your '
          'devices support 100V; bring a travel adapter for Turkish-type '
          '(F, round) plugs.',
        ),
      ),
      MustKnowTip(
        emoji: '📷',
        text: LText(
          'Google Translate uygulamasını ve Japonca çevrimdışı dil paketini '
          'indir. Kamera/çeviri modu menüleri, tabelaları ve ürün etiketlerini '
          'anında okumak için çok işine yarar.',
          'Install Google Translate and download the offline Japanese language '
          'pack. The camera/translate mode is great for instantly reading menus, '
          'signs and product labels.',
        ),
      ),
    ],
  ),

  // -------------------------------------------------------------------------
  // 💊 Sağlık
  // -------------------------------------------------------------------------
  MustKnowSection(
    emoji: '💊',
    title: LText('Sağlık', 'Health'),
    tips: [
      MustKnowTip(
        emoji: '🧦',
        text: LText(
          'Uzun uçuş için kan dolaşımını destekleyen kompresyon çorabı al; '
          'uçakta ara ara kalkıp yürü ve bol su iç (derin ven trombozu riskini '
          'azaltır).',
          'Bring compression socks for the long flight to support circulation; '
          'get up and walk around occasionally and drink plenty of water (lowers '
          'deep-vein thrombosis risk).',
        ),
      ),
      MustKnowTip(
        emoji: '💊',
        text: LText(
          'Mide koruyucu ve düzenli kullandığın reçeteli ilaçlarını yeterli '
          'miktarda, kutusu/reçetesiyle götür. Dikkat: psödoefedrin veya kodein '
          'içeren bazı ilaçlar Japonya\'da yasak — götürmeden önce kontrol et.',
          'Bring your stomach medication and any regular prescription drugs in '
          'sufficient quantity with their boxes/prescriptions. Note: some '
          'medicines containing pseudoephedrine or codeine are banned in Japan — '
          'check before you pack them.',
        ),
      ),
      MustKnowTip(
        emoji: '🪥',
        text: LText(
          'Kendi diş macununu götür: Japonya\'da satılan macunlarda florür oranı '
          'genelde daha düşüktür, alıştığın markayı bulman zor olabilir.',
          'Bring your own toothpaste: toothpaste sold in Japan usually has a '
          'lower fluoride content, and your usual brand may be hard to find.',
        ),
      ),
      MustKnowTip(
        emoji: '🩹',
        text: LText(
          'Küçük bir ecza seti hazırla: ağrı kesici, bağırsak düzenleyici, '
          'yara bandı, alerji ilacı. Yabancı marka ilaç bulmak zor ve eczaneler '
          'çoğu zaman yalnız Japonca.',
          'Pack a small first-aid kit: painkillers, anti-diarrheal, plasters, '
          'allergy medicine. Foreign brands are hard to find and pharmacies are '
          'often Japanese-only.',
        ),
      ),
    ],
  ),

  // -------------------------------------------------------------------------
  // 🚨 Acil durum ve güvenlik
  // -------------------------------------------------------------------------
  MustKnowSection(
    emoji: '🚨',
    title: LText('Acil Durum ve Güvenlik', 'Emergency & Safety'),
    tips: [
      MustKnowTip(
        emoji: '📞',
        text: LText(
          'Acil numaralar: Polis 110, İtfaiye/Ambulans 119. Ücretsiz ve 7/24 '
          'aranır; sabit hatta bile açar. Sakin, yavaş ve mümkünse İngilizce '
          'konuş; adresi/istasyon adını söyle.',
          'Emergency numbers: Police 110, Fire/Ambulance 119. Free and 24/7; '
          'they answer even from a payphone. Speak calmly and slowly, in English '
          'if you can; give the address or nearest station name.',
        ),
      ),
      MustKnowTip(
        emoji: '🪪',
        text: LText(
          'Otelin adını, adresini ve telefonunu bir kağıda (Japonca yazılı) veya '
          'telefon ekran görüntüsü olarak taşı. Kaybolursan taksiciye/polise '
          'göstermen en hızlı çözüm olur.',
          'Carry your hotel\'s name, address and phone on a card (written in '
          'Japanese) or as a phone screenshot. If you get lost, showing it to a '
          'taxi driver or police officer is the fastest fix.',
        ),
      ),
      MustKnowTip(
        emoji: '🏥',
        text: LText(
          'Sağlık sorununda Japonya Ulusal Turizm Örgütü (JNTO) 7/24 çok dilli '
          'yardım hattını ara: 050-3816-2787. Sana en yakın İngilizce hizmet '
          'veren hastaneyi/kliniği yönlendirir.',
          'For a medical issue, call the Japan National Tourism Organization '
          '(JNTO) 24/7 multilingual help line: 050-3816-2787. They direct you to '
          'the nearest hospital/clinic with English service.',
        ),
      ),
      MustKnowTip(
        emoji: '🛡️',
        text: LText(
          'Gitmeden seyahat sağlık sigortası yaptır: Japonya\'da tedavi çok '
          'pahalıdır. Poliçe numaranı ve acil asistans telefonunu offline olarak '
          'yanında bulundur.',
          'Get travel health insurance before you go: treatment in Japan is very '
          'expensive. Keep your policy number and emergency assistance phone '
          'available offline.',
        ),
      ),
      MustKnowTip(
        emoji: '📲',
        text: LText(
          'Resmi "Safety tips" uygulamasını indir (JNTO/JTA): deprem, tayfun ve '
          'tsunami erken uyarılarını İngilizce verir ve en yakın tahliye '
          'noktalarını gösterir.',
          'Install the official "Safety tips" app (JNTO/JTA): it gives '
          'earthquake, typhoon and tsunami early warnings in English and shows '
          'the nearest evacuation points.',
        ),
      ),
      MustKnowTip(
        emoji: '🇹🇷',
        text: LText(
          'T.C. Tokyo Büyükelçiliği\'nin adresini ve telefonunu kaydet. Pasaport '
          'kaybı/çalınması durumunda önce en yakın karakoldan tutanak (todokede) '
          'al, sonra büyükelçiliğe başvur.',
          'Save the address and phone of the Turkish Embassy in Tokyo. If your '
          'passport is lost/stolen, first get a report (todokede) from the '
          'nearest police box, then apply to the embassy.',
        ),
      ),
    ],
  ),

  // -------------------------------------------------------------------------
  // 🎒 Valiz
  // -------------------------------------------------------------------------
  MustKnowSection(
    emoji: '🎒',
    title: LText('Valiz', 'Packing'),
    tips: [
      MustKnowTip(
        emoji: '👟',
        text: LText(
          'En az bir hafta önceden giyip alıştırdığın, KALİTELİ bir yürüyüş '
          'ayakkabısı götür. Günde 15–22 bin adım atacaksın; yeni ayakkabı ayağını '
          'vurur.',
          'Bring a GOOD walking shoe that you have broken in for at least a week '
          'beforehand. You will do 15,000–22,000 steps a day; new shoes will give '
          'you blisters.',
        ),
      ),
      MustKnowTip(
        emoji: '🧳',
        text: LText(
          'Yanına boş bir valiz veya katlanır ek çanta al — Japonya\'da inanılmaz '
          'şeyler alacaksın ve dönüşte yer bulamazsın.',
          'Take an empty suitcase or a foldable extra bag — you will buy '
          'incredible things in Japan and won\'t have room on the way back.',
        ),
      ),
      MustKnowTip(
        emoji: '🧂',
        text: LText(
          'Yanına tuzlu atıştırmalıklar al, yolda ihtiyacın olacak — uzun uçuşta '
          've yoğun yürüyüş günlerinde tuz/elektrolit dengeni korur.',
          'Pack some salty snacks, you will need them on the way — they help keep '
          'your salt/electrolyte balance on the long flight and heavy walking days.',
        ),
      ),
      MustKnowTip(
        emoji: '🗑️',
        text: LText(
          'Küçük bir çöp poşeti taşı: sokaklarda neredeyse hiç çöp kutusu yoktur, '
          'çöpünü otele ya da bir konbiniye kadar taşımak zorunda kalırsın — çok '
          'işine yarar.',
          'Carry a small trash bag: there are almost no bins on the streets, so '
          'you will have to carry your rubbish to your hotel or a convenience '
          'store — it is very handy.',
        ),
      ),
      MustKnowTip(
        emoji: '☂️',
        text: LText(
          'Katlanır bir şemsiye ve küçük bir el havlusu al: ani sağanaklar sık, '
          've birçok umumi tuvalette kağıt havlu ya da kurutucu bulunmaz.',
          'Bring a foldable umbrella and a small hand towel: sudden downpours are '
          'common, and many public toilets have no paper towels or dryer.',
        ),
      ),
    ],
  ),

  // -------------------------------------------------------------------------
  // 🙏 Görgü kuralları
  // -------------------------------------------------------------------------
  MustKnowSection(
    emoji: '🙏',
    title: LText('Görgü Kuralları', 'Etiquette'),
    tips: [
      MustKnowTip(
        emoji: '🚫',
        text: LText(
          'Japonya\'da BAHŞİŞ yoktur. Hesaba bahşiş ekleme, garsona/şoföre para '
          'bırakma — kibarsızlık ya da kafa karıştırıcı sayılır.',
          'There is NO tipping in Japan. Do not add a tip to the bill or leave '
          'money for the waiter/driver — it is seen as rude or confusing.',
        ),
      ),
      MustKnowTip(
        emoji: '🥿',
        text: LText(
          'Kapıda ayakkabını çıkarman gereken yerler var: evler, bazı '
          'restoranlar, tapınaklar ve ryokan\'lar. Çorabının temiz ve deliksiz '
          'olmasına dikkat et.',
          'You must take your shoes off at the entrance in some places: homes, '
          'some restaurants, temples and ryokan. Make sure your socks are clean '
          'and hole-free.',
        ),
      ),
      MustKnowTip(
        emoji: '♻️',
        text: LText(
          'Çöp ayrıştırması çok titizdir: yanabilen, yanmaz, PET şişe, kutu-cam '
          've kağıt ayrı toplanır. Konbini önündeki kutulara doğru bölüme at.',
          'Waste sorting is very strict: burnable, non-burnable, PET bottles, '
          'cans-glass and paper are separated. Use the correct slot in the bins '
          'outside convenience stores.',
        ),
      ),
      MustKnowTip(
        emoji: '🚶',
        text: LText(
          'Yürüyerek yemek yeme; sırada düzgün bekle. Yürüyen merdivende bir '
          'tarafta dur (Tokyo\'da sol, Osaka\'da sağ), diğer taraf yürüyenlere '
          'kalsın.',
          'Do not eat while walking; wait properly in line. On escalators stand '
          'on one side (left in Tokyo, right in Osaka) and leave the other side '
          'for people walking.',
        ),
      ),
      MustKnowTip(
        emoji: '🎌',
        text: LText(
          'Dövmen varsa dikkat: bazı onsen (kaplıca), sento ve havuzlar dövmeli '
          'misafiri almaz. Kapatıcı bant kullan ya da önceden "tattoo-friendly" '
          'bir tesis ara.',
          'If you have tattoos, be careful: some onsen (hot springs), sento and '
          'pools do not admit tattooed guests. Use a cover patch or find a '
          '"tattoo-friendly" facility in advance.',
        ),
      ),
    ],
  ),

  // -------------------------------------------------------------------------
  // 🗾 Faydalı notlar
  // -------------------------------------------------------------------------
  MustKnowSection(
    emoji: '🗾',
    title: LText('Faydalı Notlar', 'Handy Notes'),
    tips: [
      MustKnowTip(
        emoji: '🏪',
        text: LText(
          'Konbini (7-Eleven, Lawson, FamilyMart) hayat kurtarır ve çoğu 7/24 '
          'açıktır: yemek, ATM, tuvalet, bilet, wifi, kargo — neredeyse her şey '
          'orada.',
          'Convenience stores (7-Eleven, Lawson, FamilyMart) are lifesavers and '
          'most are open 24/7: food, ATM, toilets, tickets, wifi, parcels — '
          'almost everything is there.',
        ),
      ),
      MustKnowTip(
        emoji: '🚰',
        text: LText(
          'Musluk suyu güvenli ve içilebilir. Her köşede içecek otomatı '
          '(jidohanbaiki) var; sıcak-soğuk seçenekleriyle susuz kalmazsın.',
          'Tap water is safe to drink. There are vending machines '
          '(jidohanbaiki) on every corner with hot and cold options, so you '
          'won\'t go thirsty.',
        ),
      ),
      MustKnowTip(
        emoji: '🌏',
        text: LText(
          'Deprem olursa panik yapma: sağlam bir masanın altına gir, başını koru, '
          'sarsıntı bitince açık alana çık. Japonya binaları buna göre yapılır ve '
          'telefonlar erken uyarı verir.',
          'If there is an earthquake, don\'t panic: get under a sturdy table, '
          'protect your head, and move to open space once shaking stops. Japanese '
          'buildings are built for it and phones give early warnings.',
        ),
      ),
      MustKnowTip(
        emoji: '🗣️',
        text: LText(
          'Büyük şehirler dışında İngilizce sınırlıdır ve tabela/menülerin çoğu '
          'Japoncadır. Çeviri uygulaman hazır olsun; birkaç kelime Japonca (bkz. '
          'Pusula) her kapıyı açar.',
          'Outside the big cities English is limited and most signs/menus are in '
          'Japanese. Keep your translation app ready; a few words of Japanese '
          '(see the Compass) open every door.',
        ),
      ),
    ],
  ),
];
