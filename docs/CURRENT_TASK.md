# CURRENT_TASK.md — Bugünün İşi

> Bu dosya *bugünkü* çalışmanın canlı görünümüdür. Her tamamlanan görevden
> hemen sonra güncellenir.

**Bugünün tarihi:** 2026-08-03
**Aktif branch:** `main`
**Sprint hedefi:** Rota optimizasyonu iyileştirme planının Faz 0–5 çekirdek
domain, harness schema v2, kalite kapısı ve AI-maliyet sınırlarını tamamlamak.

---

## Aktif Hedef

Rota schema v2, cross-day assignment, priority-aware dropping, bağımsız hard
validator, timeline/wait/free-time ayrımı, kişi/grup maliyeti, luggage state,
transfer timeline, yön/time-slice estimated matris ve paired profil suite
uygulandı. POI keşfi gerektiğinde kullanıcı onaylı tek AI batch + cache;
optimum rota hesabı yerel deterministik motor olarak ayrıldı. Statik analiz
temiz; 100 base × 4 profil ürün kalite kapısının bütün maddeleri geçti.

## Tamamlananlar (bu ve önceki oturumlardan)

- ✅ **2026-08-03** Rota optimizasyon v2 Faz 0–5 çekirdek değişiklikleri:
  schema v2 + semantic determinism, `TripActivityAssignmentEngine`,
  `RouteOptimizationValidator`, enum priority/structured drop, transit
  wait–idle–freeTime ayrımı, return timeline, kişi/grup/araç maliyeti,
  `LuggageState`, transfer penceresi ve directional/time-slice estimated
  harness matrisi. 100 base × 4 paired profile benchmark hard/duplicate/
  must-do/return/estimated-warning kontrollerinde sıfır ihlal üretti; beam 6
  varsayılan kaldı. AI yalnız gerektiğinde onaylı/cache'li POI keşfi için tek
  batch; rota hesabı saf Dart.

- ✅ **2026-08-03** Final ürün benchmark'ı (seed `20260803`, beam 6): 100 gezi
  ve dört eş profilde 4.672 gün kaydı; 0 hard ihlal, 0 tekrar, 0 must-do
  düşürme, 0 eksik dönüş, 0 açıklanmamış uzun boşluk ve 0 infeasible gün.
  Düşürme oranı %1,77; cluster re-entry %0,94, Kyoto %0. En hızlı profil en
  kısa süreyi, az yürüyüş profili en az yürüyüşü, en ucuz profil en düşük grup
  maliyetini verdi. Aynı öncelikte öğün koruması için regresyon testi eklendi;
  rota prompt kalite eşiği yeniden geçti. `flutter analyze --no-pub` temiz.

- ✅ **2026-08-03** `japan-reels-maker` proje dizini
  `rotori-social/japan-reels-maker` altına taşındı ve nested `.git`
  kaldırıldı. Böylece geçerli tek repository kökü `rotori-app/.git` oldu.

- ✅ **2026-08-03** Rota harness P0 doğruluk fixleri (`ROUTE_OPTIMIZATION_FIX_PLAN.md`
  Faz 1) çekirdeğe dokunmadan uygulandı: (1) yemek yeri çalışma saatleri
  korunuyor — `MealPeriod` + `servesMeal`, market'ler yalnız öğle, her şehre
  akşam servisi veren gerçek lokantalar + sentetik fallback+warning; (2) tam
  gün/uzak gezi izolasyonu `PoiDayRole` ile magic number'dan kurtarıldı ve
  refill sonrası çalışıyor (USJ/DisneySea/Miyajima artık başka POI ile
  karışmıyor); (3) <50 m co-located leg sıfırlandı (yapay kahvaltı yürüyüşü
  gitti). Ölçülen: kapalı-market akşam yemeği 0, walk>0 kahvaltı 0, park/Miyajima
  karışması 0, düşürülen aktivite 365→218. `test/tool/route_opt_harness_test.dart`
  9 test yeşil; `flutter analyze` (harness) 0 error.


