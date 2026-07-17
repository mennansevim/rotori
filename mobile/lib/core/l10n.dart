// Uygulama geneli çok dilli (i18n) altyapısı — kod üretimi / ARB YOK, basit ve
// sağlam. Anahtar→{tr,en} sözlüğü + `LanguageScope` InheritedWidget resolver.
//
// Kullanım:
//   final s = LanguageScope.of(context);
//   Text(s.s('budget.converter'))                 // düz metin
//   Text(s.p('checklist.ready', {'done': '3', 'total': '8'}))  // {placeholder}
//
// Tasarım notları:
//   - `LanguageScope.of(context)` bir LanguageScope bulamazsa varsayılan olarak
//     `AppLang.tr` döner (mirror: ViewerPalette.of → japanDark). Böylece
//     LanguageScope ile sarılmamış widget'lar/testler Türkçe render eder ve
//     mevcut davranış bozulmaz.
//   - Çevrilmemiş bir anahtar istenirse (dev sinyali) anahtarın kendisi döner.
//   - Tarih ayları/günleri de burada; ekranlar dile göre diziyi seçer.

import 'package:flutter/widgets.dart';

/// Desteklenen uygulama dilleri.
enum AppLang { tr, en }

extension AppLangX on AppLang {
  /// SharedPreferences / Locale ile uyumlu string anahtar.
  String get code => switch (this) {
        AppLang.tr => 'tr',
        AppLang.en => 'en',
      };

  /// Kısa etiket (dil seçici için).
  String get label => switch (this) {
        AppLang.tr => 'Türkçe',
        AppLang.en => 'English',
      };

  static AppLang fromCode(String? raw) => switch (raw) {
        'en' => AppLang.en,
        _ => AppLang.tr,
      };
}

/// Statik çeviri motoru — sözlük çözümü + {placeholder} doldurma.
class L10n {
  const L10n._();

  /// [key] için [lang] karşılığını çözer. Yoksa TR'ye, o da yoksa anahtara düşer.
  static String resolve(String key, AppLang lang) {
    final entry = _strings[key];
    if (entry == null) return key;
    return entry[lang] ?? entry[AppLang.tr] ?? key;
  }

  /// "{done}/{total}" gibi kalıpları [params] ile doldurur.
  static String parametrize(String template, Map<String, String> params) {
    var out = template;
    params.forEach((k, v) => out = out.replaceAll('{$k}', v));
    return out;
  }

  /// 1-index'li ay adları (index 0 boş). Tarih biçimlendirme için.
  static List<String> monthsFor(AppLang lang) =>
      lang == AppLang.en ? _enMonths : _trMonths;

  /// 1-index'li gün adları (DateTime.weekday: 1=Pzt..7=Paz; index 0 boş).
  static List<String> weekdaysFor(AppLang lang) =>
      lang == AppLang.en ? _enWeekdays : _trWeekdays;
}

// ---------------------------------------------------------------------------
// Tarih dizileri.
// ---------------------------------------------------------------------------

