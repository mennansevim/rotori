// Valiz & Hazırlık — Japonya'ya özel, kategorilere ayrılmış hazırlık/valiz
// listesi şablonu. Çevrimdışı sabit veri. Kullanıcı bu şablonun üzerine kendi
// maddelerini ekleyebilir (bkz. data/checklist_store.dart) ve her madde plan
// (trip) bazında işaretlenir.
//
// i18n: Şablon maddelerinin category/label/note DEĞERLERİ artık düz Türkçe
// metin değil, i18n ANAHTARLARIDIR (prefix `packing.`). Görüntüleme sırasında
// LanguageScope.of(context).s(key) ile çözülür (bkz. checklist_screen.dart).
// Karşılıklar core/l10n.dart sözlüğündedir. Madde `id`'leri STABİL kalır —
// işaretli durum ve özel madde kimliği bu id üzerinden saklanır.

/// Tek bir kontrol listesi maddesi.
class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.category,
    required this.label,
    this.note,
  });

  /// Stabil kimlik (kebab-case). İşaretli durumu bu id ile saklanır.
  final String id;

  /// Ait olduğu kategori (görüntüleme grubu). Şablon maddelerinde i18n
  /// anahtarı (`packing.cat.*`); özel maddelerde kullanıcının seçtiği kategori.
  final String category;

  /// Madde etiketi. Şablon maddelerinde i18n anahtarı (`packing.*`);
  /// özel maddelerde kullanıcının girdiği düz metin.
  final String label;

  /// Kısa, isteğe bağlı pratik uyarı/açıklama. Şablon maddelerinde i18n anahtarı.
  final String? note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'label': label,
        if (note != null) 'note': note,
      };

  factory ChecklistItem.fromJson(Map<String, dynamic> j) => ChecklistItem(
        id: j['id'] as String,
        category: (j['category'] as String?) ?? 'packing.cat.other',
        label: (j['label'] as String?) ?? '',
        note: j['note'] as String?,
      );
}