- ✅ **2026-08-02** Canlı kamera para birimi çevirici (`live_currency_scanner`)
  uçtan uca eklendi: cihaz-üstü OCR (ML Kit, web'de no-op koşullu export),
  saf-Dart normalizer/parser/tracker/coordinate-transformer/converter,
  Supabase `exchange_rates` migration'ı (0006, herkese-okuma RLS, istemci
  yazamaz), SharedPreferences kur cache + manuel kur, ayarlar ekranı
  (hedef para birimi, otomatik güncelleme, kart farkı, yuvarlama, performans
  profili), Apple-kalite kamera overlay + izin/hata ekranları, TR/EN i18n,
  iOS `NSCameraUsageDescription` güncellemesi + Android `CAMERA` izni.
  `flutter analyze` temiz; 60 yeni test yeşil.

- ✅ **2026-08-02** Rütbe kanjileri için Noto Sans JP alt-kümesi (subset) fontu
  eklendi. Yalnızca kullanılan 11 glif (狸狐河童天狗鶴麒麟鳳凰龍旅) alınıp 700
  ağırlığa sabitlenerek `assets/fonts/NotoSansJP-Rank.ttf` (~5.9 KB) üretildi;
  `NotoSansJPRank` ailesi olarak `pubspec.yaml`'a kaydedildi ve madalyon /
  kutlama / drawer marka (旅) metinlerine uygulandı. Web'deki "Could not find a
  set of Noto fonts" uyarısı çözüldü; kanji tüm platformlarda net render edilir.
- ✅ **2026-08-02** Keşif haritasına Ghibli esintili rütbe-atlama kutlaması
  eklendi: XP ile rütbe kademesi arttığında yumuşak sıcak ışık, yukarı süzülen
  toz zerreleri (susuwatari) + altın parıltı ve nazikçe beliren ışıklı madalyon
  gösterilir; `HapticFeedback.mediumImpact` ile eşlenir, ~2.8 sn sonra
  kendiliğinden kapanır (dokunarak da kapanır). Açılışta tetiklenmez —
  yalnızca gerçek rütbe artışında. `flutter analyze` temiz, qa geçti.

- ✅ **2026-08-02** Keşif haritası (`reward_map_screen.dart`) baştan tasarlandı:
  XP odaklı "Gezgin rütbesi" — 狸 Tanuki → 龍 Ryū 8 kademeli Japon efsane
  yaratıkları merdiveni (her 100 XP bir rütbe, `xpToLevel` ile birebir).
  Degrade kanji madalyonu + romaji/anlam + toplam XP + sonraki rütbeye kalan
  XP çubuğu; keşif metrik şeridi; sakin konum-takibi ipucu ve kartı;
  aktivite rozetleri pasif liste görünümü. `CityCard` yeniden yazıldı —
  ViewerPalette uyumlu, gezilmemiş noktalar pasif halka, gezilen yeşil onay,
  tespit amber; tabular figürlerle hizalı sayılar. `flutter analyze` temiz,
  qa_scenarios (TR/EN rütbe anahtarları dahil) geçti.

- ✅ **2026-08-01** Boş uçuş/otel bölümleri pasif collapsible yerine
  planlayıcının düzenleme adımına götüren dokunulabilir `_DrawerAddCard`
  ile değiştirildi (`drawer.flights.add` / `drawer.hotels.add` / `drawer.add.hint`).
- ✅ **2026-08-01** Panel bilgi hiyerarşisi sadeleştirildi: "Bug bildir"
  ARAÇLAR'dan HESAP grubuna alındı; ARAÇLAR yalnızca sık kullanılan
  Hatırlatmalar/Tema/Google Maps'i tutuyor.
