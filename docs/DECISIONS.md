# DECISIONS.md — Mühendislik Kararları

> Sadece **append**. Eski kayıt silinmez; yanlış çıkarsa altına yeni bir
> kayıt eklenir ve orijinali *supersedes* alanıyla bağlanır.

---

---

## 2026-08-03 — rotori-social içine `japan-reels-maker` taşıması tamamlandı

**Supersedes:** 2026-08-03 monorepo düzenleme kaydındaki
"`rotori-social/` şimdilik iskelet; kod ikinci iş olarak taşınacak" notu.

**Karar:** Kaynak proje dizini
`/Users/sevimm/Documents/Projects/japan-reels-maker`, monorepo içinde
`rotori-social/japan-reels-maker` altına taşındı.

**Git sınırı:** Taşıma sonrası nested repository etkisini kaldırmak için
`rotori-social/japan-reels-maker/.git` silindi. Böylece tek geçerli Git kökü
`rotori-app/.git` oldu.

**Neden:** Sosyal ayak kodunu monorepo içinde görünür kılıp ortak dokümantasyon,
issue takibi ve sürümleme akışını tek depoda toplamak.

**Etki:** `rotori-social/` artık yalnız README iskeleti değil; Python tabanlı
reels üretim projesinin kaynak kodunu içeriyor. Yerel geçici dosyalar proje
seviyesi `.gitignore` kurallarıyla dışarıda kalmaya devam eder.

---

## 2026-08-03 — Rota harness P0 doğruluk fixleri (yemek saatleri · gün rolü · zero-leg)

**Karar:** `ROUTE_OPTIMIZATION_FIX_PLAN.md` Faz 1 (P0) düzeltmeleri, saf Dart
optimizer çekirdeğine dokunmadan **yalnız harness veri/planlama katmanında**
uygulandı (`tool/route_opt_harness/`):

1. **Yemek yeri çalışma saatleri korunuyor.** `PoiSpec`'e `MealPeriod` (breakfast/
   lunch/dinner) ve `servesMeal(period, window, needed)` eklendi. Market türü
   yerler (Tsukiji 14:00, Nishiki/Kuromon 18:00) yalnız öğle işaretli; her şehre
   17:00–23:00 açık, akşam servisi veren gerçek lokantalar eklendi. Uygun yer
   yoksa gerçekçi saatli sentetik lokanta üretilir ve güne `warning` düşülür.
2. **Tam gün / uzak gezi POI izolasyonu magic number'dan kurtarıldı.** `PoiDayRole`
   (normal/halfDayAnchor/fullDayExclusive/excursion) eklendi. USJ/DisneySea
   `fullDayExclusive`, Miyajima `excursion`, Horyu-ji `halfDayAnchor`. İzolasyon
   kararı artık havuz refill'inden **sonra** çalışıyor; böylece refill ile gelen
   park başka noktalarla aynı güne karışmıyor. Full-day park yalnız gerçek tam
   güne izole edilir (kısa varış/transfer gününe konup düşürülmez); excursion her
   gün tipinde tek başına atanabilir.
3. **Co-located zero-leg.** Matrix builder <50 m mesafede 0 dakikalık leg üretir;
   otel kahvaltısı için baseline'daki yapay 3 dk'lık yürüyüş (toplam ~1.746 dk)
   sıfırlandı.

**Ölçülen etki** (aynı seed 20260803, 100 senaryo): kapalı-market akşam yemeği
`0`, walk>0 kahvaltı `0`, tema parkı günü karışması `0`, Miyajima karışması `0`.
Düşürülen aktivite `365 → 218` (−%40).

**Neden harness'te:** Bu bulgular test verisi kaynaklıydı; proje kararı gereği
çekirdek deterministik saf Dart kalır, harness sorunları çekirdeğe taşınmaz.

**Kalan (bu görevde yapılmadı):** Faz 0 schema-v2 envelope, Faz 2 günler-arası
`TripActivityAssignmentEngine` + priority-aware dropping, Faz 3 waiting/idle
ayrımı ve cluster re-entry sertleştirme, Faz 4 maliyet birimi/paired profiller,
Faz 5 transfer/bagaj/yönlü matris. Regresyon: `test/tool/route_opt_harness_test.dart`.



