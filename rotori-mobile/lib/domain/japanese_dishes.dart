// Rotori Eats — Japon yemekleri rehberi (saf Dart, offline).
//
// ## Neden yemek, restoran değil
//
// Restoran listesi bayatlar: mekan kapanır, fiyat kayar, sertifika iptal olur.
// Doğrulanmamış 27 kayıt ne ürün ne de güvenilir. Yemek bilgisi ise sabittir —
// tonkotsu rameninin domuz suyu bazlı olduğu değişmez, dashi'nin balık suyu
// olduğu değişmez.
//
// Ve asıl mesele şu: **neyi yiyebileceğini bilen gezgin her yerde yiyebilir.**
// Helal bir kullanıcıya 27 restoran adı vermek onu o 27 mekana hapseder;
// "ramen bazları genelde domuzdur, ama tori paitan tavuktur ve şunu sorman
// gerekir" demek Japonya'nın tamamını açar.
//
// ## Dürüstlük kuralı
//
// Bir malzemenin bulunma ihtimali [IngredientChance] ile derecelendirilir.
// "Her zaman" ile "bazen" arasındaki fark kullanıcının sorup sormayacağını
// belirler; ikisini birbirine karıştırmak ya gereksiz korkutur ya da yanlış
// güven verir. Emin olunmayan malzeme [IngredientChance.sometimes] işaretlenir
// ve kullanıcı sormaya yönlendirilir.

import 'localized_text.dart';

// ---------------------------------------------------------------------------
// Malzemeler
// ---------------------------------------------------------------------------

/// Diyet kararını etkileyen malzeme sınıfları.
enum DishIngredient {
  pork,
  beef,
  chicken,
  fish,
  shellfish,

  /// Dashi — balık (katsuobushi) veya deniz yosunu suyu. Japon mutfağının
  /// her yerinde ve GÖRÜNMEZ; vejetaryenlerin en sık düştüğü tuzak.
  dashi,

  /// Mirin / pişirme sakesi. Pişirmede alkol büyük ölçüde uçar ama helal
  /// hassasiyeti olan için yine de belirtilmesi gerekir.
  cookingAlcohol,

  egg,
  dairy,
  gluten,
  soy,
  sesame,
  peanut,
}

extension DishIngredientX on DishIngredient {
  String get emoji => switch (this) {
        DishIngredient.pork => '🐷',
        DishIngredient.beef => '🐄',
        DishIngredient.chicken => '🐔',
        DishIngredient.fish => '🐟',
        DishIngredient.shellfish => '🦐',
        DishIngredient.dashi => '🍥',
        DishIngredient.cookingAlcohol => '🍶',
        DishIngredient.egg => '🥚',
        DishIngredient.dairy => '🥛',
        DishIngredient.gluten => '🌾',
        DishIngredient.soy => '🫘',
        DishIngredient.sesame => '🌰',
        DishIngredient.peanut => '🥜',
      };

  LText get label => switch (this) {
        DishIngredient.pork => const LText('Domuz', 'Pork'),
        DishIngredient.beef => const LText('Sığır', 'Beef'),
        DishIngredient.chicken => const LText('Tavuk', 'Chicken'),
        DishIngredient.fish => const LText('Balık', 'Fish'),
        DishIngredient.shellfish => const LText('Kabuklu deniz', 'Shellfish'),
        DishIngredient.dashi => const LText('Dashi (balık suyu)', 'Dashi (fish stock)'),
        DishIngredient.cookingAlcohol =>
          const LText('Mirin / pişirme sakesi', 'Mirin / cooking sake'),
        DishIngredient.egg => const LText('Yumurta', 'Egg'),
        DishIngredient.dairy => const LText('Süt ürünü', 'Dairy'),
        DishIngredient.gluten => const LText('Gluten', 'Gluten'),
        DishIngredient.soy => const LText('Soya', 'Soy'),
        DishIngredient.sesame => const LText('Susam', 'Sesame'),
        DishIngredient.peanut => const LText('Yer fıstığı', 'Peanut'),
      };

  /// Menüde/pakette aranacak Japonca yazım. Kullanıcı bunu tanıyarak
  /// kendini koruyabilir — hiçbir restoran listesi bu kadar taşınabilir değil.
  String get japaneseLabel => switch (this) {
        DishIngredient.pork => '豚肉 / ポーク',
        DishIngredient.beef => '牛肉',
        DishIngredient.chicken => '鶏肉',
        DishIngredient.fish => '魚',
        DishIngredient.shellfish => '海老 / 貝',
        DishIngredient.dashi => 'だし / 出汁 / かつお',
        DishIngredient.cookingAlcohol => 'みりん / 料理酒',
        DishIngredient.egg => '卵 / たまご',
        DishIngredient.dairy => '乳 / チーズ',
        DishIngredient.gluten => '小麦',
        DishIngredient.soy => '大豆 / 醤油',
        DishIngredient.sesame => 'ごま',
        DishIngredient.peanut => 'ピーナッツ',
      };
}

