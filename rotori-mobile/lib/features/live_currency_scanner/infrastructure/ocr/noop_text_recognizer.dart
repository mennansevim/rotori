import 'on_device_text_recognizer.dart';

/// Web (dart.library.io yok) için no-op recognizer — ML Kit web'de yoktur.
/// Canlı tarayıcı web'de tam çalışmaz; kamera ekranı kibarca boş sonuç alır.
class NoopTextRecognizer implements OnDeviceTextRecognizer {
  @override
  Future<RecognizedFrame> recognize(CameraImageInput frame) async =>
      RecognizedFrame.empty;

  @override
  Future<void> dispose() async {}
}

/// Factory — koşullu export bu sembolü çağırır.
OnDeviceTextRecognizer createTextRecognizer() => NoopTextRecognizer();