**Karar:** Repo kökü `japan-trip` → **`rotori-app`** olarak yeniden adlandırıldı
ve içerik üç ürün ayağına gruplandı:

- `rotori-mobile/` ← eski `mobile/` (Flutter kökü; `route_opt_scenarios.json` da
  buraya alındı).
- `rotori-website/` ← eski `website/` (Rotori tanıtım sitesi = birincil web
  yüzeyi, self-contained). Eski nesil React PWA + build zinciri
  (`index.html`, `apps/`, `packages/`, `api/`, `tools/`, `scripts/`, `data/`,
  `assets/`, `img/`, `package.json`) **`rotori-website/legacy/`** altına toplandı.
  `videos/` → `rotori-website/videos/`.
- `rotori-social/` ← şimdilik yalnızca iskelet + README. Kaynak proje
  (`japan-reels-maker`) hâlâ ayrı git reposunda ve arka planda çalıştığından
  **kod ikinci iş olarak** taşınacak.
- Paylaşılan `docs/` ve `supabase/` kök seviyede tutuldu.

**Vercel kaldırıldı:** `vercel.json` silindi. Site artık Vercel build/deploy
zincirine bağlı değil; `rotori-website/index.html` tek dosya self-contained.

**Neden:** Tek ürün "Rotori" — mobil, web ve sosyal ayakları tek monorepo'da,
net sınırlarla. İki `index.html` çakışması (tanıtım vs eski PWA rehber) `legacy/`
alt-klasörüyle çözüldü. Yol bağımlılığı düşük: `mobile/` yalnızca kendi içine,
`api/` → `tools/`'a (birlikte taşındı) bağlıydı; site self-contained.

**Etki / yapılacaklar:** `.gitignore` yolları, `legacy/package.json` adı
(`rotori-website-legacy`) ve `legacy/assets/appstore/build.mjs` önizleme yolu
güncellendi. Flutter tarafında ilk açılışta `flutter clean && flutter pub get`
(+ iOS `pod install`) önerilir.

---

## 2026-08-02 — Canlı kamera para birimi çevirici: cihaz-üstü OCR + saf-Dart pipeline

**Karar:** Yeni `live_currency_scanner` özelliği `mobile/lib/features/` altında
domain / application / infrastructure / presentation katmanlarıyla eklendi.
Kamera akışı `camera` paketiyle, OCR ise mevcut `google_mlkit_text_recognition`
ile **tamamen cihaz üstünde** çalışır. Para hesapları `decimal` paketiyle
(double kayması yok) yapılır. Route: `/live-currency-scanner`; viewer drawer'ın
KEŞFET ızgarasına 4. ikon olarak (`Icons.currency_yen_rounded`) eklendi.

**Neden:**
- Gizlilik: kamera görüntüsü sunucuya/Supabase'e **gönderilmez**, diske
  yazılmaz; OCR on-device. LLM/bulut görüntü analizi kullanılmaz.
- Mevcut mimariye uyum: OCR zaten `ticket_ocr` ile ML Kit kullanıyordu; aynı
  paket yeniden kullanıldı (Japonca script). Web'e sızmaması için
  `text_recognizer_factory.dart` koşullu export (mobil = ML Kit, web = no-op).
- Test edilebilirlik: normalizer, parser, tracker, coordinate transformer,
  converter ve exchange-rate repository saf Dart/enjekte edilebilir saat ile
  yazıldı — 60 birim/widget testi.

**OCR abstraction:** `OnDeviceTextRecognizer` arayüzü, ML Kit'i domain'den
izole eder; ileride paket değiştirilebilir. `CameraFramePreprocessor` benzeri
bir ön-işleme katmanı (OpenCV) **ilk sürümde eklenmedi** — gerçek doğruluk
sorunu ölçülene kadar gereksiz native bağımlılık ve boyut eklenmez.

**Kur akışı:** `exchange_rates` tablosu (Supabase) → repository → yerel cache
(SharedPreferences) → manuel kur. Öncelik: manuel > taze cache > remote;
offline'da son cache. Yazma yetkisi istemcide değil (RLS: herkese okuma,
yalnız service-role yazma). Fallback her zaman var; kamera ağ hatasında
tamamen hata durumuna düşmez.