const List<String> _trMonths = [
  '',
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

const List<String> _enMonths = [
  '',
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const List<String> _trWeekdays = [
  '',
  'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar',
];

const List<String> _enWeekdays = [
  '',
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

// ---------------------------------------------------------------------------
// LanguageScope — aktif dili alt ağaca taşıyan InheritedWidget + resolver.
// ---------------------------------------------------------------------------

class LanguageScope extends InheritedWidget {
  const LanguageScope({
    super.key,
    required this.lang,
    required super.child,
  });

  final AppLang lang;

  /// [key] için aktif dildeki metni döner.
  String s(String key) => L10n.resolve(key, lang);

  /// [key]'i çözer ve {placeholder}'ları [params] ile doldurur.
  String p(String key, Map<String, String> params) =>
      L10n.parametrize(s(key), params);

  /// En yakın [LanguageScope]; yoksa varsayılan TR resolver döner.
  static LanguageScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LanguageScope>();
    return scope ?? _fallback;
  }

  static const _fallback =
      LanguageScope(lang: AppLang.tr, child: SizedBox.shrink());

  @override
  bool updateShouldNotify(LanguageScope oldWidget) => oldWidget.lang != lang;
}

// ---------------------------------------------------------------------------
// String tablosu — anahtar → {tr, en}.
//
// Kapsam: VIEWER (gezgin) ekranları. Planner ekranları şimdilik yalnızca TR
// (bilinçli — bkz. rapor). Domain veri etiketleri (compass_data, packing_data,
// weather_service label'ları, gün temaları) TR bırakıldı.
// ---------------------------------------------------------------------------

const Map<String, Map<AppLang, String>> _strings = {
  // ----- Ortak -----
  'common.cancel': {AppLang.tr: 'İptal', AppLang.en: 'Cancel'},
  'common.save': {AppLang.tr: 'Kaydet', AppLang.en: 'Save'},
  'common.add': {AppLang.tr: 'Ekle', AppLang.en: 'Add'},
  'common.delete': {AppLang.tr: 'Sil', AppLang.en: 'Delete'},
  'common.copy': {AppLang.tr: 'Kopyala', AppLang.en: 'Copy'},

  // ----- Dil seçici -----
  'lang.title': {AppLang.tr: 'Dil / Language', AppLang.en: 'Dil / Language'},

  // ----- Plan viewer -----
  'viewer.loadFailed': {
    AppLang.tr: 'Yüklenemedi: {err}',
    AppLang.en: 'Failed to load: {err}',
  },
  'viewer.phase.new': {AppLang.tr: '✈️ Yeni plan', AppLang.en: '✈️ New plan'},
  'viewer.phase.done': {
    AppLang.tr: '✨ Plan tamamlandı',
    AppLang.en: '✨ Trip complete',
  },
  'viewer.phase.during': {
    AppLang.tr: '🎉 Tatil başladı',
    AppLang.en: '🎉 Trip started',
  },
  'viewer.phase.countdown': {
    AppLang.tr: '🇯🇵 Tatile {d}g {h}s',
    AppLang.en: '🇯🇵 {d}d {h}h to go',
  },
  'viewer.tt.back': {AppLang.tr: 'Geri', AppLang.en: 'Back'},
  'viewer.tt.reminders': {AppLang.tr: 'Hatırlatmalar', AppLang.en: 'Reminders'},
  'viewer.tt.map': {AppLang.tr: 'Keşif haritası', AppLang.en: 'Explore map'},
  'viewer.tt.compass': {AppLang.tr: 'Pusula', AppLang.en: 'Compass'},
  'viewer.tt.weather': {AppLang.tr: 'Hava', AppLang.en: 'Weather'},
  'viewer.tt.budget': {AppLang.tr: 'Bütçe', AppLang.en: 'Budget'},
  'viewer.tt.checklist': {AppLang.tr: 'Valiz', AppLang.en: 'Packing'},
  'viewer.tt.theme': {AppLang.tr: 'Tema', AppLang.en: 'Theme'},
  'viewer.tt.edit': {AppLang.tr: 'Düzenle', AppLang.en: 'Edit'},
  'viewer.heroPill': {
    AppLang.tr: '✈️ {days} Gün · {nights} Gece',
    AppLang.en: '✈️ {days} Days · {nights} Nights',
  },
  'viewer.days.title': {AppLang.tr: '📅 Günler ({n})', AppLang.en: '📅 Days ({n})'},
  'viewer.stat.nights': {AppLang.tr: 'Gece Konaklama', AppLang.en: 'Nights Stay'},
  'viewer.stat.cityNights': {
    AppLang.tr: '{city} Gecesi',
    AppLang.en: '{city} Nights',
  },
  'viewer.stat.tickets': {AppLang.tr: 'Bilet', AppLang.en: 'Tickets'},
  'viewer.stat.days': {AppLang.tr: 'Gün', AppLang.en: 'Days'},
  'viewer.emptyDays': {
    AppLang.tr: 'Bu plana henüz gün eklenmedi. Düzenle → gün ekle.',
    AppLang.en: 'No days added to this plan yet. Edit → add days.',
  },
  'viewer.flights': {AppLang.tr: '✈️ Uçuşlar', AppLang.en: '✈️ Flights'},
  'viewer.stays': {AppLang.tr: '🏨 Konaklama', AppLang.en: '🏨 Stays'},
  'viewer.day.noItems': {
    AppLang.tr: '(Bu güne aktivite eklenmedi.)',
    AppLang.en: '(No activities added for this day.)',
  },
  'viewer.day.viewOnMap': {
    AppLang.tr: '🗺️ Haritada gör',
    AppLang.en: '🗺️ View on map',
  },
  'viewer.day.taxi': {
    AppLang.tr: '🚕 Taksi önerilir',
    AppLang.en: '🚕 Taxi recommended',
  },
  'viewer.item.next': {AppLang.tr: 'Sıradaki', AppLang.en: 'Next'},
  'viewer.theme.title': {AppLang.tr: 'Tema', AppLang.en: 'Theme'},
  // Tema adları (React data-theme).
  'theme.japanDark': {AppLang.tr: 'Japon Gecesi', AppLang.en: 'Japan Night'},
  'theme.appleLight': {AppLang.tr: 'Apple Aydınlık', AppLang.en: 'Apple Light'},
  'theme.sakuraSoft': {AppLang.tr: 'Sakura Yumuşak', AppLang.en: 'Sakura Soft'},

  // ----- Pusula (compass) -----
  'compass.title': {AppLang.tr: '🧭 Pusula', AppLang.en: '🧭 Compass'},
  'compass.subtitle': {
    AppLang.tr: 'Cebinde taşı — acil, dil, kültür',
    AppLang.en: 'Keep it in your pocket — emergencies, language, culture',
  },
  'compass.numberCopied': {
    AppLang.tr: 'Numara kopyalandı: {n}',
    AppLang.en: 'Number copied: {n}',
  },
  'compass.addressCopied': {
    AppLang.tr: 'Adres kopyalandı',
    AppLang.en: 'Address copied',
  },
  'compass.copied': {AppLang.tr: 'Kopyalandı: {n}', AppLang.en: 'Copied: {n}'},
  'compass.emergency.title': {
    AppLang.tr: 'Acil Numaralar',
    AppLang.en: 'Emergency Numbers',
  },
  'compass.emergency.subtitle': {
    AppLang.tr: 'Japonya · dokun, kopyalansın',
    AppLang.en: 'Japan · tap to copy',
  },
  'compass.hotel.title': {AppLang.tr: 'Otel adresi', AppLang.en: 'Hotel address'},
  'compass.hotel.subtitle': {
    AppLang.tr: 'Taksiciye göster',
    AppLang.en: 'Show to the taxi driver',
  },
  'compass.phrases.title': {
    AppLang.tr: 'Japonca fraz kartları',
    AppLang.en: 'Japanese phrase cards',
  },
  'compass.phrases.subtitle': {
    AppLang.tr: 'Cümleye dokun, kopyalansın',
    AppLang.en: 'Tap a phrase to copy',
  },

  // ----- Bütçe (budget) -----
  'budget.title': {AppLang.tr: '💰 Bütçe', AppLang.en: '💰 Budget'},
  'budget.editRate': {AppLang.tr: 'Kuru düzenle', AppLang.en: 'Edit rate'},
  'budget.rateQuestion': {
    AppLang.tr: '1 ¥ kaç ₺?',
    AppLang.en: 'How many ₺ per ¥?',
  },
  'budget.rateManual': {
    AppLang.tr: 'Kur elle güncellenir (çevrimdışı).',
    AppLang.en: 'Rate updated manually (offline).',
  },
  'budget.total': {
    AppLang.tr: 'Toplam tahmini harcama',
    AppLang.en: 'Total estimated spending',
  },
  'budget.perPerson': {AppLang.tr: 'Kişi başı', AppLang.en: 'Per person'},
  'budget.perPersonValue': {
    AppLang.tr: '{amount} ({n} kişi)',
    AppLang.en: '{amount} ({n} people)',
  },
  'budget.itemsWithCost': {
    AppLang.tr: '{done}/{total} öğede maliyet girili',
    AppLang.en: '{done}/{total} items have a cost',
  },
  'budget.exchangeRate': {AppLang.tr: 'Döviz kuru', AppLang.en: 'Exchange rate'},
  'budget.byCategory': {AppLang.tr: 'Kategoriye göre', AppLang.en: 'By category'},
  'budget.byDay': {AppLang.tr: 'Güne göre', AppLang.en: 'By day'},
  'budget.foodBudget': {AppLang.tr: 'Yemek bütçesi', AppLang.en: 'Food budget'},
  'budget.planned': {AppLang.tr: 'Planlanan ', AppLang.en: 'Planned '},
  'budget.actual': {AppLang.tr: ' · Gerçekleşen ', AppLang.en: ' · Actual '},
  'budget.over': {
    AppLang.tr: 'Bütçe aşıldı — planlanandan {n} fazla.',
    AppLang.en: 'Over budget — {n} more than planned.',
  },
  'budget.under': {
    AppLang.tr: 'Bütçe içinde — {n} kaldı.',
    AppLang.en: 'Within budget — {n} left.',
  },
  'budget.noFood': {
    AppLang.tr: 'Henüz planlanan yemek bütçesi yok.',
    AppLang.en: 'No planned food budget yet.',
  },
  'budget.converter': {AppLang.tr: 'Çevirici', AppLang.en: 'Converter'},
  'budget.yen': {AppLang.tr: 'Japon Yeni (¥)', AppLang.en: 'Japanese Yen (¥)'},
  'budget.lira': {AppLang.tr: 'Türk Lirası (₺)', AppLang.en: 'Turkish Lira (₺)'},
  'budget.empty': {
    AppLang.tr:
        'Planda henüz maliyet girilmemiş — Plan adımında aktivitelere ücret ekleyin.',
    AppLang.en:
        'No costs entered in the plan yet — add prices to activities in the Plan step.',
  },
  // Kategori adları (budget kind).
  'kind.activity': {AppLang.tr: 'Aktivite', AppLang.en: 'Activity'},
  'kind.meal': {AppLang.tr: 'Yemek', AppLang.en: 'Food'},
  'kind.transport': {AppLang.tr: 'Ulaşım', AppLang.en: 'Transport'},
  'kind.hotel': {AppLang.tr: 'Otel', AppLang.en: 'Hotel'},

  // ----- Valiz & Hazırlık (checklist) -----
  'checklist.title': {
    AppLang.tr: '🎒 Valiz & Hazırlık',
    AppLang.en: '🎒 Packing & Prep',
  },
  'checklist.reset': {AppLang.tr: 'Sıfırla', AppLang.en: 'Reset'},
  'checklist.resetConfirmTitle': {
    AppLang.tr: 'Listeyi sıfırla?',
    AppLang.en: 'Reset the list?',
  },
  'checklist.resetConfirmBody': {
    AppLang.tr: 'Tüm işaretler ve eklediğin özel maddeler silinecek.',
    AppLang.en: 'All checks and your custom items will be removed.',
  },
  'checklist.addOwn': {
    AppLang.tr: 'Kendi maddeni ekle',
    AppLang.en: 'Add your own item',
  },
  'checklist.category': {AppLang.tr: 'Kategori', AppLang.en: 'Category'},
  'checklist.item': {AppLang.tr: 'Madde', AppLang.en: 'Item'},
  'checklist.allReady': {
    AppLang.tr: '✅ Her şey hazır!',
    AppLang.en: '✅ All set!',
  },
  'checklist.status': {AppLang.tr: 'Hazırlık durumu', AppLang.en: 'Prep status'},
  'checklist.ready': {
    AppLang.tr: '{done} / {total} hazır',
    AppLang.en: '{done} / {total} ready',
  },
  'checklist.customBadge': {AppLang.tr: 'özel', AppLang.en: 'custom'},

  // ----- Hava durumu (weather) -----
  'weather.title': {AppLang.tr: '🌤️ Hava Durumu', AppLang.en: '🌤️ Weather'},
  'weather.loading': {
    AppLang.tr: 'Hava durumu yükleniyor…',
    AppLang.en: 'Loading weather…',
  },
  'weather.error': {
    AppLang.tr: 'Hava durumu alınamadı — internet bağlantısını kontrol et',
    AppLang.en: "Couldn't load weather — check your internet connection",
  },
  'weather.retry': {AppLang.tr: 'Tekrar dene', AppLang.en: 'Try again'},
  'weather.forecastTravel': {
    AppLang.tr: 'Seyahat günlerin için tahmin',
    AppLang.en: 'Forecast for your travel days',
  },
  'weather.forecastUpcoming': {
    AppLang.tr: 'Önümüzdeki günler için tahmin',
    AppLang.en: 'Forecast for the coming days',
  },
  'weather.today': {AppLang.tr: 'Bugün', AppLang.en: 'Today'},
  'weather.source': {
    AppLang.tr: 'Kaynak: Open-Meteo',
    AppLang.en: 'Source: Open-Meteo',
  },
  'weather.empty': {
    AppLang.tr: 'Bu konum için tahmin bulunamadı.',
    AppLang.en: 'No forecast found for this location.',
  },
};
