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

  // ===== Planner + shared UI (Wave 1, agent-generated) =====
  'explore.title': {AppLang.tr: 'Keşfet', AppLang.en: 'Explore'},
  'explore.emptyAirports': {AppLang.tr: 'Önce Rota adımında varış havaalanlarını seçin.', AppLang.en: 'First choose your arrival airports in the Route step.'},
  'explore.sub': {AppLang.tr: 'Uçuş güzergahınıza göre popüler yerler ve varışta yapılacaklar. Beğendiğinizi tek dokunuşla plana ekleyin.', AppLang.en: 'Popular places and things to do along your flight route. Add the ones you like to your plan with a single tap.'},
  'explore.interests.title': {AppLang.tr: '🎯 İlgi alanların', AppLang.en: '🎯 Your interests'},
  'explore.interests.hint': {AppLang.tr: 'Birden fazla seç. Plan bunlara göre yönlendirilir.', AppLang.en: 'Pick several. Your plan is guided by these.'},
  'explore.style.title': {AppLang.tr: '🚶 Gezi stili', AppLang.en: '🚶 Travel style'},
  'explore.style.hint': {AppLang.tr: 'Yürüyüş hedefi, ulaşım ve ödeme tercihini seç.', AppLang.en: 'Choose your walking goal, transport and payment preference.'},
  'explore.style.walkLabel': {AppLang.tr: 'Yürüyüş tempon', AppLang.en: 'Walking pace'},
  'explore.style.transportLabel': {AppLang.tr: 'Ulaşım tercihi', AppLang.en: 'Transport preference'},
  'explore.style.paymentLabel': {AppLang.tr: 'Ödeme tercihi', AppLang.en: 'Payment preference'},
  'explore.mustSee.title': {AppLang.tr: '📌 Mutlaka görmek istediklerin', AppLang.en: '📌 Your must-see places'},
  'explore.mustSee.hint': {AppLang.tr: 'Serbest liste — plan oluştururken önceliklendirilir.', AppLang.en: 'Free-form list — prioritized when building your plan.'},
  'explore.popularPlaces': {AppLang.tr: '⭐ Popüler gezilecek yerler', AppLang.en: '⭐ Popular places to visit'},
  'explore.suggestKidRoute': {AppLang.tr: '🧸 Çocuk dostu rota öner', AppLang.en: '🧸 Suggest a kid-friendly route'},
  'explore.tapToAddHint': {AppLang.tr: 'Dokunarak ekle · ✓ rozetli karta tekrar dokun → çıkar', AppLang.en: 'Tap to add · tap a ✓ card again → remove'},
  'explore.removedFromPlan': {AppLang.tr: '✓ Plandan çıkarıldı', AppLang.en: '✓ Removed from plan'},
  'explore.addedToDay': {AppLang.tr: '✓ Gün {day}\'e eklendi', AppLang.en: '✓ Added to day {day}'},
  'explore.kidRouteDistributed': {AppLang.tr: '✓ {places} yer {days} güne dağıtıldı', AppLang.en: '✓ {places} spots spread across {days} days'},
  'explore.dayFallback': {AppLang.tr: 'Gün {n}', AppLang.en: 'Day {n}'},
  'food.title': {AppLang.tr: 'Yemek', AppLang.en: 'Food'},
  'food.emptyStops': {AppLang.tr: 'Önce Rota adımında durak ekleyin.', AppLang.en: 'First add stops in the Route step.'},
  'food.prefsTitle': {AppLang.tr: 'Yemek tercihleri', AppLang.en: 'Food preferences'},
  'food.prefsSub': {AppLang.tr: 'Hassasiyetlerini seç — plan ve restoran önerileri buna göre filtrelenir.', AppLang.en: 'Pick your sensitivities — plans and restaurant suggestions are filtered accordingly.'},
  'food.sensTitle': {AppLang.tr: '🍽️ Yemek hassasiyetleri', AppLang.en: '🍽️ Food sensitivities'},
  'food.sensNote': {AppLang.tr: 'Bu seçimler tüm gezi için geçerlidir; viewer\'da hap bilgi ve fraz kartlarına yansır.', AppLang.en: 'These choices apply to the whole trip; they show up as info pills and phrase cards in the viewer.'},
  'food.mealPerPerson': {AppLang.tr: 'Kişi başı öğün ({currency})', AppLang.en: 'Per-person meal ({currency})'},
  'food.currency': {AppLang.tr: 'Para birimi', AppLang.en: 'Currency'},
  'food.addMeals': {AppLang.tr: 'Öğünleri plana ekle', AppLang.en: 'Add meals to the plan'},
  'food.addMealsHint': {AppLang.tr: 'Gezi planı oluşturulurken öğle/akşam yemeği durakları eklenir.', AppLang.en: 'Lunch and dinner stops are added when the trip plan is generated.'},
  'food.viewerNote': {AppLang.tr: 'Yemek önerileri Rehber\'de (viewer) — bu hassasiyetlere göre restoranları orada listeliyoruz.', AppLang.en: 'Food suggestions live in the Guide (viewer) — we list restaurants there based on these sensitivities.'},
  'food.sens.noPork': {AppLang.tr: 'Domuz eti istemiyorum', AppLang.en: 'No pork'},
  'food.sens.noPorkDerivatives': {AppLang.tr: 'Domuz yağı / jelatin yok', AppLang.en: 'No pork fat / gelatin'},
  'food.sens.noSeafood': {AppLang.tr: 'Deniz ürünü istemiyorum', AppLang.en: 'No seafood'},
  'food.sens.halal': {AppLang.tr: 'Helal seçenek istiyorum', AppLang.en: 'Halal options'},
  'food.sens.vegetarian': {AppLang.tr: 'Vejetaryen', AppLang.en: 'Vegetarian'},
  'food.sens.chicken': {AppLang.tr: 'Tavuk ağırlıklı', AppLang.en: 'Chicken-focused'},
  'food.sens.noFattyMeat': {AppLang.tr: 'Yağlı et sevmiyorum', AppLang.en: 'No fatty meat'},
  'food.sens.kidFriendly': {AppLang.tr: 'Çocuk dostu restoran', AppLang.en: 'Kid-friendly restaurants'},
  'food.sens.turkishPalate': {AppLang.tr: 'Türk damak tadına yakın', AppLang.en: 'Close to Turkish taste'},
  'opt.interest.anime': {AppLang.tr: 'Anime / Manga', AppLang.en: 'Anime / Manga'},
  'opt.interest.pokemon': {AppLang.tr: 'Pokémon', AppLang.en: 'Pokémon'},
  'opt.interest.shopping': {AppLang.tr: 'Alışveriş', AppLang.en: 'Shopping'},
  'opt.interest.temples': {AppLang.tr: 'Tapınaklar', AppLang.en: 'Temples'},
  'opt.interest.traditional': {AppLang.tr: 'Geleneksel Japonya', AppLang.en: 'Traditional Japan'},
  'opt.interest.tech': {AppLang.tr: 'Teknoloji mağazaları', AppLang.en: 'Tech stores'},
  'opt.interest.kids': {AppLang.tr: 'Çocuk aktiviteleri', AppLang.en: 'Kids activities'},
  'opt.interest.themeParks': {AppLang.tr: 'Tema parkları', AppLang.en: 'Theme parks'},
  'opt.interest.photography': {AppLang.tr: 'Fotoğraf noktaları', AppLang.en: 'Photo spots'},
  'opt.interest.food': {AppLang.tr: 'Yemek keşfi', AppLang.en: 'Food discovery'},
  'opt.interestW.temples': {AppLang.tr: 'Tapınaklar', AppLang.en: 'Temples'},
  'opt.interestW.traditional': {AppLang.tr: 'Geleneksel', AppLang.en: 'Traditional'},
  'opt.interestW.anime': {AppLang.tr: 'Anime & manga', AppLang.en: 'Anime & manga'},
  'opt.interestW.pokemon': {AppLang.tr: 'Pokemon & oyun', AppLang.en: 'Pokémon & games'},
  'opt.interestW.tech': {AppLang.tr: 'Teknoloji', AppLang.en: 'Tech'},
  'opt.interestW.shopping': {AppLang.tr: 'Alışveriş', AppLang.en: 'Shopping'},
  'opt.interestW.food': {AppLang.tr: 'Yemek odaklı', AppLang.en: 'Food-focused'},
  'opt.interestW.themeParks': {AppLang.tr: 'Tema parklar', AppLang.en: 'Theme parks'},
  'opt.interestW.kids': {AppLang.tr: 'Çocuk dostu', AppLang.en: 'Kid-friendly'},
  'opt.interestW.photography': {AppLang.tr: 'Fotoğrafçılık', AppLang.en: 'Photography'},
  'opt.sens.noPork': {AppLang.tr: 'Domuz eti istemiyorum', AppLang.en: 'No pork'},
  'opt.sens.noPorkDerivatives': {AppLang.tr: 'Domuz yağı / jelatin yok', AppLang.en: 'No pork fat / gelatin'},
  'opt.sens.noSeafood': {AppLang.tr: 'Deniz ürünü istemiyorum', AppLang.en: 'No seafood'},
  'opt.sens.halal': {AppLang.tr: 'Helal seçenek istiyorum', AppLang.en: 'Halal options'},
  'opt.sens.vegetarian': {AppLang.tr: 'Vejetaryen', AppLang.en: 'Vegetarian'},
  'opt.sens.chicken': {AppLang.tr: 'Tavuk ağırlıklı', AppLang.en: 'Chicken-focused'},
  'opt.sens.noFattyMeat': {AppLang.tr: 'Yağlı et sevmiyorum', AppLang.en: 'No fatty meat'},
  'opt.sens.kidFriendly': {AppLang.tr: 'Çocuk dostu restoran', AppLang.en: 'Kid-friendly restaurants'},
  'opt.sens.turkishPalate': {AppLang.tr: 'Türk damak tadına yakın', AppLang.en: 'Close to Turkish taste'},
  'opt.walk.light': {AppLang.tr: 'Az', AppLang.en: 'Light'},
  'opt.walk.light.hint': {AppLang.tr: '~7k adım/gün', AppLang.en: '~7k steps/day'},
  'opt.walk.moderate': {AppLang.tr: 'Orta', AppLang.en: 'Moderate'},
  'opt.walk.moderate.hint': {AppLang.tr: '~11k adım/gün', AppLang.en: '~11k steps/day'},
  'opt.walk.intense': {AppLang.tr: 'Yoğun', AppLang.en: 'Intense'},
  'opt.walk.intense.hint': {AppLang.tr: '~15k+ adım/gün', AppLang.en: '~15k+ steps/day'},
  'opt.transport.transit': {AppLang.tr: 'Toplu taşıma', AppLang.en: 'Public transit'},
  'opt.transport.mixed': {AppLang.tr: 'Karışık', AppLang.en: 'Mixed'},
  'opt.transport.taxi': {AppLang.tr: 'Taksi destekli', AppLang.en: 'Taxi-assisted'},
  'opt.transport.walking': {AppLang.tr: 'Yürüyüş ağırlıklı', AppLang.en: 'Mostly walking'},
  'opt.payment.card': {AppLang.tr: 'Kredi kartı', AppLang.en: 'Credit card'},
  'opt.payment.cash': {AppLang.tr: 'Nakit', AppLang.en: 'Cash'},
  'opt.payment.cardCash': {AppLang.tr: 'Kart + nakit', AppLang.en: 'Card + cash'},
  'opt.payment.ic': {AppLang.tr: 'IC kart (Suica/Pasmo)', AppLang.en: 'IC card (Suica/Pasmo)'},
  'opt.pace.relaxed': {AppLang.tr: 'Rahat', AppLang.en: 'Relaxed'},
  'opt.pace.relaxed.hint': {AppLang.tr: 'Az durak, uzun molalar', AppLang.en: 'Fewer stops, long breaks'},
  'opt.pace.moderate': {AppLang.tr: 'Dengeli', AppLang.en: 'Balanced'},
  'opt.pace.moderate.hint': {AppLang.tr: 'Standart tempo', AppLang.en: 'Standard pace'},
  'opt.pace.intense': {AppLang.tr: 'Yoğun', AppLang.en: 'Intense'},
  'opt.pace.intense.hint': {AppLang.tr: 'Çok yer, sıkı program', AppLang.en: 'Many spots, packed schedule'},
  'diet.halal.label': {AppLang.tr: 'Helal', AppLang.en: 'Halal'},
  'diet.halal.desc': {AppLang.tr: 'Helal sertifikalı veya domuzsuz seçenekler', AppLang.en: 'Halal-certified or pork-free options'},
  'diet.noPork.label': {AppLang.tr: 'Domuz yok', AppLang.en: 'No pork'},
  'diet.noPork.desc': {AppLang.tr: 'Domuz eti ve domuz yağı içermesin', AppLang.en: 'No pork meat or pork fat'},
  'diet.vegetarian.label': {AppLang.tr: 'Vejetaryen', AppLang.en: 'Vegetarian'},
  'diet.vegetarian.desc': {AppLang.tr: 'Et ve balık yok, yumurta/süt olabilir', AppLang.en: 'No meat or fish; eggs/dairy allowed'},
  'diet.vegan.label': {AppLang.tr: 'Vegan', AppLang.en: 'Vegan'},
  'diet.vegan.desc': {AppLang.tr: 'Hayvansal ürün yok', AppLang.en: 'No animal products'},
  'diet.lowFat.label': {AppLang.tr: 'Yağsız / hafif', AppLang.en: 'Low-fat / light'},
  'diet.lowFat.desc': {AppLang.tr: 'Kızartma ve ağır soslardan kaçın', AppLang.en: 'Avoid fried food and heavy sauces'},
  'diet.noAlcohol.label': {AppLang.tr: 'Alkolsüz', AppLang.en: 'Alcohol-free'},
  'diet.noAlcohol.desc': {AppLang.tr: 'Yemeklerde alkol kullanılmasın', AppLang.en: 'No alcohol used in dishes'},
  'diet.bakeryOk.label': {AppLang.tr: 'Hamur işi OK', AppLang.en: 'Baked goods OK'},
  'diet.bakeryOk.desc': {AppLang.tr: 'Ekmek, noodle, unlu atıştırmalıklar uygun', AppLang.en: 'Bread, noodles and flour-based snacks are fine'},
  'diet.meatOk.label': {AppLang.tr: 'Et sever', AppLang.en: 'Meat lover'},
  'diet.meatOk.desc': {AppLang.tr: 'Wagyu, yakiniku, et ağırlıklı menüler', AppLang.en: 'Wagyu, yakiniku, meat-heavy menus'},
  'diet.chickenOnly.label': {AppLang.tr: 'Tavuk / hindi', AppLang.en: 'Chicken / turkey'},
  'diet.chickenOnly.desc': {AppLang.tr: 'Kırmızı et yerine tavuk tercih', AppLang.en: 'Prefer chicken over red meat'},
  'diet.seafoodOk.label': {AppLang.tr: 'Deniz ürünü', AppLang.en: 'Seafood'},
  'diet.seafoodOk.desc': {AppLang.tr: 'Sushi, sashimi, deniz ürünleri uygun', AppLang.en: 'Sushi, sashimi and seafood are fine'},
  'diet.glutenFree.label': {AppLang.tr: 'Glutensiz', AppLang.en: 'Gluten-free'},
  'diet.glutenFree.desc': {AppLang.tr: 'Buğday / gluten hassasiyeti', AppLang.en: 'Wheat / gluten sensitivity'},
  'diet.spicyOk.label': {AppLang.tr: 'Acı sever', AppLang.en: 'Loves spicy'},
  'diet.spicyOk.desc': {AppLang.tr: 'Acı ve baharatlı yemekler uygun', AppLang.en: 'Spicy and heavily seasoned food is fine'},
  'diet.spicyAvoid.label': {AppLang.tr: 'Acı istemiyorum', AppLang.en: 'No spicy'},
  'diet.spicyAvoid.desc': {AppLang.tr: 'Acı sos ve gochujang azaltılsın', AppLang.en: 'Reduce chili sauce and gochujang'},
  'hotels.title': {AppLang.tr: 'Konaklama', AppLang.en: 'Stays'},
  'hotels.subtitle': {AppLang.tr: 'Otel eklemek zorunda değilsin — konaklanacak bölgeyi yazmak yeter (taksi/rehber için). Otel ekleyeceksen açık adres gerekir.', AppLang.en: 'You don\'t have to add a hotel — just naming the area you\'ll stay in is enough (for taxis and guides). If you do add one, a full address is required.'},
  'hotels.stayArea': {AppLang.tr: '🏘️ Konaklanacak bölge (opsiyonel)', AppLang.en: '🏘️ Area to stay (optional)'},
  'hotels.stayAreaHint': {AppLang.tr: 'Otel eklemesen de bu bölge adı taksi/rehberde kullanılır.', AppLang.en: 'Even without a hotel, this area name is used for taxis and guides.'},
  'hotels.stayAreaPlaceholder': {AppLang.tr: 'Örn. Shinjuku, Namba, Kyoto istasyon çevresi', AppLang.en: 'e.g. Shinjuku, Namba, around Kyoto Station'},
  'hotels.emptyHint': {AppLang.tr: 'Otel eklemek istersen aşağıdan ekle — istemiyorsan bölge yazmak yeterli.', AppLang.en: 'Add a hotel below if you\'d like — otherwise naming the area is enough.'},
  'hotels.addHotel': {AppLang.tr: '+ Otel ekle', AppLang.en: '+ Add hotel'},
  'hotels.addAnother': {AppLang.tr: '+ Başka otel ekle', AppLang.en: '+ Add another hotel'},
  'hotels.deleteTitle': {AppLang.tr: 'Oteli sil', AppLang.en: 'Delete hotel'},
  'hotels.deleteConfirm': {AppLang.tr: '"{name}" silinsin mi?', AppLang.en: 'Delete "{name}"?'},
  'hotels.cancel': {AppLang.tr: 'Vazgeç', AppLang.en: 'Cancel'},
  'hotels.delete': {AppLang.tr: 'Sil', AppLang.en: 'Delete'},
  'hotels.hotelN': {AppLang.tr: 'Otel {n}', AppLang.en: 'Hotel {n}'},
  'hotels.addressRequired': {AppLang.tr: 'Taksi ve harita için adres gerekli', AppLang.en: 'Address required for taxis and maps'},
  'hotels.edit': {AppLang.tr: 'Düzenle', AppLang.en: 'Edit'},
  'hotels.city': {AppLang.tr: 'Şehir *', AppLang.en: 'City *'},
  'hotels.hotelName': {AppLang.tr: 'Otel adı *', AppLang.en: 'Hotel name *'},
  'hotels.checkIn': {AppLang.tr: 'Giriş *', AppLang.en: 'Check-in *'},
  'hotels.checkOut': {AppLang.tr: 'Çıkış *', AppLang.en: 'Check-out *'},
  'hotels.address': {AppLang.tr: 'Açık adres (sokak, posta kodu) *', AppLang.en: 'Full address (street, postal code) *'},
  'hotels.addressLocal': {AppLang.tr: 'Adres (yerel dil)', AppLang.en: 'Address (local language)'},
  'hotels.addressLocalHint': {AppLang.tr: 'Japonca — taksiciye göster', AppLang.en: 'Japanese — show it to the taxi driver'},
  'hotels.mapsUrl': {AppLang.tr: 'Google Maps linki', AppLang.en: 'Google Maps link'},
  'hotels.phone': {AppLang.tr: 'Telefon', AppLang.en: 'Phone'},
  'hotels.notes': {AppLang.tr: 'Notlar', AppLang.en: 'Notes'},
  'hotels.notesPlaceholder': {AppLang.tr: 'Check-in saati, kat, ek notlar', AppLang.en: 'Check-in time, floor, extra notes'},
  'hotels.done': {AppLang.tr: 'Bitti', AppLang.en: 'Done'},
  'hotels.pickDate': {AppLang.tr: 'Tarih seç', AppLang.en: 'Pick a date'},
  'publish.title': {AppLang.tr: 'Yayına hazır', AppLang.en: 'Ready to publish'},
  'publish.subtitle': {AppLang.tr: 'Planınız "{slug}" kullanıcısı altında kaydedildi. Uyarıları çözüp Rehber\'e (viewer) geçebilirsin.', AppLang.en: 'Your plan is saved under the "{slug}" user. Resolve the warnings, then move on to the Guide (viewer).'},
  'publish.backToStep': {AppLang.tr: '{step} adımına dön →', AppLang.en: 'Back to {step} →'},
  'publish.export': {AppLang.tr: 'Dışa aktar', AppLang.en: 'Export'},
  'publish.import': {AppLang.tr: 'İçe aktar', AppLang.en: 'Import'},
  'publish.lockNote': {AppLang.tr: 'Yayın kilidi: plan boşsa yayın adımı kilitli kalır — viewer boş ekran açmasın diye. En az bir aktivite ekle.', AppLang.en: 'Publish lock: if the plan is empty, the publish step stays locked — so the viewer never opens to a blank screen. Add at least one activity.'},
  'publish.exportTitle': {AppLang.tr: 'JSON dışa aktar', AppLang.en: 'Export JSON'},
  'publish.jsonCopied': {AppLang.tr: '✓ JSON kopyalandı', AppLang.en: '✓ JSON copied'},
  'publish.copy': {AppLang.tr: 'Kopyala', AppLang.en: 'Copy'},
  'publish.close': {AppLang.tr: 'Kapat', AppLang.en: 'Close'},
  'publish.importTitle': {AppLang.tr: 'JSON içe aktar', AppLang.en: 'Import JSON'},
  'publish.importHint': {AppLang.tr: 'Buraya Trip JSON yapıştır…', AppLang.en: 'Paste Trip JSON here…'},
  'publish.cancel': {AppLang.tr: 'Vazgeç', AppLang.en: 'Cancel'},
  'publish.imported': {AppLang.tr: '✓ Plan içe aktarıldı', AppLang.en: '✓ Plan imported'},
  'publish.invalidJson': {AppLang.tr: 'Geçersiz JSON: {err}', AppLang.en: 'Invalid JSON: {err}'},
  'publish.step.journey': {AppLang.tr: 'Rota', AppLang.en: 'Route'},
  'publish.step.explore': {AppLang.tr: 'Keşfet', AppLang.en: 'Explore'},
  'publish.step.title': {AppLang.tr: 'Başlık', AppLang.en: 'Title'},
  'publish.step.hotels': {AppLang.tr: 'Konaklama', AppLang.en: 'Stays'},
  'publish.step.food': {AppLang.tr: 'Yemek', AppLang.en: 'Food'},
  'publish.step.plan': {AppLang.tr: 'Plan', AppLang.en: 'Plan'},
  'publish.step.calendar': {AppLang.tr: 'Takvim', AppLang.en: 'Calendar'},
  'booking.title': {AppLang.tr: 'Bilet açılış tarihleri', AppLang.en: 'Ticket sale dates'},
  'booking.body': {AppLang.tr: 'Planına eklenen aşağıdaki deneyimlerin biletleri sınırlı süreyle satışa açılıyor. Hatırlatma açarsan bilet satışa çıktığı gün sabah 09:00\'da bildirim geleceğim.', AppLang.en: 'Tickets for the experiences below in your plan go on sale for a limited time. Turn on a reminder and I\'ll notify you at 09:00 on the morning they open.'},
  'booking.notNow': {AppLang.tr: 'Şimdi değil', AppLang.en: 'Not now'},
  'booking.adding': {AppLang.tr: 'Ekleniyor…', AppLang.en: 'Adding…'},
  'booking.addReminders': {AppLang.tr: 'Hatırlatmaları ekle', AppLang.en: 'Add reminders'},
  'booking.reminderSubtitle': {AppLang.tr: 'Bilet bugün satışa açıldı — {date} planı için.', AppLang.en: 'Tickets went on sale today — for your {date} plan.'},
  'booking.salePill': {AppLang.tr: 'Satış: {date} · {days} gün önce', AppLang.en: 'On sale: {date} · {days} days before'},
  'booking.planDayPill': {AppLang.tr: 'Plan günü: {date}', AppLang.en: 'Plan day: {date}'},
  'booking.windowPassed': {AppLang.tr: 'Satış penceresi geçti / bugün', AppLang.en: 'Sale window passed / today'},
  'pickers.airportPlaceholder': {AppLang.tr: 'Havaalanı, şehir veya ülke', AppLang.en: 'Airport, city or country'},
  'pickers.airlinePlaceholder': {AppLang.tr: 'Havayolu (örn. Turkish Airlines, TK)', AppLang.en: 'Airline (e.g. Turkish Airlines, TK)'},
  'pickers.pickAirport': {AppLang.tr: 'Havaalanı seç', AppLang.en: 'Select airport'},
  'pickers.airportSearchHint': {AppLang.tr: 'IATA, şehir veya ülke', AppLang.en: 'IATA, city or country'},
  'pickers.pickAirline': {AppLang.tr: 'Havayolu seç', AppLang.en: 'Select airline'},
  'pickers.airlineSearchHint': {AppLang.tr: 'Ad veya kod (TK, JL…)', AppLang.en: 'Name or code (TK, JL…)'},
  'pickers.close': {AppLang.tr: 'Kapat', AppLang.en: 'Close'},
  'steps.welcome': {AppLang.tr: 'Başla', AppLang.en: 'Start'},
  'steps.journey': {AppLang.tr: 'Rota', AppLang.en: 'Route'},
  'steps.explore': {AppLang.tr: 'Keşfet', AppLang.en: 'Explore'},
  'steps.title': {AppLang.tr: 'Başlık', AppLang.en: 'Title'},
  'steps.hotels': {AppLang.tr: 'Konaklama', AppLang.en: 'Stay'},
  'steps.food': {AppLang.tr: 'Yemek', AppLang.en: 'Food'},
  'steps.plan': {AppLang.tr: 'Plan', AppLang.en: 'Plan'},
  'steps.publish': {AppLang.tr: 'Yayın', AppLang.en: 'Publish'},
  'title.autoTitle': {AppLang.tr: 'Japonya {year}', AppLang.en: 'Japan {year}'},
  'title.headline': {AppLang.tr: 'Planına isim ver', AppLang.en: 'Name your plan'},
  'title.routeSummary': {AppLang.tr: 'Rotanız: {route} · {n} gün', AppLang.en: 'Your route: {route} · {n} days'},
  'title.routeIncomplete': {AppLang.tr: 'Önce Rota adımında rotayı tamamlayın.', AppLang.en: 'First complete your route in the Route step.'},
  'title.displayName': {AppLang.tr: 'Görünen ad', AppLang.en: 'Display name'},
  'title.field.title': {AppLang.tr: 'Başlık', AppLang.en: 'Title'},
  'title.titleHint': {AppLang.tr: 'Gezinin yılına göre otomatik belirlenir (örn. {sample}). İstersen elle değiştirebilirsin.', AppLang.en: 'Set automatically from the trip\'s year (e.g. {sample}). You can change it by hand if you like.'},
  'title.field.subtitle': {AppLang.tr: 'Açıklama (opsiyonel)', AppLang.en: 'Description (optional)'},
  'title.subtitleHint': {AppLang.tr: 'Kısa bir not', AppLang.en: 'A short note'},
  'title.field.pace': {AppLang.tr: 'Tempo', AppLang.en: 'Pace'},
  'title.pace.relaxed': {AppLang.tr: 'Rahat', AppLang.en: 'Relaxed'},
  'title.pace.moderate': {AppLang.tr: 'Dengeli', AppLang.en: 'Balanced'},
  'title.pace.intense': {AppLang.tr: 'Yoğun', AppLang.en: 'Intense'},
  'journey.title': {AppLang.tr: '🇯🇵 Japonya rotası', AppLang.en: '🇯🇵 Japan route'},
  'journey.sub.ticket': {AppLang.tr: 'Türkiye\'den Japonya\'ya gidiş ve dönüş uçuşlarını gir. Her uçuş kartında havayolu, uçuş no, tarih ve havaalanları var.', AppLang.en: 'Enter your outbound and return flights from Türkiye to Japan. Each flight card has the airline, flight number, date and airports.'},
  'journey.sub.plan': {AppLang.tr: 'Türkiye\'den nereden kalkacaksın ve Japonya\'da hangi şehre ineceksin? Şimdilik şehir ve tarih yeter.', AppLang.en: 'Where in Türkiye will you take off from, and which city in Japan will you land in? For now, city and date are enough.'},
  'journey.routeLabel': {AppLang.tr: 'Rota: ', AppLang.en: 'Route: '},
  'journey.continueHint': {AppLang.tr: 'Devam için: kalkış (Türkiye) ve varış (Japonya) havaalanını seç.', AppLang.en: 'To continue, choose your departure (Türkiye) and arrival (Japan) airports.'},
  'journey.shinkansen.title': {AppLang.tr: '🚄 Şehirler arası Shinkansen', AppLang.en: '🚄 Shinkansen between cities'},
  'journey.shinkansen.body': {AppLang.tr: 'Birden fazla şehir gezeceksin → Shinkansen (yüksek hızlı tren) en pratiği.', AppLang.en: 'You\'ll be visiting more than one city → the Shinkansen (bullet train) is the most practical way.'},
  'journey.shinkansen.note': {AppLang.tr: 'JR Pass / Smart-EX önerilir. Plan adımında otomatik şehir geçiş kartları çıkar.', AppLang.en: 'JR Pass / Smart-EX recommended. City-to-city transfer cards appear automatically in the Plan step.'},
  'journey.cities.title': {AppLang.tr: '🏙️ Gezilecek şehirler', AppLang.en: '🏙️ Cities to visit'},
  'journey.cities.hint': {AppLang.tr: 'Listeden seç — rotana eklenir. Tekrar dokun → çıkar. İkinci şehri seçtiğinde şehirler arası Shinkansen önerilir.', AppLang.en: 'Pick from the list to add it to your route. Tap again to remove. Choosing a second city suggests the Shinkansen between cities.'},
  'journey.banner.title': {AppLang.tr: '🇯🇵 Japonya 14 günlük tam plan', AppLang.en: '🇯🇵 Full 14-day Japan plan'},
  'journey.banner.body': {AppLang.tr: 'Tokyo → Kyoto → Nara → Osaka rotası; günler, tarihler ve oteller hazır.', AppLang.en: 'Tokyo → Kyoto → Nara → Osaka route; days, dates and hotels are ready.'},
  'journey.banner.load': {AppLang.tr: 'Planı yükle', AppLang.en: 'Load plan'},
  'journey.leg.outbound': {AppLang.tr: '✈︎ Gidiş — Türkiye → Japonya', AppLang.en: '✈︎ Outbound — Türkiye → Japan'},
  'journey.leg.route': {AppLang.tr: '📍 Rota — Türkiye → Japonya', AppLang.en: '📍 Route — Türkiye → Japan'},
  'journey.leg.return': {AppLang.tr: '🏠 Dönüş — Japonya → Türkiye', AppLang.en: '🏠 Return — Japan → Türkiye'},
  'journey.field.airline': {AppLang.tr: 'Havayolu', AppLang.en: 'Airline'},
  'journey.field.flightNo': {AppLang.tr: 'Uçuş numarası', AppLang.en: 'Flight number'},
  'journey.field.date': {AppLang.tr: 'Tarih', AppLang.en: 'Date'},
  'journey.field.departureTr': {AppLang.tr: 'Kalkış (Türkiye)', AppLang.en: 'Departure (Türkiye)'},
  'journey.field.arrivalJp': {AppLang.tr: 'Varış (Japonya)', AppLang.en: 'Arrival (Japan)'},
  'journey.field.departureJp': {AppLang.tr: 'Kalkış (Japonya)', AppLang.en: 'Departure (Japan)'},
  'journey.field.arrivalTr': {AppLang.tr: 'Varış (Türkiye)', AppLang.en: 'Arrival (Türkiye)'},
  'journey.ph.returnDep': {AppLang.tr: 'Japonya\'dan kalkış havalimanı', AppLang.en: 'Departure airport in Japan'},
  'journey.ph.returnArr': {AppLang.tr: 'Türkiye\'ye varış havalimanı', AppLang.en: 'Arrival airport in Türkiye'},
  'journey.pax.title': {AppLang.tr: 'Yolcu & seçenekler', AppLang.en: 'Passengers & options'},
  'journey.pax.subtitle': {AppLang.tr: 'Kaç kişi + kaç çocuk?', AppLang.en: 'How many adults + children?'},
  'journey.pax.adult': {AppLang.tr: 'Yetişkin', AppLang.en: 'Adults'},
  'journey.pax.child': {AppLang.tr: 'Çocuk', AppLang.en: 'Children'},
  'journey.pax.pace': {AppLang.tr: 'Tempo', AppLang.en: 'Pace'},
  'journey.pace.relaxed': {AppLang.tr: 'Rahat', AppLang.en: 'Relaxed'},
  'journey.pace.moderate': {AppLang.tr: 'Dengeli', AppLang.en: 'Balanced'},
  'journey.pace.intense': {AppLang.tr: 'Yoğun', AppLang.en: 'Intense'},
  'journey.date.pick': {AppLang.tr: 'Tarih seç', AppLang.en: 'Pick a date'},
  'journey.city.other': {AppLang.tr: '+ Başka şehir', AppLang.en: '+ Another city'},
  'journey.city.sheetTitle': {AppLang.tr: 'Şehir seç', AppLang.en: 'Choose a city'},
  'journey.city.close': {AppLang.tr: 'Kapat', AppLang.en: 'Close'},
  'journey.city.searchHint': {AppLang.tr: 'Şehir ara — Kyoto, Hakone, Nikko…', AppLang.en: 'Search cities — Kyoto, Hakone, Nikko…'},
  'journey.city.airport': {AppLang.tr: 'Havalimanı', AppLang.en: 'Airport'},
  'journey.city.byTrain': {AppLang.tr: 'Shinkansen / tren erişimli', AppLang.en: 'Reachable by Shinkansen / train'},
  'welcome.choose.ticket.title': {AppLang.tr: 'Biletim var', AppLang.en: 'I have a ticket'},
  'welcome.choose.ticket.desc': {AppLang.tr: 'Uçuş bilgilerini gir ya da bilet fotoğrafını yükle', AppLang.en: 'Enter your flight details or upload a photo of your ticket'},
  'welcome.choose.plan.title': {AppLang.tr: 'Gezi planla', AppLang.en: 'Plan a trip'},
  'welcome.choose.plan.desc': {AppLang.tr: 'Sana en uygun tarihleri birlikte seçelim', AppLang.en: 'Let\'s pick the dates that suit you best, together'},
  'welcome.choose.heading': {AppLang.tr: 'Japonya\'yı planlayalım', AppLang.en: 'Let\'s plan Japan'},
  'welcome.choose.subheading': {AppLang.tr: 'Nereden başlayalım?', AppLang.en: 'Where shall we start?'},
  'welcome.ticket.title': {AppLang.tr: 'Bilet bilgilerin', AppLang.en: 'Your ticket details'},
  'welcome.ticket.sub': {AppLang.tr: 'Sadece tarihler zorunlu — diğer alanları boş bırakabilirsin. En fazla {n} günlük plan oluşturuyoruz.', AppLang.en: 'Only the dates are required — you can leave the other fields blank. We build plans of up to {n} days.'},
  'welcome.ticket.outDate': {AppLang.tr: 'Gidiş tarihi', AppLang.en: 'Departure date'},
  'welcome.ticket.retDate': {AppLang.tr: 'Dönüş tarihi', AppLang.en: 'Return date'},
  'welcome.ticket.tooLong': {AppLang.tr: 'En fazla {max} günlük plan oluşturuyoruz — {sel} gün seçildi, otomatik kısaltılacak.', AppLang.en: 'We build plans of up to {max} days — you selected {sel} days, so it will be shortened automatically.'},
  'welcome.ticket.airline': {AppLang.tr: 'Havayolu', AppLang.en: 'Airline'},
  'welcome.ticket.outFlightNo': {AppLang.tr: 'Uçuş no (gidiş)', AppLang.en: 'Flight no. (outbound)'},
  'welcome.ticket.retFlightNo': {AppLang.tr: 'Uçuş no (dönüş)', AppLang.en: 'Flight no. (return)'},
  'welcome.ticket.upload': {AppLang.tr: '📷 Bilet fotoğrafı yükle', AppLang.en: '📷 Upload a photo of your ticket'},
  'welcome.ticket.ocrSoon': {AppLang.tr: 'Bilet OCR (AI) sonraki iterasyonda bağlanacak.', AppLang.en: 'Ticket OCR (AI) will be connected in a future update.'},
  'welcome.continue': {AppLang.tr: 'Devam', AppLang.en: 'Continue'},
  'welcome.plan.title': {AppLang.tr: 'Japonya\'da esnek gezi', AppLang.en: 'Flexible trip in Japan'},
  'welcome.plan.sub': {AppLang.tr: 'Bir tarih aralığı seç — otomatik gidiş-dönüş olarak Rota adımına geçelim.', AppLang.en: 'Pick a date range — we\'ll set it up as a round trip and move on to the Route step.'},
  'welcome.plan.customRange': {AppLang.tr: '📅 Kendim seçmek istiyorum', AppLang.en: '📅 I\'ll choose the dates myself'},
  'welcome.range.help': {AppLang.tr: 'Gidiş — Dönüş tarihlerini seç', AppLang.en: 'Select departure — return dates'},
  'welcome.range.cancel': {AppLang.tr: 'Vazgeç', AppLang.en: 'Cancel'},
  'welcome.range.confirm': {AppLang.tr: 'Uygula', AppLang.en: 'Apply'},
  'welcome.save': {AppLang.tr: 'Kaydet', AppLang.en: 'Save'},
  'welcome.origin.title': {AppLang.tr: 'Kalkış şehri', AppLang.en: 'Departure city'},
  'welcome.back': {AppLang.tr: '← Geri', AppLang.en: '← Back'},
  'welcome.originPill': {AppLang.tr: 'Kalkış: {city}', AppLang.en: 'From: {city}'},
  'welcome.date.placeholder': {AppLang.tr: 'gg.aa.yyyy', AppLang.en: 'dd.mm.yyyy'},
  'welcome.dest.country': {AppLang.tr: 'Japonya', AppLang.en: 'Japan'},
  'welcome.dest.tokyo.tag': {AppLang.tr: 'Meiji, İmparatorluk Sarayı ve müzeler', AppLang.en: 'Meiji, the Imperial Palace and museums'},
  'welcome.dest.osaka.tag': {AppLang.tr: 'Osaka Kalesi\'nin bulunduğu liman şehri', AppLang.en: 'The port city home to Osaka Castle'},
  'welcome.range.tokyo.sakuraPeak': {AppLang.tr: '🌸 Sakura zirvesi', AppLang.en: '🌸 Peak sakura'},
  'welcome.range.tokyo.lateSakura': {AppLang.tr: '🌸 Geç sakura, ılıman', AppLang.en: '🌸 Late sakura, mild'},
  'welcome.range.tokyo.autumn': {AppLang.tr: '🍁 Sonbahar renkleri', AppLang.en: '🍁 Autumn colors'},
  'welcome.range.osaka.sakuraKansai': {AppLang.tr: '🌸 Sakura + Kansai', AppLang.en: '🌸 Sakura + Kansai'},
  'welcome.range.osaka.mild': {AppLang.tr: 'Ilıman, kalabalık az', AppLang.en: 'Mild, fewer crowds'},
  'welcome.range.osaka.autumnFood': {AppLang.tr: '🍁 Sonbahar + gastronomi', AppLang.en: '🍁 Autumn + cuisine'},
  'welcome.range.week': {AppLang.tr: '~{n} hafta', AppLang.en: '~{n} week'},
  'welcome.range.weeks': {AppLang.tr: '~{n} hafta', AppLang.en: '~{n} weeks'},
  'welcome.range.days': {AppLang.tr: '~{n} gün', AppLang.en: '~{n} days'},
  'placeDetail.nearby': {AppLang.tr: 'Yakınlarda', AppLang.en: 'Nearby'},
  'placeDetail.whatToEat': {AppLang.tr: 'Ne yenir', AppLang.en: 'What to eat'},
  'placeDetail.tips': {AppLang.tr: 'İpuçları', AppLang.en: 'Tips'},
  'placeDetail.duration': {AppLang.tr: 'Süre', AppLang.en: 'Duration'},
  'placeDetail.walking': {AppLang.tr: 'Yürüme', AppLang.en: 'Walking'},
  'placeDetail.ticketLabel': {AppLang.tr: 'Bilet', AppLang.en: 'Ticket'},
  'placeDetail.daysBefore': {AppLang.tr: '{n} gün önce', AppLang.en: '{n} days ahead'},
  'placeDetail.steps': {AppLang.tr: '~{n} adım', AppLang.en: '~{n} steps'},
  'placeDetail.stepsThousand': {AppLang.tr: '~{n} bin adım', AppLang.en: '~{n}k steps'},
  'placeDetail.durationMin': {AppLang.tr: '{n} dk', AppLang.en: '{n} min'},
  'placeDetail.durationHour': {AppLang.tr: '{n} saat', AppLang.en: '{n} hr'},
  'placeDetail.durationHourMin': {AppLang.tr: '{h} sa {m} dk', AppLang.en: '{h} hr {m} min'},
  'placeDetail.thousandShort': {AppLang.tr: 'bin', AppLang.en: 'k'},
  'placeDetail.reviewCount': {AppLang.tr: '({n} yorum)', AppLang.en: '({n} reviews)'},
  'placeDetail.defaultIntro': {AppLang.tr: 'Planınızdaki bir durak.', AppLang.en: 'A stop on your itinerary.'},
  'placeDetail.openMap': {AppLang.tr: 'Haritada aç', AppLang.en: 'Open in Maps'},
  'placeDetail.edit': {AppLang.tr: 'Düzenle', AppLang.en: 'Edit'},
  'placeDetail.mapOpenFailed': {AppLang.tr: 'Harita açılamadı — bağlantı panoya kopyalandı', AppLang.en: 'Couldn\'t open the map — link copied to clipboard'},
  'placeDetail.camera': {AppLang.tr: 'Kamera', AppLang.en: 'Camera'},
  'placeDetail.gallery': {AppLang.tr: 'Galeri', AppLang.en: 'Gallery'},
  'placeDetail.cancel': {AppLang.tr: 'Vazgeç', AppLang.en: 'Cancel'},
  'placeDetail.addTicket': {AppLang.tr: 'Bilet ekle', AppLang.en: 'Add ticket'},
  'placeDetail.adding': {AppLang.tr: 'Ekleniyor…', AppLang.en: 'Adding…'},
  'placeDetail.ticketCardTitle': {AppLang.tr: '🎫 Bilet', AppLang.en: '🎫 Ticket'},
  'placeDetail.ticketAdded': {AppLang.tr: '🎫 Bilet eklendi', AppLang.en: '🎫 Ticket added'},
  'placeDetail.ticketAddedStatus': {AppLang.tr: 'Bilet eklendi', AppLang.en: 'Ticket added'},
  'placeDetail.ticketAddedWeb': {AppLang.tr: '🎫 Bilet eklendi · Otomatik metin çıkarımı cihazda (iOS) çalışır', AppLang.en: '🎫 Ticket added · Automatic text extraction runs on device (iOS)'},
  'placeDetail.ticketAddFailed': {AppLang.tr: 'Bilet eklenemedi — tekrar deneyin', AppLang.en: 'Couldn\'t add the ticket — please try again'},
  'placeDetail.visitDate': {AppLang.tr: 'Ziyaret: {date}', AppLang.en: 'Visit: {date}'},
  'placeDetail.scannedText': {AppLang.tr: '📄 Okunan metin', AppLang.en: '📄 Scanned text'},
  'placeDetail.category.temple': {AppLang.tr: 'Tapınak', AppLang.en: 'Temple'},
  'placeDetail.category.shrine': {AppLang.tr: 'Tapınak', AppLang.en: 'Shrine'},
  'placeDetail.category.view': {AppLang.tr: 'Manzara', AppLang.en: 'View'},
  'placeDetail.category.city': {AppLang.tr: 'Şehir', AppLang.en: 'City'},
  'placeDetail.category.museum': {AppLang.tr: 'Müze', AppLang.en: 'Museum'},
  'placeDetail.category.park': {AppLang.tr: 'Park', AppLang.en: 'Park'},
  'placeDetail.category.shopping': {AppLang.tr: 'Alışveriş', AppLang.en: 'Shopping'},
  'placeDetail.category.fun': {AppLang.tr: 'Eğlence', AppLang.en: 'Entertainment'},
  'placeDetail.category.nature': {AppLang.tr: 'Doğa', AppLang.en: 'Nature'},
  'placeDetail.category.food': {AppLang.tr: 'Yemek', AppLang.en: 'Food'},
  'placeDetail.category.culture': {AppLang.tr: 'Kültür', AppLang.en: 'Culture'},
  'placeDetail.category.landmark': {AppLang.tr: 'Simge yapı', AppLang.en: 'Landmark'},
  'plan.generate': {AppLang.tr: '✨ Gezi planı oluştur', AppLang.en: '✨ Build trip plan'},
  'plan.regenerate': {AppLang.tr: '✨ Planı yeniden oluştur', AppLang.en: '✨ Rebuild trip plan'},
  'plan.generating': {AppLang.tr: '✨ Plan oluşturuluyor…', AppLang.en: '✨ Building your plan…'},
  'plan.generated': {AppLang.tr: '✨ Gezi planı oluşturuldu', AppLang.en: '✨ Trip plan ready'},
  'plan.regenerated': {AppLang.tr: '✨ Plan yeniden oluşturuldu', AppLang.en: '✨ Plan rebuilt'},
  'plan.regenConfirmTitle': {AppLang.tr: 'Planı yeniden oluştur', AppLang.en: 'Rebuild the plan'},
  'plan.regenConfirmBody': {AppLang.tr: 'Mevcut plan küratörlü şablonlardan yeniden üretilecek. Elle yaptığınız düzenlemeler değişebilir. Devam edilsin mi?', AppLang.en: 'Your current plan will be rebuilt from curated templates. Your manual edits may change. Continue?'},
  'plan.regenConfirm': {AppLang.tr: 'Yeniden oluştur', AppLang.en: 'Rebuild'},
  'plan.cancel': {AppLang.tr: 'Vazgeç', AppLang.en: 'Cancel'},
  'plan.delete': {AppLang.tr: 'Sil', AppLang.en: 'Delete'},
  'plan.save': {AppLang.tr: 'Kaydet', AppLang.en: 'Save'},
  'plan.done': {AppLang.tr: 'Bitti', AppLang.en: 'Done'},
  'plan.add': {AppLang.tr: '+ Ekle', AppLang.en: '+ Add'},
  'plan.addPlain': {AppLang.tr: 'Ekle', AppLang.en: 'Add'},
  'plan.addActivity': {AppLang.tr: '+ Aktivite', AppLang.en: '+ Activity'},
  'plan.optimize': {AppLang.tr: '⚡ Optimize et', AppLang.en: '⚡ Optimize'},
  'plan.discover': {AppLang.tr: '🌍 Yeni durak keşfet', AppLang.en: '🌍 Discover a new stop'},
  'plan.remindersAdded': {AppLang.tr: '🔔 {n} hatırlatma eklendi', AppLang.en: '🔔 {n} reminders added'},
  'plan.emptyRouteSub': {AppLang.tr: 'Önce Rota adımında havaalanı/durak ekleyin.', AppLang.en: 'Add an airport or stop in the Route step first.'},
  'plan.daysRoute': {AppLang.tr: '{n} gün · {route}', AppLang.en: '{n} days · {route}'},
  'plan.childrenSuffix': {AppLang.tr: ' · {n} çocuk', AppLang.en: ' · {n} children'},
  'plan.pace': {AppLang.tr: 'Tempo', AppLang.en: 'Pace'},
  'plan.pace.relaxed': {AppLang.tr: 'Rahat', AppLang.en: 'Relaxed'},
  'plan.pace.moderate': {AppLang.tr: 'Dengeli', AppLang.en: 'Balanced'},
  'plan.pace.intense': {AppLang.tr: 'Yoğun', AppLang.en: 'Intense'},
  'plan.stepsK': {AppLang.tr: '👣 {n}k adım', AppLang.en: '👣 {n}k steps'},
  'plan.introBlurb': {AppLang.tr: 'Saat saat aktivite, ulaşım, restoran ve ipuçları küratörlü şablonlardan üretilir. Günleri sürükleyerek düzenleyebilirsiniz.', AppLang.en: 'Hour-by-hour activities, transport, restaurants and tips are generated from curated templates. Drag the days to rearrange them.'},
  'plan.transitionsTitle': {AppLang.tr: '🚄 Şehirler arası geçiş önerisi', AppLang.en: '🚄 Suggested city-to-city transfer'},
  'plan.addAll': {AppLang.tr: 'Hepsini ekle ({n})', AppLang.en: 'Add all ({n})'},
  'plan.noPlanTitle': {AppLang.tr: 'Henüz plan yok', AppLang.en: 'No plan yet'},
  'plan.noPlanBody': {AppLang.tr: 'Yukarıdaki butonla kur — sonra saat saat düzenleyebilirsin.', AppLang.en: 'Build it with the button above — then fine-tune it hour by hour.'},
  'plan.emptyDaysTitle': {AppLang.tr: 'Gün listesi boş kaldı', AppLang.en: 'Your days are empty'},
  'plan.emptyDaysBody': {AppLang.tr: 'Rota veya tarihleri güncelleyip "Planı yeniden oluştur"a bas.', AppLang.en: 'Update your route or dates, then tap "Rebuild trip plan".'},
  'plan.pickTransportTitle': {AppLang.tr: 'Ulaşım modunu seç', AppLang.en: 'Choose transport mode'},
  'plan.mode.shinkansenNote': {AppLang.tr: 'Yüksek hızlı tren — en hızlı, konforlu.', AppLang.en: 'High-speed rail — the fastest and most comfortable.'},
  'plan.mode.trainLabel': {AppLang.tr: 'Yerel / hızlı tren', AppLang.en: 'Local / rapid train'},
  'plan.mode.trainNote': {AppLang.tr: 'Daha ucuz, sürelidir. IC kart yeter.', AppLang.en: 'Cheaper but slower. An IC card is all you need.'},
  'plan.mode.busLabel': {AppLang.tr: 'Gecelik otobüs', AppLang.en: 'Overnight bus'},
  'plan.mode.busNote': {AppLang.tr: 'Ucuz ama 8+ saat sürer. Willer Express popüler.', AppLang.en: 'Cheap but takes 8+ hours. Willer Express is popular.'},
  'plan.mode.carLabel': {AppLang.tr: 'Kiralık araç', AppLang.en: 'Rental car'},
  'plan.mode.carNote': {AppLang.tr: 'Uluslararası ehliyet gerekir. Kırsalda mantıklı.', AppLang.en: 'Requires an international license. Makes sense in rural areas.'},
  'plan.dayRange': {AppLang.tr: 'Gün {from} → Gün {to} · {duration} · {fare}', AppLang.en: 'Day {from} → Day {to} · {duration} · {fare}'},
  'plan.changeTransport': {AppLang.tr: 'Ulaşım değiştir', AppLang.en: 'Change transport'},
  'plan.yamatoTitle': {AppLang.tr: 'Yamato Takkyubin — valiz transferi', AppLang.en: 'Yamato Takkyubin — luggage transfer'},
  'plan.yamatoBody': {AppLang.tr: 'Valizini Yamato Takkyubin ile otele önceden gönderebilirsin — ~2000¥/parça, 1 gün sürer. Otel resepsiyonuna "takkyubin" de yeter.', AppLang.en: 'You can send your luggage ahead to the hotel with Yamato Takkyubin — about ¥2000 per piece, takes 1 day. Just say "takkyubin" at the hotel front desk.'},
  'plan.dayN': {AppLang.tr: 'Gün {n}', AppLang.en: 'Day {n}'},
  'plan.stops': {AppLang.tr: '{n} durak', AppLang.en: '{n} stops'},
  'plan.dayTheme': {AppLang.tr: 'Gün teması', AppLang.en: 'Day theme'},
  'plan.dayThemeHint': {AppLang.tr: 'Örn. Asakusa & Skytree', AppLang.en: 'e.g. Asakusa & Skytree'},
  'plan.dayEmpty': {AppLang.tr: 'Bu güne aktivite ekleyin veya başka günden taşıyın.', AppLang.en: 'Add an activity to this day, or move one from another day.'},
  'plan.removeConfirmTitle': {AppLang.tr: 'Aktiviteyi sil', AppLang.en: 'Remove activity'},
  'plan.removeConfirmBody': {AppLang.tr: '"{title}" silinsin mi?', AppLang.en: 'Remove "{title}"?'},
  'plan.movedFrom': {AppLang.tr: '↕ Gün {n}\'den taşındı', AppLang.en: '↕ Moved from Day {n}'},
  'plan.moveToDay': {AppLang.tr: 'Başka güne taşı', AppLang.en: 'Move to another day'},
  'plan.dayWithDate': {AppLang.tr: 'Gün {n} · {date}', AppLang.en: 'Day {n} · {date}'},
  'plan.editActivity': {AppLang.tr: 'Aktiviteyi düzenle', AppLang.en: 'Edit activity'},
  'plan.fieldTitle': {AppLang.tr: 'Başlık', AppLang.en: 'Title'},
  'plan.fieldTime': {AppLang.tr: 'Saat', AppLang.en: 'Time'},
  'plan.fieldDuration': {AppLang.tr: 'Süre (dk)', AppLang.en: 'Duration (min)'},
  'plan.fieldCost': {AppLang.tr: 'Ücret', AppLang.en: 'Cost'},
  'plan.fieldCurrency': {AppLang.tr: 'Birim', AppLang.en: 'Currency'},
  'plan.fieldDescription': {AppLang.tr: 'Açıklama', AppLang.en: 'Description'},
  'plan.fieldDescriptionHint': {AppLang.tr: 'Kısa açıklama', AppLang.en: 'Short description'},
  'plan.fieldTips': {AppLang.tr: 'İpucu', AppLang.en: 'Tip'},
  'plan.fieldTipsHint': {AppLang.tr: 'Örn. Erken git, sıra uzun olur', AppLang.en: 'e.g. Go early, the line gets long'},
  'plan.copyMapLink': {AppLang.tr: '🗺️ Harita linkini kopyala', AppLang.en: '🗺️ Copy map link'},
  'plan.mapLinkCopied': {AppLang.tr: 'Harita linki kopyalandı', AppLang.en: 'Map link copied'},
  'plan.pickTime': {AppLang.tr: 'Saat seç', AppLang.en: 'Pick a time'},
  'plan.discoverPortal': {AppLang.tr: 'Keşif portalı', AppLang.en: 'Discovery portal'},
  'plan.placeSuggestions': {AppLang.tr: 'Yer önerileri', AppLang.en: 'Place suggestions'},
  'plan.discoverSub': {AppLang.tr: 'En çok ziyaret edilen yerler — karta dokununca plana eklenir.', AppLang.en: 'The most-visited places — tap a card to add it to your plan.'},
  'plan.pickMultiple': {AppLang.tr: 'Birden fazla seçebilirsin', AppLang.en: 'You can pick more than one'},
  'plan.placesAdded': {AppLang.tr: '{n} yer eklendi', AppLang.en: '{n} places added'},
  'plan.advanceBooking': {AppLang.tr: '🎟 {n} gün önce bilet', AppLang.en: '🎟 Book {n} days ahead'},
  'plan.kidFriendly': {AppLang.tr: '🧒 Çocuk dostu', AppLang.en: '🧒 Kid-friendly'},
  'plan.durMin': {AppLang.tr: '{n} dk', AppLang.en: '{n} min'},
  'plan.durHour': {AppLang.tr: '{n} saat', AppLang.en: '{n} hr'},
  'plan.durHourMin': {AppLang.tr: '{h} sa {m} dk', AppLang.en: '{h}h {m}m'},
  'plan.kindActivity': {AppLang.tr: 'Aktivite', AppLang.en: 'Activity'},
  'plan.kindMeal': {AppLang.tr: 'Yemek', AppLang.en: 'Food'},
  'plan.kindTransport': {AppLang.tr: 'Ulaşım', AppLang.en: 'Transport'},
  'plan.kindHotel': {AppLang.tr: 'Otel', AppLang.en: 'Hotel'},
  'plan.addActivityTitle': {AppLang.tr: 'Yeni aktivite ekle', AppLang.en: 'Add new activity'},
  'plan.placeName': {AppLang.tr: 'Yer adı', AppLang.en: 'Place name'},
  'plan.placeNameRequired': {AppLang.tr: 'Yer adı gerekli', AppLang.en: 'Place name is required'},
  'plan.placeNameHint': {AppLang.tr: 'Örn. Senso-ji, teamLab, ramen molası', AppLang.en: 'e.g. Senso-ji, teamLab, ramen break'},
  'plan.noSlots': {AppLang.tr: 'Boş dilim yok — mevcut aktivitelerden birini kaldır.', AppLang.en: 'No open slots — remove one of the existing activities.'},
  'plan.kindOptional': {AppLang.tr: 'Tür (opsiyonel)', AppLang.en: 'Type (optional)'},
  'shell.brand': {AppLang.tr: 'Seyahat', AppLang.en: 'Trip'},
  'shell.newPlan': {AppLang.tr: 'Yeni plan', AppLang.en: 'New plan'},
  'shell.guide': {AppLang.tr: 'Rehber', AppLang.en: 'Guide'},
  'shell.back': {AppLang.tr: 'Geri', AppLang.en: 'Back'},
  'shell.continue': {AppLang.tr: 'Devam', AppLang.en: 'Continue'},
};
