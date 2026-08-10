// Rotori Eats — küratörlü Japon yemekleri listesi.
//
// Veri seçimi ilkesi: **bayatlamayan bilgi.** Bir yemeğin ne olduğu, neyden
// yapıldığı ve nasıl yendiği yıllarca değişmez. Fiyat bantları geniş tutuldu
// (kesin fiyat iddia edilmiyor), belirli mekan adı verilmiyor — `whereToFind`
// yalnızca "hangi tür yerde bulunur" tarifidir.
//
// Malzeme ihtimalleri bilinçli olarak temkinli: emin olunmayan malzeme
// `sometimes` işaretlenir, böylece kullanıcı "sor" uyarısı alır. Yanlış
// güven vermektense fazladan sordurmayı tercih ediyoruz.

import 'japanese_dishes.dart';
import 'localized_text.dart';

const List<JapaneseDish> kJapaneseDishes = [
  // === ERİŞTELER ===========================================================
  JapaneseDish(
    id: 'ramen',
    name: 'Ramen',
    nameJa: 'ラーメン',
    romaji: 'Rāmen',
    emoji: '🍜',
    category: DishCategory.noodles,
    summary: LText(
      'Buğday eriştesi + uzun süre kaynatılmış et suyu. Japonya\'nın en yaygın '
          'tek öğünü; bölgeden bölgeye baz suyu tamamen değişir.',
      'Wheat noodles in a long-simmered broth. Japan\'s most common single '
          'meal; the broth base changes completely from region to region.',
    ),
    priceMinJpy: 800,
    priceMaxJpy: 2000,
    ingredients: {
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.pork: IngredientChance.usually,
      DishIngredient.soy: IngredientChance.usually,
      DishIngredient.egg: IngredientChance.usually,
      DishIngredient.cookingAlcohol: IngredientChance.sometimes,
    },
    variants: [
      DishVariant(
        name: 'Tonkotsu',
        nameJa: '豚骨',
        note: LText(
          'Domuz kemiği suyu — beyaz ve yoğun. Fukuoka kökenli.',
          'Pork bone broth — white and rich. From Fukuoka.',
        ),
        ingredients: {DishIngredient.pork: IngredientChance.always},
      ),
      DishVariant(
        name: 'Shoyu',
        nameJa: '醤油',
        note: LText(
          'Soya sosu bazlı, berrak. Bazı yerlerde tavuk suyu kullanılır ama '
              'domuz da sık.',
          'Soy sauce based, clear. Some shops use chicken stock, but pork is '
              'also common.',
        ),
        ingredients: {DishIngredient.pork: IngredientChance.sometimes},
      ),
      DishVariant(
        name: 'Tori paitan',
        nameJa: '鶏白湯',
        note: LText(
          'Tavuk suyu bazlı, kremamsı. Helal ramen mekanlarının çoğu bunu '
              'yapar — ama kesim yine sorulmalı.',
          'Creamy chicken broth. Most halal ramen shops serve this — but you '
              'still need to ask about the slaughter.',
        ),
        ingredients: {
          DishIngredient.pork: IngredientChance.sometimes,
          DishIngredient.chicken: IngredientChance.always,
        },
      ),
      DishVariant(
        name: 'Vegan ramen',
        nameJa: 'ヴィーガンラーメン',
        note: LText(
          'Sebze/mantar suyu. Büyük şehirlerde bulunur; dashi kullanılmadığını '
              'teyit et.',
          'Vegetable/mushroom broth. Found in big cities; confirm no dashi is '
              'used.',
        ),
        ingredients: {
          DishIngredient.pork: IngredientChance.sometimes,
          DishIngredient.dashi: IngredientChance.sometimes,
        },
      ),
    ],
    howToEat: LText(
      'Sesli çekmek ayıp değil, normaldir — eriştenin aromasını açar ve '
          'soğutur. Kaseyi kaldırıp suyu içebilirsin. Erişte hamurlaşmadan, '
          '5–10 dakikada bitirilmesi beklenir; masada uzun oturulmaz.',
      'Slurping is normal, not rude — it aerates and cools the noodles. You '
          'may lift the bowl to drink the broth. Finish in 5–10 minutes before '
          'the noodles soften; nobody lingers at the counter.',
    ),
    watchOut: LText(
      'Domuz en çok SUDA saklanır, üstteki dilimde değil. "Chāshū nashi" '
          '(domuz dilimi yok) demek suyu değiştirmez — bazı yerde ayrıca '
          'domuz yağı (lard) da eklenir.',
      'Pork hides in the BROTH, not just the slice on top. Saying "chāshū '
          'nashi" (no pork slice) does not change the broth — some shops also '
          'add pork fat (lard).',
    ),
    orderTip: LText(
      'Çoğu yerde kapıda bilet makinesi var: parayı at, düğmeye bas, fişi '
          'tezgaha ver. Menü Japonca ise en soldaki üst düğme genelde ana '
          'ramendir.',
      'Most shops have a ticket machine at the door: insert cash, press a '
          'button, hand the ticket to the counter. If the menu is in Japanese, '
          'the top-left button is usually the house ramen.',
    ),
    whereToFind: LText(
      'Her istasyon çevresinde. Zincirler (Ichiran, Ippudo) İngilizce menüye '
          'sahiptir ama tonkotsu ağırlıklıdır.',
      'Around every station. Chains (Ichiran, Ippudo) have English menus but '
          'lean tonkotsu.',
    ),
    veganVersionExists: true,
  ),

  JapaneseDish(
    id: 'udon',
    name: 'Udon',
    nameJa: 'うどん',
    romaji: 'Udon',
    emoji: '🍲',
    category: DishCategory.noodles,
    summary: LText(
      'Kalın, yumuşak buğday eriştesi. Hafif dashi suyunda sıcak ya da soğuk '
          'sosla yenir. Rameneden çok daha sade ve ucuz.',
      'Thick, soft wheat noodles in a light dashi broth, hot or with a cold '
          'dipping sauce. Much plainer and cheaper than ramen.',
    ),
    priceMinJpy: 400,
    priceMaxJpy: 1200,
    ingredients: {
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.dashi: IngredientChance.always,
      DishIngredient.soy: IngredientChance.usually,
      DishIngredient.cookingAlcohol: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Sesli çekilir. Ayaküstü udon dükkanlarında (tachigui) ayakta yenir, '
          '5 dakikada biter ve genelde en ucuz sıcak öğündür.',
      'Slurped. At stand-and-eat udon shops (tachigui) you eat standing, in '
          'five minutes — usually the cheapest hot meal available.',
    ),
    watchOut: LText(
      'Etsiz göründüğü için vejetaryen sanılır ama suyu neredeyse her zaman '
          'dashi\'dir, yani balık. Kake udon bile vejetaryen değildir.',
      'Looks meat-free so people assume it is vegetarian, but the broth is '
          'almost always dashi — fish. Even plain kake udon is not vegetarian.',
    ),
    orderTip: LText(
      '"Kake udon" en sade hâli. Üzerine tempura seçebilirsin; tepsiyle '
          'ilerleyip kasada ödersin.',
      '"Kake udon" is the plainest version. You can add tempura on top; you '
          'move along with a tray and pay at the register.',
    ),
    whereToFind: LText(
      'İstasyon peronlarında ayaküstü dükkanlar, alışveriş merkezi katları.',
      'Stand-up shops on station platforms, mall food floors.',
    ),
  ),

  JapaneseDish(
    id: 'soba',
    name: 'Soba',
    nameJa: 'そば',
    romaji: 'Soba',
    emoji: '🥢',
    category: DishCategory.noodles,
    summary: LText(
      'Karabuğday eriştesi. Soğuk (mori/zaru) servis edilip sosa batırılarak '
          'ya da sıcak suda yenir. Daha "yetişkin" ve sade bir lezzet.',
      'Buckwheat noodles. Served cold (mori/zaru) to dip in sauce, or hot in '
          'broth. A plainer, more grown-up flavour.',
    ),
    priceMinJpy: 500,
    priceMaxJpy: 2000,
    ingredients: {
      DishIngredient.gluten: IngredientChance.usually,
      DishIngredient.dashi: IngredientChance.always,
      DishIngredient.soy: IngredientChance.always,
      DishIngredient.cookingAlcohol: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Soğuk sobayı azar azar sosa batır, hepsini birden daldırma. Sonunda '
          'erişte suyu (sobayu) getirilir; kalan sosa katıp çorba gibi içilir.',
      'Dip cold soba a little at a time, never the whole bundle. At the end '
          'they bring the noodle water (sobayu); pour it into the leftover '
          'sauce and drink it like soup.',
    ),
    watchOut: LText(
      '"Karabuğday" glutensiz sanılır ama Japon sobasının çoğu buğdayla '
          'karışıktır. Saf olanı "juwari soba" (十割) diye aranır.',
      'Buckwheat sounds gluten-free, but most Japanese soba is cut with wheat. '
          'The pure kind is called "juwari soba" (十割).',
    ),
    whereToFind: LText(
      'Eski mahallelerde bağımsız dükkanlar; istasyonlarda ayaküstü şubeler.',
      'Independent shops in older neighbourhoods; stand-up branches in stations.',
    ),
  ),

  // === PİRİNÇ KASELERİ =====================================================
  JapaneseDish(
    id: 'gyudon',
    name: 'Gyudon',
    nameJa: '牛丼',
    romaji: 'Gyūdon',
    emoji: '🍚',
    category: DishCategory.rice,
    summary: LText(
      'İnce dilimlenmiş sığır eti ve soğanın tatlı soya sosunda pişip pirinç '
          'üstüne konması. Japonya\'nın en hızlı ve en ucuz sıcak öğünü.',
      'Thin-sliced beef and onion simmered in sweet soy sauce over rice. '
          'Japan\'s fastest and cheapest hot meal.',
    ),
    priceMinJpy: 400,
    priceMaxJpy: 900,
    ingredients: {
      DishIngredient.beef: IngredientChance.always,
      DishIngredient.soy: IngredientChance.always,
      DishIngredient.cookingAlcohol: IngredientChance.usually,
      DishIngredient.dashi: IngredientChance.usually,
      DishIngredient.gluten: IngredientChance.usually,
    },
    howToEat: LText(
      'Bilet makinesinden al, 2 dakikada gelir, 10 dakikada çıkılır. Masadaki '
          'kırmızı biber (shichimi) ve zencefil turşusu (beni shoga) ücretsiz.',
      'Buy from the ticket machine, it arrives in two minutes, you leave in '
          'ten. The red pepper (shichimi) and pickled ginger (beni shoga) on '
          'the table are free.',
    ),
    orderTip: LText(
      'Porsiyon adları: nami (normal) < ō-mori (büyük) < tokumori (ekstra).',
      'Portion names: nami (regular) < ō-mori (large) < tokumori (extra).',
    ),
    whereToFind: LText(
      'Yoshinoya, Sukiya, Matsuya zincirleri — 24 saat açık, her istasyonda.',
      'Yoshinoya, Sukiya, Matsuya chains — open 24h, at every station.',
    ),
  ),

  JapaneseDish(
    id: 'katsudon',
    name: 'Katsudon',
    nameJa: 'カツ丼',
    romaji: 'Katsudon',
    emoji: '🍛',
    category: DishCategory.rice,
    summary: LText(
      'Panelenmiş domuz pirzolasının yumurta ve soğanla birlikte pişirilip '
          'pirinç üstüne konması. Doyurucu ve ağır.',
      'Breaded pork cutlet simmered with egg and onion over rice. Filling and '
          'heavy.',
    ),
    priceMinJpy: 700,
    priceMaxJpy: 1500,
    ingredients: {
      DishIngredient.pork: IngredientChance.always,
      DishIngredient.egg: IngredientChance.always,
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.dashi: IngredientChance.always,
      DishIngredient.soy: IngredientChance.always,
      DishIngredient.cookingAlcohol: IngredientChance.usually,
    },
    variants: [
      DishVariant(
        name: 'Oyakodon',
        nameJa: '親子丼',
        note: LText(
          'Aynı yemeğin tavuklu hâli — "anne ve çocuk" (tavuk + yumurta).',
          'The chicken version — "parent and child" (chicken + egg).',
        ),
        ingredients: {
          DishIngredient.pork: IngredientChance.sometimes,
          DishIngredient.chicken: IngredientChance.always,
        },
      ),
    ],
    howToEat: LText(
      'Kaşıkla değil, çubukla yenir; kaseyi ağzına yaklaştırmak normaldir.',
      'Eaten with chopsticks, not a spoon; bringing the bowl close to your '
          'mouth is normal.',
    ),
    whereToFind: LText(
      'Teishoku (set menü) lokantaları, istasyon restoran katları.',
      'Teishoku (set meal) diners, station restaurant floors.',
    ),
  ),

  JapaneseDish(
    id: 'curry-rice',
    name: 'Japon körisi',
    nameJa: 'カレーライス',
    romaji: 'Karē raisu',
    emoji: '🍛',
    category: DishCategory.rice,
    summary: LText(
      'Hint körisinden çok farklı: koyu, tatlımsı, neredeyse sos kıvamında. '
          'Japonya\'nın "ev yemeği" sayılır.',
      'Very different from Indian curry: dark, slightly sweet, almost gravy-'
          'like. Considered Japanese comfort food.',
    ),
    priceMinJpy: 600,
    priceMaxJpy: 1600,
    ingredients: {
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.beef: IngredientChance.sometimes,
      DishIngredient.pork: IngredientChance.sometimes,
      DishIngredient.chicken: IngredientChance.sometimes,
      DishIngredient.dairy: IngredientChance.sometimes,
      DishIngredient.soy: IngredientChance.usually,
    },
    variants: [
      DishVariant(
        name: 'Vejetaryen köri',
        nameJa: 'ベジタリアンカレー',
        note: LText(
          'Bazı zincirler ayrı kazanda sebze körisi yapar; sosun eti '
              'içermediğini teyit et.',
          'Some chains make a separate vegetable curry; confirm the sauce '
              'itself is meat-free.',
        ),
        ingredients: {
          DishIngredient.beef: IngredientChance.sometimes,
          DishIngredient.pork: IngredientChance.sometimes,
          DishIngredient.chicken: IngredientChance.sometimes,
        },
      ),
    ],
    howToEat: LText(
      'Kaşıkla yenir — çubuk kullanılmayan nadir Japon yemeklerinden. Acılık '
          've pirinç miktarı çoğu yerde seçilebilir.',
      'Eaten with a spoon — one of the few Japanese dishes that skips '
          'chopsticks. Spice level and rice amount are usually adjustable.',
    ),
    watchOut: LText(
      'Köri sosunun kendisinde et suyu ve bazen süt tozu vardır; üstünde et '
          'olmaması sosun etsiz olduğu anlamına gelmez.',
      'The curry roux itself often contains meat stock and sometimes milk '
          'powder; no meat on top does not mean the sauce is meat-free.',
    ),
    whereToFind: LText(
      'CoCo Ichibanya zinciri her yerde ve acılık/porsiyon seçtirir.',
      'The CoCo Ichibanya chain is everywhere and lets you pick spice and size.',
    ),
    veganVersionExists: true,
  ),

  JapaneseDish(
    id: 'onigiri',
    name: 'Onigiri',
    nameJa: 'おにぎり',
    romaji: 'Onigiri',
    emoji: '🍙',
    category: DishCategory.breakfast,
    summary: LText(
      'Üçgen pirinç topu, ortasında bir dolgu, dışında yosun. Konbini\'nin '
          'temel taşı; ¥150 civarı ve her yerde.',
      'A triangular rice ball with a filling inside and seaweed outside. The '
          'cornerstone of konbini food; around ¥150 and everywhere.',
    ),
    priceMinJpy: 130,
    priceMaxJpy: 350,
    ingredients: {
      DishIngredient.fish: IngredientChance.sometimes,
      DishIngredient.soy: IngredientChance.sometimes,
      DishIngredient.dashi: IngredientChance.sometimes,
    },
    variants: [
      DishVariant(
        name: 'Ume (erik turşusu)',
        nameJa: '梅',
        note: LText(
          'Tuzlu erik. Bitkisel ve en güvenli seçeneklerden.',
          'Salted plum. Plant-based and one of the safest choices.',
        ),
        ingredients: {
          DishIngredient.fish: IngredientChance.sometimes,
          DishIngredient.dashi: IngredientChance.sometimes,
        },
      ),
      DishVariant(
        name: 'Kombu (yosun)',
        nameJa: '昆布',
        note: LText(
          'Tatlı soya sosunda pişmiş yosun. Genelde bitkisel.',
          'Kelp simmered in sweet soy. Usually plant-based.',
        ),
        ingredients: {
          DishIngredient.fish: IngredientChance.sometimes,
          DishIngredient.dashi: IngredientChance.sometimes,
        },
      ),
      DishVariant(
        name: 'Tuna mayo',
        nameJa: 'ツナマヨ',
        note: LText(
          'En popüler dolgu ama balık + yumurtalı mayonez içerir.',
          'The most popular filling, but it has fish plus egg-based mayo.',
        ),
        ingredients: {
          DishIngredient.fish: IngredientChance.always,
          DishIngredient.egg: IngredientChance.always,
        },
      ),
    ],
    howToEat: LText(
      'Paketteki 1-2-3 numaralı şeritleri sırayla çek; yosun böylece pirinçle '
          'buluşur ve çıtır kalır. Konbini önünde ayaküstü yemek normaldir.',
      'Pull the numbered 1-2-3 tabs in order; that keeps the seaweed crisp '
          'until it meets the rice. Eating standing outside the konbini is fine.',
    ),
    orderTip: LText(
      'Dolgu adı paketin üstünde Japonca yazar. Emin değilsen ume (梅) ya da '
          'kombu (昆布) en güvenli iki seçenektir.',
      'The filling is written in Japanese on top. When unsure, ume (梅) or '
          'kombu (昆布) are the two safest picks.',
    ),
    whereToFind: LText(
      '7-Eleven, FamilyMart, Lawson — 24 saat, her köşede.',
      '7-Eleven, FamilyMart, Lawson — 24h, on every corner.',
    ),
    veganVersionExists: true,
  ),

  // === ÇİĞ / SUŞİ ==========================================================
  JapaneseDish(
    id: 'sushi',
    name: 'Suşi',
    nameJa: '寿司',
    romaji: 'Sushi',
    emoji: '🍣',
    category: DishCategory.raw,
    summary: LText(
      'Sirkelenmiş pirinç + üzerine malzeme. Dönen bant (kaiten) mekanlarında '
          'ucuz ve stressiz; tezgah suşisi ayrı bir dünya ve fiyat.',
      'Vinegared rice with a topping. Cheap and stress-free at conveyor-belt '
          '(kaiten) places; counter sushi is a different world and price.',
    ),
    priceMinJpy: 1000,
    priceMaxJpy: 8000,
    ingredients: {
      DishIngredient.fish: IngredientChance.usually,
      DishIngredient.soy: IngredientChance.always,
      DishIngredient.shellfish: IngredientChance.sometimes,
      DishIngredient.egg: IngredientChance.sometimes,
      DishIngredient.cookingAlcohol: IngredientChance.sometimes,
    },
    variants: [
      DishVariant(
        name: 'Inari',
        nameJa: 'いなり',
        note: LText(
          'Tatlı tofu kesesinde pirinç. Tamamen bitkisel — vejetaryenler için '
              'en güvenli suşi.',
          'Rice in a sweet tofu pouch. Fully plant-based — the safest sushi '
              'for vegetarians.',
        ),
        ingredients: {
          DishIngredient.fish: IngredientChance.sometimes,
          DishIngredient.soy: IngredientChance.always,
        },
      ),
      DishVariant(
        name: 'Kappa maki (salatalık)',
        nameJa: 'かっぱ巻き',
        note: LText(
          'Salatalıklı ince rulo. Bitkisel; pirinç sirkesinde dashi olup '
              'olmadığını sorabilirsin.',
          'Thin cucumber roll. Plant-based; you can ask whether the rice '
              'vinegar contains dashi.',
        ),
        ingredients: {
          DishIngredient.fish: IngredientChance.sometimes,
          DishIngredient.soy: IngredientChance.always,
        },
      ),
      DishVariant(
        name: 'Tamago',
        nameJa: '玉子',
        note: LText(
          'Tatlı omlet dilimi. Vejetaryen ama vegan değil; içinde dashi '
              'bulunabilir.',
          'Sweet omelette slice. Vegetarian but not vegan; may contain dashi.',
        ),
        ingredients: {
          DishIngredient.fish: IngredientChance.sometimes,
          DishIngredient.egg: IngredientChance.always,
          DishIngredient.dashi: IngredientChance.usually,
        },
      ),
    ],
    howToEat: LText(
      'Soya sosunu PİRİNCE değil, malzemeye değdir — pirinç sosu emip dağılır. '
          'Elle yemek serbesttir. Zencefil turşusu tatlar arasında damak '
          'temizlemek içindir, suşinin üstüne konmaz.',
      'Dip the TOPPING in soy sauce, not the rice — rice soaks it up and falls '
          'apart. Eating with your hands is fine. The pickled ginger is a '
          'palate cleanser between pieces, not a topping.',
    ),
    orderTip: LText(
      'Kaiten mekanlarında tabak rengi fiyatı gösterir; dokunmatik ekranı '
          'İngilizceye çevirebilirsin. Hesap tabak sayımıyla çıkar.',
      'At kaiten places the plate colour is the price; you can switch the '
          'touchscreen to English. The bill is counted by plates.',
    ),
    whereToFind: LText(
      'Kaiten zincirleri (Sushiro, Kura, Uobei) ucuz ve çocuk dostu.',
      'Kaiten chains (Sushiro, Kura, Uobei) are cheap and kid-friendly.',
    ),
    veganVersionExists: true,
  ),

  JapaneseDish(
    id: 'sashimi',
    name: 'Sashimi',
    nameJa: '刺身',
    romaji: 'Sashimi',
    emoji: '🐟',
    category: DishCategory.raw,
    summary: LText(
      'Pirinçsiz, sadece çiğ balık dilimleri. Tazelik dışında hiçbir şeyin '
          'arkasına saklanmadığı için kalite doğrudan anlaşılır.',
      'Just slices of raw fish, no rice. With nothing to hide behind, quality '
          'is immediately obvious.',
    ),
    priceMinJpy: 800,
    priceMaxJpy: 5000,
    ingredients: {
      DishIngredient.fish: IngredientChance.always,
      DishIngredient.soy: IngredientChance.always,
    },
    howToEat: LText(
      'Wasabi\'yi soya sosuna karıştırmak yerine balığın üstüne azıcık koymak '
          'daha makbul. Altındaki beyaz turp rendesi süs değil, yenir.',
      'Placing a little wasabi on the fish is better form than stirring it '
          'into the soy sauce. The shredded white radish underneath is food, '
          'not decoration.',
    ),
    whereToFind: LText(
      'Balık halleri (Tsukiji dış çarşı), izakaya\'lar, süpermarketlerin '
          'akşam indirimli reyonları.',
      'Fish markets (Tsukiji outer market), izakaya, and supermarket evening '
          'discount shelves.',
    ),
  ),

  // === IZGARA ==============================================================
  JapaneseDish(
    id: 'yakitori',
    name: 'Yakitori',
    nameJa: '焼き鳥',
    romaji: 'Yakitori',
    emoji: '🍢',
    category: DishCategory.grilled,
    summary: LText(
      'Kömürde pişen tavuk şişleri. Tuzlu (shio) ya da tatlı soslu (tare) '
          'seçilir. Akşamüstü içki eşliğinde yenen tipik atıştırmalık.',
      'Chicken skewers over charcoal, ordered salted (shio) or with sweet '
          'sauce (tare). The classic early-evening snack alongside a drink.',
    ),
    priceMinJpy: 150,
    priceMaxJpy: 400,
    ingredients: {
      DishIngredient.chicken: IngredientChance.always,
      DishIngredient.soy: IngredientChance.usually,
      DishIngredient.cookingAlcohol: IngredientChance.usually,
    },
    howToEat: LText(
      'Şiş başına sipariş edilir, 2–3 tanesi bir öğün değildir. Şişten '
          'çıkarmadan doğrudan ısırılır.',
      'Ordered per skewer; two or three is a snack, not a meal. Bite straight '
          'off the skewer rather than pulling the pieces off.',
    ),
    watchOut: LText(
      'Tare sosu genelde mirin ve sake içerir. Alkolden tamamen kaçınıyorsan '
          '"shio" (tuzlu) iste.',
      'The tare sauce usually contains mirin and sake. If you avoid alcohol '
          'entirely, ask for "shio" (salt) instead.',
    ),
    orderTip: LText(
      'Şiş adları: momo (but), negima (but+pırasa), kawa (deri), tsukune '
          '(köfte, yumurta içerebilir).',
      'Skewer names: momo (thigh), negima (thigh + leek), kawa (skin), tsukune '
          '(meatball, may contain egg).',
    ),
    whereToFind: LText(
      'İstasyon altı sokaklar, izakaya\'lar, yokocho denen dar ara sokaklar.',
      'Streets under station tracks, izakaya, and the narrow alleys called '
          'yokocho.',
    ),
  ),

  JapaneseDish(
    id: 'yakiniku',
    name: 'Yakiniku',
    nameJa: '焼肉',
    romaji: 'Yakiniku',
    emoji: '🥩',
    category: DishCategory.grilled,
    summary: LText(
      'Masadaki ızgarada eti kendin pişirirsin. Sığır ağırlıklı; özel gün '
          'yemeği sayılır ve fiyatı hızla yükselir.',
      'You grill the meat yourself on a griddle set into the table. Mostly '
          'beef; treated as a special-occasion meal and the bill climbs fast.',
    ),
    priceMinJpy: 2500,
    priceMaxJpy: 10000,
    ingredients: {
      DishIngredient.beef: IngredientChance.usually,
      DishIngredient.pork: IngredientChance.sometimes,
      DishIngredient.soy: IngredientChance.usually,
      DishIngredient.cookingAlcohol: IngredientChance.sometimes,
      DishIngredient.sesame: IngredientChance.usually,
    },
    howToEat: LText(
      'Az miktarda koy, sık çevir; ızgara küçük ve hızlı. Çiğ eti tuttuğun '
          'maşayla yemek yenmez — ayrı çubuk kullanılır.',
      'Add a little at a time and turn often; the grill is small and fast. '
          'Never eat with the tongs you handled raw meat with — use separate '
          'chopsticks.',
    ),
    whereToFind: LText(
      'Her şehirde; helal yakiniku Tokyo ve Osaka\'da bulunur ama azdır ve '
          'rezervasyon ister.',
      'In every city; halal yakiniku exists in Tokyo and Osaka but is rare and '
          'usually needs a reservation.',
    ),
  ),

  JapaneseDish(
    id: 'okonomiyaki',
    name: 'Okonomiyaki',
    nameJa: 'お好み焼き',
    romaji: 'Okonomiyaki',
    emoji: '🥞',
    category: DishCategory.grilled,
    summary: LText(
      'Lahana ve hamurun sacda pişirilmesi — "istediğin gibi kızart" demek. '
          'Osaka ve Hiroşima usulleri tamamen farklıdır.',
      'Cabbage and batter cooked on a hotplate — the name means "grill it how '
          'you like". The Osaka and Hiroshima styles are completely different.',
    ),
    priceMinJpy: 700,
    priceMaxJpy: 1800,
    ingredients: {
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.egg: IngredientChance.always,
      DishIngredient.dashi: IngredientChance.usually,
      DishIngredient.fish: IngredientChance.usually,
      DishIngredient.pork: IngredientChance.usually,
      DishIngredient.soy: IngredientChance.usually,
    },
    howToEat: LText(
      'Bazı mekanlarda sacda kendin pişirirsin, bazılarında pişmiş gelir. '
          'Küçük spatulayla kesip doğrudan sactan yemek normaldir.',
      'At some places you cook it yourself on the hotplate, at others it '
          'arrives done. Cutting it with the small spatula and eating straight '
          'off the plate is normal.',
    ),
    watchOut: LText(
      'Üstündeki oynayan pullar katsuobushi — kurutulmuş balık. Sos da genelde '
          'balık/istiridye içerir. Sebzeli sipariş etsen bile vejetaryen olmaz; '
          '"katsuobushi nashi, sōsu nashi" demen gerekir.',
      'Those dancing flakes on top are katsuobushi — dried fish. The sauce '
          'usually contains fish or oyster too. Even a veggie order is not '
          'vegetarian unless you say "katsuobushi nashi, sōsu nashi".',
    ),
    whereToFind: LText(
      'Osaka her yerde; Tokyo\'da da yaygın. Hiroşima usulü noodle katmanlıdır.',
      'Everywhere in Osaka and common in Tokyo. The Hiroshima style adds a '
          'noodle layer.',
    ),
  ),

  // === KIZARTMA ============================================================
  JapaneseDish(
    id: 'tempura',
    name: 'Tempura',
    nameJa: '天ぷら',
    romaji: 'Tenpura',
    emoji: '🍤',
    category: DishCategory.fried,
    summary: LText(
      'İnce, hafif hamurda kızartılmış deniz ürünü ve sebze. İyi yapılanı '
          'yağlı değil, cam gibi çıtırdır.',
      'Seafood and vegetables in a thin, light batter. Done well it is not '
          'greasy but glassy and crisp.',
    ),
    priceMinJpy: 800,
    priceMaxJpy: 6000,
    ingredients: {
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.egg: IngredientChance.usually,
      DishIngredient.shellfish: IngredientChance.usually,
      DishIngredient.dashi: IngredientChance.usually,
      DishIngredient.soy: IngredientChance.usually,
    },
    variants: [
      DishVariant(
        name: 'Yasai tempura (sebze)',
        nameJa: '野菜天ぷら',
        note: LText(
          'Sadece sebze. Aynı yağda karides kızartıldığını unutma; hassassan '
              'ayrı yağ sor.',
          'Vegetables only. Remember shrimp is fried in the same oil; if you '
              'are strict, ask about separate oil.',
        ),
        ingredients: {DishIngredient.shellfish: IngredientChance.sometimes},
      ),
    ],
    howToEat: LText(
      'Tuzla ya da tentsuyu sosuna batırarak; sos dashi bazlıdır. Sıcakken '
          'yenir, beklerse çıtırlığı gider.',
      'With salt or dipped in tentsuyu sauce, which is dashi-based. Eat it hot '
          '— it loses its crunch quickly.',
    ),
    whereToFind: LText(
      'Bağımsız tempura lokantaları, udon dükkanlarında üstüne eklenir.',
      'Dedicated tempura restaurants, or as a topping at udon shops.',
    ),
  ),

  JapaneseDish(
    id: 'karaage',
    name: 'Karaage',
    nameJa: '唐揚げ',
    romaji: 'Karaage',
    emoji: '🍗',
    category: DishCategory.fried,
    summary: LText(
      'Soya, zencefil ve sarımsakla terbiye edilip nişastayla kızartılmış '
          'tavuk. Konbini\'den izakaya\'ya kadar her yerde.',
      'Chicken marinated in soy, ginger and garlic, then fried in starch. '
          'Everywhere from konbini counters to izakaya.',
    ),
    priceMinJpy: 250,
    priceMaxJpy: 900,
    ingredients: {
      DishIngredient.chicken: IngredientChance.always,
      DishIngredient.soy: IngredientChance.always,
      DishIngredient.gluten: IngredientChance.usually,
      DishIngredient.cookingAlcohol: IngredientChance.usually,
      DishIngredient.egg: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Limon sıkılır. Konbini kasasının yanındaki sıcak reyondan tek parça '
          'alıp yürürken yemek yaygındır.',
      'Squeeze the lemon over it. Grabbing a piece from the hot case next to '
          'the konbini register is common.',
    ),
    whereToFind: LText(
      'Konbini sıcak reyonu, izakaya menüsü, teishoku setleri.',
      'Konbini hot cases, izakaya menus, teishoku sets.',
    ),
  ),

  JapaneseDish(
    id: 'tonkatsu',
    name: 'Tonkatsu',
    nameJa: 'とんかつ',
    romaji: 'Tonkatsu',
    emoji: '🍖',
    category: DishCategory.fried,
    summary: LText(
      'Panko ekmek kırıntısıyla kaplanıp kızartılmış domuz pirzolası. Lahana, '
          'pirinç ve miso çorbasıyla set hâlinde gelir.',
      'Pork cutlet coated in panko crumbs and deep-fried. Comes as a set with '
          'shredded cabbage, rice and miso soup.',
    ),
    priceMinJpy: 1000,
    priceMaxJpy: 3000,
    ingredients: {
      DishIngredient.pork: IngredientChance.always,
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.egg: IngredientChance.always,
      DishIngredient.soy: IngredientChance.usually,
    },
    variants: [
      DishVariant(
        name: 'Gyukatsu (dana)',
        nameJa: '牛カツ',
        note: LText(
          'Domuz yerine dana; masadaki sıcak taşta kendin pişirirsin.',
          'Beef instead of pork; you finish it yourself on a hot stone at the '
              'table.',
        ),
        ingredients: {
          DishIngredient.pork: IngredientChance.sometimes,
          DishIngredient.beef: IngredientChance.always,
        },
      ),
    ],
    howToEat: LText(
      'Yanındaki lahana ücretsiz tazelenir. Susamı havanda ezip sosu üstüne '
          'dökmek servisin parçasıdır.',
      'The shredded cabbage is refilled free. Grinding the sesame and pouring '
          'the sauce over it is part of the ritual.',
    ),
    whereToFind: LText(
      'Bağımsız katsu lokantaları ve zincirler; her alışveriş merkezinde var.',
      'Dedicated katsu restaurants and chains; in every shopping centre.',
    ),
  ),

  // === TENCERE =============================================================
  JapaneseDish(
    id: 'shabu-shabu',
    name: 'Shabu-shabu',
    nameJa: 'しゃぶしゃぶ',
    romaji: 'Shabu-shabu',
    emoji: '🍲',
    category: DishCategory.hotpot,
    summary: LText(
      'Kaynayan suda ince et dilimlerini birkaç saniye sallayıp sosa batırma. '
          'Adı, etin suda çıkardığı sesten gelir.',
      'Swishing thin slices of meat in boiling broth for a few seconds, then '
          'dipping them in sauce. The name is the sound the meat makes.',
    ),
    priceMinJpy: 2500,
    priceMaxJpy: 8000,
    ingredients: {
      DishIngredient.beef: IngredientChance.usually,
      DishIngredient.pork: IngredientChance.sometimes,
      DishIngredient.dashi: IngredientChance.usually,
      DishIngredient.soy: IngredientChance.usually,
      DishIngredient.sesame: IngredientChance.usually,
      DishIngredient.egg: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Eti 3–5 saniyeden fazla tutma, sertleşir. Sonunda kalan suya pirinç ya '
          'da erişte atıp çorba yapmak (shime) geleneğin parçası.',
      'Do not leave the meat in more than 3–5 seconds or it toughens. At the '
          'end, adding rice or noodles to the leftover broth (shime) is part '
          'of the tradition.',
    ),
    whereToFind: LText(
      'Zincir tabemahodai (sınırsız) mekanları uygun fiyatlıdır.',
      'All-you-can-eat (tabehōdai) chains are the affordable option.',
    ),
  ),

  JapaneseDish(
    id: 'miso-soup',
    name: 'Miso çorbası',
    nameJa: '味噌汁',
    romaji: 'Misoshiru',
    emoji: '🥣',
    category: DishCategory.breakfast,
    summary: LText(
      'Fermente soya ezmesi + dashi. Her öğünün yanında gelir; ayrı sipariş '
          'edilmez, setin parçasıdır.',
      'Fermented soybean paste in dashi. Comes alongside almost every meal; '
          'you rarely order it separately.',
    ),
    priceMinJpy: 0,
    priceMaxJpy: 300,
    ingredients: {
      DishIngredient.dashi: IngredientChance.always,
      DishIngredient.soy: IngredientChance.always,
      DishIngredient.fish: IngredientChance.usually,
    },
    howToEat: LText(
      'Kaşık verilmez. Kaseyi kaldırıp içilir, katıları çubukla alınır.',
      'No spoon is given. Lift the bowl and drink it, picking up the solids '
          'with chopsticks.',
    ),
    watchOut: LText(
      'Japonya\'nın en yaygın vejetaryen tuzağı. "Sebze çorbası" gibi görünür '
          'ama neredeyse her zaman balık suyu (dashi) ile yapılır.',
      'Japan\'s most common vegetarian trap. It looks like a vegetable soup '
          'but is almost always made with fish stock (dashi).',
    ),
    whereToFind: LText(
      'Her teishoku setinde; konbini\'de anlık toz paketleri.',
      'In every teishoku set; instant sachets at konbini.',
    ),
  ),

  // === SOKAK ===============================================================
  JapaneseDish(
    id: 'takoyaki',
    name: 'Takoyaki',
    nameJa: 'たこ焼き',
    romaji: 'Takoyaki',
    emoji: '🐙',
    category: DishCategory.street,
    summary: LText(
      'İçinde ahtapot parçası olan, dışı çıtır içi akışkan hamur topları. '
          'Osaka\'nın simgesi.',
      'Batter balls with a piece of octopus inside — crisp outside, molten '
          'inside. The symbol of Osaka.',
    ),
    priceMinJpy: 400,
    priceMaxJpy: 800,
    ingredients: {
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.shellfish: IngredientChance.always,
      DishIngredient.egg: IngredientChance.usually,
      DishIngredient.dashi: IngredientChance.usually,
      DishIngredient.fish: IngredientChance.usually,
      DishIngredient.soy: IngredientChance.usually,
    },
    howToEat: LText(
      'İçi CİDDEN çok sıcaktır — ilkini bir dakika bekle, yoksa damağını '
          'yakarsın. Kürdanla yenir, genelde tezgahın önünde ayaküstü.',
      'The inside is genuinely scalding — wait a minute before the first one. '
          'Eaten with a toothpick, usually standing at the stall.',
    ),
    whereToFind: LText(
      'Dotonbori ve festival tezgahları; Osaka\'da her köşe.',
      'Dotonbori and festival stalls; every corner in Osaka.',
    ),
  ),

  JapaneseDish(
    id: 'gyoza',
    name: 'Gyoza',
    nameJa: '餃子',
    romaji: 'Gyōza',
    emoji: '🥟',
    category: DishCategory.street,
    summary: LText(
      'Bir yüzü çıtır kızartılmış, diğer yanı buharda pişmiş mantı. Ramen\'in '
          'yanında ısmarlanır.',
      'Dumplings fried crisp on one side and steamed on the other. Usually '
          'ordered alongside ramen.',
    ),
    priceMinJpy: 300,
    priceMaxJpy: 700,
    ingredients: {
      DishIngredient.pork: IngredientChance.usually,
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.soy: IngredientChance.always,
      DishIngredient.sesame: IngredientChance.usually,
      DishIngredient.cookingAlcohol: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Soya + sirke + acı susam yağı karıştırılıp batırılır. Tek lokmada '
          'yenmesi beklenir.',
      'Mix soy, vinegar and chilli sesame oil to dip. Meant to be eaten in one '
          'bite.',
    ),
    watchOut: LText(
      'Standart iç harç domuzdur. "Yasai gyoza" (sebzeli) bazı yerlerde var '
          'ama aynı tavada pişer.',
      'The standard filling is pork. "Yasai gyoza" (vegetable) exists in some '
          'places but is cooked in the same pan.',
    ),
    whereToFind: LText(
      'Ramen dükkanları, Çin lokantaları, konbini dondurulmuş reyonu.',
      'Ramen shops, Chinese diners, konbini freezer aisles.',
    ),
  ),

  // === TATLI ===============================================================
  JapaneseDish(
    id: 'taiyaki',
    name: 'Taiyaki',
    nameJa: 'たい焼き',
    romaji: 'Taiyaki',
    emoji: '🐟',
    category: DishCategory.sweets,
    summary: LText(
      'Balık şeklinde waffle hamuru, içinde tatlı fasulye ezmesi. Balık '
          'içermez — sadece kalıbı balık şeklindedir.',
      'Fish-shaped waffle batter filled with sweet bean paste. It contains no '
          'fish — only the mould is fish-shaped.',
    ),
    priceMinJpy: 150,
    priceMaxJpy: 400,
    ingredients: {
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.egg: IngredientChance.usually,
      DishIngredient.dairy: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Sıcak yenir, kuyruğundan başlanır. Yürürken yemek yerine tezgah '
          'önünde bitirmek daha uygun.',
      'Eaten hot, starting from the tail. Better to finish it at the stall '
          'than to eat while walking.',
    ),
    whereToFind: LText(
      'Tapınak yolları, festival tezgahları, istasyon çıkışları.',
      'Temple approaches, festival stalls, station exits.',
    ),
  ),

  JapaneseDish(
    id: 'matcha-sweets',
    name: 'Matcha tatlıları',
    nameJa: '抹茶スイーツ',
    romaji: 'Matcha suītsu',
    emoji: '🍵',
    category: DishCategory.sweets,
    summary: LText(
      'Toz yeşil çayla yapılan dondurma, parfait ve kek. Kyoto\'da (özellikle '
          'Uji) en iyisi bulunur; acımsı ve yoğun.',
      'Ice cream, parfait and cake made with powdered green tea. Kyoto — Uji '
          'especially — has the best; bitter and intense.',
    ),
    priceMinJpy: 400,
    priceMaxJpy: 1500,
    ingredients: {
      DishIngredient.dairy: IngredientChance.usually,
      DishIngredient.egg: IngredientChance.sometimes,
      DishIngredient.gluten: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Yoğunluk dereceleri vardır; en koyusu yetişkin damağına göredir. '
          'Yanında gelen tatlı fasulye acılığı dengeler.',
      'They come in intensity grades; the darkest is an acquired taste. The '
          'sweet bean served alongside balances the bitterness.',
    ),
    whereToFind: LText(
      'Kyoto Uji bölgesi, tapınak çevresi çay evleri, büyük mağaza katları.',
      'Kyoto\'s Uji area, teahouses near temples, department-store floors.',
    ),
  ),

  // === KAHVALTI / SET ======================================================
  JapaneseDish(
    id: 'teishoku',
    name: 'Teishoku (set menü)',
    nameJa: '定食',
    romaji: 'Teishoku',
    emoji: '🍱',
    category: DishCategory.breakfast,
    summary: LText(
      'Ana yemek + pirinç + miso çorbası + turşu. Japon öğününün standart '
          'kurgusu; en dengeli ve öngörülebilir seçenek.',
      'A main + rice + miso soup + pickles. The standard shape of a Japanese '
          'meal; the most balanced and predictable option.',
    ),
    priceMinJpy: 700,
    priceMaxJpy: 2000,
    ingredients: {
      DishIngredient.dashi: IngredientChance.usually,
      DishIngredient.soy: IngredientChance.usually,
      DishIngredient.fish: IngredientChance.sometimes,
      DishIngredient.gluten: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Kaseleri sırayla değil dönüşümlü tüket — biraz pirinç, biraz ana yemek, '
          'bir yudum çorba. Pirince çubuk saplamak cenaze törenini çağrıştırır, '
          'yapılmaz.',
      'Alternate between the bowls rather than finishing one at a time — some '
          'rice, some main, a sip of soup. Never stand chopsticks upright in '
          'the rice; it echoes a funeral rite.',
    ),
    whereToFind: LText(
      'Ofis bölgelerinde öğle saatlerinde her yerde; en iyi fiyat/performans.',
      'Everywhere in office districts at lunchtime; the best value in Japan.',
    ),
  ),

  JapaneseDish(
    id: 'shojin-ryori',
    name: 'Shojin ryori',
    nameJa: '精進料理',
    romaji: 'Shōjin ryōri',
    emoji: '🌿',
    category: DishCategory.breakfast,
    summary: LText(
      'Budist manastır mutfağı: tamamen bitkisel, et ve balık yok. '
          'Vejetaryenler için Japonya\'nın en güvenli geleneksel öğünü.',
      'Buddhist temple cuisine: fully plant-based, no meat or fish. The safest '
          'traditional meal in Japan for vegetarians.',
    ),
    priceMinJpy: 3000,
    priceMaxJpy: 7000,
    ingredients: {
      DishIngredient.soy: IngredientChance.always,
      DishIngredient.sesame: IngredientChance.usually,
      DishIngredient.gluten: IngredientChance.usually,
    },
    howToEat: LText(
      'Genelde tapınak içinde, yer sofrasında ve öğle saatinde servis edilir. '
          'Rezervasyon çoğu yerde şart.',
      'Usually served inside a temple, at floor seating, at lunchtime. Most '
          'places require a reservation.',
    ),
    watchOut: LText(
      'Dashi kullanılmaz ama bazı modern yorumlar balık suyu ekleyebiliyor; '
          'tapınak işletmesi değilse sor.',
      'Dashi is traditionally excluded, but some modern interpretations add '
          'fish stock; ask if the place is not temple-run.',
    ),
    whereToFind: LText(
      'Kyoto ve Koyasan tapınakları; bazıları konaklamayla birlikte sunar.',
      'Temples in Kyoto and Koyasan; some serve it with an overnight stay.',
    ),
    veganVersionExists: true,
  ),

  JapaneseDish(
    id: 'konbini-meal',
    name: 'Konbini öğünü',
    nameJa: 'コンビニご飯',
    romaji: 'Konbini gohan',
    emoji: '🏪',
    category: DishCategory.breakfast,
    summary: LText(
      'Market yemeği ama Japonya\'da gerçekten iyi: taze sandviç, salata, '
          'erişte kutusu, sıcak reyon. Bütçeyi ve tempoyu kurtarır.',
      'Convenience-store food, but genuinely good in Japan: fresh sandwiches, '
          'salads, noodle boxes, a hot case. It saves both budget and pace.',
    ),
    priceMinJpy: 300,
    priceMaxJpy: 900,
    ingredients: {
      DishIngredient.gluten: IngredientChance.sometimes,
      DishIngredient.egg: IngredientChance.sometimes,
      DishIngredient.pork: IngredientChance.sometimes,
      DishIngredient.fish: IngredientChance.sometimes,
      DishIngredient.dairy: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Kasada "atatamemasu ka?" diye sorulur — ısıtılsın mı demek. Kaşık/çubuk '
          'istenir. Çoğu markette oturacak yer yoktur; dışarıda ayaküstü yenir.',
      'At the register they ask "atatamemasu ka?" — shall I heat it. Ask for '
          'a spoon or chopsticks. Most stores have no seating; you eat outside.',
    ),
    orderTip: LText(
      'Alerjen listesi paketin arkasında Japonca ve zorunludur; telefon '
          'kamerasıyla çeviri en pratik yöntem.',
      'The allergen list on the back of the pack is mandatory and in Japanese; '
          'phone-camera translation is the practical way to read it.',
    ),
    whereToFind: LText(
      '7-Eleven, FamilyMart, Lawson — 24 saat açık, her yerde.',
      '7-Eleven, FamilyMart, Lawson — open 24h, everywhere.',
    ),
    veganVersionExists: true,
  ),
];

