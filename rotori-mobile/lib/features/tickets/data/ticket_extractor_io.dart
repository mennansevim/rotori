import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/ticket_import_models.dart';
import 'ticket_extractor.dart';

TicketRawExtractor createTicketRawExtractor() => _OnDeviceTicketRawExtractor();

Future<TicketExtractionResult> extractTicketImage(String imagePath) =>
    TicketCandidateExtractor(createTicketRawExtractor()).extract(imagePath);

class _OnDeviceTicketRawExtractor implements TicketRawExtractor {
  @override
  Future<TicketRawExtraction> extractRaw(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
    try {
      final results = await Future.wait<Object>([
        textRecognizer.processImage(input),
        barcodeScanner.processImage(input),
      ]);
      final text = (results[0] as RecognizedText).text;
      final qrPayloads = (results[1] as List<Barcode>)
          .map((barcode) => barcode.rawValue?.trim())
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false);
      return TicketRawExtraction(text: text, qrPayloads: qrPayloads);
    } finally {
      await textRecognizer.close();
      await barcodeScanner.close();
    }
  }
}