- ✅ **2026-08-01** `plan_viewer_screen.dart` 7125 → 5626 satıra indi: sandvich
  drawer widget ailesi (~1500 satır) davranış birebir korunarak
  `widgets/plan_viewer_drawer.dart` part dosyasına taşındı. `part of` ile
  private erişim ve paylaşılan importlar aynen sürüyor; `flutter analyze`
  temiz, test farkı yok (mevcut edit-mode/checklist hataları değişiklikten
  önce de vardı).
- ✅ **2026-08-01** Viewer hamburger (sandvich) paneli görsel olarak yenilendi:
  `assets/images/hamb-menu-top-bg.png` hero görseli `cover` + okunabilirlik
  scrim'i + palete akan alt gradyanla üst başlığa yerleştirildi; marka rozeti
  gölge/halka ile fotoğrafın üstünde okunur oldu, cam efektli kapatma düğmesi
  eklendi. Yolculuk özet kartı başlık/badge tekrarından arındırılıp sade üç
  metrik şeridine indirildi. `flutter analyze` temiz; qa_scenarios geçti.

- ✅ **2026-08-01** Uygulama kabuğu `AppTheme.light`, viewer yeni kurulum
  varsayılanı `appleLight` oldu; kaydedilmiş `viewer:theme` tercihi korunuyor.
- ✅ **2026-08-01** Hamburger menüsü küçülten `FittedBox` yapısından çıkarılıp
  Yolculuk/Keşfet/Araçlar/Hesap hiyerarşisi, iki sütunlu hızlı aksiyonlar,
  gruplanmış ayar satırları ve gerçek küçük-ekran kaydırmasıyla yenilendi.
- ✅ **2026-08-01** TR/EN menü anahtarları ve tema/menu regresyonları eklendi;
  `flutter analyze` temiz, hedefli tema ve drawer testleri başarılı. Çalışan
  Chrome Flutter oturumu hot restart ile güncellendi.
- ✅ **2026-07-22** Marka ismi Rotori olarak rebrand + sitede/uygulamada
  tutarlı hale getirildi (`360e5ae`).
- ✅ **2026-07-29** Mobil planner/viewer refaktörü ve site cilası commit edilip
  gönderildi (`f9b1207`).
- ✅ **2026-07-29** Hero görseli `rotori-hand-mobile.svg` adıyla yayın asset'i
  olarak sabitlendi (`4c0f735`).
- ✅ **2026-07-30** Hero “Planla / Yolculuk / Sahada” öğeleri erişilebilir
  bölüm bağlantılarına dönüştürüldü; aktif durum ve kaydırma doğrulandı.
- ✅ **2026-07-30** Altı Japonca kategori uygulamadaki yerel MP3'lere bağlandı;
  oynat/durdur, kategori seçimi, TR/EN metinleri ve romaji görünümü doğrulandı.
- ✅ **2026-07-30** Site genelindeki TR/EN pazarlama metinleri baştan sona
  gözden geçirildi; belirsiz vaatler somut fayda ve gizlilik açıklamalarıyla
  değiştirildi.
- ✅ **2026-07-30** Hero el ve telefon SVG'si masaüstünde %40 büyütüldü;
  Japonca cümle kartı %40 küçültüldü ve sesler 0,78× hızda oynatıldı.
- ✅ **2026-07-30** Hero sahnesi referanstaki merkez telefon, iki yandaki
  katmanlı bildirimler ve görsele binen koyu aşama çubuğuyla yeniden düzenlendi.
- ✅ **2026-07-30** Güven kartları geniş ekranda 6×1, orta ekranda 3×2,
  mobilde 1×6 olacak şekilde dengelendi.
- ✅ **2026-07-30** Alışveriş ses örneği “Kaado wa tsukaemasu ka?” /
  “Kart kullanabilir miyim?” cümlesi ve eşleşen MP3 ile değiştirildi.
- ✅ **2026-07-30** Hero sahnesi 1.600 px maksimum genişlikte ortalandı;
  2.048 px ekranda iki yanda 224 px, mobilde 36 px güvenli boşluk doğrulandı.
