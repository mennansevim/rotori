import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/features/live_currency_scanner/infrastructure/parsing/japanese_text_normalizer.dart';

void main() {
  const n = JapaneseTextNormalizer();

  test('tam genişlik rakam + virgül + 円 yarı genişliğe iner', () {
    expect(n.normalize('１２，８００円'), '12,800円');
  });

  test('tam genişlik ￥ + rakam → ¥980', () {
    expect(n.normalize('￥９８０'), '¥980');
  });

  test('boşluklu fiyat birleşir ve gruplanır', () {
    expect(n.normalize('12 800 円'), '12,800円');
  });

  test('rakam-para işareti arası boşluk temizlenir', () {
    expect(n.normalize('¥ 1280'), '¥1,280');
  });

  test('4+ haneli çıplak rakam binlik virgülle gruplanır', () {
    expect(n.normalize('12800'), '12,800');
    expect(n.normalize('1234567'), '1,234,567');
  });

  test('zaten gruplu ve kısa değerler korunur', () {
    expect(n.normalize('12,800'), '12,800');
    expect(n.normalize('980'), '980');
  });

  test('ideographic space (全角スペース) normal boşluğa iner', () {
    expect(n.normalize('税込\u300012,800円'), '税込 12,800円');
  });
}