/// Bir malzemenin o yemekte bulunma ihtimali.
///
/// Bu derecelendirme kararın kendisidir: `always` "bu yemeği yiyemezsin",
/// `sometimes` ise "sorman gerek" demektir.
enum IngredientChance {
  /// Yemeğin tanımı gereği içinde var.
  always,

  /// Standart tarifte var; istisnası nadir.
  usually,

  /// Mekana/tarife göre değişir — SORULMALI.
  sometimes,

  /// Bu ALT TÜRDE bilinçli olarak YOK — ana yemekten kalıtılan malzemeyi
  /// siler. Sadece [DishVariant.ingredients] içinde kullanılır;
  /// [JapaneseDish.effectiveIngredients] bu değeri gördüğü anda ilgili
  /// malzemeyi sonuçtan tamamen çıkarır. Kalıtımı EKLEME/ÜZERİNE YAZMA
  /// mantığıyla kurduğumuz için "kaldırma" için ayrı bir sinyal gerekiyordu;
  /// boş bir ingredients haritası (`{}`) "override yok" ile "hiçbir şey
  /// yok" arasında ayrım yapamıyordu (bkz. dango → Anko dango).
  none,
}

extension IngredientChanceX on IngredientChance {
  LText get label => switch (this) {
        IngredientChance.always => const LText('her zaman', 'always'),
        IngredientChance.usually => const LText('genelde', 'usually'),
        IngredientChance.sometimes => const LText('bazen', 'sometimes'),
        // effectiveIngredients bunu her zaman filtreler; UI'ya asla ulaşmaz.
        IngredientChance.none => const LText('yok', 'none'),
      };
}

// ---------------------------------------------------------------------------
// Yemek kategorileri
// ---------------------------------------------------------------------------

enum DishCategory {
  noodles,
  rice,
  grilled,
  fried,
  raw,
  hotpot,
  street,
  sweets,
  breakfast,
}

extension DishCategoryX on DishCategory {
  String get emoji => switch (this) {
        DishCategory.noodles => '🍜',
        DishCategory.rice => '🍚',
        DishCategory.grilled => '🔥',
        DishCategory.fried => '🍤',
        DishCategory.raw => '🍣',
        DishCategory.hotpot => '🍲',
        DishCategory.street => '🥟',
        DishCategory.sweets => '🍡',
        DishCategory.breakfast => '🌅',
      };

  LText get label => switch (this) {
        DishCategory.noodles => const LText('Erişteler', 'Noodles'),
        DishCategory.rice => const LText('Pirinç kaseleri', 'Rice bowls'),
        DishCategory.grilled => const LText('Izgara', 'Grilled'),
        DishCategory.fried => const LText('Kızartma', 'Fried'),
        DishCategory.raw => const LText('Çiğ / suşi', 'Raw / sushi'),
        DishCategory.hotpot => const LText('Tencere', 'Hotpot'),
        DishCategory.street => const LText('Sokak lezzeti', 'Street food'),
        DishCategory.sweets => const LText('Tatlı', 'Sweets'),
        DishCategory.breakfast => const LText('Kahvaltı', 'Breakfast'),
      };
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// Bir yemeğin alt türü (ör. ramen → tonkotsu / shoyu / miso).
///
/// Alt türler kritiktir: "ramen yiyemezsin" yanlış, "tonkotsu yiyemezsin ama
/// tori paitan tavuktur" doğrudur.
class DishVariant {
  const DishVariant({
    required this.name,
    required this.nameJa,
    required this.note,
    this.ingredients = const {},
  });

  final String name;
  final String nameJa;
  final LText note;

  /// Alt türe ÖZGÜ malzeme farkları. Ana yemeğinkini ezer.
  final Map<DishIngredient, IngredientChance> ingredients;
}

class JapaneseDish {
  const JapaneseDish({
    required this.id,
    required this.name,
    required this.nameJa,
    required this.romaji,
    required this.emoji,
    required this.category,
    required this.summary,
    required this.priceMinJpy,
    required this.priceMaxJpy,
    required this.ingredients,
    required this.howToEat,
    this.variants = const [],
    this.watchOut,
    this.orderTip,
    this.whereToFind,
    this.veganVersionExists = false,
  });

  final String id;

  /// Latin harfli yaygın ad ("Ramen").
  final String name;

  /// Japonca yazım — menüde tanımak ve göstermek için.
  final String nameJa;

  /// Hepburn okunuş.
  final String romaji;

