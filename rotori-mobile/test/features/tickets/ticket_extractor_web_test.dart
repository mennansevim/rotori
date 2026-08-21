import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/features/tickets/data/ticket_extractor.dart';
import 'package:rotori/features/tickets/data/ticket_extractor_stub.dart'
    as web;

void main() {
  // `flutter test` her zaman Dart VM'de çalışır (`dart.library.io` her zaman
  // true'dur), bu yüzden `ticket_extractor.dart` içindeki conditional import
  // hiçbir zaman bu stub'a düşmez — her zaman gerçek ML Kit'i çağıran
  // `ticket_extractor_io.dart`'ı seçer. Web/stub davranışını deterministik
  // biçimde doğrulamak için stub modülü burada doğrudan import edilir.
  test('web fallback extractor returns the empty manual result', () async {
    final directResult = await web.extractTicketImage('/tmp/ticket.jpg');
    final extractorResult = await TicketCandidateExtractor(
      web.createTicketRawExtractor(),
    ).extract('/tmp/ticket.jpg');

    for (final result in [directResult, extractorResult]) {
      expect(result.candidates, isEmpty);
      expect(result.rawText, isEmpty);
      expect(result.qrPayloads, isEmpty);
    }
  });
}
