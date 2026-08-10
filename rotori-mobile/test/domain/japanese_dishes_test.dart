// "Bunu yiyebilir miyim?" motoru + içerik bütünlüğü.
//
// Bu motorun yanlış cevabı dinî/sağlık sonucu doğurur; testler bu yüzden
// kural kural yazıldı. Özellikle iki davranış korunuyor:
//   1. Diyet girilmemişse hüküm VERİLMEZ (uydurma "uygun" yok),
//   2. Malzeme "bazen" ise "uygun değil" değil "sor" denir.

import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/japanese_dishes.dart';
import 'package:japan_trip/domain/localized_text.dart';
import 'package:japan_trip/domain/japanese_dishes_data.dart';

JapaneseDish _dish(Map<DishIngredient, IngredientChance> ingredients) =>
    JapaneseDish(
      id: 't',
      name: 'Test',
      nameJa: 'テスト',
      romaji: 'Tesuto',
      emoji: '🍽️',
      category: DishCategory.rice,
      summary: const LText('tr', 'en'),
      priceMinJpy: 100,
      priceMaxJpy: 200,
      ingredients: ingredients,
      howToEat: const LText('tr', 'en'),
    );

void main() {
  group('assessDish — hüküm', () {
    test('diyet girilmemişse hüküm verilmez', () {
      final a = assessDish(_dish({DishIngredient.pork: IngredientChance.always}));
      expect(a.verdict, DishVerdict.unknown);
      expect(a.reasons, isEmpty);
    });

    test('çakışma yoksa güvenli', () {
      final a = assessDish(
        _dish({DishIngredient.soy: IngredientChance.always}),
        diet: {'halal'},
      );
      expect(a.verdict, DishVerdict.safe);
    });

    test('"her zaman" çakışması uygun değil verir', () {
      final a = assessDish(
        _dish({DishIngredient.pork: IngredientChance.always}),
        diet: {'halal'},
      );
      expect(a.verdict, DishVerdict.avoid);
      expect(a.blockers, contains(DishIngredient.pork));
    });

    test('"bazen" çakışması SOR verir — kesin yasak değil', () {
      final a = assessDish(
        _dish({DishIngredient.pork: IngredientChance.sometimes}),
        diet: {'halal'},
      );
      expect(a.verdict, DishVerdict.ask);
    });

    test('"genelde" çakışması uygun değil sayılır', () {
      final a = assessDish(
        _dish({DishIngredient.pork: IngredientChance.usually}),
        diet: {'no_pork'},
      );
      expect(a.verdict, DishVerdict.avoid);
    });
  });

  group('diyet kuralları', () {
    test('helal kullanıcı için et KESİMİ sorun — tavuk da uygun değil', () {
      final a = assessDish(
        _dish({DishIngredient.chicken: IngredientChance.always}),
        diet: {'halal'},
      );
      expect(a.verdict, DishVerdict.avoid);
    });

    test('sadece domuzsuz diyen için tavuk sorun değil', () {
      final a = assessDish(
        _dish({DishIngredient.chicken: IngredientChance.always}),
        diet: {'no_pork'},
      );
      expect(a.verdict, DishVerdict.safe);
    });

    test('helal kullanıcı için mirin/pişirme sakesi çakışır', () {
      final a = assessDish(
        _dish({DishIngredient.cookingAlcohol: IngredientChance.always}),
        diet: {'halal'},
      );
      expect(a.verdict, DishVerdict.avoid);
    });

    test('vejetaryen için dashi çakışır — gizli balık suyu', () {
      final a = assessDish(
        _dish({DishIngredient.dashi: IngredientChance.always}),
        diet: {'vegetarian'},
      );
      expect(a.verdict, DishVerdict.avoid);
      expect(a.blockers, contains(DishIngredient.dashi));
    });

    test('vejetaryen yumurta/sütü yer, vegan yemez', () {
      final dish = _dish({DishIngredient.egg: IngredientChance.always});
      expect(assessDish(dish, diet: {'vegetarian'}).verdict, DishVerdict.safe);
      expect(assessDish(dish, diet: {'vegan'}).verdict, DishVerdict.avoid);
    });

    test('vegan aynı zamanda vejetaryen kısıtlarını taşır', () {
      final a = assessDish(
        _dish({DishIngredient.fish: IngredientChance.always}),
        diet: {'vegan'},
      );
      expect(a.verdict, DishVerdict.avoid);
    });

    test('glutensiz için buğday çakışır', () {
      final a = assessDish(
        _dish({DishIngredient.gluten: IngredientChance.always}),
        diet: {'gluten_free'},
      );
      expect(a.verdict, DishVerdict.avoid);
    });

    test('susam/soya diyet kararını etkilemez', () {
      final a = assessDish(
        _dish({
          DishIngredient.soy: IngredientChance.always,
          DishIngredient.sesame: IngredientChance.always,
        }),
        diet: {'vegan', 'halal', 'gluten_free'},
      );
      expect(a.verdict, DishVerdict.safe);
    });
  });

  group('alt türler', () {
    test('alt tür ana yemeğin malzemesini ezer', () {
      final ramen = kJapaneseDishes.firstWhere((d) => d.id == 'ramen');
      final tonkotsu = ramen.variants.firstWhere((v) => v.name == 'Tonkotsu');
      final vegan = ramen.variants.firstWhere((v) => v.name == 'Vegan ramen');

      expect(
        assessDish(ramen, diet: {'no_pork'}, variant: tonkotsu).verdict,
        DishVerdict.avoid,
      );
      // Vegan ramende domuz "bazen"e düşer → yasak değil, sor.
      expect(
        assessDish(ramen, diet: {'no_pork'}, variant: vegan).verdict,
        DishVerdict.ask,
      );
    });

    test('safeVariantFor uygun bir alternatif bulur', () {
      final ramen = kJapaneseDishes.firstWhere((d) => d.id == 'ramen');
      final alt = safeVariantFor(ramen, {'no_pork'});
      expect(alt, isNotNull);
    });

    test('diyet yoksa alternatif aranmaz', () {
      final ramen = kJapaneseDishes.firstWhere((d) => d.id == 'ramen');
      expect(safeVariantFor(ramen, const {}), isNull);
    });
  });

  group('içerik bütünlüğü', () {
    test('id\'ler benzersiz', () {
      final ids = kJapaneseDishes.map((d) => d.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('her yemekte Japonca ad, romaji ve fiyat bandı var', () {
      for (final d in kJapaneseDishes) {
        expect(d.nameJa, isNotEmpty, reason: d.id);
        expect(d.romaji, isNotEmpty, reason: d.id);
        expect(d.priceMinJpy, lessThanOrEqualTo(d.priceMaxJpy), reason: d.id);
        expect(d.howToEat.tr, isNotEmpty, reason: d.id);
      }
    });

    // "Tencere yemeği 1 tane mi gerçekten?" — evet öyleydi. Sayfa gurme
    // rehberi olacaksa hiçbir kategori tek örnekle geçilemez; eşik 5.
    test('her kategoride en az 5 farklı yemek var', () {
      for (final c in DishCategory.values) {
        final list = kJapaneseDishes.where((d) => d.category == c).toList();
        expect(list.length, greaterThanOrEqualTo(5), reason: c.name);
      }
    });

    test('en az 60 yemek var — dar bir liste değil', () {
      expect(kJapaneseDishes.length, greaterThanOrEqualTo(60));
    });

    test('her diyet için en az birkaç yiyecek şey kalıyor', () {
      for (final diet in [
        {'halal'},
        {'vegetarian'},
        {'vegan'},
        {'no_pork'},
      ]) {
        final edible = kJapaneseDishes.where((d) {
          final v = assessDish(d, diet: diet).verdict;
          return v == DishVerdict.safe || v == DishVerdict.ask;
        });
        expect(edible.length, greaterThanOrEqualTo(3), reason: diet.toString());
      }
    });

    test('dashi içeren yemekler vejetaryene uygun işaretlenmiyor', () {
      // Miso çorbası ve udon en sık yapılan hata; regresyon koruması.
      for (final id in ['miso-soup', 'udon']) {
        final dish = kJapaneseDishes.firstWhere((d) => d.id == id);
        expect(
          assessDish(dish, diet: {'vegetarian'}).verdict,
          DishVerdict.avoid,
          reason: id,
        );
      }
    });

    test('menü kelimeleri sözlüğü dolu ve Japonca yazım taşıyor', () {
      expect(kMenuWordsToKnow.length, greaterThanOrEqualTo(8));
      for (final w in kMenuWordsToKnow) {
        expect(w.ja, isNotEmpty);
        expect(w.romaji, isNotEmpty);
      }
    });
  });
}

