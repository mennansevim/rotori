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
      // Shoyu tarzı (özellikle Tokyo chūka soba) sık sık niboshi/katsuobushi
      // dashi'yi et suyuyla harmanlar; sadece tonkotsu gerçekten dashi'siz.
      DishIngredient.dashi: IngredientChance.sometimes,
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
      // Kakejiru (su) tarifi dashi + soya + mirin'in standart üçlüsüdür;
      // mirinsiz versiyon istisna, kural değil.
      DishIngredient.cookingAlcohol: IngredientChance.usually,
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
      // Kaeshi (soya:mirin:şeker, klasik 3:1:1) sos/su tabanının tanımlayıcı
      // üçlüsü — mirin istisna değil, standart tarif.
      DishIngredient.cookingAlcohol: IngredientChance.usually,
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

  JapaneseDish(
    id: 'yakisoba',
    name: 'Yakisoba',
    nameJa: '焼きそば',
    romaji: 'Yakisoba',
    emoji: '🍜',
    category: DishCategory.noodles,
    summary: LText(
      'Wok\'ta kızartılmış erişte + Worcester tarzı tatlı-ekşi sos. Festival '
          'tezgahlarının klasiği; ramenle karıştırılmasın, suyu yoktur.',
      'Noodles fried in a wok with a sweet-savoury Worcester-style sauce. The '
          'classic festival-stall dish; do not confuse it with ramen — there '
          'is no broth.',
    ),
    priceMinJpy: 500,
    priceMaxJpy: 1200,
    ingredients: {
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.pork: IngredientChance.usually,
      // Sos tarifi soyayı tanımlayıcı kılıyor; istiridye özü de aşağıdaki
      // watchOut'ta zaten söylendiği gibi standart, istisna değil.
      DishIngredient.soy: IngredientChance.always,
      DishIngredient.shellfish: IngredientChance.usually,
      DishIngredient.egg: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Üstüne beni shoga (kırmızı zencefil turşusu) ve aonori (yosun tozu) '
          'serpilir. Festival tezgahında tabak/çubukla ayaküstü yenir.',
      'Topped with beni shoga (red pickled ginger) and aonori (seaweed '
          'flakes). At festival stalls it is eaten standing, off a tray.',
    ),
    watchOut: LText(
      'Sos Worcester tarzıdır ve sıkça istiridye özü içerir; "istiridye yok" '
          'diye sormak gerekebilir.',
      'The sauce is Worcester-style and often contains oyster extract — you '
          'may need to ask for "no oyster".',
    ),
    whereToFind: LText(
      'Festival tezgahları, okonomiyaki dükkanlarının yan menüsü, konbini '
          'dondurulmuş reyonu.',
      'Festival stalls, the side menu at okonomiyaki shops, konbini freezer '
          'aisles.',
    ),
  ),

  JapaneseDish(
    id: 'hiyashi-chuka',
    name: 'Hiyashi chuka',
    nameJa: '冷やし中華',
    romaji: 'Hiyashi chūka',
    emoji: '🥗',
    category: DishCategory.noodles,
    summary: LText(
      'Soğuk erişte üzerine ince şeritler hâlinde jülyen jambon, yumurta '
          'krepi, salatalık; sirkeli-soyalı sosla. Yaz mevsimi yemeği.',
      'Cold noodles topped with julienned ham, thin egg-crepe strips and '
          'cucumber, dressed in a vinegar-soy sauce. A summer-only dish.',
    ),
    priceMinJpy: 700,
    priceMaxJpy: 1400,
    ingredients: {
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.egg: IngredientChance.usually,
      DishIngredient.pork: IngredientChance.usually,
      // Jambon yerine surimi (balık bazlı) kullanılan versiyon da yaygın —
      // watchOut zaten bunu söylüyor, malzeme haritası da yansıtmalı.
      DishIngredient.fish: IngredientChance.sometimes,
      DishIngredient.soy: IngredientChance.always,
      DishIngredient.sesame: IngredientChance.usually,
    },
    howToEat: LText(
      'Servis edilir edilmez tüm malzemeler karıştırılıp yenir; erişte '
          'soğuduğu için beklemenin bir sakıncası yoktur.',
      'Everything is mixed together right after serving; since the noodles '
          'are cold there is no rush to finish it hot.',
    ),
    watchOut: LText(
      'Jambon yerine bazı yerlerde surimi (yengeç taklidi) kullanılır — ikisi '
          'de standart tarifte var, sebzeli versiyonu az bulunur.',
      'Some shops use surimi (imitation crab) instead of ham — either way the '
          'standard recipe is not vegetarian; a veggie-only version is rare.',
    ),
    whereToFind: LText(
      'Çin lokantaları ve soba/ramen dükkanlarının yaz menüsü.',
      'Chinese diners and the summer menu at soba/ramen shops.',
    ),
  ),

  JapaneseDish(
    id: 'champon',
    name: 'Champon',
    nameJa: 'ちゃんぽん',
    romaji: 'Chanpon',
    emoji: '🍜',
    category: DishCategory.noodles,
    summary: LText(
      'Nagasaki\'ye özgü: domuz kemiği + deniz ürünü suyuna biraz süt eklenip '
          'kalın erişte ve bol sebzeyle servis edilir. Kremamsı ve doyurucu.',
      'Nagasaki\'s own: pork-bone and seafood broth with a little milk added, '
          'served with thick noodles and lots of vegetables. Creamy and '
          'filling.',
    ),
    priceMinJpy: 800,
    priceMaxJpy: 1600,
    ingredients: {
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.pork: IngredientChance.usually,
      DishIngredient.shellfish: IngredientChance.usually,
      DishIngredient.fish: IngredientChance.usually,
      DishIngredient.dairy: IngredientChance.usually,
      DishIngredient.soy: IngredientChance.usually,
      DishIngredient.cookingAlcohol: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Kaşıkla suyu, çubukla eriştesi yenir; ikisi birlikte servis edilen '
          'nadir tabaklardan.',
      'Spoon for the broth, chopsticks for the noodles — one of the few '
          'dishes served with both utensils together.',
    ),
    watchOut: LText(
      'Sütlü olması vegan/laktoz hassasiyeti için ayrı bir engel; ayrıca '
          'domuz ve deniz ürünü suyu aynı kazanda karışır, biri hariç '
          'tutulamaz.',
      'The milk is a separate barrier for vegan or lactose needs; also the '
          'pork and seafood stocks are simmered together, so one cannot be '
          'excluded.',
    ),
    whereToFind: LText(
      'Nagasaki\'de her yerde; büyük şehirlerde Nagasaki mutfağı '
          'lokantalarında.',
      'Everywhere in Nagasaki; at Nagasaki-cuisine restaurants in big cities.',
    ),
  ),

  JapaneseDish(
    id: 'somen',
    name: 'Somen',
    nameJa: 'そうめん',
    romaji: 'Sōmen',
    emoji: '🍜',
    category: DishCategory.noodles,
    summary: LText(
      'Sobadan da ince buğday eriştesi; buzlu suda soğuk servis edilip dashi '
          'bazlı sosa batırılarak yenir. Yazın hafif bir öğün.',
      'Wheat noodles even thinner than soba, served ice-cold and dipped in a '
          'dashi-based sauce. A light summer meal.',
    ),
    priceMinJpy: 400,
    priceMaxJpy: 1000,
    ingredients: {
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.dashi: IngredientChance.always,
      DishIngredient.soy: IngredientChance.always,
      // Mentsuyu (soya + dashi + mirin + şeker) soba/udon sosuyla aynı
      // yapıda — mirin standart, istisna değil.
      DishIngredient.cookingAlcohol: IngredientChance.usually,
    },
    howToEat: LText(
      'Küçük bir tutam alıp sosa batırılır; büyük lokma yapıp uzun süre '
          'çekmek beklenen bir davranış değildir. "Nagashi somen" (akan '
          'oluktan yakalayarak yeme) bazı restoranlarda oyun gibi sunulur.',
      'Take a small pinch and dip it — long, drawn-out slurping of a big '
          'bundle is not the norm here. "Nagashi somen" (catching noodles as '
          'they flow down a chute) is offered as a game at some restaurants.',
    ),
    watchOut: LText(
      'Soğuk ve etsiz göründüğü için vejetaryen sanılır ama sos dashi '
          'bazlıdır.',
      'It looks vegetarian because it is cold and meat-free, but the dipping '
          'sauce is dashi-based.',
    ),
    whereToFind: LText(
      'Yaz aylarında soba dükkanları ve ev sofralarında yaygın.',
      'Common at soba shops and home tables during summer.',
    ),
    veganVersionExists: true,
  ),

  JapaneseDish(
    id: 'tsukemen',
    name: 'Tsukemen',
    nameJa: 'つけ麺',
    romaji: 'Tsukemen',
    emoji: '🍜',
    category: DishCategory.noodles,
    summary: LText(
      'Erişte ve su ayrı kaselerde gelir; erişteyi yoğun, koyu suya batırarak '
          'yersin. Ramenden farklı bir yeme ritüeli.',
      'Noodles and broth arrive in separate bowls; you dip the noodles into a '
          'thick, concentrated broth. A different eating ritual from ramen.',
    ),
    priceMinJpy: 900,
    priceMaxJpy: 1800,
    ingredients: {
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.pork: IngredientChance.usually,
      DishIngredient.fish: IngredientChance.usually,
      DishIngredient.soy: IngredientChance.usually,
      DishIngredient.cookingAlcohol: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Erişte SOĞUK gelir, su SICAK ve koyudur — erişteyi suya batırıp hemen '
          'ağzına al. Sonunda "supu-wari" isteyebilirsin: kalan koyu suyu '
          'sıcak dashi ile inceltip çorba gibi içersin.',
      'The noodles arrive COLD, the broth HOT and concentrated — dip and eat '
          'immediately. At the end you can ask for "supu-wari": the leftover '
          'thick broth is diluted with hot dashi and drunk like soup.',
    ),
    whereToFind: LText(
      'Bağımsız tsukemen dükkanları, büyük şehirlerde yaygın.',
      'Dedicated tsukemen shops, common in big cities.',
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
    // Diğer tüm yemeklerde `name` Latin harfli, uluslararası ortak addır
    // (Ramen, Udon, Gyudon…) ve LText DEĞİLDİR — İngilizce arayüzde de
    // aynen gösterilir. "Japon körisi" burada bir çeviri gibi kalmıştı;
    // düzeltildi.
    name: 'Curry rice',
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
      // Standart köri sosu bloğu (S&B, House Vermont, Glico gibi) varsayılan
      // olarak sığır/domuz/tavuk yağı ya da özütü içerir — üstüne konan et
      // seçiminden BAĞIMSIZ. "Bazen" demek bunu "sor"a indiriyordu; oysa
      // watchOut zaten "üstünde et olmaması sosun etsiz olduğu anlamına
      // gelmez" diyor. Sos ayrıca ısmarlanmadıkça varsayılan budur.
      DishIngredient.beef: IngredientChance.usually,
      DishIngredient.pork: IngredientChance.usually,
      DishIngredient.chicken: IngredientChance.usually,
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
          // "Soya sosunda pişmiş" (tsukudani) demek; standart tarif soya +
          // mirin + sake + şeker kaynatmasıdır — soya burada temel malzeme,
          // ana yemekten kalıtılan "bazen" seviyesi bunu düşük gösteriyordu.
          DishIngredient.soy: IngredientChance.always,
          DishIngredient.cookingAlcohol: IngredientChance.usually,
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

  JapaneseDish(
    id: 'unadon',
    name: 'Unadon',
    nameJa: '鰻丼',
    romaji: 'Unadon',
    emoji: '🐍',
    category: DishCategory.rice,
    summary: LText(
      'Izgarada tatlı-soyalı sosla (kabayaki) fırınlanmış yılan balığı fileto, '
          'pirinç üstünde. Yaz aylarında dayanıklılık için yenen geleneksel '
          'bir yemek.',
      'Grilled eel fillet basted with a sweet soy glaze (kabayaki), over '
          'rice. Traditionally eaten in summer for stamina.',
    ),
    // Zincir/ucuz unadon (¥500–990) da yaygın; alt sınır bunu dışlıyordu.
    priceMinJpy: 700,
    priceMaxJpy: 5000,
    ingredients: {
      DishIngredient.fish: IngredientChance.always,
      // Kabayaki tam olarak "soya+mirin+sake+şeker sosuyla glazelenmiş"
      // demek — bu dişin ADI bu sosla tanımlanıyor, "genelde" değil.
      DishIngredient.soy: IngredientChance.always,
      DishIngredient.cookingAlcohol: IngredientChance.always,
      DishIngredient.gluten: IngredientChance.usually,
    },
    howToEat: LText(
      'Üstüne serpilen sansho (Japon biberi) tadı hafifletir. Çubukla '
          'yenir; kesme gerekmez, dilimler zaten ayrılmıştır.',
      'The sansho pepper sprinkled on top cuts the richness. Eaten with '
          'chopsticks — no cutting needed, the fillet is already sliced.',
    ),
    whereToFind: LText(
      'Bağımsız unagi lokantaları (pahalı) ve süpermarket hazır kutuları '
          '(ucuz alternatif).',
      'Dedicated unagi restaurants (expensive) and pre-packed supermarket '
          'boxes (the cheap alternative).',
    ),
  ),

  JapaneseDish(
    id: 'kaisendon',
    name: 'Kaisendon',
    nameJa: '海鮮丼',
    romaji: 'Kaisendon',
    emoji: '🐟',
    category: DishCategory.rice,
    summary: LText(
      'Sirkeli pirinç üstüne serpiştirilmiş çeşit çeşit çiğ deniz ürünü. '
          'Suşiden farkı: parçalar ayrı ayrı şekillendirilmez, kaseye dökülür.',
      'An assortment of raw seafood scattered over vinegared rice. Unlike '
          'sushi, the pieces are not individually shaped — they are simply '
          'piled onto the bowl.',
    ),
    priceMinJpy: 1200,
    priceMaxJpy: 4000,
    ingredients: {
      DishIngredient.fish: IngredientChance.always,
      DishIngredient.shellfish: IngredientChance.usually,
      DishIngredient.soy: IngredientChance.always,
    },
    howToEat: LText(
      'Malzemelere ayrı ayrı soya sosu değdirilir, pirince değil. Wasabi '
          'genelde balığın üstünde ince bir tabaka olarak zaten konmuştur.',
      'Dip each piece of seafood in soy sauce individually, not the rice. '
          'Wasabi is often already placed as a thin layer under the fish.',
    ),
    whereToFind: LText(
      'Balık halleri ve liman kentlerindeki lokantalar; Tsukiji dış çarşı.',
      'Fish markets and restaurants in port towns; the Tsukiji outer market.',
    ),
  ),

  JapaneseDish(
    id: 'omurice',
    name: 'Omurice',
    nameJa: 'オムライス',
    romaji: 'Omuraisu',
    emoji: '🍳',
    category: DishCategory.rice,
    summary: LText(
      'Ketçaplı tavuklu kızarmış pirincin ince bir omletle sarılması. Batı '
          'etkili "yōshoku" mutfağının simgesi; çocuklar için de sevilir.',
      'Ketchup-fried chicken rice wrapped in a thin omelette. A symbol of '
          'Western-influenced "yōshoku" cuisine; a favourite with kids too.',
    ),
    priceMinJpy: 700,
    priceMaxJpy: 1600,
    ingredients: {
      DishIngredient.egg: IngredientChance.always,
      DishIngredient.chicken: IngredientChance.usually,
      DishIngredient.dairy: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Kaşıkla yenir. Üstüne ketçap ya da demi-glace sos çizgi hâlinde '
          'dökülür; bazı yerlerde isim/şekil çizdirebilirsin.',
      'Eaten with a spoon. Ketchup or demi-glace sauce is drizzled in a line '
          'on top; some shops will draw a shape or write on it for you.',
    ),
    variants: [
      DishVariant(
        name: 'Demi-glace omurice',
        nameJa: 'デミグラスオムライス',
        note: LText(
          'Ketçap yerine koyu et suyu sosu — genelde sığır suyu bazlıdır.',
          'Rich brown sauce instead of ketchup — usually beef-stock based.',
        ),
        ingredients: {DishIngredient.beef: IngredientChance.usually},
      ),
    ],
    whereToFind: LText(
      'Yōshoku lokantaları, kafeler, aile restoranı zincirleri.',
      'Yōshoku diners, cafés, family restaurant chains.',
    ),
  ),

  JapaneseDish(
    id: 'ochazuke',
    name: 'Ochazuke',
    nameJa: 'お茶漬け',
    romaji: 'Ochazuke',
    emoji: '🍵',
    category: DishCategory.rice,
    summary: LText(
      'Sıcak dashi veya yeşil çayın pirincin üzerine dökülmesi; üstüne nori, '
          'susam, bazen tuzlu somon. Gece geç saatte ya da mide rahatlatmak '
          'için yenir.',
      'Hot dashi or green tea poured over rice, topped with nori, sesame, '
          'sometimes salted salmon. Eaten late at night or to settle the '
          'stomach.',
    ),
    priceMinJpy: 300,
    priceMaxJpy: 900,
    ingredients: {
      DishIngredient.dashi: IngredientChance.usually,
      DishIngredient.fish: IngredientChance.sometimes,
      DishIngredient.soy: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Çorba gibi kaseyi kaldırıp içilir; hızlı ve sessiz yenen bir yemektir, '
          'sosyal bir öğün değildir.',
      'Lift the bowl and drink it like a soup; it is eaten quickly and '
          'quietly, not really a social meal.',
    ),
    variants: [
      DishVariant(
        name: 'Ume ochazuke',
        nameJa: '梅茶漬け',
        note: LText(
          'Tuzlu erikle — ama hazır paket sosunda (ör. Nagatanien) genelde '
              'katsuobushi/balık özü vardır; "balıksız" sanma, ambalajı '
              'kontrol et.',
          'With salted plum — but the packaged seasoning (e.g. Nagatanien) '
              'usually still contains bonito/fish extract; don\'t assume '
              '"fish-free", check the packet.',
        ),
        ingredients: {DishIngredient.fish: IngredientChance.sometimes},
      ),
    ],
    whereToFind: LText(
      'Ev sofraları, izakaya\'ların gece geç menüsü.',
      'Home tables, the late-night menu at izakaya.',
    ),
    veganVersionExists: true,
  ),

  JapaneseDish(
    id: 'butadon',
    name: 'Butadon',
    nameJa: '豚丼',
    romaji: 'Butadon',
    emoji: '🍚',
    category: DishCategory.rice,
    summary: LText(
      'Hokkaido\'nun (Obihiro) yerel yemeği: ince dilim domuzun tatlı-soyalı '
          'sosla ızgarada glazelenip pirince konması. Gyudon\'un domuzlu hâli.',
      'A Hokkaido (Obihiro) local dish: thin pork slices grilled and '
          'glazed in a sweet soy sauce, served over rice. The pork version of '
          'gyudon.',
    ),
    priceMinJpy: 600,
    priceMaxJpy: 1400,
    ingredients: {
      DishIngredient.pork: IngredientChance.always,
      DishIngredient.soy: IngredientChance.always,
      DishIngredient.cookingAlcohol: IngredientChance.usually,
    },
    howToEat: LText(
      'Sırayla ısırılır, bir seferde bitirilmez — sıcak servis edilir ve '
          'soğumadan yenmesi beklenir.',
      'Eaten steadily, not rushed in one go — served hot and best finished '
          'before it cools.',
    ),
    whereToFind: LText(
      'Hokkaido\'da (özellikle Obihiro) her yerde; büyük şehirlerde Hokkaido '
          'mutfağı lokantaları.',
      'Everywhere in Hokkaido (especially Obihiro); Hokkaido-cuisine diners '
          'in big cities.',
    ),
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
          'Tatlı tofu kesesinde pirinç. Kese genelde balık bazlı (katsuobushi) '
              'dashi\'de haşlanır — "tamamen bitkisel" sanma, kombu-dashi '
              '(deniz yosunu, balıksız) ile yapılıp yapılmadığını sor.',
          'Rice in a sweet tofu pouch. The pouch is usually simmered in a '
              'bonito-based dashi broth — don\'t assume "fully plant-based"; '
              'ask if it was made with kombu-only (seaweed, no fish) dashi.',
        ),
        ingredients: {
          DishIngredient.fish: IngredientChance.sometimes,
          DishIngredient.soy: IngredientChance.always,
          DishIngredient.dashi: IngredientChance.usually,
          DishIngredient.cookingAlcohol: IngredientChance.sometimes,
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
      // Bir moriawase (karışık tabak) genelde amaebi/hotate/uni/ika gibi
      // kabuklu/yumuşakça deniz ürünü de içerir, sadece balık değil.
      DishIngredient.shellfish: IngredientChance.sometimes,
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

  JapaneseDish(
    id: 'chirashi',
    name: 'Chirashizushi',
    nameJa: 'ちらし寿司',
    romaji: 'Chirashizushi',
    emoji: '🍣',
    category: DishCategory.raw,
    summary: LText(
      'Sirkeli suşi pirinci üstüne serpiştirilmiş çeşit çeşit çiğ balık ve '
          'bazen omlet, yosun şeridi. Kaisendon\'un "suşi pirinçli" hâli.',
      'A scatter of assorted raw fish — sometimes with omelette strips and '
          'nori — over vinegared sushi rice. The "sushi rice" version of '
          'kaisendon.',
    ),
    priceMinJpy: 1200,
    priceMaxJpy: 4500,
    ingredients: {
      DishIngredient.fish: IngredientChance.always,
      DishIngredient.soy: IngredientChance.always,
      DishIngredient.egg: IngredientChance.sometimes,
      DishIngredient.shellfish: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Kaisendon gibi malzemeye soya sosu değdirilir; kaşıkla değil çubukla '
          'yenir.',
      'Like kaisendon, dip the topping in soy sauce; eaten with chopsticks, '
          'not a spoon.',
    ),
    whereToFind: LText(
      'Suşi lokantaları, Hina Matsuri (kız çocuk bayramı) sofralarında '
          'geleneksel.',
      'Sushi restaurants; traditional on Hina Matsuri (Girls\' Day) tables.',
    ),
  ),

  JapaneseDish(
    id: 'temaki',
    name: 'Temaki',
    nameJa: '手巻き',
    romaji: 'Temaki',
    emoji: '🍙',
    category: DishCategory.raw,
    summary: LText(
      'El yapımı koni şeklinde suşi rulosu — yosun içine pirinç ve dolgu '
          'sarılır. Restoranda da yapılır ama asıl evde parti yemeğidir.',
      'A hand-rolled cone of sushi — rice and filling wrapped in nori. Made '
          'at restaurants too, but its real home is the family sushi party.',
    ),
    priceMinJpy: 300,
    priceMaxJpy: 1200,
    ingredients: {
      DishIngredient.fish: IngredientChance.usually,
      DishIngredient.soy: IngredientChance.always,
      DishIngredient.shellfish: IngredientChance.sometimes,
      // Tamago (dashimaki/tamagoyaki) somon/ton kadar yaygın bir dolgu.
      DishIngredient.egg: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Yapıldığı anda, yosun çıtırlığını kaybetmeden hemen elle yenir; '
          'masaya bırakılıp beklenmez.',
      'Eaten by hand right after rolling, before the nori loses its crunch — '
          'not something you set down and wait to eat.',
    ),
    whereToFind: LText(
      'Suşi lokantaları, kendi-yap suşi setleri (evde parti).',
      'Sushi restaurants; DIY sushi kits at home parties.',
    ),
    veganVersionExists: true,
  ),

  JapaneseDish(
    id: 'aburi-sushi',
    name: 'Aburi suşi',
    nameJa: '炙り寿司',
    romaji: 'Aburi zushi',
    emoji: '🔥',
    category: DishCategory.raw,
    summary: LText(
      'Üstü alevle hafifçe dağlanmış (aburi) nigiri; balık yarı çiğ, yarı '
          'pişmiş kalır ve genelde bir sos fırçalanır.',
      'Nigiri with the top lightly seared with a torch (aburi); the fish '
          'ends up half raw, half cooked, usually brushed with a sauce.',
    ),
    priceMinJpy: 1500,
    priceMaxJpy: 6000,
    ingredients: {
      DishIngredient.fish: IngredientChance.usually,
      DishIngredient.soy: IngredientChance.always,
      // watchOut zaten "çoğu zaman" diyor — bu "genelde" seviyesidir,
      // "bazen"in "sor" düzeyinden daha kesin bir uyarı gerektiriyor.
      DishIngredient.egg: IngredientChance.usually,
      DishIngredient.dairy: IngredientChance.sometimes,
      // Klasik aburi sosu (nitsume) soya+mirin+sake redüksiyonudur; mayonez
      // bazlı sos daha yeni bir füzyon alternatifi.
      DishIngredient.cookingAlcohol: IngredientChance.usually,
    },
    watchOut: LText(
      'Fırçalanan sos çoğu zaman mayonez bazlıdır (yumurta) — "çıplak" nigiri '
          'sanıp yersen sürpriz olabilir.',
      'The brushed sauce is often mayo-based (egg) — a surprise if you '
          'assumed it was a plain nigiri.',
    ),
    howToEat: LText(
      'Standart suşi gibi elle veya çubukla, tek lokmada.',
      'Like standard sushi — by hand or chopsticks, in one bite.',
    ),
    whereToFind: LText(
      'Modern/fusion suşi lokantaları, kaiten (dönen bant) zincirlerinin özel '
          'menüsü.',
      'Modern/fusion sushi restaurants; the special menu at kaiten (conveyor '
          'belt) chains.',
    ),
  ),

  JapaneseDish(
    id: 'katsuo-tataki',
    name: 'Katsuo no tataki',
    nameJa: 'カツオのたたき',
    romaji: 'Katsuo no tataki',
    emoji: '🐟',
    category: DishCategory.raw,
    summary: LText(
      'Palamut/orkinos türü balığın dışı ateşte hafif kavrulup içi çiğ '
          'bırakılması; ponzu (turunçgil-soya) sosuyla servis edilir. Kochi '
          'bölgesinin klasiği.',
      'Bonito seared briefly on the outside, raw inside, served with ponzu '
          '(citrus-soy) sauce. A classic from the Kochi region.',
    ),
    priceMinJpy: 900,
    priceMaxJpy: 2500,
    ingredients: {
      DishIngredient.fish: IngredientChance.always,
      DishIngredient.soy: IngredientChance.always,
      // Ponzu, tanımı gereği soya sosu + turunçgil + mirindir; mirin
      // istisna değil, sosun standart bileşeni.
      DishIngredient.cookingAlcohol: IngredientChance.usually,
    },
    howToEat: LText(
      'İnce dilimlenmiş üstüne sarımsak, taze zencefil ve myoga (Japon '
          'zencefil çiçeği) konur; çubukla yenir.',
      'Thinly sliced and topped with garlic, fresh ginger and myoga '
          '(Japanese ginger flower); eaten with chopsticks.',
    ),
    whereToFind: LText(
      'Kochi bölgesi lokantaları, izakaya menüleri.',
      'Restaurants in the Kochi region, izakaya menus.',
    ),
  ),

  JapaneseDish(
    id: 'negitoro',
    name: 'Negitoro',
    nameJa: 'ねぎとろ',
    romaji: 'Negitoro',
    emoji: '🍣',
    category: DishCategory.raw,
    summary: LText(
      'İnce kıyılmış yağlı orkinos (toro) ile doğranmış yeşil soğanın '
          'karıştırılması. Suşi rulosu, gunkan (zırhlı) suşi ya da pirinç '
          'kasesi üstünde bulunur.',
      'Minced fatty tuna (toro) mixed with chopped spring onion. Found in '
          'sushi rolls, gunkan (battleship) sushi, or over a bowl of rice.',
    ),
    priceMinJpy: 600,
    priceMaxJpy: 2000,
    ingredients: {
      DishIngredient.fish: IngredientChance.always,
      DishIngredient.soy: IngredientChance.always,
      DishIngredient.gluten: IngredientChance.sometimes,
    },
    watchOut: LText(
      'Bazı yerlerde mayonez katılır (yumurta) — "mayonezsiz" istemek '
          'gerekebilir.',
      'Some shops mix in mayonnaise (egg) — you may need to ask for it '
          '"without mayo".',
    ),
    howToEat: LText(
      'Rulo ya da gunkan hâlindeyse elle/çubukla tek lokma; kase hâlindeyse '
          'karıştırıp pirinçle yenir.',
      'If it is a roll or gunkan, one bite by hand or chopsticks; if it is a '
          'bowl, mix it into the rice first.',
    ),
    whereToFind: LText(
      'Suşi lokantaları, kaiten zincirleri.',
      'Sushi restaurants, kaiten chains.',
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
      // Standart tare, sake+mirin kaynatılıp soya/sarımsak/susamla
      // birleştirilerek yapılır — varsayılan sos, istisna değil.
      DishIngredient.cookingAlcohol: IngredientChance.usually,
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

  JapaneseDish(
    id: 'teppanyaki',
    name: 'Teppanyaki',
    nameJa: '鉄板焼き',
    romaji: 'Teppanyaki',
    emoji: '🍳',
    category: DishCategory.grilled,
    summary: LText(
      'Geniş demir sac üzerinde şefin gözünün önünde ızgara edilen et, deniz '
          'ürünü ve sebze. Yakiniku\'dan farkı: eti sen değil şef pişirir.',
      'Meat, seafood and vegetables grilled on a wide iron plate in front of '
          'you by the chef. Unlike yakiniku, you do not do the grilling.',
    ),
    priceMinJpy: 2500,
    priceMaxJpy: 15000,
    ingredients: {
      DishIngredient.beef: IngredientChance.usually,
      DishIngredient.shellfish: IngredientChance.sometimes,
      DishIngredient.soy: IngredientChance.usually,
      // Sarımsaklı tereyağı, kendi metnimizin de dediği gibi "genelde"
      // ikram edilen bir garnitür — nadir bir seçenek değil.
      DishIngredient.dairy: IngredientChance.usually,
      DishIngredient.cookingAlcohol: IngredientChance.usually,
      DishIngredient.gluten: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Şef parça parça servis eder, sıcakken hemen ye — bekletme. Genelde '
          'sarımsaklı tereyağı ya da soya bazlı sos ikram edilir.',
      'The chef serves piece by piece — eat each one hot, do not let it sit. '
          'Usually served with garlic butter or a soy-based sauce.',
    ),
    watchOut: LText(
      'Garnitür olarak eklenen tereyağı süt ürünüdür; vegan/laktozsuz '
          'istersen önceden söyle.',
      'The garlic butter garnish is dairy; say so in advance if you need '
          'vegan or lactose-free.',
    ),
    whereToFind: LText(
      'Özel gün teppanyaki lokantaları, oteller; genelde rezervasyon ister.',
      'Special-occasion teppanyaki restaurants, hotels; usually needs a '
          'reservation.',
    ),
  ),

  JapaneseDish(
    id: 'unagi-kabayaki',
    name: 'Unagi no kabayaki',
    nameJa: '鰻の蒲焼',
    romaji: 'Unagi no kabayaki',
    emoji: '🐍',
    category: DishCategory.grilled,
    summary: LText(
      'Yılan balığının kelebek açılıp tekrar tekrar tatlı soya sosuyla '
          'fırçalanarak ızgarada pişirilmesi. Unadon\'un pirinçsiz, tabakta '
          'servis edilen hâli.',
      'Eel, butterflied and repeatedly basted with a sweet soy glaze while '
          'grilling. The plate version of unadon, without rice.',
    ),
    priceMinJpy: 1800,
    priceMaxJpy: 6000,
    ingredients: {
      DishIngredient.fish: IngredientChance.always,
      // "Kabayaki" tam olarak bu soya+mirin+sake+şeker sosuyla glazelenmiş
      // olmak demek — dişin adının kendisi bu sosla tanımlanıyor.
      DishIngredient.soy: IngredientChance.always,
      DishIngredient.cookingAlcohol: IngredientChance.always,
      DishIngredient.gluten: IngredientChance.usually,
    },
    howToEat: LText(
      'Sıcakken, çubukla; genelde bir set menünün parçası olarak pirinç ve '
          'çorbayla birlikte gelir.',
      'Eaten hot with chopsticks; usually comes as part of a set with rice '
          'and soup.',
    ),
    whereToFind: LText(
      'Bağımsız unagi lokantaları — genelde geleneksel, ahşap iç mekanlı.',
      'Dedicated unagi restaurants — usually traditional, wood-panelled '
          'interiors.',
    ),
  ),

  JapaneseDish(
    id: 'saba-shioyaki',
    name: 'Saba no shioyaki',
    nameJa: '鯖の塩焼き',
    romaji: 'Saba no shioyaki',
    emoji: '🐟',
    category: DishCategory.grilled,
    summary: LText(
      'Tuzlanıp doğrudan ızgarada pişirilmiş uskumru. Sos yok, süsleme yok — '
          'ev yemeğinin ve teishoku\'nun en sade balık seçeneği.',
      'Mackerel salted and grilled plain. No sauce, no fuss — the simplest '
          'fish option in home cooking and teishoku sets.',
    ),
    priceMinJpy: 500,
    priceMaxJpy: 1400,
    ingredients: {
      DishIngredient.fish: IngredientChance.always,
    },
    howToEat: LText(
      'Yanındaki rendelenmiş beyaz turpun üzerine biraz soya sosu dökülüp '
          'balıkla birlikte yenir; kılçıklara dikkat.',
      'A little soy sauce is poured over the grated white radish alongside '
          'and eaten with the fish; watch for small bones.',
    ),
    whereToFind: LText(
      'Teishoku lokantaları, ev sofraları, konbini ısıtılmış reyonu.',
      'Teishoku diners, home tables, the heated case at konbini.',
    ),
  ),

  JapaneseDish(
    id: 'robatayaki',
    name: 'Robatayaki',
    nameJa: '炉端焼き',
    romaji: 'Robatayaki',
    emoji: '🔥',
    category: DishCategory.grilled,
    summary: LText(
      'Kömür ateşi başında karışık deniz ürünü, sebze ve et şişlerinin '
          'ızgara edilmesi. Yakitori\'den farkı: tavuğa kilitli değil, çok '
          'daha geniş bir menüsü var.',
      'Charcoal-fire grilling of mixed seafood, vegetable and meat skewers. '
          'Unlike yakitori it is not chicken-only — the menu is far wider.',
    ),
    priceMinJpy: 300,
    priceMaxJpy: 1200,
    ingredients: {
      DishIngredient.fish: IngredientChance.sometimes,
      DishIngredient.shellfish: IngredientChance.sometimes,
      DishIngredient.beef: IngredientChance.sometimes,
      DishIngredient.soy: IngredientChance.usually,
      // Yakitori ile aynı tare (sake+mirin+soya+şeker) birçok şişte
      // kullanılır; menü geniş olduğu için "her şişte" değil ama "bazı
      // şişlerde" seviyesinden fazlası.
      DishIngredient.cookingAlcohol: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Geleneksel robatayaki\'de şişler uzun bir kürekle tezgahtan sana '
          'uzatılır; şişten doğrudan ısırılır.',
      'At a traditional robatayaki counter, skewers are handed to you on a '
          'long wooden paddle; bite straight off the skewer.',
    ),
    whereToFind: LText(
      'İzakaya\'lar, özellikle Hokkaido kökenli tezgah usulü mekanlar.',
      'Izakaya, especially counter-style places with Hokkaido roots.',
    ),
  ),

  JapaneseDish(
    id: 'motsuyaki',
    name: 'Motsuyaki',
    nameJa: 'モツ焼き',
    romaji: 'Motsuyaki',
    emoji: '🍢',
    category: DishCategory.grilled,
    summary: LText(
      'Sakatat (bağırsak, ciğer, kalp) şişlerinin ızgarada pişirilmesi. '
          'İzakaya\'nın ucuz ve yoğun tatlı klasiği; herkesin damağına göre '
          'değil.',
      'Grilled skewers of offal (intestine, liver, heart). A cheap, '
          'intensely flavoured izakaya classic — not to everyone\'s taste.',
    ),
    priceMinJpy: 120,
    priceMaxJpy: 350,
    ingredients: {
      DishIngredient.pork: IngredientChance.usually,
      DishIngredient.beef: IngredientChance.sometimes,
      DishIngredient.soy: IngredientChance.usually,
      // Kendi metni "yakitori gibi shio/tare" diyor; yakitori'nin tare'si
      // aynı sake+mirin sosu — aynı seviyede olmalı.
      DishIngredient.cookingAlcohol: IngredientChance.usually,
    },
    howToEat: LText(
      'Tuzlu (shio) veya soslu (tare) seçilir; yakitori gibi şişten doğrudan '
          'ısırılır.',
      'Ordered salted (shio) or with sauce (tare); bitten straight off the '
          'skewer like yakitori.',
    ),
    whereToFind: LText(
      'İzakaya, özellikle Tokyo\'nun eski işçi mahallelerindeki (Kita-'
          'senju, San\'ya) tezgahlar.',
      'Izakaya, especially counters in Tokyo\'s old working-class districts '
          '(Kita-senju, San\'ya).',
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

  JapaneseDish(
    id: 'korokke',
    name: 'Korokke',
    nameJa: 'コロッケ',
    romaji: 'Korokke',
    emoji: '🥔',
    category: DishCategory.fried,
    summary: LText(
      'Patates püresi (bazen kıymalı) panelenip kızartılmış kroket. '
          'Konbini\'nin ve kasap dükkanlarının sokak atıştırmalığı.',
      'A croquette of mashed potato (often mixed with minced meat), breaded '
          'and fried. The street snack of konbini and butcher-shop counters.',
    ),
    priceMinJpy: 100,
    priceMaxJpy: 300,
    ingredients: {
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.egg: IngredientChance.usually,
      // "Genelde kıymalı" (summary) ve watchOut'un "varsayılan kıymalıdır"
      // demesiyle tutarlı olmak için: klasik/en bilinen korokke patates+kıyma
      // karışımıdır, saf sebzeli olan (kabocha) bilinçli istisnadır.
      DishIngredient.beef: IngredientChance.usually,
      DishIngredient.pork: IngredientChance.usually,
      DishIngredient.dairy: IngredientChance.sometimes,
    },
    variants: [
      DishVariant(
        name: 'Kabocha korokke',
        nameJa: 'かぼちゃコロッケ',
        note: LText(
          'Bal kabağı bazlı, genelde etsiz — ama fritöz aynı yağı '
              'paylaşabilir.',
          'Pumpkin-based, usually meat-free — but the fryer oil may be '
              'shared.',
        ),
        ingredients: {
          DishIngredient.beef: IngredientChance.sometimes,
          DishIngredient.pork: IngredientChance.sometimes,
        },
      ),
    ],
    howToEat: LText(
      'Sıcakken elle ya da çubukla; Worcester tarzı sos ya da ketçapla '
          'yenir. Ayaküstü, kasap dükkanı önünde yemek yaygındır.',
      'Eaten hot, by hand or chopsticks, with Worcester-style sauce or '
          'ketchup. Eating it standing outside the butcher shop is common.',
    ),
    watchOut: LText(
      'Kasaplarda kıymalı olanı varsayılandır; "yasai" (sebzeli) diye '
          'sorulmadıkça et içerdiğini düşün.',
      'At butcher shops the meat-filled kind is the default; assume it '
          'contains meat unless you ask for "yasai" (vegetable).',
    ),
    whereToFind: LText(
      'Kasap dükkanları, konbini, süpermarket hazır reyonu.',
      'Butcher shops, konbini, supermarket ready-food aisles.',
    ),
  ),

  JapaneseDish(
    id: 'ebi-fry',
    name: 'Ebi fry',
    nameJa: 'エビフライ',
    romaji: 'Ebi furai',
    emoji: '🍤',
    category: DishCategory.fried,
    summary: LText(
      'Panelenip kızartılmış büyük karides. Tempura\'dan farkı: hamur ince '
          'değil, panko ekmek kırıntısıyla kaplanır — daha kalın ve çıtır.',
      'Large shrimp, breaded and deep-fried. Unlike tempura, the coating is '
          'not a thin batter but panko crumbs — thicker and crunchier.',
    ),
    priceMinJpy: 500,
    priceMaxJpy: 1800,
    ingredients: {
      DishIngredient.shellfish: IngredientChance.always,
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.egg: IngredientChance.usually,
    },
    howToEat: LText(
      'Tartar sosuna ya da Worcester tarzı sosa batırılıp çubukla yenir; '
          'çoğunlukla lahana rendesiyle servis edilir.',
      'Dipped in tartar sauce or Worcester-style sauce, eaten with '
          'chopsticks; usually served with shredded cabbage.',
    ),
    whereToFind: LText(
      'Yōshoku lokantaları, aile restoranı zincirleri, bento kutuları.',
      'Yōshoku diners, family restaurant chains, bento boxes.',
    ),
  ),

  JapaneseDish(
    id: 'menchi-katsu',
    name: 'Menchi katsu',
    nameJa: 'メンチカツ',
    romaji: 'Menchi katsu',
    emoji: '🍔',
    category: DishCategory.fried,
    summary: LText(
      'Kıyma (genelde sığır-domuz karışık) köftenin panelenip kızartılması. '
          'Tonkatsu\'nun kıymalı, daha yumuşak dokulu kardeşi.',
      'Minced meat (usually a beef-pork mix) formed into a patty, breaded '
          'and fried. Tonkatsu\'s minced, softer-textured cousin.',
    ),
    priceMinJpy: 200,
    priceMaxJpy: 600,
    ingredients: {
      DishIngredient.beef: IngredientChance.usually,
      DishIngredient.pork: IngredientChance.usually,
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.egg: IngredientChance.usually,
      DishIngredient.soy: IngredientChance.usually,
    },
    howToEat: LText(
      'İçi sıcak sulu kalır — ilk ısırıkta dikkat et. Worcester tarzı sosla '
          've lahanayla servis edilir.',
      'The inside stays hot and juicy — mind the first bite. Served with '
          'Worcester-style sauce and shredded cabbage.',
    ),
    whereToFind: LText(
      'Kasap dükkanları, konbini, tonkatsu lokantalarının yan menüsü.',
      'Butcher shops, konbini, the side menu at tonkatsu restaurants.',
    ),
  ),

  JapaneseDish(
    id: 'chicken-nanban',
    name: 'Chicken nanban',
    nameJa: 'チキン南蛮',
    romaji: 'Chikin nanban',
    emoji: '🍗',
    category: DishCategory.fried,
    summary: LText(
      'Kızarmış tavuğun tatlı-ekşi sirke sosuna batırılıp üstüne tartar sos '
          'dökülmesi. Miyazaki bölgesinin ihraç ettiği en ünlü tabağı.',
      'Fried chicken dipped in a sweet-sour vinegar sauce, then topped with '
          'tartar sauce. Miyazaki\'s most famous export dish.',
    ),
    priceMinJpy: 700,
    priceMaxJpy: 1600,
    ingredients: {
      DishIngredient.chicken: IngredientChance.always,
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.egg: IngredientChance.always,
      DishIngredient.soy: IngredientChance.usually,
    },
    howToEat: LText(
      'Tartar sosu üstte kalır, karıştırmadan üstten alıp tavukla birlikte '
          'yenir. Teishoku setinin parçası olarak da gelir.',
      'The tartar sauce sits on top — scoop it up with the chicken rather '
          'than mixing it in. Often served as part of a teishoku set.',
    ),
    whereToFind: LText(
      'Miyazaki mutfağı lokantaları, aile restoranı zincirleri.',
      'Miyazaki-cuisine restaurants, family restaurant chains.',
    ),
  ),

  JapaneseDish(
    id: 'age-dashi-tofu',
    name: 'Age-dashi tofu',
    nameJa: '揚げ出し豆腐',
    romaji: 'Agedashi tōfu',
    emoji: '🍲',
    category: DishCategory.fried,
    summary: LText(
      'İnce nişastaya bulanıp kızartılmış tofunun sıcak dashi sosunda '
          'servis edilmesi. Görünüşte hafif ve vejetaryen ama değildir.',
      'Tofu lightly coated in starch and fried, served in a hot dashi-based '
          'sauce. Looks light and vegetarian — it is not.',
    ),
    priceMinJpy: 400,
    priceMaxJpy: 900,
    ingredients: {
      DishIngredient.dashi: IngredientChance.always,
      DishIngredient.fish: IngredientChance.usually,
      DishIngredient.soy: IngredientChance.always,
      DishIngredient.gluten: IngredientChance.sometimes,
    },
    watchOut: LText(
      'Tofu bitkiseldir ama içine battığı sos ve üstüne serpilen katsuobushi '
          '(kurutulmuş balık) pulları balık kaynaklıdır — bu Japonya\'nın en '
          'yanıltıcı "vejetaryen" tabaklarından biri.',
      'The tofu itself is plant-based, but the sauce it sits in and the '
          'katsuobushi (dried fish) flakes on top are fish-derived — one of '
          'Japan\'s most misleading "vegetarian" dishes.',
    ),
    howToEat: LText(
      'Çubukla, sosu tofuyla birlikte kaşıklayarak; üstündeki rendelenmiş '
          'turp ve yeşil soğan tofuyla birlikte yenir.',
      'With chopsticks, spooning the sauce along with the tofu; the grated '
          'radish and spring onion on top are eaten together with it.',
    ),
    whereToFind: LText(
      'İzakaya, teishoku lokantaları, geleneksel Japon restoranları.',
      'Izakaya, teishoku diners, traditional Japanese restaurants.',
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
    id: 'sukiyaki',
    name: 'Sukiyaki',
    nameJa: 'すき焼き',
    romaji: 'Sukiyaki',
    emoji: '🍲',
    category: DishCategory.hotpot,
    summary: LText(
      'İnce sığır dilimleri, tofu, pırasa ve shirataki eriştesinin tatlı '
          'soya-mirin suyunda (warishita) pişirilmesi; her lokma çiğ '
          'çırpılmış yumurtaya batırılır.',
      'Thin beef slices, tofu, leeks and shirataki noodles simmered in a '
          'sweet soy-mirin broth (warishita); each bite is dipped in raw '
          'beaten egg.',
    ),
    priceMinJpy: 2500,
    priceMaxJpy: 9000,
    ingredients: {
      DishIngredient.beef: IngredientChance.always,
      DishIngredient.soy: IngredientChance.always,
      DishIngredient.cookingAlcohol: IngredientChance.always,
      DishIngredient.egg: IngredientChance.usually,
      DishIngredient.gluten: IngredientChance.sometimes,
    },
    watchOut: LText(
      'Yumurdaki çiğdir — bazı ülkelerde alışılmadık bir uygulama; '
          'istemiyorsan pişmiş servis edilip edilmediğini sor. Warishita '
          'her zaman mirin/sake içerir.',
      'The egg dip is raw — an unusual practice for some visitors; ask '
          'whether a cooked option exists if you would rather skip it. The '
          'warishita broth always contains mirin/sake.',
    ),
    howToEat: LText(
      'Eti kısa süre suya batırıp hemen çıkar, sonra çiğ yumurdaya batırıp '
          'ye. Sonunda kalan suya erişte/pirinç eklenerek bitirilir.',
      'Dip the meat briefly in the broth, pull it out quickly, then dip it '
          'in the raw egg. At the end, noodles or rice are added to the '
          'leftover broth to finish the meal.',
    ),
    whereToFind: LText(
      'Bağımsız sukiyaki lokantaları, özel gün yemeği olarak evde de '
          'yapılır.',
      'Dedicated sukiyaki restaurants; also made at home for special '
          'occasions.',
    ),
  ),

  JapaneseDish(
    id: 'oden',
    name: 'Oden',
    nameJa: 'おでん',
    romaji: 'Oden',
    emoji: '🍢',
    category: DishCategory.hotpot,
    summary: LText(
      'Balık ezmesi köfteleri, beyaz turp, konyak (konjac) ve haşlanmış '
          'yumurtanın hafif dashi suyunda uzun süre kaynatılması. Kışın '
          'konbini kasasının yanında da satılır.',
      'Fish-cake dumplings, daikon radish, konjac and boiled eggs simmered '
          'for a long time in a light dashi broth. Sold right at the konbini '
          'register in winter.',
    ),
    priceMinJpy: 150,
    priceMaxJpy: 900,
    ingredients: {
      DishIngredient.dashi: IngredientChance.always,
      DishIngredient.fish: IngredientChance.always,
      DishIngredient.egg: IngredientChance.usually,
      DishIngredient.soy: IngredientChance.usually,
      DishIngredient.gluten: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Konbini\'de istediğin parçaları kase içine seçip aldırırsın; hardal '
          '(karashi) yanında ister sürer ister sürmezsin.',
      'At a konbini you point to the pieces you want and they go in a bowl '
          'for you; you can add or skip the mustard (karashi) on the side.',
    ),
    watchOut: LText(
      'Balık ezmesi köfteleri (chikuwa, hanpen) ve dashi kendisi balık '
          'kaynaklıdır; sebze görünse de bütün kase paylaşımlı aynı suda '
          'kaynar.',
      'The fish-cake dumplings (chikuwa, hanpen) and the dashi itself are '
          'fish-derived; even the vegetables simmer in the same shared '
          'broth.',
    ),
    whereToFind: LText(
      'Konbini kasasının yanı (kış), özel oden lokantaları, festival '
          'tezgahları.',
      'By the konbini register (winter), dedicated oden restaurants, '
          'festival stalls.',
    ),
  ),

  JapaneseDish(
    id: 'chanko-nabe',
    name: 'Chanko nabe',
    nameJa: 'ちゃんこ鍋',
    romaji: 'Chanko nabe',
    emoji: '🍲',
    category: DishCategory.hotpot,
    summary: LText(
      'Sumo güreşçilerinin beslenme kültüründen gelen tencere yemeği: '
          'tavuk/balık köftesi, tofu ve bol sebze, tavuk suyu ya da dashi '
          'bazlı miso/soya çorbasında. Geleneksel olarak dört bacaklı '
          'hayvan eti (sığır/domuz) uğursuz sayılıp kullanılmaz.',
      'A hot pot from sumo wrestlers\' eating culture: chicken or fish '
          'meatballs, tofu and lots of vegetables in a chicken-stock or '
          'dashi-based miso/soy soup. Traditionally, four-legged animal meat '
          '(beef/pork) is considered unlucky and left out.',
    ),
    priceMinJpy: 1500,
    priceMaxJpy: 4000,
    ingredients: {
      // Geleneksel olarak tavuk (iki bacak = ayakta durmak/kazanmak) baskın
      // ama tek başına evrensel değil — bazı chanko fasılları balık-ağırlıklı
      // ya da modern/ticari yerlerde tamamen farklı kurulabiliyor.
      DishIngredient.chicken: IngredientChance.usually,
      DishIngredient.fish: IngredientChance.sometimes,
      DishIngredient.dashi: IngredientChance.sometimes,
      DishIngredient.soy: IngredientChance.usually,
      DishIngredient.cookingAlcohol: IngredientChance.sometimes,
      // watchOut zaten bunu söylüyor ama malzeme haritasında hiç yoktu —
      // motor bu riski hiçbir zaman helal/vejetaryen kullanıcıya göstermezdi.
      DishIngredient.pork: IngredientChance.sometimes,
      DishIngredient.beef: IngredientChance.sometimes,
    },
    watchOut: LText(
      'Geleneksel tarif sığır/domuz kullanmaz ama her sumo ahırının kendi '
          'reçetesi vardır — modern/ticari yerlerde dört bacaklı et de '
          'eklenebilir; menüde sor.',
      'The traditional recipe skips beef and pork, but every sumo stable '
          'has its own recipe — modern or commercial versions may add '
          'four-legged meat too; ask about the menu.',
    ),
    howToEat: LText(
      'Ortak kazandan kendi kasene alırsın; sonunda kalan suya pirinç veya '
          'erişte eklenip ochazuke/zosui gibi bitirilir.',
      'You serve yourself from the shared pot into your own bowl; at the '
          'end, rice or noodles are added to the leftover broth to finish, '
          'like an ochazuke or zosui.',
    ),
    whereToFind: LText(
      'Sumo ahırlarına yakın Tokyo\'daki (Ryōgoku) özel chanko lokantaları.',
      'Dedicated chanko restaurants near sumo stables in Tokyo (Ryōgoku).',
    ),
  ),

  JapaneseDish(
    id: 'motsunabe',
    name: 'Motsunabe',
    nameJa: 'もつ鍋',
    romaji: 'Motsunabe',
    emoji: '🍲',
    category: DishCategory.hotpot,
    summary: LText(
      'Fukuoka\'nın imza tenceresi: sığır/domuz sakatatı, lahana ve bol '
          'kuru soğan yeşiliyle miso veya soya bazlı suda kaynatılır. Yoğun '
          've keskin aromalı.',
      'Fukuoka\'s signature pot: beef or pork offal simmered with cabbage '
          'and plenty of garlic chives in a miso- or soy-based broth. Rich '
          'and pungent.',
    ),
    priceMinJpy: 1800,
    priceMaxJpy: 4500,
    ingredients: {
      DishIngredient.beef: IngredientChance.usually,
      DishIngredient.pork: IngredientChance.sometimes,
      DishIngredient.soy: IngredientChance.usually,
      // Otantik Hakata usulü tarifler (Just One Cookbook, Sudachi vb.)
      // dashi'yi (genelde tavuk suyuyla birlikte) suyun tabanı olarak
      // kullanır — istisna değil.
      DishIngredient.dashi: IngredientChance.usually,
      DishIngredient.cookingAlcohol: IngredientChance.usually,
      // Kendi howToEat'imiz "çampon eriştesiyle bitirme yerel gelenek"
      // diyor — bu gluten demek, nadir bir olasılık değil.
      DishIngredient.gluten: IngredientChance.usually,
    },
    howToEat: LText(
      'Sakatat uzun kaynatılır, hemen yenmez — birkaç dakika beklenir. '
          'Sonunda çampon eriştesi ekleyip bitirmek (shime) yerel bir '
          'gelenek.',
      'The offal simmers a while — it is not eaten right away, give it a '
          'few minutes. Finishing with champon noodles added to the broth '
          '(shime) is a local tradition.',
    ),
    whereToFind: LText(
      'Fukuoka\'da (Hakata) her yerde; büyük şehirlerde Kyushu mutfağı '
          'lokantaları.',
      'Everywhere in Fukuoka (Hakata); Kyushu-cuisine restaurants in big '
          'cities.',
    ),
  ),

  JapaneseDish(
    id: 'yosenabe',
    name: 'Yosenabe',
    nameJa: '寄せ鍋',
    romaji: 'Yosenabe',
    emoji: '🍲',
    category: DishCategory.hotpot,
    summary: LText(
      '"Her şey tenceresi": tavuk, balık, karides, tofu ve bol sebzenin '
          'dashi bazlı hafif suda birlikte kaynatılması. Kış aylarının en '
          'aile dostu tenceresi.',
      'The "everything pot": chicken, fish, shrimp, tofu and plenty of '
          'vegetables simmered together in a light dashi-based broth. The '
          'most family-friendly hot pot of winter.',
    ),
    priceMinJpy: 1500,
    priceMaxJpy: 4000,
    ingredients: {
      DishIngredient.dashi: IngredientChance.always,
      DishIngredient.chicken: IngredientChance.usually,
      DishIngredient.fish: IngredientChance.usually,
      DishIngredient.shellfish: IngredientChance.usually,
      DishIngredient.soy: IngredientChance.usually,
      // Standart yosenabe suyu dashi+sake+mirin+soyadır; sake "seafood/etli
      // nabe'de neredeyse her zaman kullanılır" diye belgeleniyor.
      DishIngredient.cookingAlcohol: IngredientChance.usually,
      DishIngredient.gluten: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Herkes ortak kazandan kendi kasesine alır; malzeme bitene kadar '
          'ekleme yapılır, en son suya pirinç/erişte katılır.',
      'Everyone serves themselves from the shared pot; ingredients are '
          'topped up as they run out, and rice or noodles finish the broth '
          'at the end.',
    ),
    whereToFind: LText(
      'Ev sofraları, izakaya\'ların kış menüsü, aile restoranı zincirleri.',
      'Home tables, the winter menu at izakaya, family restaurant chains.',
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
      // dashi:always zaten balık suyu riskini kapsıyor; standart wakame+tofu
      // misoshiru'da et olarak balık PARÇASI istisna, kural değil (bölgesel/
      // deniz-ürünlü versiyonlar ayrı).
      DishIngredient.fish: IngredientChance.sometimes,
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

  JapaneseDish(
    id: 'ikayaki',
    name: 'Ikayaki',
    nameJa: 'イカ焼き',
    romaji: 'Ikayaki',
    emoji: '🦑',
    category: DishCategory.street,
    summary: LText(
      'Bütün ahtapotgil (kalamar/mürekkep balığı) şişe geçirilip soya '
          'sosuyla fırçalanarak ızgara edilmesi. Festival tezgahlarının '
          'kokusu.',
      'A whole squid or cuttlefish skewered and grilled while being basted '
          'with soy sauce. The signature smell of a festival stall.',
    ),
    priceMinJpy: 400,
    priceMaxJpy: 900,
    ingredients: {
      DishIngredient.shellfish: IngredientChance.always,
      DishIngredient.soy: IngredientChance.always,
      // Fırçalanan standart soya sosu (koikuchi shoyu) tamari değilse
      // buğday içerir — soya fırçalama zaten tanımlayıcı hazırlık.
      DishIngredient.gluten: IngredientChance.usually,
    },
    howToEat: LText(
      'Kağıda sarılı verilir, şişten ya da doğrudan elle koparıp yenir; '
          'ayaküstü festival yürüyüşünde yaygın.',
      'Handed over wrapped in paper; torn off the skewer or eaten by hand. '
          'Common to eat while walking a festival.',
    ),
    whereToFind: LText(
      'Festival tezgahları, sahil kentlerindeki balık pazarları.',
      'Festival stalls, fish markets in coastal towns.',
    ),
  ),

  JapaneseDish(
    id: 'senbei',
    name: 'Senbei',
    nameJa: '煎餅',
    romaji: 'Senbei',
    emoji: '🍘',
    category: DishCategory.street,
    summary: LText(
      'Pirinç unundan yapılıp fırınlanmış/ızgara edilmiş çıtır kraker; en '
          'bilineni soya sosuyla glazelenir, ama tuzlu (shio) ya da şekerli '
          '(zarame) soyasız çeşitler de yaygın. Bazı çeşitleri karides tozu '
          'içerir.',
      'Crisp rice crackers, baked or grilled; the best-known kind is glazed '
          'with soy sauce, but plain salted (shio) or sugar-glazed (zarame) '
          'soy-free versions are also common. Some varieties contain shrimp '
          'powder.',
    ),
    priceMinJpy: 100,
    priceMaxJpy: 500,
    ingredients: {
      // Senbei geniş bir kategori: shio (tuzlu) ve zarame (şekerli) gibi
      // soyasız çeşitler de yaygın satılıyor — "her zaman" soya yanlış.
      DishIngredient.soy: IngredientChance.usually,
      // Soya glazesi varsa (en bilinen shoyu senbei) standart soya sosu
      // buğday içerir; gluten riski soyayla birlikte gider.
      DishIngredient.gluten: IngredientChance.usually,
      DishIngredient.shellfish: IngredientChance.sometimes,
    },
    watchOut: LText(
      '"Ebi senbei" (karidesli) çok popülerdir ve paket üstünde ayırt '
          'etmesi kolay değildir; kabuklu deniz ürünü hassasiyetin varsa '
          'içindekiler listesine bak.',
      '"Ebi senbei" (shrimp) is very popular and not always easy to spot on '
          'the package; check the ingredient list if you have a shellfish '
          'concern.',
    ),
    howToEat: LText(
      'Elden yenir, çay eşliğinde. Bazı tapınak/turistik bölgelerde "yaki-'
          'senbei" tezgahında sıcak, taze bastırılmış hâli bulunur.',
      'Eaten by hand, with tea. In some temple/tourist areas you can find '
          'freshly pressed, hot "yaki-senbei" at a stall.',
    ),
    whereToFind: LText(
      'Tapınak yolları, konbini, hediyelik dükkanları.',
      'Temple approaches, konbini, souvenir shops.',
    ),
    veganVersionExists: true,
  ),

  JapaneseDish(
    id: 'dango',
    name: 'Dango (mitarashi)',
    nameJa: 'みたらし団子',
    romaji: 'Mitarashi dango',
    emoji: '🍡',
    category: DishCategory.street,
    summary: LText(
      'Pirinç unundan yapılan yuvarlak toplar şişe dizilip tatlı-tuzlu '
          'soya sosuna (mitarashi) batırılır. Tatlı ama Batı standardına '
          'göre hafif tuzlu bir tatlı sayılabilir.',
      'Round balls of rice flour dough, skewered and glazed with a sweet-'
          'savoury soy sauce (mitarashi). Sweet, but by Western standards '
          'almost a savoury treat.',
    ),
    priceMinJpy: 100,
    priceMaxJpy: 400,
    ingredients: {
      DishIngredient.soy: IngredientChance.always,
      // Mitarashi glazesi soyayla gelir; standart shoyu buğday içerir —
      // gluten riski soya glazesine bağlı, nadir bir istisna değil.
      DishIngredient.gluten: IngredientChance.usually,
    },
    variants: [
      DishVariant(
        name: 'Anko dango',
        nameJa: 'あんこ団子',
        note: LText(
          'Soya sosu yerine tatlı fasulye ezmesiyle kaplı — tamamen '
              'bitkisel. Hamurun kendisi pirinç unundan (mochiko), buğday '
              'içermez.',
          'Coated in sweet bean paste instead of soy glaze — fully '
              'plant-based. The dough itself is rice flour (mochiko), no '
              'wheat.',
        ),
        // Bu türde soya glazesi YOK, dolayısıyla ondan gelen gluten de yok.
        // IngredientChance.none, ana yemekten kalıtılan malzemeyi açıkça
        // KALDIRIR — boş harita ({}) burada işe yaramazdı, çünkü
        // effectiveIngredients boş override'ı "hiç override yok" sayıp
        // ana yemeğin soya/gluten değerlerini olduğu gibi bırakırdı.
        ingredients: {
          DishIngredient.soy: IngredientChance.none,
          DishIngredient.gluten: IngredientChance.none,
        },
      ),
    ],
    howToEat: LText(
      'Şişten doğrudan ısırılır; tapınak yolu boyunca yürürken yenmesi '
          'yaygın kabul görür (diğer yiyeceklerin aksine).',
      'Bitten straight off the skewer; unlike most street food, eating it '
          'while strolling a temple approach is widely accepted.',
    ),
    whereToFind: LText(
      'Tapınak yolları, festival tezgahları, geleneksel tatlı dükkanları.',
      'Temple approaches, festival stalls, traditional sweet shops.',
    ),
    veganVersionExists: true,
  ),

  JapaneseDish(
    id: 'yaki-imo',
    name: 'Yaki-imo',
    nameJa: '焼き芋',
    romaji: 'Yaki-imo',
    emoji: '🍠',
    category: DishCategory.street,
    summary: LText(
      'Bütün tatlı patatesin taş/odun ateşinde ağır ağır kavrulması. '
          'Kışın gezici satıcı kamyonetlerinin anons sesiyle tanınır.',
      'A whole sweet potato slow-roasted over stone or wood embers. Known '
          'in winter by the announcement calls of roaming vendor trucks.',
    ),
    priceMinJpy: 300,
    priceMaxJpy: 800,
    ingredients: {},
    howToEat: LText(
      'Sıcak kağıda sarılı verilir; ikiye bölüp elle, kabuğuyla birlikte de '
          'yenebilir.',
      'Handed over wrapped in hot paper; split in half and eaten by hand, '
          'skin and all if you like.',
    ),
    whereToFind: LText(
      'Kış aylarında gezici satıcı kamyonetleri, konbini, süpermarket '
          'fırın reyonu.',
      'Roaming vendor trucks in winter, konbini, supermarket oven-food '
          'aisles.',
    ),
    veganVersionExists: true,
  ),

  JapaneseDish(
    id: 'age-mochi',
    name: 'Age-mochi',
    nameJa: '揚げ餅',
    romaji: 'Age-mochi',
    emoji: '🍘',
    category: DishCategory.street,
    summary: LText(
      'Küçük pirinç keki (mochi) parçalarının kızartılıp soya sosu ve '
          'yosunla kaplanması. Dışı çıtır, içi yapışkan.',
      'Small pieces of rice cake (mochi), deep-fried and coated in soy '
          'sauce and seaweed. Crisp outside, chewy inside.',
    ),
    priceMinJpy: 200,
    priceMaxJpy: 600,
    ingredients: {
      DishIngredient.soy: IngredientChance.always,
      // Standart soya kaplaması buğday içerir; dango'daki aynı mantık.
      DishIngredient.gluten: IngredientChance.usually,
    },
    howToEat: LText(
      'Kürdanla ya da elle, sıcakken; içi çok yapışkan olduğu için küçük '
          'ısırıklar tercih edilir.',
      'With a toothpick or by hand, while hot; small bites are wise since '
          'the inside is very sticky.',
    ),
    whereToFind: LText(
      'Festival tezgahları, konbini, geleneksel tatlı dükkanları.',
      'Festival stalls, konbini, traditional sweet shops.',
    ),
    veganVersionExists: true,
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

  JapaneseDish(
    id: 'dorayaki',
    name: 'Dorayaki',
    nameJa: 'どら焼き',
    romaji: 'Dorayaki',
    emoji: '🥞',
    category: DishCategory.sweets,
    summary: LText(
      'İki küçük pankek arasına tatlı fasulye ezmesi (anko) konması. '
          'Doraemon\'un en sevdiği yiyecek olarak tanınır.',
      'Sweet bean paste (anko) sandwiched between two small pancakes. '
          'Famous as Doraemon\'s favourite food.',
    ),
    priceMinJpy: 150,
    priceMaxJpy: 400,
    ingredients: {
      DishIngredient.egg: IngredientChance.always,
      DishIngredient.gluten: IngredientChance.always,
      DishIngredient.dairy: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Elle, ikiye katlanmış hâliyle doğrudan; genelde tek seferde bitirilir.',
      'By hand, already folded like a sandwich; usually finished in one go.',
    ),
    whereToFind: LText(
      'Geleneksel tatlı dükkanları, konbini, süpermarket paketli reyonu.',
      'Traditional sweet shops, konbini, supermarket packaged snack aisle.',
    ),
  ),

  JapaneseDish(
    id: 'daifuku',
    name: 'Daifuku',
    nameJa: '大福',
    romaji: 'Daifuku',
    emoji: '🍡',
    category: DishCategory.sweets,
    summary: LText(
      'Yumuşak pirinç keki (mochi) içine tatlı fasulye ezmesi doldurulması; '
          'bazı versiyonlarda içine bütün çilek eklenir (ichigo daifuku).',
      'Soft rice cake (mochi) filled with sweet bean paste; some versions '
          'add a whole strawberry inside (ichigo daifuku).',
    ),
    priceMinJpy: 120,
    priceMaxJpy: 350,
    ingredients: {},
    variants: [
      DishVariant(
        name: 'Ichigo daifuku',
        nameJa: '苺大福',
        note: LText(
          'İçine bütün çilek eklenir; malzemeler aynı, tamamen bitkisel.',
          'A whole strawberry is added inside; same ingredients, fully '
              'plant-based.',
        ),
        ingredients: {},
      ),
    ],
    howToEat: LText(
      'Elle, tek lokmada ya da ikiye bölerek; nişasta tozu elin üstünde '
          'kalabilir, o normal.',
      'By hand, in one bite or split in half; a dusting of starch on your '
          'fingers is normal.',
    ),
    whereToFind: LText(
      'Geleneksel tatlı dükkanları (wagashi-ya), konbini, süpermarketler.',
      'Traditional sweet shops (wagashi-ya), konbini, supermarkets.',
    ),
    veganVersionExists: true,
  ),

  JapaneseDish(
    id: 'kakigori',
    name: 'Kakigori',
    nameJa: 'かき氷',
    romaji: 'Kakigōri',
    emoji: '🍧',
    category: DishCategory.sweets,
    summary: LText(
      'İnce ince kazınmış buzun üzerine şurup (matcha, çilek, kavun) '
          'dökülmesi. Yazın en soğutucu tatlı; bazı yerlerde yoğunlaştırılmış '
          'süt eklenir.',
      'Finely shaved ice topped with syrup (matcha, strawberry, melon). The '
          'coldest dessert of summer; some places add condensed milk.',
    ),
    // Butik/gurme kakigori dalgası fiyatı ¥1500–3000+'a taşıdı; festival
    // usulü sade kakigori hâlâ alt sınırda kalıyor.
    priceMinJpy: 500,
    priceMaxJpy: 2800,
    ingredients: {
      DishIngredient.dairy: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Kaşıkla, üstten aşağıya; buz erimeden bitirmek için hızlı yenir, '
          'sosyal bir masa yemeği değildir.',
      'With a spoon, from top down; eaten quickly before it melts, not '
          'really a leisurely table dessert.',
    ),
    whereToFind: LText(
      'Yaz festivalleri, kafeler, geleneksel tatlı dükkanları.',
      'Summer festivals, cafés, traditional sweet shops.',
    ),
    veganVersionExists: true,
  ),

  JapaneseDish(
    id: 'anmitsu',
    name: 'Anmitsu',
    nameJa: '餡蜜',
    romaji: 'Anmitsu',
    emoji: '🍮',
    category: DishCategory.sweets,
    summary: LText(
      'Agar jölesi küpleri, tatlı fasulye ezmesi ve meyvenin kara şeker '
          'şurubuyla (kuromitsu) servis edilmesi. Bazı yerlerde üstüne bir '
          'top dondurma eklenir.',
      'Cubes of agar jelly, sweet bean paste and fruit, served with a black '
          'sugar syrup (kuromitsu). Some places add a scoop of ice cream on '
          'top.',
    ),
    priceMinJpy: 500,
    priceMaxJpy: 1200,
    ingredients: {
      DishIngredient.dairy: IngredientChance.sometimes,
    },
    howToEat: LText(
      'Kaşıkla, şurubu her katmana biraz dökerek; dondurma eklenmişse önce '
          'onu yemek gerekmez, karıştırarak yenir.',
      'With a spoon, pouring a little syrup over each layer; if ice cream '
          'is added there is no rule to eat it first — mix as you go.',
    ),
    whereToFind: LText(
      'Geleneksel tatlı dükkanları, kafeler, büyük mağaza tatlı katları.',
      'Traditional sweet shops, cafés, department-store dessert floors.',
    ),
    veganVersionExists: true,
  ),

  JapaneseDish(
    id: 'castella',
    name: 'Castella',
    nameJa: 'カステラ',
    romaji: 'Kasutera',
    emoji: '🍰',
    category: DishCategory.sweets,
    summary: LText(
      'Portekiz kökenli, Nagasaki\'de yerelleşmiş nemli sünger kek. '
          'Yumurta ve bal ağırlıklı, yoğun ve hafif tatlı.',
      'A moist sponge cake of Portuguese origin, made local in Nagasaki. '
          'Heavy on egg and honey, dense and lightly sweet.',
    ),
    priceMinJpy: 200,
    priceMaxJpy: 1500,
    ingredients: {
      DishIngredient.egg: IngredientChance.always,
      DishIngredient.gluten: IngredientChance.always,
    },
    howToEat: LText(
      'Dilimlenip çubuk ya da çatal olmadan elle de yenebilir; genelde bir '
          'kutu hâlinde hediye olarak alınır.',
      'Sliced and can be eaten by hand without a fork; often bought boxed '
          'as a gift.',
    ),
    whereToFind: LText(
      'Nagasaki\'de özel dükkanlar, hediyelik reyonları, süpermarketler.',
      'Dedicated shops in Nagasaki, souvenir counters, supermarkets.',
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
      // Ana yemek genelde et: tonkatsu/shogayaki (domuz), karaage (tavuk)
      // en yaygın teishoku anaları — sadece balık değil.
      DishIngredient.pork: IngredientChance.sometimes,
      DishIngredient.chicken: IngredientChance.sometimes,
      DishIngredient.beef: IngredientChance.sometimes,
      DishIngredient.cookingAlcohol: IngredientChance.sometimes,
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
      // Karaage-kun, tavuklu sandviç/bento kadar yaygın; sadece domuz/balık
      // değil.
      DishIngredient.chicken: IngredientChance.sometimes,
      DishIngredient.beef: IngredientChance.sometimes,
      DishIngredient.fish: IngredientChance.sometimes,
      DishIngredient.shellfish: IngredientChance.sometimes,
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

  JapaneseDish(
    id: 'tamago-kake-gohan',
    name: 'Tamago kake gohan',
    nameJa: '卵かけご飯',
    romaji: 'Tamago kake gohan',
    emoji: '🍚',
    category: DishCategory.breakfast,
    summary: LText(
      'Çiğ yumurdanın sıcak pirincin üzerine kırılıp soya sosuyla '
          'karıştırılması. Japonya\'nın en sade kahvaltısı — sadece iki '
          'malzeme.',
      'A raw egg cracked over hot rice and mixed with soy sauce. Japan\'s '
          'simplest breakfast — just two ingredients.',
    ),
    priceMinJpy: 150,
    priceMaxJpy: 500,
    ingredients: {
      DishIngredient.egg: IngredientChance.always,
      DishIngredient.soy: IngredientChance.always,
    },
    watchOut: LText(
      'Yumurta ÇİĞDİR. Japonya\'da yumurtalar çiğ tüketim için sıkı '
          'denetlenir ama hamilelik/bağışıklık hassasiyetin varsa bunu '
          'bilerek sipariş et.',
      'The egg is RAW. Japanese eggs are strictly inspected for raw '
          'consumption, but order this knowingly if you are pregnant or '
          'immunocompromised.',
    ),
    howToEat: LText(
      'Hızlıca çubukla karıştırıp sıcakken yenir; bekletilirse yumurta '
          'pişmeye başlar ve doku değişir.',
      'Mix quickly with chopsticks and eat while hot; if left too long the '
          'egg starts to cook and the texture changes.',
    ),
    whereToFind: LText(
      'Ev sofraları, bazı teishoku lokantalarının kahvaltı menüsü.',
      'Home tables; the breakfast menu at some teishoku diners.',
    ),
  ),

  JapaneseDish(
    id: 'natto-gohan',
    name: 'Natto gohan',
    nameJa: '納豆ご飯',
    romaji: 'Nattō gohan',
    emoji: '🍚',
    category: DishCategory.breakfast,
    summary: LText(
      'Fermente soya fasulyesinin (natto) hardal ve soya sosuyla '
          'karıştırılıp sıcak pirince eklenmesi. Kokusu ve yapışkan dokusu '
          'yüzünden Japonların kendi içinde bile "sevenler/sevmeyenler" '
          'ayrımı vardır.',
      'Fermented soybeans (natto) mixed with mustard and soy sauce, served '
          'over hot rice. Even among Japanese people it famously divides '
          'into "loves it / hates it" camps because of the smell and '
          'sticky texture.',
    ),
    priceMinJpy: 150,
    priceMaxJpy: 500,
    ingredients: {
      DishIngredient.soy: IngredientChance.always,
      DishIngredient.dashi: IngredientChance.sometimes,
    },
    watchOut: LText(
      'Paketle gelen küçük sos poşetinde bazen dashi (balık suyu) özütü '
          'bulunur; sadece soya sosuyla karıştırılan natto vejetaryendir, '
          'paket sosu vejetaryen OLMAYABİLİR.',
      'The little sauce packet that comes with packaged natto sometimes '
          'contains dashi (fish stock) extract; natto mixed with plain soy '
          'sauce is vegetarian, but the packet sauce may NOT be.',
    ),
    howToEat: LText(
      'Çubukla köpürene kadar hızlıca karıştırılır, sonra pirince eklenir. '
          'Uzun uzun karıştırmak lifleri artırır — bu istenen bir şeydir.',
      'Stir briskly with chopsticks until it turns frothy, then add to the '
          'rice. Stirring a long time increases the stringiness — that is '
          'considered desirable.',
    ),
    whereToFind: LText(
      'Ev sofraları, konbini (küçük paketler hâlinde), teishoku setleri.',
      'Home tables; konbini (in small packets); teishoku sets.',
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
