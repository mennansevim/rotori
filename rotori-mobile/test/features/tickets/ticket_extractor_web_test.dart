import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/features/tickets/data/ticket_extractor.dart';

void main() {
  test('public extractor facade uses the empty manual fallback on web',
      () async {
    final directResult = await extractTicketImage('/tmp/ticket.jpg');
    final extractorResult =
        await createTicketExtractor().extract('/tmp/ticket.jpg');

    for (final result in [directResult, extractorResult]) {
      expect(result.candidates, isEmpty);
      expect(result.rawText, isEmpty);
      expect(result.qrPayloads, isEmpty);
    }
  });
}
