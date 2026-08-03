// Yolculuk öncesi hazırlık listesi — domain modeli.
//
// Preset maddeler `kPreDeparturePresets` içinde i18n anahtarlarıyla tanımlıdır
// (label/desc her iki dilde `core/l10n.dart` sözlüğünde çözülür). Kullanıcı
// bunları check/uncheck yapabilir, kendi maddesini ekleyebilir (custom=true).
//
// JSON şeması (Supabase `pre_departure_checklists.items` alanı ile birebir):
//   { "id": "...", "emoji": "...", "label_tr": "...", "label_en": "...",
//     "desc_tr": null, "desc_en": null, "checked": false, "custom": false }
//
// Preset maddelerin metin alanları storage'da BOŞ bırakılabilir — id ile
// i18n sözlüğünden çözülür. Custom maddelerde kullanıcının yazdığı metin
// hem label_tr hem label_en alanına yazılır (kullanıcı tek dilde yazar).

import 'dart:collection';

/// Tek bir hazırlık maddesi. Preset maddeler yalnızca id/emoji + i18n anahtar
/// referansı taşır; custom maddelerde `labelTr`/`labelEn` düz metindir.
class PrepItem {
  const PrepItem({
    required this.id,
    required this.emoji,
    this.labelTr,
    this.labelEn,
    this.descTr,
    this.descEn,
    this.checked = false,
    this.custom = false,
  });

  /// Stabil kimlik. Preset maddelerde sabit slug; custom maddelerde
  /// `custom-<hash>` biçiminde etikettan türer (bkz. [PrepItem.customFromLabel]).
  final String id;

  /// Emoji ikonu. Boş dize izinli (özel maddelerde varsayılan 📌).
  final String emoji;

  /// Türkçe etiket. Preset maddelerde `null` — sözlükten (prep.item.<id>.title) çözülür.
  final String? labelTr;

  /// İngilizce etiket. Preset maddelerde `null`.
  final String? labelEn;

  /// Türkçe kısa açıklama (opsiyonel).
  final String? descTr;

  /// İngilizce kısa açıklama (opsiyonel).
  final String? descEn;

  final bool checked;
  final bool custom;

  PrepItem copyWith({
    String? emoji,
    String? labelTr,
    String? labelEn,
    String? descTr,
    String? descEn,
    bool? checked,
    bool? custom,
  }) =>
      PrepItem(
        id: id,
        emoji: emoji ?? this.emoji,
        labelTr: labelTr ?? this.labelTr,
        labelEn: labelEn ?? this.labelEn,
        descTr: descTr ?? this.descTr,
        descEn: descEn ?? this.descEn,
        checked: checked ?? this.checked,
        custom: custom ?? this.custom,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'emoji': emoji,
        if (labelTr != null) 'label_tr': labelTr,
        if (labelEn != null) 'label_en': labelEn,
        if (descTr != null) 'desc_tr': descTr,
        if (descEn != null) 'desc_en': descEn,
        'checked': checked,
        'custom': custom,
      };

  factory PrepItem.fromJson(Map<String, dynamic> j) => PrepItem(
        id: (j['id'] as String?) ?? '',
        emoji: (j['emoji'] as String?) ?? '',
        labelTr: j['label_tr'] as String?,
        labelEn: j['label_en'] as String?,
        descTr: j['desc_tr'] as String?,
        descEn: j['desc_en'] as String?,
        checked: (j['checked'] as bool?) ?? false,
        custom: (j['custom'] as bool?) ?? false,
      );

  /// Kullanıcı metninden stabil id + custom PrepItem üretir. Aynı metin
  /// için her çağrıda aynı id döner (hash bazlı). Emoji boş bırakılırsa 📌.
  factory PrepItem.customFromLabel(String label, {String emoji = '📌'}) {
    final trimmed = label.trim();
    final safeEmoji = emoji.trim().isEmpty ? '📌' : emoji.trim();
    return PrepItem(
      id: 'custom-${trimmed.hashCode.toRadixString(16)}',
      emoji: safeEmoji,
      labelTr: trimmed,
      labelEn: trimmed,
      checked: false,
      custom: true,
    );
  }
}

/// Bir plan için hazırlık listesinin tüm durumu (değişmez).
class PreDepartureChecklist {
  PreDepartureChecklist({
    required this.tripId,
    required List<PrepItem> items,
    this.daysBefore = 7,
    this.updatedAt,
  }) : items = List.unmodifiable(items);

  final String tripId;

  /// Preset + custom maddelerin karışık listesi. Sıralama önemlidir —
  /// preset maddeler `kPreDeparturePresets` sırasına, custom maddeler
  /// ekleme sırasına göre saklanır.
  final List<PrepItem> items;

  /// Viewer üstünde bandın belirmeye başladığı gün eşiği (1..30). Default 7.
  final int daysBefore;

  final DateTime? updatedAt;