/// Menüde/pakette tanınması en çok işe yarayan Japonca kelimeler.
///
/// Bu tablo tek başına bir restoran listesinden daha taşınabilir: kullanıcı
/// bunları tanıyorsa Japonya'nın her yerinde kendini koruyabilir.
const List<({String ja, String romaji, LText meaning})> kMenuWordsToKnow = [
  (
    ja: '豚肉',
    romaji: 'butaniku',
    meaning: LText('domuz eti', 'pork'),
  ),
  (
    ja: '牛肉',
    romaji: 'gyūniku',
    meaning: LText('sığır eti', 'beef'),
  ),
  (
    ja: '鶏肉',
    romaji: 'toriniku',
    meaning: LText('tavuk', 'chicken'),
  ),
  (
    ja: 'だし / 出汁',
    romaji: 'dashi',
    meaning: LText('balık suyu — vejetaryen tuzağı', 'fish stock — the vegetarian trap'),
  ),
  (
    ja: 'みりん',
    romaji: 'mirin',
    meaning: LText('tatlı pişirme şarabı', 'sweet cooking wine'),
  ),
  (
    ja: '料理酒',
    romaji: 'ryōrishu',
    meaning: LText('pişirme sakesi', 'cooking sake'),
  ),
  (
    ja: 'ラード',
    romaji: 'rādo',
    meaning: LText('domuz yağı', 'lard'),
  ),
  (
    ja: 'ゼラチン',
    romaji: 'zerachin',
    meaning: LText('jelatin (kaynağı belirsiz)', 'gelatin (source unclear)'),
  ),
  (
    ja: '卵 / たまご',
    romaji: 'tamago',
    meaning: LText('yumurta', 'egg'),
  ),
  (
    ja: '海老',
    romaji: 'ebi',
    meaning: LText('karides', 'shrimp'),
  ),
  (
    ja: '野菜',
    romaji: 'yasai',
    meaning: LText('sebze', 'vegetable'),
  ),
  (
    ja: '精進',
    romaji: 'shōjin',
    meaning: LText('bitkisel (manastır usulü)', 'plant-based (temple style)'),
  ),
];