**Performans:** OCR single-flight + `ScannerPerformanceProfile`
(batterySaver 500ms / balanced 300ms / highAccuracy 200ms); kareler kuyruğa
alınmaz, en güncel kare işlenir; overlay `PriceDetectionTracker` ile IoU +
merkez + exponential smoothing kullanarak titremez. Tüm eşikler
`ScannerTuning` içinde (magic number yok).

**Vergi:** 税込 (vergi dahil) ana gösterimde önceliklidir; yakın 税抜 çifti
oran + kutu yakınlığıyla eşleşince hariç fiyat ana gösterimden düşürülür.

**Trade-off / bilinen sınırlar:** ML Kit web'de yok (no-op recognizer); kamera
rotasyonu ilk sürümde sensör oryantasyonundan alınır (cihaz oryantasyonu tam
matris hesaplanmaz); native `integration_test` için bağlı cihaz yok. "Sistem
ayarlarını aç" için ekstra `permission_handler`/`app_settings` paketi
eklenmedi — kalıcı redde retry + yönlendirme metni gösterilir.

---

## 2026-07-22 — Marka: **Rotori** (Tabi'den rebrand)

**Karar:** Marka adı **Rotori** olarak sabitlendi. Uygulama title'ı
(`main.dart` → `title: 'Rotori'`), tanıtım sitesi (`website/index.html`) ve
metinler tutarlı hale getirildi.

**Neden:** "Tabi" (旅) Japonca köke bağlıydı ama global App Store aramasında
zayıf ayırt ediciydi; ayrıca Türkçe konuşurken "tabii" ile karışabiliyordu.
Rotori hem daha ayırt edici hem de "rota + tori (kuş)" çağrışımıyla ürünle
uyumlu.

**Alternatifler değerlendirilen:**
- Tabi (旅) — özgün ilk öneri
- Sakura Route
- Nihon Rota

**Trade-off'lar:** Tabi'nin Japonya-özgün semantik bağı kayboldu; Rotori
markasının kültürel bağı daha soft. Kabul edildi çünkü hedef pazar (Türk
gezginler) için "Japonya" zaten üründe zımnen var.

**Sonuç:** `[[launch-website-tabi]]` memory'sindeki "Tabi" adı artık
tarihsel. Site + uygulama Rotori. Commit izi: `360e5ae`.

---

## 2026-07-07 — React web'i **Flutter mobile'a 1:1 port** et

**Karar:** `apps/planner` + `apps/viewer` React uygulamaları Flutter tarafına
(`mobile/`) birebir taşındı. Mobil (iPhone-first) birincil ürün oldu.

**Neden:** App Store'da yer almak, offline harita/geofence gibi native yetenekler,
tek codebase'de iOS + web preview (via device_preview).

**Alternatifler:** React Native, Capacitor sarma, PWA-only devam.

**Trade-off'lar:**
- **Kazanç:** Native performans, offline-first, ML Kit OCR, App Store dağıtımı.
- **Kayıp:** Web tarafı bakım moduna geçti; iki paralel kod tabanı (kısa vadede).

**Sonuç:** `mobile/lib/domain/` `packages/shared/src/types.ts`'i aynalar;
domain saf Dart, `flutter analyze` 0 error hedefli.

---

## 2026-07-07 — Domain katmanı **saf Dart** (Flutter import etmez)

**Karar:** `mobile/lib/domain/*.dart` içindeki hiçbir dosya `flutter/*` veya
`supabase_flutter` import etmez.

**Neden:** Hızlı unit test, platformdan bağımsız iş kuralı, ileride başka
UI hedeflerine (macOS / desktop) taşınabilirlik.

**Alternatifler:** Widget'la iç içe domain — kısa vadede hızlı ama test edilemez.

**Sonuç:** `flutter test` altındaki 236+ test hızlı çalışıyor. Her yeni
domain dosyası testli girer (bkz. `day_schedule.dart` + testi).

---

## 2026-07-x — **Riverpod** + **go_router** kombinasyonu

**Karar:** State için `flutter_riverpod`, routing için `go_router`.

**Neden:** Riverpod compile-time güvenli, `AsyncNotifier` Supabase ile temiz
uyum; go_router deep-link + guard için modern.

**Alternatifler:** Bloc (fazla ceremony), Provider (state modelleri düşük),
auto_route (learning curve daha büyük).

**Sonuç:** `authProvider` → router guard zinciri kuruldu. Provider adları
`xxxProvider` konvansiyonu.