  final String emoji;
  final DishCategory category;
  final LText summary;

  /// Tipik kişi başı fiyat aralığı (JPY). Bandı geniş tuttuk; kesin fiyat
  /// iddia etmiyoruz.
  final int priceMinJpy;
  final int priceMaxJpy;

  /// Malzeme → bulunma ihtimali.
  final Map<DishIngredient, IngredientChance> ingredients;

  /// Nasıl yenir: sesli çekmek serbest mi, sos nasıl kullanılır, bilet
  /// makinesi var mı. Japonya'da yemeğin yarısı bu.
  final LText howToEat;

  final List<DishVariant> variants;

  /// Gizli risk — "vejetaryen görünür ama dashi vardır" gibi.
  final LText? watchOut;

  /// Sipariş verirken söylenecek/istenecek şey.
  final LText? orderTip;

  /// Nerede bulunur — semt/zincir tipi genel tarif, belirli mekan DEĞİL.
  final LText? whereToFind;

  /// Yaygın olarak vegan/vejetaryen versiyonu bulunabiliyor mu?
  final bool veganVersionExists;

  String get priceBand => '¥${_group(priceMinJpy)}–${_group(priceMaxJpy)}';

  /// Yemeğin (alt tür seçildiyse onun) etkin malzeme haritası.
  ///
  /// [IngredientChance.none] işaretli girişler ana yemekten kalıtılmış
  /// olsa bile sonuçtan ÇIKARILIR — bu, bir alt türün "bu malzeme bende
  /// yok" diyebilmesinin tek yolu (bkz. [IngredientChance.none] dokümanı).
  Map<DishIngredient, IngredientChance> effectiveIngredients([
    DishVariant? variant,
  ]) {
    if (variant == null || variant.ingredients.isEmpty) return ingredients;
    final merged = {...ingredients, ...variant.ingredients};
    merged.removeWhere((_, chance) => chance == IngredientChance.none);
    return merged;
  }
}

String _group(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

// ---------------------------------------------------------------------------
// "Bunu yiyebilir miyim?" motoru
// ---------------------------------------------------------------------------

/// Kullanıcının diyetine göre bir yemeğin durumu.
enum DishVerdict {
  /// Bilinen bir çakışma yok.
  safe,

  /// Mekana göre değişen bir malzeme var — sormalı.
  ask,

  /// Standart hâliyle uygun değil; alt türü/versiyonu olabilir.
  avoid,

  /// Kullanıcı diyet belirtmemiş — hüküm verilmez.
  unknown,
}

extension DishVerdictX on DishVerdict {
  LText get label => switch (this) {
        DishVerdict.safe => const LText('Yiyebilirsin', 'You can eat this'),
        DishVerdict.ask => const LText('Sorman gerek', 'Ask first'),
        DishVerdict.avoid => const LText('Uygun değil', 'Not suitable'),
        DishVerdict.unknown => const LText('Tercih girilmedi', 'No preference set'),
      };

  String get emoji => switch (this) {
        DishVerdict.safe => '✅',
        DishVerdict.ask => '⚠️',
        DishVerdict.avoid => '⛔',
        DishVerdict.unknown => '•',
      };
}

/// Bir yemek + kullanıcı diyeti değerlendirmesinin sonucu.
class DishAssessment {
  const DishAssessment({
    required this.verdict,
    required this.reasons,
    required this.blockers,
  });

  final DishVerdict verdict;

  /// Kullanıcıya gösterilecek gerekçeler (en güçlü önce).
  final List<LText> reasons;

  /// Karara yol açan malzemeler — UI bunları rozet olarak gösterir.
  final List<DishIngredient> blockers;
}

/// Bir malzemenin verilen diyet etiketleriyle çakışıp çakışmadığı.
bool _conflicts(DishIngredient ing, Set<String> diet) {
  final halal = diet.contains('halal');
  final noPork = halal || diet.contains('no_pork');
  final vegan = diet.contains('vegan');
  final vegetarian = vegan || diet.contains('vegetarian');
  final glutenFree = diet.contains('gluten_free');
  final noSeafood = diet.contains('no_seafood');

  switch (ing) {
    case DishIngredient.pork:
      return noPork || vegetarian;
    case DishIngredient.beef:
    case DishIngredient.chicken:
      // Helal kullanıcı için sorun etin kendisi değil, KESİMİ.
      return vegetarian || halal;
    case DishIngredient.fish:
    case DishIngredient.shellfish:
      return vegetarian || noSeafood;
    case DishIngredient.dashi:
      return vegetarian || noSeafood;
    case DishIngredient.cookingAlcohol:
      return halal || diet.contains('no_alcohol');
    case DishIngredient.egg:
    case DishIngredient.dairy:
      return vegan;
    case DishIngredient.gluten:
      return glutenFree;
    case DishIngredient.soy:
    case DishIngredient.sesame:
    case DishIngredient.peanut:
      return false; // alerji ayrı bir eksen; burada karar vermiyoruz
  }
}

/// Çakışan malzeme için kullanıcıya gösterilecek gerekçe.
LText _reasonFor(DishIngredient ing, IngredientChance chance, Set<String> diet) {
  final always = chance == IngredientChance.always;
  switch (ing) {
    case DishIngredient.pork:
      return always
          ? const LText(
              'Domuz eti bu yemeğin tanımında var.',
              'Pork is part of what this dish is.',
            )
          : const LText(
              'Domuz eti ya da domuz suyu içerebilir — mutlaka sor.',
              'May contain pork meat or pork broth — always ask.',
            );
    case DishIngredient.beef:
    case DishIngredient.chicken:
      return diet.contains('halal')
          ? const LText(
              'Et var; kesimin helal olup olmadığını mekana sormalısın.',
              'Contains meat; you need to ask whether the slaughter was halal.',
            )
          : const LText('Et içerir.', 'Contains meat.');
    case DishIngredient.fish:
      return const LText('Balık içerir.', 'Contains fish.');
    case DishIngredient.shellfish:
      return const LText('Kabuklu deniz ürünü içerir.', 'Contains shellfish.');
    case DishIngredient.dashi:
      return always
          ? const LText(
              'Suyu dashi ile yapılır — dashi balık (katsuobushi) suyudur, '
                  'sebzeli görünse de vejetaryen değildir.',
              'The broth is made with dashi — dashi is fish (katsuobushi) stock, '
                  'so it is not vegetarian even when it looks meat-free.',
            )
          : const LText(
              'Dashi kullanılmış olabilir; "dashi nashi" diye sor.',
              'Dashi may be used; ask for "dashi nashi".',
            );
    case DishIngredient.cookingAlcohol:
      return const LText(
        'Mirin ya da pişirme sakesi kullanılır. Pişerken büyük ölçüde uçar '
            'ama hassassan sor.',
        'Mirin or cooking sake is used. Most alcohol cooks off, but ask if you '
            'are strict.',
      );
    case DishIngredient.egg:
      return const LText('Yumurta içerir.', 'Contains egg.');
    case DishIngredient.dairy:
      return const LText('Süt ürünü içerir.', 'Contains dairy.');
    case DishIngredient.gluten:
      return const LText(
        'Buğday içerir; Japonya\'da glutensiz seçenek çok nadirdir.',
        'Contains wheat; gluten-free options are very rare in Japan.',
      );
    case DishIngredient.soy:
    case DishIngredient.sesame:
    case DishIngredient.peanut:
      return ing.label;
  }
}

/// Yemeği kullanıcının beslenme etiketlerine göre değerlendirir.
///
/// [diet] boşsa hüküm verilmez — uydurma bir "uygun" demektense
/// [DishVerdict.unknown] döner ve UI kullanıcıyı tercih girmeye çağırır.
DishAssessment assessDish(
  JapaneseDish dish, {
  Set<String> diet = const {},
  DishVariant? variant,
}) {
  if (diet.isEmpty) {
    return const DishAssessment(
      verdict: DishVerdict.unknown,
      reasons: [],
      blockers: [],
    );
  }

  final ingredients = dish.effectiveIngredients(variant);
  final hardBlockers = <DishIngredient>[];
  final softBlockers = <DishIngredient>[];
  final reasons = <LText>[];

  ingredients.forEach((ing, chance) {
    if (!_conflicts(ing, diet)) return;
    if (chance == IngredientChance.sometimes) {
      softBlockers.add(ing);
    } else {
      hardBlockers.add(ing);
    }
    reasons.add(_reasonFor(ing, chance, diet));
  });

  final verdict = hardBlockers.isNotEmpty
      ? DishVerdict.avoid
      : (softBlockers.isNotEmpty ? DishVerdict.ask : DishVerdict.safe);

  return DishAssessment(
    verdict: verdict,
    reasons: reasons.take(3).toList(growable: false),
    blockers: [...hardBlockers, ...softBlockers],
  );
}

/// Yemeğin, kullanıcının yiyebileceği bir alt türü var mı?
///
/// "Ramen yiyemezsin" demek yerine "tonkotsu olmaz ama tori paitan olur"
/// diyebilmek için.
DishVariant? safeVariantFor(JapaneseDish dish, Set<String> diet) {
  if (diet.isEmpty) return null;
  for (final v in dish.variants) {
    final a = assessDish(dish, diet: diet, variant: v);
    if (a.verdict == DishVerdict.safe || a.verdict == DishVerdict.ask) return v;
  }
  return null;
}
