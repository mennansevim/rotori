import '../domain/ticket_import_models.dart';
import 'ticket_extractor.dart';

TicketRawExtractor createTicketRawExtractor() => _StubTicketRawExtractor();

Future<TicketExtractionResult> extractTicketImage(String imagePath) async =>
    const TicketExtractionResult();

class _StubTicketRawExtractor implements TicketRawExtractor {
  @override
  Future<TicketRawExtraction> extractRaw(String imagePath) async =>
      const TicketRawExtraction();
}
