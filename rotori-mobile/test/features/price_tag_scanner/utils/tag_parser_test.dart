import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/features/price_tag_scanner/utils/tag_parser.dart';

void main() {
  const parser = TagParser();

  group('TagParser', () {
    test('税込 fiyatı, 税抜 ve ポイント değerlerine tercih eder', () {
      const input = '''
SONY WH-1000XM5
ノイズキャンセリングヘッドホン
税込 ¥45,800
税抜 ¥41,636
10%ポイント 4,580ポイント還元
''';

      final result = parser.parse(input);

      expect(result.productModel, 'WH-1000XM5');
      expect(result.jpyPrice, 45800);
      expect(result.hasTaxIncluded, isTrue);
      expect(result.hasTaxExcluded, isTrue);
    });

    test('円 son ekli fiyatı yakalar ve model kodunu bulur', () {
      const input = '''
PlayStation 5 CFI-1200A
販売価格 59,980円
会員ポイント 3,000 ポイント
''';

      final result = parser.parse(input);

      expect(result.productModel, 'CFI-1200A');
      expect(result.jpyPrice, 59980);
    });

    test('tam genişlik rakamları normalize eder ve model çıkarır', () {
      const input = '''
BIC CAMERA
MODEL RX100M7
税込 １３２，０００円
本体価格 １２０，０００円 税抜
''';

      final result = parser.parse(input);

      expect(result.productModel, 'RX100M7');
      expect(result.jpyPrice, 132000);
      expect(result.hasCoreData, isTrue);
    });
  });
}