---

## 2026-07-x — **Supabase** (self-hosted değil, hosted)

**Karar:** Backend olarak Supabase (proje ref `vsclzcillbveregzsgmj`,
Tokyo bölgesi ap-northeast-1). Auth + `plans` + `profiles` + RLS.

**Neden:** Auth (email + Google + Apple), RLS ile satır seviyesi güvenlik,
Postgres, migration disiplini, storage bonus. Hosted olduğu için sunucu
bakımı yok — F1'de asıl mesele App Store'a çıkmak.

**Alternatifler:** Firebase (Google bağımlılığı + yeniden yazım), kendi Node/Postgres
(bakım yükü), Appwrite (olgunluk).

**Trade-off:** Tek satıcıya bağımlılık. Kabul, çünkü şema Postgres — ihraç
yolu açık.

**Prod öncesi zorunlu:** Supabase Auth "Confirm email" **açılacak** (şu an
test için kapalı — `mailer_autoconfirm:true`). Bu bir *unresolved decision*
olarak kalmalıdır.

---

## 2026-07-x — Tanıtım sitesi **tek dosya, self-contained**

**Karar:** `website/index.html` inline CSS/JS/SVG. Harici asset yok.

**Neden:** Basit deploy (rsync), CDN karmaşası yok, prompt-injection yüzeyi
minimal, çevrimdışı görüntülenebilir.

**Alternatifler:** Astro/Next tabanlı bir mikro-site.

**Trade-off:** Dosya büyür (~200 KB civarında). Kabul — hâlâ tek istek.

**Sonuç:** Design System v2 (`4578280`) aynı disiplinle geldi. `window.__i18nAudit()`
i18n bütünlüğünü doğruluyor.

---

## 2026-07-x — **i18n el yapımı** (`intl` codegen yerine)

**Karar:** `lib/core/l10n.dart` içinde manuel sözlük + `LText` inline.

**Neden:** Runtime dil switch'i (kullanıcı tercihini kalıcılaştır),
codegen aşamasız iterasyon, büyük içerik (city_places, place_guide) için
inline `LText(tr, en)` daha esnek.

**Alternatifler:** `intl` + arb + codegen — enterprise düzeyi ama iterasyon
maliyetli.

**Trade-off:** Anahtar kaçırma riski var — buna karşı `.__i18nAudit()`
(site) ve `flutter analyze`'in tetikleyeceği eksik anahtar hataları
kullanılıyor.

**Kabul edilen sınır:** Üretilen plan içeriği (itinerary_generator +
fillEmptyDays) *üretim anındaki dilde donar*; sonradan dil değişirse plan
yeniden çevrilmez.

---

## 2026-07-x — Web hedefi **conditional import ile graceful**

**Karar:** Mobil-only paketler (ML Kit OCR, `flutter_local_notifications`,
`flutter_cache_manager` file cache, `home_widget`) web build'ine sızmaz.
Her biri `kIsWeb` kapısı veya conditional import ile no-op'a düşer.

**Neden:** `preview_main.dart` ile web-preview üzerinden tasarım/QA yapılıyor;
build kırılmamalı.

**Alternatifler:** Web derlemesini bütünüyle kapatmak.

**Sonuç:** `data/ticket_ocr.dart` conditional import (`ticket_ocr_stub.dart` /
`ticket_ocr_mlkit.dart`). Home widget web'de sessizce düşer (`home_widget_hook.dart`).

---

## 2026-07-x — Harita: **OSM raster tile** + kendi cache

**Karar:** Harita için `flutter_map` + OSM raster tile. API key yok. Cache
`flutter_cache_manager` ile.

**Neden:** Ücretsiz, key yönetimi yok, çevrimdışı-öncelikli, App Store'da
key sızıntısı riski yok.

**Alternatifler:** Mapbox (key + fatura), Google Maps SDK (fatura + Apple
uyum çıtası).

**Trade-off:** Görsel kalite OSM'de. Kabul — plan yönlendirme + geofence için
yeterli.

---

## 2026-07-x — GPS keşif: dwell 600 s, grace 120 s, radius+min(accuracy,80)

**Karar:** Geofence tetiklemesi için dwell süresi 600 saniye, grace 120 saniye,
eşik `radius + min(accuracy, 80)` metre.