/// Japonya'ya özel valiz & hazırlık şablonu. Kategori sırası bu listenin
/// görünüş sırasını belirler (ekran kategorileri ilk görüldükleri sırayla
/// gruplar). category/label/note değerleri i18n anahtarıdır (bkz. dosya başı).
const List<ChecklistItem> kJapanChecklist = [
  // --- Belgeler -----------------------------------------------------------
  ChecklistItem(
    id: 'doc-passport',
    category: 'packing.cat.documents',
    label: 'packing.doc-passport.label',
    note: 'packing.doc-passport.note',
  ),
  ChecklistItem(
    id: 'doc-visa',
    category: 'packing.cat.documents',
    label: 'packing.doc-visa.label',
    note: 'packing.doc-visa.note',
  ),
  ChecklistItem(
    id: 'doc-jrpass',
    category: 'packing.cat.documents',
    label: 'packing.doc-jrpass.label',
    note: 'packing.doc-jrpass.note',
  ),
  ChecklistItem(
    id: 'doc-hotel',
    category: 'packing.cat.documents',
    label: 'packing.doc-hotel.label',
    note: 'packing.doc-hotel.note',
  ),
  ChecklistItem(
    id: 'doc-flight',
    category: 'packing.cat.documents',
    label: 'packing.doc-flight.label',
  ),
  ChecklistItem(
    id: 'doc-insurance',
    category: 'packing.cat.documents',
    label: 'packing.doc-insurance.label',
  ),

  // --- Bağlantı -----------------------------------------------------------
  ChecklistItem(
    id: 'net-wifi-esim',
    category: 'packing.cat.connectivity',
    label: 'packing.net-wifi-esim.label',
    note: 'packing.net-wifi-esim.note',
  ),
  ChecklistItem(
    id: 'net-ic-card',
    category: 'packing.cat.connectivity',
    label: 'packing.net-ic-card.label',
    note: 'packing.net-ic-card.note',
  ),

  // --- Ödeme --------------------------------------------------------------
  ChecklistItem(
    id: 'pay-cash-yen',
    category: 'packing.cat.payment',
    label: 'packing.pay-cash-yen.label',
    note: 'packing.pay-cash-yen.note',
  ),
  ChecklistItem(
    id: 'pay-credit-card',
    category: 'packing.cat.payment',
    label: 'packing.pay-credit-card.label',
  ),
  ChecklistItem(
    id: 'pay-bank-notice',
    category: 'packing.cat.payment',
    label: 'packing.pay-bank-notice.label',
    note: 'packing.pay-bank-notice.note',
  ),

  // --- Elektronik ---------------------------------------------------------
  ChecklistItem(
    id: 'elec-adapter',
    category: 'packing.cat.electronics',
    label: 'packing.elec-adapter.label',
    note: 'packing.elec-adapter.note',
  ),
  ChecklistItem(
    id: 'elec-powerbank',
    category: 'packing.cat.electronics',
    label: 'packing.elec-powerbank.label',
    note: 'packing.elec-powerbank.note',
  ),
  ChecklistItem(
    id: 'elec-cables',
    category: 'packing.cat.electronics',
    label: 'packing.elec-cables.label',
  ),
  ChecklistItem(
    id: 'elec-headphones',
    category: 'packing.cat.electronics',
    label: 'packing.elec-headphones.label',
  ),

  // --- Sağlık -------------------------------------------------------------
  ChecklistItem(
    id: 'health-meds',
    category: 'packing.cat.health',
    label: 'packing.health-meds.label',
    note: 'packing.health-meds.note',
  ),
  ChecklistItem(
    id: 'health-mask',
    category: 'packing.cat.health',
    label: 'packing.health-mask.label',
    note: 'packing.health-mask.note',
  ),
  ChecklistItem(
    id: 'health-firstaid',
    category: 'packing.cat.health',
    label: 'packing.health-firstaid.label',
  ),

  // --- Giyim --------------------------------------------------------------
  ChecklistItem(
    id: 'cloth-layers',
    category: 'packing.cat.clothing',
    label: 'packing.cloth-layers.label',
  ),
  ChecklistItem(
    id: 'cloth-shoes',
    category: 'packing.cat.clothing',
    label: 'packing.cloth-shoes.label',
    note: 'packing.cloth-shoes.note',
  ),
  ChecklistItem(
    id: 'cloth-rain',
    category: 'packing.cat.clothing',
    label: 'packing.cloth-rain.label',
  ),

  // --- Vergi iadesi & alışveriş ------------------------------------------
  ChecklistItem(
    id: 'tax-passport',
    category: 'packing.cat.taxRefund',
    label: 'packing.tax-passport.label',
    note: 'packing.tax-passport.note',
  ),
  ChecklistItem(
    id: 'tax-foldable-bag',
    category: 'packing.cat.taxRefund',
    label: 'packing.tax-foldable-bag.label',
    note: 'packing.tax-foldable-bag.note',
  ),
  ChecklistItem(
    id: 'tax-keep-receipts',
    category: 'packing.cat.taxRefund',
    label: 'packing.tax-keep-receipts.label',
    note: 'packing.tax-keep-receipts.note',
  ),

  // --- Kültür / pratik ----------------------------------------------------
  ChecklistItem(
    id: 'culture-towel',
    category: 'packing.cat.culture',
    label: 'packing.culture-towel.label',
    note: 'packing.culture-towel.note',
  ),
  ChecklistItem(
    id: 'culture-trash-bag',
    category: 'packing.cat.culture',
    label: 'packing.culture-trash-bag.label',
    note: 'packing.culture-trash-bag.note',
  ),
  ChecklistItem(
    id: 'culture-coin-wallet',
    category: 'packing.cat.culture',
    label: 'packing.culture-coin-wallet.label',
    note: 'packing.culture-coin-wallet.note',
  ),
];
