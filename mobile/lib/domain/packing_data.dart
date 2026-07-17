// Valiz & Hazırlık — Japonya'ya özel, kategorilere ayrılmış hazırlık/valiz
// listesi şablonu. Türkçe, çevrimdışı sabit veri. Kullanıcı bu şablonun
// üzerine kendi maddelerini ekleyebilir (bkz. data/checklist_store.dart) ve
// her madde plan (trip) bazında işaretlenir.
//
// Not değerleri (note) kısa, pratik uyarılardır — Japonya bağlamına özgü.

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

  /// Ait olduğu kategori (görüntüleme grubu).
  final String category;

  /// Türkçe madde etiketi.
  final String label;

  /// Kısa, isteğe bağlı pratik uyarı/açıklama.
  final String? note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'label': label,
        if (note != null) 'note': note,
      };

  factory ChecklistItem.fromJson(Map<String, dynamic> j) => ChecklistItem(
        id: j['id'] as String,
        category: (j['category'] as String?) ?? 'Diğer',
        label: (j['label'] as String?) ?? '',
        note: j['note'] as String?,
      );
}

/// Japonya'ya özel valiz & hazırlık şablonu. Kategori sırası bu listenin
/// görünüş sırasını belirler (ekran kategorileri ilk görüldükleri sırayla
/// gruplar).
const List<ChecklistItem> kJapanChecklist = [
  // --- Belgeler -----------------------------------------------------------
  ChecklistItem(
    id: 'doc-passport',
    category: 'Belgeler',
    label: 'Pasaport',
    note: 'Son kullanma tarihi dönüşten en az 6 ay sonra olmalı',
  ),
  ChecklistItem(
    id: 'doc-visa',
    category: 'Belgeler',
    label: '(Varsa) vize',
    note: 'Vize gerekiyorsa yanına al veya e-vize çıktısını sakla',
  ),
  ChecklistItem(
    id: 'doc-jrpass',
    category: 'Belgeler',
    label: 'JR Pass voucher / QR',
    note: 'Aktivasyon için voucher veya dijital QR gerekir',
  ),
  ChecklistItem(
    id: 'doc-hotel',
    category: 'Belgeler',
    label: 'Otel rezervasyon çıktısı',
    note: 'Girişte istenebilir; çevrimdışı erişim için çıktı al',
  ),
  ChecklistItem(
    id: 'doc-flight',
    category: 'Belgeler',
    label: 'Uçuş bileti / biniş kartı',
  ),
  ChecklistItem(
    id: 'doc-insurance',
    category: 'Belgeler',
    label: 'Seyahat sigortası poliçesi',
  ),

  // --- Bağlantı -----------------------------------------------------------
  ChecklistItem(
    id: 'net-wifi-esim',
    category: 'Bağlantı',
    label: 'Cep wifi veya eSIM',
    note: "Japonya'da ücretsiz wifi az — internetini garantiye al",
  ),
  ChecklistItem(
    id: 'net-ic-card',
    category: 'Bağlantı',
    label: 'IC kart (Suica / Pasmo)',
    note: 'Metro + konbini ödemesi için pratik',
  ),

  // --- Ödeme --------------------------------------------------------------
  ChecklistItem(
    id: 'pay-cash-yen',
    category: 'Ödeme',
    label: 'Bir miktar nakit yen',
    note: 'Küçük dükkanlar ve tapınaklar kart almaz',
  ),
  ChecklistItem(
    id: 'pay-credit-card',
    category: 'Ödeme',
    label: 'Kredi kartı (temassız)',
  ),
  ChecklistItem(
    id: 'pay-bank-notice',
    category: 'Ödeme',
    label: 'Bankaya yurtdışı / kart kullanım bildirimi',
    note: 'Kartın yurtdışında bloke olmasın',
  ),

  // --- Elektronik ---------------------------------------------------------
  ChecklistItem(
    id: 'elec-adapter',
    category: 'Elektronik',
    label: 'Priz adaptörü',
    note: 'Japonya A tipi priz, 100V',
  ),
  ChecklistItem(
    id: 'elec-powerbank',
    category: 'Elektronik',
    label: 'Powerbank',
    note: 'Uzun yürüyüş günlerinde telefon şarjı için',
  ),
  ChecklistItem(
    id: 'elec-cables',
    category: 'Elektronik',
    label: 'Şarj kabloları',
  ),
  ChecklistItem(
    id: 'elec-headphones',
    category: 'Elektronik',
    label: 'Kulaklık',
  ),

  // --- Sağlık -------------------------------------------------------------
  ChecklistItem(
    id: 'health-meds',
    category: 'Sağlık',
    label: 'Kişisel ilaçlar + reçete',
    note: "Bazı ilaçlar Japonya'da yasak — önceden kontrol et",
  ),
  ChecklistItem(
    id: 'health-mask',
    category: 'Sağlık',
    label: 'Maske',
    note: 'Kalabalık metro ve hastalıkta yaygın kullanılır',
  ),
  ChecklistItem(
    id: 'health-firstaid',
    category: 'Sağlık',
    label: 'Küçük ilk yardım seti',
  ),

  // --- Giyim --------------------------------------------------------------
  ChecklistItem(
    id: 'cloth-layers',
    category: 'Giyim',
    label: 'Mevsime uygun katmanlı giysi',
  ),
  ChecklistItem(
    id: 'cloth-shoes',
    category: 'Giyim',
    label: 'Rahat yürüyüş ayakkabısı',
    note: 'Günde 15–20 bin adım yürüyeceksin',
  ),
  ChecklistItem(
    id: 'cloth-rain',
    category: 'Giyim',
    label: 'Yağmurluk / katlanır şemsiye',
  ),

  // --- Vergi iadesi & alışveriş ------------------------------------------
  ChecklistItem(
    id: 'tax-passport',
    category: 'Vergi iadesi & alışveriş',
    label: 'Pasaport (tax-free için)',
    note: 'Vergisiz alışverişte pasaport gösterilir',
  ),
  ChecklistItem(
    id: 'tax-foldable-bag',
    category: 'Vergi iadesi & alışveriş',
    label: 'Katlanır çanta',
    note: 'Alışverişler için ekstra taşıma alanı',
  ),
  ChecklistItem(
    id: 'tax-keep-receipts',
    category: 'Vergi iadesi & alışveriş',
    label: 'Fiş / makbuz saklama',
    note: 'Tax-free fişleri pasaporta iliştirilir, çıkışta kontrol edilir',
  ),

  // --- Kültür / pratik ----------------------------------------------------
  ChecklistItem(
    id: 'culture-towel',
    category: 'Kültür / pratik',
    label: 'Küçük havlu / mendil',
    note: 'Umumi tuvaletlerde kağıt havlu yok',
  ),
  ChecklistItem(
    id: 'culture-trash-bag',
    category: 'Kültür / pratik',
    label: 'Çöp için poşet',
    note: 'Sokakta çöp kutusu az — çöpünü yanında taşı',
  ),
  ChecklistItem(
    id: 'culture-coin-wallet',
    category: 'Kültür / pratik',
    label: 'Bozuk para için küçük cüzdan',
    note: 'Nakit ağırlıklı — çok madeni para birikir',
  ),
];
