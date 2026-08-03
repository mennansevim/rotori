// Canlı para birimi tarayıcının desteklediği hedef para birimleri.
//
// Saf Dart — Flutter/OCR/Supabase importu YOK; birim testlenebilir.
// Mimari genişletilebilir: yeni bir para birimi eklemek için buraya bir enum
// değeri + metadata eklemek yeterli.

/// Tarayıcının çevirebildiği hedef para birimleri.
///
/// Kaynak para birimi her zaman JPY'dir (Japonya odaklı ürün). Hedef ise
/// kullanıcının seçtiği para birimidir; varsayılan [CurrencyCode.tryl].
enum CurrencyCode {
  /// Türk lirası (varsayılan hedef).
  tryl,
  usd,
  eur,
  gbp,
  krw,
  cny;

  /// ISO 4217 kodu (kalıcı depolama + Supabase anahtarı).
  String get iso => switch (this) {
        CurrencyCode.tryl => 'TRY',
        CurrencyCode.usd => 'USD',
        CurrencyCode.eur => 'EUR',
        CurrencyCode.gbp => 'GBP',
        CurrencyCode.krw => 'KRW',
        CurrencyCode.cny => 'CNY',
      };

  /// Para birimi sembolü (UI gösterimi).
  String get symbol => switch (this) {
        CurrencyCode.tryl => '₺',
        CurrencyCode.usd => r'$',
        CurrencyCode.eur => '€',
        CurrencyCode.gbp => '£',
        CurrencyCode.krw => '₩',
        CurrencyCode.cny => '¥',
      };

  /// Ondalık hane sayısı (minor unit). KRW ve JPY ondalıksızdır.
  int get decimalDigits => switch (this) {
        CurrencyCode.krw => 0,
        _ => 2,
      };

  /// ISO kodundan çöz; bilinmiyorsa varsayılan [CurrencyCode.tryl].
  static CurrencyCode fromIso(String? raw) => switch (raw?.toUpperCase()) {
        'TRY' => CurrencyCode.tryl,
        'USD' => CurrencyCode.usd,
        'EUR' => CurrencyCode.eur,
        'GBP' => CurrencyCode.gbp,
        'KRW' => CurrencyCode.krw,
        'CNY' => CurrencyCode.cny,
        _ => CurrencyCode.tryl,
      };

  /// Kaynak (sabit) para birimi kodu.
  static const String baseIso = 'JPY';
}
