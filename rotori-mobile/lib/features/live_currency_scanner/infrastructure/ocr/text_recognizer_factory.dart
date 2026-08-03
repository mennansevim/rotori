// Cihaz üstü OCR recognizer factory — koşullu import cephesi.
//
// Web (dart.library.io yok) → noop_text_recognizer (ML Kit web'de yok).
// Mobil (dart.library.io var) → mlkit_text_recognizer (google_mlkit).
//
// Bu izolasyon `flutter build web`'in google_mlkit'i import etmesini engeller.
export 'noop_text_recognizer.dart'
    if (dart.library.io) 'mlkit_text_recognizer.dart';
