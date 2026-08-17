import '../../shared/ticket_support.dart';
import '../domain/ticket_import_models.dart';
import 'ticket_extractor_stub.dart'
    if (dart.library.io) 'ticket_extractor_io.dart' as platform;

class TicketRawExtraction {
  const TicketRawExtraction({
    this.text = '',
    this.qrPayloads = const [],
  });

  final String text;
  final List<String> qrPayloads;
}

abstract interface class TicketRawExtractor {
  Future<TicketRawExtraction> extractRaw(String imagePath);
}

class TicketCandidateExtractor implements TicketExtractor {
  const TicketCandidateExtractor(this._rawExtractor);

  final TicketRawExtractor _rawExtractor;

  @override
  Future<TicketExtractionResult> extract(String imagePath) async {
    final raw = await _rawExtractor.extractRaw(imagePath);
    return TicketExtractionResult(
      rawText: raw.text,
      qrPayloads: raw.qrPayloads,
      candidates: buildTicketImportCandidates(
        raw.text,
        qrPayloads: raw.qrPayloads,
      ),
    );
  }
}

TicketExtractor createTicketExtractor() =>
    TicketCandidateExtractor(platform.createTicketRawExtractor());

Future<TicketExtractionResult> extractTicketImage(String imagePath) =>
    platform.extractTicketImage(imagePath);
