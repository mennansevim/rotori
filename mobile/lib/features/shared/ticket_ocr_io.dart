// Mobil (dart.library.io) uygulaması — google_mlkit ile cihaz üstü OCR.
// Yalnızca dart.library.io varken (iOS/Android) derlenir; web'de ticket_ocr_stub
// kullanılır (bkz. ticket_ocr.dart koşullu export).
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

Future<String> extractTicketText(String imagePath) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final input = InputImage.fromFilePath(imagePath);
    final result = await recognizer.processImage(input);
    return result.text;
  } catch (_) {
    return '';
  } finally {
    await recognizer.close();
  }
}
