// Bilet OCR — cihaz üstü (on-device) metin çıkarımı için koşullu import cephesi.
//
// Web (dart.library.io yoksa) → ticket_ocr_stub.dart (boş metin döner).
// Mobil (dart.library.io var) → ticket_ocr_io.dart (google_mlkit ile OCR).
//
// Bu izolasyon sayesinde web bağımlılık grafiği google_mlkit'i ASLA import etmez;
// böylece `flutter build web` mlkit'in mobil eklentilerinden etkilenmez.
export 'ticket_ocr_stub.dart' if (dart.library.io) 'ticket_ocr_io.dart';
