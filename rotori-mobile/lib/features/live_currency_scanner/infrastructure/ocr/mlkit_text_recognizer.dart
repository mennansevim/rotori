import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'on_device_text_recognizer.dart';

/// ML Kit tabanlı cihaz üstü metin tanıma (yalnızca mobil / dart.library.io).
///
/// Japonca script kullanır — 円/税込 gibi kanji + rakamları tanır. Web'de bu
/// dosya derlenmez; `text_recognizer_factory.dart` koşullu export ile no-op
/// recognizer'a düşer.
class MlkitTextRecognizer implements OnDeviceTextRecognizer {
  MlkitTextRecognizer()
      : _recognizer = TextRecognizer(script: TextRecognitionScript.japanese);

  final TextRecognizer _recognizer;

  @override
  Future<RecognizedFrame> recognize(CameraImageInput frame) async {
    final input = _toInputImage(frame);
    if (input == null) return RecognizedFrame.empty;
    try {
      final result = await _recognizer.processImage(input);
      final lines = <RecognizedTextLine>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          final box = line.boundingBox;
          lines.add(RecognizedTextLine(
            text: line.text,
            boundingBox: Rect.fromLTRB(
              box.left,
              box.top,
              box.right,
              box.bottom,
            ),
          ));
        }
      }
      return RecognizedFrame(
        lines: lines,
        imageSize: frame.imageSize,
        rotationDegrees: frame.rotationDegrees,
      );
    } catch (_) {
      // OCR hatası tek kareyi düşürür; kamera akışı bloklanmaz.
      return RecognizedFrame.empty;
    }
  }

  InputImage? _toInputImage(CameraImageInput frame) {
    final rotation =
        InputImageRotationValue.fromRawValue(frame.rotationDegrees) ??
            InputImageRotation.rotation0deg;
    final format = InputImageFormatValue.fromRawValue(frame.rawFormat) ??
        InputImageFormat.nv21;

    if (frame.planes.isEmpty) return null;

    final builder = BytesBuilder();
    for (final plane in frame.planes) {
      builder.add(plane.bytes);
    }
    final bytes = builder.toBytes();

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: frame.bytesPerRow,
      ),
    );
  }

  @override
  Future<void> dispose() => _recognizer.close();
}

/// Factory — koşullu export bu sembolü çağırır.
OnDeviceTextRecognizer createTextRecognizer() => MlkitTextRecognizer();