- ✅ **2026-07-30** Referans site oranına göre hero sahnesi 1.400 px'e,
  el/telefon 520 px'e ve bildirim kartları 460 px'e indirildi; sahne yüksekliği
  901 px'den 759 px'e düşürüldü.
- ✅ **2026-07-30** Hero sahnesi en fazla 1.120 px ve ekranın %84'ü olacak
  şekilde daraltıldı; el/telefon 460 px, bildirim kartları en fazla 400 px oldu.
- ✅ **2026-07-30** Hero sahnesindeki sağ bildirim kartları telefona 75–86 px
  yaklaştırıldı; 1.280 px ve 1.024 px genişliklerde yatay taşma olmadığı
  doğrulandı.
- ✅ **2026-07-30** Hero bildirim kartları iki tarafta telefonun arkasına
  bitişecek biçimde içeri alındı; 1.280 px ve 1.024 px genişliklerde katmanlama
  ve yatay taşma kontrol edildi.
- ✅ **2026-07-30** Hero bildirimlerindeki başlık, alt açıklama ve zaman
  etiketleri TR/EN için kelime başları büyük olacak biçimde düzenlendi.
- ✅ **2026-07-30** Hero kartlarının dış boşluklarını kartları ayrı ayrı
  taşıyarak eşitleme denemesi yapıldı; kompozisyonu bozduğu için sonraki
  düzenlemede geri alınmasına karar verildi.
- ✅ **2026-07-30** Sol bildirimler, telefon/el ve sağ bildirimler tek bir
  görsel blok olarak ortalandı; merkez sapması 1.280 px ve 1.024 px
  genişliklerde 0 px, yatay taşma 0 px ölçüldü.
- ✅ **2026-07-30** `website/` altındaki tüm `teamLab` marka yazımları
  `TeamLab` olarak düzeltildi; TR/EN sözlüklerinde eski yazım kalmadı.
- ✅ **2026-07-30** Site değişiklikleri `japan-trip` (`da3a659`) ve yayın
  paketi `rotori-web` (`fa5d353`) depolarına gönderildi; Pi deploy'u
  tamamlandı, container healthy ve `https://rotori.app` HTTP 200 doğrulandı.
- ✅ **2026-07-22** Website F1 seti (privacy + support + footer link + copy
  tazeleme) — `08d7449`, `cbd592a`.
- ✅ **2026-07-22** F1 App Store hazırlığı: Info.plist, hesap silme, aydınlık
  mor tanıtım (`11f3541`).
- ✅ **2026-07-2x** Design System v2 devreye alındı (`4578280`).
- ✅ F2.0 test regresyonları çözüldü — `plan_viewer` + `day_map` (`70c82d2`).
- ✅ Daha önce: Supabase auth uçtan uca (`233a57e` · Google OAuth),
  QA framework 100 senaryo (`13969b9`, `888feb2`), viewer satır içi düzenleme
  (`e66429c`), top-down shinkansen planı (`c7ef17f`).
- ✅ **2026-07-30** Saf Dart `PlanScheduleEngine` ile gün içi/günler arası
  taşıma, yeniden sıralama, saat/süre, ekleme/silme, gün başlığı/tarihi ve gün
  sırası komutları tek immutable işlem hattında toplandı.
- ✅ **2026-07-30** Çakışma, o tarihte geçerli 30 dakikalık yemek boşluğu, gün sınırı, tekrar
  eden komut ve sabit rezervasyon kuralları typed failure'larla güvenceye
  alındı.
- ✅ **2026-07-30** Uçuş/varış, otel check-in/out ve satın alınmış biletler
  açık lock/capability metadatasıyla geriye uyumlu JSON modeline taşındı.
- ✅ **2026-07-30** `PlanEditSession` optimistic update, seri kayıt, yerel
  yazma hatasında rollback, undo ve remote snapshot yenilemesini uyguladı.