**Neden:** iPhone GPS aksürasi değişken; kısa dwell false-positive üretiyor,
uzun dwell UX'i öldürüyor. 600/120 kombinasyonu kullanıcı test'inde stabildi.

**Alternatifler:** iOS `CLRegion` (native geofence) — arka planda daha güçlü
ama Flutter köprü karmaşası.

**Sonuç:** `lib/features/viewer/geofence_service.dart` içinde. React tarafında
`apps/viewer/src/hooks/useGeofence.ts` matematiksel aynası — port doğrulandı.

---

## 2026-07-x — QA: **kod-içi senaryo dashboard'u**

**Karar:** Playwright/E2E harici bir framework yerine uygulama içinde bir QA
dashboard + `gps_sim_screen.dart` simülasyon aracı.

**Neden:** Flutter tek codebase; test framework fragmantasyonu istemedik;
gerçek widget davranışını doğrulamak native flutter test paketiyle daha hızlı.

**Alternatifler:** `integration_test` paketi + Playwright web.

**Sonuç:** 110 senaryo · 95 otomatik %100 pass (`888feb2`).

---

## 2026-07-29 — /docs mimarisi kalıcılaştırıldı

**Karar:** `docs/CLAUDE.md`, `docs/ARCHITECTURE.md`, `docs/CURRENT_TASK.md`,
`docs/DECISIONS.md` proje bilgi zeminini oluşturur. Her feature bitişinde
güncellenir; kod ve döküman uyumsuz kalırsa **önce döküman düzeltilir**.

**Neden:** Oturumlar arası bilgi kaybını engellemek. Memory sistemi (~/.claude)
oturum yardımcısıdır; repo içi `/docs` tek gerçek kaynağıdır.

**Alternatifler:** README genişletme, wiki, notion.