  /// Preset id'lerinden ve kayıtlı override'lardan tam listeyi birleştirir.
  /// Bilinmeyen preset id'ler (kod güncellendiğinde eski kayıt) atlanır;
  /// custom id'ler `true` işaretli/normal olarak korunur.
  factory PreDepartureChecklist.merged({
    required String tripId,
    required List<PrepItem> presetTemplates,
    required Iterable<PrepItem> stored,
    int daysBefore = 7,
    DateTime? updatedAt,
  }) {
    // Stored'u id ile hızlı arama için map'e al.
    final byId = <String, PrepItem>{
      for (final s in stored) s.id: s,
    };
    final merged = <PrepItem>[];
    // Preset sırasını koru, checked override'ı uygula.
    for (final tpl in presetTemplates) {
      final override = byId.remove(tpl.id);
      merged.add(
        override == null
            ? tpl
            : tpl.copyWith(checked: override.checked),
      );
    }
    // Kalan custom maddeleri (ekleme sırasında) sona al.
    for (final rest in byId.values) {
      if (rest.custom) merged.add(rest);
    }
    return PreDepartureChecklist(
      tripId: tripId,
      items: merged,
      daysBefore: daysBefore.clamp(1, 30),
      updatedAt: updatedAt,
    );
  }

  int get doneCount => items.where((i) => i.checked).length;
  int get totalCount => items.length;
  bool get allDone => totalCount > 0 && doneCount == totalCount;

  PreDepartureChecklist copyWith({
    List<PrepItem>? items,
    int? daysBefore,
    DateTime? updatedAt,
  }) =>
      PreDepartureChecklist(
        tripId: tripId,
        items: items ?? this.items,
        daysBefore: (daysBefore ?? this.daysBefore).clamp(1, 30),
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Bir maddenin işaretini değiştirir. Bilinmeyen id sessizce döner.
  PreDepartureChecklist toggle(String id) {
    var found = false;
    final next = <PrepItem>[
      for (final it in items)
        if (it.id == id) ...[
          () {
            found = true;
            return it.copyWith(checked: !it.checked);
          }(),
        ] else
          it,
    ];
    return found ? copyWith(items: next) : this;
  }

  /// Yeni bir özel madde ekler. Aynı id'li madde varsa değişmez.
  PreDepartureChecklist addCustom(PrepItem custom) {
    if (!custom.custom) {
      throw ArgumentError('addCustom yalnızca custom=true PrepItem alır');
    }
    if (items.any((it) => it.id == custom.id)) return this;
    return copyWith(items: [...items, custom]);
  }

  /// Bir özel maddeyi siler (preset ise no-op).
  PreDepartureChecklist removeCustom(String id) {
    final next = items.where((it) => !(it.custom && it.id == id)).toList();
    if (next.length == items.length) return this;
    return copyWith(items: next);
  }

  /// Görünme eşiğini günceller (1..30 arasına clamp'lenir).
  PreDepartureChecklist withDaysBefore(int n) => copyWith(daysBefore: n);

  /// Trip başlangıç tarihine göre "bugüne kadar" görünme eşiğine ulaşıp
  /// ulaşılmadığını döner. `tripStart` YYYY-MM-DD; parse edilemezse `false`.
  /// [now] test için opsiyonel — default `DateTime.now()`.
  bool shouldShowBanner(String tripStart, {DateTime? now}) {
    final start = DateTime.tryParse(tripStart);
    if (start == null) return false;
    final today = now ?? DateTime.now();
    final startDay = DateTime(start.year, start.month, start.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    // Trip başladıysa (start <= today) da banner küçük olarak gösterilebilir;
    // burada sadece "eşiğe ulaşıldı mı" testini yaparız.
    if (!todayDay.isBefore(startDay)) return true; // during / after
    final diff = startDay.difference(todayDay).inDays;
    return diff <= daysBefore;
  }

  /// Trip başlangıcına kalan gün (start dahil). Trip başladıysa 0. Parse
  /// edilemezse null.
  static int? daysUntil(String tripStart, {DateTime? now}) {
    final start = DateTime.tryParse(tripStart);
    if (start == null) return null;
    final today = now ?? DateTime.now();
    final startDay = DateTime(start.year, start.month, start.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    final diff = startDay.difference(todayDay).inDays;
    return diff < 0 ? 0 : diff;
  }

  /// Yalnızca "diff/override" maddeleri döner (checked=true olanlar +
  /// tüm custom maddeler) — storage için minimal payload. Preset+unchecked
  /// maddeler storage'a yazılmaz; okumada template ile birleştirilir.
  List<PrepItem> storableItems() => UnmodifiableListView(
        items.where((it) => it.custom || it.checked).toList(growable: false),
      );
}

// ---------------------------------------------------------------------------
// Preset maddeler.
// ---------------------------------------------------------------------------

/// Japonya'ya özel hazırlık listesi presetleri. Sıra ekranda görüldüğü sıra.
/// label/desc metinleri sözlükte `prep.item.<id>.title|desc` anahtarındadır.
const List<PrepItem> kPreDeparturePresets = [
  PrepItem(id: 'passport', emoji: '📄'),
  PrepItem(id: 'visitJapanWeb', emoji: '🎫'),
  PrepItem(id: 'bankCard', emoji: '💳'),
  PrepItem(id: 'cashYen', emoji: '💴'),
  PrepItem(id: 'powerbank', emoji: '🔋'),
  PrepItem(id: 'esim', emoji: '📱'),
  PrepItem(id: 'jrPass', emoji: '🎫'),
  PrepItem(id: 'medications', emoji: '💊'),
  PrepItem(id: 'toothpaste', emoji: '🦷'),
  PrepItem(id: 'walkingShoes', emoji: '👟'),
  PrepItem(id: 'trashBags', emoji: '🧴'),
  PrepItem(id: 'waterBottle', emoji: '💧'),
];