- ✅ **2026-07-30** Viewer'a uzun-bas drag/drop, gün hedefi vurgusu, kapalı
  günü bekleyince açma, sabit satır görünümü, haptic geri bildirim ve
  erişilebilir “güne taşı” alternatifi eklendi; planner aynı motora bağlandı.
- ✅ **2026-07-30** Küçük ekran ve dark mode web preview elle kontrol edildi.
  `flutter analyze` temiz, tam test paketi 370/370 başarılı.
- ✅ **2026-07-30** Osaka yer sayısı (9), toplam geofence koordinat kapsamı
  (52) ve ilgili testler güncel veriyle doğrulandı.
- ✅ **2026-07-30** Eski plandaki ilgisiz transfer/check-in çakışmasının
  akşam yemeğini 19:30'dan 18:30/17:30'a alma ve günler arası taşıma
  komutlarını engellemesi düzeltildi. Motor artık yalnızca yeni veya büyüyen
  zaman çakışmasını reddediyor.
- ✅ **2026-07-30** Demo üzerinde 17:30 saat kaydı, menüden 2. güne taşıma ve
  hedef günde 16:15'e yeniden saatleme elle doğrulandı. Menü ve uzun-bas
  drag/drop için widget regresyonları eklendi; `flutter analyze` temiz,
  tam paket 374/374 başarılı.
- ✅ **2026-07-30** Edit Engine ortak 15 dakikalık aktivite/yemek tamponuna
  geçirildi. Saat değişikliğinde seçilen aktivite korunup aynı günün devamı;
  günler arası taşımada kaynak ve hedef gün otomatik yeniden saatleniyor.
- ✅ **2026-07-30** 08:00–22:00 arasındaki 15 dakikalık slot ızgarası eklendi.
  Geçersiz saatler gri ve pasif; hedef günde boşluk yoksa kaydetme kapalı ve
  “Bu günde uygun zaman aralığı bulunamadı.” bilgisi gösteriliyor.
- ✅ **2026-07-30** Menüden taşıma ve uzun-bas drag/drop aynı uygun-saat
  seçimini açıyor; kenar sürüklemede auto-scroll, lift/gölge, hedef gün
  highlight ve haptic davranışları birlikte çalışıyor.
- ✅ **2026-07-30** Flight/Train Arrival ve Departure satırlarının eski
  planlarda da gün/saat/sıra/drag yetenekleri kapatıldı. Başarılı mutasyon
  sonrası undo yalnızca 5 saniyelik snackbar üzerinden sunuluyor.
- ✅ **2026-07-30** Yeni domain/widget regresyonları dahil `flutter analyze`
  temiz, tam mobil test paketi **380/380 başarılı**.
- ✅ **2026-07-30** Aksiyonlu snackbar'ın erişilebilirlik modunda süresiz açık
  kalması düzeltildi; uygulama tarafındaki zamanlayıcı undo yüzeyini her
  durumda 5 saniye sonunda kapatıyor.
- ✅ **2026-07-30** Viewer hamburger menüsünde konaklama sonrası içerik
  referansa göre yeniden sıralandı: üçlü metrikler, dört yuvarlak Keşfet
  kısayolu, dört satırlı Araçlar kartı, profil ve hesap/navigasyon işlemleri.
  Tema ve tüm rotayı Google Maps'te açma işlevleri ikincil satır olarak
  korundu.
- ✅ **2026-07-30** Hamburger menü web preview'de üst ve alt bölümleriyle
  görsel kontrol edildi; temiz hot restart sonrasında konsol hatası yok.
  `flutter analyze` temiz, güncel tam mobil paket **381/381 başarılı**.
- ✅ **2026-07-30** Günlük “Haritada gör” ekranında duraklar kırmızı numaralı
  noktalarla gösterilip beyaz konturlu kırmızı rota çizgisiyle birbirine
  bağlandı. Web preview'de görsel doğrulandı; `flutter analyze` temiz ve
  günlük harita widget testleri **4/4 başarılı**.
