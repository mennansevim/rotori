// Japon fiyat etiketlerindeki vergi durumu.
//
// Saf Dart. `税込` (vergi dahil), `税抜` / `本体価格` (vergi hariç) etiketleri
// parser tarafından bu tipe çözülür. Aynı ürün için iki fiyat bulunduğunda
// varsayılan olarak [taxIncluded] gösterilir.

enum JapanesePriceTaxType {
  /// 税込 — vergi dahil (ana gösterim önceliği).
  taxIncluded,

  /// 税抜 / 本体価格 — vergi hariç.
  taxExcluded,

  /// Vergi etiketi bulunamadı.
  unknown;

  bool get isIncluded => this == JapanesePriceTaxType.taxIncluded;
  bool get isExcluded => this == JapanesePriceTaxType.taxExcluded;
}
