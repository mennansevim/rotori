enum TicketCandidateType {
  label,
  date,
  time,
  venue,
  confirmationCode,
  seat,
  gate,
  partySize,
  url,
  qr,
}

class TicketImportCandidate {
  const TicketImportCandidate({
    required this.id,
    required this.type,
    required this.value,
    required this.needsReview,
  });

  final String id;
  final TicketCandidateType type;
  final String value;
  final bool needsReview;
}

class TicketExtractionResult {
  const TicketExtractionResult({
    this.candidates = const [],
    this.rawText = '',
    this.qrPayloads = const [],
  });

  final List<TicketImportCandidate> candidates;
  final String rawText;
  final List<String> qrPayloads;
}

abstract interface class TicketExtractor {
  Future<TicketExtractionResult> extract(String imagePath);
}