- ✅ **2026-07-30** Harita doğrudan URL ile açıldığında geri okunun tepkisiz
  kalması düzeltildi. Geçmiş yoksa ilgili plan görünümüne güvenli dönüş
  yapıyor; çalışan web preview üzerinde rota değişimi elle doğrulandı.
- ✅ **2026-07-30** Yönlü kapıdan kapıya rota matrisi, yedi ulaşım modu,
  deterministik fake repository ve sağlayıcıdan bağımsız backend gateway
  sözleşmesi eklendi; mobil uygulamaya API anahtarı konulmadı.
- ✅ **2026-07-30** Beam width 6 kullanan saf Dart optimizer; hard feasibility
  pruning, artımlı state, local swap/move, geri dönüş/küme/aktarma maliyetleri
  ve Balanced/Fastest/Least Walking/Cheapest profilleriyle tamamlandı.
- ✅ **2026-07-30** Tokyo, Osaka, 14:00 sabit rezervasyon, kapanış/minimum süre,
  otel dönüşü, ulaşım profili ve yönlü matris regresyonları eklendi.
- ✅ **2026-07-30** Rota cache anahtarı koordinat hassasiyeti, yön, ulaşım
  modu, gün tipi, zaman dilimi, profil ve sağlayıcıyı kapsayacak biçimde
  modellendi; primary/alternative/stale fallback ve typed failure eklendi.
- ✅ **2026-07-30** AI review policy, bütçe/model/token config'i, yapılandırılmış
  çıktı, scope doğrulama ve cache eklendi. Normal optimizasyonda AI çağrısı
  yok; AI hatası deterministik rotayı veya kaydı bozmuyor.
- ✅ **2026-07-30** Riverpod `PlanOptimizationController`, mevcut
  `TimelineItem` modelini adapter ile kullanarak eski/yeni metrik ön izlemesi,
  açık onay, vazgeçme ve plan-version/activity-hash sonuç cache'i sağladı.
- ✅ **2026-07-30** Birleştirilmiş rota optimizasyon çalışmasında
  `flutter analyze` temiz ve tam mobil test paketi **416/416 başarılı**.
- ✅ **2026-07-30** Viewer gün kartına “Rotayı optimize et” eylemi eklendi.
  Dengeli/En hızlı/Az yürüyüş/En ucuz profilleri, yükleme/hata durumları,
  Önce/Sonra ulaşım-yürüyüş-aktarma-maliyet karşılaştırması ve açık
  “Rotayı uygula / Vazgeç” onayı tek bottom sheet'te bağlandı.
- ✅ **2026-07-30** Optimizasyon sonucu onaydan önce kalıcı planı değiştirmiyor;
  onayda repository + edit session + home widget birlikte yenileniyor.
  Güvenilir koordinat veya route matrix yoksa plan korunup anlaşılır hata
  gösteriliyor. QA preview deterministik fake matrix ile elle doğrulandı.
- ✅ **2026-07-30** Web'de üst bar zilindeki üçüncü taraf ikon getter'ının
  oluşturduğu stack overflow Material ikonla giderildi. `flutter analyze`
  temiz, tam mobil test paketi **418/418 başarılı** ve temiz preview açılışında
  konsol hatası yok.
- ✅ **2026-07-30** Gelecekteki ilk gezi gününün bugünün saatine göre yanlışlıkla
  “geçmiş” sayılıp soluk gösterilmesi düzeltildi. Saat karşılaştırması artık
  yalnız plan tarihi bugünse çalışıyor; gelecek günün ilk aktivitesi doğru
  “Sıradaki” öğe oluyor. `flutter analyze` temiz, viewer testleri **19/19**
  başarılı.

## Kalanlar (kısa vadeli)

