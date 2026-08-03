/// Canlı para çevirici için merkezî yapılandırma sabitleri.
///
/// Magic number dağıtmamak için tüm eşikler burada toplanır. Test edilebilir
/// ve tek yerden ayarlanabilir.
class ScannerTuning {
  const ScannerTuning._();

  // --- Fiyat makul aralığı (JPY) -------------------------------------------
  /// Bu değerin altındaki tutarlar fiyat sayılmaz (barkod/kod gürültüsü).
  static const int minPlausibleJpy = 10;

  /// Bu değerin üstündeki tutarlar şüpheli kabul edilir (güven düşer).
  static const int maxPlausibleJpy = 100000000; // 100M ¥

  // --- Güven skoru katkıları -----------------------------------------------
  static const double baseConfidence = 0.30;
  static const double currencyMarkBonus = 0.35; // ¥ ￥ 円 JPY yakınlığı
  static const double taxLabelBonus = 0.15; // 税込/税抜 aynı satırda
  static const double plausibleRangeBonus = 0.15;
  static const double repeatFrameBonus = 0.10; // aynı değer ardışık karede

  // --- Tracking -------------------------------------------------------------
  /// Bir fiyatın overlay'de gösterilmesi için gereken minimum görülme sayısı.
  static const int minSeenToDisplay = 2;

  /// Detection bu süre boyunca görülmezse iz kaldırılır (ms).
  static const int staleTrackMs = 700;

  /// İki kutunun aynı fiyat kabul edilmesi için minimum IoU.
  static const double matchIouThreshold = 0.35;

  /// Kutu merkezleri arası (kutu boyutuna oranlı) maksimum eşleşme mesafesi.
  static const double matchCenterDistanceRatio = 0.6;

  /// Exponential smoothing katsayısı — geçmişin ağırlığı.
  static const double boxSmoothingPrevWeight = 0.75;
  static const double boxSmoothingNewWeight = 0.25;

  // --- Overlay --------------------------------------------------------------
  /// Aynı anda gösterilecek maksimum overlay sayısı.
  static const int maxOverlays = 6;

  /// Düşük güven altında overlay daha temkinli gösterilir.
  static const double lowConfidenceThreshold = 0.55;

  // --- Kur eskimesi ---------------------------------------------------------
  /// Bu yaştan sonra güncelleme denenir.
  static const Duration refreshAfter = Duration(hours: 24);

  /// Bu yaştan sonra "kur eski olabilir" uyarısı gösterilir.
  static const Duration staleWarningAfter = Duration(hours: 48);

  // --- Vergi dahil/hariç eşleştirme ----------------------------------------
  /// 税込/税抜 çiftinin aynı ürün kabul edilmesi için oran alt/üst sınırı.
  static const double taxPairMinRatio = 1.02; // dahil ≥ hariç * 1.02
  static const double taxPairMaxRatio = 1.20; // dahil ≤ hariç * 1.20

  /// Vergi çifti kutularının yakınlık eşiği (kutu yüksekliğine oranlı).
  static const double taxPairProximityRatio = 3.0;
}
