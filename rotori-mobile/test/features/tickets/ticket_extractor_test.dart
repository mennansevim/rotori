import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/features/tickets/data/ticket_extractor.dart';
import 'package:rotori/features/tickets/domain/ticket_import_models.dart';

void main() {
  test('extractor combines raw text and QR candidates in its in-memory result',
      () async {
    final extractor = TicketCandidateExtractor(
      _FakeTicketRawExtractor(
        const TicketRawExtraction(
          text: 'teamLab Planets\nVisit 2026-08-17\nEntry 09:00',
          qrPayloads: ['https://ticket.example/AB12CD34'],
        ),
      ),
    );

    final result = await extractor.extract('/tmp/ticket.jpg');

    expect(result.rawText, contains('teamLab Planets'));
    expect(result.qrPayloads, ['https://ticket.example/AB12CD34']);
    expect(
      result.candidates.any(
        (candidate) => candidate.type == TicketCandidateType.date,
      ),
      isTrue,
    );
    expect(
      result.candidates.any(
        (candidate) => candidate.type == TicketCandidateType.qr,
      ),
      isTrue,
    );
  });
}

class _FakeTicketRawExtractor implements TicketRawExtractor {
  const _FakeTicketRawExtractor(this._result);

  final TicketRawExtraction _result;

  @override
  Future<TicketRawExtraction> extractRaw(String imagePath) async => _result;
}