- [ ] Supabase Edge Function veya mevcut backend üzerinde gerçek route matrix
  gateway'ini uygula; sağlayıcı seçimi ve gizli anahtarlar sunucuda kalsın.
- [ ] Bellek içi rota/ön izleme cache'lerini cihazda kalıcı cache'e taşı.
- [ ] Planner içine görünür optimizasyon karşılaştırmasını ve günler arası
  taşımada iki-günlük atomik coğrafi ön izlemeyi bağla.
- [ ] Büyük Japonya istasyonları için tek merkezli metadata/tampon kaynağını
  backend route normalizasyonuna ekle.
- [ ] Kök `img/hand-mobile.svg` tasarım kaynak dosyasıdır. Yayında bunun
  `website/img/rotori-hand-mobile.svg` adlı kopyası kullanılır; kök kopya
  deploy paketine girmez.
- [ ] Supabase Auth "Confirm email" prod öncesi **aç** (hâlâ kapalı — `[[supabase-backend]]`).
- [ ] App Store submission checklist — Sign in with Apple Services ID
  yapılandırması ($99/yıl Developer + Services ID) — `[[supabase-backend]]`.

## Bilinen Blocker'lar

- **Önceden var olan widget testi hataları** (bu oturumdan bağımsız, baseline
  `39ad0cb`'de de kırık): `test/features/viewer/plan_viewer_test.dart` edit-mode
  senaryoları (⋮ menü, geri al, hedef gün boşluğu, kilitli aktivite) ve
  `test/features/viewer/checklist_screen_test.dart` kategori render'ı ile
  welcome-flow görsel testleri. Drawer görsel/refactor çalışması bunları ne
  bozdu ne düzeltti; ayrı bir görev olarak ele alınmalı.

- Native `integration_test` koşusu için bağlı iOS/Android cihaz veya emulator
  yok. Web integration runner desteklenmiyor; macOS desktop hedefi projede
  yapılandırılmamış. Aynı kritik sözleşmeler normal Flutter test paketinde
  çalışıyor.
- Sunucuda plan revision/CAS alanı yok; aynı plan iki cihazda aynı anda
  değiştirilirse cihaz içi sıra ve dirty-cache korumasına rağmen son yazan
  kazanabilir.

## Sıradaki Uygulama Adımı

1. Route matrix backend/Edge Function sağlayıcısını ve merkezi büyük-istasyon
   metadata normalizasyonunu uygula.
2. Rota cache'ini kalıcılaştırıp API çağrı/hit-rate ölçümlerini gerçek
   sağlayıcı üzerinde doğrula.
3. Planner'a aynı karşılaştırma/onay yüzeyini bağla; günler arası taşımada iki
   günü tek ön izlemede göster.
4. Gerçek bir iOS cihaz veya simulator üzerinde offline→online cache/fallback
   ve sürükle-bırak sonrası yeniden optimizasyonu doğrula.

## Şu An Değişen Dosyalar

Başlangıçta kullanıcıya ait `docs/CLAUDE.md` değişikliği ve untracked kök
`img/` tasarım kaynağı vardı; ikisine de dokunulmadı. Bu görev kapsamında
domain motoru, edit session, viewer/planner, repository, l10n, testler ve
ilgili mimari belgelerdeki mevcut değişiklikler korunacaktır. Yeni rota
optimizasyonu bu dirty worktree üzerinde yeni izole domain/data/controller/test
dosyalarıyla eklendi; mevcut kullanıcı değişiklikleri geri alınmadı veya
üzerlerine yazılmadı.

## Son Commit'ler (referans)

```
4578280 feat(website): baştan aşağı revizyon — Design System v2
70c82d2 fix(test): plan_viewer + day_map regresyonlarını çöz — F2.0
cbd592a copy(website): 'Hesap gerekmez' → 'Ücretsiz · reklamsız'
08d7449 feat(website): Privacy Policy + Destek sayfaları + footer link
11f3541 feat(release+web): F1 App Store prep — Info.plist, hesap silme
```
