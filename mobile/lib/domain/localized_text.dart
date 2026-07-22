// Satır içi iki dilli metin.
//
// Büyük "yer içeriği" verisi (place_guide.dart / city_places.dart) anahtar →
// sözlük tabanlı i18n sistemine (core/l10n.dart) sığmayacak kadar uzun ve
// serbest metindir. Bu yüzden TR ve EN karşılıkları doğrudan veri modelinin
// içinde, yan yana tutulur; [of] aktif [AppLang]'e göre doğru dizeyi döndürür.
//
//   const LText('Sabah git', 'Go in the morning').of(lang)

import '../core/l10n.dart';

/// TR + EN karşılığı bir arada tutulan basit metin sarmalayıcı.
class LText {
  const LText(this.tr, this.en);

  /// Türkçe karşılık (orijinal metin).
  final String tr;

  /// İngilizce karşılık.
  final String en;

  /// Aktif dildeki metin — [AppLang.en] ise İngilizce, aksi halde Türkçe.
  String of(AppLang lang) => lang == AppLang.en ? en : tr;
}