**Sonuç:** Bu dosya bugün eklendi. `PHASE2-ROUTING.md` (Haziran '26) tarihsel
referans olarak `docs/` altında kalır.

---

## 2026-07-30 — Tanıtım sitesi yerel medya asset'lerini destekler

**Supersedes:** 2026-07-x — Tanıtım sitesi **tek dosya, self-contained**

**Karar:** CSS ve JavaScript tek `website/index.html` dosyasında kalır; büyük
görsel ve sesler `website/img/` ile `website/audio/` altında yerel,
versiyonlanmış dosyalar olarak yayınlanabilir.

**Neden:** Hero illüstrasyonu ve gerçek Japonca MP3 örnekleri HTML içine
gömüldüğünde dosyayı gereksiz büyütüyor. Ayrı yerel asset'ler tarayıcı
önbelleğini ve ses akışını iyileştiriyor.

**Kısıt:** Üçüncü taraf CDN veya çalışma zamanı servisi yoktur. Site deploy'u
`website/` ağacını bütünüyle taşımalıdır; yalnızca `index.html` kopyalamak
artık yeterli değildir.

---

## 2026-07-30 — Plan düzenleme tek domain komut hattından geçer

**Karar:** Viewer ve planner'daki bütün plan mutasyonları saf Dart
`PlanScheduleEngine` komutlarıyla yapılır. Uçuş/varış, otel check-in/out ve
satın alınmış bilet kısıtları başlık/emoji tahminine bırakılmaz; `TimelineItem`
üzerinde geriye uyumlu lock ve capability alanlarıyla açıkça saklanır.

**Neden:** Widget içinde ayrı ayrı yapılan liste/saat mutasyonları çakışma,
veri kaybı ve iki ekran arasında farklı davranış üretiyordu. Immutable komut
sonucu aynı validasyonu planner, viewer ve unit testler için yeniden
kullanılabilir kılar.

**Kalıcılık:** `PlanEditSession` komutları cihaz içinde sıraya alır, UI'a
optimistic uygular, yerel yazma hatasında snapshot'ı geri yükler ve başarılı
işlemler için undo tutar. Dirty yerel snapshot realtime sunucu verisiyle
ezilmez.

**Alternatifler:** Her widget'ın kendi listelerini doğrudan değiştirmesi;
yalnızca repository seviyesinde validasyon; bütün günü her değişiklikte
yeniden üretmek.

**Trade-off:** Sunucuda revision/compare-and-swap alanı henüz yoktur; iki
cihazın aynı planı eşzamanlı düzenlemesi son-yazan davranışına düşebilir.
Gezi saatleri yerel duvar saati dakikalarıdır ve gece yarısını aşan tek
aktivite otomatik bölünmek yerine reddedilir.

---

## 2026-07-30 — Mevcut zaman çakışması ilgisiz düzenlemeyi engellemez

**Karar:** Plan düzenleme sırasında tarih, kimlik, süre, sabit saat ve gün
sınırı gibi yapısal invariant'lar her komutta eksiksiz doğrulanır. Zaman
çakışmalarında ise komut öncesi ve sonrası karşılaştırılır; yalnızca yeni
oluşan veya dakika olarak büyüyen çakışma reddedilir.

**Neden:** Eski veya generator kaynaklı bir transfer/check-in çakışması,
kendisiyle ilgisiz akşam yemeği saatini değiştirmeyi ve aktiviteyi başka güne
taşımayı tamamen kilitliyordu. Kullanıcı geçerli düzenlemeler yapabilmeli ve
planı adım adım iyileştirebilmelidir.

**Güvence:** Yeni çakışma oluşturmak hâlâ engellenir. Mevcut çakışma
küçültülebilir veya başka düzenlemeler yapılırken aynı seviyede kalabilir;
büyütülemez.

---

## 2026-07-30 — Edit slotları ortak 15 dakikalık tampon kullanır

**Supersedes:** 2026-07-30 — Plan düzenleme tek domain komut hattından geçer
kararındaki yemek için ayrı 30 dakikalık boşluk ayrıntısı.

**Karar:** Plan düzenleme sırasında bütün ardışık aktiviteler arasında 15
dakikalık minimum geçiş vardır. Yemek kategorisi de aynı 15 dakikalık
sonraki-aktivite tamponunu kullanır; ayrıca 30 dakikalık özel boşluk istemez.
Saat ve gün değiştirme yüzeyleri serbest metin veya tüm saatleri sunmak yerine
motorun hesapladığı uygun slotları gösterir; uygun olmayan slotlar gri ve
pasiftir.

**Taşıma:** Günler arası taşıma seçilen uygun başlangıç saatine yapılır.
Komut hem kaynak hem hedef günü yeniden optimize eder. Hedef günün aktivite
süresi ve 15 dakikalık görünmez tamponları içinde uygun slot yoksa plan
değişmez ve kullanıcıya “Bu günde uygun zaman aralığı bulunamadı.” bilgisi
verilir.

**UX:** Sabit uçuş ve tren varış/kalkışları gün, saat, sıra ve drag
yeteneklerini kapatır. Başarılı her mutasyon 5 saniyelik “Değişiklik
kaydedildi / Geri Al” snackbar'ı üretir.

---

## 2026-07-30 — Rota sırasını AI değil yönlü matris + deterministik motor belirler

**Karar:** Günlük coğrafi sıra ve ulaşım modu, gerçek kapıdan kapıya
alternatifler içeren yönlü `RouteMatrix` üzerinde çalışan saf Dart
`BeamSearchItineraryOptimizer` tarafından belirlenir. Varsayılan beam width
6'dır; arama sonrası sınırlı swap/move iyileştirmesi uygulanır. Sabit saat,
açılış-kapanış, minimum süre ve gün sonu kısıtları yüksek ceza yerine hard
failure/pruning üretir.

**Neden:** Eski `day_optimizer.dart` koordinat tabanlı nearest-neighbor
yaklaşımı nehir, büyük istasyon, aktarma ve kapıdan kapıya süre farklarını
bilemez. Dil modeli de bu verileri güvenilir biçimde üretemez. Rota matrisi
gerçek ulaşım verisini, deterministik motor ise tekrar üretilebilir ve test
edilebilir kararı sağlar.

**Ulaşım sağlayıcısı sınırı:** Flutter belirli harita sağlayıcısına veya API
anahtarına bağlanmaz. `RouteMatrixBackendGateway`, backend/Supabase Edge
Function tarafından uygulanır; anahtar sunucu ortamında tutulur. Fallback
sırası taze cache, birincil sağlayıcı, alternatif sağlayıcı, stale/estimated
cache ve typed unavailable'dır. Koordinat mesafesi yalnızca ön eleme/kümeleme
içindir; gerçek süre olarak kullanılamaz.

**AI sınırı:** AI varsayılan olarak çağrılmaz ve rotayı değiştiremez.
`CostOptimizedAiUsagePolicy` yalnızca kullanıcı açıklama istediğinde, güven
düşük olduğunda veya açık bir uyarı/anomali bulunduğunda yapılandırılmış review
çağrısına izin verir. Bütçe, model adı, token sınırı ve cache tek merkezden
yönetilir. AI hatası deterministik planı engellemez.

**Trade-off:** Gerçek route gateway henüz yapılandırılmadığı için üretim
provider'ı typed unavailable döndürür; cache'ler ilk sürümde bellek içidir.
Bu sınırlar bilinçli olarak kabul edildi: önce sağlayıcıdan bağımsız domain
sözleşmesi, testler ve Flutter ön izleme/onay akışı tamamlandı. Kalıcı cache,
Edge Function ve görünür son kullanıcı optimizasyon yüzeyi sonraki entegrasyon
adımıdır.

---

## 2026-08-01 — Yeni kurulum aydınlık tema ve görev odaklı viewer menüsüyle açılır

**Karar:** Uygulama kabuğunun varsayılanı `AppTheme.light`, viewer tema
tercihinin kayıtsız varsayılanı `appleLight` olarak değiştirildi. Mevcut
`viewer:theme` değeri aynen yüklenir; bu nedenle daha önce koyu veya Sakura
tema seçmiş kullanıcıların tercihi değiştirilmez.

Viewer hamburger menüsü sabit yüksekliğe sığdırılan `FittedBox` düzeninden
çıkarıldı. İçerik gerçek kaydırma içinde **Yolculuk → Keşfet → Araçlar →
Hesap** sırasını izler. Uçuş ve otel ayrıntıları açılabilir kalır; sık kullanılan
dört keşif aksiyonu iki sütunlu kartlar, ikincil işlemler gruplanmış satırlar
olarak sunulur.

**Neden:** Koyu ilk açılış ve yoğun, küçültülmüş menü özellikle küçük ekranda
okunabilirliği ve görev bulmayı zayıflatıyordu. Aydınlık başlangıç daha nötr
bir ilk izlenim verir; kaydırmalı bölüm yapısı ise dokunma alanlarını küçültmeden
bilgi yoğunluğunu yönetir.

**Trade-off:** Menü ilk ekranda bütün işlemleri aynı anda göstermez; alt
bölümler için kaydırma gerekir. Buna karşılık temel yolculuk özeti ve dört sık
aksiyon ilk görünümde kalır, diğer işlemler anlamlı gruplarla bulunabilir olur.

---

## 2026-08-03 — POI keşfinde gerektiğinde AI, rota hesabında yerel motor

**Karar:** Kullanıcı izin verdiyse ve katalog yetersiz/eski ya da özel ilgi
boşluğu varsa AI gezi başına en çok bir batch ile Japonya POI adaylarını
zenginleştirebilir. Sonuç şehir+tercih+katalog sürümü+dil anahtarıyla cache'lenir.
AI gün ataması, ulaşım modu veya sıra kararı vermez; bunlar saf Dart assignment,
optimizer ve validator hattında kalır.

**Neden:** Hiç AI kullanmamak kişiselleştirilmiş/güncel nokta keşfini zayıflatır;
her rota denemesinde AI kullanmak ise maliyeti, gecikmeyi ve determinizm riskini
artırır. Tek keşif batch'i ile yerel optimizasyon bu iki hedefi ayırır.

---

## 2026-08-03 — Cross-day assignment, priority-aware dropping ve açık maliyet birimleri

**Karar:** Günlük optimizer'dan önce `TripActivityAssignmentEngine` bütün şehir
günlerini birlikte çözer. Must-do/fixed düşürülemez; diğer dropping sonuçları
priority ve gerekçeyle yapılandırılır. Legler transit wait/schedule idle/free
time ayrımını ve `costPerPersonYen`, `partyTotalCostYen`, `vehicleCount`,
`fareBasis` alanlarını taşır. Varsayılan beam width 6'dır.

**Ölçüm:** Seed 20260803 product suite, 100 base × 4 profile: hard ihlal 0,
duplicate 0, must-do drop 0, return eksik 0, dropping %3 altı. Beam 10 kaliteyi
bir miktar artırsa da yaklaşık %17 yavaş olduğundan 6 korunmuştur.
