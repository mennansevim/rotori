// Rotori marka sabitleri — TEMADAN BAĞIMSIZ.
//
// **Why ayrı dosya:** `ViewerPalette` kullanıcının seçtiği temaya göre
// değişiyor (appleLight'ta mor/mavi, japanDark'ta menekşe, sakuraSoft'ta
// pembe). Marka işareti ve marka yüzeyleri her temada AYNI kırmızı olmalı;
// yoksa logo Rotori gibi durmuyor. Tema renkleri içerik için, bu renkler
// kimlik için.

import 'package:flutter/painting.dart';

abstract final class RotoriBrand {
  /// Torii kırmızısı — launcher ikonundaki ana kırmızı.
  static const Color torii = Color(0xFFE0231A);

  /// Rota kurdelesinin daha koyu tonu; torii üzerinde ayrışsın diye.
  static const Color route = Color(0xFFB71508);

  /// Marka yüzeylerinin (oluşturma akışı hero'su) derin kırmızısı.
  static const Color deep = Color(0xFF8E1109);

  /// Hero gradyanı: torii kırmızısından derin kırmızıya.
  ///
  /// Eski gradyan `[fuji, sakura]` (mor → pembe) idi; jenerik bir "AI
  /// uygulaması" görünümü veriyordu ve markanın kırmızısıyla ilgisi yoktu.
  static const List<Color> heroGradient = [torii, deep];

  /// Uygulama içi marka işareti.
  static const String logoAsset = 'assets/images/rotori-logo.png';
}
