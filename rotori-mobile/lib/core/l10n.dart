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

  /// Kısa ay adları (1-index'li; index 0 boş). Dar başlıklarda tam ad satırı
  /// taşırdığı için kullanılır: "15–17 Eki".
  static List<String> monthsShortFor(AppLang lang) =>
      lang == AppLang.en ? _enMonthsShort : _trMonthsShort;
}

const List<String> _trMonthsShort = [
  '',
  'Oca',
  'Şub',
  'Mar',
  'Nis',
  'May',
  'Haz',
  'Tem',
  'Ağu',
  'Eyl',
  'Eki',
  'Kas',
  'Ara',
];

const List<String> _enMonthsShort = [
  '',
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

// ---------------------------------------------------------------------------
// Tarih dizileri.
// ---------------------------------------------------------------------------

const List<String> _trMonths = [
  '',
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

const List<String> _enMonths = [
  '',
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _trWeekdays = [
  '',
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];

const List<String> _enWeekdays = [
  '',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
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
  'common.done': {AppLang.tr: 'Bitti', AppLang.en: 'Done'},

  // ----- Hata bildirimi -----
  'bugReport.menu': {
    AppLang.tr: 'Hata bildir',
    AppLang.en: 'Report a problem',
  },
  'bugReport.title': {
    AppLang.tr: 'Planlama hatası bildir',
    AppLang.en: 'Report a planning issue',
  },
  'bugReport.body': {
    AppLang.tr:
        'Ne olduğunu kısaca anlat. Tanı için bu planın sınırlı özeti ve uygulama bilgisi eklenir.',
    AppLang.en:
        'Tell us briefly what happened. A limited plan summary and app diagnostics will be attached.',
  },
  'bugReport.category': {AppLang.tr: 'Kategori', AppLang.en: 'Category'},
  'bugReport.category.planning': {
    AppLang.tr: 'Rota / planlama',
    AppLang.en: 'Route / planning',
  },
  'bugReport.category.schedule': {
    AppLang.tr: 'Saat / çakışma',
    AppLang.en: 'Time / conflict',
  },
  'bugReport.category.save': {
    AppLang.tr: 'Kayıt / senkronizasyon',
    AppLang.en: 'Save / sync',
  },
  'bugReport.category.ui': {
    AppLang.tr: 'Görünüm / kullanım',
    AppLang.en: 'UI / interaction',
  },
  'bugReport.category.other': {AppLang.tr: 'Diğer', AppLang.en: 'Other'},
  'bugReport.message': {AppLang.tr: 'Sorun', AppLang.en: 'Issue'},
  'bugReport.messageHint': {
    AppLang.tr: 'Örn. 14:00 aktivitesi 13:00 aktivitesinin üstüne geldi.',
    AppLang.en: 'E.g. the 14:00 activity overlapped the 13:00 activity.',
  },
  'bugReport.emailOptional': {
    AppLang.tr: 'E-posta (isteğe bağlı)',
    AppLang.en: 'Email (optional)',
  },
  'bugReport.privacy': {
    AppLang.tr:
        'Kişisel notlar ve bilet içerikleri gönderilmez; yalnızca hata ayıklama özeti paylaşılır.',
    AppLang.en:
        'Personal notes and ticket contents are not sent; only a debugging summary is shared.',
  },
  'bugReport.send': {AppLang.tr: 'Gönder', AppLang.en: 'Send'},
  'bugReport.success': {
    AppLang.tr: 'Hata bildirimin alındı, teşekkürler.',
    AppLang.en: 'Your report was received. Thank you.',
  },
  'bugReport.error': {
    AppLang.tr: 'Bildirim gönderilemedi. İnternet bağlantını kontrol et.',
    AppLang.en: 'Could not send the report. Check your connection.',
  },

  // ----- Dil seçici -----
  'lang.title': {AppLang.tr: 'Dil / Language', AppLang.en: 'Dil / Language'},

  // ----- Plan viewer -----
  'viewer.loadFailed': {
    AppLang.tr: 'Yüklenemedi: {err}',
    AppLang.en: 'Failed to load: {err}',
  },
  'viewer.phase.new': {AppLang.tr: 'Yeni plan', AppLang.en: 'New plan'},
  'viewer.phase.done': {
    AppLang.tr: 'Plan tamamlandı',
    AppLang.en: 'Trip complete',
  },
  'viewer.phase.during': {
    AppLang.tr: 'Tatil başladı',
    AppLang.en: 'Trip started',
  },
  'viewer.phase.countdown': {
    AppLang.tr: 'Tatile {d}g {h}s',
    AppLang.en: '{d}d {h}h to go',
  },
  'viewer.tt.back': {AppLang.tr: 'Geri', AppLang.en: 'Back'},
  'viewer.tt.reminders': {AppLang.tr: 'Hatırlatmalar', AppLang.en: 'Reminders'},
  'viewer.tt.map': {AppLang.tr: 'Keşif haritası', AppLang.en: 'Explore map'},
  'viewer.tt.compass': {AppLang.tr: 'Pusula', AppLang.en: 'Compass'},
  'viewer.tt.weather': {AppLang.tr: 'Hava', AppLang.en: 'Weather'},
  // --- Canlı Fiyat Çevirici (live currency scanner) ---
  'scanner.title': {
    AppLang.tr: 'Canlı Fiyat Çevirici',
    AppLang.en: 'Live Price Converter',
  },
  'scanner.tt': {AppLang.tr: 'Fiyat çevir', AppLang.en: 'Convert price'},
  'scanner.price_tag': {
    AppLang.tr: 'Fiyat etiketi tara',
    AppLang.en: 'Scan price tag',
  },
  'scanner.hint': {
    AppLang.tr: 'Kamerayı fiyat etiketine tutun',
    AppLang.en: 'Point the camera at a price tag',
  },
  'scanner.onDevice': {
    AppLang.tr: 'Fiyatlar cihazınızda algılanır',
    AppLang.en: 'Prices are detected on your device',
  },
  'scanner.noUpload': {
    AppLang.tr: 'Kamera görüntüsü yüklenmez',
    AppLang.en: 'Camera image is never uploaded',
  },
  'scanner.rateFresh': {
    AppLang.tr: 'Kur güncel',
    AppLang.en: 'Rate is current'
  },
  'scanner.rateStale': {
    AppLang.tr: 'Kur eski olabilir',
    AppLang.en: 'Rate may be outdated',
  },
  'scanner.rateMissing': {
    AppLang.tr: 'Kur bulunamadı',
    AppLang.en: 'No rate available',
  },
  'scanner.lastUpdated': {
    AppLang.tr: 'Son güncelleme',
    AppLang.en: 'Last updated'
  },
  'scanner.manualRate': {AppLang.tr: 'Manuel kur', AppLang.en: 'Manual rate'},
  'scanner.manualRateOn': {
    AppLang.tr: 'Manuel kur kullanılıyor',
    AppLang.en: 'Using manual rate',
  },
  'scanner.targetCurrency': {
    AppLang.tr: 'Hedef para birimi',
    AppLang.en: 'Target currency',
  },
  'scanner.autoUpdate': {
    AppLang.tr: 'Otomatik kur güncelleme',
    AppLang.en: 'Automatic rate update',
  },
  'scanner.cardMarkup': {
    AppLang.tr: 'Kart/banka farkı',
    AppLang.en: 'Card/bank markup',
  },
  'scanner.rounding': {AppLang.tr: 'Yuvarlama', AppLang.en: 'Rounding'},
  'scanner.rounding.none': {AppLang.tr: 'Yok', AppLang.en: 'None'},
  'scanner.rounding.whole': {
    AppLang.tr: 'En yakın tam birim',
    AppLang.en: 'Nearest whole',
  },
  'scanner.rounding.ten': {
    AppLang.tr: 'En yakın 10 birim',
    AppLang.en: 'Nearest 10',
  },
  'scanner.performance': {AppLang.tr: 'Performans', AppLang.en: 'Performance'},
  'scanner.perf.battery': {
    AppLang.tr: 'Pil dostu',
    AppLang.en: 'Battery saver'
  },
  'scanner.perf.balanced': {AppLang.tr: 'Dengeli', AppLang.en: 'Balanced'},
  'scanner.perf.accuracy': {
    AppLang.tr: 'Yüksek doğruluk',
    AppLang.en: 'High accuracy',
  },
  'scanner.permTitle': {
    AppLang.tr: 'Kamera izni gerekli',
    AppLang.en: 'Camera permission required',
  },
  'scanner.permBody': {
    AppLang.tr:
        'Mağaza fiyatlarını algılayıp seçtiğiniz para birimine çevirmek için kameraya erişim gerekir.',
    AppLang.en:
        'Camera access is needed to detect store prices and convert them to your currency.',
  },
  'scanner.permDeniedBody': {
    AppLang.tr: 'Kamera iznini ayarlardan etkinleştirin',
    AppLang.en: 'Enable the camera permission from settings',
  },
  'scanner.cameraFailed': {
    AppLang.tr: 'Kamera başlatılamadı',
    AppLang.en: 'Camera could not be started',
  },
  'scanner.cameraUnavailable': {
    AppLang.tr: 'Cihazda kamera bulunamadı',
    AppLang.en: 'No camera found on this device',
  },
  'scanner.retry': {AppLang.tr: 'Tekrar dene', AppLang.en: 'Try again'},
  'scanner.openSettings': {
    AppLang.tr: 'Sistem ayarlarını aç',
    AppLang.en: 'Open system settings',
  },
  'scanner.closeCamera': {
    AppLang.tr: 'Kamerayı kapat',
    AppLang.en: 'Close camera',
  },
  'scanner.detecting': {
    AppLang.tr: 'Fiyat algılanıyor',
    AppLang.en: 'Detecting price'
  },
  'scanner.notFound': {
    AppLang.tr: 'Fiyat bulunamadı',
    AppLang.en: 'No price found'
  },
  'scanner.settings': {
    AppLang.tr: 'Çevirici ayarları',
    AppLang.en: 'Converter settings'
  },
  'scanner.taxIncluded': {
    AppLang.tr: 'Vergi dahil',
    AppLang.en: 'Tax included'
  },
  'scanner.taxExcluded': {
    AppLang.tr: 'Vergi hariç',
    AppLang.en: 'Tax excluded'
  },
  'scanner.rateShort': {AppLang.tr: 'Kur', AppLang.en: 'Rate'},
  'scanner.rateUsed': {AppLang.tr: 'Kullanılan kur', AppLang.en: 'Rate used'},
  'scanner.addToBudget': {
    AppLang.tr: 'Bütçeye ekle',
    AppLang.en: 'Add to budget'
  },
  'scanner.error.cameraInit': {
    AppLang.tr:
        'Kamera başlatılamadı. İzinleri ve kamera erişimini kontrol edip tekrar deneyin.',
    AppLang.en:
        'Could not initialize camera. Check permissions and camera access, then try again.',
  },
  'scanner.error.streamStart': {
    AppLang.tr:
        'Canlı önizleme akışı başlatılamadı. Uygulamayı yeniden açıp tekrar deneyin.',
    AppLang.en:
        'Could not start live preview stream. Reopen the app and try again.',
  },
  'scanner.error.previewStability': {
    AppLang.tr:
        'Kamera akışı kararsızlaştı. Tarayıcı güvenli şekilde durduruldu; "Tekrar dene" ile yeniden başlatabilirsiniz.',
    AppLang.en:
        'Camera stream became unstable. Scanner was stopped safely; tap "Try again" to restart.',
  },
  'scanner.error.unknown': {
    AppLang.tr: 'Beklenmeyen bir kamera hatası oluştu.',
    AppLang.en: 'An unexpected camera error occurred.',
  },
  'scanner.market.queryReadyBadge': {
    AppLang.tr: 'Ürün sorguya hazır',
    AppLang.en: 'Ready to query',
  },
  'scanner.market.queryCta': {
    AppLang.tr: 'Fiyatı Sorgula',
    AppLang.en: 'Query price',
  },
  'scanner.market.loadingTitle': {
    AppLang.tr: 'Pazar fiyatları sorgulanıyor',
    AppLang.en: 'Checking market prices',
  },
  'scanner.market.resultsTitle': {
    AppLang.tr: 'Pazar fiyat karşılaştırması',
    AppLang.en: 'Market price comparison',
  },
  'scanner.market.close': {
    AppLang.tr: 'Kapat',
    AppLang.en: 'Close',
  },
  'scanner.market.jpReference': {
    AppLang.tr: 'Japonya referansı',
    AppLang.en: 'Japan reference',
  },
  'scanner.market.summaryTitle': {
    AppLang.tr: 'Özet',
    AppLang.en: 'Summary',
  },
  'scanner.market.trMedian': {
    AppLang.tr: 'TR medyan',
    AppLang.en: 'TR median',
  },
  'scanner.market.trMin': {
    AppLang.tr: 'TR en düşük',
    AppLang.en: 'TR minimum',
  },
  'scanner.market.trMax': {
    AppLang.tr: 'TR en yüksek',
    AppLang.en: 'TR maximum',
  },
  'scanner.market.diff': {
    AppLang.tr: 'Fark',
    AppLang.en: 'Difference',
  },
  'scanner.market.cheaperInJapan': {
    AppLang.tr: 'Japonya fiyatı daha avantajlı görünüyor.',
    AppLang.en: 'Japan price currently looks better.',
  },
  'scanner.market.expensiveInJapan': {
    AppLang.tr: 'Türkiye fiyatı daha avantajlı görünüyor.',
    AppLang.en: 'Turkey market price currently looks better.',
  },
  'scanner.market.estimatedHint': {
    AppLang.tr:
        'Not: İlk sürümde market sonuçları tahmini/önizleme verisi olabilir.',
    AppLang.en:
        'Note: In this first release, market results may be estimated/preview data.',
  },
  'scanner.market.estimatedBadge': {
    AppLang.tr: 'Tahmini',
    AppLang.en: 'Estimated',
  },
  'scanner.market.confidence': {
    AppLang.tr: 'Güven',
    AppLang.en: 'Confidence',
  },
  'scanner.market.source.hepsiburada': {
    AppLang.tr: 'Hepsiburada',
    AppLang.en: 'Hepsiburada',
  },
  'scanner.market.source.trendyol': {
    AppLang.tr: 'Trendyol',
    AppLang.en: 'Trendyol',
  },
  'scanner.market.source.amazon': {
    AppLang.tr: 'Amazon Türkiye',
    AppLang.en: 'Amazon Turkey',
  },
  'scanner.market.status.pending': {
    AppLang.tr: 'Bekliyor',
    AppLang.en: 'Pending',
  },
  'scanner.market.status.loading': {
    AppLang.tr: 'Sorgulanıyor',
    AppLang.en: 'Loading',
  },
  'scanner.market.status.failed': {
    AppLang.tr: 'Ulaşılamadı',
    AppLang.en: 'Failed',
  },
  'scanner.market.error.noResults': {
    AppLang.tr: 'Hiç fiyat sonucu alınamadı. Tekrar deneyin.',
    AppLang.en: 'No price result was returned. Please try again.',
  },
  'viewer.quick.home': {AppLang.tr: 'Ana Sayfa', AppLang.en: 'Home'},
  'viewer.quick.explore': {AppLang.tr: 'Keşfet', AppLang.en: 'Explore'},
  'viewer.quick.tickets': {AppLang.tr: 'Biletler', AppLang.en: 'Tickets'},
  'viewer.quick.weather': {AppLang.tr: 'Hava', AppLang.en: 'Weather'},
  'viewer.quick.japanese': {AppLang.tr: 'Japonca', AppLang.en: 'Japanese'},
  'viewer.quick.guide': {AppLang.tr: 'Rehber', AppLang.en: 'Guide'},
  'viewer.quick.transport': {
    AppLang.tr: 'Ulaşım ve biletler',
    AppLang.en: 'Transport and tickets',
  },
  'viewer.quick.flight': {AppLang.tr: 'Uçuş', AppLang.en: 'Flight'},
  'viewer.quick.outbound': {AppLang.tr: 'Gidiş uçuşu', AppLang.en: 'Outbound'},
  'viewer.quick.return': {AppLang.tr: 'Dönüş uçuşu', AppLang.en: 'Return'},
  'viewer.quick.noFlights': {
    AppLang.tr: 'Uçuş bilgisi eklenmedi.',
    AppLang.en: 'No flight information added.',
  },
  'viewer.quick.noTickets': {
    AppLang.tr: 'Henüz bilet eklenmedi.',
    AppLang.en: 'No tickets added yet.',
  },
  'viewer.quick.noTicketsHelp': {
    AppLang.tr:
        'Tren, etkinlik veya uçuş biletini ekleyerek rezervasyonunu planla birlikte tut.',
    AppLang.en:
        'Keep train, attraction, or flight reservations together with your plan.',
  },
  'viewer.quick.addTicket': {
    AppLang.tr: 'İlk bileti ekle',
    AppLang.en: 'Add first ticket',
  },
  'viewer.quick.ticketPurchased': {
    AppLang.tr: 'Satın alındı',
    AppLang.en: 'Purchased',
  },
  'viewer.quick.ticketPending': {
    AppLang.tr: 'Rezervasyon bekliyor',
    AppLang.en: 'Reservation pending',
  },

  // ----- Rotori Wallet -----
  'ticketWallet.title': {AppLang.tr: 'Biletler', AppLang.en: 'Tickets'},
  'ticketWallet.add': {AppLang.tr: 'Bilet ekle', AppLang.en: 'Add ticket'},
  'ticketWallet.summary.tickets.singular': {
    AppLang.tr: '{count} bilet',
    AppLang.en: '{count} ticket',
  },
  'ticketWallet.summary.tickets.plural': {
    AppLang.tr: '{count} bilet',
    AppLang.en: '{count} tickets',
  },
  'ticketWallet.summary.ready.singular': {
    AppLang.tr: '{count} hazır',
    AppLang.en: '{count} ready',
  },
  'ticketWallet.summary.ready.plural': {
    AppLang.tr: '{count} hazır',
    AppLang.en: '{count} ready',
  },
  'ticketWallet.summary.next.today': {
    AppLang.tr: 'sıradaki bugün',
    AppLang.en: 'next today',
  },
  'ticketWallet.summary.next.tomorrow': {
    AppLang.tr: 'sıradaki yarın',
    AppLang.en: 'next tomorrow',
  },
  'ticketWallet.summary.next.days': {
    AppLang.tr: 'sıradaki {count} gün sonra',
    AppLang.en: 'next in {count} days',
  },
  'ticketWallet.summary.separator': {AppLang.tr: ' · ', AppLang.en: ' · '},
  'ticketWallet.otherReady': {
    AppLang.tr: 'Diğer hazır biletler',
    AppLang.en: 'Other ready tickets',
  },
  'ticketWallet.pending': {
    AppLang.tr: 'Hazırlanıyor',
    AppLang.en: 'In progress',
  },
  'ticketWallet.status.ready': {AppLang.tr: 'Hazır', AppLang.en: 'Ready'},
  'ticketWallet.status.pending': {
    AppLang.tr: 'Rezervasyon bekliyor',
    AppLang.en: 'Reservation pending',
  },
  'ticketWallet.status.saleToday': {
    AppLang.tr: 'Satış bugün',
    AppLang.en: 'On sale today',
  },
  'ticketWallet.status.saleTomorrow': {
    AppLang.tr: 'Satışa 1 gün',
    AppLang.en: 'On sale in 1 day',
  },
  'ticketWallet.status.saleInDays': {
    AppLang.tr: 'Satışa {count} gün',
    AppLang.en: 'On sale in {count} days',
  },
  'ticketWallet.status.missingInfo': {
    AppLang.tr: 'Eksik bilgi',
    AppLang.en: 'Missing information',
  },
  'ticketWallet.date': {
    AppLang.tr: '{day} {month} {year}',
    AppLang.en: '{month} {day}, {year}',
  },
  'ticketWallet.semantic.separator': {
    AppLang.tr: ', ',
    AppLang.en: ', ',
  },
  'ticketWallet.semantic.summary': {
    AppLang.tr: '{name}. {details}. {status}',
    AppLang.en: '{name}. {details}. {status}',
  },
  'ticketWallet.semantic.summaryNoDetails': {
    AppLang.tr: '{name}. {status}',
    AppLang.en: '{name}. {status}',
  },
  'ticketWallet.openMedia': {
    AppLang.tr: '{name} bilet görselini aç',
    AppLang.en: 'Open ticket image for {name}',
  },
  'ticketWallet.empty.title': {
    AppLang.tr: 'Biletlerin burada hazır olacak',
    AppLang.en: 'Your tickets will be ready here',
  },
  'ticketWallet.empty.body': {
    AppLang.tr:
        'Tren ve etkinlik biletlerini ekle; sıradaki rezervasyonun yolculukta elinin altında olsun.',
    AppLang.en:
        'Add train and attraction tickets so your next reservation stays close at hand.',
  },
  'ticketWallet.empty.add': {
    AppLang.tr: 'İlk bileti ekle',
    AppLang.en: 'Add first ticket',
  },
  'ticketAdd.title': {AppLang.tr: 'Bilet ekle', AppLang.en: 'Add ticket'},
  'ticketAdd.body': {
    AppLang.tr: 'Biletini ekleme şeklini seç.',
    AppLang.en: 'Choose how you want to add your ticket.',
  },
  'ticketAdd.gallery': {
    AppLang.tr: 'Fotoğraflardan seç',
    AppLang.en: 'Choose from photos',
  },
  'ticketAdd.galleryBody': {
    AppLang.tr: 'Ekran görüntüsü veya bilet fotoğrafı',
    AppLang.en: 'A screenshot or ticket photo',
  },
  'ticketAdd.camera': {
    AppLang.tr: 'Kamerayla tara',
    AppLang.en: 'Scan with camera',
  },
  'ticketAdd.cameraBody': {
    AppLang.tr: 'Yeni bir bilet fotoğrafı çek',
    AppLang.en: 'Take a new ticket photo',
  },
  'ticketAdd.plan': {
    AppLang.tr: 'Plandan seç',
    AppLang.en: 'Choose from plan',
  },
  'ticketAdd.planBody': {
    AppLang.tr: 'Etkinlik veya şehir geçişiyle bağla',
    AppLang.en: 'Link an activity or city transfer',
  },
  'ticketAdd.manual': {AppLang.tr: 'Elle gir', AppLang.en: 'Enter manually'},
  'ticketAdd.manualBody': {
    AppLang.tr: 'Görselsiz bir bilet oluştur',
    AppLang.en: 'Create a ticket without an image',
  },
  'ticketReview.title': {
    AppLang.tr: 'Bulunan bilgileri kontrol et',
    AppLang.en: 'Review found details',
  },
  'ticketReview.body': {
    AppLang.tr: 'Yalnız onayladığın bilgiler bilete eklenir.',
    AppLang.en: 'Only details you approve are added to the ticket.',
  },
  'ticketReview.label': {AppLang.tr: 'Bilet adı', AppLang.en: 'Ticket name'},
  'ticketReview.purchased': {
    AppLang.tr: 'Satın alındı',
    AppLang.en: 'Purchased',
  },
  'ticketReview.purchasedBody': {
    AppLang.tr: 'Bu bilgi otomatik belirlenmez.',
    AppLang.en: 'This is never determined automatically.',
  },
  'ticketReview.save': {AppLang.tr: 'Bileti kaydet', AppLang.en: 'Save ticket'},
  'ticketReview.value': {AppLang.tr: 'Değer', AppLang.en: 'Value'},
  'ticketReview.needsReview': {
    AppLang.tr: 'Kontrol et',
    AppLang.en: 'Review',
  },
  'ticketReview.remove': {AppLang.tr: 'Kaldır', AppLang.en: 'Remove'},
  'ticketReview.accept': {
    AppLang.tr: 'Bilete ekle',
    AppLang.en: 'Add to ticket'
  },
  'ticketReview.addDetail': {
    AppLang.tr: 'Ayrıntı ekle',
    AppLang.en: 'Add detail',
  },
  'ticketReview.detailLabel': {
    AppLang.tr: 'Ayrıntı adı',
    AppLang.en: 'Detail label',
  },
  'ticketReview.detailValue': {
    AppLang.tr: 'Ayrıntı değeri',
    AppLang.en: 'Detail value',
  },
  'ticketReview.candidate.label': {
    AppLang.tr: 'Bilet adı',
    AppLang.en: 'Ticket name'
  },
  'ticketReview.candidate.date': {AppLang.tr: 'Tarih', AppLang.en: 'Date'},
  'ticketReview.candidate.time': {AppLang.tr: 'Saat', AppLang.en: 'Time'},
  'ticketReview.candidate.venue': {AppLang.tr: 'Mekân', AppLang.en: 'Venue'},
  'ticketReview.candidate.confirmationCode': {
    AppLang.tr: 'Onay kodu',
    AppLang.en: 'Confirmation code',
  },
  'ticketReview.candidate.seat': {AppLang.tr: 'Koltuk', AppLang.en: 'Seat'},
  'ticketReview.candidate.gate': {AppLang.tr: 'Kapı', AppLang.en: 'Gate'},
  'ticketReview.candidate.partySize': {
    AppLang.tr: 'Kişi sayısı',
    AppLang.en: 'Party size',
  },
  'ticketReview.candidate.url': {AppLang.tr: 'Bağlantı', AppLang.en: 'Link'},
  'ticketReview.candidate.qr': {
    AppLang.tr: 'QR içeriği',
    AppLang.en: 'QR content'
  },
  'ticketDetail.title': {
    AppLang.tr: 'Bileti düzenle',
    AppLang.en: 'Edit ticket',
  },
  'ticketDetail.label': {AppLang.tr: 'Bilet adı', AppLang.en: 'Ticket name'},
  'ticketDetail.purchased': {
    AppLang.tr: 'Satın alındı',
    AppLang.en: 'Purchased',
  },
  'ticketDetail.save': {AppLang.tr: 'Kaydet', AppLang.en: 'Save'},
  'ticketDetail.replaceMedia': {
    AppLang.tr: 'Bilet görselini değiştir',
    AppLang.en: 'Replace ticket image',
  },
  'ticketDetail.reattachMedia': {
    AppLang.tr: 'Görseli yeniden ekle',
    AppLang.en: 'Reattach ticket image',
  },
  'ticketDetail.reattach': {AppLang.tr: 'Ekle', AppLang.en: 'Reattach'},
  'ticketDetail.mediaLabel': {
    AppLang.tr: '{name} bilet görseli',
    AppLang.en: 'Ticket image for {name}',
  },
  'ticketDetail.delete': {
    AppLang.tr: 'Bileti sil',
    AppLang.en: 'Delete ticket'
  },
  'ticketDetail.deleteTitle': {
    AppLang.tr: 'Bilet silinsin mi?',
    AppLang.en: 'Delete ticket?',
  },
  'ticketDetail.deleteBody': {
    AppLang.tr: '{name} ve bağlı görseli silinecek.',
    AppLang.en: '{name} and its attached image will be deleted.',
  },
  'ticketDetail.deleteConfirm': {AppLang.tr: 'Sil', AppLang.en: 'Delete'},
  'ticketDetail.cancel': {AppLang.tr: 'Vazgeç', AppLang.en: 'Cancel'},
  'viewer.tt.budget': {AppLang.tr: 'Bütçe', AppLang.en: 'Budget'},
  'viewer.tt.checklist': {AppLang.tr: 'Checklist', AppLang.en: 'Checklist'},
  'viewer.tt.phrases': {AppLang.tr: 'Japonca', AppLang.en: 'Japanese'},
  'viewer.tt.mustKnow': {AppLang.tr: 'Bilmelisin', AppLang.en: 'Must-know'},
  'viewer.tt.foodGuide': {
    AppLang.tr: 'Yemek rehberi',
    AppLang.en: 'Food guide'
  },
  'viewer.tt.eats': {AppLang.tr: 'Rotori Eats', AppLang.en: 'Rotori Eats'},
  'viewer.tt.theme': {
    AppLang.tr: 'Tasarımı değiştir',
    AppLang.en: 'Change design',
  },
  'viewer.tt.edit': {AppLang.tr: 'Düzenle', AppLang.en: 'Edit'},
  'viewer.tt.viewTrain': {
    AppLang.tr: 'Tren görünümü',
    AppLang.en: 'Train view'
  },
  'viewer.tt.viewList': {AppLang.tr: 'Liste görünümü', AppLang.en: 'List view'},
  'viewer.tt.editDone': {AppLang.tr: 'Bitir', AppLang.en: 'Done'},
  'viewer.tt.editRebuild': {
    AppLang.tr: 'Baştan oluştur',
    AppLang.en: 'Rebuild plan'
  },
  'viewer.tt.editRebuildConfirmTitle': {
    AppLang.tr: 'Plan baştan oluşturulsun mu?',
    AppLang.en: 'Rebuild the plan?'
  },
  'viewer.tt.editRebuildConfirmBody': {
    AppLang.tr:
        'Mevcut plan silinir ve tercihlerin üzerinden yeniden üretilir. Bu geri alınamaz.',
    AppLang.en:
        'Your current plan will be discarded and regenerated from your preferences. This cannot be undone.',
  },
  'viewer.edit.moveUp': {AppLang.tr: 'Yukarı taşı', AppLang.en: 'Move up'},
  'viewer.edit.moveDown': {AppLang.tr: 'Aşağı taşı', AppLang.en: 'Move down'},
  'viewer.edit.moveToDay': {
    AppLang.tr: 'Başka güne al',
    AppLang.en: 'Move to another day'
  },
  'viewer.edit.moveToDayTitle': {
    AppLang.tr: 'Hangi güne alalım?',
    AppLang.en: 'Move to which day?'
  },
  'viewer.edit.deleteItem': {AppLang.tr: 'Kaldır', AppLang.en: 'Remove'},
  'viewer.edit.deletedSnack': {
    AppLang.tr: 'Kaldırıldı: {title}',
    AppLang.en: 'Removed: {title}'
  },
  'viewer.edit.movedSnack': {
    AppLang.tr: '{title} → Gün {day}',
    AppLang.en: '{title} → Day {day}'
  },
  'viewer.edit.droppedSnack': {
    AppLang.tr: '{title} → Gün {day}, {time}',
    AppLang.en: '{title} → Day {day}, {time}'
  },
  'viewer.edit.undo': {AppLang.tr: 'Geri al', AppLang.en: 'Undo'},
  'viewer.edit.cancel': {AppLang.tr: 'Vazgeç', AppLang.en: 'Cancel'},
  'viewer.edit.rebuild': {AppLang.tr: 'Baştan oluştur', AppLang.en: 'Rebuild'},
  'viewer.edit.editTime': {
    AppLang.tr: 'Saati düzenle',
    AppLang.en: 'Edit time'
  },
  'viewer.edit.editSheetTitle': {
    AppLang.tr: 'Aktiviteyi düzenle',
    AppLang.en: 'Edit activity',
  },
  'viewer.edit.dayLabel': {AppLang.tr: 'Gün', AppLang.en: 'Day'},
  'viewer.edit.save': {AppLang.tr: 'Kaydet', AppLang.en: 'Save'},
  'viewer.edit.dayShort': {
    AppLang.tr: 'Gün {n}',
    AppLang.en: 'Day {n}',
  },
  'viewer.edit.ticketConfirmTitle': {
    AppLang.tr: 'Biletli aktiviteyi düzenle',
    AppLang.en: 'Edit ticketed activity',
  },
  'viewer.edit.ticketConfirmBody': {
    AppLang.tr:
        '"{title}" için bilet girmişsin. Biletli bir aktiviteyi düzenlemek üzeresin — biletine uygun bir slot seçtiğinden emin misin?',
    AppLang.en:
        'You have a ticket for "{title}". You are about to edit a ticketed activity — are you sure the new slot matches your ticket?',
  },
  'viewer.edit.ticketConfirmContinue': {
    AppLang.tr: 'Devam et',
    AppLang.en: 'Continue',
  },
  'viewer.edit.addPlace': {
    AppLang.tr: 'Bu güne durak ekle',
    AppLang.en: 'Add a stop to this day'
  },
  'viewer.edit.addSheetTitle': {
    AppLang.tr: 'Yeni durak ekle',
    AppLang.en: 'Add a stop'
  },
  'viewer.edit.searchPlace': {
    AppLang.tr: 'Gezmek istediğin yeri yaz…',
    AppLang.en: 'Search a place…'
  },
  'viewer.edit.timeLabel': {AppLang.tr: 'Saat', AppLang.en: 'Time'},
  'viewer.edit.availableTimeHint': {
    AppLang.tr: 'Yalnızca uygun saatler seçilebilir.',
    AppLang.en: 'Only available times can be selected.',
  },
  'viewer.edit.noAvailableTime': {
    AppLang.tr: 'Bu günde uygun zaman aralığı bulunamadı.',
    AppLang.en: 'No available time slot was found on this day.',
  },
  'viewer.edit.durationLabel': {AppLang.tr: 'Süre', AppLang.en: 'Duration'},
  'viewer.edit.durationMinutes': {
    AppLang.tr: '{minutes} dakika',
    AppLang.en: '{minutes} minutes',
  },
  'viewer.edit.add': {AppLang.tr: 'Ekle', AppLang.en: 'Add'},
  'viewer.edit.addedSnack': {
    AppLang.tr: 'Eklendi: {title}',
    AppLang.en: 'Added: {title}'
  },
  'viewer.edit.hasTicket': {
    AppLang.tr: 'Biletim / rezervasyonum var',
    AppLang.en: 'I have a ticket / reservation',
  },
  'viewer.edit.hasTicketHint': {
    AppLang.tr:
        'Giriş saatini sabitler, günü bu etkinliğin çevresinde düzenler.',
    AppLang.en: 'Locks the entry time and arranges the day around it.',
  },
  'viewer.edit.ticketDuration': {
    AppLang.tr: 'İçeride ayıracağın süre',
    AppLang.en: 'Time you will spend inside',
  },
  'viewer.edit.ticketFixedSummary': {
    AppLang.tr: '{time} sabit · {buffer} dk erken varış',
    AppLang.en: '{time} fixed · arrive {buffer} min early',
  },
  'viewer.edit.addTicketed': {
    AppLang.tr: 'Bileti sabitle ve ekle',
    AppLang.en: 'Lock ticket and add',
  },
  'viewer.edit.ticketAddedSnack': {
    AppLang.tr: 'Bilet sabitlendi; gün bu saate göre düzenlendi.',
    AppLang.en: 'Ticket locked; the day was arranged around this time.',
  },
  'viewer.edit.ticketAttachedSnack': {
    AppLang.tr: 'Bilet etkinliğe bağlandı; gün yeniden düzenlendi.',
    AppLang.en: 'Ticket linked to the activity; the day was rearranged.',
  },
  'viewer.edit.saved': {
    AppLang.tr: 'Değişiklik kaydedildi',
    AppLang.en: 'Change saved',
  },
  'viewer.edit.saveFailed': {
    AppLang.tr: 'Kaydedilemedi; plan eski haline getirildi.',
    AppLang.en: 'Could not save; the plan was restored.',
  },
  'viewer.edit.retry': {AppLang.tr: 'Tekrar dene', AppLang.en: 'Retry'},
  'viewer.edit.locked': {
    AppLang.tr: 'Bu bilgi bir rezervasyondan geliyor ve değiştirilemez.',
    AppLang.en:
        'This information comes from a reservation and cannot be changed.',
  },
  'viewer.edit.conflict': {
    AppLang.tr:
        '{first} ile {second} arasında {minutes} dakikalık çakışma var.',
    AppLang.en:
        'There is a {minutes}-minute conflict between {first} and {second}.',
  },
  'viewer.edit.invalidChange': {
    AppLang.tr: 'Bu değişiklik geçerli bir plan oluşturmuyor.',
    AppLang.en: 'This change would create an invalid plan.',
  },
  'viewer.edit.fixedReason': {
    AppLang.tr: 'Sabit rezervasyon',
    AppLang.en: 'Fixed reservation',
  },
  'viewer.edit.dragHint': {
    AppLang.tr: 'Taşımak için uzun basıp sürükle',
    AppLang.en: 'Long press and drag to move',
  },
  // Kullanıcı kilidi — bileti alınmış durakları rota yeniden üretilirken
  // yerinde tutar.
  'viewer.edit.pinReason': {
    AppLang.tr: 'Kilitledin — bileti alınmış olabilir',
    AppLang.en: 'You locked this — the ticket may be booked',
  },
  'viewer.edit.pin': {
    AppLang.tr: 'Kilitle',
    AppLang.en: 'Lock',
  },
  'viewer.edit.unpin': {
    AppLang.tr: 'Kilidi aç',
    AppLang.en: 'Unlock',
  },
  'viewer.edit.pinHint': {
    AppLang.tr: 'Rota yeniden kurulsa da bu durak günü ve saatiyle kalır.',
    AppLang.en:
        'This stop keeps its day and time even if the route is rebuilt.',
  },
  'viewer.edit.pinned': {
    AppLang.tr: '🔒 Durak kilitlendi',
    AppLang.en: '🔒 Stop locked',
  },
  'viewer.edit.unpinned': {
    AppLang.tr: '🔓 Kilit açıldı',
    AppLang.en: '🔓 Stop unlocked',
  },
  'viewer.edit.pinSystemLocked': {
    AppLang.tr: 'Bu saat uçuş/otel bilgisinden geliyor, elle açılamaz.',
    AppLang.en: 'This time comes from flight/stay data and cannot be unlocked.',
  },
  'viewer.edit.editDay': {AppLang.tr: 'Günü düzenle', AppLang.en: 'Edit day'},
  'viewer.edit.dayTitle': {AppLang.tr: 'Gün başlığı', AppLang.en: 'Day title'},
  'viewer.edit.dayDate': {AppLang.tr: 'Tarih', AppLang.en: 'Date'},
  'viewer.edit.flightLockReason': {
    AppLang.tr: 'Bu saat uçuş bilgisinden geliyor ve değiştirilemez.',
    AppLang.en:
        'This time comes from the flight details and cannot be changed.',
  },
  'viewer.edit.hotelLockReason': {
    AppLang.tr: 'Bu saat konaklama bilgisinden geliyor ve değiştirilemez.',
    AppLang.en:
        'This time comes from the accommodation details and cannot be changed.',
  },
  'viewer.edit.noResults': {
    AppLang.tr: 'Eşleşme yok — yine de ekleyebilirsin',
    AppLang.en: 'No matches — you can still add it'
  },
  'viewer.edit.customPlace': {
    AppLang.tr: '“{q}” olarak ekle',
    AppLang.en: 'Add as “{q}”'
  },
  'viewer.heroPill': {
    AppLang.tr: '✈️ {days} Gün · {nights} Gece',
    AppLang.en: '✈️ {days} Days · {nights} Nights',
  },
  'viewer.days.title': {
    AppLang.tr: '📅 Günler ({n})',
    AppLang.en: '📅 Days ({n})'
  },
  'viewer.stat.nights': {
    AppLang.tr: 'Gece Konaklama',
    AppLang.en: 'Nights Stay'
  },
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
  'viewer.flights.outbound': {AppLang.tr: 'Gidiş', AppLang.en: 'Outbound'},
  'viewer.flights.return': {AppLang.tr: 'Dönüş', AppLang.en: 'Return'},
  'viewer.flights.duration': {
    AppLang.tr: '{h}sa {m}dk',
    AppLang.en: '{h}h {m}m',
  },
  'viewer.flights.via': {
    AppLang.tr: 'Aktarma: {stops}',
    AppLang.en: 'Via: {stops}',
  },
  'viewer.stays': {AppLang.tr: '🏨 Konaklama', AppLang.en: '🏨 Stays'},
  'viewer.hotels': {AppLang.tr: 'Konaklama', AppLang.en: 'Hotels'},
  'viewer.hotels.more': {
    AppLang.tr: '+{n} tesis daha',
    AppLang.en: '+{n} more',
  },
  'viewer.metric.nights': {AppLang.tr: 'Gece', AppLang.en: 'Nights'},
  'viewer.metric.cities': {AppLang.tr: 'Şehir', AppLang.en: 'Cities'},
  'viewer.metric.days': {AppLang.tr: 'Gün', AppLang.en: 'Days'},
  'viewer.day.noItems': {
    AppLang.tr: '(Bu güne aktivite eklenmedi.)',
    AppLang.en: '(No activities added for this day.)',
  },
  'viewer.day.viewOnMap': {
    AppLang.tr: '🗺️ Haritada gör',
    AppLang.en: '🗺️ View on map',
  },
  'viewer.cityTransition': {
    AppLang.tr: '{from} → {to}',
    AppLang.en: '{from} → {to}',
  },
  'viewer.day.taxi': {
    AppLang.tr: '🚕 Taksi önerilir',
    AppLang.en: '🚕 Taxi recommended',
  },
  'viewer.item.next': {AppLang.tr: 'Sıradaki', AppLang.en: 'Next'},
  'viewer.theme.title': {AppLang.tr: 'Tema', AppLang.en: 'Theme'},
  'viewer.appearance.title': {
    AppLang.tr: 'Tasarımı değiştir',
    AppLang.en: 'Change design',
  },
  'viewer.template.title': {AppLang.tr: 'Tasarım', AppLang.en: 'Design'},
  'viewer.template.journeyProgress': {
    AppLang.tr: 'Yolculuk',
    AppLang.en: 'Journey',
  },
  'viewer.template.journeyProgress.description': {
    AppLang.tr: 'İlerleme ve sıradaki adıma odaklanır',
    AppLang.en: 'Focuses on progress and the next step',
  },
  'viewer.template.mapFocus': {
    AppLang.tr: 'Harita',
    AppLang.en: 'Map',
  },
  'viewer.template.mapFocus.description': {
    AppLang.tr: 'Günün rotasını ve duraklarını öne çıkarır',
    AppLang.en: 'Highlights the day route and its stops',
  },
  'viewer.template.progress': {
    AppLang.tr: '{done}/{total} tamamlandı',
    AppLang.en: '{done}/{total} completed',
  },
  'viewer.template.next': {AppLang.tr: 'Sıradaki', AppLang.en: 'Next'},
  'viewer.template.dayComplete': {
    AppLang.tr: 'Bugünün planı tamamlandı',
    AppLang.en: 'Today\'s plan is complete',
  },
  'viewer.template.map.open': {
    AppLang.tr: 'Haritada aç',
    AppLang.en: 'Open map',
  },
  'viewer.template.map.layers': {
    AppLang.tr: 'Katmanlar',
    AppLang.en: 'Layers',
  },
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
  'compass.hotel.title': {
    AppLang.tr: 'Otel adresi',
    AppLang.en: 'Hotel address'
  },
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
  'budget.exchangeRate': {
    AppLang.tr: 'Döviz kuru',
    AppLang.en: 'Exchange rate'
  },
  'budget.byCategory': {
    AppLang.tr: 'Kategoriye göre',
    AppLang.en: 'By category'
  },
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
  'budget.lira': {
    AppLang.tr: 'Türk Lirası (₺)',
    AppLang.en: 'Turkish Lira (₺)'
  },
  'budget.empty': {
    AppLang.tr:
        'Planda henüz maliyet girilmemiş — Plan adımında aktivitelere ücret ekleyin.',
    AppLang.en:
        'No costs entered in the plan yet — add prices to activities in the Plan step.',
  },
  'budget.familyMaxTitle': {
    AppLang.tr: 'Aile için güvenli üst limit',
    AppLang.en: 'Safe upper limit for family',
  },
  'budget.familyMaxJpy': {
    AppLang.tr: '≈ {jpy}',
    AppLang.en: '≈ {jpy}',
  },
  'budget.familyMaxAssumption': {
    AppLang.tr:
        '{transfer} aktarma · {tripType} · {multiplier}x güven payı varsayımı',
    AppLang.en:
        '{transfer} transfers · {tripType} · {multiplier}x safety margin assumption',
  },
  'budget.familyMaxHint': {
    AppLang.tr:
        'Bu değer tahmindir; beklenmedik transfer, çocuk ihtiyaçları ve kur oynaklığı için pay içerir.',
    AppLang.en:
        'This is an estimate; it includes a buffer for unexpected transfers, child needs, and FX volatility.',
  },
  'budget.tripType.oneway': {
    AppLang.tr: 'tek yön',
    AppLang.en: 'one-way',
  },
  'budget.tripType.roundtrip': {
    AppLang.tr: 'gidiş-dönüş',
    AppLang.en: 'round-trip',
  },
  'budget.expert.title': {
    AppLang.tr: 'Uzman görünümü',
    AppLang.en: 'Expert view',
  },
  'budget.expert.coverage': {
    AppLang.tr: 'Maliyet kapsama oranı',
    AppLang.en: 'Cost coverage ratio',
  },
  'budget.expert.dailyBurn': {
    AppLang.tr: 'Günlük ortalama yakım',
    AppLang.en: 'Daily burn rate',
  },
  'budget.expert.fixed': {
    AppLang.tr: 'Sabit gider (ulaşım+otel)',
    AppLang.en: 'Fixed costs (transport+hotel)',
  },
  'budget.expert.flex': {
    AppLang.tr: 'Esnek gider (aktivite+yemek)',
    AppLang.en: 'Flexible costs (activity+food)',
  },
  'budget.expert.contingency': {
    AppLang.tr: 'Güvenlik payı (%12)',
    AppLang.en: 'Contingency buffer (12%)',
  },
  'budget.expert.cashFloor': {
    AppLang.tr: 'Önerilen nakit tabanı',
    AppLang.en: 'Suggested cash floor',
  },
  'budget.expert.scenarioTitle': {
    AppLang.tr: 'Senaryo toplamları',
    AppLang.en: 'Scenario totals',
  },
  'budget.expert.frugal': {
    AppLang.tr: 'Tutumlu',
    AppLang.en: 'Frugal',
  },
  'budget.expert.realistic': {
    AppLang.tr: 'Gerçekçi',
    AppLang.en: 'Realistic',
  },
  'budget.expert.comfort': {
    AppLang.tr: 'Konforlu',
    AppLang.en: 'Comfort',
  },
  'budget.expert.currencyWarning': {
    AppLang.tr:
        '{n} kalemde JPY/TRY dışı para birimi var; toplamlar yaklaşık gösterilir.',
    AppLang.en: '{n} items use non-JPY/TRY currencies; totals are approximate.',
  },
  // ----- Tahmini gider dökümü (yıl bazlı birim tablo, AI'sız) -----
  'budget.estimate.title': {
    AppLang.tr: 'Bu rota sizin için tahminen',
    AppLang.en: 'Estimated cost for this route',
  },
  'budget.estimate.sub': {
    AppLang.tr: '≈ {jpyMin} – {jpyMax} · {days} gün · {people}',
    AppLang.en: '≈ {jpyMin} – {jpyMax} · {days} days · {people}',
  },
  'budget.estimate.people': {
    AppLang.tr: '{adults} yetişkin + {children} çocuk',
    AppLang.en: '{adults} adults + {children} children',
  },
  'budget.estimate.adultsOnly': {
    AppLang.tr: '{adults} yetişkin',
    AppLang.en: '{adults} adults',
  },
  'budget.estimate.note': {
    AppLang.tr:
        'Tahmin {year} ortalama birim fiyatlarına dayanır; yapay zekâ kullanılmaz, değerler birim maliyet tablosundan gelir.',
    AppLang.en:
        'Estimate is based on {year} average unit prices; no AI is used — values come from the unit cost table.',
  },
  'budget.estimate.refTitle': {
    AppLang.tr: 'Örnek birim fiyatlar',
    AppLang.en: 'Sample unit prices',
  },
  'budget.share.title': {
    AppLang.tr: 'Gider dağılımı',
    AppLang.en: 'Cost distribution',
  },
  // Pasta ORTA tahmini kullanır; başlıktaki toplam bir aralık olduğu için
  // "aralığın payı" tanımsız olurdu. Kullanıcı neyi gördüğünü bilsin.
  'budget.share.basis': {
    AppLang.tr: 'Min–maks ortalamasına göre',
    AppLang.en: 'Based on the min–max average',
  },
  'budget.currencyTitle': {
    AppLang.tr: 'Para birimi',
    AppLang.en: 'Currency',
  },
  'budget.overrideBadge': {AppLang.tr: 'elle', AppLang.en: 'custom'},
  'budget.editLine': {
    AppLang.tr: 'Satırı düzenle',
    AppLang.en: 'Edit line',
  },
  'budget.editLineHint': {
    AppLang.tr:
        'Bu kalem için kendi tutarını gir. Boş bırakırsan tahmine döner.',
    AppLang.en:
        'Enter your own amount for this item. Leave empty to revert to the estimate.',
  },
  'budget.clearOverride': {AppLang.tr: 'Sıfırla', AppLang.en: 'Reset'},
  'budget.estimate.editHint': {
    AppLang.tr: 'Bir kaleme dokunarak kendi tutarını girebilirsin.',
    AppLang.en: 'Tap a line to enter your own amount.',
  },
  'budget.editLineTitle': {
    AppLang.tr: '{item} tutarını düzenle',
    AppLang.en: 'Edit {item} amount',
  },
  'budget.rateQuestionCurrency': {
    AppLang.tr: '1 ¥ kaç {code}?',
    AppLang.en: 'How many {code} per ¥?',
  },
  'budget.cat.flight': {AppLang.tr: 'Uçak bileti', AppLang.en: 'Flight'},
  'budget.cat.hotel': {AppLang.tr: 'Konaklama', AppLang.en: 'Accommodation'},
  'budget.cat.food': {AppLang.tr: 'Yemek', AppLang.en: 'Food'},
  'budget.cat.train': {AppLang.tr: 'Tren', AppLang.en: 'Train'},
  'budget.cat.taxi': {AppLang.tr: 'Taksi', AppLang.en: 'Taxi'},
  'budget.cat.shopping': {AppLang.tr: 'Alışveriş', AppLang.en: 'Shopping'},
  'budget.cat.electronics': {
    AppLang.tr: 'Elektronik',
    AppLang.en: 'Electronics',
  },
  'budget.cat.attractions': {
    AppLang.tr: 'Gezi / giriş',
    AppLang.en: 'Attractions',
  },
  'budget.ref.ramen': {AppLang.tr: 'Ramen', AppLang.en: 'Ramen'},
  'budget.ref.sushi_set': {AppLang.tr: 'Suşi seti', AppLang.en: 'Sushi set'},
  'budget.ref.konbini_meal': {
    AppLang.tr: 'Konbini yemeği',
    AppLang.en: 'Konbini meal',
  },
  'budget.ref.coffee': {AppLang.tr: 'Kahve', AppLang.en: 'Coffee'},
  'budget.ref.subway_ride': {
    AppLang.tr: 'Metro bileti',
    AppLang.en: 'Subway ride',
  },
  'budget.ref.taxi_start': {
    AppLang.tr: 'Taksi açılış',
    AppLang.en: 'Taxi base fare',
  },
  'budget.ref.shinkansen_tokyo_kyoto': {
    AppLang.tr: 'Shinkansen Tokyo–Kyoto',
    AppLang.en: 'Shinkansen Tokyo–Kyoto',
  },
  'budget.ref.hotel_night_family': {
    AppLang.tr: 'Otel/gece (aile)',
    AppLang.en: 'Hotel/night (family)',
  },
  'budget.ref.day_pass': {
    AppLang.tr: 'Günlük ulaşım kartı',
    AppLang.en: 'Day transit pass',
  },
  'budget.ref.museum': {AppLang.tr: 'Müze girişi', AppLang.en: 'Museum entry'},
  // Kategori adları (budget kind).
  'kind.activity': {AppLang.tr: 'Aktivite', AppLang.en: 'Activity'},
  'kind.meal': {AppLang.tr: 'Yemek', AppLang.en: 'Food'},
  'kind.transport': {AppLang.tr: 'Ulaşım', AppLang.en: 'Transport'},
  'kind.hotel': {AppLang.tr: 'Otel', AppLang.en: 'Hotel'},

  // ----- Valiz & Hazırlık (checklist) -----
  'checklist.title': {
    AppLang.tr: '✓ Checklist',
    AppLang.en: '✓ Checklist',
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
  'checklist.status': {
    AppLang.tr: 'Hazırlık durumu',
    AppLang.en: 'Prep status'
  },
  'checklist.ready': {
    AppLang.tr: '{done} / {total} hazır',
    AppLang.en: '{done} / {total} ready',
  },
  'checklist.customBadge': {AppLang.tr: 'özel', AppLang.en: 'custom'},

  // ----- Yolculuk öncesi hazırlık (pre-departure) -----
  'viewer.tt.prep': {AppLang.tr: 'Checklist', AppLang.en: 'Checklist'},
  'prep.title': {
    AppLang.tr: '✓ Checklist',
    AppLang.en: '✓ Checklist',
  },
  'prep.countdown.before': {
    AppLang.tr: 'Gezine {n} gün kaldı',
    AppLang.en: '{n} days to your trip',
  },
  'prep.countdown.started': {
    AppLang.tr: 'Gezi başladı 🌸',
    AppLang.en: 'Trip started 🌸',
  },
  'prep.status': {
    AppLang.tr: '{done}/{total} tamam',
    AppLang.en: '{done}/{total} done',
  },
  'prep.allReady': {
    AppLang.tr: '✅ Her şey hazır — iyi yolculuklar!',
    AppLang.en: '✅ All set — safe travels!',
  },
  'prep.addCustom': {
    AppLang.tr: '+ Kendi maddeni ekle',
    AppLang.en: '+ Add your own item',
  },
  'prep.addCustom.hint': {
    AppLang.tr: 'Yeni madde',
    AppLang.en: 'New item',
  },
  'prep.addCustom.emoji': {
    AppLang.tr: 'Emoji (opsiyonel)',
    AppLang.en: 'Emoji (optional)',
  },
  'prep.settings.title': {
    AppLang.tr: 'Ayarlar',
    AppLang.en: 'Settings',
  },
  'prep.settings.daysBefore': {
    AppLang.tr: 'Kaç gün önce görünsün?',
    AppLang.en: 'Show how many days before?',
  },
  'prep.settings.daysBeforeValue': {
    AppLang.tr: '{n} gün önce',
    AppLang.en: '{n} days before',
  },
  'prep.banner.remaining': {
    AppLang.tr: '🎒 Gitmeden {n} gün — hazırlık listeni kontrol et →',
    AppLang.en: '🎒 {n} days to go — check your prep list →',
  },
  'prep.banner.today': {
    AppLang.tr: '🎒 Bugün — son bir kontrol →',
    AppLang.en: '🎒 Today — one last check →',
  },
  'prep.banner.done': {
    AppLang.tr: '🎒 Hazırlık tamam ✅',
    AppLang.en: '🎒 Prep complete ✅',
  },
  // Preset madde metinleri (id ile eşleşir: prep.item.<id>.title|desc)
  'prep.item.passport.title': {
    AppLang.tr: 'Pasaport hazır',
    AppLang.en: 'Passport ready',
  },
  'prep.item.passport.desc': {
    AppLang.tr: 'Dönüş tarihinden itibaren en az 6 ay geçerli olmalı.',
    AppLang.en: 'Valid at least 6 months beyond your return date.',
  },
  'prep.item.visitJapanWeb.title': {
    AppLang.tr: 'Visit Japan Web QR',
    AppLang.en: 'Visit Japan Web QR',
  },
  'prep.item.visitJapanWeb.desc': {
    AppLang.tr: 'Varış öncesi giriş & gümrük formlarını doldur.',
    AppLang.en: 'Fill immigration & customs forms before arrival.',
  },
  'prep.item.bankCard.title': {
    AppLang.tr: 'Banka / ATM kartı',
    AppLang.en: 'Bank / ATM card',
  },
  'prep.item.bankCard.desc': {
    AppLang.tr:
        'Japonya ATM\'lerinde çalıştığını (7-Eleven / Japan Post) teyit et.',
    AppLang.en: 'Confirm it works at Japan ATMs (7-Eleven / Japan Post).',
  },
  'prep.item.cashYen.title': {
    AppLang.tr: '~10.000-20.000¥ nakit',
    AppLang.en: '~10,000-20,000¥ cash',
  },
  'prep.item.cashYen.desc': {
    AppLang.tr: 'Küçük restoran, tapınak ve otobüs için nakit hâlâ gerekli.',
    AppLang.en: 'Small eateries, shrines and buses often need cash.',
  },
  'prep.item.powerbank.title': {
    AppLang.tr: 'Powerbank',
    AppLang.en: 'Powerbank',
  },
  'prep.item.powerbank.desc': {
    AppLang.tr: '≤160Wh, en fazla 2 adet, kabin bagajında (kargoya yasak).',
    AppLang.en: '≤160Wh, max 2 units, cabin bag only (not checked-in).',
  },
  'prep.item.esim.title': {
    AppLang.tr: 'eSIM aktivasyon linki',
    AppLang.en: 'eSIM activation link',
  },
  'prep.item.esim.desc': {
    AppLang.tr: 'QR kodu / linki uçağa binmeden önce kaydet.',
    AppLang.en: 'Save the QR / link before boarding — offline access.',
  },
  'prep.item.jrPass.title': {
    AppLang.tr: 'JR Pass değişim kuponu',
    AppLang.en: 'JR Pass exchange voucher',
  },
  'prep.item.jrPass.desc': {
    AppLang.tr: 'Aldıysan — orijinal kâğıt kuponu yanına al.',
    AppLang.en: 'If purchased — bring the original paper voucher.',
  },
  'prep.item.medications.title': {
    AppLang.tr: 'Reçeteli ilaçlar',
    AppLang.en: 'Prescription medications',
  },
  'prep.item.medications.desc': {
    AppLang.tr: 'Orijinal kutularında + reçetenin fotoğrafı yanında olsun.',
    AppLang.en: 'In original boxes; carry a photo of the prescription.',
  },
  'prep.item.toothpaste.title': {
    AppLang.tr: 'Diş macunu',
    AppLang.en: 'Toothpaste',
  },
  'prep.item.toothpaste.desc': {
    AppLang.tr: 'Japonya\'da florür oranı düşük — kendi macununu getir.',
    AppLang.en: 'Japan\'s toothpaste has low fluoride — bring your own.',
  },
  'prep.item.walkingShoes.title': {
    AppLang.tr: 'Kaliteli yürüyüş ayakkabısı',
    AppLang.en: 'Broken-in walking shoes',
  },
  'prep.item.walkingShoes.desc': {
    AppLang.tr: 'En az bir hafta önceden giyilmiş, ayağa oturmuş olsun.',
    AppLang.en: 'Wear for at least a week before the trip.',
  },
  'prep.item.trashBags.title': {
    AppLang.tr: 'Küçük çöp poşetleri',
    AppLang.en: 'Small trash bags',
  },
  'prep.item.trashBags.desc': {
    AppLang.tr: 'Japonya\'da sokakta çöp kutusu neredeyse yok — cebinde taşı.',
    AppLang.en:
        'Public trash cans are rare — carry your trash in a pocket bag.',
  },
  'prep.item.waterBottle.title': {
    AppLang.tr: 'Boş su şişesi',
    AppLang.en: 'Empty water bottle',
  },
  'prep.item.waterBottle.desc': {
    AppLang.tr: 'Havaalanı sonrası çeşmeden doldur — musluk suyu içilebilir.',
    AppLang.en: 'Refill after security — tap water is safe to drink.',
  },

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
  'weather.routeSubtitle': {
    AppLang.tr: 'Rotandaki her gün, o gün bulunduğun şehrin havası',
    AppLang.en: "Each day of your route, in the city you're in that day"
  },
  'weather.dayNumber': {AppLang.tr: '{n}. gün', AppLang.en: 'Day {n}'},
  'weather.dayCount': {AppLang.tr: '{n} gün', AppLang.en: '{n} days'},
  'weather.unknownCity': {
    AppLang.tr: 'Rota dışı günler',
    AppLang.en: 'Days outside the route'
  },
  // "Henüz" bilinçli: veri eksikliği kalıcı değil, tahmin ufku daha o güne
  // ulaşmadı. Kullanıcı yaklaştıkça dolacağını anlamalı.
  'weather.noData': {
    AppLang.tr: 'Henüz tahmin yok',
    AppLang.en: 'No forecast yet'
  },
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
  'explore.emptyAirports': {
    AppLang.tr: 'Önce Rota adımında varış havaalanlarını seçin.',
    AppLang.en: 'First choose your arrival airports in the Route step.'
  },
  'explore.sub': {
    AppLang.tr:
        'Uçuş güzergahınıza göre popüler yerler ve varışta yapılacaklar. Beğendiğinizi tek dokunuşla plana ekleyin.',
    AppLang.en:
        'Popular places and things to do along your flight route. Add the ones you like to your plan with a single tap.'
  },
  'explore.interests.title': {
    AppLang.tr: '🎯 İlgi alanların',
    AppLang.en: '🎯 Your interests'
  },
  'explore.interests.hint': {
    AppLang.tr: 'Birden fazla seç. Plan bunlara göre yönlendirilir.',
    AppLang.en: 'Pick several. Your plan is guided by these.'
  },
  'explore.style.title': {
    AppLang.tr: '🚶 Gezi stili',
    AppLang.en: '🚶 Travel style'
  },
  'explore.style.hint': {
    AppLang.tr: 'Yürüyüş hedefi, ulaşım ve ödeme tercihini seç.',
    AppLang.en: 'Choose your walking goal, transport and payment preference.'
  },
  'explore.style.walkLabel': {
    AppLang.tr: 'Yürüyüş tempon',
    AppLang.en: 'Walking pace'
  },
  'explore.style.transportLabel': {
    AppLang.tr: 'Ulaşım tercihi',
    AppLang.en: 'Transport preference'
  },
  'explore.style.paymentLabel': {
    AppLang.tr: 'Ödeme tercihi',
    AppLang.en: 'Payment preference'
  },
  'explore.mustSee.title': {
    AppLang.tr: '📌 Mutlaka görmek istediklerin',
    AppLang.en: '📌 Your must-see places'
  },
  'explore.mustSee.hint': {
    AppLang.tr: 'Serbest liste — plan oluştururken önceliklendirilir.',
    AppLang.en: 'Free-form list — prioritized when building your plan.'
  },
  'explore.popularPlaces': {
    AppLang.tr: '⭐ Popüler gezilecek yerler',
    AppLang.en: '⭐ Popular places to visit'
  },
  'explore.suggestKidRoute': {
    AppLang.tr: '🧸 Çocuk dostu rota öner',
    AppLang.en: '🧸 Suggest a kid-friendly route'
  },
  'explore.tapToAddHint': {
    AppLang.tr: 'Dokunarak ekle · ✓ rozetli karta tekrar dokun → çıkar',
    AppLang.en: 'Tap to add · tap a ✓ card again → remove'
  },
  'explore.removedFromPlan': {
    AppLang.tr: '✓ Plandan çıkarıldı',
    AppLang.en: '✓ Removed from plan'
  },
  'explore.addedToDay': {
    AppLang.tr: '✓ Gün {day}\'e eklendi',
    AppLang.en: '✓ Added to day {day}'
  },
  'explore.kidRouteDistributed': {
    AppLang.tr: '✓ {places} yer {days} güne dağıtıldı',
    AppLang.en: '✓ {places} spots spread across {days} days'
  },
  'explore.dayFallback': {AppLang.tr: 'Gün {n}', AppLang.en: 'Day {n}'},
  'opt.interest.anime': {
    AppLang.tr: 'Anime / Manga',
    AppLang.en: 'Anime / Manga'
  },
  'opt.interest.pokemon': {AppLang.tr: 'Pokémon', AppLang.en: 'Pokémon'},
  'opt.interest.shopping': {AppLang.tr: 'Alışveriş', AppLang.en: 'Shopping'},
  'opt.interest.temples': {AppLang.tr: 'Tapınaklar', AppLang.en: 'Temples'},
  'opt.interest.traditional': {
    AppLang.tr: 'Geleneksel Japonya',
    AppLang.en: 'Traditional Japan'
  },
  'opt.interest.tech': {
    AppLang.tr: 'Teknoloji mağazaları',
    AppLang.en: 'Tech stores'
  },
  'opt.interest.kids': {
    AppLang.tr: 'Çocuk aktiviteleri',
    AppLang.en: 'Kids activities'
  },
  'opt.interest.themeParks': {
    AppLang.tr: 'Tema parkları',
    AppLang.en: 'Theme parks'
  },
  'opt.interest.photography': {
    AppLang.tr: 'Fotoğraf noktaları',
    AppLang.en: 'Photo spots'
  },
  'opt.interest.food': {
    AppLang.tr: 'Yemek keşfi',
    AppLang.en: 'Food discovery'
  },
  'opt.interestW.temples': {AppLang.tr: 'Tapınaklar', AppLang.en: 'Temples'},
  'opt.interestW.traditional': {
    AppLang.tr: 'Geleneksel',
    AppLang.en: 'Traditional'
  },
  'opt.interestW.anime': {
    AppLang.tr: 'Anime & manga',
    AppLang.en: 'Anime & manga'
  },
  'opt.interestW.pokemon': {
    AppLang.tr: 'Pokemon & oyun',
    AppLang.en: 'Pokémon & games'
  },
  'opt.interestW.tech': {AppLang.tr: 'Teknoloji', AppLang.en: 'Tech'},
  'opt.interestW.shopping': {AppLang.tr: 'Alışveriş', AppLang.en: 'Shopping'},
  'opt.interestW.food': {
    AppLang.tr: 'Yemek odaklı',
    AppLang.en: 'Food-focused'
  },
  'opt.interestW.themeParks': {
    AppLang.tr: 'Tema parklar',
    AppLang.en: 'Theme parks'
  },
  'opt.interestW.kids': {AppLang.tr: 'Çocuk dostu', AppLang.en: 'Kid-friendly'},
  'opt.interestW.photography': {
    AppLang.tr: 'Fotoğrafçılık',
    AppLang.en: 'Photography'
  },
  'opt.sens.noPork': {
    AppLang.tr: 'Domuz eti istemiyorum',
    AppLang.en: 'No pork'
  },
  'opt.sens.noPorkDerivatives': {
    AppLang.tr: 'Domuz yağı / jelatin yok',
    AppLang.en: 'No pork fat / gelatin'
  },
  'opt.sens.noSeafood': {
    AppLang.tr: 'Deniz ürünü istemiyorum',
    AppLang.en: 'No seafood'
  },
  'opt.sens.halal': {
    AppLang.tr: 'Helal seçenek istiyorum',
    AppLang.en: 'Halal options'
  },
  'opt.sens.vegetarian': {AppLang.tr: 'Vejetaryen', AppLang.en: 'Vegetarian'},
  'opt.sens.chicken': {
    AppLang.tr: 'Tavuk ağırlıklı',
    AppLang.en: 'Chicken-focused'
  },
  'opt.sens.noFattyMeat': {
    AppLang.tr: 'Yağlı et sevmiyorum',
    AppLang.en: 'No fatty meat'
  },
  'opt.sens.kidFriendly': {
    AppLang.tr: 'Çocuk dostu restoran',
    AppLang.en: 'Kid-friendly restaurants'
  },
  'opt.sens.turkishPalate': {
    AppLang.tr: 'Türk damak tadına yakın',
    AppLang.en: 'Close to Turkish taste'
  },
  'opt.walk.light': {AppLang.tr: 'Az', AppLang.en: 'Light'},
  'opt.walk.light.hint': {
    AppLang.tr: '~7k adım/gün',
    AppLang.en: '~7k steps/day'
  },
  'opt.walk.moderate': {AppLang.tr: 'Orta', AppLang.en: 'Moderate'},
  'opt.walk.moderate.hint': {
    AppLang.tr: '~11k adım/gün',
    AppLang.en: '~11k steps/day'
  },
  'opt.walk.intense': {AppLang.tr: 'Yoğun', AppLang.en: 'Intense'},
  'opt.walk.intense.hint': {
    AppLang.tr: '~15k+ adım/gün',
    AppLang.en: '~15k+ steps/day'
  },
  'opt.transport.transit': {
    AppLang.tr: 'Toplu taşıma',
    AppLang.en: 'Public transit'
  },
  'opt.transport.mixed': {AppLang.tr: 'Karışık', AppLang.en: 'Mixed'},
  'opt.transport.taxi': {
    AppLang.tr: 'Taksi destekli',
    AppLang.en: 'Taxi-assisted'
  },
  'opt.transport.walking': {
    AppLang.tr: 'Yürüyüş ağırlıklı',
    AppLang.en: 'Mostly walking'
  },
  'opt.payment.card': {AppLang.tr: 'Kredi kartı', AppLang.en: 'Credit card'},
  'opt.payment.cash': {AppLang.tr: 'Nakit', AppLang.en: 'Cash'},
  'opt.payment.cardCash': {
    AppLang.tr: 'Kart + nakit',
    AppLang.en: 'Card + cash'
  },
  'opt.payment.ic': {
    AppLang.tr: 'IC kart (Suica/Pasmo)',
    AppLang.en: 'IC card (Suica/Pasmo)'
  },
  'opt.pace.relaxed': {AppLang.tr: 'Rahat', AppLang.en: 'Relaxed'},
  'opt.pace.relaxed.hint': {
    AppLang.tr: 'Az durak, uzun molalar',
    AppLang.en: 'Fewer stops, long breaks'
  },
  'opt.pace.moderate': {AppLang.tr: 'Dengeli', AppLang.en: 'Balanced'},
  'opt.pace.moderate.hint': {
    AppLang.tr: 'Standart tempo',
    AppLang.en: 'Standard pace'
  },
  'opt.pace.intense': {AppLang.tr: 'Yoğun', AppLang.en: 'Intense'},
  'opt.pace.intense.hint': {
    AppLang.tr: 'Çok yer, sıkı program',
    AppLang.en: 'Many spots, packed schedule'
  },
  'diet.halal.label': {AppLang.tr: 'Helal', AppLang.en: 'Halal'},
  'diet.halal.desc': {
    AppLang.tr: 'Helal sertifikalı veya domuzsuz seçenekler',
    AppLang.en: 'Halal-certified or pork-free options'
  },
  'diet.noPork.label': {AppLang.tr: 'Domuz yok', AppLang.en: 'No pork'},
  'diet.noPork.desc': {
    AppLang.tr: 'Domuz eti ve domuz yağı içermesin',
    AppLang.en: 'No pork meat or pork fat'
  },
  'diet.vegetarian.label': {AppLang.tr: 'Vejetaryen', AppLang.en: 'Vegetarian'},
  'diet.vegetarian.desc': {
    AppLang.tr: 'Et ve balık yok, yumurta/süt olabilir',
    AppLang.en: 'No meat or fish; eggs/dairy allowed'
  },
  'diet.vegan.label': {AppLang.tr: 'Vegan', AppLang.en: 'Vegan'},
  'diet.vegan.desc': {
    AppLang.tr: 'Hayvansal ürün yok',
    AppLang.en: 'No animal products'
  },
  'diet.lowFat.label': {
    AppLang.tr: 'Yağsız / hafif',
    AppLang.en: 'Low-fat / light'
  },
  'diet.lowFat.desc': {
    AppLang.tr: 'Kızartma ve ağır soslardan kaçın',
    AppLang.en: 'Avoid fried food and heavy sauces'
  },
  'diet.noAlcohol.label': {AppLang.tr: 'Alkolsüz', AppLang.en: 'Alcohol-free'},
  'diet.noAlcohol.desc': {
    AppLang.tr: 'Yemeklerde alkol kullanılmasın',
    AppLang.en: 'No alcohol used in dishes'
  },
  'diet.bakeryOk.label': {
    AppLang.tr: 'Hamur işi OK',
    AppLang.en: 'Baked goods OK'
  },
  'diet.bakeryOk.desc': {
    AppLang.tr: 'Ekmek, noodle, unlu atıştırmalıklar uygun',
    AppLang.en: 'Bread, noodles and flour-based snacks are fine'
  },
  'diet.meatOk.label': {AppLang.tr: 'Et sever', AppLang.en: 'Meat lover'},
  'diet.meatOk.desc': {
    AppLang.tr: 'Wagyu, yakiniku, et ağırlıklı menüler',
    AppLang.en: 'Wagyu, yakiniku, meat-heavy menus'
  },
  'diet.poultryOk.label': {
    AppLang.tr: 'Tavuk / hindi',
    AppLang.en: 'Chicken / turkey'
  },
  'diet.poultryOk.desc': {
    AppLang.tr: 'Yakitori, karaage, oyakodon uygun',
    AppLang.en: 'Yakitori, karaage and oyakodon are fine'
  },
  'diet.seafoodOk.label': {AppLang.tr: 'Deniz ürünü', AppLang.en: 'Seafood'},
  'diet.seafoodOk.desc': {
    AppLang.tr: 'Sushi, sashimi, deniz ürünleri uygun',
    AppLang.en: 'Sushi, sashimi and seafood are fine'
  },
  'diet.glutenFree.label': {AppLang.tr: 'Glutensiz', AppLang.en: 'Gluten-free'},
  'diet.glutenFree.desc': {
    AppLang.tr: 'Buğday / gluten hassasiyeti',
    AppLang.en: 'Wheat / gluten sensitivity'
  },
  'diet.spicyOk.label': {AppLang.tr: 'Acı sever', AppLang.en: 'Loves spicy'},
  'diet.spicyOk.desc': {
    AppLang.tr: 'Acı ve baharatlı yemekler uygun',
    AppLang.en: 'Spicy and heavily seasoned food is fine'
  },
  'diet.spicyAvoid.label': {
    AppLang.tr: 'Acı istemiyorum',
    AppLang.en: 'No spicy'
  },
  'diet.spicyAvoid.desc': {
    AppLang.tr: 'Acı sos ve gochujang azaltılsın',
    AppLang.en: 'Reduce chili sauce and gochujang'
  },
  'hotels.title': {AppLang.tr: 'Konaklama', AppLang.en: 'Stays'},
  'hotels.subtitle': {
    AppLang.tr:
        'Otel eklemek zorunda değilsin — konaklanacak bölgeyi yazmak yeter (taksi/rehber için). Otel ekleyeceksen açık adres gerekir.',
    AppLang.en:
        'You don\'t have to add a hotel — just naming the area you\'ll stay in is enough (for taxis and guides). If you do add one, a full address is required.'
  },
  'hotels.stayArea': {
    AppLang.tr: '🏘️ Konaklanacak bölge (opsiyonel)',
    AppLang.en: '🏘️ Area to stay (optional)'
  },
  'hotels.stayAreaHint': {
    AppLang.tr: 'Otel eklemesen de bu bölge adı taksi/rehberde kullanılır.',
    AppLang.en:
        'Even without a hotel, this area name is used for taxis and guides.'
  },
  'hotels.stayAreaPlaceholder': {
    AppLang.tr: 'Örn. Shinjuku, Namba, Kyoto istasyon çevresi',
    AppLang.en: 'e.g. Shinjuku, Namba, around Kyoto Station'
  },
  'hotels.emptyHint': {
    AppLang.tr:
        'Otel eklemek istersen aşağıdan ekle — istemiyorsan bölge yazmak yeterli.',
    AppLang.en:
        'Add a hotel below if you\'d like — otherwise naming the area is enough.'
  },
  'hotels.addHotel': {AppLang.tr: '+ Otel ekle', AppLang.en: '+ Add hotel'},
  'hotels.addAnother': {
    AppLang.tr: '+ Başka otel ekle',
    AppLang.en: '+ Add another hotel'
  },
  'hotels.deleteTitle': {AppLang.tr: 'Oteli sil', AppLang.en: 'Delete hotel'},
  'hotels.deleteConfirm': {
    AppLang.tr: '"{name}" silinsin mi?',
    AppLang.en: 'Delete "{name}"?'
  },
  'hotels.cancel': {AppLang.tr: 'Vazgeç', AppLang.en: 'Cancel'},
  'hotels.delete': {AppLang.tr: 'Sil', AppLang.en: 'Delete'},
  'hotels.hotelN': {AppLang.tr: 'Otel {n}', AppLang.en: 'Hotel {n}'},
  'hotels.addressRequired': {
    AppLang.tr: 'Taksi ve harita için adres gerekli',
    AppLang.en: 'Address required for taxis and maps'
  },
  'hotels.edit': {AppLang.tr: 'Düzenle', AppLang.en: 'Edit'},
  'hotels.city': {AppLang.tr: 'Şehir *', AppLang.en: 'City *'},
  'hotels.hotelName': {AppLang.tr: 'Otel adı *', AppLang.en: 'Hotel name *'},
  'hotels.checkIn': {AppLang.tr: 'Giriş *', AppLang.en: 'Check-in *'},
  'hotels.checkOut': {AppLang.tr: 'Çıkış *', AppLang.en: 'Check-out *'},
  'hotels.address': {
    AppLang.tr: 'Açık adres (sokak, posta kodu) *',
    AppLang.en: 'Full address (street, postal code) *'
  },
  'hotels.addressLocal': {
    AppLang.tr: 'Adres (yerel dil)',
    AppLang.en: 'Address (local language)'
  },
  'hotels.addressLocalHint': {
    AppLang.tr: 'Japonca — taksiciye göster',
    AppLang.en: 'Japanese — show it to the taxi driver'
  },
  'hotels.mapsUrl': {
    AppLang.tr: 'Google Maps linki',
    AppLang.en: 'Google Maps link'
  },
  'hotels.openMap': {
    AppLang.tr: 'Haritada aç',
    AppLang.en: 'Open in Maps',
  },
  'hotels.findOnMap': {
    AppLang.tr: 'Google Maps’te otel bul',
    AppLang.en: 'Find a hotel in Google Maps',
  },
  'hotels.mapPickerHelp': {
    AppLang.tr:
        'Google Maps ücretsiz açılır. Oteli bulduktan sonra adını, adresini veya paylaşım bağlantısını buraya ekleyebilirsin.',
    AppLang.en:
        'Google Maps opens for free. After finding the hotel, add its name, address, or shared link here.',
  },
  'hotels.mapOpenFailed': {
    AppLang.tr: 'Google Maps açılamadı.',
    AppLang.en: 'Google Maps could not be opened.',
  },
  'hotels.mapSearchDefault': {
    AppLang.tr: 'otel',
    AppLang.en: 'hotel',
  },
  'hotels.formIntro': {
    AppLang.tr:
        'Konaklama bilgilerini ekle; rota, taksi ve günlük plan detaylarında kullanalım.',
    AppLang.en:
        'Add your stay details so they can be used for routes, taxis, and daily planning.',
  },
  'hotels.phone': {AppLang.tr: 'Telefon', AppLang.en: 'Phone'},
  'hotels.notes': {AppLang.tr: 'Notlar', AppLang.en: 'Notes'},
  'hotels.notesPlaceholder': {
    AppLang.tr: 'Check-in saati, kat, ek notlar',
    AppLang.en: 'Check-in time, floor, extra notes'
  },
  'hotels.done': {AppLang.tr: 'Bitti', AppLang.en: 'Done'},
  'hotels.saveHotel': {AppLang.tr: 'Oteli kaydet', AppLang.en: 'Save hotel'},
  'hotels.saving': {AppLang.tr: 'Kaydediliyor…', AppLang.en: 'Saving…'},
  'hotels.saveError': {
    AppLang.tr: 'Plan yüklenemedi.',
    AppLang.en: 'Could not load the plan.',
  },
  'hotels.saveFailed': {
    AppLang.tr: 'Otel kaydedilemedi. Bağlantını kontrol edip tekrar dene.',
    AppLang.en: 'Could not save the hotel. Check your connection and retry.',
  },
  'hotels.pickDate': {AppLang.tr: 'Tarih seç', AppLang.en: 'Pick a date'},
  'booking.title': {
    AppLang.tr: 'Bilet açılış tarihleri',
    AppLang.en: 'Ticket sale dates'
  },
  'booking.body': {
    AppLang.tr:
        'Planına eklenen aşağıdaki deneyimlerin biletleri sınırlı süreyle satışa açılıyor. Hatırlatma açarsan bilet satışa çıktığı gün sabah 09:00\'da bildirim geleceğim.',
    AppLang.en:
        'Tickets for the experiences below in your plan go on sale for a limited time. Turn on a reminder and I\'ll notify you at 09:00 on the morning they open.'
  },
  'booking.notNow': {AppLang.tr: 'Şimdi değil', AppLang.en: 'Not now'},
  'booking.adding': {AppLang.tr: 'Ekleniyor…', AppLang.en: 'Adding…'},
  'booking.addReminders': {
    AppLang.tr: 'Hatırlatmaları ekle',
    AppLang.en: 'Add reminders'
  },
  'booking.reminderSubtitle': {
    AppLang.tr: 'Bilet bugün satışa açıldı — {date} planı için.',
    AppLang.en: 'Tickets went on sale today — for your {date} plan.'
  },
  'booking.salePill': {
    AppLang.tr: 'Satış: {date} · {days} gün önce',
    AppLang.en: 'On sale: {date} · {days} days before'
  },
  'booking.planDayPill': {
    AppLang.tr: 'Plan günü: {date}',
    AppLang.en: 'Plan day: {date}'
  },
  'booking.windowPassed': {
    AppLang.tr: 'Satış penceresi geçti / bugün',
    AppLang.en: 'Sale window passed / today'
  },
  'pickers.airportPlaceholder': {
    AppLang.tr: 'Havaalanı, şehir veya ülke',
    AppLang.en: 'Airport, city or country'
  },
  'pickers.airlinePlaceholder': {
    AppLang.tr: 'Havayolu (örn. Turkish Airlines, TK)',
    AppLang.en: 'Airline (e.g. Turkish Airlines, TK)'
  },
  'pickers.pickAirport': {
    AppLang.tr: 'Havaalanı seç',
    AppLang.en: 'Select airport'
  },
  'pickers.airportSearchHint': {
    AppLang.tr: 'IATA, şehir veya ülke',
    AppLang.en: 'IATA, city or country'
  },
  'pickers.pickAirline': {
    AppLang.tr: 'Havayolu seç',
    AppLang.en: 'Select airline'
  },
  'pickers.airlineSearchHint': {
    AppLang.tr: 'Ad veya kod (TK, JL…)',
    AppLang.en: 'Name or code (TK, JL…)'
  },
  'pickers.close': {AppLang.tr: 'Kapat', AppLang.en: 'Close'},
  'journey.title': {
    AppLang.tr: '🇯🇵 Japonya rotası',
    AppLang.en: '🇯🇵 Japan route'
  },
  'journey.sub.ticket': {
    AppLang.tr:
        'Kalkış ve dönüş uçuşlarını gir. Her uçuş kartında havayolu, uçuş no, tarih ve havaalanları var.',
    AppLang.en:
        'Enter your outbound and return flights. Each flight card has the airline, flight number, date and airports.'
  },
  'journey.sub.plan': {
    AppLang.tr:
        'Nereden kalkacaksın ve Japonya\'da hangi şehre ineceksin? Şimdilik şehir ve tarih yeter.',
    AppLang.en:
        'Where will you take off from, and which city in Japan will you land in? For now, city and date are enough.'
  },
  'journey.routeLabel': {AppLang.tr: 'Rota: ', AppLang.en: 'Route: '},
  'journey.continueHint': {
    AppLang.tr: 'Devam için: kalkış ve Japonya varış havaalanını seç.',
    AppLang.en: 'To continue, choose your departure and Japan arrival airports.'
  },
  'journey.shinkansen.title': {
    AppLang.tr: '🚄 Şehirler arası Shinkansen',
    AppLang.en: '🚄 Shinkansen between cities'
  },
  'journey.shinkansen.body': {
    AppLang.tr:
        'Birden fazla şehir gezeceksin → Shinkansen (yüksek hızlı tren) en pratiği.',
    AppLang.en:
        'You\'ll be visiting more than one city → the Shinkansen (bullet train) is the most practical way.'
  },
  'journey.shinkansen.note': {
    AppLang.tr:
        'JR Pass / Smart-EX önerilir. Plan adımında otomatik şehir geçiş kartları çıkar.',
    AppLang.en:
        'JR Pass / Smart-EX recommended. City-to-city transfer cards appear automatically in the Plan step.'
  },
  'journey.cities.title': {
    AppLang.tr: '🏙️ Gezilecek şehirler',
    AppLang.en: '🏙️ Cities to visit'
  },
  'journey.cities.hint': {
    AppLang.tr:
        'Listeden seç — rotana eklenir. Tekrar dokun → çıkar. İkinci şehri seçtiğinde şehirler arası Shinkansen önerilir.',
    AppLang.en:
        'Pick from the list to add it to your route. Tap again to remove. Choosing a second city suggests the Shinkansen between cities.'
  },
  'journey.banner.title': {
    AppLang.tr: '🇯🇵 Japonya 14 günlük tam plan',
    AppLang.en: '🇯🇵 Full 14-day Japan plan'
  },
  'journey.banner.body': {
    AppLang.tr:
        'Tokyo → Kyoto → Nara → Osaka rotası; günler, tarihler ve oteller hazır.',
    AppLang.en:
        'Tokyo → Kyoto → Nara → Osaka route; days, dates and hotels are ready.'
  },
  'journey.banner.load': {AppLang.tr: 'Planı yükle', AppLang.en: 'Load plan'},
  'journey.leg.outbound': {
    AppLang.tr: '✈︎ Gidiş — Japonya\'ya',
    AppLang.en: '✈︎ Outbound — to Japan'
  },
  'journey.leg.route': {
    AppLang.tr: '📍 Rota — Japonya\'ya',
    AppLang.en: '📍 Route — to Japan'
  },
  'journey.leg.return': {
    AppLang.tr: '🏠 Dönüş — Japonya\'dan',
    AppLang.en: '🏠 Return — from Japan'
  },
  'journey.field.airline': {AppLang.tr: 'Havayolu', AppLang.en: 'Airline'},
  'journey.field.flightNo': {
    AppLang.tr: 'Uçuş numarası',
    AppLang.en: 'Flight number'
  },
  'journey.field.date': {AppLang.tr: 'Tarih', AppLang.en: 'Date'},
  'journey.field.departureTr': {AppLang.tr: 'Kalkış', AppLang.en: 'Departure'},
  'journey.field.arrivalJp': {
    AppLang.tr: 'Varış (Japonya)',
    AppLang.en: 'Arrival (Japan)'
  },
  'journey.field.departureJp': {
    AppLang.tr: 'Kalkış (Japonya)',
    AppLang.en: 'Departure (Japan)'
  },
  'journey.field.arrivalTr': {AppLang.tr: 'Varış', AppLang.en: 'Arrival'},
  'journey.ph.returnDep': {
    AppLang.tr: 'Japonya\'dan kalkış havalimanı',
    AppLang.en: 'Departure airport in Japan'
  },
  'journey.ph.returnArr': {
    AppLang.tr: 'Kalkış ülkene varış havalimanı',
    AppLang.en: 'Arrival airport back home'
  },
  'journey.pax.title': {
    AppLang.tr: 'Yolcu & seçenekler',
    AppLang.en: 'Passengers & options'
  },
  'journey.pax.subtitle': {
    AppLang.tr: 'Kaç kişi + kaç çocuk?',
    AppLang.en: 'How many adults + children?'
  },
  'journey.pax.adult': {AppLang.tr: 'Yetişkin', AppLang.en: 'Adults'},
  'journey.pax.child': {AppLang.tr: 'Çocuk', AppLang.en: 'Children'},
  'journey.pax.pace': {AppLang.tr: 'Tempo', AppLang.en: 'Pace'},
  'journey.pace.relaxed': {AppLang.tr: 'Rahat', AppLang.en: 'Relaxed'},
  'journey.pace.moderate': {AppLang.tr: 'Dengeli', AppLang.en: 'Balanced'},
  'journey.pace.intense': {AppLang.tr: 'Yoğun', AppLang.en: 'Intense'},
  'journey.date.pick': {AppLang.tr: 'Tarih seç', AppLang.en: 'Pick a date'},
  'journey.time.pick': {AppLang.tr: 'Saat seç', AppLang.en: 'Pick a time'},
  'journey.field.arrivalTime': {
    AppLang.tr: 'İniş saati (Japonya)',
    AppLang.en: 'Arrival time (Japan)'
  },
  'journey.field.departureTime': {
    AppLang.tr: 'Kalkış saati (Japonya)',
    AppLang.en: 'Departure time (Japan)'
  },
  'journey.city.other': {
    AppLang.tr: '+ Başka şehir',
    AppLang.en: '+ Another city'
  },
  'journey.city.sheetTitle': {
    AppLang.tr: 'Şehir seç',
    AppLang.en: 'Choose a city'
  },
  'journey.city.close': {AppLang.tr: 'Kapat', AppLang.en: 'Close'},
  'journey.city.searchHint': {
    AppLang.tr: 'Şehir ara — Kyoto, Hakone, Nikko…',
    AppLang.en: 'Search cities — Kyoto, Hakone, Nikko…'
  },
  'journey.city.airport': {AppLang.tr: 'Havalimanı', AppLang.en: 'Airport'},
  'journey.city.byTrain': {
    AppLang.tr: 'Shinkansen / tren erişimli',
    AppLang.en: 'Reachable by Shinkansen / train'
  },
  'journey.cities.inertHint': {
    AppLang.tr: 'Seçmek yalnızca şehri ekler — rota ve tarihler değişmez.',
    AppLang.en: 'Selecting only adds the city — route and dates stay.'
  },
  'journey.badge.arrival': {AppLang.tr: 'iniş', AppLang.en: 'arrival'},
  'journey.badge.return': {AppLang.tr: 'dönüş', AppLang.en: 'return'},
  'journey.cityPlaces.title': {
    AppLang.tr: '{city} · gezilecekler',
    AppLang.en: '{city} · things to do'
  },
  'journey.cityPlaces.selected': {
    AppLang.tr: '{n} seçili',
    AppLang.en: '{n} selected'
  },
  'placeDetail.nearby': {AppLang.tr: 'Yakınlarda', AppLang.en: 'Nearby'},
  'placeDetail.nearbyRestaurants': {
    AppLang.tr: 'Yakındaki restoranlar (haritada aç)',
    AppLang.en: 'Nearby restaurants (open in Maps)',
  },
  'placeDetail.whatToEat': {AppLang.tr: 'Ne yenir', AppLang.en: 'What to eat'},
  'placeDetail.tips': {AppLang.tr: 'İpuçları', AppLang.en: 'Tips'},
  'placeDetail.duration': {AppLang.tr: 'Süre', AppLang.en: 'Duration'},
  'placeDetail.walking': {AppLang.tr: 'Yürüme', AppLang.en: 'Walking'},
  'placeDetail.ticketLabel': {AppLang.tr: 'Bilet', AppLang.en: 'Ticket'},
  'placeDetail.daysBefore': {
    AppLang.tr: '{n} gün önce',
    AppLang.en: '{n} days ahead'
  },
  'placeDetail.steps': {AppLang.tr: '~{n} adım', AppLang.en: '~{n} steps'},
  'placeDetail.stepsThousand': {
    AppLang.tr: '~{n} bin adım',
    AppLang.en: '~{n}k steps'
  },
  'placeDetail.durationMin': {AppLang.tr: '{n} dk', AppLang.en: '{n} min'},
  'placeDetail.durationHour': {AppLang.tr: '{n} saat', AppLang.en: '{n} hr'},
  'placeDetail.durationHourMin': {
    AppLang.tr: '{h} sa {m} dk',
    AppLang.en: '{h} hr {m} min'
  },
  'placeDetail.thousandShort': {AppLang.tr: 'bin', AppLang.en: 'k'},
  'placeDetail.reviewCount': {
    AppLang.tr: '({n} yorum)',
    AppLang.en: '({n} reviews)'
  },
  'placeDetail.defaultIntro': {
    AppLang.tr: 'Planınızdaki bir durak.',
    AppLang.en: 'A stop on your itinerary.'
  },
  'placeDetail.openMap': {
    AppLang.tr: 'Haritada aç',
    AppLang.en: 'Open in Maps'
  },
  'placeDetail.edit': {AppLang.tr: 'Düzenle', AppLang.en: 'Edit'},
  'placeDetail.mapOpenFailed': {
    AppLang.tr: 'Harita açılamadı — bağlantı panoya kopyalandı',
    AppLang.en: 'Couldn\'t open the map — link copied to clipboard'
  },
  'placeDetail.camera': {AppLang.tr: 'Kamera', AppLang.en: 'Camera'},
  'placeDetail.gallery': {AppLang.tr: 'Galeri', AppLang.en: 'Gallery'},
  'placeDetail.cancel': {AppLang.tr: 'Vazgeç', AppLang.en: 'Cancel'},
  'placeDetail.addTicket': {AppLang.tr: 'Bilet ekle', AppLang.en: 'Add ticket'},
  'placeDetail.adding': {AppLang.tr: 'Ekleniyor…', AppLang.en: 'Adding…'},
  'placeDetail.ticketCardTitle': {
    AppLang.tr: '🎫 Bilet',
    AppLang.en: '🎫 Ticket'
  },
  'placeDetail.ticketAdded': {
    AppLang.tr: '🎫 Bilet eklendi',
    AppLang.en: '🎫 Ticket added'
  },
  'placeDetail.ticketAddedStatus': {
    AppLang.tr: 'Bilet eklendi',
    AppLang.en: 'Ticket added'
  },
  'placeDetail.ticketAddedWeb': {
    AppLang.tr:
        '🎫 Bilet eklendi · Otomatik metin çıkarımı cihazda (iOS) çalışır',
    AppLang.en:
        '🎫 Ticket added · Automatic text extraction runs on device (iOS)'
  },
  'placeDetail.ticketAddFailed': {
    AppLang.tr: 'Bilet eklenemedi — tekrar deneyin',
    AppLang.en: 'Couldn\'t add the ticket — please try again'
  },
  'placeDetail.visitDate': {
    AppLang.tr: 'Ziyaret: {date}',
    AppLang.en: 'Visit: {date}'
  },
  'placeDetail.scannedText': {
    AppLang.tr: '📄 Okunan metin',
    AppLang.en: '📄 Scanned text'
  },
  'placeDetail.category.temple': {AppLang.tr: 'Tapınak', AppLang.en: 'Temple'},
  'placeDetail.category.shrine': {AppLang.tr: 'Tapınak', AppLang.en: 'Shrine'},
  'placeDetail.category.view': {AppLang.tr: 'Manzara', AppLang.en: 'View'},
  'placeDetail.category.city': {AppLang.tr: 'Şehir', AppLang.en: 'City'},
  'placeDetail.category.museum': {AppLang.tr: 'Müze', AppLang.en: 'Museum'},
  'placeDetail.category.park': {AppLang.tr: 'Park', AppLang.en: 'Park'},
  'placeDetail.category.shopping': {
    AppLang.tr: 'Alışveriş',
    AppLang.en: 'Shopping'
  },
  'placeDetail.category.fun': {
    AppLang.tr: 'Eğlence',
    AppLang.en: 'Entertainment'
  },
  'placeDetail.category.nature': {AppLang.tr: 'Doğa', AppLang.en: 'Nature'},
  'placeDetail.category.food': {AppLang.tr: 'Yemek', AppLang.en: 'Food'},
  'placeDetail.category.culture': {AppLang.tr: 'Kültür', AppLang.en: 'Culture'},
  'placeDetail.category.landmark': {
    AppLang.tr: 'Simge yapı',
    AppLang.en: 'Landmark'
  },
  'plan.generate': {
    AppLang.tr: '✨ Gezi planı oluştur',
    AppLang.en: '✨ Build trip plan'
  },
  'plan.regenerate': {
    AppLang.tr: '✨ Planı yeniden oluştur',
    AppLang.en: '✨ Rebuild trip plan'
  },
  'plan.generating': {
    AppLang.tr: '✨ Plan oluşturuluyor…',
    AppLang.en: '✨ Building your plan…'
  },
  'plan.generated': {
    AppLang.tr: '✨ Gezi planı oluşturuldu',
    AppLang.en: '✨ Trip plan ready'
  },
  'plan.regenerated': {
    AppLang.tr: '✨ Plan yeniden oluşturuldu',
    AppLang.en: '✨ Plan rebuilt'
  },
  'plan.regenConfirmTitle': {
    AppLang.tr: 'Planı yeniden oluştur',
    AppLang.en: 'Rebuild the plan'
  },
  'plan.regenConfirmBody': {
    AppLang.tr:
        'Mevcut plan küratörlü şablonlardan yeniden üretilecek. Elle yaptığınız düzenlemeler değişebilir. Devam edilsin mi?',
    AppLang.en:
        'Your current plan will be rebuilt from curated templates. Your manual edits may change. Continue?'
  },
  'plan.regenConfirm': {AppLang.tr: 'Yeniden oluştur', AppLang.en: 'Rebuild'},
  'plan.cancel': {AppLang.tr: 'Vazgeç', AppLang.en: 'Cancel'},
  'plan.delete': {AppLang.tr: 'Sil', AppLang.en: 'Delete'},
  'plan.save': {AppLang.tr: 'Kaydet', AppLang.en: 'Save'},
  'plan.done': {AppLang.tr: 'Bitti', AppLang.en: 'Done'},
  'plan.add': {AppLang.tr: '+ Ekle', AppLang.en: '+ Add'},
  'plan.addPlain': {AppLang.tr: 'Ekle', AppLang.en: 'Add'},
  'plan.addActivity': {AppLang.tr: '+ Aktivite', AppLang.en: '+ Activity'},
  'plan.optimize': {AppLang.tr: '⚡ Optimize et', AppLang.en: '⚡ Optimize'},
  'plan.discover': {
    AppLang.tr: '🌍 Yeni durak keşfet',
    AppLang.en: '🌍 Discover a new stop'
  },
  'plan.remindersAdded': {
    AppLang.tr: '🔔 {n} hatırlatma eklendi',
    AppLang.en: '🔔 {n} reminders added'
  },
  'popular.title': {AppLang.tr: 'Popüler yerler', AppLang.en: 'Popular places'},
  'popular.sub': {
    AppLang.tr: 'Plana eklemek istediklerini seç — istersen atla.',
    AppLang.en: 'Pick the ones to add to your plan — or skip.'
  },
  'popular.skip': {AppLang.tr: 'Atla', AppLang.en: 'Skip'},
  'popular.confirm': {
    AppLang.tr: 'Ekle ve oluştur',
    AppLang.en: 'Add & generate'
  },
  'popular.cityWarn.title': {
    AppLang.tr: 'Farklı şehir',
    AppLang.en: 'Different city'
  },
  'popular.cityWarn.body': {
    AppLang.tr:
        '{place} {city} şehrinde. Rotana {city} eklenip plan ona göre yapılsın mı?',
    AppLang.en:
        '{place} is in {city}. Add {city} to your route and plan accordingly?'
  },
  'popular.cityWarn.confirm': {
    AppLang.tr: 'Evet, ekle',
    AppLang.en: 'Yes, add'
  },
  'popular.cityWarn.cancel': {AppLang.tr: 'Vazgeç', AppLang.en: 'Cancel'},
  'plan.emptyRouteSub': {
    AppLang.tr: 'Önce Rota adımında havaalanı/durak ekleyin.',
    AppLang.en: 'Add an airport or stop in the Route step first.'
  },
  'plan.daysRoute': {
    AppLang.tr: '{n} gün · {route}',
    AppLang.en: '{n} days · {route}'
  },
  'plan.childrenSuffix': {
    AppLang.tr: ' · {n} çocuk',
    AppLang.en: ' · {n} children'
  },
  'plan.pace': {AppLang.tr: 'Tempo', AppLang.en: 'Pace'},
  'plan.childrenQuestion': {AppLang.tr: 'Çocuk', AppLang.en: 'Children'},
  'plan.pace.relaxed': {AppLang.tr: 'Rahat', AppLang.en: 'Relaxed'},
  'plan.pace.moderate': {AppLang.tr: 'Dengeli', AppLang.en: 'Balanced'},
  'plan.pace.intense': {AppLang.tr: 'Yoğun', AppLang.en: 'Intense'},
  'plan.stepsK': {AppLang.tr: '👣 {n}k adım', AppLang.en: '👣 {n}k steps'},
  'plan.dayAlloc.title': {
    AppLang.tr: 'Gün dağılımı',
    AppLang.en: 'Days per city'
  },
  'plan.dayAlloc.summary': {
    AppLang.tr: 'Toplam {total} gün · kalan {left}',
    AppLang.en: '{total} days total · {left} left'
  },
  'plan.introBlurb': {
    AppLang.tr:
        'Saat saat aktivite, ulaşım, restoran ve ipuçları küratörlü şablonlardan üretilir. Günleri sürükleyerek düzenleyebilirsiniz.',
    AppLang.en:
        'Hour-by-hour activities, transport, restaurants and tips are generated from curated templates. Drag the days to rearrange them.'
  },
  'plan.transitionsTitle': {
    AppLang.tr: '🚄 Şehirler arası geçiş önerisi',
    AppLang.en: '🚄 Suggested city-to-city transfer'
  },
  'plan.addAll': {
    AppLang.tr: 'Hepsini ekle ({n})',
    AppLang.en: 'Add all ({n})'
  },
  'plan.noPlanTitle': {AppLang.tr: 'Henüz plan yok', AppLang.en: 'No plan yet'},
  'plan.noPlanBody': {
    AppLang.tr: 'Yukarıdaki butonla kur — sonra saat saat düzenleyebilirsin.',
    AppLang.en:
        'Build it with the button above — then fine-tune it hour by hour.'
  },
  'plan.emptyDaysTitle': {
    AppLang.tr: 'Gün listesi boş kaldı',
    AppLang.en: 'Your days are empty'
  },
  'plan.emptyDaysBody': {
    AppLang.tr: 'Rota veya tarihleri güncelleyip "Planı yeniden oluştur"a bas.',
    AppLang.en: 'Update your route or dates, then tap "Rebuild trip plan".'
  },
  'plan.pickTransportTitle': {
    AppLang.tr: 'Ulaşım modunu seç',
    AppLang.en: 'Choose transport mode'
  },
  'plan.mode.shinkansenNote': {
    AppLang.tr: 'Yüksek hızlı tren — en hızlı, konforlu.',
    AppLang.en: 'High-speed rail — the fastest and most comfortable.'
  },
  'plan.mode.trainLabel': {
    AppLang.tr: 'Yerel / hızlı tren',
    AppLang.en: 'Local / rapid train'
  },
  'plan.mode.trainNote': {
    AppLang.tr: 'Daha ucuz, sürelidir. IC kart yeter.',
    AppLang.en: 'Cheaper but slower. An IC card is all you need.'
  },
  'plan.mode.busLabel': {
    AppLang.tr: 'Gecelik otobüs',
    AppLang.en: 'Overnight bus'
  },
  'plan.mode.busNote': {
    AppLang.tr: 'Ucuz ama 8+ saat sürer. Willer Express popüler.',
    AppLang.en: 'Cheap but takes 8+ hours. Willer Express is popular.'
  },
  'plan.mode.carLabel': {AppLang.tr: 'Kiralık araç', AppLang.en: 'Rental car'},
  'plan.mode.carNote': {
    AppLang.tr: 'Uluslararası ehliyet gerekir. Kırsalda mantıklı.',
    AppLang.en: 'Requires an international license. Makes sense in rural areas.'
  },
  'plan.dayRange': {
    AppLang.tr: 'Gün {from} → Gün {to} · {duration} · {fare}',
    AppLang.en: 'Day {from} → Day {to} · {duration} · {fare}'
  },
  'plan.changeTransport': {
    AppLang.tr: 'Ulaşım değiştir',
    AppLang.en: 'Change transport'
  },
  'plan.yamatoTitle': {
    AppLang.tr: 'Yamato Takkyubin — valiz transferi',
    AppLang.en: 'Yamato Takkyubin — luggage transfer'
  },
  'plan.yamatoBody': {
    AppLang.tr:
        'Valizini Yamato Takkyubin ile otele önceden gönderebilirsin — ~2000¥/parça, 1 gün sürer. Otel resepsiyonuna "takkyubin" de yeter.',
    AppLang.en:
        'You can send your luggage ahead to the hotel with Yamato Takkyubin — about ¥2000 per piece, takes 1 day. Just say "takkyubin" at the hotel front desk.'
  },
  'plan.dayN': {AppLang.tr: 'Gün {n}', AppLang.en: 'Day {n}'},
  'plan.stops': {AppLang.tr: '{n} durak', AppLang.en: '{n} stops'},
  'plan.dayTheme': {AppLang.tr: 'Gün teması', AppLang.en: 'Day theme'},
  'plan.dayThemeHint': {
    AppLang.tr: 'Örn. Asakusa & Skytree',
    AppLang.en: 'e.g. Asakusa & Skytree'
  },
  'plan.dayEmpty': {
    AppLang.tr: 'Bu güne aktivite ekleyin veya başka günden taşıyın.',
    AppLang.en: 'Add an activity to this day, or move one from another day.'
  },
  'plan.removeConfirmTitle': {
    AppLang.tr: 'Aktiviteyi sil',
    AppLang.en: 'Remove activity'
  },
  'plan.removeConfirmBody': {
    AppLang.tr: '"{title}" silinsin mi?',
    AppLang.en: 'Remove "{title}"?'
  },
  'plan.movedFrom': {
    AppLang.tr: '↕ Gün {n}\'den taşındı',
    AppLang.en: '↕ Moved from Day {n}'
  },
  'plan.moveToDay': {
    AppLang.tr: 'Başka güne taşı',
    AppLang.en: 'Move to another day'
  },
  'plan.dayWithDate': {
    AppLang.tr: 'Gün {n} · {date}',
    AppLang.en: 'Day {n} · {date}'
  },
  'plan.editActivity': {
    AppLang.tr: 'Aktiviteyi düzenle',
    AppLang.en: 'Edit activity'
  },
  'plan.fieldTitle': {AppLang.tr: 'Başlık', AppLang.en: 'Title'},
  'plan.fieldTime': {AppLang.tr: 'Saat', AppLang.en: 'Time'},
  'plan.fieldDuration': {AppLang.tr: 'Süre (dk)', AppLang.en: 'Duration (min)'},
  'plan.fieldCost': {AppLang.tr: 'Ücret', AppLang.en: 'Cost'},
  'plan.fieldCurrency': {AppLang.tr: 'Birim', AppLang.en: 'Currency'},
  'plan.fieldDescription': {AppLang.tr: 'Açıklama', AppLang.en: 'Description'},
  'plan.fieldDescriptionHint': {
    AppLang.tr: 'Kısa açıklama',
    AppLang.en: 'Short description'
  },
  'plan.fieldTips': {AppLang.tr: 'İpucu', AppLang.en: 'Tip'},
  'plan.fieldTipsHint': {
    AppLang.tr: 'Örn. Erken git, sıra uzun olur',
    AppLang.en: 'e.g. Go early, the line gets long'
  },
  'plan.copyMapLink': {
    AppLang.tr: '🗺️ Harita linkini kopyala',
    AppLang.en: '🗺️ Copy map link'
  },
  'plan.mapLinkCopied': {
    AppLang.tr: 'Harita linki kopyalandı',
    AppLang.en: 'Map link copied'
  },
  'plan.pickTime': {AppLang.tr: 'Saat seç', AppLang.en: 'Pick a time'},
  'plan.discoverPortal': {
    AppLang.tr: 'Keşif portalı',
    AppLang.en: 'Discovery portal'
  },
  'plan.placeSuggestions': {
    AppLang.tr: 'Yer önerileri',
    AppLang.en: 'Place suggestions'
  },
  'plan.discoverSub': {
    AppLang.tr: 'En çok ziyaret edilen yerler — karta dokununca plana eklenir.',
    AppLang.en: 'The most-visited places — tap a card to add it to your plan.'
  },
  'plan.pickMultiple': {
    AppLang.tr: 'Birden fazla seçebilirsin',
    AppLang.en: 'You can pick more than one'
  },
  'plan.placesAdded': {
    AppLang.tr: '{n} yer eklendi',
    AppLang.en: '{n} places added'
  },
  'plan.advanceBooking': {
    AppLang.tr: '🎟 {n} gün önce bilet',
    AppLang.en: '🎟 Book {n} days ahead'
  },
  'plan.kidFriendly': {
    AppLang.tr: '🧒 Çocuk dostu',
    AppLang.en: '🧒 Kid-friendly'
  },
  'plan.durMin': {AppLang.tr: '{n} dk', AppLang.en: '{n} min'},
  'plan.durHour': {AppLang.tr: '{n} saat', AppLang.en: '{n} hr'},
  'plan.durHourMin': {AppLang.tr: '{h} sa {m} dk', AppLang.en: '{h}h {m}m'},
  'plan.kindActivity': {AppLang.tr: 'Aktivite', AppLang.en: 'Activity'},
  'plan.kindMeal': {AppLang.tr: 'Yemek', AppLang.en: 'Food'},
  'plan.kindTransport': {AppLang.tr: 'Ulaşım', AppLang.en: 'Transport'},
  'plan.kindHotel': {AppLang.tr: 'Otel', AppLang.en: 'Hotel'},
  'plan.addActivityTitle': {
    AppLang.tr: 'Yeni aktivite ekle',
    AppLang.en: 'Add new activity'
  },
  'plan.placeName': {AppLang.tr: 'Yer adı', AppLang.en: 'Place name'},
  'plan.placeNameRequired': {
    AppLang.tr: 'Yer adı gerekli',
    AppLang.en: 'Place name is required'
  },
  'plan.placeNameHint': {
    AppLang.tr: 'Örn. Senso-ji, teamLab, ramen molası',
    AppLang.en: 'e.g. Senso-ji, teamLab, ramen break'
  },
  'plan.noSlots': {
    AppLang.tr: 'Boş dilim yok — mevcut aktivitelerden birini kaldır.',
    AppLang.en: 'No open slots — remove one of the existing activities.'
  },
  'plan.kindOptional': {
    AppLang.tr: 'Tür (opsiyonel)',
    AppLang.en: 'Type (optional)'
  },
  'shell.brand': {AppLang.tr: 'Seyahat', AppLang.en: 'Trip'},
  'shell.newPlan': {AppLang.tr: 'Yeni plan', AppLang.en: 'New plan'},
  'shell.guide': {AppLang.tr: 'Rehber', AppLang.en: 'Guide'},
  'shell.createPlan': {AppLang.tr: 'Planı Oluştur', AppLang.en: 'Create Plan'},
  'shell.back': {AppLang.tr: 'Geri', AppLang.en: 'Back'},
  'shell.continue': {AppLang.tr: 'Devam', AppLang.en: 'Continue'},

  // ===== Screens + data labels (Wave 2/3, agent-generated) =====
  'compassData.cat.basic': {AppLang.tr: 'Temel', AppLang.en: 'Basics'},
  'compassData.cat.food': {
    AppLang.tr: 'Yemekte sor',
    AppLang.en: 'Ask about food'
  },
  'compassData.cat.directions': {
    AppLang.tr: 'Yol sor',
    AppLang.en: 'Ask for directions'
  },
  'compassData.cat.emergency': {AppLang.tr: 'Acil', AppLang.en: 'Emergency'},
  'compassData.phrase.basic.excuseMe': {
    AppLang.tr: 'Affedersiniz / Pardon',
    AppLang.en: 'Excuse me / Sorry'
  },
  'compassData.phrase.basic.thanks': {
    AppLang.tr: 'Çok teşekkürler',
    AppLang.en: 'Thank you very much'
  },
  'compassData.phrase.basic.english': {
    AppLang.tr: 'İngilizce biliyor musunuz?',
    AppLang.en: 'Do you speak English?'
  },
  'compassData.phrase.basic.howMuch': {
    AppLang.tr: 'Kaç para?',
    AppLang.en: 'How much is it?'
  },
  'compassData.phrase.basic.toilet': {
    AppLang.tr: 'Tuvalet nerede?',
    AppLang.en: 'Where is the toilet?'
  },
  'compassData.phrase.food.pork': {
    AppLang.tr: 'Bu yemekte domuz eti var mı?',
    AppLang.en: 'Does this dish contain pork?'
  },
  'compassData.phrase.food.lard': {
    AppLang.tr: 'Domuz yağı kullanılıyor mu?',
    AppLang.en: 'Is lard used in this?'
  },
  'compassData.phrase.food.alcohol': {
    AppLang.tr: 'Alkol içeriyor mu?',
    AppLang.en: 'Does it contain alcohol?'
  },
  'compassData.phrase.food.chicken': {
    AppLang.tr: 'Tavuklu seçenek var mı?',
    AppLang.en: 'Is there a chicken option?'
  },
  'compassData.phrase.food.seafood': {
    AppLang.tr: 'Deniz ürünü içeriyor mu?',
    AppLang.en: 'Does it contain seafood?'
  },
  'compassData.phrase.food.kidMild': {
    AppLang.tr: 'Çocuk için acısız bir seçenek var mı?',
    AppLang.en: 'Is there a non-spicy option for kids?'
  },
  'compassData.phrase.food.vegetarian': {
    AppLang.tr: 'Vejetaryen menü var mı?',
    AppLang.en: 'Is there a vegetarian menu?'
  },
  'compassData.phrase.directions.station': {
    AppLang.tr: 'İstasyon nerede?',
    AppLang.en: 'Where is the station?'
  },
  'compassData.phrase.directions.trainGoes': {
    AppLang.tr: 'Bu tren __ a gidiyor mu?',
    AppLang.en: 'Does this train go to __?'
  },
  'compassData.phrase.directions.takeMeTo': {
    AppLang.tr: 'Lütfen __ a kadar',
    AppLang.en: 'Please take me to __'
  },
  'compassData.phrase.directions.showMap': {
    AppLang.tr: 'Haritayı gösterir misiniz?',
    AppLang.en: 'Could you show me on the map?'
  },
  'compassData.phrase.emergency.help': {
    AppLang.tr: 'İmdat!',
    AppLang.en: 'Help!'
  },
  'compassData.phrase.emergency.ambulance': {
    AppLang.tr: 'Ambulans çağırın',
    AppLang.en: 'Please call an ambulance'
  },
  'compassData.phrase.emergency.police': {
    AppLang.tr: 'Polis çağırın',
    AppLang.en: 'Please call the police'
  },
  'compassData.phrase.emergency.feelSick': {
    AppLang.tr: 'Kendimi iyi hissetmiyorum',
    AppLang.en: 'I feel unwell'
  },
  'compassData.phrase.emergency.lostPassport': {
    AppLang.tr: 'Pasaportumu kaybettim',
    AppLang.en: 'I lost my passport'
  },
  'compassData.emergency.police': {AppLang.tr: 'Polis', AppLang.en: 'Police'},
  'compassData.emergency.ambulanceFire': {
    AppLang.tr: 'Ambulans / İtfaiye',
    AppLang.en: 'Ambulance / Fire'
  },
  'compassData.emergency.foreignHelp': {
    AppLang.tr: 'Yabancı danışma (Tokyo)',
    AppLang.en: 'Foreign assistance (Tokyo)'
  },
  'compassData.emergency.trEmbassy': {
    AppLang.tr: 'TR Tokyo Büyükelçiliği',
    AppLang.en: 'Turkish Embassy, Tokyo'
  },
  'compassData.money.title': {
    AppLang.tr: 'Para & Döviz',
    AppLang.en: 'Money & Currency'
  },
  'compassData.money.subtitle': {AppLang.tr: 'JPY', AppLang.en: 'JPY'},
  'compassData.money.line': {
    AppLang.tr:
        '1.000 ¥ ≈ kur değişir · 7-Eleven ATM yabancı kart kabul · Suica/Pasmo IC kart metro + konbini için pratik.',
    AppLang.en:
        '¥1,000 ≈ varies with the rate · 7-Eleven ATMs accept foreign cards · a Suica/Pasmo IC card is handy for the metro + konbini.'
  },
  'compassData.culture.title': {
    AppLang.tr: 'Kültür kuralları',
    AppLang.en: 'Cultural etiquette'
  },
  'compassData.culture.subtitle': {
    AppLang.tr: 'Yerel etiket',
    AppLang.en: 'Local etiquette'
  },
  'compassData.culture.metro.label': {
    AppLang.tr: 'Metro:',
    AppLang.en: 'Metro:'
  },
  'compassData.culture.metro.text': {
    AppLang.tr: 'Sessiz ol, telefonda konuşma; önce inenlere yol ver.',
    AppLang.en:
        'Stay quiet, don\'t talk on the phone; let passengers off first.'
  },
  'compassData.culture.tipping.label': {
    AppLang.tr: 'Bahşiş:',
    AppLang.en: 'Tipping:'
  },
  'compassData.culture.tipping.text': {
    AppLang.tr: 'Verilmez — hakaret sayılabilir.',
    AppLang.en: 'Not expected — it can even be taken as an insult.'
  },
  'compassData.culture.temple.label': {
    AppLang.tr: 'Tapınak:',
    AppLang.en: 'Temple:'
  },
  'compassData.culture.temple.text': {
    AppLang.tr: 'Bazı yerlerde ayakkabı çıkarılır; çekim yasaklarına dikkat.',
    AppLang.en: 'Shoes come off in some places; mind the photography bans.'
  },
  'compassData.culture.trash.label': {AppLang.tr: 'Çöp:', AppLang.en: 'Trash:'},
  'compassData.culture.trash.text': {
    AppLang.tr: 'Sokakta çöp kutusu yok; yanında taşı, otele götür.',
    AppLang.en:
        'No bins on the street; carry it with you and take it back to the hotel.'
  },
  'gps.title': {
    AppLang.tr: 'GPS Simülatörü (test)',
    AppLang.en: 'GPS Simulator (test)'
  },
  'gps.snack.teleport': {
    AppLang.tr: '📍 {emoji} {name} konumuna gidildi (dwell başladı)',
    AppLang.en: '📍 Arrived at {emoji} {name} (dwell started)'
  },
  'gps.snack.autoTourDone': {
    AppLang.tr: '🎲 Otomatik tur tamamlandı',
    AppLang.en: '🎲 Auto tour complete'
  },
  'gps.intro': {
    AppLang.tr:
        'Bu araç sahte konum verisi besler; gerçek GPS gerektirmez. Buradaki keşifler kalıcıdır ve keşif haritasında da görünür.',
    AppLang.en:
        'This tool feeds mock location data — no real GPS required. Discoveries made here are permanent and also appear on the explore map.'
  },
  'gps.simClock': {
    AppLang.tr: '🕒 Simüle saat: {time}',
    AppLang.en: '🕒 Sim clock: {time}'
  },
  'gps.plus1min': {AppLang.tr: '+1 dk', AppLang.en: '+1 min'},
  'gps.plus10min': {AppLang.tr: '+10 dk (bekle)', AppLang.en: '+10 min (wait)'},
  'gps.readout.discoveries': {AppLang.tr: 'Keşif', AppLang.en: 'Discoveries'},
  'gps.readout.badges': {AppLang.tr: 'Rozet', AppLang.en: 'Badges'},
  'gps.autoTour': {
    AppLang.tr: '🎲 Otomatik tur (ilk 6 nokta)',
    AppLang.en: '🎲 Auto tour (first 6 spots)'
  },
  'gps.emptyFences': {
    AppLang.tr:
        'Bu rotada küratörlü nokta yok. Planlayıcıda Tokyo, Kyoto, Osaka gibi şehirler ekle.',
    AppLang.en:
        'No curated spots on this route. Add cities like Tokyo, Kyoto or Osaka in the planner.'
  },
  'gps.fence.discovered': {
    AppLang.tr: 'keşfedildi ✓',
    AppLang.en: 'discovered ✓'
  },
  'gps.fence.goHere': {AppLang.tr: '📍 Buraya git', AppLang.en: '📍 Go here'},
  'gps.fence.dwell': {
    AppLang.tr: '⏱️ 10 dk kal & onayla',
    AppLang.en: '⏱️ Stay 10 min & confirm'
  },
  'gps.fence.activeProgress': {
    AppLang.tr: '⏱️ {mins}/10 dk',
    AppLang.en: '⏱️ {mins}/10 min'
  },
  'gps.currentZone.none': {
    AppLang.tr: '📍 Şu an bir noktada değilsin',
    AppLang.en: '📍 You are not inside a spot right now'
  },
  'gps.currentZone.active': {
    AppLang.tr: '📍 Şu an: {emoji} {name} · {city} · {mins} dk',
    AppLang.en: '📍 Current: {emoji} {name} · {city} · {mins} min'
  },
  'map.dayTitle': {AppLang.tr: '🗺️ Gün {day}', AppLang.en: '🗺️ Day {day}'},
  'map.osmAttribution': {
    AppLang.tr: '© OpenStreetMap katkıda bulunanlar',
    AppLang.en: '© OpenStreetMap contributors'
  },
  'map.emptyBanner': {
    AppLang.tr: 'Bu güne haritada gösterilecek konumlu durak yok.',
    AppLang.en: 'No located stops to show on the map for this day.'
  },
  'viewer.metrics.steps': {AppLang.tr: 'adım', AppLang.en: 'steps'},
  'viewer.metrics.distance': {AppLang.tr: 'mesafe', AppLang.en: 'distance'},
  'viewer.metrics.calories': {AppLang.tr: 'kcal', AppLang.en: 'kcal'},
  'viewer.metrics.caloriesLabel': {
    AppLang.tr: 'kalori',
    AppLang.en: 'calories'
  },
  'viewer.metrics.duration': {AppLang.tr: 'süre', AppLang.en: 'duration'},
  'viewer.metrics.stops': {AppLang.tr: 'durak', AppLang.en: 'stops'},
  'viewer.metrics.progress': {AppLang.tr: 'ilerleme', AppLang.en: 'progress'},
  'viewer.metrics.remaining': {AppLang.tr: 'kalan', AppLang.en: 'remaining'},
  'viewer.metrics.reservations': {
    AppLang.tr: 'rezervasyon',
    AppLang.en: 'bookings'
  },
  'viewer.metrics.live': {AppLang.tr: 'CİHAZ', AppLang.en: 'LIVE'},
  'viewer.template.routePanorama': {
    AppLang.tr: 'Rota Panoraması',
    AppLang.en: 'Route panorama'
  },
  'viewer.template.routePanorama.description': {
    AppLang.tr: 'Adım, kalori ve mesafeyle günün panosu',
    AppLang.en: 'Steps, calories and distance dashboard'
  },
  'viewer.template.premium.title': {
    AppLang.tr: 'Rotori Pro tasarımı',
    AppLang.en: 'A Rotori Pro design'
  },
  'viewer.template.premium.body': {
    AppLang.tr:
        'Yolculuk ve Harita tasarımları Rotori Pro ile açılır. Premium’a geçince istediğin görünümü kullanabilirsin.',
    AppLang.en:
        'Journey and Map designs unlock with Rotori Pro. Upgrade to use the view that fits your trip.'
  },
  'viewer.template.premium.journey': {
    AppLang.tr: 'İlerlemeyi ve sıradaki adımı öne çıkarır',
    AppLang.en: 'Brings progress and the next step forward'
  },
  'viewer.template.premium.map': {
    AppLang.tr: 'Günün rotasını ve duraklarını haritada gösterir',
    AppLang.en: 'Shows the day route and stops on a map'
  },
  'viewer.template.premium.close': {
    AppLang.tr: 'Anladım',
    AppLang.en: 'Got it'
  },
  'viewer.report.title': {
    AppLang.tr: 'Gezi tamamlandı! 🎉',
    AppLang.en: 'Trip complete! 🎉'
  },
  'viewer.report.days': {AppLang.tr: 'gün', AppLang.en: 'days'},
  'viewer.report.places': {AppLang.tr: 'mekan', AppLang.en: 'places'},
  'viewer.report.meals': {AppLang.tr: 'öğün', AppLang.en: 'meals'},
  'viewer.report.cities': {AppLang.tr: 'şehir', AppLang.en: 'cities'},
  'viewer.report.showDays': {
    AppLang.tr: 'Günleri gör',
    AppLang.en: 'Show days'
  },
  'viewer.report.hideDays': {
    AppLang.tr: 'Günleri gizle',
    AppLang.en: 'Hide days'
  },
  'viewer.report.cta': {
    AppLang.tr: 'Gezi tamamlandı — Raporu gör',
    AppLang.en: 'Trip complete — View report'
  },
  'map.openInGoogleMaps': {
    AppLang.tr: 'Google Maps\'te aç',
    AppLang.en: 'Open in Google Maps'
  },
  'map.openFailed': {
    AppLang.tr: 'Harita açılamadı — URL panoya kopyalandı',
    AppLang.en: 'Couldn\'t open the map — URL copied to clipboard'
  },
  'map.truncatedWaypoints': {
    AppLang.tr: 'Google Maps sınırı: sadece ilk 9 durak yönlendirmeye eklendi.',
    AppLang.en: 'Google Maps limit: only the first 9 stops added to the route.'
  },
  'map.openTripInGoogleMaps': {
    AppLang.tr: 'Tüm rotayı Google Maps\'te aç',
    AppLang.en: 'Open the full trip in Google Maps'
  },
  'map.stopsCount': {AppLang.tr: '{count} durak', AppLang.en: '{count} stops'},
  'map.zoomIn': {AppLang.tr: 'Yakınlaştır', AppLang.en: 'Zoom in'},
  'map.zoomOut': {AppLang.tr: 'Uzaklaştır', AppLang.en: 'Zoom out'},
  'map.replay': {AppLang.tr: 'Tekrar oynat', AppLang.en: 'Replay'},
  'map.fitRoute': {AppLang.tr: 'Rotaya sığdır', AppLang.en: 'Fit route'},
  'map.navigate': {AppLang.tr: 'Yol tarifi', AppLang.en: 'Navigate'},
  'map.minimalAttribution': {
    AppLang.tr: '© OpenStreetMap katkıda bulunanlar',
    AppLang.en: '© OpenStreetMap contributors'
  },
  'routeOptimization.action': {
    AppLang.tr: 'Rotayı optimize et',
    AppLang.en: 'Optimize route'
  },
  'routeOptimization.title': {
    AppLang.tr: 'Akıllı rota',
    AppLang.en: 'Smart route'
  },
  'routeOptimization.subtitle': {
    AppLang.tr:
        'Sabit saatler korunur. Değişiklikler yalnızca onayladığında kaydedilir.',
    AppLang.en:
        'Fixed times stay protected. Changes are saved only after approval.'
  },
  'routeOptimization.recommended': {
    AppLang.tr: 'Önerilen rota',
    AppLang.en: 'Recommended route',
  },
  'routeOptimization.loading': {
    AppLang.tr: 'En uygun günlük rota hesaplanıyor…',
    AppLang.en: 'Calculating the best daily route…'
  },
  'routeOptimization.before': {AppLang.tr: 'Önce', AppLang.en: 'Before'},
  'routeOptimization.after': {AppLang.tr: 'Sonra', AppLang.en: 'After'},
  'routeOptimization.travel': {AppLang.tr: 'Ulaşım', AppLang.en: 'Travel'},
  'routeOptimization.walking': {AppLang.tr: 'Yürüyüş', AppLang.en: 'Walking'},
  'routeOptimization.transfers': {
    AppLang.tr: 'Aktarma',
    AppLang.en: 'Transfers'
  },
  'routeOptimization.cost': {AppLang.tr: 'Maliyet', AppLang.en: 'Cost'},
  'routeOptimization.minute': {AppLang.tr: 'dk', AppLang.en: 'min'},
  'routeOptimization.changes': {
    AppLang.tr: 'Yapılacak değişiklikler',
    AppLang.en: 'Proposed changes'
  },
  'routeOptimization.legs.title': {
    AppLang.tr: 'Nasıl gidilecek?',
    AppLang.en: 'How will you get there?'
  },
  'routeOptimization.legs.subtitle': {
    AppLang.tr:
        'Çıkış saati, ulaşım türü ve yol ayrıntılarını uygulamadan önce kontrol et.',
    AppLang.en:
        'Review departure times, transport modes, and journey details before applying.'
  },
  'routeOptimization.legs.departure': {
    AppLang.tr: 'Güne başlangıç',
    AppLang.en: 'Start the day'
  },
  'routeOptimization.legs.betweenStops': {
    AppLang.tr: 'Sonraki durağa geçiş',
    AppLang.en: 'Continue to the next stop'
  },
  'routeOptimization.legs.returnToBase': {
    AppLang.tr: 'Konaklamaya dönüş',
    AppLang.en: 'Return to your stay'
  },
  'routeOptimization.legs.estimated': {
    AppLang.tr: 'TAHMİNİ',
    AppLang.en: 'ESTIMATED'
  },
  'routeOptimization.legs.estimatedHelp': {
    AppLang.tr:
        'Bu süre koordinatlara dayalı tahmindir. Kesin hat ve peronu çıkıştan önce haritada doğrula.',
    AppLang.en:
        'This duration is coordinate-based. Confirm the exact line and platform in maps before departure.'
  },
  'routeOptimization.legs.line': {
    AppLang.tr: 'Hat: {line}',
    AppLang.en: 'Line: {line}'
  },
  'routeOptimization.legs.direction': {
    AppLang.tr: 'Yön: {direction}',
    AppLang.en: 'Direction: {direction}'
  },
  'routeOptimization.legs.walk': {
    AppLang.tr: '{minutes} dk yürü',
    AppLang.en: 'Walk {minutes} min'
  },
  'routeOptimization.legs.wait': {
    AppLang.tr: '{minutes} dk bekle',
    AppLang.en: 'Wait {minutes} min'
  },
  'routeOptimization.legs.transfer': {
    AppLang.tr: '{count} aktarma',
    AppLang.en: '{count} transfer'
  },
  'routeOptimization.legs.semantics': {
    AppLang.tr: '{from} noktasından {to} noktasına, {mode}, {minutes} dakika',
    AppLang.en: '{from} to {to}, {mode}, {minutes} minutes'
  },
  'routeOptimization.mode.walking': {
    AppLang.tr: 'Yürüyerek',
    AppLang.en: 'Walk'
  },
  'routeOptimization.mode.train': {AppLang.tr: 'Tren', AppLang.en: 'Train'},
  'routeOptimization.mode.metro': {AppLang.tr: 'Metro', AppLang.en: 'Metro'},
  'routeOptimization.mode.bus': {AppLang.tr: 'Otobüs', AppLang.en: 'Bus'},
  'routeOptimization.mode.taxi': {AppLang.tr: 'Taksi', AppLang.en: 'Taxi'},
  'routeOptimization.mode.shinkansen': {
    AppLang.tr: 'Shinkansen',
    AppLang.en: 'Shinkansen'
  },
  'routeOptimization.mode.regionalTrain': {
    AppLang.tr: 'Bölgesel tren',
    AppLang.en: 'Regional train'
  },
  'routeOptimization.apply': {
    AppLang.tr: 'Rotayı uygula',
    AppLang.en: 'Apply route'
  },
  'routeOptimization.cancel': {AppLang.tr: 'Vazgeç', AppLang.en: 'Cancel'},
  // Kazanç yoksa "Uygula" hiç sunulmaz: uygulanacak bir şey yok.
  'routeOptimization.noGain.title': {
    AppLang.tr: 'Bu gün zaten en iyi sırada',
    AppLang.en: 'This day is already in the best order',
  },
  'routeOptimization.noGain.body': {
    AppLang.tr:
        'Durakları yeniden dizmeyi denedim; ulaşım süresi, yürüyüş, aktarma ve maliyetin hiçbirinde kazanç çıkmadı. Değiştirecek bir şey yok.',
    AppLang.en:
        'I tried reordering the stops; there was no gain in travel time, walking, transfers or cost. Nothing to change.',
  },
  'routeOptimization.retry': {
    AppLang.tr: 'Tekrar dene',
    AppLang.en: 'Try again'
  },
  'routeOptimization.weatherAction': {
    AppLang.tr: 'Havaya göre düzenle',
    AppLang.en: 'Adjust for weather',
  },
  'routeOptimization.weather.clear': {
    AppLang.tr: 'Hava uygun: dengeli profil seçildi.',
    AppLang.en: 'Weather is favorable: balanced profile selected.',
  },
  'routeOptimization.weather.rain': {
    AppLang.tr:
        'Yağış bekleniyor: kapalı mekânlar öne, açık hava durakları sona alındı.',
    AppLang.en:
        'Rain expected: indoor stops moved earlier and outdoor stops later.',
  },
  'routeOptimization.weather.storm': {
    AppLang.tr:
        'Sert hava koşulu: kapalı mekânlar öne alındı ve yürüyüş azaltıldı.',
    AppLang.en:
        'Severe weather: indoor stops moved earlier and walking reduced.',
  },
  'routeOptimization.weather.extremeTemp': {
    AppLang.tr: 'Sıcaklık sert: yürüyüş limiti düşürüldü.',
    AppLang.en: 'Extreme temperature: walking limit reduced.',
  },
  'routeOptimization.unavailable': {
    AppLang.tr:
        'Güvenilir rota verisine şu anda ulaşılamıyor. Planın değiştirilmedi.',
    AppLang.en:
        'Reliable route data is unavailable right now. Your plan was not changed.'
  },
  'routeOptimization.noFeasible': {
    AppLang.tr:
        'Bu gün çok sıkışık görünüyor; tüm durakları bu zaman penceresine güvenli biçimde sığdıramadım.',
    AppLang.en:
        'This day looks too dense; I could not safely fit all stops into this time window.',
  },
  'routeOptimization.fixedConflict': {
    AppLang.tr:
        'Sabit saatli aktiviteler çakışıyor. Sabit saatleri biraz esnetip tekrar deneyin.',
    AppLang.en:
        'Fixed-time activities conflict. Loosen fixed times a bit and try again.',
  },
  'routeOptimization.routeDataMissing': {
    AppLang.tr:
        'Duraklar arasında rota bağlantısı eksik görünüyor. Farklı bir profil seçip tekrar deneyin.',
    AppLang.en:
        'Route connectivity between stops appears incomplete. Try another profile and retry.',
  },
  'routeOptimization.dataIssue': {
    AppLang.tr:
        'Plan verisinde tutarsızlık tespit edildi. Planı düzenleyip tekrar deneyin.',
    AppLang.en:
        'An inconsistency was detected in plan data. Edit the plan and try again.',
  },
  'routeOptimization.needTwoStops': {
    AppLang.tr: 'Optimizasyon için en az iki durak gerekli.',
    AppLang.en: 'At least two stops are required for optimization.'
  },
  'routeOptimization.missingLocation': {
    AppLang.tr:
        'Bu gün için güvenilir konum bilgisi eksik. Planın değiştirilmedi.',
    AppLang.en:
        'Reliable location data is missing for this day. Your plan was not changed.'
  },
  'routeOptimization.stopLocationMissing': {
    AppLang.tr: '{name} için konum bulunamadı. Planın değiştirilmedi.',
    AppLang.en: 'Location was not found for {name}. Your plan was not changed.'
  },
  'routeOptimization.dayBase': {
    AppLang.tr: 'Gün başlangıcı',
    AppLang.en: 'Day base'
  },
  'routeOptimization.profile.balanced': {
    AppLang.tr: 'Dengeli',
    AppLang.en: 'Balanced'
  },
  'routeOptimization.profile.fastest': {
    AppLang.tr: 'En hızlı',
    AppLang.en: 'Fastest'
  },
  'routeOptimization.profile.leastWalking': {
    AppLang.tr: 'Az yürüyüş',
    AppLang.en: 'Less walking'
  },
  'routeOptimization.profile.cheapest': {
    AppLang.tr: 'En ucuz',
    AppLang.en: 'Cheapest'
  },
  'routeOptimization.premium.title': {
    AppLang.tr: 'Rotori Pro özelliği',
    AppLang.en: 'A Rotori Pro feature'
  },
  'routeOptimization.premium.body': {
    AppLang.tr: 'Rota optimizasyonu premium üyeler için sunulacak. '
        'Şimdilik rotanı "Haritada gör" butonuyla Google Maps üzerinden takip edebilirsin.',
    AppLang.en: 'Route optimization will be available for premium members. '
        'For now, you can follow your route on Google Maps using the "View on map" button.'
  },
  'routeOptimization.premium.benefitOrder': {
    AppLang.tr: 'Günlük rotanı en uygun sıraya getirir',
    AppLang.en: 'Puts your daily route in the most suitable order'
  },
  'routeOptimization.premium.benefitCompare': {
    AppLang.tr: 'Yürüyüş, süre, aktarma ve maliyeti karşılaştırır',
    AppLang.en: 'Compares walking, time, transfers, and cost'
  },
  'routeOptimization.premium.benefitPreview': {
    AppLang.tr: 'Değişikliği uygulamadan önce gösterir',
    AppLang.en: 'Shows the change before you apply it'
  },
  'scanner.premium.title': {
    AppLang.tr: 'Rotori Pro özelliği',
    AppLang.en: 'A Rotori Pro feature'
  },
  'scanner.premium.body': {
    AppLang.tr:
        'Fiyat etiketlerini daha sık tara, ürünü tanı ve Türkiye fiyatlarıyla tek yerde karşılaştır.',
    AppLang.en:
        'Scan more price tags, identify products, and compare them with prices in Türkiye in one place.'
  },
  'scanner.premium.benefitScans': {
    AppLang.tr: 'Günde 100 fiyat etiketi tarar',
    AppLang.en: 'Scans 100 price tags per day'
  },
  'scanner.premium.benefitDetection': {
    AppLang.tr: 'Ürünü akıllı model tespitiyle tanır',
    AppLang.en: 'Identifies the product with smart model detection'
  },
  'scanner.premium.benefitCompare': {
    AppLang.tr: 'Türkiye mağazalarındaki fiyatlarla karşılaştırır',
    AppLang.en: 'Compares prices across stores in Türkiye'
  },
  'home.appTitle': {
    AppLang.tr: 'Rotori Önizleme',
    AppLang.en: 'Rotori Preview'
  },
  'home.appBar': {
    AppLang.tr: 'Rotori · Önizleme',
    AppLang.en: 'Rotori · Preview'
  },
  'home.planLoadFailed': {
    AppLang.tr: 'Plan yüklenemedi: {err}',
    AppLang.en: 'Failed to load plan: {err}'
  },
  'home.demoLoaded': {
    AppLang.tr: '🇯🇵 Demo veri yüklendi',
    AppLang.en: '🇯🇵 Demo data loaded'
  },
  'home.demoSub': {
    AppLang.tr:
        'Tokyo + Kyoto rotalı, dolu günlü örnek plan. Supabase/login yok — sadece görsel kontrol.',
    AppLang.en:
        'A full sample itinerary along a Tokyo + Kyoto route. No Supabase or login — just a visual preview.'
  },
  'home.card.new.title': {
    AppLang.tr: 'Sıfırdan yeni plan',
    AppLang.en: 'New plan from scratch'
  },
  'home.card.new.sub': {
    AppLang.tr: 'Boş bir gezi ile Welcome adımından başla',
    AppLang.en: 'Start from the Welcome step with an empty trip'
  },
  'home.card.planner.title': {
    AppLang.tr: 'Planlayıcı (demo)',
    AppLang.en: 'Planner (demo)'
  },
  'home.card.planner.sub': {
    AppLang.tr: 'Dolu Tokyo+Kyoto demo planında adımları gez',
    AppLang.en: 'Walk the steps in the full Tokyo+Kyoto demo plan'
  },
  'home.card.viewer.title': {
    AppLang.tr: 'Rehber (Viewer)',
    AppLang.en: 'Guide (Viewer)'
  },
  'home.card.viewer.sub': {
    AppLang.tr: 'Geri sayım, günlük plan, keşif haritası girişi',
    AppLang.en: 'Countdown, daily plan, explore-map entry'
  },
  'packing.cat.documents': {AppLang.tr: 'Belgeler', AppLang.en: 'Documents'},
  'packing.cat.connectivity': {
    AppLang.tr: 'Bağlantı',
    AppLang.en: 'Connectivity'
  },
  'packing.cat.payment': {AppLang.tr: 'Ödeme', AppLang.en: 'Payment'},
  'packing.cat.electronics': {
    AppLang.tr: 'Elektronik',
    AppLang.en: 'Electronics'
  },
  'packing.cat.health': {AppLang.tr: 'Sağlık', AppLang.en: 'Health'},
  'packing.cat.clothing': {AppLang.tr: 'Giyim', AppLang.en: 'Clothing'},
  'packing.cat.taxRefund': {
    AppLang.tr: 'Vergi iadesi & alışveriş',
    AppLang.en: 'Tax refund & shopping'
  },
  'packing.cat.culture': {
    AppLang.tr: 'Kültür / pratik',
    AppLang.en: 'Culture / practical'
  },
  'packing.cat.other': {AppLang.tr: 'Diğer', AppLang.en: 'Other'},
  'packing.doc-passport.label': {
    AppLang.tr: 'Pasaport',
    AppLang.en: 'Passport'
  },
  'packing.doc-passport.note': {
    AppLang.tr: 'Son kullanma tarihi dönüşten en az 6 ay sonra olmalı',
    AppLang.en: 'Must stay valid for at least 6 months after your return'
  },
  'packing.doc-visa.label': {
    AppLang.tr: '(Varsa) vize',
    AppLang.en: 'Visa (if required)'
  },
  'packing.doc-visa.note': {
    AppLang.tr: 'Vize gerekiyorsa yanına al veya e-vize çıktısını sakla',
    AppLang.en: 'If you need a visa, bring it or keep a printout of your e-visa'
  },
  'packing.doc-jrpass.label': {
    AppLang.tr: 'JR Pass voucher / QR',
    AppLang.en: 'JR Pass voucher / QR'
  },
  'packing.doc-jrpass.note': {
    AppLang.tr: 'Aktivasyon için voucher veya dijital QR gerekir',
    AppLang.en: 'A voucher or digital QR is required for activation'
  },
  'packing.doc-hotel.label': {
    AppLang.tr: 'Otel rezervasyon çıktısı',
    AppLang.en: 'Hotel reservation printout'
  },
  'packing.doc-hotel.note': {
    AppLang.tr: 'Girişte istenebilir; çevrimdışı erişim için çıktı al',
    AppLang.en: 'May be asked for at check-in; print it for offline access'
  },
  'packing.doc-flight.label': {
    AppLang.tr: 'Uçuş bileti / biniş kartı',
    AppLang.en: 'Flight ticket / boarding pass'
  },
  'packing.doc-insurance.label': {
    AppLang.tr: 'Seyahat sigortası poliçesi',
    AppLang.en: 'Travel insurance policy'
  },
  'packing.net-wifi-esim.label': {
    AppLang.tr: 'Cep wifi veya eSIM',
    AppLang.en: 'Pocket Wi-Fi or eSIM'
  },
  'packing.net-wifi-esim.note': {
    AppLang.tr: 'Japonya\'da ücretsiz wifi az — internetini garantiye al',
    AppLang.en:
        'Free Wi-Fi is scarce in Japan — lock in your connection ahead of time'
  },
  'packing.net-ic-card.label': {
    AppLang.tr: 'IC kart (Suica / Pasmo)',
    AppLang.en: 'IC card (Suica / Pasmo)'
  },
  'packing.net-ic-card.note': {
    AppLang.tr: 'Metro + konbini ödemesi için pratik',
    AppLang.en: 'Handy for metro rides and konbini payments'
  },
  'packing.pay-cash-yen.label': {
    AppLang.tr: 'Bir miktar nakit yen',
    AppLang.en: 'Some cash in yen'
  },
  'packing.pay-cash-yen.note': {
    AppLang.tr: 'Küçük dükkanlar ve tapınaklar kart almaz',
    AppLang.en: 'Small shops and temples don\'t take cards'
  },
  'packing.pay-credit-card.label': {
    AppLang.tr: 'Kredi kartı (temassız)',
    AppLang.en: 'Credit card (contactless)'
  },
  'packing.pay-bank-notice.label': {
    AppLang.tr: 'Bankaya yurtdışı / kart kullanım bildirimi',
    AppLang.en: 'Notify your bank of overseas card use'
  },
  'packing.pay-bank-notice.note': {
    AppLang.tr: 'Kartın yurtdışında bloke olmasın',
    AppLang.en: 'So your card isn\'t blocked abroad'
  },
  'packing.elec-adapter.label': {
    AppLang.tr: 'Priz adaptörü',
    AppLang.en: 'Plug adapter'
  },
  'packing.elec-adapter.note': {
    AppLang.tr: 'Japonya A tipi priz, 100V',
    AppLang.en: 'Japan uses Type A outlets, 100V'
  },
  'packing.elec-powerbank.label': {
    AppLang.tr: 'Powerbank',
    AppLang.en: 'Power bank'
  },
  'packing.elec-powerbank.note': {
    AppLang.tr: 'Uzun yürüyüş günlerinde telefon şarjı için',
    AppLang.en: 'For charging your phone on long walking days'
  },
  'packing.elec-cables.label': {
    AppLang.tr: 'Şarj kabloları',
    AppLang.en: 'Charging cables'
  },
  'packing.elec-headphones.label': {
    AppLang.tr: 'Kulaklık',
    AppLang.en: 'Headphones'
  },
  'packing.health-meds.label': {
    AppLang.tr: 'Kişisel ilaçlar + reçete',
    AppLang.en: 'Personal medication + prescription'
  },
  'packing.health-meds.note': {
    AppLang.tr: 'Bazı ilaçlar Japonya\'da yasak — önceden kontrol et',
    AppLang.en: 'Some medicines are banned in Japan — check beforehand'
  },
  'packing.health-mask.label': {AppLang.tr: 'Maske', AppLang.en: 'Face mask'},
  'packing.health-mask.note': {
    AppLang.tr: 'Kalabalık metro ve hastalıkta yaygın kullanılır',
    AppLang.en: 'Widely worn on crowded trains and when you\'re unwell'
  },
  'packing.health-firstaid.label': {
    AppLang.tr: 'Küçük ilk yardım seti',
    AppLang.en: 'Small first-aid kit'
  },
  'packing.cloth-layers.label': {
    AppLang.tr: 'Mevsime uygun katmanlı giysi',
    AppLang.en: 'Season-appropriate layered clothing'
  },
  'packing.cloth-shoes.label': {
    AppLang.tr: 'Rahat yürüyüş ayakkabısı',
    AppLang.en: 'Comfortable walking shoes'
  },
  'packing.cloth-shoes.note': {
    AppLang.tr: 'Günde 15–20 bin adım yürüyeceksin',
    AppLang.en: 'You\'ll walk 15,000–20,000 steps a day'
  },
  'packing.cloth-rain.label': {
    AppLang.tr: 'Yağmurluk / katlanır şemsiye',
    AppLang.en: 'Raincoat / folding umbrella'
  },
  'packing.tax-passport.label': {
    AppLang.tr: 'Pasaport (tax-free için)',
    AppLang.en: 'Passport (for tax-free)'
  },
  'packing.tax-passport.note': {
    AppLang.tr: 'Vergisiz alışverişte pasaport gösterilir',
    AppLang.en: 'Your passport is shown for tax-free purchases'
  },
  'packing.tax-foldable-bag.label': {
    AppLang.tr: 'Katlanır çanta',
    AppLang.en: 'Foldable bag'
  },
  'packing.tax-foldable-bag.note': {
    AppLang.tr: 'Alışverişler için ekstra taşıma alanı',
    AppLang.en: 'Extra carrying space for your shopping'
  },
  'packing.tax-keep-receipts.label': {
    AppLang.tr: 'Fiş / makbuz saklama',
    AppLang.en: 'Keep your receipts'
  },
  'packing.tax-keep-receipts.note': {
    AppLang.tr:
        'Tax-free fişleri pasaporta iliştirilir, çıkışta kontrol edilir',
    AppLang.en:
        'Tax-free receipts are attached to your passport and checked on departure'
  },
  'packing.culture-towel.label': {
    AppLang.tr: 'Küçük havlu / mendil',
    AppLang.en: 'Small towel / handkerchief'
  },
  'packing.culture-towel.note': {
    AppLang.tr: 'Umumi tuvaletlerde kağıt havlu yok',
    AppLang.en: 'Public restrooms often have no paper towels'
  },
  'packing.culture-trash-bag.label': {
    AppLang.tr: 'Çöp için poşet',
    AppLang.en: 'Bag for your trash'
  },
  'packing.culture-trash-bag.note': {
    AppLang.tr: 'Sokakta çöp kutusu az — çöpünü yanında taşı',
    AppLang.en: 'Street bins are rare — carry your trash with you'
  },
  'packing.culture-coin-wallet.label': {
    AppLang.tr: 'Bozuk para için küçük cüzdan',
    AppLang.en: 'Small coin purse'
  },
  'packing.culture-coin-wallet.note': {
    AppLang.tr: 'Nakit ağırlıklı — çok madeni para birikir',
    AppLang.en: 'It\'s a cash-heavy country — coins pile up fast'
  },
  'reminders.title': {AppLang.tr: 'Hatırlatmalar', AppLang.en: 'Reminders'},
  'reminders.add': {AppLang.tr: 'Hatırlatıcı ekle', AppLang.en: 'Add reminder'},
  'reminders.other': {
    AppLang.tr: 'Diğer hatırlatıcılar',
    AppLang.en: 'Other reminders',
  },
  'reminders.remove': {
    AppLang.tr: '{name} hatırlatıcısını sil',
    AppLang.en: 'Delete reminder for {name}',
  },
  'reminders.status.today': {AppLang.tr: 'Bugün', AppLang.en: 'Today'},
  'reminders.status.upcoming': {
    AppLang.tr: 'Yaklaşıyor',
    AppLang.en: 'Upcoming',
  },
  'reminders.status.passed': {AppLang.tr: 'Geçti', AppLang.en: 'Passed'},
  'reminders.summary.count.singular': {
    AppLang.tr: '{count} hatırlatıcı',
    AppLang.en: '{count} reminder',
  },
  'reminders.summary.count.plural': {
    AppLang.tr: '{count} hatırlatıcı',
    AppLang.en: '{count} reminders',
  },
  'reminders.summary.next.today': {
    AppLang.tr: 'sıradaki bugün',
    AppLang.en: 'next today',
  },
  'reminders.summary.next.tomorrow': {
    AppLang.tr: 'sıradaki yarın',
    AppLang.en: 'next tomorrow',
  },
  'reminders.summary.next.days': {
    AppLang.tr: 'sıradaki {count} gün sonra',
    AppLang.en: 'next in {count} days',
  },
  'reminders.summary.next.none': {
    AppLang.tr: 'hepsi geçmiş',
    AppLang.en: 'all passed',
  },
  'reminders.summary.separator': {AppLang.tr: ' · ', AppLang.en: ' · '},
  'reminders.premiumBadge': {AppLang.tr: 'PRO', AppLang.en: 'PRO'},
  'reminders.premiumTitle': {
    AppLang.tr: 'Rotori Pro özelliği',
    AppLang.en: 'A Rotori Pro feature'
  },
  'reminders.premiumBody': {
    AppLang.tr:
        'Biletlerin satışa çıktığı anı kaçırmamak için hazır veya özel hatırlatıcıları Rotori Pro ile oluşturabilirsin.',
    AppLang.en:
        'Create ready-made or custom reminders with Rotori Pro so you do not miss the moment tickets go on sale.'
  },
  'reminders.premiumBenefitDates': {
    AppLang.tr: 'Satış tarihini ziyaret gününden otomatik hesaplar',
    AppLang.en: 'Calculates the sale date from your visit date'
  },
  'reminders.premiumBenefitMultiple': {
    AppLang.tr: 'Birden fazla bilet için tek seferde planlama yapar',
    AppLang.en: 'Plans several ticket alerts at once'
  },
  'reminders.premiumBenefitCustom': {
    AppLang.tr: 'Özel tarih ve saatli hatırlatıcı ekler',
    AppLang.en: 'Adds reminders with a custom date and time'
  },
  'reminders.premiumClose': {AppLang.tr: 'Anladım', AppLang.en: 'Got it'},
  'reminders.premiumCta': {
    AppLang.tr: 'Rotori Pro ile aç',
    AppLang.en: 'Unlock with Rotori Pro'
  },
  'reminders.clearAll': {AppLang.tr: 'Tümünü temizle', AppLang.en: 'Clear all'},
  'reminders.clearAllTitle': {
    AppLang.tr: 'Tümünü sil',
    AppLang.en: 'Delete all'
  },
  'reminders.clearAllBody': {
    AppLang.tr:
        'Tüm hatırlatmalar silinsin mi? Bildirim planlamaları da iptal edilir.',
    AppLang.en:
        'Delete all reminders? Their scheduled notifications will be cancelled too.'
  },
  'reminders.cancel': {AppLang.tr: 'Vazgeç', AppLang.en: 'Cancel'},
  'reminders.delete': {AppLang.tr: 'Sil', AppLang.en: 'Delete'},
  'reminders.passed': {
    AppLang.tr: 'Bugün / geçti',
    AppLang.en: 'Today / passed'
  },
  'reminders.inDays': {AppLang.tr: '{n} gün sonra', AppLang.en: 'in {n} days'},
  'reminders.inHours': {
    AppLang.tr: '{n} saat sonra',
    AppLang.en: 'in {n} hours'
  },
  'reminders.emptyTitle': {
    AppLang.tr: 'Henüz hatırlatma yok',
    AppLang.en: 'No reminders yet'
  },
  'reminders.emptyBody': {
    AppLang.tr:
        'Shinkansen, Disney, USJ ve teamLab için hazır seçimlerden yararlanabilir veya kendi tarihini ekleyebilirsin.',
    AppLang.en:
        'Use ready-made choices for Shinkansen, Disney, USJ and teamLab, or add your own date.'
  },
  'reminders.mon.1': {AppLang.tr: 'Oca', AppLang.en: 'Jan'},
  'reminders.mon.2': {AppLang.tr: 'Şub', AppLang.en: 'Feb'},
  'reminders.mon.3': {AppLang.tr: 'Mar', AppLang.en: 'Mar'},
  'reminders.mon.4': {AppLang.tr: 'Nis', AppLang.en: 'Apr'},
  'reminders.mon.5': {AppLang.tr: 'May', AppLang.en: 'May'},
  'reminders.mon.6': {AppLang.tr: 'Haz', AppLang.en: 'Jun'},
  'reminders.mon.7': {AppLang.tr: 'Tem', AppLang.en: 'Jul'},
  'reminders.mon.8': {AppLang.tr: 'Ağu', AppLang.en: 'Aug'},
  'reminders.mon.9': {AppLang.tr: 'Eyl', AppLang.en: 'Sep'},
  'reminders.mon.10': {AppLang.tr: 'Eki', AppLang.en: 'Oct'},
  'reminders.mon.11': {AppLang.tr: 'Kas', AppLang.en: 'Nov'},
  'reminders.mon.12': {AppLang.tr: 'Ara', AppLang.en: 'Dec'},
  'auth.createAccount': {
    AppLang.tr: 'Hesap oluştur',
    AppLang.en: 'Create account'
  },
  'auth.signIn': {AppLang.tr: 'Giriş yap', AppLang.en: 'Sign in'},
  'auth.email': {AppLang.tr: 'E-posta', AppLang.en: 'Email'},
  'auth.emailInvalid': {
    AppLang.tr: 'Geçerli bir e-posta gir',
    AppLang.en: 'Enter a valid email'
  },
  'auth.password': {AppLang.tr: 'Şifre', AppLang.en: 'Password'},
  'auth.passwordTooShort': {
    AppLang.tr: 'En az 6 karakter',
    AppLang.en: 'At least 6 characters'
  },
  'auth.register': {AppLang.tr: 'Kayıt ol', AppLang.en: 'Sign up'},
  'auth.haveAccount': {
    AppLang.tr: 'Zaten hesabın var mı? Giriş yap',
    AppLang.en: 'Already have an account? Sign in'
  },
  'auth.noAccount': {
    AppLang.tr: 'Hesabın yok mu? Kayıt ol',
    AppLang.en: 'Don\'t have an account? Sign up'
  },
  'auth.or': {AppLang.tr: 'veya', AppLang.en: 'or'},
  'auth.signInWithApple': {
    AppLang.tr: 'Apple ile Giriş Yap',
    AppLang.en: 'Sign in with Apple'
  },
  'auth.signInWithGoogle': {
    AppLang.tr: 'Google ile Giriş Yap',
    AppLang.en: 'Sign in with Google'
  },
  'auth.tagline': {
    AppLang.tr: 'Sürpriz yok, plan var.',
    AppLang.en: 'No surprises. Just the plan.',
  },
  'auth.error.invalidCredentials': {
    AppLang.tr:
        'E-posta veya şifre hatalı. Bilgilerini kontrol edip tekrar dene.',
    AppLang.en:
        'The email or password is incorrect. Check your details and try again.',
  },
  'auth.error.emailNotConfirmed': {
    AppLang.tr: 'E-posta adresini doğrulamak için gelen kutunu kontrol et.',
    AppLang.en: 'Check your inbox to confirm your email address.',
  },
  'auth.error.userExists': {
    AppLang.tr: 'Bu e-posta ile zaten bir hesap var. Giriş yapmayı dene.',
    AppLang.en: 'An account already exists for this email. Try signing in.',
  },
  'auth.error.weakPassword': {
    AppLang.tr: 'Daha güçlü bir şifre seç. En az 6 karakter kullan.',
    AppLang.en: 'Choose a stronger password with at least 6 characters.',
  },
  'auth.error.rateLimit': {
    AppLang.tr: 'Çok fazla deneme yapıldı. Birkaç dakika sonra tekrar dene.',
    AppLang.en: 'Too many attempts. Please try again in a few minutes.',
  },
  'auth.error.network': {
    AppLang.tr: 'Bağlantı kurulamadı. İnternetini kontrol edip tekrar dene.',
    AppLang.en: 'Could not connect. Check your internet and try again.',
  },
  'auth.error.generic': {
    AppLang.tr: 'Giriş sırasında bir sorun oluştu. Lütfen tekrar dene.',
    AppLang.en: 'Something went wrong while signing in. Please try again.',
  },
  'drawer.brand': {AppLang.tr: 'Rotori', AppLang.en: 'Rotori'},
  'drawer.tagline': {
    AppLang.tr: 'Sürpriz yok, plan var.',
    AppLang.en: 'No surprises, just a plan.',
  },
  'drawer.section.discover': {AppLang.tr: 'KEŞFET', AppLang.en: 'DISCOVER'},
  'drawer.section.planning': {
    AppLang.tr: 'PLANLAMA ARAÇLARI',
    AppLang.en: 'PLANNING TOOLS',
  },
  'drawer.section.guides': {
    AppLang.tr: 'REHBERLER',
    AppLang.en: 'GUIDES',
  },
  'drawer.section.tools': {AppLang.tr: 'ARAÇLAR', AppLang.en: 'TOOLS'},
  // KEŞFET karolarının tek satırlık açıklamaları. Eskiden karolar etiketsiz
  // ikon kareleriydi; hangisinin ne yaptığı ancak tooltip ile anlaşılıyordu.
  'drawer.discover.eats.sub': {
    AppLang.tr: 'Helal, vejetaryen ve bütçene göre restoranlar',
    AppLang.en: 'Restaurants by halal, vegetarian and your budget',
  },
  'drawer.discover.eats.short': {
    AppLang.tr: 'Yemek rehberi',
    AppLang.en: 'Food guide',
  },
  'viewer.tt.experienceGuide': {
    AppLang.tr: 'Macera rehberi',
    AppLang.en: 'Adventure guide',
  },
  'drawer.discover.experienceGuide.sub': {
    AppLang.tr: 'USJ, Disney ve teamLab: bilet, süre, tam gün',
    AppLang.en: 'USJ, Disney and teamLab: tickets, timing, full day',
  },
  'drawer.discover.weather.sub': {
    AppLang.tr: 'Rota boyunca gün gün',
    AppLang.en: 'Day by day along your route',
  },
  'drawer.discover.budget.sub': {
    AppLang.tr: 'Harcama takibi',
    AppLang.en: 'Spend tracking',
  },
  'drawer.discover.checklist.sub': {
    AppLang.tr: 'Yola çıkmadan',
    AppLang.en: 'Before you go',
  },
  'drawer.discover.scanner.sub': {
    AppLang.tr: 'Etiketi çevir',
    AppLang.en: 'Translate a tag',
  },
  'drawer.discover.scanner.heroSub': {
    AppLang.tr: 'Etiketi tara, ürünü çevir ve fiyatı anında karşılaştır',
    AppLang.en: 'Scan a label, translate the product and compare its price',
  },
  'drawer.discover.theme.sub': {
    AppLang.tr: 'Görünümünü kişiselleştir',
    AppLang.en: 'Personalize your view',
  },
  'drawer.discover.travelEssentials.sub': {
    AppLang.tr: 'Yola çıkmadan gerekenler',
    AppLang.en: 'Travel essentials before departure',
  },
  'drawer.premium.label': {
    AppLang.tr: 'Premium',
    AppLang.en: 'Premium',
  },
  'drawer.premium.active': {
    AppLang.tr: 'Premium aktif',
    AppLang.en: 'Premium active',
  },
  'drawer.eats.pass': {AppLang.tr: 'Pass', AppLang.en: 'Pass'},
  'drawer.eats.free': {AppLang.tr: 'Ücretsiz', AppLang.en: 'Free'},
  'drawer.section.account': {AppLang.tr: 'HESAP', AppLang.en: 'ACCOUNT'},
  'drawer.flights.count': {
    AppLang.tr: '{n} uçuş',
    AppLang.en: '{n} flights',
  },
  'drawer.flights.leg': {
    AppLang.tr: 'Gezi {n}',
    AppLang.en: 'Trip {n}',
  },
  'drawer.hotels.count': {
    AppLang.tr: '{n} otel',
    AppLang.en: '{n} hotels',
  },
  'drawer.flights.empty': {
    AppLang.tr: 'Uçuş eklenmedi',
    AppLang.en: 'No flights',
  },
  'drawer.hotels.empty': {
    AppLang.tr: 'Otel eklenmedi',
    AppLang.en: 'No hotels',
  },
  'drawer.flights.add': {
    AppLang.tr: 'Uçuş ekle',
    AppLang.en: 'Add flight',
  },
  'drawer.hotels.add': {
    AppLang.tr: 'Otel ekle',
    AppLang.en: 'Add hotel',
  },
  'drawer.add.hint': {
    AppLang.tr: 'Planlayıcıda düzenle',
    AppLang.en: 'Edit in planner',
  },
  'drawer.flights.stops': {
    AppLang.tr: '{n} aktarma',
    AppLang.en: '{n} stop',
  },
  'drawer.flights.stops.plural': {
    AppLang.tr: '{n} aktarma',
    AppLang.en: '{n} stops',
  },
  'drawer.role.guest': {AppLang.tr: 'Misafir', AppLang.en: 'Guest'},
  'drawer.role.traveler': {AppLang.tr: 'Gezgin', AppLang.en: 'Traveler'},
  'drawer.nav.travelEssentials': {
    AppLang.tr: 'Seyahat öncesi hallet 📦',
    AppLang.en: 'Book before you go 📦'
  },
  'drawer.nav.plans': {AppLang.tr: 'Planlarım', AppLang.en: 'My plans'},
  'drawer.nav.viewer': {AppLang.tr: 'Rehber', AppLang.en: 'Guide'},
  'drawer.nav.reminders': {
    AppLang.tr: 'Hatırlatmalar',
    AppLang.en: 'Reminders',
  },
  'drawer.signout': {AppLang.tr: 'Çıkış yap', AppLang.en: 'Sign out'},
  'drawer.deleteAccount': {
    AppLang.tr: 'Hesabı sil',
    AppLang.en: 'Delete account'
  },
  'account.delete.title': {
    AppLang.tr: 'Hesabı silmek istiyor musun?',
    AppLang.en: 'Delete your account?',
  },
  'account.delete.body': {
    AppLang.tr:
        'Bu işlem geri alınamaz. Hesabın, planların ve tüm verilerin kalıcı olarak silinir. Devam etmek istiyor musun?',
    AppLang.en:
        'This action cannot be undone. Your account, plans and all data will be permanently deleted. Do you want to continue?',
  },
  'account.delete.confirm': {
    AppLang.tr: 'Evet, sil',
    AppLang.en: 'Yes, delete'
  },
  'account.delete.cancel': {AppLang.tr: 'Vazgeç', AppLang.en: 'Cancel'},
  'account.delete.error': {
    AppLang.tr: 'Hesap silinemedi. Lütfen tekrar dene.',
    AppLang.en: 'Could not delete account. Please try again.',
  },
  'account.delete.success': {
    AppLang.tr: 'Hesabın silindi. Sağlıcakla.',
    AppLang.en: 'Your account has been deleted. Farewell.',
  },
  'drawer.tt.menu': {AppLang.tr: 'Menü', AppLang.en: 'Menu'},
  // --- Yeni plan oluşturma (2 adım: nereye? → ne zaman?) ---
  'create.cities.title': {
    AppLang.tr: 'Japonya\'da nereye?',
    AppLang.en: 'Where in Japan?',
  },
  'create.cities.sub': {
    AppLang.tr: 'Şehirleri seç · rota sırası seçim sıran olur',
    AppLang.en: 'Pick your cities · route order follows your selection',
  },
  'create.cities.placeCount': {
    AppLang.tr: '{n} gezilecek yer',
    AppLang.en: '{n} places to see',
  },
  'create.cities.selected': {
    AppLang.tr: '{n} şehir seçildi',
    AppLang.en: '{n} cities selected',
  },
  'create.cities.selectHint': {
    AppLang.tr: 'En az bir şehir seç',
    AppLang.en: 'Pick at least one city',
  },
  'create.dates.title': {AppLang.tr: 'Ne zaman?', AppLang.en: 'When?'},
  'create.dates.sub': {
    AppLang.tr: 'Gidiş ve dönüş gününü seç',
    AppLang.en: 'Choose your travel window',
  },
  'create.dates.pick': {
    AppLang.tr: 'Tarih aralığı seç',
    AppLang.en: 'Pick a date range',
  },
  'create.dates.pickHint': {
    AppLang.tr: 'Gidiş ve dönüş gününü belirle',
    AppLang.en: 'Set your departure and return days',
  },
  'create.dates.depart': {AppLang.tr: 'GİDİŞ', AppLang.en: 'DEPART'},
  'create.dates.return': {AppLang.tr: 'DÖNÜŞ', AppLang.en: 'RETURN'},
  'create.dates.change': {AppLang.tr: 'Değiştir', AppLang.en: 'Change'},
  'create.dates.unknown': {
    AppLang.tr: '📅 Tarih henüz belli değil',
    AppLang.en: '📅 I don\'t know the dates yet',
  },
  'create.dates.estimated': {
    AppLang.tr:
        '🗓️ Sezona göre önerdik — plan hazır olduktan sonra istediğin zaman değiştirebilirsin.',
    AppLang.en:
        '🗓️ We picked a good season for you — change it any time after your plan is ready.',
  },
  'create.dates.nights': {
    AppLang.tr: '{nights} gece · {days} gün',
    AppLang.en: '{nights} nights · {days} days',
  },
  'create.dates.cityDays': {AppLang.tr: '{n} gün', AppLang.en: '{n} days'},
  'create.dates.splitNote': {
    AppLang.tr: 'Gün dağılımını plan hazır olduktan sonra değiştirebilirsin.',
    AppLang.en: 'You can adjust the day split once your plan is ready.',
  },
  'create.route.longTitle': {
    AppLang.tr: 'Rotan gereksiz uzun görünüyor',
    AppLang.en: 'Your route looks longer than it needs to be',
  },
  'create.route.current': {
    AppLang.tr: 'SEÇTİĞİN SIRA',
    AppLang.en: 'YOUR ORDER',
  },
  'create.route.suggested': {
    AppLang.tr: '~{km} KM DAHA KISA',
    AppLang.en: '~{km} KM SHORTER',
  },
  'create.route.fix': {
    AppLang.tr: 'Rotayı bu sıraya göre düzelt',
    AppLang.en: 'Reorder my route',
  },
  'create.route.fixed': {
    AppLang.tr: 'Rota sırası güncellendi.',
    AppLang.en: 'Route order updated.',
  },
  'create.dates.splitEditable': {
    AppLang.tr:
        '− / + ile şehir başına günü değiştir. Toplam gün sabit kalır; fark diğer şehirden alınır.',
    AppLang.en:
        'Use − / + to change days per city. The total stays fixed — days move between cities.',
  },
  'create.dates.tooManyCities': {
    AppLang.tr:
        'Seçtiğin şehir sayısı gün sayısından fazla. Tarihi uzat ya da bir şehir çıkar.',
    AppLang.en:
        'You picked more cities than days. Extend your dates or remove a city.',
  },
  'create.dates.editCities': {
    AppLang.tr: 'Şehirleri düzenle',
    AppLang.en: 'Edit cities',
  },
  'create.rangeHelp': {
    AppLang.tr: 'Seyahat tarihlerin',
    AppLang.en: 'Your travel dates',
  },
  'create.rangeConfirm': {AppLang.tr: 'Tamam', AppLang.en: 'Done'},
  'create.rangeCancel': {AppLang.tr: 'Vazgeç', AppLang.en: 'Cancel'},
  'create.continue': {AppLang.tr: 'Devam', AppLang.en: 'Continue'},
  'create.back': {AppLang.tr: 'Geri', AppLang.en: 'Back'},
  'create.generate': {
    AppLang.tr: 'Planımı oluştur',
    AppLang.en: 'Create my plan'
  },
  'create.dates.continue': {AppLang.tr: 'Devam', AppLang.en: 'Continue'},
  // 3. adım — beslenme tercihi + öğün bütçesi. İkisi de isteğe bağlı; boş
  // bırakılırsa Rotori uyum skoru o bileşeni "eksik" sayar (uydurmaz).
  'create.prefs.title': {
    AppLang.tr: 'Damak tadın',
    AppLang.en: 'Your taste',
  },
  'create.prefs.sub': {
    AppLang.tr: 'İsteğe bağlı — restoran önerilerini sana göre ayarlar.',
    AppLang.en: 'Optional — tunes restaurant picks to you.',
  },
  'create.assumptions.title': {
    AppLang.tr: 'Bu varsayımlarla hazırlıyorum',
    AppLang.en: 'I’ll build with these assumptions'
  },
  'create.assumptions.help': {
    AppLang.tr:
        'Planı oluşturmadan önce kontrol et. Uçuş ve otel bilgisi eklenene kadar taslak kalır.',
    AppLang.en:
        'Review before creating the plan. Flights and stays remain drafts until you add them.'
  },
  'create.assumptions.route': {AppLang.tr: 'ROTA', AppLang.en: 'ROUTE'},
  'create.assumptions.dates': {AppLang.tr: 'TARİHLER', AppLang.en: 'DATES'},
  'create.assumptions.flight': {AppLang.tr: 'UÇUŞ', AppLang.en: 'FLIGHT'},
  'create.assumptions.hotel': {AppLang.tr: 'OTEL', AppLang.en: 'STAY'},
  'create.assumptions.draft': {
    AppLang.tr: 'Eklenmedi · taslak',
    AppLang.en: 'Not added · draft'
  },
  'create.assumptions.estimatedBadge': {
    AppLang.tr: 'TAHMİNİ',
    AppLang.en: 'ESTIMATED'
  },
  'create.assumptions.estimatedReason': {
    AppLang.tr:
        'Yıl ve tarih aralığı, sezon havası ile yoğunluk dengesi gözetilerek önerildi; değiştirilebilir.',
    AppLang.en:
        'The year and dates were suggested to balance seasonal weather and crowds; you can change them.'
  },
  'create.assumptions.edit': {AppLang.tr: 'Düzelt', AppLang.en: 'Edit'},
  'create.assumptions.roundTrip': {
    AppLang.tr: 'gidiş-dönüş',
    AppLang.en: 'round trip',
  },
  'create.assumptions.add': {AppLang.tr: 'Ekle', AppLang.en: 'Add'},
  // Uçuş/otel ekleme planın var olmasını gerektiriyor: aksiyon önce planı
  // üretir, sonra ilgili ekranı açar. Kullanıcı ne olacağını önden bilsin.
  'create.assumptions.addHint': {
    AppLang.tr: 'Plan oluşturulur ve bu adım hemen açılır.',
    AppLang.en: 'Your plan is created, then this step opens.',
  },
  'create.prefs.diet': {
    AppLang.tr: 'Beslenme tercihlerin',
    AppLang.en: 'Your dietary needs',
  },
  'create.prefs.dietHint': {
    AppLang.tr:
        'Birden fazla seçebilirsin. Rotori Eats listeyi buna göre daraltır.',
    AppLang.en:
        'Pick as many as you need. Rotori Eats narrows the list to match.',
  },
  'create.prefs.budget': {
    AppLang.tr: 'Kişi başı öğün bütçen',
    AppLang.en: 'Meal budget per person',
  },
  'create.prefs.budgetHint': {
    AppLang.tr: 'Bir öğün için ayırdığın üst sınır.',
    AppLang.en: 'The ceiling you set for a single meal.',
  },
  'create.prefs.budgetSkip': {
    AppLang.tr: 'Belirtmek istemiyorum',
    AppLang.en: 'Prefer not to say',
  },
  'create.prefs.skip': {
    AppLang.tr: 'Bu adımı atla',
    AppLang.en: 'Skip this step',
  },
  'create.generating': {
    AppLang.tr: 'Planın hazırlanıyor…',
    AppLang.en: 'Building your plan…',
  },
  'create.ready': {
    AppLang.tr: '✨ Planın hazır',
    AppLang.en: '✨ Your plan is ready',
  },
  'create.saveFailed': {
    AppLang.tr: 'Plan kaydedilemedi. Bağlantını kontrol edip tekrar dene.',
    AppLang.en: 'Couldn\'t save the plan. Check your connection and try again.',
  },
  // --- Uçuş sayfası (plan sonrası, opsiyonel) ---
  'flights.title': {AppLang.tr: 'Uçuş bilgileri', AppLang.en: 'Flight details'},
  'flights.intro': {
    AppLang.tr:
        'Uçuşun girmesen de plan çalışır — varış saati varsayılan olarak 13:00 kabul edilir. '
            'Gerçek saatlerini girersen varış ve dönüş günü buna göre yeniden düzenlenir.',
    AppLang.en:
        'Your plan works even without flight details — arrival defaults to 13:00. '
            'Enter your real times and the arrival/departure days adjust to match.',
  },
  'flights.regenHint': {
    AppLang.tr:
        'Saatleri kaydettin — varış ve dönüş gününü bu saatlere göre yeniden düzenleyebilirsin.',
    AppLang.en:
        'Times saved — you can rebuild the arrival and departure days to match.',
  },
  'flights.regenAction': {
    AppLang.tr: 'Günleri yeniden düzenle',
    AppLang.en: 'Rebuild these days',
  },
  'flights.regenerated': {
    AppLang.tr: 'Varış ve dönüş günü güncellendi',
    AppLang.en: 'Arrival and departure days updated',
  },
  'flights.saved.title': {
    AppLang.tr: 'Uçuş kaydedildi',
    AppLang.en: 'Flight saved',
  },
  'flights.saved.body': {
    AppLang.tr: 'Rotanız uçuş saatlerinize göre güncellendi.',
    AppLang.en: 'Your itinerary was updated around your flight times.',
  },
  'flights.saveFailed': {
    AppLang.tr: 'Uçuş kaydedilemedi. Lütfen tekrar deneyin.',
    AppLang.en: 'The flight could not be saved. Please try again.',
  },
  'budget.rateAgeMin': {
    AppLang.tr: 'Kur {n} dk önce güncellendi',
    AppLang.en: 'Rate updated {n} min ago',
  },
  'budget.rateAgeHour': {
    AppLang.tr: 'Kur {n} saat önce güncellendi',
    AppLang.en: 'Rate updated {n}h ago',
  },
  'budget.rateAgeDay': {
    AppLang.tr: 'Kur {n} gün önce güncellendi',
    AppLang.en: 'Rate updated {n}d ago',
  },
  // Kısa biçimler: kur satırı artık tek satırda kur + tazelik + "Kuru düzenle"
  // taşıyor; uzun cümle orada kırpılıyordu ("Kur 11 saat önce…"). Bağlam
  // (kurun hemen yanı + ⟳ ikonu) neyin güncellendiğini zaten söylüyor.
  'budget.rateAgeMinShort': {
    AppLang.tr: '{n} dk önce',
    AppLang.en: '{n} min ago',
  },
  'budget.rateAgeHourShort': {
    AppLang.tr: '{n} sa önce',
    AppLang.en: '{n}h ago',
  },
  'budget.rateAgeDayShort': {
    AppLang.tr: '{n} gün önce',
    AppLang.en: '{n}d ago',
  },
  'viewer.guide.search': {
    AppLang.tr: 'Rehberde ara — Suica, valiz, fiş…',
    AppLang.en: 'Search the guide — Suica, packing, plugs…',
  },
  'viewer.guide.noResult': {
    AppLang.tr: 'Bu aramaya uyan madde yok.',
    AppLang.en: 'No tips match that search.',
  },
  'viewer.transition.official': {
    AppLang.tr: 'Resmî bilet',
    AppLang.en: 'Official',
  },
  'viewer.transition.pickerTitle': {
    AppLang.tr: '{from} → {to} ulaşımı',
    AppLang.en: '{from} → {to} transport'
  },
  'viewer.transition.pickerHelp': {
    AppLang.tr:
        'Tercihin plana kaydedilir. Süre ve ücret kesin bilet bilgisi değildir.',
    AppLang.en:
        'Your choice is saved to the plan. Duration and fare are not confirmed ticket details.'
  },
  'viewer.transition.mode.shinkansen': {
    AppLang.tr: 'Shinkansen',
    AppLang.en: 'Shinkansen'
  },
  'viewer.transition.mode.train': {AppLang.tr: 'Tren', AppLang.en: 'Train'},
  'viewer.transition.mode.bus': {AppLang.tr: 'Otobüs', AppLang.en: 'Bus'},
  'viewer.transition.mode.taxi': {AppLang.tr: 'Taksi', AppLang.en: 'Taxi'},
  'viewer.transition.mode.flight': {AppLang.tr: 'Uçak', AppLang.en: 'Flight'},
  'viewer.transition.addTicket': {
    AppLang.tr: 'Bu geçişe bilet ekle',
    AppLang.en: 'Add a ticket to this transfer'
  },
  'viewer.transition.editTicket': {
    AppLang.tr: 'Bağlı bileti görüntüle veya düzenle',
    AppLang.en: 'View or edit the linked ticket'
  },
  'viewer.transition.openOfficial': {
    AppLang.tr: 'Resmî Shinkansen rezervasyonunu aç',
    AppLang.en: 'Open official Shinkansen booking'
  },
  'viewer.ticketEditor.addTitle': {
    AppLang.tr: 'Bilet ekle',
    AppLang.en: 'Add ticket'
  },
  'viewer.ticketEditor.editTitle': {
    AppLang.tr: 'Bileti düzenle',
    AppLang.en: 'Edit ticket'
  },
  'viewer.ticketEditor.label': {
    AppLang.tr: 'Bilet adı',
    AppLang.en: 'Ticket name'
  },
  'viewer.ticketEditor.url': {
    AppLang.tr: 'Bilet veya rezervasyon bağlantısı (isteğe bağlı)',
    AppLang.en: 'Ticket or booking link (optional)'
  },
  'viewer.ticketEditor.purchased': {
    AppLang.tr: 'Bilet satın alındı',
    AppLang.en: 'Ticket purchased'
  },
  'viewer.ticketEditor.save': {AppLang.tr: 'Kaydet', AppLang.en: 'Save'},
  'viewer.ticketEditor.saveFailed': {
    AppLang.tr: 'Bilet kaydedilemedi. Lütfen tekrar dene.',
    AppLang.en: 'The ticket could not be saved. Please try again.'
  },
  'viewer.mustSee.title': {
    AppLang.tr: 'Bunları da gör',
    AppLang.en: 'See these too',
  },
  'viewer.mustSee.body': {
    AppLang.tr: 'Rotandaki şehirlerden, planına henüz girmemiş yerler.',
    AppLang.en: 'Places in your cities that your plan doesn\'t cover yet.',
  },
  'viewer.mustSee.cta': {
    AppLang.tr: 'Plana ekle',
    AppLang.en: 'Add to plan',
  },
  'viewer.mustSee.ctaCount': {
    AppLang.tr: '{n} yeri plana ekle',
    AppLang.en: 'Add {n} to plan',
  },
  'viewer.mustSee.dismiss': {
    AppLang.tr: 'Bu kartı gizle',
    AppLang.en: 'Hide this card',
  },
  'viewer.mustSee.added': {
    AppLang.tr: '{n} yer plana eklendi.',
    AppLang.en: '{n} place(s) added to your plan.',
  },
  'viewer.mustSee.partial': {
    AppLang.tr: '{n} eklendi · {m} sığmadı (günler dolu).',
    AppLang.en: '{n} added · {m} didn\'t fit (days are full).',
  },
  'viewer.mustSee.none': {
    AppLang.tr: 'Hiçbiri sığmadı — günlerin dolu. Önce bir şeyler çıkar.',
    AppLang.en: 'Nothing fit — your days are full. Remove something first.',
  },
  'viewer.addFlight.title': {
    AppLang.tr: '✈️ Uçuşunu ekle',
    AppLang.en: '✈️ Add your flight',
  },
  'viewer.addFlight.body': {
    AppLang.tr:
        'Kalkış/varış saatlerini gir — varış ve dönüş günü otomatik düzenlensin.',
    AppLang.en:
        'Enter your flight times so arrival and departure days adjust automatically.',
  },
  'plans.title': {AppLang.tr: 'Planlarım', AppLang.en: 'My plans'},
  'plans.headerSubtitle': {
    AppLang.tr: '旅 · yolculuklarını tek yerde tut',
    AppLang.en: '旅 · keep every journey in one place',
  },
  'plans.refresh': {AppLang.tr: 'Yenile', AppLang.en: 'Refresh'},
  'plans.signOut': {AppLang.tr: 'Çıkış yap', AppLang.en: 'Sign out'},
  'plans.newPlan': {AppLang.tr: 'Yeni plan', AppLang.en: 'New plan'},
  'plans.emptyTitle': {
    AppLang.tr: 'Henüz planın yok',
    AppLang.en: 'No plans yet'
  },
  'plans.emptyBody': {
    AppLang.tr:
        'Sağ alttaki "Yeni plan" ile başla — sonra günleri, uçuşları ve otelleri ekleriz.',
    AppLang.en:
        'Start with "New plan" at the bottom right — then we\'ll add the days, flights and hotels.'
  },
  'plans.offline': {
    AppLang.tr: 'Çevrimdışı — yerel kopya gösteriliyor',
    AppLang.en: 'Offline — showing your local copy'
  },
  'plans.dateRange': {
    AppLang.tr: '{start} → {end}  ·  {n} gün',
    AppLang.en: '{start} → {end}  ·  {n} days'
  },
  'plans.days': {AppLang.tr: '{n} gün', AppLang.en: '{n} days'},
  'plans.destinations': {
    AppLang.tr: '{n} şehir',
    AppLang.en: '{n} cities',
  },
  'plans.view': {AppLang.tr: 'Görüntüle', AppLang.en: 'View'},
  'plans.edit': {AppLang.tr: 'Düzenle', AppLang.en: 'Edit'},
  'plans.delete': {AppLang.tr: 'Sil', AppLang.en: 'Delete'},
  'plans.deleteConfirmTitle': {
    AppLang.tr: 'Planı sil',
    AppLang.en: 'Delete plan',
  },
  'plans.deleteConfirmBody': {
    AppLang.tr:
        '"{title}" planı ve içindeki tüm günler kalıcı olarak silinsin mi?',
    AppLang.en: 'Delete "{title}" and all its days permanently?',
  },
  'plans.deleteConfirmAction': {AppLang.tr: 'Sil', AppLang.en: 'Delete'},
  'plans.cancel': {AppLang.tr: 'Vazgeç', AppLang.en: 'Cancel'},
  'plans.signOutConfirmTitle': {
    AppLang.tr: 'Çıkış yapılsın mı?',
    AppLang.en: 'Sign out now?',
  },
  'plans.signOutConfirmBody': {
    AppLang.tr:
        'Bu cihazda oturum kapanacak. Planların bulutta kalır, tekrar giriş yapabilirsin.',
    AppLang.en:
        'This will sign you out on this device. Your plans stay in the cloud and you can sign in again anytime.',
  },
  'plans.signOutConfirmAction': {
    AppLang.tr: 'Çıkış yap',
    AppLang.en: 'Sign out',
  },
  'reward.title': {AppLang.tr: 'Keşif haritası', AppLang.en: 'Explore Map'},
  // Keşfet ana yüzeyi — harita + planlı duraklar. XP/rozet ekranı ayrı ve
  // ikincil bir akış olarak kalır.
  'explore.today': {
    AppLang.tr: 'Bugün · {city}',
    AppLang.en: 'Today · {city}',
  },
  'explore.mode.planned': {
    AppLang.tr: 'Planlı duraklar',
    AppLang.en: 'Planned stops',
  },
  'explore.mode.nearby': {
    AppLang.tr: 'Yakınımda',
    AppLang.en: 'Nearby',
  },
  'explore.day': {
    AppLang.tr: '{n}. gün · {city}',
    AppLang.en: 'Day {n} · {city}',
  },
  'explore.map': {AppLang.tr: 'Harita', AppLang.en: 'Map'},
  'explore.openFullMap': {
    AppLang.tr: 'Büyük haritada aç',
    AppLang.en: 'Open full map',
  },
  'explore.mapHint': {
    AppLang.tr: 'Bir durağa dokunarak ayrıntılarını gör.',
    AppLang.en: 'Tap a stop to see its details.',
  },
  'explore.duration': {AppLang.tr: '{n} dk', AppLang.en: '{n} min'},
  'explore.distanceMeters': {AppLang.tr: '{n} m', AppLang.en: '{n} m'},
  'explore.distanceKilometers': {
    AppLang.tr: '{n} km',
    AppLang.en: '{n} km',
  },
  'explore.nearbyWaiting': {
    AppLang.tr: 'Konum alınana kadar planındaki durakları gösteriyoruz.',
    AppLang.en: 'We show your planned stops until a location fix is available.',
  },
  'explore.nearbyActive': {
    AppLang.tr: 'Duraklar konumuna göre yakından uzağa sıralanıyor.',
    AppLang.en: 'Stops are ordered from nearest to farthest from you.',
  },
  'explore.inPlan': {AppLang.tr: 'Rotanda', AppLang.en: 'In your plan'},
  'explore.visited': {AppLang.tr: 'Gezildi', AppLang.en: 'Visited'},
  'explore.noStopsTitle': {
    AppLang.tr: 'Bu gün için planlı durak yok',
    AppLang.en: 'No planned stops for this day',
  },
  'explore.noStopsBody': {
    AppLang.tr: 'Gün akışına bir yer eklediğinde burada haritada görünür.',
    AppLang.en: 'Places added to the day flow will appear here on the map.',
  },
  'explore.nearbyHint': {
    AppLang.tr:
        'Yakındaki planlı durakları göstermek için konumunu paylaş. Rotori dışarıdan rastgele yer aramaz.',
    AppLang.en:
        'Share your location to see planned stops nearby. Rotori does not search random places outside your plan.',
  },
  'explore.progressTitle': {
    AppLang.tr: 'İlerlemen',
    AppLang.en: 'Your progress',
  },
  'explore.progressSummary': {
    AppLang.tr: '{visited} / {total} durak',
    AppLang.en: '{visited} / {total} stops',
  },
  'explore.viewProgress': {
    AppLang.tr: 'Tüm ilerlemeyi gör',
    AppLang.en: 'See all progress',
  },
  'reward.gpsSimTooltip': {
    AppLang.tr: 'GPS Simülatörü (test)',
    AppLang.en: 'GPS Simulator (test)'
  },
  'reward.discovered': {
    AppLang.tr: '🎉 {emoji} {name} keşfedildi! +{xp} XP',
    AppLang.en: '🎉 {emoji} {name} discovered! +{xp} XP'
  },
  'reward.badgeEarned': {
    AppLang.tr: '🎉 {emoji} {title} rozeti kazanıldı!',
    AppLang.en: '🎉 {emoji} {title} badge earned!'
  },
  'reward.badgeEarnedMany': {
    AppLang.tr: '🎉 {count} yeni rozet kazanıldı!',
    AppLang.en: '🎉 {count} new badges earned!'
  },
  'reward.summary': {
    AppLang.tr:
        '{cities} şehir · {visited}/{total} nokta gezildi · Level {level}',
    AppLang.en:
        '{cities} cities · {visited}/{total} spots visited · Level {level}'
  },
  'reward.level': {AppLang.tr: 'Level {n}', AppLang.en: 'Level {n}'},
  'reward.xpToNext': {
    AppLang.tr: '{xp} XP sonraki seviyeye',
    AppLang.en: '{xp} XP to next level'
  },
  'reward.noCities': {
    AppLang.tr:
        'Rotanda tanıdık bir şehir bulamadık. Planlayıcıda Tokyo, Kyoto, Osaka gibi şehirler eklersen keşif haritası burada belirir.',
    AppLang.en:
        'We couldn\'t find a familiar city on your route. Add cities like Tokyo, Kyoto or Osaka in the planner and the explore map will appear here.'
  },
  'reward.cityIntro': {
    AppLang.tr:
        'Her şehrin popüler noktaları aşağıda. Konum takibi açıkken bir noktada 10 dakikadan fazla kalırsan otomatik yeşillenir ve sana bildirim gelir. 📍',
    AppLang.en:
        'Each city\'s popular spots are below. With location tracking on, staying at a spot for more than 10 minutes turns it green automatically and sends you a notification. 📍'
  },
  'reward.stat.visited': {AppLang.tr: 'Gezilen', AppLang.en: 'Visited'},
  'reward.stat.total': {AppLang.tr: 'Toplam', AppLang.en: 'Total'},
  'reward.stat.cities': {AppLang.tr: 'Şehir', AppLang.en: 'Cities'},
  'reward.stat.pointsValue': {AppLang.tr: '{n} nokta', AppLang.en: '{n} spots'},
  'reward.badgesTitle': {
    AppLang.tr: '🏅 Aktivite rozetleri',
    AppLang.en: '🏅 Activity badges'
  },
  'reward.badgesSubtitle': {
    AppLang.tr:
        'Bunlar manuel planlama/kullanım rozetleridir (GPS doğrulaması gerekmiyor).',
    AppLang.en:
        'These are manual planning/usage badges (no GPS verification required).'
  },
  'reward.chip': {
    AppLang.tr: 'Level {level} · {xp} XP · {earned}/{total}',
    AppLang.en: 'Level {level} · {xp} XP · {earned}/{total}'
  },
  'reward.tracking.unsupported': {
    AppLang.tr: '📵 Konum servisleri kullanılamıyor',
    AppLang.en: '📵 Location services unavailable'
  },
  'reward.tracking.denied': {
    AppLang.tr: '🔒 Konum izni reddedildi',
    AppLang.en: '🔒 Location permission denied'
  },
  'reward.tracking.deniedForever': {
    AppLang.tr: '🔒 Konum izni kalıcı olarak reddedildi',
    AppLang.en: '🔒 Location permission permanently denied'
  },
  'reward.tracking.on': {
    AppLang.tr: '📡 Konum takibi açık',
    AppLang.en: '📡 Location tracking on'
  },
  'reward.tracking.off': {
    AppLang.tr: '📍 Konum takibini aç',
    AppLang.en: '📍 Turn on location tracking'
  },
  'reward.tracking.body': {
    AppLang.tr:
        'Noktaların otomatik gezildi olması için konum takibi gerekir. Bir yerde 10 dk+ kalınca kendiliğinden yeşillenir ve bildirim alırsın. Batarya için uygulama arka plandayken takip duraklatılır.',
    AppLang.en:
        'Location tracking is needed for spots to be marked visited automatically. Staying somewhere for 10+ min turns it green on its own and sends you a notification. To save battery, tracking pauses while the app is in the background.'
  },
  'reward.tracking.smartMode': {
    AppLang.tr: 'Akıllı takip modu',
    AppLang.en: 'Smart tracking mode',
  },
  'reward.tracking.smartModeHint': {
    AppLang.tr:
        'Gezi tarihleri içinde otomatik aktif olur, dışında kendini durdurur.',
    AppLang.en:
        'Automatically active during trip dates, pauses itself outside the window.',
  },
  'reward.tracking.mode.battery': {
    AppLang.tr: 'Tasarruf',
    AppLang.en: 'Battery saver',
  },
  'reward.tracking.mode.balanced': {
    AppLang.tr: 'Dengeli',
    AppLang.en: 'Balanced',
  },
  'reward.tracking.mode.precise': {
    AppLang.tr: 'Hassas',
    AppLang.en: 'Precise',
  },
  'reward.tracking.tripWindowPaused': {
    AppLang.tr:
        'Akıllı mod nedeniyle takip şu an beklemede (gezi tarih aralığı dışında).',
    AppLang.en:
        'Smart mode is paused right now (outside the trip date window).',
  },
  'reward.tracking.openSettings': {
    AppLang.tr: 'Ayarlar\'dan konum iznini aç',
    AppLang.en: 'Open location permission in Settings'
  },
  'reward.tracking.stop': {AppLang.tr: 'Durdur', AppLang.en: 'Stop'},
  'reward.tracking.start': {
    AppLang.tr: 'Konumu izlemeye başla',
    AppLang.en: 'Start tracking location'
  },
  'reward.locked': {AppLang.tr: '🔒 Kilitli', AppLang.en: '🔒 Locked'},
  // ----- Gezgin rütbesi (Japon efsane yaratıkları merdiveni) -----
  'reward.rankTier': {
    AppLang.tr: 'Gezgin rütbesi',
    AppLang.en: 'Traveler rank'
  },
  'reward.xpTotal': {AppLang.tr: 'Toplam XP', AppLang.en: 'Total XP'},
  'reward.nextRank': {AppLang.tr: 'Sonraki rütbe', AppLang.en: 'Next rank'},
  'reward.toNextRank': {
    AppLang.tr: '{rank} rütbesine {xp} XP',
    AppLang.en: '{xp} XP to {rank}',
  },
  'reward.maxRank': {
    AppLang.tr: 'En yüksek rütbeye ulaştın',
    AppLang.en: 'You reached the highest rank',
  },
  'reward.exploreProgress': {
    AppLang.tr: 'Keşif ilerlemesi',
    AppLang.en: 'Exploration progress',
  },
  'reward.rankUp.label': {AppLang.tr: 'YENİ RÜTBE', AppLang.en: 'NEW RANK'},
  'reward.rankUp.body': {
    AppLang.tr: 'Yeni bir rütbeye yükseldin — yolculuk sürüyor.',
    AppLang.en: 'You rose to a new rank — the journey continues.',
  },
  'reward.rank.tanuki': {
    AppLang.tr: 'Meraklı yolcu',
    AppLang.en: 'Curious wanderer'
  },
  'reward.rank.kitsune': {
    AppLang.tr: 'Kurnaz kaşif',
    AppLang.en: 'Clever explorer'
  },
  'reward.rank.kappa': {
    AppLang.tr: 'Nehir yoldaşı',
    AppLang.en: 'River companion'
  },
  'reward.rank.tengu': {
    AppLang.tr: 'Dağ bekçisi',
    AppLang.en: 'Mountain guardian'
  },
  'reward.rank.tsuru': {
    AppLang.tr: 'Zarif gezgin',
    AppLang.en: 'Graceful traveler'
  },
  'reward.rank.kirin': {
    AppLang.tr: 'Kutlu kaşif',
    AppLang.en: 'Blessed explorer'
  },
  'reward.rank.hoo': {
    AppLang.tr: 'Küllerinden doğan',
    AppLang.en: 'Risen from ashes'
  },
  'reward.rank.ryu': {
    AppLang.tr: 'Efsane ejderha',
    AppLang.en: 'Legendary dragon'
  },
  'badge.firstJapanPlan.title': {
    AppLang.tr: 'İlk Japonya Planı',
    AppLang.en: 'First Japan Plan'
  },
  'badge.firstJapanPlan.desc': {
    AppLang.tr: 'Japonya gezi planını oluşturdun.',
    AppLang.en: 'You created your Japan trip plan.'
  },
  'badge.firstJapanPlan.hint': {
    AppLang.tr: 'Planlayıcıdan ilk planı kaydet.',
    AppLang.en: 'Save your first plan from the planner.'
  },
  'badge.osakaExplorer.title': {
    AppLang.tr: 'Osaka Kaşifi',
    AppLang.en: 'Osaka Explorer'
  },
  'badge.osakaExplorer.desc': {
    AppLang.tr: 'Osaka\'yı rotana ekledin.',
    AppLang.en: 'You added Osaka to your route.'
  },
  'badge.osakaExplorer.hint': {
    AppLang.tr: 'Rotaya Osaka eklendiğinde açılır.',
    AppLang.en: 'Unlocks when Osaka is added to your route.'
  },
  'badge.kyotoTempleWanderer.title': {
    AppLang.tr: 'Kyoto Tapınak Gezgini',
    AppLang.en: 'Kyoto Temple Wanderer'
  },
  'badge.kyotoTempleWanderer.desc': {
    AppLang.tr: 'Kyoto’da tapınak rotası planladın.',
    AppLang.en: 'You planned a temple route in Kyoto.'
  },
  'badge.kyotoTempleWanderer.hint': {
    AppLang.tr: 'Kyoto\'ya git + Fushimi Inari / tapınak ekle.',
    AppLang.en: 'Go to Kyoto and add Fushimi Inari or a temple.'
  },
  'badge.naraDeerFriend.title': {
    AppLang.tr: 'Nara Geyik Dostu',
    AppLang.en: 'Nara Deer Friend'
  },
  'badge.naraDeerFriend.desc': {
    AppLang.tr: 'Nara durağı planına girdi.',
    AppLang.en: 'A Nara stop made it into your plan.'
  },
  'badge.naraDeerFriend.hint': {
    AppLang.tr: 'Rotana Nara ekle.',
    AppLang.en: 'Add Nara to your route.'
  },
  'badge.pokemonHunter.title': {
    AppLang.tr: 'Pokémon Avcısı',
    AppLang.en: 'Pokémon Hunter'
  },
  'badge.pokemonHunter.desc': {
    AppLang.tr: 'Pokémon ilgisini açtın.',
    AppLang.en: 'You turned on the Pokémon interest.'
  },
  'badge.pokemonHunter.hint': {
    AppLang.tr: 'Onboarding\'de Pokémon ilgi alanını seç.',
    AppLang.en: 'Pick the Pokémon interest during onboarding.'
  },
  'badge.donkiExpert.title': {
    AppLang.tr: 'Donki Uzmanı',
    AppLang.en: 'Donki Expert'
  },
  'badge.donkiExpert.desc': {
    AppLang.tr: 'Alışverişe odaklı bir plan kurdun.',
    AppLang.en: 'You built a shopping-focused plan.'
  },
  'badge.donkiExpert.hint': {
    AppLang.tr: 'Shopping ilgi alanını seç.',
    AppLang.en: 'Pick the Shopping interest.'
  },
  'badge.kidsJapan.title': {
    AppLang.tr: 'Çocukla Japonya',
    AppLang.en: 'Japan with Kids'
  },
  'badge.kidsJapan.desc': {
    AppLang.tr: 'Çocuklu bir Japonya gezisi planladın.',
    AppLang.en: 'You planned a Japan trip with children.'
  },
  'badge.kidsJapan.hint': {
    AppLang.tr: 'Çocuk profili gir.',
    AppLang.en: 'Add a child profile.'
  },
  'badge.rainyDaySaviour.title': {
    AppLang.tr: 'Yağmurlu Gün Kurtarıcısı',
    AppLang.en: 'Rainy Day Saviour'
  },
  'badge.rainyDaySaviour.desc': {
    AppLang.tr: 'Hava\'ya göre planla özelliğini kullandın.',
    AppLang.en: 'You used the plan-by-weather feature.'
  },
  'badge.rainyDaySaviour.hint': {
    AppLang.tr: 'WeatherStrip\'teki "🪄 Hava\'ya göre planla" butonunu kullan.',
    AppLang.en: 'Use the "🪄 Plan by weather" button in the WeatherStrip.'
  },
  'badge.firstRevision.title': {
    AppLang.tr: 'İlk Plan Revizyonu',
    AppLang.en: 'First Plan Revision'
  },
  'badge.firstRevision.desc': {
    AppLang.tr: 'AI düzenleme kullandın.',
    AppLang.en: 'You used AI editing.'
  },
  'badge.firstRevision.hint': {
    AppLang.tr: 'Düzenle butonuyla planı revize et.',
    AppLang.en: 'Revise the plan with the Edit button.'
  },
  'badge.longWalker.title': {
    AppLang.tr: '20.000 Adım Günü',
    AppLang.en: '20,000-Step Day'
  },
  'badge.longWalker.desc': {
    AppLang.tr: 'Plana çok yürüyüşlü bir gün koydun.',
    AppLang.en: 'You added a big walking day to your plan.'
  },
  'badge.longWalker.hint': {
    AppLang.tr: 'Bir günün adım tahmini 20.000+ olsun.',
    AppLang.en: 'Make a day\'s step estimate 20,000+.'
  },
  'badge.mediumWalker.title': {
    AppLang.tr: '10.000 Adım Günü',
    AppLang.en: '10,000-Step Day'
  },
  'badge.mediumWalker.desc': {
    AppLang.tr: '10.000+ adım hedefli bir gün hazırladın.',
    AppLang.en: 'You prepared a day targeting 10,000+ steps.'
  },
  'badge.mediumWalker.hint': {
    AppLang.tr: 'Bir günün adım tahmini 10.000+ olsun.',
    AppLang.en: 'Make a day\'s step estimate 10,000+.'
  },
  'badge.communityJoined.title': {
    AppLang.tr: 'Topluluğa Katkı',
    AppLang.en: 'Community Contributor'
  },
  'badge.communityJoined.desc': {
    AppLang.tr: 'Beta topluluğa ilgi gösterdin.',
    AppLang.en: 'You showed interest in the beta community.'
  },
  'badge.communityJoined.hint': {
    AppLang.tr: 'Beta topluluk bölümünden bir oda seç.',
    AppLang.en: 'Pick a room in the beta community section.'
  },
  'badge.firstDiscovery.title': {
    AppLang.tr: 'İlk Keşif',
    AppLang.en: 'First Discovery'
  },
  'badge.firstDiscovery.desc': {
    AppLang.tr: 'GPS ile ilk yerini keşfettin.',
    AppLang.en: 'You discovered your first place with GPS.'
  },
  'badge.firstDiscovery.hint': {
    AppLang.tr: 'Rotandaki bir yere git ve 10 dk kal.',
    AppLang.en: 'Go to a place on your route and stay 10 min.'
  },
  'badge.explorer5.title': {AppLang.tr: 'Kaşif', AppLang.en: 'Explorer'},
  'badge.explorer5.desc': {
    AppLang.tr: '5 yer keşfettin.',
    AppLang.en: 'You discovered 5 places.'
  },
  'badge.explorer5.hint': {
    AppLang.tr: 'GPS ile 5 farklı yeri gez.',
    AppLang.en: 'Visit 5 different places with GPS.'
  },
  'badge.explorer10.title': {
    AppLang.tr: 'Japonya Gezgini',
    AppLang.en: 'Japan Voyager'
  },
  'badge.explorer10.desc': {
    AppLang.tr: '10 yer keşfettin.',
    AppLang.en: 'You discovered 10 places.'
  },
  'badge.explorer10.hint': {
    AppLang.tr: 'GPS ile 10 farklı yeri gez.',
    AppLang.en: 'Visit 10 different places with GPS.'
  },
  'badge.tokyoRoamer.title': {
    AppLang.tr: 'Tokyo Kâşifi',
    AppLang.en: 'Tokyo Roamer'
  },
  'badge.tokyoRoamer.desc': {
    AppLang.tr: 'Tokyo\'da 3 yer gezdin.',
    AppLang.en: 'You explored 3 places in Tokyo.'
  },
  'badge.tokyoRoamer.hint': {
    AppLang.tr: 'Tokyo\'da GPS ile 3 yer keşfet.',
    AppLang.en: 'Discover 3 places in Tokyo with GPS.'
  },
  'badge.kyotoRoamer.title': {
    AppLang.tr: 'Kyoto Kâşifi',
    AppLang.en: 'Kyoto Roamer'
  },
  'badge.kyotoRoamer.desc': {
    AppLang.tr: 'Kyoto\'da 3 yer gezdin.',
    AppLang.en: 'You explored 3 places in Kyoto.'
  },
  'badge.kyotoRoamer.hint': {
    AppLang.tr: 'Kyoto\'da GPS ile 3 yer keşfet.',
    AppLang.en: 'Discover 3 places in Kyoto with GPS.'
  },
  'badge.osakaRoamer.title': {
    AppLang.tr: 'Osaka Kâşifi',
    AppLang.en: 'Osaka Roamer'
  },
  'badge.osakaRoamer.desc': {
    AppLang.tr: 'Osaka\'da 3 yer gezdin.',
    AppLang.en: 'You explored 3 places in Osaka.'
  },
  'badge.osakaRoamer.hint': {
    AppLang.tr: 'Osaka\'da GPS ile 3 yer keşfet.',
    AppLang.en: 'Discover 3 places in Osaka with GPS.'
  },

  // ===== Domain content (Wave 4: transfers/generators/weather/rules/booking) =====
  'bw.usj.title': {
    AppLang.tr: 'USJ Express Pass',
    AppLang.en: 'USJ Express Pass'
  },
  'bw.usj.subtitle': {
    AppLang.tr: 'Universal Studios Japan bilet ve Express Pass',
    AppLang.en: 'Universal Studios Japan tickets & Express Pass'
  },
  'bw.usj.tip': {
    AppLang.tr:
        'Studio Pass ve Express Pass takvimi değişebilir. Yaklaşık 2 ay önce resmî USJ satış takvimini kontrol et; Express ürünleri yoğun dönemde hızlı tükenebilir.',
    AppLang.en:
        'Studio Pass and Express Pass schedules can change. Check the official USJ sales calendar about 2 months ahead; Express products can sell quickly in peak season.'
  },
  'bw.disney.title': {
    AppLang.tr: 'Tokyo Disney passport + Premier Access',
    AppLang.en: 'Tokyo Disney passport + Premier Access'
  },
  'bw.disney.subtitle': {
    AppLang.tr: 'Tokyo Disneyland / DisneySea giriş bileti',
    AppLang.en: 'Tokyo Disneyland / DisneySea entry ticket'
  },
  'bw.disney.tip': {
    AppLang.tr:
        'Giriş biletleri ~2 ay öncesinden Tokyo Disney Resort resmi sitesinden. Premier Access uygulama üzerinden gün içi alınır ama giriş bileti şart.',
    AppLang.en:
        'Entry tickets open ~2 months ahead on the official Tokyo Disney Resort site. Premier Access is bought in-app on the day, but an entry ticket is required first.'
  },
  'bw.shinkansen.title': {
    AppLang.tr: 'Shinkansen (Smart-EX)',
    AppLang.en: 'Shinkansen (Smart-EX)'
  },
  'bw.shinkansen.subtitle': {
    AppLang.tr: 'Tokyo ↔ Kyoto / Osaka arası yüksek hızlı tren',
    AppLang.en: 'High-speed train between Tokyo ↔ Kyoto / Osaka'
  },
  'bw.shinkansen.tip': {
    AppLang.tr:
        'SmartEX standart rezervasyonu 1 ay önce 10:00 JST’de açılır. Daha erken talepler alınabilse de tren ve koltuk 1 ay kala kesinleşebilir; resmî koşulları kontrol et.',
    AppLang.en:
        'Standard SmartEX booking opens at 10:00 JST one month ahead. Earlier requests may be accepted, but train and seat details can be confirmed one month out; check the official terms.'
  },
  'bw.teamlabPlanets.title': {
    AppLang.tr: 'teamLab Planets',
    AppLang.en: 'teamLab Planets'
  },
  'bw.teamlabPlanets.subtitle': {
    AppLang.tr: 'Toyosu saatli giriş bileti',
    AppLang.en: 'Timed admission in Toyosu'
  },
  'bw.teamlabPlanets.tip': {
    AppLang.tr:
        'Sabit bir satış açılış günü ilan edilmiyor. Popüler saatlerin tükenme riskine karşı 4 hafta önce resmî takvimi kontrol et.',
    AppLang.en:
        'There is no fixed published release day. Check the official calendar 4 weeks ahead because popular time slots can sell out.'
  },
  'bw.teamlabBorderless.title': {
    AppLang.tr: 'teamLab Borderless',
    AppLang.en: 'teamLab Borderless'
  },
  'bw.teamlabBorderless.subtitle': {
    AppLang.tr: 'Azabudai Hills saatli giriş bileti',
    AppLang.en: 'Timed admission at Azabudai Hills'
  },
  'bw.teamlabBorderless.tip': {
    AppLang.tr:
        'Sabit bir açılış günü yerine güvenli planlama hedefi kullanılır. İstediğin saat için 4 hafta önce resmî takvimi kontrol et.',
    AppLang.en:
        'This uses a planning target rather than a fixed release rule. Check the official calendar 4 weeks ahead for your preferred time.'
  },
  'bw.teamlabBotanical.title': {
    AppLang.tr: 'teamLab Botanical Garden',
    AppLang.en: 'teamLab Botanical Garden'
  },
  'bw.teamlabBotanical.subtitle': {
    AppLang.tr: 'Osaka gece bahçesi tarihli bileti',
    AppLang.en: 'Dated Osaka night garden ticket'
  },
  'bw.teamlabBotanical.tip': {
    AppLang.tr:
        'Saatler mevsim ve hava koşullarıyla değişir. İki hafta önce bilet ve son giriş saatini resmî sayfadan kontrol et.',
    AppLang.en:
        'Hours vary with season and weather. Check tickets and final entry on the official page two weeks ahead.'
  },
  'bw.reason.tokyoKansai': {
    AppLang.tr: 'Tokyo → Kansai geçişi',
    AppLang.en: 'Tokyo → Kansai transfer'
  },
  'rules.stepsOverLimit': {
    AppLang.tr:
        'Gün {day}: tahmini {estimate} adım, limit {limit}. Taksi veya aktivite azaltmayı düşünün.',
    AppLang.en:
        'Day {day}: about {estimate} steps estimated, limit {limit}. Consider a taxi or fewer activities.'
  },
  'rules.mustSeeUnassigned': {
    AppLang.tr: '"{place}" henüz günlük plana eklenmemiş.',
    AppLang.en: '"{place}" hasn\'t been added to any day yet.'
  },
  'rules.shinkansenUrgent': {
    AppLang.tr: 'Shinkansen rezervasyon penceresi geçti veya bugün son gün.',
    AppLang.en:
        'The Shinkansen booking window has closed, or today is the last day.'
  },
  'rules.shinkansenSoon': {
    AppLang.tr: 'Shinkansen rezervasyonuna {days} gün kaldı.',
    AppLang.en: '{days} days left to book the Shinkansen.'
  },
  'rules.hotelsMissing': {
    AppLang.tr: 'Henüz otel eklenmedi. Konaklama adımında en az bir otel ekle.',
    AppLang.en: 'No hotels added yet. Add at least one in the Stays step.'
  },
  'rules.hotelsIncomplete': {
    AppLang.tr: '{count} otel için şehir, ad veya açık adres eksik.',
    AppLang.en: '{count} hotel(s) are missing a city, name or full address.'
  },
  'rules.planEmpty': {
    AppLang.tr:
        'Plan günleri tamamen boş. Plan adımından gezi planını oluştur.',
    AppLang.en:
        'Your itinerary days are all empty. Build the plan from the Plan step.'
  },
  'rules.titleDefault': {
    AppLang.tr:
        'Plan başlığı varsayılan. Kendi başlığını yazmak istersen Başlık adımına dön.',
    AppLang.en:
        'Your plan still has the default title. Go back to the Title step to name it yourself.'
  },
  'xfer.mode.localTrain': {
    AppLang.tr: 'Yerel/hızlı tren',
    AppLang.en: 'Local / rapid train'
  },
  'xfer.mode.overnightBus': {
    AppLang.tr: 'Gecelik/otobüs',
    AppLang.en: 'Overnight bus'
  },
  'xfer.mode.regionalBus': {
    AppLang.tr: 'Şehirlerarası otobüs',
    AppLang.en: 'Intercity bus'
  },
  'xfer.mode.rentalCar': {AppLang.tr: 'Kiralık araç', AppLang.en: 'Rental car'},
  'xfer.tip.tokyoOsaka': {
    AppLang.tr:
        'IC kart yerine gişe/Smart-EX. JR Pass kullanılmaz Nozomi için.',
    AppLang.en:
        'Use a ticket window or Smart-EX instead of an IC card — the JR Pass isn\'t valid on the Nozomi.'
  },
  'xfer.tip.tokyoKyoto': {
    AppLang.tr:
        'Sabah erken Nozomi sefer aralıkları sık, oturma kolaylığı için ayırtılabilir.',
    AppLang.en:
        'Early-morning Nozomi departures are frequent; reserve a seat for an easy ride.'
  },
  'xfer.tip.tokyoHakone': {
    AppLang.tr: 'Hakone Free Pass al, gün boyu dağ ulaşımı dahil.',
    AppLang.en:
        'Get the Hakone Free Pass — it covers mountain transport all day.'
  },
  'xfer.tip.osakaKyoto': {
    AppLang.tr: 'IC kart (Suica/Icoca) ile bin, ek bilet gerekmez.',
    AppLang.en:
        'Just tap in with an IC card (Suica/Icoca) — no extra ticket needed.'
  },
  'xfer.tip.train': {
    AppLang.tr: 'Daha ucuz, sürelidir. IC kart yeter.',
    AppLang.en: 'Cheaper but slower. An IC card is all you need.'
  },
  'xfer.tip.bus': {
    AppLang.tr: 'Ucuz ama 8+ saat sürer. Willer Express popüler.',
    AppLang.en: 'Cheap but takes 8+ hours. Willer Express is popular.'
  },
  // --- Bagaj lojistiği (v3): şehir geçişi günü bagaj adımları ---
  'luggage.step.coinLocker': {
    AppLang.tr: 'İstasyonda bagaj dolabına bırak',
    AppLang.en: 'Store bags in a station coin locker'
  },
  'luggage.tip.coinLocker': {
    AppLang.tr:
        'Büyük göz bulmak için ~20 dk ayır; IC kart ya da bozuk para hazır olsun.',
    AppLang.en:
        'Allow ~20 min to find a large bay; have an IC card or coins ready.'
  },
  'luggage.step.hotelEarlyDrop': {
    AppLang.tr: 'Otele erken bagaj bırak',
    AppLang.en: 'Drop bags at the hotel early'
  },
  'luggage.tip.hotelEarlyDrop': {
    AppLang.tr:
        'Check-in saatinden önce resepsiyon bagajı alır; odaya çıkmak gerekmez.',
    AppLang.en:
        'Reception holds bags before check-in time; no need to access the room.'
  },
  'luggage.step.hotelCheckIn': {
    AppLang.tr: 'Otele giriş yap',
    AppLang.en: 'Check in at the hotel'
  },
  'luggage.tip.hotelCheckIn': {
    AppLang.tr: 'Check-in penceresi açık — doğrudan odaya çıkabilirsin.',
    AppLang.en: 'The check-in window is open — you can go straight to the room.'
  },
  'luggage.step.yamato': {
    AppLang.tr: 'Bagajı kargoya ver (Yamato)',
    AppLang.en: 'Forward bags by courier (Yamato)'
  },
  'luggage.tip.yamato': {
    AppLang.tr:
        'Bagaj ertesi gün otele ulaşır. Bir gecelik çantayı yanında tut.',
    AppLang.en:
        'Bags arrive at the hotel the next day. Keep an overnight bag with you.'
  },
  'xfer.tip.regionalBus': {
    AppLang.tr: 'Doğrudan sefer ve bagaj koşullarını operatörden doğrula.',
    AppLang.en:
        'Confirm the direct service and luggage rules with the operator.'
  },
  'xfer.tip.car': {
    AppLang.tr: 'Uluslararası ehliyet gerekir. Kırsalda mantıklı.',
    AppLang.en: 'Requires an international license. Makes sense in rural areas.'
  },
  'xfer.tip.shinkansen': {
    AppLang.tr: 'JR Pass geçmez Nozomi\'de; Smart-EX kullan.',
    AppLang.en: 'The JR Pass isn\'t valid on the Nozomi — use Smart-EX.'
  },
  'tmpl.tokyoArrival.label': {
    AppLang.tr: 'Varış günü',
    AppLang.en: 'Arrival day'
  },
  'tmpl.tokyoArrival.theme': {
    AppLang.tr: 'Tokyo\'ya varış & check-in',
    AppLang.en: 'Arrival in Tokyo & check-in'
  },
  'tmpl.asakusaSkytree.label': {
    AppLang.tr: 'Asakusa + Skytree',
    AppLang.en: 'Asakusa + Skytree'
  },
  'tmpl.asakusaSkytree.theme': {
    AppLang.tr: 'Asakusa & Skytree',
    AppLang.en: 'Asakusa & Skytree'
  },
  'tmpl.shibuya.label': {AppLang.tr: 'Shibuya günü', AppLang.en: 'Shibuya day'},
  'tmpl.shibuya.theme': {
    AppLang.tr: 'Shibuya & Harajuku',
    AppLang.en: 'Shibuya & Harajuku'
  },
  'tmpl.disney.label': {AppLang.tr: 'Disneyland', AppLang.en: 'Disneyland'},
  'tmpl.disney.theme': {
    AppLang.tr: 'Tokyo Disneyland',
    AppLang.en: 'Tokyo Disneyland'
  },
  'tmpl.teamlabDay.label': {AppLang.tr: 'teamLab', AppLang.en: 'teamLab'},
  'tmpl.teamlabDay.theme': {
    AppLang.tr: 'teamLab Planets — ışık ve su',
    AppLang.en: 'teamLab Planets — light & water'
  },
  'tmpl.usjDay.label': {
    AppLang.tr: 'Universal Studios',
    AppLang.en: 'Universal Studios'
  },
  'tmpl.usjDay.theme': {
    AppLang.tr: 'Universal Studios Japan',
    AppLang.en: 'Universal Studios Japan'
  },
  'gen.coverage.parkLunch': {
    AppLang.tr: 'Park içinde öğle molası',
    AppLang.en: 'Lunch inside the park'
  },
  'gen.coverage.parkLunchDesc': {
    AppLang.tr: 'Restoranlar sıralı — 11:30 civarı git.',
    AppLang.en: 'Restaurants queue up — head there around 11:30.'
  },
  'gen.coverage.postDinner': {
    AppLang.tr: 'Çıkışta akşam yemeği',
    AppLang.en: 'Dinner after leaving'
  },
  'gen.coverage.postDinnerDesc': {
    AppLang.tr: 'Park çıkışı yakınında ramen/izakaya.',
    AppLang.en: 'Ramen or izakaya near the park exit.'
  },
  'gen.coverage.halfMorning': {
    AppLang.tr: 'Sabah gezisi',
    AppLang.en: 'Morning stroll'
  },
  'gen.coverage.halfMorningDesc': {
    AppLang.tr: 'Yakın bir tapınak veya sokak — teamLab öncesi hafif tempo.',
    AppLang.en: 'A nearby shrine or street — easy pace before teamLab.'
  },
  'tmpl.osakaMove.label': {
    AppLang.tr: 'Osaka geçiş',
    AppLang.en: 'Osaka transfer'
  },
  'tmpl.osakaMove.theme': {
    AppLang.tr: 'Osaka & Dotonbori',
    AppLang.en: 'Osaka & Dotonbori'
  },
  'tmpl.kyotoDay.label': {
    AppLang.tr: 'Kyoto günübirlik',
    AppLang.en: 'Kyoto day trip'
  },
  'tmpl.kyotoDay.theme': {
    AppLang.tr: 'Kyoto & Fushimi Inari',
    AppLang.en: 'Kyoto & Fushimi Inari'
  },
  'tmpl.naraDay.label': {
    AppLang.tr: 'Nara günübirlik',
    AppLang.en: 'Nara day trip'
  },
  'tmpl.naraDay.theme': {AppLang.tr: 'Nara turu', AppLang.en: 'Nara tour'},
  'gen.tip.cultureEarly': {
    AppLang.tr: 'Sabah erken gitmek kalabalığı azaltır.',
    AppLang.en: 'Going early helps you beat the crowds.'
  },
  'gen.tip.foodMeal': {
    AppLang.tr: 'Öğle veya akşam için ideal.',
    AppLang.en: 'Ideal for lunch or dinner.'
  },
  'gen.meal.lunchBreak': {
    AppLang.tr: 'Öğle yemeği molası',
    AppLang.en: 'Lunch break'
  },
  'gen.meal.lunchStop': {AppLang.tr: 'Öğle molası', AppLang.en: 'Lunch stop'},
  'gen.meal.lunch': {AppLang.tr: 'Öğle yemeği', AppLang.en: 'Lunch'},
  'gen.meal.dinner': {AppLang.tr: 'Akşam yemeği', AppLang.en: 'Dinner'},
  'gen.meal.ramen': {AppLang.tr: 'Ramen molası', AppLang.en: 'Ramen stop'},
  'gen.meal.conveyorSushi': {
    AppLang.tr: 'Conveyor sushi',
    AppLang.en: 'Conveyor-belt sushi'
  },
  'gen.meal.yakitori': {
    AppLang.tr: 'Yakitori izakaya',
    AppLang.en: 'Yakitori izakaya'
  },
  'gen.meal.konbiniBento': {
    AppLang.tr: 'Konbini bento',
    AppLang.en: 'Konbini bento'
  },
  'gen.meal.japaneseCurry': {
    AppLang.tr: 'Japon curry',
    AppLang.en: 'Japanese curry'
  },
  'gen.mealTip.ramen': {
    AppLang.tr:
        'Tonkotsu veya shoyu — Ichiran, Ippudo, Afuri gibi zincirlerden biri.',
    AppLang.en: 'Tonkotsu or shoyu — try a chain like Ichiran, Ippudo or Afuri.'
  },
  'gen.mealTip.conveyorSushi': {
    AppLang.tr: 'Sushiro / Kura Sushi — uygun fiyatlı, çocuk dostu.',
    AppLang.en: 'Sushiro / Kura Sushi — affordable and kid-friendly.'
  },
  'gen.mealTip.yakitori': {
    AppLang.tr: 'Tori-kizoku zinciri ya da Omoide Yokocho ara sokakları.',
    AppLang.en: 'The Tori-kizoku chain or the back alleys of Omoide Yokocho.'
  },
  'gen.mealTip.konbiniBento': {
    AppLang.tr: 'Family Mart / Lawson — taze onigiri & bento, hızlı seçenek.',
    AppLang.en: 'Family Mart / Lawson — fresh onigiri & bento, a quick option.'
  },
  'gen.mealTip.japaneseCurry': {
    AppLang.tr: 'CoCo Ichibanya — acılığı + topping seçilebilir.',
    AppLang.en: 'CoCo Ichibanya — choose your spice level and toppings.'
  },
  'gen.arrival.checkinTitle': {
    AppLang.tr: 'Varış & check-in',
    AppLang.en: 'Arrival & check-in'
  },
  'gen.arrival.checkinDesc': {
    AppLang.tr: 'Otele yerleş, jet lag için hafif tempo.',
    AppLang.en: 'Settle into the hotel; keep it light for jet lag.'
  },
  'gen.arrival.exploreTitle': {
    AppLang.tr: 'Çevre keşfi & konbini',
    AppLang.en: 'Explore nearby & konbini'
  },
  'gen.arrival.exploreDesc': {
    AppLang.tr: 'Yakın çevrede kısa yürüyüş, akşam atıştırmalığı.',
    AppLang.en: 'A short walk nearby and an evening snack.'
  },
  'gen.arrival.cityTheme': {
    AppLang.tr: '{city} · Varış & yerleşme',
    AppLang.en: '{city} · Arrival & check-in'
  },
  'gen.arrival.airportTitle': {
    AppLang.tr: 'Havaalanına iniş',
    AppLang.en: 'Landing at the airport'
  },
  'gen.arrival.airportDesc': {
    AppLang.tr: 'Immigration, bagaj ve SIM/eSIM aktivasyonu.',
    AppLang.en: 'Immigration, luggage, and SIM/eSIM setup.'
  },
  'gen.arrival.transferTitle': {
    AppLang.tr: 'Otele transfer',
    AppLang.en: 'Transfer to the hotel'
  },
  'gen.arrival.transferDesc': {
    AppLang.tr:
        'Airport Limousine ya da ekspres trenle otele (Narita Express, Haruka…).',
    AppLang.en:
        'Airport Limousine or express train to the hotel (Narita Express, Haruka…).'
  },
  'gen.transfer.summary': {
    AppLang.tr: '{arrival} varış · {minutes} dk · {modes}',
    AppLang.en: 'Arrive {arrival} · {minutes} min · {modes}'
  },
  'gen.arrival.lightDinnerTitle': {
    AppLang.tr: 'Hafif akşam yemeği',
    AppLang.en: 'Light dinner nearby'
  },
  'gen.arrival.lightDinnerDesc': {
    AppLang.tr: 'Otele yakın ramen ya da konbini — jet lag için ağır olmasın.',
    AppLang.en: 'Ramen or konbini near the hotel — go easy on the jet lag.'
  },
  'gen.tempoLabel': {AppLang.tr: 'tempo', AppLang.en: 'pace'},
  'gen.departure.theme': {
    AppLang.tr: 'Ayrılış & havaalanı',
    AppLang.en: 'Departure & airport'
  },
  'gen.departure.tag': {AppLang.tr: 'Ayrılış', AppLang.en: 'Departure'},
  'gen.departure.checkoutTitle': {
    AppLang.tr: 'Check-out & valiz',
    AppLang.en: 'Check-out & luggage'
  },
  'gen.departure.transferTitle': {
    AppLang.tr: 'Havaalanı transferi',
    AppLang.en: 'Airport transfer'
  },
  'gen.departure.transferDesc': {
    AppLang.tr: 'Tren veya taksi — uçuş saatine göre erken çık.',
    AppLang.en: 'Train or taxi — leave early depending on your flight time.'
  },
  'gen.departure.flightTitle': {
    AppLang.tr: 'Dönüş uçuşu',
    AppLang.en: 'Return flight'
  },
  'gen.departure.atAirportTitle': {
    AppLang.tr: 'Havaalanında',
    AppLang.en: 'At the airport'
  },
  'gen.departure.atAirportDesc': {
    AppLang.tr: 'Check-in, bagaj ve güvenlik.',
    AppLang.en: 'Check-in, luggage, and security.'
  },
  'gen.departure.highlightTitle': {
    AppLang.tr: 'Ayrılış günü',
    AppLang.en: 'Departure day'
  },
  'gen.departure.highlightBody': {
    AppLang.tr: 'Havaalanına en az 2–3 saat önce varın.',
    AppLang.en: 'Arrive at the airport at least 2–3 hours early.'
  },
  'gen.highlight.featured': {AppLang.tr: 'Öne çıkan', AppLang.en: 'Highlights'},
  'gen.fill.mealDesc': {
    AppLang.tr: 'Hızlı, yerel bir mola.',
    AppLang.en: 'A quick, local bite.'
  },
  'gen.fill.neighborhoodWalk': {
    AppLang.tr: 'Mahalle yürüyüşü',
    AppLang.en: 'Neighborhood walk'
  },
  'gen.fill.popularStop': {
    AppLang.tr: '{city} bölgesinde popüler durak.',
    AppLang.en: 'A popular stop in the {city} area.'
  },
  'gen.fill.freeExplore': {
    AppLang.tr: 'Bölgede serbest keşif.',
    AppLang.en: 'Free exploration around the area.'
  },
  'gen.fill.exploreDay': {
    AppLang.tr: '{city} keşif günü',
    AppLang.en: '{city} exploration day'
  },
  'wx.clear': {AppLang.tr: 'Açık', AppLang.en: 'Clear'},
  'wx.partlyCloudy': {
    AppLang.tr: 'Parçalı bulutlu',
    AppLang.en: 'Partly cloudy'
  },
  'wx.fog': {AppLang.tr: 'Sisli', AppLang.en: 'Foggy'},
  'wx.rain': {AppLang.tr: 'Yağmurlu', AppLang.en: 'Rainy'},
  'wx.snow': {AppLang.tr: 'Karlı', AppLang.en: 'Snowy'},
  'wx.showers': {AppLang.tr: 'Sağanak', AppLang.en: 'Showers'},
  'wx.thunderstorm': {AppLang.tr: 'Gök gürültülü', AppLang.en: 'Thunderstorm'},
  'wx.unknown': {AppLang.tr: 'Bilinmiyor', AppLang.en: 'Unknown'},
  'wx.high': {AppLang.tr: 'En yüksek', AppLang.en: 'High'},
  'wx.low': {AppLang.tr: 'En düşük', AppLang.en: 'Low'},
  'wx.precip': {AppLang.tr: 'Yağış olasılığı', AppLang.en: 'Precipitation'},
  'wx.close': {AppLang.tr: 'Kapat', AppLang.en: 'Close'},

  // ===== City discovery card (Wave 4 polish) =====
  'cityCard.visitedCount': {
    AppLang.tr: '{done}/{total} gezildi',
    AppLang.en: '{done}/{total} visited'
  },
  'cityCard.visited': {AppLang.tr: 'gezildi', AppLang.en: 'visited'},
  'cityCard.detecting': {AppLang.tr: 'algılanıyor…', AppLang.en: 'detecting…'},
};
