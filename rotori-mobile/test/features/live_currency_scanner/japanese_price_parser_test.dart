import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/features/live_currency_scanner/domain/japanese_price_tax_type.dart';
import 'package:japan_trip/features/live_currency_scanner/infrastructure/parsing/japanese_price_parser.dart';

void main() {
  const parser = JapanesePriceParser();

  int? amountOf(String line) {
    final c = parser.parseLine(line);
    return c.isEmpty ? null : c.first.amountInJpy;
  }

  group('geçerli fiyat formatları', () {
    test('¥12,800', () => expect(amountOf('¥12,800'), 12800));
    test('￥980 (tam genişlik)', () => expect(amountOf('￥９８０'), 980));
    test('12,800円', () => expect(amountOf('12,800円'), 12800));
    test('税込 11,000円', () {
      final c = parser.parseLine('税込 11,000円');
      expect(c.single.amountInJpy, 11000);
      expect(c.single.taxType, JapanesePriceTaxType.taxIncluded);
    });
    test('税抜 10,000円', () {
      final c = parser.parseLine('税抜 10,000円');
      expect(c.single.amountInJpy, 10000);
      expect(c.single.taxType, JapanesePriceTaxType.taxExcluded);
    });
    test('本体価格 → vergi hariç', () {
      expect(parser.parseLine('本体価格 3,000円').single.taxType,
          JapanesePriceTaxType.taxExcluded);
    });
    test('tam genişlik １２，８００円', () => expect(amountOf('１２，８００円'), 12800));
    test('OCR nokta hatası ¥1.280 → 1280',
        () => expect(amountOf('¥1.280'), 1280));
    test('binlik virgül ¥2,999 → 2999', () => expect(amountOf('¥2,999'), 2999));
    test('binlik virgül ¥1,198 → 1198', () => expect(amountOf('¥1,198'), 1198));
    test('OCR virgülü nokta sanmış ¥2.999 → 2999',
        () => expect(amountOf('¥2.999'), 2999));
  });

  group('fiyat olmayanları ele', () {
    test('yüzde', () => expect(parser.parseLine('30%').isEmpty, isTrue));
    test(
        'tarih 2026年', () => expect(parser.parseLine('2026年').isEmpty, isTrue));
    test('saat 12:30', () => expect(parser.parseLine('12:30').isEmpty, isTrue));
    test('telefon 03-1234-5678',
        () => expect(parser.parseLine('03-1234-5678').isEmpty, isTrue));
    test('ürün kodu AB1234',
        () => expect(parser.parseLine('AB1234').isEmpty, isTrue));
    test('adet 5個', () => expect(parser.parseLine('5個').isEmpty, isTrue));
    test('para işareti/vergi yoksa sayı fiyat değildir',
        () => expect(parser.parseLine('12800').isEmpty, isTrue));
    test('boş metin', () => expect(parser.parseLine('   ').isEmpty, isTrue));
  });

  test('birden fazla fiyat aynı satırda', () {
    final c = parser.parseLine('¥500 ¥1,200円');
    expect(c.map((e) => e.amountInJpy).toList(), containsAll(<int>[500, 1200]));
  });

  test('aynı blokta vergi dahil + hariç → hariç elenir, dahil kalır', () {
    final result = parser.parse('税抜 ¥10,000\n税込 ¥11,000');
    final amounts = result.map((e) => e.amountInJpy).toList();
    expect(amounts, contains(11000));
    expect(amounts, isNot(contains(10000)));
  });

  test('para işaretli sayı güveni işaretsizden yüksek', () {
    final withMark = parser.parseLine('¥12,800').single.confidence;
    final withTax = parser.parseLine('税込 12,800円').single.confidence;
    expect(withTax, greaterThan(withMark));
  });
}
